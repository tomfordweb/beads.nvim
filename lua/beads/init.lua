local M = {}

--- Configure beads.nvim. Optional — all commands work with defaults.
---@param opts table|nil see beads.config defaults
function M.setup(opts)
  require("beads.config").setup(opts)

  local keymaps = require("beads.config").get().keymaps
  if type(keymaps) == "table" then
    local actions = require("beads.actions")
    for key, value in pairs(keymaps.menus or {}) do
      if value ~= false then
        local fn, desc = actions.resolve(value)
        if fn then
          vim.keymap.set("n", keymaps.base .. key, fn, { desc = "Beads: " .. desc, silent = true })
        else
          vim.notify(("beads.nvim: unknown keymap action %q for key %q"):format(tostring(value), key), vim.log.levels.WARN)
        end
      end
    end
  end
end

function M.open(opts)
  require("beads.picker").open(opts)
end

function M.show(id)
  require("beads.view").open(id)
end

return M
