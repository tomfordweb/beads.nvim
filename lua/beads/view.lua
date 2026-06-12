-- Floating detail view for a single issue: render, mutate (status/priority/
-- close/reopen), navigate dependencies in place with history.
--
-- Two shapes (config.view.editable_description):
--  * true (default): the main float IS the issue description as a real,
--    always-editable buffer (full nvim editing; :w saves, :q closes). All
--    issue actions live in the sidebar — as selectable rows and as single-key
--    shortcuts while the sidebar is focused.
--  * false (legacy): a read-only rendered detail buffer with single-key
--    action mappings and the `e` inline-edit submode.

local cli = require("beads.cli")
local config = require("beads.config")
local float = require("beads.float")
local inline_edit = require("beads.inline_edit")
local issues = require("beads.issues")
local render = require("beads.render")
local sidebar = require("beads.sidebar")
local util = require("beads.util")

local M = {}

-- One reusable float. history holds previously viewed ids for <BS>;
-- on_close (when set by the caller, e.g. the picker) runs after the float
-- closes so the user lands back where they came from. sidebar_visible
-- persists across dep jumps within one view session.
local state = {
  win = nil,
  buf = nil,
  issue = nil,
  comments = nil,
  children = nil,
  history = {},
  on_close = nil,
  sidebar_visible = nil,
}

-- True when the main float is the always-editable description buffer.
local function editable()
  return config.get().view.editable_description
end

local function reset_state()
  inline_edit.abort() -- the float is gone; flush + drop editor bookkeeping
  local cb = state.on_close
  state.win = nil
  state.buf = nil
  state.issue = nil
  state.comments = nil
  state.children = nil
  state.history = {}
  state.on_close = nil
  state.sidebar_visible = nil
  sidebar.close()
  if cb then
    vim.schedule(cb)
  end
end

local function close_win()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    -- WinClosed autocmd runs reset_state (and the on_close resume)
    vim.api.nvim_win_close(state.win, true)
  else
    reset_state()
  end
end

local function is_open()
  return state.win ~= nil and vim.api.nvim_win_is_valid(state.win)
end

-- Geometry for the view float and (when visible) the sidebar beside it,
-- centered together as one unit. Returns main, sidebar (sidebar nil when
-- hidden). Shrinks the sidebar first on narrow screens.
local function layout()
  local count = state.buf
      and vim.api.nvim_buf_is_valid(state.buf)
      and vim.api.nvim_buf_line_count(state.buf)
    or 24
  -- width/height resolve config percentages (e.g. 0.8) or absolutes; the
  -- height fallback is content-sized so an unconfigured view hugs its content.
  local view_w = float.width("view", 96)
  local view_h = float.height("view", count + 1)
  local side_cfg = config.get().sidebar
  local side_pref = float.resolve_dim(side_cfg.width, vim.o.columns) or 34
  if not state.sidebar_visible then
    return float.center(view_w, view_h), nil
  end
  local gap = 2 -- the two floats' facing borders
  local pair = float.center(view_w + side_pref + gap, view_h)
  local side_w = math.min(side_pref, math.max(10, pair.width - 40))
  local main_w = pair.width - side_w - gap
  local main = { relative = "editor", row = pair.row, height = pair.height, width = main_w }
  local sb = { relative = "editor", row = pair.row, height = pair.height, width = side_w }
  if side_cfg.position == "left" then
    sb.col = pair.col
    main.col = pair.col + side_w + gap
  else
    main.col = pair.col
    sb.col = pair.col + main_w + gap
  end
  return main, sb
end

-- Main-float geometry; repositions (or closes) the sidebar as a side effect
-- so set_content and the VimResized recompute keep the pair in sync.
local function win_geometry()
  local main, sb = layout()
  if sb then
    sidebar.reposition(sb)
  elseif sidebar.is_open() then
    sidebar.close()
  end
  return main
end

local update_sidebar -- defined below; needs the jump/back helpers
local close_win_saved -- defined below; save-then-close for the editable buffer

-- Helpbar pane + float title for the main window.
local function main_pane()
  return editable() and "view_editable" or "view"
end

local function main_title(issue)
  if not editable() then
    return " " .. issue.id .. " "
  end
  local title = issue.title or ""
  if vim.fn.strchars(title) > 48 then
    title = vim.fn.strcharpart(title, 0, 47) .. "…"
  end
  return (" %s — %s "):format(issue.id, title)
end

-- Close path for the editable description buffer (:q/:wq/ZZ and the sidebar's
-- quit): make sure the body is persisted before the float (and with it the
-- buffer) goes away. Already-saved/discarded paths fall straight through.
close_win_saved = function()
  if editable() and inline_edit.is_active() then
    inline_edit.save(function()
      close_win()
    end)
  else
    close_win()
  end
