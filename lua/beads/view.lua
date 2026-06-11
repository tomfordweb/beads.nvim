-- Floating detail view for a single issue: render, mutate (status/priority/
-- close/reopen), navigate dependencies in place with history.

local cli = require("beads.cli")
local issues = require("beads.issues")
local render = require("beads.render")

local M = {}

-- One reusable float. history holds previously viewed ids for <BS>.
local state = { win = nil, buf = nil, issue = nil, history = {} }

local function close_win()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win = nil
  state.buf = nil
  state.issue = nil
  state.history = {}
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

local function set_content(issue)
  state.issue = issue
  local lines, hls = render.detail_lines(issue)

  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false
  vim.bo[state.buf].filetype = "markdown"
  apply_highlights(state.buf, hls)

  if is_open() then
    local height = math.min(#lines + 1, vim.o.lines - 6)
    vim.api.nvim_win_set_config(state.win, {
      title = " " .. issue.id .. " ",
      title_pos = "center",
      height = height,
    })
  end
end

local function update_and_rerender(args, msg)
  local id = state.issue and state.issue.id
  if not id then
    return
  end
  cli.run_plain(args, function(ok)
    if not ok then
      return
    end
    if msg then
      vim.notify("bd: " .. msg, vim.log.levels.INFO)
    end
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
  end
end

local function setup_keymaps(buf)
  local function bmap(lhs, rhs, desc)
    vim.keymap.set("n", lhs, rhs, { buffer = buf, silent = true, nowait = true, desc = "Beads: " .. desc })
  end

  bmap("q", close_win, "close")
  bmap("<Esc>", close_win, "close")

  bmap("e", function()
    if state.issue then
      require("beads.edit").open_description(state.issue)
    end
  end, "edit description")

  bmap("s", function()
    if not state.issue then
      return
    end
    vim.ui.select(issues.STATUSES, { prompt = "Status for " .. state.issue.id }, function(choice)
      if choice then
        update_and_rerender({ "update", state.issue.id, "-s", choice }, state.issue.id .. " → " .. choice)
      end
    end)
  end, "set status")

  bmap("p", function()
    if not state.issue then
      return
    end
    local labels = { "P0 critical", "P1 high", "P2 normal", "P3 low", "P4 backlog" }
    vim.ui.select(labels, { prompt = "Priority for " .. state.issue.id }, function(choice, idx)
      if choice then
        update_and_rerender({ "update", state.issue.id, "-p", tostring(idx - 1) }, state.issue.id .. " → P" .. (idx - 1))
      end
    end)
  end, "set priority")

  bmap("c", function()
    if state.issue then
      update_and_rerender({ "close", state.issue.id }, "closed " .. state.issue.id)
    end
  end, "close issue")

  bmap("o", function()
    if state.issue then
      update_and_rerender({ "reopen", state.issue.id }, "reopened " .. state.issue.id)
    end
  end, "reopen issue")

  bmap("gd", dep_jump, "jump to dependency")
  bmap("<CR>", dep_jump, "jump to dependency")
  bmap("<BS>", history_back, "back")
  bmap("R", M.refresh, "refresh")
end

local function ensure_float(id)
  if is_open() then
    return
  end
  state.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.buf].buftype = "nofile"
  vim.bo[state.buf].bufhidden = "wipe"

  local width = math.min(96, vim.o.columns - 8)
  local height = math.min(24, vim.o.lines - 6)
  state.win = vim.api.nvim_open_win(state.buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2) - 1,
    col = math.floor((vim.o.columns - width) / 2),
    border = "rounded",
    title = " " .. id .. " ",
    title_pos = "center",
    style = "minimal",
  })
  vim.wo[state.win].wrap = true
  vim.wo[state.win].conceallevel = 2

  setup_keymaps(state.buf)

  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(state.win),
    once = true,
    callback = function()
      state.win = nil
      state.buf = nil
      state.issue = nil
      state.history = {}
    end,
  })
end

--- Open (or re-render) the detail float for an issue id.
---@param id string
function M.open(id)
  render.define_highlights()
  cli.run_json({ "show", id }, function(ok, result)
    if not ok or not result or not result[1] then
      if ok then
        vim.notify("bd: issue not found: " .. id, vim.log.levels.WARN)
      end
      return
    end
    ensure_float(id)
    set_content(issues.normalize(result[1]))
  end)
end

--- Refetch and re-render the currently shown issue (no-op when closed).
function M.refresh()
  if not is_open() or not state.issue then
    return
  end
  local id = state.issue.id
  cli.run_json({ "show", id }, function(ok, result)
    if ok and result and result[1] and is_open() then
      set_content(issues.normalize(result[1]))
    end
  end)
end

M.close = close_win

return M
