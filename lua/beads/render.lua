-- Pure rendering: normalized issue tables -> display strings/lines/highlights.
-- No buffer or window manipulation here; view.lua and picker.lua consume this.

local issues = require("beads.issues")

local M = {}

---@param s string
---@return string
function M.strip_ansi(s)
  return (s:gsub("\27%[[%d;]*m", ""))
end

---@param iso string|nil
---@return string
local function short_date(iso)
  if type(iso) ~= "string" or #iso < 10 then
    return "?"
  end
  return iso:sub(1, 10)
end

--- Column strings for the telescope entry displayer.
---@param issue table normalized issue
---@return { id: string, icon: string, priority: string, type: string, title: string, deps: string }
function M.entry_columns(issue)
  local deps = ""
  if issue.dependency_count > 0 then
    deps = "↓" .. issue.dependency_count
  end
  if issue.dependent_count > 0 then
    deps = deps .. (deps ~= "" and " " or "") .. "↑" .. issue.dependent_count
  end
  return {
    id = issue.id,
    icon = issues.status_icon(issue.status),
    priority = issues.priority_label(issue.priority),
    type = issue.issue_type,
    title = issue.title,
    deps = deps,
  }
end

---@param lines string[]
---@param hls table[]
---@param text string
---@param hl_group string|nil applied to the whole line when given
local function add_line(lines, hls, text, hl_group)
  table.insert(lines, text)
  if hl_group then
    table.insert(hls, { lnum = #lines - 1, col_start = 0, col_end = -1, hl_group = hl_group })
  end
end

local STATUS_HL = {
  open = "BeadsStatusOpen",
  in_progress = "BeadsStatusInProgress",
  blocked = "BeadsStatusBlocked",
  closed = "BeadsStatusClosed",
  deferred = "BeadsStatusDeferred",
}

---@param status string
---@return string
function M.status_hl(status)
  return STATUS_HL[status] or "BeadsStatusOpen"
end

--- Render a full issue (from `bd show --json`) into buffer lines plus
--- extmark highlight specs ({lnum, col_start, col_end, hl_group}, 0-indexed).
---@param issue table normalized issue
---@param comments { author: string|nil, text: string|nil, created_at: string|nil }[]|nil
---@return string[] lines, table[] highlights
function M.detail_lines(issue, comments)
  local lines, hls = {}, {}

  add_line(lines, hls, ("# %s"):format(issue.title), "BeadsTitle")
  add_line(
    lines,
    hls,
    ("%s %s   %s   %s"):format(
      issues.status_icon(issue.status),
      issue.status,
      issues.priority_label(issue.priority),
      issue.issue_type
    ),
    M.status_hl(issue.status)
  )

  local meta = {}
  if issue.assignee and issue.assignee ~= "" then
    table.insert(meta, "assignee: " .. issue.assignee)
  end
  table.insert(meta, "created: " .. short_date(issue.created_at))
  table.insert(meta, "updated: " .. short_date(issue.updated_at))
  add_line(lines, hls, table.concat(meta, "   "), "BeadsMeta")

  if #issue.labels > 0 then
    add_line(lines, hls, "labels: " .. table.concat(issue.labels, ", "), "BeadsMeta")
  end

  add_line(lines, hls, "")
  add_line(lines, hls, "## Description", "BeadsSection")
  if issue.description == "" then
    add_line(lines, hls, "_(none)_", "Comment")
  else
    for _, l in ipairs(vim.split(issue.description, "\n", { plain = true })) do
      add_line(lines, hls, l)
    end
  end

  if #issue.dependencies > 0 then
    add_line(lines, hls, "")
    add_line(lines, hls, "## Depends on", "BeadsSection")
    for _, dep in ipairs(issue.dependencies) do
      -- dep id rendered as a standalone WORD so <cWORD> dep-jump matches
      local text = ("  %-10s %s  %s %s  %s  %s"):format(
        dep.dependency_type or "dep",
        dep.id,
        issues.status_icon(dep.status),
        dep.status or "?",
        issues.priority_label(dep.priority),
        dep.title or ""
      )
      add_line(lines, hls, text, dep.status == "closed" and "Comment" or nil)
      -- style the jumpable id as a link (layered after the line highlight)
      local id_start = text:find(dep.id, 1, true)
      if id_start then
        table.insert(hls, {
          lnum = #lines - 1,
          col_start = id_start - 1,
          col_end = id_start - 1 + #dep.id,
          hl_group = "BeadsLink",
        })
      end
    end
  end

  if issue.dependent_count > 0 then
    add_line(lines, hls, "")
    add_line(lines, hls, ("Blocks %d other issue(s)"):format(issue.dependent_count), "BeadsMeta")
  end

  if issue.notes and issue.notes ~= "" then
    add_line(lines, hls, "")
    add_line(lines, hls, "## Notes", "BeadsSection")
    for _, l in ipairs(vim.split(issue.notes, "\n", { plain = true })) do
      add_line(lines, hls, l)
    end
  end

  if comments and #comments > 0 then
    add_line(lines, hls, "")
    add_line(lines, hls, ("## Comments (%d)"):format(#comments), "BeadsSection")
    for _, comment in ipairs(comments) do
      add_line(lines, hls, ("%s — %s"):format(comment.author or "?", short_date(comment.created_at)), "BeadsMeta")
      for _, l in ipairs(vim.split(comment.text or "", "\n", { plain = true })) do
        add_line(lines, hls, "  " .. l)
      end
    end
  end

  return lines, hls
end

--- Link-style highlight tuple for the first issue id on each line.
--- Intended for surfaces with one id per line (bd graph output); issue
--- titles may contain hyphenated words, so later matches are skipped to
--- avoid false links. Pure.
---@param lines string[]
---@return table[] highlights ({lnum, col_start, col_end, hl_group})
function M.link_spans(lines)
  local hls = {}
  for lnum, line in ipairs(lines) do
    local s, e = line:find("[%a][%w_-]*%-%w+")
    if s then
      table.insert(hls, {
        lnum = lnum - 1,
        col_start = s - 1,
        col_end = e,
        hl_group = "BeadsLink",
      })
    end
  end
  return hls
end

--- Define default highlight groups (links); called once at plugin load.
function M.define_highlights()
  local links = {
    BeadsTitle = "Title",
    BeadsMeta = "Comment",
    BeadsSection = "Function",
    BeadsHelp = "NonText",
    BeadsHelpKey = "Special",
    BeadsLink = "Underlined",
    BeadsStatusOpen = "DiagnosticInfo",
    BeadsStatusInProgress = "DiagnosticWarn",
    BeadsStatusBlocked = "DiagnosticError",
    BeadsStatusClosed = "Comment",
    BeadsStatusDeferred = "NonText",
  }
  for group, link in pairs(links) do
    vim.api.nvim_set_hl(0, group, { link = link, default = true })
  end
end

return M