end

local function set_content(issue, comments, children)
  state.issue = issue
  state.comments = comments
  state.children = children

  -- filetype before content so treesitter/syntax parses from the first render;
  -- set only when it changes since set_content re-runs on every refresh (M6).
  if vim.bo[state.buf].filetype ~= "markdown" then
    vim.bo[state.buf].filetype = "markdown"
  end

  if editable() then
    -- the main buffer is the live description editor: attach once, then
    -- re-target on navigation; never clobber unsaved same-issue edits
    if not inline_edit.is_active() then
      inline_edit.attach(state.buf, issue, { on_quit = close_win_saved })
    elseif inline_edit.current_id() ~= issue.id or not vim.bo[state.buf].modified then
      inline_edit.set_issue(issue)
    end
    -- (same issue + unsaved edits: leave the buffer alone; the sidebar
    -- below still picks up the refreshed metadata)
  else
    local lines, hls = render.detail_lines(issue, comments, children)
    vim.bo[state.buf].modifiable = true
    vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
    vim.bo[state.buf].modifiable = false
    float.apply_highlights(state.buf, "beads_view", hls)
  end

  if is_open() then
    vim.api.nvim_win_set_config(
      state.win,
      float.decorate(win_geometry(), { title = main_title(issue), pane = main_pane() })
    )
  end
  update_sidebar(issue)
end

-- Run each fn(done) concurrently; cb fires once after every fn called done.
-- Lets the independent bd fetches behind a render overlap instead of
-- queueing serially (open latency = slowest call, not the sum).
local function join(fns, cb)
  local pending = #fns
  if pending == 0 then
    cb()
    return
  end
  for _, fn in ipairs(fns) do
    fn(function()
      pending = pending - 1
      if pending == 0 then
        cb()
      end
    end)
  end
end

-- Epics show a Children section in the body; non-epics skip the extra call.
local function with_children(issue, cb)
  if issue.issue_type ~= "epic" then
    cb(nil)
    return
  end
  cli.run_json({ "children", issue.id }, function(ok, raw)
    if not ok or type(raw) ~= "table" then
      cb(nil)
      return
    end
    local out = {}
    for _, c in ipairs(raw) do
      table.insert(out, issues.normalize(c))
    end
    cb(out)
  end)
end

local function update_and_rerender(args, msg, action)
  local id = state.issue and state.issue.id
  if not id then
    return
  end
  cli.run_plain(args, function(ok)
    if not ok then
      return
    end
    if msg then
      util.info("bd: " .. msg)
    end
    util.emit("BeadsIssueUpdated", { id = id, action = action or args[1] })
    M.refresh()
  end)
end

local function jump_to(id)
  if not id or (state.issue and id == state.issue.id) then
    return
  end
  if state.issue then
    table.insert(state.history, state.issue.id)
  end
  M.open(id)
end

local function dep_jump()
  jump_to(issues.match_issue_id(vim.fn.expand("<cWORD>")))
end

local function history_back()
  local prev = table.remove(state.history)
  if prev then
    M.open(prev)
  else
    -- nothing left to pop: back out of the view entirely (resumes the
    -- picker when the view was opened from it)
    close_win()
  end
end

local handlers -- defined below; the sidebar action callback dispatches into it

local sidebar_callbacks = {
  jump = jump_to,
  action = function(name)
    local h = handlers and handlers[name]
    if h then
      h.fn()
    end
  end,
  focus_view = function()
    if is_open() then
      vim.api.nvim_set_current_win(state.win)
    end
  end,
  back = history_back,
  quit = function()
    close_win_saved()
  end,
}

-- Fetch dependents (+ a recent-history summary when that section is enabled)
-- and (re)render the sidebar for the shown issue.
update_sidebar = function(issue, focus)
  if not state.sidebar_visible then
    return
  end
  local sidebar_cfg = config.get().sidebar

  local dependents, history_rows
  local fetches = {
    function(done)
      cli.run_json({ "dep", "list", issue.id, "--direction=up" }, function(ok, deps)
        dependents = ok and deps or nil
        done()
      end)
    end,
  }
  -- Surface the last-N change rows inline (M3); skip the extra bd call when
  -- the section is disabled.
  if vim.tbl_contains(sidebar_cfg.sections or {}, "history") then
    table.insert(fetches, function(done)
      cli.run_json({ "history", issue.id }, function(hok, entries)
        if hok and type(entries) == "table" then
          history_rows = require("beads.history").recent(entries, sidebar_cfg.history_limit or 3)
        end
        done()
      end)
    end)
  end

  join(fetches, function()
    if not is_open() or not state.issue or state.issue.id ~= issue.id then
      return
    end
    local links = issues.partition_links(issue, dependents or {})
    -- comments render in the sidebar; epics get their richer `bd children`
    -- rows (fetched for the body in legacy mode) over dependency-derived ones
    links.comments = state.comments
    if state.children and #state.children > 0 then
      links.children = state.children
    end
    links.history = history_rows
    local _, sb = layout()
    if sb then
      sidebar.open(issue, links, sb, sidebar_callbacks)
      if focus then
        sidebar.focus()
      end
    end
  end)
