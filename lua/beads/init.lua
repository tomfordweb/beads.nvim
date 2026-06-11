local M = {}

--- Configure beads.nvim. Optional — all commands work with defaults.
---@param opts table|nil see beads.config defaults
function M.setup(opts)
  require("beads.config").setup(opts)

  local keymaps = require("beads.config").get().keymaps
  if type(keymaps) == "table" then
    local function map(lhs, rhs, desc)
      if lhs then
        vim.keymap.set("n", lhs, rhs, { desc = "Beads: " .. desc, silent = true })
      end
    end
    map(keymaps.list, function()
      require("beads.picker").open()
    end, "browse issues")
    map(keymaps.ready, function()
      require("beads.picker").open({ source = "ready" })
    end, "ready work")
    map(keymaps.create, function()
      require("beads.create").open_form()
    end, "create issue")
    map(keymaps.quick, function()
      require("beads.create").quick()
    end, "quick capture")
    map(keymaps.palette, function()
      require("beads.palette").open()
    end, "command palette")
  end
end

function M.open(opts)
  require("beads.picker").open(opts)
end

function M.show(id)
  require("beads.view").open(id)
end

return M
