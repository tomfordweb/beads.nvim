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
  memories = {
    desc = "browse memories",
    fn = function()
      require("beads.memories").open()
    end,
  },
  search = {
    desc = "live search",
    fn = function()
      require("beads.picker").search()
    end,
  },
  graph = {
    desc = "dependency graph",
    fn = function()
      local issues = require("beads.issues")
      local id = issues.match_issue_id(vim.fn.expand("<cWORD>"))
      if id then
        require("beads.graphview").open(id, "issue")
        return
      end
      -- No id in context (e.g. the <leader>bdg menu): open the all-issues graph
      -- straight away; toggle to a single issue from inside the float.
      require("beads.graphview").open(nil, "all")
    end,
  },
  dashboard = {
    desc = "home dashboard",
    fn = function()
      require("beads.dashboard").open()
    end,
  },
  board = {
    desc = "kanban board",
    fn = function()
      require("beads.board").open()
    end,
  },
  wisps = {
    desc = "browse wisps",
    fn = function()
      require("beads.wisps").open()
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

--- True when `value` is an in-pane custom-action spec: a table carrying both a
--- `key` (lhs) and a callable `fn`. Plain lhs values (string/list/false) and
--- the builtin `{ desc, fn }` menu shape (no `key`) are not custom specs.
---@param value any
---@return boolean
function M.is_custom_spec(value)
  return type(value) == "table" and value.key ~= nil and type(value.fn) == "function"
end

return M