end

local function reapply_main_geometry()
  if is_open() and state.issue then
    vim.api.nvim_win_set_config(
      state.win,
      float.decorate(win_geometry(), { title = main_title(state.issue), pane = main_pane() })
    )
  end
end

local function show_sidebar(focus)
  state.sidebar_visible = true
  reapply_main_geometry()
  if state.issue then
    update_sidebar(state.issue, focus)
  end
end

local function hide_sidebar()
  state.sidebar_visible = false
  sidebar.close()
  reapply_main_geometry()
end

-- Enter the in-place description editor inside this float (M4). The submode
-- swaps an editable buffer into state.win and restores the detail view on exit
-- (re-rendering so a saved description shows immediately).
local function enter_inline_edit()
  if not (is_open() and state.issue) then
    return
  end
  inline_edit.enter({
    win = state.win,
    view_buf = state.buf,
    issue = state.issue,
    reconfigure = function(opts)
      if is_open() then
        vim.api.nvim_win_set_config(state.win, float.decorate(win_geometry(), opts))
      end
    end,
    on_exit = function()
      M.refresh()
    end,
  })
end

-- Handlers for the configurable view mappings (config.mappings.view); in
-- editable-description mode these run from the sidebar instead (action rows
-- + focused single-key shortcuts), dispatched via sidebar_callbacks.action.
handlers = {
  quit = { desc = "close", fn = close_win },
  edit = {
    desc = "edit description",
    fn = function()
      if not state.issue then
        return
      end
      if config.get().edit.inline then
        enter_inline_edit()
      else
        require("beads.edit").open_description(state.issue)
      end
    end,
  },
  status = {
    desc = "set status",
    fn = function()
      if not state.issue then
        return
      end
      vim.ui.select(
        issues.statuses(),
        { prompt = "Status for " .. state.issue.id },
        function(choice)
          if choice then
            update_and_rerender(
              { "update", state.issue.id, "-s", choice },
              state.issue.id .. " → " .. choice,
              "status"
            )
          end
        end
      )
    end,
  },
  priority = {
    desc = "set priority",
    fn = function()
      if not state.issue then
        return
      end
      local labels = { "P0 critical", "P1 high", "P2 normal", "P3 low", "P4 backlog" }
      vim.ui.select(labels, { prompt = "Priority for " .. state.issue.id }, function(choice, idx)
        if choice then
          update_and_rerender(
            { "update", state.issue.id, "-p", tostring(idx - 1) },
            state.issue.id .. " → P" .. (idx - 1),
            "priority"
          )
        end
      end)
    end,
  },
  assign = {
    desc = "assign issue",
    fn = function()
      if not state.issue then
        return
      end
      local id = state.issue.id
      vim.ui.input({
        prompt = "Assignee for " .. id .. " (empty = unassign): ",
        default = state.issue.assignee or "",
      }, function(name)
        if name == nil then
          return
        end
        name = vim.trim(name)
        local msg = name == "" and ("unassigned " .. id) or (id .. " → " .. name)
        update_and_rerender({ "assign", id, name }, msg, "assign")
      end)
    end,
  },
  defer = {
    desc = "defer / undefer",
    fn = function()
      if not state.issue then
        return
      end
      local id = state.issue.id
      if state.issue.status == "deferred" then
        update_and_rerender({ "undefer", id }, "undeferred " .. id, "undefer")
        return
      end
      vim.ui.input({ prompt = "Defer " .. id .. " until (empty = no date): " }, function(expr)
        if expr == nil then
          return
        end
        expr = vim.trim(expr)
        local args = { "defer", id }
        if expr ~= "" then
          table.insert(args, "--until=" .. expr)
        end
        local msg = expr == "" and ("deferred " .. id) or ("deferred " .. id .. " until " .. expr)
        update_and_rerender(args, msg, "defer")
      end)
    end,
  },
  close = {
    desc = "close issue",
    fn = function()
      if state.issue then
        update_and_rerender({ "close", state.issue.id }, "closed " .. state.issue.id, "close")
      end
    end,
  },
  reopen = {
    desc = "reopen issue",
    fn = function()
      if state.issue then
        update_and_rerender({ "reopen", state.issue.id }, "reopened " .. state.issue.id, "reopen")
      end
    end,
  },
  comment = {
    desc = "add comment",
    fn = function()
      if not state.issue then
        return
      end
      local id = state.issue.id
      vim.ui.input({ prompt = "Comment on " .. id .. ": " }, function(text)
        if not text or vim.trim(text) == "" then
          return
        end
        cli.run_stdin({ "comment", id, "--stdin" }, text, function(ok)
          if ok then
            util.info("bd: commented on " .. id)
            util.emit("BeadsIssueUpdated", { id = id, action = "comment" })
            M.refresh()
          end
        end)
      end)
    end,
  },
  labels = {
    desc = "manage labels",
    fn = function()
      if not state.issue then
        return
      end
      local id = state.issue.id
      local current = state.issue.labels or {}
      -- existing labels (across the db) offered as quick-add choices, current
      -- labels offered for removal, plus a free-text "new label" escape hatch
      cli.run_json({ "label", "list-all" }, function(ok, all)
        local items, dispatch = {}, {}
        for _, l in ipairs(current) do
          table.insert(items, "− " .. l)
          table.insert(dispatch, { op = "remove", label = l })
        end
        if ok and type(all) == "table" then
          for _, entry in ipairs(all) do
            local name = type(entry) == "table" and entry.label or entry
            if type(name) == "string" and not vim.tbl_contains(current, name) then
              table.insert(items, "+ " .. name)
              table.insert(dispatch, { op = "add", label = name })
            end
          end
        end
        table.insert(items, "✚ new label…")
        table.insert(dispatch, { op = "new" })
        vim.ui.select(items, { prompt = "Labels for " .. id }, function(_, idx)
          local action = idx and dispatch[idx]
          if not action then
            return
          end
          if action.op == "new" then
            vim.ui.input({ prompt = "New label: " }, function(input)
              local name = input and vim.trim(input)
              if not name or name == "" then
                return
              end
              update_and_rerender(
                { "label", "add", id, name },
                "labeled " .. id .. " #" .. name,
                "label"
              )
            end)
          elseif action.op == "add" then
            update_and_rerender(
              { "label", "add", id, action.label },
              "labeled " .. id .. " #" .. action.label,
              "label"
            )
          else
            update_and_rerender(
              { "label", "remove", id, action.label },
              "unlabeled " .. id .. " #" .. action.label,
              "label"
            )
          end
        end)
      end)
    end,
  },
  graph = {
    desc = "dependency graph",
    fn = function()
      if state.issue then
        require("beads.graphview").open(state.issue.id)
      end
    end,
  },
  history = {
    desc = "change history",
    fn = function()
      if state.issue then
        require("beads.history").open(state.issue.id)
      end
    end,
  },
  jump = { desc = "jump to dependency", fn = dep_jump },
  back = { desc = "back", fn = history_back },
  sidebar = {
    desc = "focus links sidebar",
    fn = function()
      if sidebar.is_open() then
        sidebar.focus()
      else
        show_sidebar(true)
      end
    end,
  },
  sidebar_toggle = {
    desc = "toggle links sidebar",
    fn = function()
      if state.sidebar_visible then
        hide_sidebar()
      else
        show_sidebar(false)
      end
    end,
  },
  refresh = {
    desc = "refresh",
    fn = function()
      M.refresh()
    end,
  },
}

