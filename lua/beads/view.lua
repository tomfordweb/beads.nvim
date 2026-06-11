-- Floating detail view for a single issue: render, mutate (status/priority/
-- close/reopen), navigate dependencies in place with history.

local cli = require("beads.cli")
local config = require("beads.config")
local float = require("beads.float")
local issues = require("beads.issues")
local render = require("beads.render")
local sidebar = require("beads.sidebar")
local util = require("beads.util")

local M = {}

-- One reusable float. history holds previously viewed ids for <BS>;
-- on_close (when set by the caller, e.g. the picker) runs after the float
-- closes so the user lands back where they came from. sidebar_visible
-- persists across dep jumps within one view session.
local state =
  { win = nil, buf = nil, issue = nil, history = {}, on_close = nil, sidebar_visible = nil }

local function reset_state()
  local cb = state.on_close
  state.win = nil
  state.buf = nil
  state.issue = nil
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
  local view_w = float.dims("view").width or 96
  local side_cfg = config.get().sidebar
  if not state.sidebar_visible then
    return float.center(view_w, count + 1), nil
  end
  local gap = 2 -- the two floats' facing borders
  local pair = float.center(view_w + (side_cfg.width or 34) + gap, count + 1)
  local side_w = math.min(side_cfg.width or 34, math.max(10, pair.width - 40))
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

local function set_content(issue, comments, children)
  state.issue = issue
  local lines, hls = render.detail_lines(issue, comments, children)

  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false
  vim.bo[state.buf].filetype = "markdown"
  float.apply_highlights(state.buf, "beads_view", hls)

  if is_open() then
    vim.api.nvim_win_set_config(
      state.win,
      float.decorate(win_geometry(), { title = " " .. issue.id .. " ", pane = "view" })
    )
  end
  update_sidebar(issue)
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

local sidebar_callbacks = {
  jump = jump_to,
  focus_view = function()
    if is_open() then
      vim.api.nvim_set_current_win(state.win)
    end
  end,
  back = history_back,
  quit = close_win,
}

-- Fetch dependents and (re)render the sidebar for the shown issue.
update_sidebar = function(issue, focus)
  if not state.sidebar_visible then
    return
  end
  cli.run_json({ "dep", "list", issue.id, "--direction=up" }, function(ok, dependents)
    if not is_open() or not state.issue or state.issue.id ~= issue.id then
      return
    end
    local links = issues.partition_links(issue, ok and dependents or {})
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
      float.decorate(win_geometry(), { title = " " .. state.issue.id .. " ", pane = "view" })
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

-- Handlers for the configurable view mappings (config.mappings.view).
local handlers = {
  quit = { desc = "close", fn = close_win },
  edit = {
    desc = "edit description",
    fn = function()
      if state.issue then
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
  local mappings = config.get().mappings.view or {}
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
end

local function ensure_float(id)
  if is_open() then
    return
  end
  if state.sidebar_visible == nil then
    state.sidebar_visible = config.get().sidebar.enabled
  end
  state.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.buf].buftype = "nofile"
  vim.bo[state.buf].bufhidden = "wipe"

  state.win = vim.api.nvim_open_win(
    state.buf,
    true,
    float.decorate(win_geometry(), {
      title = " " .. id .. " ",
      pane = "view",
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
  cli.run_json({ "show", id }, function(ok, result)
    if not ok or not result or not result[1] then
      if ok then
        vim.notify("bd: issue not found: " .. id, vim.log.levels.WARN)
      end
      return
    end
    local issue = issues.normalize(result[1])
    cli.run_json({ "comments", id }, function(cok, comments)
      with_children(issue, function(children)
        ensure_float(id)
        if opts and opts.on_close then
          state.on_close = opts.on_close
        end
        set_content(issue, cok and comments or nil, children)
      end)
    end)
  end)
end

--- Refetch and re-render the currently shown issue (no-op when closed).
function M.refresh()
  if not is_open() or not state.issue then
    return
  end
  local id = state.issue.id
  cli.run_json({ "show", id }, function(ok, result)
    if not (ok and result and result[1] and is_open()) then
      return
    end
    local issue = issues.normalize(result[1])
    cli.run_json({ "comments", id }, function(cok, comments)
      with_children(issue, function(children)
        if is_open() then
          set_content(issue, cok and comments or nil, children)
        end
      end)
    end)
  end)
end

M.close = close_win

return M
