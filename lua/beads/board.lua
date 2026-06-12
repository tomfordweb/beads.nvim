-- Kanban board (F2): every issue grouped into status columns, one float per
-- column. h/l move between columns, j/k within (native), <CR>/gd opens the
-- detail view, s moves a card to another status. Reuses render.board_* for the
-- pure column rendering and float.columns for the multi-window geometry.

local cli = require("beads.cli")
local config = require("beads.config")
local float = require("beads.float")
local issues = require("beads.issues")
local render = require("beads.render")
local util = require("beads.util")

local M = {}

-- One board session: ordered column windows/buffers, their per-line id maps,
-- the active status subset, and the current column inner width.
local state = { wins = {}, bufs = {}, rows = {}, statuses = {}, col_width = 24 }
local closing = false

local function is_open()
  for _, win in ipairs(state.wins) do
    if vim.api.nvim_win_is_valid(win) then
      return true
    end
  end
  return false
end

-- Close every column window. Guarded so the per-window WinClosed autocmd
-- (which calls back here to tear the board down as a unit) can't recurse.
local function close()
  if closing then
    return
  end
  closing = true
  local wins = state.wins
  state.wins, state.bufs, state.rows = {}, {}, {}
  for _, win in ipairs(wins) do
    if vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
  closing = false
end

-- Index of the focused column, or nil when focus is elsewhere.
local function current_index()
  local cur = vim.api.nvim_get_current_win()
  for i, win in ipairs(state.wins) do
    if win == cur then
      return i
    end
  end
end

-- Move focus to the column `delta` away (clamped — no wraparound).
local function focus_col(delta)
  local i = current_index()
  if not i then
    return
  end
  local target = state.wins[i + delta]
  if target and vim.api.nvim_win_is_valid(target) then
    vim.api.nvim_set_current_win(target)
  end
end

-- Issue id under the cursor in the focused column, or nil on a blank/header row.
local function cursor_id()
  local i = current_index()
  if not i then
    return nil
  end
  local lnum = vim.api.nvim_win_get_cursor(state.wins[i])[1]
  return state.rows[i] and state.rows[i][lnum]
end

-- Column geometries from float.columns, sized by the optional float.board
-- config (width/height as % / fraction / absolute, like the other floats).
local function geometries()
  local cfg = config.get().float.board or {}
  return float.columns(#state.statuses, {
    width = float.resolve_dim(cfg.width, vim.o.columns),
    height = float.resolve_dim(cfg.height, vim.o.lines),
  })
end

-- Render the fetched issues into the existing column buffers in place (windows
-- persist across refreshes; only the buffer contents change).
local function render_columns(list)
  local groups = render.board_group(list, state.statuses)
  for i, group in ipairs(groups) do
    local buf = state.bufs[i]
    if buf and vim.api.nvim_buf_is_valid(buf) then
      local lines, hls, rows = render.board_column_lines(group, state.col_width)
      vim.bo[buf].modifiable = true
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      vim.bo[buf].modifiable = false
      float.apply_highlights(buf, "beads_board_" .. i, hls)
      state.rows[i] = rows
    end
  end
end

-- Refetch every issue and re-render the columns. No-op when the board is closed.
function M.refresh()
  if not is_open() then
    return
  end
  cli.run_json({ "list", "--all" }, function(ok, raw)
    if not ok or type(raw) ~= "table" or not is_open() then
      return
    end
    local list = {}
    for _, r in ipairs(raw) do
      table.insert(list, issues.normalize(r))
    end
    render_columns(list)
  end)
end

-- Open the detail view for the carded issue, reopening the board when it closes
-- so the board feels like the home surface the user returns to.
local function open_detail()
  local id = cursor_id()
  if not id then
    return
  end
  close()
  require("beads.view").open(id, {
    on_close = function()
      M.open()
    end,
  })
end

-- Move the carded issue to another status (bd update -s), then refresh so the
-- card jumps to its new column.
local function change_status()
  local id = cursor_id()
  if not id then
    return
  end
  vim.ui.select(issues.statuses(), { prompt = "Move " .. id .. " to" }, function(choice)
    if not choice then
      return
    end
    cli.run_plain({ "update", id, "-s", choice }, function(ok)
      if ok then
        util.info("bd: " .. id .. " → " .. choice)
        util.emit("BeadsIssueUpdated", { id = id, action = "status" })
        M.refresh()
      end
    end)
  end)
end

local function setup_keymaps(buf)
  local m = config.get().mappings.board or {}
  local binds = {
    { m.open, open_detail },
    { m.status, change_status },
    {
      m.left,
      function()
        focus_col(-1)
      end,
    },
    {
      m.right,
      function()
        focus_col(1)
      end,
    },
    { m.refresh, M.refresh },
    { m.quit, close },
  }
  for _, bind in ipairs(binds) do
    for _, lhs in ipairs(config.lhs(bind[1])) do
      vim.keymap.set("n", lhs, bind[2], { buffer = buf, silent = true, nowait = true })
    end
  end
end

-- Create one float per column with its status-named title + board helpbar, and
-- wire resize + close-as-a-unit autocmds.
local function open_windows()
  local geos = geometries()
  state.col_width = geos[1] and geos[1].width or 24
  for i = 1, #state.statuses do
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "wipe"
    local title = (" %s "):format(render.status_title(state.statuses[i]))
    local win = vim.api.nvim_open_win(
      buf,
      i == 1,
      float.decorate(geos[i], { title = title, pane = "board", style = "minimal" })
    )
    vim.wo[win].wrap = false
    vim.wo[win].cursorline = true
    state.bufs[i] = buf
    state.wins[i] = win
    setup_keymaps(buf)
    -- track the column's geometry on resize; col_width stays in sync so a later
    -- refresh re-truncates cards to the new width
    float.auto_resize(win, function()
      local g = geometries()
      state.col_width = g[1] and g[1].width or state.col_width
      return g[i]
    end)
    vim.api.nvim_create_autocmd("WinClosed", {
      pattern = tostring(win),
      once = true,
      callback = function()
        vim.schedule(close)
      end,
    })
  end
end

--- Open (or refresh) the kanban board.
function M.open()
  render.define_highlights()
  issues.prefetch() -- warm statuses for the `s` move-status select
  cli.run_json({ "list", "--all" }, function(ok, raw)
    if not ok or type(raw) ~= "table" then
      return
    end
    local list = {}
    for _, r in ipairs(raw) do
      table.insert(list, issues.normalize(r))
    end
    if is_open() then
      close()
    end
    local board = config.get().board or {}
    state.statuses = board.statuses or { "open", "in_progress", "blocked", "closed" }
    open_windows()
    render_columns(list)
  end)
end

return M