local function setup_keymaps(buf)
  local actions = require("beads.actions")
  local mappings = config.get().mappings.view or {}
  if editable() then
    -- the description buffer is a real editor: every key keeps its native
    -- vim meaning (q records macros, a/c/o/s edit text, …). Only navigation
    -- to the sidebar/history is mapped; actions live on the sidebar buffer,
    -- and quitting goes through :q/:wq/ZZ (intercepted by inline_edit).
    local nav = {
      sidebar = handlers.sidebar,
      sidebar_toggle = handlers.sidebar_toggle,
      back = handlers.back,
    }
    for action, handler in pairs(nav) do
      for _, lhs in ipairs(config.lhs(mappings[action])) do
        vim.keymap.set(
          "n",
          lhs,
          handler.fn,
          { buffer = buf, silent = true, nowait = true, desc = "Beads: " .. handler.desc }
        )
      end
    end
    return
  end
  for action, handler in pairs(handlers) do
    for _, lhs in ipairs(config.lhs(mappings[action])) do
      vim.keymap.set(
        "n",
        lhs,
        handler.fn,
        { buffer = buf, silent = true, nowait = true, desc = "Beads: " .. handler.desc }
      )
    end
  end
  -- User-defined custom actions: any non-builtin name whose value is a
  -- { key, fn, desc } spec. Builtins win on name collision.
  for action, value in pairs(mappings) do
    if not handlers[action] and actions.is_custom_spec(value) then
      local fn, desc = actions.resolve(value)
      for _, lhs in ipairs(config.lhs(value.key)) do
        vim.keymap.set("n", lhs, function()
          local ok, err = pcall(fn, state.issue)
          if not ok then
            vim.notify(
              "beads: custom action '" .. action .. "' error: " .. tostring(err),
              vim.log.levels.WARN
            )
          end
        end, {
          buffer = buf,
          silent = true,
          nowait = true,
          desc = "Beads: " .. (desc or action),
        })
      end
    end
  end
