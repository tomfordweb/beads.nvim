---@class BeadsKeymaps
---@field list string|false
---@field ready string|false
---@field create string|false
---@field quick string|false
---@field palette string|false

---@class BeadsConfig
---@field bd_bin string
---@field cwd string|nil
---@field list_limit integer
---@field default_filters { status: string|nil, priority: integer|nil, type: string|nil, all: boolean }
---@field picker { theme: string }
---@field keymaps boolean|BeadsKeymaps
---@field palette { extra: table[] }
---@field runner fun(argv: string[], opts: table, on_exit: fun(out: table))|nil

local M = {}

local defaults = {
  bd_bin = "bd",
  cwd = nil,
  list_limit = 200,
  default_filters = { status = nil, priority = nil, type = nil, all = false },
  picker = { theme = "ivy" },
  keymaps = false,
  palette = { extra = {} },
  runner = nil,
}

local default_keymaps = {
  list = "<leader>bdl",
  ready = "<leader>bdr",
  create = "<leader>bdc",
  quick = "<leader>bdq",
  palette = "<leader>bdp",
}

local options = vim.deepcopy(defaults)

---@param opts table|nil
function M.setup(opts)
  options = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  if options.keymaps == true then
    options.keymaps = vim.deepcopy(default_keymaps)
  elseif type(options.keymaps) == "table" then
    options.keymaps = vim.tbl_extend("force", vim.deepcopy(default_keymaps), options.keymaps)
  end
end

---@return BeadsConfig
function M.get()
  return options
end

M.default_keymaps = default_keymaps

return M
