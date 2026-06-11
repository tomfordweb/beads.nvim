-- Shared float geometry: centered layout plus redraw on VimResized, so
-- terminal size changes (tmux pane resize/zoom) re-center open floats.

local M = {}

--- Centered editor-relative geometry clamped to the current screen.
---@param max_width integer
---@param max_height integer
---@return { relative: string, width: integer, height: integer, row: integer, col: integer }
function M.center(max_width, max_height)
  local width = math.max(1, math.min(max_width, vim.o.columns - 8))
  local height = math.max(1, math.min(max_height, vim.o.lines - 6))
  return {
    relative = "editor",
    width = width,
    height = height,
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
  }
end

--- Re-apply geometry from `recompute` on every VimResized until the
--- window closes.
---@param win integer
---@param recompute fun(): table window config fragment
function M.auto_resize(win, recompute)
  local group = vim.api.nvim_create_augroup("beads_float_resize_" .. win, { clear = true })
  vim.api.nvim_create_autocmd("VimResized", {
    group = group,
    callback = function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_set_config(win, recompute())
      end
    end,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    pattern = tostring(win),
    once = true,
    callback = function()
      pcall(vim.api.nvim_del_augroup_by_id, group)
    end,
  })
end

return M
