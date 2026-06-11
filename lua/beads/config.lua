---@class BeadsKeymaps
---@field base string prefix prepended to every menu key (e.g. "<leader>b")
---@field menus table<string, string|fun()|{ desc: string|nil, fn: fun() }|false>
--- menu values: builtin action name (see beads.actions), a function, a
--- { desc, fn } table, or false to disable a default entry

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
  base = "<leader>bd",
  menus = {
    l = "browse",
    o = "open",
    r = "ready",
    c = "create",
    q = "quick",
    p = "palette",
  },
}

local options = vim.deepcopy(defaults)

---@param opts table|nil
function M.setup(opts)
  options = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  if options.keymaps == true then
    options.keymaps = vim.deepcopy(default_keymaps)
  elseif type(options.keymaps) == "table" then
    local user = options.keymaps
    options.keymaps = {
      base = user.base or default_keymaps.base,
      -- user menus replace the defaults wholesale when given; mixing
      -- defaults into custom single-letter menus surprises more than helps
      menus = user.menus or vim.deepcopy(default_keymaps.menus),
    }
  end
end

---@return BeadsConfig
function M.get()
  return options
end

M.default_keymaps = default_keymaps

return M
