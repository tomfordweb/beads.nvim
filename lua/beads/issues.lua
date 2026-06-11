-- Mostly-pure helpers: CLI argument builders, issue normalization, display
-- constants. statuses()/types() are the one exception — they lazily shell out
-- to bd (once, cached) so custom statuses/types configured in bd show up.

local M = {}

-- Fallback cycle orders for the picker filter mappings; the live lists come
-- from `bd statuses` / `bd types` via M.statuses() / M.types() so custom
-- types configured in bd show up. nil means "no filter".
M.STATUSES = { "open", "in_progress", "blocked", "deferred", "closed" }
M.TYPES = { "bug", "feature", "task", "epic", "chore", "decision" }
M.PRIORITIES = { 0, 1, 2, 3, 4 }

-- Lazily fetched per session; _reset_lists() clears for tests.
local lists = { statuses = nil, types = nil, status_icons = {} }

function M._reset_lists()
  lists = { statuses = nil, types = nil, status_icons = {} }
end

--- Status names from `bd statuses --json` (cached; falls back to M.STATUSES
--- when bd is unavailable). Also caches bd's own status icons as a fallback
--- icon source for statuses the config table doesn't know.
---@return string[]
function M.statuses()
  if lists.statuses then
    return lists.statuses
  end
  local out = {}
  local ok, raw = require("beads.cli").run_sync({ "statuses" }, { json = true })
  if ok and type(raw) == "table" then
    for _, s in ipairs(raw.built_in_statuses or {}) do
      if type(s.name) == "string" then
        table.insert(out, s.name)
        if type(s.icon) == "string" then
          lists.status_icons[s.name] = s.icon
        end
      end
    end
  end
  lists.statuses = #out > 0 and out or vim.deepcopy(M.STATUSES)
  return lists.statuses
end

--- Type names from `bd types --json` (cached; falls back to M.TYPES).
---@return string[]
function M.types()
  if lists.types then
    return lists.types
  end
  local out = {}
  local ok, raw = require("beads.cli").run_sync({ "types" }, { json = true })
  if ok and type(raw) == "table" then
    for _, t in ipairs(raw.core_types or {}) do
      if type(t.name) == "string" then
        table.insert(out, t.name)
      end
    end
  end
  lists.types = #out > 0 and out or vim.deepcopy(M.TYPES)
  return lists.types
end

---@param status string|nil
---@return string
function M.status_icon(status)
  local icons = require("beads.config").get().icons.status or {}
  return icons[status] or lists.status_icons[status] or "?"
end

---@param priority integer|nil
---@return string
function M.priority_label(priority)
  if priority == nil then
    return "P?"
  end
  return "P" .. tostring(priority)
end

--- Extract a bead issue id from a word under cursor.
--- Ids look like `<prefix>-<hash>` where prefix may contain letters, digits,
--- underscores and hyphens (e.g. beads_nvim-x9s, bundle-analyzer-v2y, bd-15).
---@param word string|nil
---@return string|nil
function M.match_issue_id(word)
  if not word or word == "" then
    return nil
  end
  -- greedy class + backtracking pins the hash to the last hyphen segment,
  -- so multi-hyphen prefixes match in full instead of truncating; dots
  -- cover hierarchical child ids (bd-u2f.1), trailing dots are sentence
  -- punctuation, not id
  local id = word:match("([%a][%w_-]*%-[%w.]+)")
  return id and id:gsub("%.+$", "") or nil
end

--- Build argv tail for `bd search`.
---@param prompt string
---@param opts { all: boolean|nil }|nil
---@return string[]
function M.build_search_args(prompt, opts)
  local args = { "search", prompt }
  if opts and opts.all then
    table.insert(args, "--status")
    table.insert(args, "all")
  end
  return args
end

--- Build argv tail for `bd list`.
---@param filters { status: string|nil, priority: integer|nil, type: string|nil, all: boolean|nil, limit: integer|nil }
---@return string[]
function M.build_list_args(filters)
  filters = filters or {}
  local args = { "list" }
  if filters.all then
    table.insert(args, "--all")
  end
  if filters.status then
    table.insert(args, "--status")
    table.insert(args, filters.status)
  end
  if filters.priority ~= nil then
    table.insert(args, "-p")
    table.insert(args, tostring(filters.priority))
  end
  if filters.type then
    table.insert(args, "--type")
    table.insert(args, filters.type)
  end
  if filters.limit ~= nil then
    table.insert(args, "-n")
    table.insert(args, tostring(filters.limit))
  end
  return args
