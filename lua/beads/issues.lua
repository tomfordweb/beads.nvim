-- Pure helpers: CLI argument builders, issue normalization, display constants.
-- No vim API side effects beyond table utilities; everything here is unit-testable.

local M = {}

-- Cycle orders used by the picker filter mappings. nil means "no filter".
M.STATUSES = { "open", "in_progress", "blocked", "closed" }
M.TYPES = { "bug", "feature", "task", "epic", "chore" }
M.PRIORITIES = { 0, 1, 2, 3, 4 }

M.STATUS_ICONS = {
  open = "○",
  in_progress = "◐",
  blocked = "⊘",
  deferred = "❄",
  closed = "●",
}

---@param status string|nil
---@return string
function M.status_icon(status)
  return M.STATUS_ICONS[status] or "?"
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
  -- so multi-hyphen prefixes match in full instead of truncating
  return word:match("([%a][%w_-]*%-%w+)")
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
