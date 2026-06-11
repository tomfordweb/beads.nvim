-- Shared float geometry: centered layout plus redraw on VimResized, so
-- terminal size changes (tmux pane resize/zoom) re-center open floats.
-- Dimensions and border come from the `float` config table.

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

--- Configured dimensions for a float kind ("view"|"edit"|"palette"|"graph").
---@param kind string
---@return { width: integer, height: integer|nil }
function M.dims(kind)
  return require("beads.config").get().float[kind] or {}
end

--- Configured border style.
---@return string|table
function M.border()
  return require("beads.config").get().float.border
end

--- Decorate a win config with border, title and (when the helpbar is
--- enabled) the pane's footer. footer_pos without footer is an nvim error,
--- so the footer keys are only set when there is something to show.
---@param cfg table geometry fragment (from M.center)
---@param opts { title: string|nil, pane: string|nil, style: string|nil }
---@return table
function M.decorate(cfg, opts)
  cfg = vim.tbl_extend("force", cfg, { border = M.border() })
  if opts.title then
    cfg.title = opts.title
    cfg.title_pos = "center"
  end
  if opts.style then
    cfg.style = opts.style
  end
  if opts.pane then
    local footer = require("beads.helpbar").footer(opts.pane)
    if footer then
      cfg.footer = footer
      cfg.footer_pos = "center"
    end
  end
  return cfg
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
