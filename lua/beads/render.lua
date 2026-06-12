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
  local icons = require("beads.config").get().icons
  local deps = ""
  if issue.dependency_count > 0 then
    deps = (icons.deps_down or "↓") .. issue.dependency_count
  end
  if issue.dependent_count > 0 then
    deps = deps .. (deps ~= "" and " " or "") .. (icons.deps_up or "↑") .. issue.dependent_count
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

--- Append a link-styled, gd-jumpable issue row (icon, id, status, prio,
--- title) indented under a section. Closed entries are dimmed.
local function add_issue_row(lines, hls, entry)
  local text = ("  %s %s  %s  %s  %s"):format(
    issues.status_icon(entry.status),
    entry.id,
    entry.status or "?",
    issues.priority_label(entry.priority),
    entry.title or ""
  )
  add_line(lines, hls, text, entry.status == "closed" and "Comment" or nil)
  local id_start = text:find(entry.id, 1, true)
  if id_start then
    table.insert(hls, {
      lnum = #lines - 1,
      col_start = id_start - 1,
      col_end = id_start - 1 + #entry.id,
      hl_group = "BeadsLink",
    })
  end
end

--- Render a full issue (from `bd show --json`) into buffer lines plus
--- extmark highlight specs ({lnum, col_start, col_end, hl_group}, 0-indexed).
---@param issue table normalized issue
---@param comments { author: string|nil, text: string|nil, created_at: string|nil }[]|nil
---@param children table[]|nil normalized children (epics only; from bd children)
---@return string[] lines, table[] highlights
function M.detail_lines(issue, comments, children)
  local lines, hls = {}, {}

  add_line(lines, hls, ("# %s"):format(issue.title), "BeadsTitle")
  if issue.id and issue.id ~= "" then
    add_line(lines, hls, issue.id, "BeadsId")
  end
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

  if children and #children > 0 then
    local closed = 0
    for _, child in ipairs(children) do
      if child.status == "closed" then
        closed = closed + 1
      end
    end
    add_line(lines, hls, "")
    add_line(lines, hls, ("## Children (%d/%d closed)"):format(closed, #children), "BeadsSection")
    for _, child in ipairs(children) do
      add_issue_row(lines, hls, child)
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
      add_line(
        lines,
        hls,
        ("%s — %s"):format(comment.author or "?", short_date(comment.created_at)),
        "BeadsMeta"
      )
      for _, l in ipairs(vim.split(comment.text or "", "\n", { plain = true })) do
        add_line(lines, hls, "  " .. l)
      end
    end
  end

  return lines, hls
end

---@param s string
---@param width integer
---@return string
local function truncate(s, width)
  if vim.fn.strdisplaywidth(s) <= width then
    return s
  end
  return vim.fn.strcharpart(s, 0, math.max(1, width - 1)) .. "…"
end

--- One linked issue as two sidebar lines: " <icon> <id>" with the id
--- link-styled, then the truncated title indented beneath. Both lines are
--- tagged in `rows` so cursor dispatch works anywhere on the entry.
local function add_link_entry(lines, hls, entry, width, rows)
  local text = (" %s %s"):format(issues.status_icon(entry.status), entry.id)
  add_line(lines, hls, text, entry.status == "closed" and "Comment" or nil)
  rows[#lines] = { kind = "link", id = entry.id }
  local id_start = text:find(entry.id, 1, true)
  if id_start then
    -- layered after the line highlight, same as detail_lines dep ids
    table.insert(hls, {
      lnum = #lines - 1,
      col_start = id_start - 1,
      col_end = id_start - 1 + #entry.id,
      hl_group = "BeadsLink",
    })
  end
  if entry.title and entry.title ~= "" then
    add_line(lines, hls, "   " .. truncate(entry.title, width - 4), "BeadsMeta")
    rows[#lines] = { kind = "link", id = entry.id }
  end
end

--- Issue-action rows for the sidebar Actions section, reflecting the issue's
--- current state (close vs reopen, defer vs undefer, current status/priority).
---@param issue table normalized issue
---@return { name: string, label: string }[]
local function action_rows(issue)
  local assignee = issue.assignee and issue.assignee ~= "" and issue.assignee or nil
  return {
    { name = "status", label = "status: " .. issue.status },
    { name = "priority", label = "priority: " .. issues.priority_label(issue.priority) },
    { name = "comment", label = "add comment" },
    { name = "labels", label = "labels" },
    { name = "assign", label = assignee and ("assign: " .. assignee) or "assign" },
    { name = "defer", label = issue.status == "deferred" and "undefer" or "defer" },
    issue.status == "closed" and { name = "reopen", label = "reopen" }
      or { name = "close", label = "close" },
    { name = "graph", label = "graph" },
    { name = "history", label = "history" },
  }
end

local SIDEBAR_TITLES = {
  parent = "Parent",
  children = "Children",
  depends_on = "Depends on",
  blocks = "Blocks",
}

--- Render the issue sidebar (overview / actions / links / comments /
--- history). Sections come from opts.sections (order preserved, empty ones
--- omitted). Ids are standalone WORDs so <cWORD> dep-jump works. The third
--- return maps 1-indexed line numbers to dispatch targets:
--- { kind = "action", name = <handler name> } | { kind = "link", id = <id> }.
--- Pure.
---@param issue table normalized issue
---@param links { parent: table|nil, children: table[], depends_on: table[], blocks: table[], comments: table[]|nil, history: table[]|nil }
---@param opts { sections: string[], width: integer, action_keys: table<string, string>|nil }
---@return string[] lines, table[] highlights, table<integer, table> rows
function M.sidebar_lines(issue, links, opts)
  local width = opts.width or 34
  local lines, hls, rows = {}, {}, {}

  local function blank_separator()
    if #lines > 0 then
      add_line(lines, hls, "")
    end
  end

  for _, section in ipairs(opts.sections or {}) do
    if section == "overview" then
      blank_separator()
      add_line(lines, hls, "Overview", "BeadsSection")
      add_line(
        lines,
        hls,
        (" %s %s  %s %s"):format(
          issues.status_icon(issue.status),
          issue.status,
          issues.priority_label(issue.priority),
          issue.issue_type
        ),
        M.status_hl(issue.status)
      )
      if issue.assignee and issue.assignee ~= "" then
        add_line(lines, hls, truncate(" assignee: " .. issue.assignee, width), "BeadsMeta")
      end
      if #issue.labels > 0 then
        add_line(
          lines,
          hls,
          truncate(" labels: " .. table.concat(issue.labels, ", "), width),
          "BeadsMeta"
        )
      end
      add_line(lines, hls, " created " .. short_date(issue.created_at), "BeadsMeta")
      add_line(lines, hls, " updated " .. short_date(issue.updated_at), "BeadsMeta")
      if issue.comment_count > 0 then
        add_line(lines, hls, (" comments: %d"):format(issue.comment_count), "BeadsMeta")
      end
    elseif section == "actions" then
      blank_separator()
      add_line(lines, hls, "Actions", "BeadsSection")
      for _, row in ipairs(action_rows(issue)) do
        local key = opts.action_keys and opts.action_keys[row.name]
        local text
        if key then
          text = (" %s  %s"):format(key, row.label)
        else
          text = ("    %s"):format(row.label)
        end
        add_line(lines, hls, truncate(text, width), "BeadsMeta")
        rows[#lines] = { kind = "action", name = row.name }
        if key then
          table.insert(hls, {
            lnum = #lines - 1,
            col_start = 1,
            col_end = 1 + #key,
            hl_group = "BeadsHelpKey",
          })
        end
      end
    elseif section == "comments" then
      local cs = links.comments or {}
      if #cs > 0 then
        blank_separator()
        add_line(lines, hls, ("Comments (%d)"):format(#cs), "BeadsSection")
        for _, comment in ipairs(cs) do
          add_line(
            lines,
            hls,
            truncate(
              (" %s — %s"):format(comment.author or "?", short_date(comment.created_at)),
              width
            ),
            "BeadsMeta"
          )
          for _, l in ipairs(vim.split(comment.text or "", "\n", { plain = true })) do
            add_line(lines, hls, truncate("  " .. l, width))
          end
        end
      end
    elseif section == "history" then
      -- last-N change rows surfaced inline (M3); full log stays behind `H`
      local rows = links.history or {}
      if #rows > 0 then
        blank_separator()
        add_line(lines, hls, "Recent history", "BeadsSection")
        for _, row in ipairs(rows) do
          add_line(
            lines,
            hls,
            truncate((" %s  %s"):format(row.date, row.committer), width),
            "BeadsMeta"
          )
          add_line(lines, hls, truncate("  " .. row.summary, width))
        end
      end
    elseif SIDEBAR_TITLES[section] then
      local entries = section == "parent" and (links.parent and { links.parent } or {})
        or links[section]
        or {}
      if #entries > 0 then
        blank_separator()
        local header = SIDEBAR_TITLES[section]
        if #entries > 1 then
          header = ("%s (%d)"):format(header, #entries)
        end
        add_line(lines, hls, header, "BeadsSection")
        for _, entry in ipairs(entries) do
          add_link_entry(lines, hls, entry, width, rows)
        end
      end
    end
  end

  if #lines == 0 then
    add_line(lines, hls, "(no links)", "BeadsMeta")
  end
  return lines, hls, rows
end

-- Status rows for the home dashboard, in display order.
local DASHBOARD_ROWS = {
  { key = "open_issues", status = "open", label = "open" },
  { key = "in_progress_issues", status = "in_progress", label = "in progress" },
  { key = "blocked_issues", status = "blocked", label = "blocked" },
  { key = "deferred_issues", status = "deferred", label = "deferred" },
  { key = "closed_issues", status = "closed", label = "closed" },
}

--- Home-dashboard lines from a `bd stats --json` summary table: one colored
--- row per status with its count, then ready/total. Missing fields render 0.
--- Pure.
---@param summary table the `summary` object from bd stats --json
---@return string[] lines, table[] highlights
function M.dashboard_lines(summary)
  summary = summary or {}
  local lines, hls = {}, {}
  add_line(lines, hls, "beads.nvim", "BeadsTitle")
  add_line(lines, hls, "")
  for _, row in ipairs(DASHBOARD_ROWS) do
    local n = tonumber(summary[row.key]) or 0
    add_line(
      lines,
      hls,
      (" %s %-13s %4d"):format(issues.status_icon(row.status), row.label, n),
      M.status_hl(row.status)
    )
  end
  add_line(lines, hls, "")
  add_line(
    lines,
    hls,
    (" %-15s %4d"):format("ready", tonumber(summary.ready_issues) or 0),
    "BeadsSection"
  )
  add_line(
    lines,
    hls,
    (" %-15s %4d"):format("total", tonumber(summary.total_issues) or 0),
    "BeadsMeta"
  )
  -- nudge: epics whose children are all closed and can be wrapped up
  local epics_done = tonumber(summary.epics_eligible_for_closure) or 0
  if epics_done > 0 then
    add_line(
      lines,
      hls,
      (" %-15s %4d"):format("epics to close", epics_done),
      "BeadsStatusInProgress"
    )
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
    local s, e = line:find("[%a][%w_-]*%-[%w.]+")
    if s then
      while e > s and line:sub(e, e) == "." do
        e = e - 1
      end
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
    BeadsId = "Identifier",
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
