-- Linked-issues sidebar companion to the detail view: overview + parent /
-- children / depends-on / blocks sections, each id jumpable. The view owns
-- the lifecycle (open/refresh/close alongside its own float) and injects
-- navigation callbacks so there is no require cycle back into beads.view.

local config = require("beads.config")
local float = require("beads.float")
local issues = require("beads.issues")
local render = require("beads.render")

local M = {}

-- callbacks: { jump = fun(id), focus_view = fun(), back = fun(), quit = fun() }
local state = { win = nil, buf = nil, callbacks = nil }

function M.is_open()
  return state.win ~= nil and vim.api.nvim_win_is_valid(state.win)
end

function M.close()
  if M.is_open() then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win = nil
  state.buf = nil
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

local function setup_keymaps(buf)
  local mappings = config.get().mappings.sidebar or {}
  local handlers = {
    jump = {
      desc = "open issue under cursor",
      fn = function()
        local id = issues.match_issue_id(vim.fn.expand("<cWORD>"))
        if id and state.callbacks then
          state.callbacks.jump(id)
        end
      end,
    },
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

local function ensure_win(geometry)
  if M.is_open() then
    vim.api.nvim_win_set_config(
      state.win,
      float.decorate(geometry, { title = " links ", pane = "sidebar" })
    )
    return
  end
  state.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[state.buf].buftype = "nofile"
  vim.bo[state.buf].bufhidden = "wipe"

  state.win = vim.api.nvim_open_win(
    state.buf,
    false, -- the detail view keeps focus
    float.decorate(geometry, { title = " links ", pane = "sidebar", style = "minimal" })
  )
  vim.wo[state.win].wrap = false
  setup_keymaps(state.buf)

  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(state.win),
    once = true,
    callback = function()
      state.win = nil
      state.buf = nil
    end,
  })
end

--- Open or re-render the sidebar.
---@param issue table normalized issue
---@param links table from issues.partition_links
---@param geometry table window geometry fragment (from the view's layout)
---@param callbacks { jump: fun(id: string), focus_view: fun(), back: fun(), quit: fun() }
function M.open(issue, links, geometry, callbacks)
  state.callbacks = callbacks or state.callbacks
  ensure_win(geometry)

  local cfg = config.get().sidebar
  local lines, hls =
    render.sidebar_lines(issue, links, { sections = cfg.sections, width = cfg.width })
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
      float.decorate(geometry, { title = " links ", pane = "sidebar" })
    )
  end
end

return M