end

local function ensure_float(id)
  if is_open() then
    return
  end
  if state.sidebar_visible == nil then
    state.sidebar_visible = config.get().sidebar.enabled
  end
  if editable() then
    -- the editable description buffer; inline_edit.attach (in set_content)
    -- wires saving, autosave, undo, and the :w/:q intercepts onto it
    state.buf = vim.api.nvim_create_buf(false, false)
    pcall(vim.api.nvim_buf_set_name, state.buf, ("beads://%s/description"):format(id))
    vim.bo[state.buf].buftype = "acwrite"
    vim.bo[state.buf].bufhidden = "wipe"
    vim.bo[state.buf].swapfile = false
  else
    state.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[state.buf].buftype = "nofile"
    vim.bo[state.buf].bufhidden = "wipe"
  end

  state.win = vim.api.nvim_open_win(
    state.buf,
    true,
    float.decorate(win_geometry(), {
      title = " " .. id .. " ",
      pane = main_pane(),
      style = "minimal",
    })
  )
  vim.wo[state.win].wrap = true
  vim.wo[state.win].conceallevel = 2

  float.auto_resize(state.win, win_geometry)
  setup_keymaps(state.buf)

  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(state.win),
    once = true,
    callback = reset_state,
  })
end

--- Open (or re-render) the detail float for an issue id.
---@param id string
---@param opts { on_close: fun()|nil }|nil on_close runs after the float closes
function M.open(id, opts)
  render.define_highlights()
  issues.prefetch() -- warm statuses/types for the status action's vim.ui.select
  cli.run_json({ "show", id }, function(ok, result)
    if not ok or not result or not result[1] then
      if ok then
        vim.notify("bd: issue not found: " .. id, vim.log.levels.WARN)
      end
      return
    end
    local issue = issues.normalize(result[1])
    local comments, children
    join({
      function(done)
        cli.run_json({ "comments", id }, function(cok, c)
          comments = cok and c or nil
          done()
        end)
      end,
      function(done)
        with_children(issue, function(ch)
          children = ch
          done()
        end)
      end,
    }, function()
      ensure_float(id)
      if opts and opts.on_close then
        state.on_close = opts.on_close
      end
      set_content(issue, comments, children)
      -- Lifecycle hook: fire once on the initial open of an id (M.refresh
      -- re-renders never reach here). pcall so a user error can't break the
      -- view; surface it as a warning instead.
      local on_open = config.get().hooks and config.get().hooks.on_open
      if on_open then
        local hook_ok, err = pcall(on_open, issue)
        if not hook_ok then
          vim.notify("beads: hooks.on_open error: " .. tostring(err), vim.log.levels.WARN)
        end
      end
    end)
  end)
end

--- Refetch and re-render the currently shown issue. No-op when closed, or —
--- legacy mode only — while the inline-edit submode owns the window. In
--- editable mode set_content refreshes the sidebar always and reloads the
--- description buffer only when it has no unsaved edits.
function M.refresh()
  if not is_open() or not state.issue then
    return
  end
  if not editable() and inline_edit.is_active() then
    return
  end
  local id = state.issue.id
  cli.run_json({ "show", id }, function(ok, result)
    if not (ok and result and result[1] and is_open()) then
      return
    end
    local issue = issues.normalize(result[1])
    local comments, children
    join({
      function(done)
        cli.run_json({ "comments", id }, function(cok, c)
          comments = cok and c or nil
          done()
        end)
      end,
      function(done)
        with_children(issue, function(ch)
          children = ch
          done()
        end)
      end,
    }, function()
      if is_open() then
        set_content(issue, comments, children)
      end
    end)
  end)
end

-- Public close: persists unsaved description edits first in editable mode.
M.close = function()
  close_win_saved()
end

return M
