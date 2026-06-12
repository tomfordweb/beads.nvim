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

--- N equally-sized columns laid out as one centered row, each editor-relative,
--- with a border gap between them — the kanban board's geometry. Generalizes
--- the single centered float to N side-by-side windows. Column widths shrink to
--- fit the screen (never below `min_col`), and the whole row stays clamped and
--- centered. Reads vim.o.columns/lines; otherwise pure.
---@param n integer column count (>= 1)
---@param opts { width: integer|nil, height: integer|nil, gap: integer|nil, min_col: integer|nil }|nil
---@return { relative: string, row: integer, col: integer, width: integer, height: integer }[]
function M.columns(n, opts)
  opts = opts or {}
  n = math.max(1, n)
  local gap = opts.gap or 2
  local avail_w = math.max(1, vim.o.columns - 8)
  local avail_h = math.max(1, vim.o.lines - 6)
  local height = math.max(1, math.min(opts.height or avail_h, avail_h))
  local total = math.min(opts.width or avail_w, avail_w)
  local gaps = gap * (n - 1)
  local col_w = math.max(opts.min_col or 16, math.floor((total - gaps) / n))
  -- min_col may push the row past the screen; clamp the width back down so the
  -- row always fits (columns get narrower rather than overflowing offscreen).
  if col_w * n + gaps > avail_w then
    col_w = math.max(1, math.floor((avail_w - gaps) / n))
  end
  local footprint = col_w * n + gaps
  local start_col = math.max(0, math.floor((vim.o.columns - footprint) / 2))
  local row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1)
  local out = {}
  for i = 1, n do
    table.insert(out, {
      relative = "editor",
      row = row,
      col = start_col + (i - 1) * (col_w + gap),
      width = col_w,
      height = height,
    })
  end
  return out
end

--- Configured dimensions for a float kind ("view"|"edit"|"palette"|"graph").
---@param kind string
---@return { width: integer, height: integer|nil }
function M.dims(kind)
  return require("beads.config").get().float[kind] or {}
end

--- Resolve a configured dimension to absolute cells against a total extent.
--- Accepts: a fraction 0 < n <= 1 (percentage of `total`), a "<n>%" string,
--- or an absolute count > 1. nil/invalid -> nil (caller supplies a fallback).
---@param value number|string|nil
---@param total integer editor columns (width) or lines (height)
---@return integer|nil
function M.resolve_dim(value, total)
  if type(value) == "string" then
    local pct = value:match("^%s*(%d+%.?%d*)%s*%%%s*$")
    if pct then
      return math.max(1, math.floor(total * tonumber(pct) / 100))
    end
    value = tonumber(value)
  end
  if type(value) ~= "number" then
    return nil
  end
  if value > 0 and value <= 1 then
    return math.max(1, math.floor(total * value))
  end
  return math.max(1, math.floor(value))
end

--- Resolved width for a float kind (config % / fraction / absolute), or
--- `fallback` when unset.
---@param kind string
---@param fallback integer
---@return integer
function M.width(kind, fallback)
  return M.resolve_dim(M.dims(kind).width, vim.o.columns) or fallback
end

--- Resolved height for a float kind, or `fallback` (callers pass the
--- content-sized height so unconfigured floats stay content-sized).
---@param kind string
---@param fallback integer
---@return integer
function M.height(kind, fallback)
  return M.resolve_dim(M.dims(kind).height, vim.o.lines) or fallback
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

--- Apply {lnum, col_start, col_end, hl_group} specs (0-indexed, col_end = -1
--- for whole line) as extmarks in a named namespace, clearing it first.
---@param buf integer
---@param ns_name string
---@param hls table[]
function M.apply_highlights(buf, ns_name, hls)
  local ns = vim.api.nvim_create_namespace(ns_name)
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

--- Re-apply geometry from `recompute` until the window closes. Tracks
--- VimResized plus the focus-resume events (FocusGained, VimResume) because a
--- tmux reattach or pane-zoom frequently reports those instead of VimResized,
--- which left floats stale (M2). The focus events are opt-out via
--- `refresh_on_focus`; VimResized always applies. Each event is logged through
--- util.debug when `debug = true`.
---@param win integer
---@param recompute fun(): table window config fragment
function M.auto_resize(win, recompute)
  local group = vim.api.nvim_create_augroup("beads_float_resize_" .. win, { clear = true })
  local apply = function(event)
    if not vim.api.nvim_win_is_valid(win) then
      return
    end
    if event ~= "VimResized" and not require("beads.config").get().refresh_on_focus then
      return
    end
    local cfg = recompute()
    vim.api.nvim_win_set_config(win, cfg)
    require("beads.util").debug(
      ("%s -> float %sx%s (editor %dx%d)"):format(
        event,
        tostring(cfg.width or "?"),
        tostring(cfg.height or "?"),
        vim.o.columns,
        vim.o.lines
      )
    )
  end
  vim.api.nvim_create_autocmd({ "VimResized", "FocusGained", "VimResume" }, {
    group = group,
    callback = function(args)
      apply(args.event)
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
