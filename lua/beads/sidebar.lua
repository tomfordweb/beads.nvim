-- Issue sidebar companion to the detail view: overview, action rows
-- (status/priority/comment/… — run with <CR> or their single keys while the
-- sidebar is focused), parent / children / depends-on / blocks links,
-- comments, and recent history. The view owns the lifecycle (open/refresh/
-- close alongside its own float) and injects navigation + action callbacks so
-- there is no require cycle back into beads.view.

local config = require("beads.config")
local float = require("beads.float")
local issues = require("beads.issues")
local render = require("beads.render")

local M = {}

-- callbacks: { jump = fun(id), action = fun(name), focus_view = fun(),
--              back = fun(), quit = fun() }
local state = { win = nil, buf = nil, callbacks = nil, rows = nil, issue = nil }

-- Builtin issue actions runnable from the sidebar; keys resolve through
-- config.mappings.view so user overrides apply here too.
local ACTION_NAMES = {
  "status",
  "priority",
  "comment",
  "labels",
  "assign",
  "defer",
  "close",
  "reopen",
  "graph",
  "history",
}

function M.is_open()
  return state.win ~= nil and vim.api.nvim_win_is_valid(state.win)
end

function M.close()
  if M.is_open() then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win = nil
  state.buf = nil
  state.rows = nil
  state.issue = nil
end

--- Move the cursor into the sidebar window.
function M.focus()
  if M.is_open() then
    vim.api.nvim_set_current_win(state.win)
  end
end

function M.win()
  return state.win
end

--- Single key per action for the rendered Actions rows (first configured
--- lhs; multi-char keys are shown as-is).
local function action_keys()
  local mappings = config.get().mappings.view or {}
  local keys = {}
  for _, name in ipairs(ACTION_NAMES) do
    keys[name] = config.lhs(mappings[name])[1]
  end
  return keys
end

local function run_action(name)
  if state.callbacks and state.callbacks.action then
    state.callbacks.action(name)
  end
end

-- <CR>/gd on a sidebar row: action rows run their action, link rows open the
-- issue; anywhere else falls back to <cWORD> id matching (e.g. ids inside
-- history rows).
local function dispatch_row()
  local row = state.rows and state.rows[vim.api.nvim_win_get_cursor(state.win)[1]]
  if row and row.kind == "action" then
    run_action(row.name)
    return
  end
  local id = row and row.kind == "link" and row.id
    or issues.match_issue_id(vim.fn.expand("<cWORD>"))
  if id and state.callbacks then
    state.callbacks.jump(id)
  end
end

local function setup_keymaps(buf)
  local actions = require("beads.actions")
  local mappings = config.get().mappings.sidebar or {}
  local handlers = {
    jump = { desc = "run action / open issue under cursor", fn = dispatch_row },
    focus_view = {
      desc = "focus detail view",
      fn = function()
        if state.callbacks then
          state.callbacks.focus_view()
        end
      end,
    },
    back = {
      desc = "back",
      fn = function()
        if state.callbacks then
          state.callbacks.back()
        end
      end,
    },
    quit = {
      desc = "close",
      fn = function()
        if state.callbacks then
          state.callbacks.quit()
        end
      end,
    },
  }
  -- Single-key action shortcuts while the sidebar is focused (s = status,
  -- a = comment, c = close, … — the keys the read-only detail view used to
  -- own). Resolved from mappings.view. Set FIRST so the sidebar navigation
  -- keys below win on any lhs collision.
  local view_mappings = config.get().mappings.view or {}
  for _, name in ipairs(ACTION_NAMES) do
    for _, lhs in ipairs(config.lhs(view_mappings[name])) do
      vim.keymap.set("n", lhs, function()
        run_action(name)
      end, { buffer = buf, silent = true, nowait = true, desc = "Beads: " .. name })
    end
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
  -- User-defined custom actions (non-builtin names in mappings.view holding a
  -- { key, fn, desc } spec) are runnable from the sidebar too.
  for action, value in pairs(view_mappings) do
    if not vim.tbl_contains(ACTION_NAMES, action) and actions.is_custom_spec(value) then
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

local function ensure_win(geometry)
  if M.is_open() then
    vim.api.nvim_win_set_config(
      state.win,
      float.decorate(geometry, { title = " issue ", pane = "sidebar" })
    )
    return
  end
  state.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.buf].buftype = "nofile"
  vim.bo[state.buf].bufhidden = "wipe"

  state.win = vim.api.nvim_open_win(
    state.buf,
    false, -- the detail view keeps focus
    float.decorate(geometry, { title = " issue ", pane = "sidebar", style = "minimal" })
  )
  vim.wo[state.win].wrap = false
  setup_keymaps(state.buf)

  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(state.win),
    once = true,
    callback = function()
      state.win = nil
      state.buf = nil
      state.rows = nil
    end,
  })
end

--- Open or re-render the sidebar.
---@param issue table normalized issue
---@param links table from issues.partition_links (plus comments/history)
---@param geometry table window geometry fragment (from the view's layout)
---@param callbacks { jump: fun(id: string), action: fun(name: string)|nil, focus_view: fun(), back: fun(), quit: fun() }
function M.open(issue, links, geometry, callbacks)
  state.callbacks = callbacks or state.callbacks
  state.issue = issue
  ensure_win(geometry)

  local cfg = config.get().sidebar
  local lines, hls, rows = render.sidebar_lines(
    issue,
    links,
    { sections = cfg.sections, width = cfg.width, action_keys = action_keys() }
  )
  state.rows = rows
  vim.bo[state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  vim.bo[state.buf].modifiable = false
  float.apply_highlights(state.buf, "beads_sidebar", hls)
end

--- Re-apply geometry (resize/recenter); no-op when closed.
---@param geometry table
function M.reposition(geometry)
  if M.is_open() then
    vim.api.nvim_win_set_config(
      state.win,
      float.decorate(geometry, { title = " issue ", pane = "sidebar" })
    )
  end
end

return M
