-- Floating detail view for a single issue: render, mutate (status/priority/
-- close/reopen), navigate dependencies in place with history.

local cli = require("beads.cli")
local config = require("beads.config")
local float = require("beads.float")
local issues = require("beads.issues")
local render = require("beads.render")
local util = require("beads.util")

local M = {}

-- One reusable float. history holds previously viewed ids for <BS>;
-- on_close (when set by the caller, e.g. the picker) runs after the float
-- closes so the user lands back where they came from.
local state = { win = nil, buf = nil, issue = nil, history = {}, on_close = nil }

local function reset_state()
  local cb = state.on_close
  state.win = nil
  state.buf = nil
  state.issue = nil
  state.history = {}
  state.on_close = nil
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

local function apply_highlights(buf, hls)
  local ns = vim.api.nvim_create_namespace("beads_view")
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, h in ipairs(hls) do
    vim.api.nvim_buf_set_extmark(buf, ns, h.lnum, h.col_start, {
      end_row = h.col_end == -1 and h.lnum + 1 or h.lnum,
      end_col = h.col_end == -1 and 0 or h.col_end,
      hl_group = h.hl_group,
      hl_eol = h.col_end == -1,
    })
  end
end

-- Content-sized centered geometry for the current buffer.
local function win_geometry()
  local count = state.buf and vim.api.nvim_buf_is_valid(state.buf) and vim.api.nvim_buf_line_count(state.buf) or 24
  return float.center(float.dims("view").width or 96, count + 1)
end

local function set_content(issue, comments)
  state.issue = issue
  local lines, hls = render.detail_lines(issue, comments)

  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false
  vim.bo[state.buf].filetype = "markdown"
  apply_highlights(state.buf, hls)

  if is_open() then
    vim.api.nvim_win_set_config(
      state.win,
      float.decorate(win_geometry(), { title = " " .. issue.id .. " ", pane = "view" })
    )
  end
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

local function dep_jump()
  local id = issues.match_issue_id(vim.fn.expand("<cWORD>"))
  if not id or (state.issue and id == state.issue.id) then
    return
  end
  if state.issue then
    table.insert(state.history, state.issue.id)
  end
  M.open(id)
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
      vim.ui.select(issues.statuses(), { prompt = "Status for " .. state.issue.id }, function(choice)
        if choice then
          update_and_rerender({ "update", state.issue.id, "-s", choice }, state.issue.id .. " → " .. choice, "status")
        end
      end)
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
      vim.keymap.set("n", lhs, handler.fn, { buffer = buf, silent = true, nowait = true, desc = "Beads: " .. handler.desc })
    end
  end
end

local function ensure_float(id)
  if is_open() then
    return
  end
  state.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.buf].buftype = "nofile"
  vim.bo[state.buf].bufhidden = "wipe"

  state.win = vim.api.nvim_open_win(
    state.buf,
    true,
    float.decorate(float.center(float.dims("view").width or 96, 24), {
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
      ensure_float(id)
      if opts and opts.on_close then
        state.on_close = opts.on_close
      end
      set_content(issue, cok and comments or nil)
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
      if is_open() then
        set_content(issue, cok and comments or nil)
      end
    end)
  end)
end

M.close = close_win

return M
