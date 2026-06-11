-- Per-pane keybind help bar. Floats render it as a window footer
-- (nvim >= 0.10); the telescope picker embeds it in the prompt title since
-- telescope draws its own borders. Keys are resolved from the effective
-- `mappings` config so user overrides render truthfully; panes whose binds
-- are not configurable (:w/:q buffers, palette output) use literal keys.
-- `helpbar = false` suppresses the bar everywhere.

local config = require("beads.config")

local M = {}

--- Ordered pane specs. Entries are either { action, label } resolved through
--- the mapping group named by `group`, or { key = literal, label = label }.
---@type table<string, { group: string|nil, [integer]: table }>
M.PANES = {
  picker = {
    group = "picker",
    { action = "open", label = "open" },
    { action = "status", label = "status" },
    { action = "priority", label = "prio" },
    { action = "type", label = "type" },
    { action = "label", label = "label" },
    { action = "defer", label = "defer" },
    { action = "closed", label = "closed" },
    { action = "refetch", label = "refetch" },
  },
  picker_ready = {
    group = "picker",
    { action = "open", label = "open" },
    { action = "priority", label = "prio" },
    { action = "type", label = "type" },
    { action = "label", label = "label" },
    { action = "defer", label = "defer" },
    { action = "refetch", label = "refetch" },
  },
  picker_search = {
    group = "picker",
    { action = "open", label = "open" },
    { action = "closed", label = "closed" },
  },
  view = {
    group = "view",
    { action = "edit", label = "edit" },
    { action = "status", label = "status" },
    { action = "priority", label = "prio" },
    { action = "comment", label = "comment" },
    { action = "labels", label = "labels" },
    { action = "assign", label = "assign" },
    { action = "defer", label = "defer" },
    { action = "close", label = "close" },
    { action = "reopen", label = "reopen" },
    { action = "graph", label = "graph" },
    { action = "history", label = "history" },
    { action = "jump", label = "dep-jump" },
    { action = "sidebar", label = "links" },
    { action = "back", label = "back" },
    { action = "refresh", label = "refresh" },
    { action = "quit", label = "quit" },
  },
  sidebar = {
    group = "sidebar",
    { action = "jump", label = "open" },
    { action = "focus_view", label = "view" },
    { action = "back", label = "history" },
    { action = "quit", label = "quit" },
  },
  memories = {
    group = "memories",
    { action = "edit", label = "edit" },
    { action = "new", label = "new" },
    { action = "forget", label = "forget" },
    { action = "refetch", label = "refetch" },
  },
  graph = {
    group = "graph",
    { action = "jump", label = "open issue" },
    { action = "quit", label = "close" },
  },
  edit = {
    { key = ":w", label = "save" },
    { key = ":q", label = "close" },
  },
  memory_edit = {
    { key = ":w", label = "save" },
    { key = ":q", label = "close" },
  },
  palette_output = {
    { key = "q", label = "close" },
  },
}

--- Resolve a pane to ordered { key, label } pairs using effective config.
--- Disabled actions (lhs = false) are dropped; multi-key actions show the
--- first key only.
---@param pane string
---@return string[][]
function M.items(pane)
  local spec = M.PANES[pane]
  if not spec or not config.get().helpbar then
    return {}
  end
  local group = spec.group and config.get().mappings[spec.group] or nil
  local out = {}
  for _, item in ipairs(spec) do
    local key = item.key
    if not key and item.action and group then
      key = config.lhs(group[item.action])[1]
    end
    if key then
      table.insert(out, { key, item.label })
    end
  end
  return out
end

--- Plain one-line help string ("<CR> open  <C-s> status  …").
--- Empty when the pane is unknown or `helpbar = false`.
---@param pane string
---@return string
function M.line(pane)
  local parts = {}
  for _, item in ipairs(M.items(pane)) do
    table.insert(parts, item[1] .. " " .. item[2])
  end
  return table.concat(parts, "  ")
end

--- Highlighted chunk list for nvim_open_win's `footer` option, or nil when
--- there is nothing to show (so call sites can pass it straight through).
---@param pane string
---@return string[][]|nil [text, hl_group] chunks
function M.footer(pane)
  local items = M.items(pane)
  if #items == 0 then
    return nil
  end
  local chunks = {}
  for i, item in ipairs(items) do
    table.insert(chunks, { (i == 1 and " " or "  ") .. item[1], "BeadsHelpKey" })
    table.insert(chunks, { " " .. item[2], "BeadsHelp" })
  end
  table.insert(chunks, { " ", "BeadsHelp" })
  return chunks
end

return M
