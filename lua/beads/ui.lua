-- Telescope-facing UI helpers shared by the issue, search and memory pickers.

local config = require("beads.config")

local M = {}

--- Base opts for pickers.new: the configured theme (built with theme_opts)
--- with the raw `picker.telescope` table merged on top.
---@return table
function M.picker_opts()
  local cfg = config.get().picker
  local base = {}
  if cfg.theme then
    local themes = require("telescope.themes")
    local builder = themes["get_" .. cfg.theme]
    if builder then
      base = builder(vim.deepcopy(cfg.theme_opts or {}))
    else
      vim.notify(
        ("beads.nvim: unknown picker.theme %q (use ivy/dropdown/cursor or false)"):format(
          tostring(cfg.theme)
        ),
        vim.log.levels.WARN
      )
    end
  end
  return vim.tbl_deep_extend("force", base, cfg.telescope or {})
end

return M
