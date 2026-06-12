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
      local hrows = links.history or {}
      if #hrows > 0 then
        blank_separator()
        add_line(lines, hls, "Recent history", "BeadsSection")
        for _, row in ipairs(hrows) do
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

--- Title-case a status name for a board column header
--- ("in_progress" -> "In Progress"). Pure.
---@param status string|nil
---@return string
function M.status_title(status)
  local s = (status or ""):gsub("_", " ")
  return (s:gsub("(%a)([%w]*)", function(a, b)
    return a:upper() .. b:lower()
  end))
end

--- Group normalized issues into ordered status columns for the kanban board.
--- Only the statuses in `statuses` become columns (in that order); issues whose
--- status falls outside the subset are dropped. A status with no issues still
--- yields an empty column. Pure.
---@param list table[] normalized issues
---@param statuses string[] column status order / subset
---@return { status: string, items: table[] }[]
function M.board_group(list, statuses)
  local by_status = {}
  for _, issue in ipairs(list or {}) do
    local s = issue.status or "open"
    by_status[s] = by_status[s] or {}
    table.insert(by_status[s], issue)
  end
  local out = {}
  for _, s in ipairs(statuses or {}) do
    table.insert(out, { status = s, items = by_status[s] or {} })
  end
  return out
end

--- Render one board column (header + issue cards) into lines + highlight specs
--- + a line->id dispatch map. Each card is two lines: an icon/id/priority row
--- (id link-styled and gd-jumpable) and the indented, truncated title. Pure.
---@param group { status: string, items: table[] }
---@param width integer column inner width
---@return string[] lines, table[] hls, table<integer, string> rows
function M.board_column_lines(group, width)
  local lines, hls, rows = {}, {}, {}
  add_line(
    lines,
    hls,
    ("%s %s (%d)"):format(
      issues.status_icon(group.status),
      M.status_title(group.status),
      #group.items
    ),
    M.status_hl(group.status)
  )
  add_line(lines, hls, "")
  if #group.items == 0 then
    add_line(lines, hls, " (empty)", "BeadsMeta")
    return lines, hls, rows
  end
  for _, issue in ipairs(group.items) do
    -- truncate first, then locate the id in the final text: a narrow column can
    -- clip the id, and a highlight spanning past the clipped line is an extmark
    -- "out of range" error. find() on the truncated text only matches an intact
    -- id, so a clipped id simply renders unlinked.
    local text = truncate(
      (" %s %s  %s"):format(
        issues.status_icon(issue.status),
        issue.id,
        issues.priority_label(issue.priority)
      ),
      width
    )
    add_line(lines, hls, text, issue.status == "closed" and "Comment" or nil)
    rows[#lines] = issue.id
    local id_start = text:find(issue.id, 1, true)
    if id_start then
      table.insert(hls, {
        lnum = #lines - 1,
        col_start = id_start - 1,
        col_end = id_start - 1 + #issue.id,
        hl_group = "BeadsLink",
      })
    end
    add_line(lines, hls, truncate("   " .. (issue.title or ""), width), "BeadsMeta")
    rows[#lines] = issue.id
  end
  return lines, hls, rows
end

--- Render the wisps browser: ephemeral agent issues grouped by wisp type
--- (in `types` order; empty types are omitted), one link-styled, gd-jumpable
--- row each. Returns lines + highlight specs + a line->id dispatch map. Pure.
---@param list table[] normalized wisps, each tagged with a `wisp_type`
---@param types string[] wisp-type order
---@param width integer inner width for truncation
---@return string[] lines, table[] hls, table<integer, string> rows
function M.wisp_lines(list, types, width)
  local by_type = {}
  for _, w in ipairs(list or {}) do
    local t = w.wisp_type or "?"
    by_type[t] = by_type[t] or {}
    table.insert(by_type[t], w)
  end
  local lines, hls, rows = {}, {}, {}
  for _, t in ipairs(types or {}) do
    local items = by_type[t]
    if items and #items > 0 then
      if #lines > 0 then
        add_line(lines, hls, "")
      end
      add_line(lines, hls, ("%s (%d)"):format(t, #items), "BeadsSection")
      for _, w in ipairs(items) do
        -- truncate before locating the id (see board_column_lines): a clipped
        -- id must not produce an out-of-range highlight.
        local text = truncate(
          (" %s %s  %s  %s"):format(
            issues.status_icon(w.status),
            w.id,
            issues.priority_label(w.priority),
            w.title or ""
          ),
          width
        )
        add_line(lines, hls, text)
        rows[#lines] = w.id
        local id_start = text:find(w.id, 1, true)
        if id_start then
          table.insert(hls, {
            lnum = #lines - 1,
            col_start = id_start - 1,
            col_end = id_start - 1 + #w.id,
            hl_group = "BeadsLink",
          })
        end
      end
    end
  end
  if #lines == 0 then
    add_line(lines, hls, "No wisps.", "BeadsSection")
    add_line(lines, hls, "")
    add_line(
      lines,
      hls,
      "Wisps are ephemeral agent-runtime issues (heartbeats, patrols,",
      "BeadsMeta"
    )
    add_line(
      lines,
      hls,
      "health checks). Promote one with p to make it a permanent bead.",
      "BeadsMeta"
    )
  end
  return lines, hls, rows
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

local HL_LINKS = {
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

local function apply_highlights()
  for group, link in pairs(HL_LINKS) do
    vim.api.nvim_set_hl(0, group, { link = link, default = true })
  end
end

--- Define default highlight groups (links). Call sites invoke this on every
--- surface open as lazy init; after the first call it is free. A ColorScheme
--- autocmd re-applies the links since `hi clear` wipes them.
local highlights_defined = false
function M.define_highlights()
  if highlights_defined then
    return
  end
  highlights_defined = true
  apply_highlights()
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("beads_highlights", { clear = true }),
    callback = apply_highlights,
  })
end

return M