end

--- Build argv tail for `bd create`.
---@param form { title: string, type: string|nil, priority: integer|nil, deps: string|nil, description: string|nil }
---@return string[]
function M.build_create_args(form)
  local args = { "create", form.title }
  if form.type then
    table.insert(args, "-t")
    table.insert(args, form.type)
  end
  if form.priority ~= nil then
    table.insert(args, "-p")
    table.insert(args, tostring(form.priority))
  end
  if form.description and form.description ~= "" then
    table.insert(args, "-d")
    table.insert(args, form.description)
  end
  if form.deps and form.deps ~= "" then
    table.insert(args, "--deps")
    table.insert(args, form.deps)
  end
  return args
end

--- Normalize a raw issue table from bd JSON output. Single choke point for
--- shape drift: every downstream consumer sees these defaults.
---@param raw table
---@return table
function M.normalize(raw)
  return {
    id = raw.id or "?",
    title = raw.title or "",
    status = raw.status or "open",
    priority = raw.priority or 2,
    issue_type = raw.issue_type or "task",
    assignee = raw.assignee,
    labels = raw.labels or {},
    description = raw.description or "",
    design = raw.design,
    acceptance_criteria = raw.acceptance_criteria,
    notes = raw.notes,
    created_at = raw.created_at or "",
    updated_at = raw.updated_at or "",
    closed_at = raw.closed_at,
    dependencies = raw.dependencies or {},
    dependency_count = raw.dependency_count or 0,
    dependent_count = raw.dependent_count or 0,
    comment_count = raw.comment_count or 0,
  }
end

--- Split an issue's links into sidebar sections. `issue.dependencies` (from
--- bd show) holds what this issue depends on — a parent-child entry there is
--- the parent. `dependents` (from `bd dep list <id> --direction=up`) holds
--- what depends on this issue — parent-child entries there are children,
--- everything else is blocked by this issue. Entries are normalized. Pure.
---@param issue table normalized issue
---@param dependents table[]|nil raw entries from dep list --direction=up
---@return { parent: table|nil, children: table[], depends_on: table[], blocks: table[] }
function M.partition_links(issue, dependents)
  local links = { parent = nil, children = {}, depends_on = {}, blocks = {} }
  for _, dep in ipairs(issue.dependencies or {}) do
    local n = M.normalize(dep)
    n.dependency_type = dep.dependency_type
    if dep.dependency_type == "parent-child" then
      links.parent = links.parent or n
    else
      table.insert(links.depends_on, n)
    end
  end
  for _, dep in ipairs(dependents or {}) do
    local n = M.normalize(dep)
    n.dependency_type = dep.dependency_type
    if dep.dependency_type == "parent-child" then
      table.insert(links.children, n)
    else
      table.insert(links.blocks, n)
    end
  end
  return links
end

--- Client-side filter predicate matching the picker's active filters.
---@param issue table normalized issue
---@param filters { status: string|nil, priority: integer|nil, type: string|nil, all: boolean|nil }
---@return boolean
function M.matches(issue, filters)
  if not filters.all and not filters.status and issue.status == "closed" then
    return false
  end
  if filters.status and issue.status ~= filters.status then
    return false
  end
  if filters.priority ~= nil and issue.priority ~= filters.priority then
    return false
  end
  if filters.type and issue.issue_type ~= filters.type then
    return false
  end
  return true
end

--- Cycle a value through a list: nil -> list[1] -> ... -> list[#list] -> nil.
---@generic T
---@param current T|nil
---@param values T[]
---@return T|nil
function M.cycle(current, values)
  if current == nil then
    return values[1]
  end
  for i, v in ipairs(values) do
    if v == current then
      return values[i + 1] -- nil after last entry, completing the cycle
    end
  end
  return values[1]
end

return M
