-- Named actions referenced by the `keymaps.menus` config. Each entry maps a
-- stable name to a description and a function; menu values may also be a
-- plain function or a { desc, fn } table for custom entries.

local M = {}

---@class BeadsAction
---@field desc string
---@field fn fun()

---@type table<string, BeadsAction>
M.actions = {
  browse = {
    desc = "browse issues",
    fn = function()
      require("beads.picker").open()
    end,
  },
  all = {
    desc = "all issues (incl. closed)",
    fn = function()
      require("beads.picker").open({ filters = { all = true } })
    end,
  },
  open = {
    desc = "open issues",
    fn = function()
      require("beads.picker").open({ filters = { status = "open" } })
    end,
  },
  in_progress = {
    desc = "in-progress issues",
    fn = function()
      require("beads.picker").open({ filters = { status = "in_progress" } })
    end,
  },
  blocked = {
    desc = "blocked issues",
    fn = function()
      require("beads.picker").open({ filters = { status = "blocked" } })
    end,
  },
  closed = {
    desc = "closed issues",
    fn = function()
      require("beads.picker").open({ filters = { status = "closed" } })
    end,
  },
  ready = {
    desc = "ready (unblocked) work",
    fn = function()
      require("beads.picker").open({ source = "ready" })
    end,
  },
  create = {
    desc = "create issue",
    fn = function()
      require("beads.create").open_form()
    end,
  },
  quick = {
    desc = "quick capture",
    fn = function()
      require("beads.create").quick()
    end,
  },
  palette = {
    desc = "command palette",
    fn = function()
      require("beads.palette").open()
    end,
  },
}

--- Resolve a menus value (action name, function, or { desc, fn } table)
--- into a callable + description.
---@param value string|fun()|{ desc: string|nil, fn: fun() }
---@return fun()|nil fn, string|nil desc
function M.resolve(value)
  if type(value) == "string" then
    local action = M.actions[value]
    if not action then
      return nil, nil
    end
    return action.fn, action.desc
  end
  if type(value) == "function" then
    return value, "custom action"
  end
  if type(value) == "table" and type(value.fn) == "function" then
    return value.fn, value.desc or "custom action"
  end
  return nil, nil
end

return M
