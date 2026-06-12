-- Change history for a single issue. `bd history <id> --json` returns one
-- entry per db commit (newest first), each carrying a full snapshot of the
-- issue at that commit. Most commits don't touch this issue, so we collapse
-- the stream to the transitions where a tracked field actually changed and
-- render a compact changelog in a read-only float.

local cli = require("beads.cli")
local float = require("beads.float")
local render = require("beads.render")

local M = {}

-- Fields we summarize, in display order. priority is formatted as P<n>.
local TRACKED = { "status", "priority", "assignee", "title", "issue_type", "description" }

---@param iso string|nil
---@return string
local function short_datetime(iso)
  if type(iso) ~= "string" or #iso < 16 then
    return "?"
  end
  -- "2026-06-11T13:53:16..." -> "2026-06-11 13:53"
  return iso:sub(1, 10) .. " " .. iso:sub(12, 16)
end

---@param field string
---@param value any
---@return string
local function fmt(field, value)
  if value == nil or value == "" then
    return "∅"
  end
  if field == "priority" then
    return "P" .. tostring(value)
  end
  if field == "description" then
    return "…" -- bodies are large; we only flag that it changed
  end
  return tostring(value)
end

--- Reduce raw history entries (newest-first) to chronological change rows.
--- Each row: { date, committer, parts = { "field: old → new", ... } | "created" }.
--- Pure (no I/O) so it is unit-testable.
---@param entries table[] raw bd history --json entries
---@return { date: string, committer: string, summary: string }[]
function M.changes(entries)
  local ordered = {}
  for i = #entries, 1, -1 do -- reverse to oldest-first
    table.insert(ordered, entries[i])
  end

  local rows, prev = {}, nil
  for _, e in ipairs(ordered) do
    local issue = e.Issue or {}
    if prev == nil then
      local created = ("created (%s, %s)"):format(
        fmt("status", issue.status),
        fmt("priority", issue.priority)
      )
      table.insert(rows, {
        date = short_datetime(e.CommitDate),
        committer = e.Committer or "?",
        summary = created,
      })
    else
      local parts = {}
      for _, field in ipairs(TRACKED) do
        if tostring(issue[field]) ~= tostring(prev[field]) then
          if field == "description" then
            table.insert(parts, "description edited")
          else
            table.insert(
              parts,
              ("%s: %s → %s"):format(field, fmt(field, prev[field]), fmt(field, issue[field]))
            )
          end
        end
      end
      if #parts > 0 then
        table.insert(rows, {
          date = short_datetime(e.CommitDate),
          committer = e.Committer or "?",
          summary = table.concat(parts, ", "),
        })
      end
    end
    prev = issue
  end
  return rows
end

--- The most recent `n` change rows, newest-first, for the sidebar summary
--- (M3) — surfaces history inline instead of only in the modal. Pure.
---@param entries table[] raw bd history --json entries
---@param n integer
---@return { date: string, committer: string, summary: string }[]
function M.recent(entries, n)
  local rows = M.changes(entries)
  local out = {}
  for i = #rows, math.max(1, #rows - n + 1), -1 do
    table.insert(out, rows[i])
  end
  return out
end

--- Render change rows into display lines + highlights (date dimmed). Pure.
---@param id string
---@param rows { date: string, committer: string, summary: string }[]
---@return string[] lines, table[] highlights
function M.lines(id, rows)
  local lines, hls = {}, {}
  table.insert(lines, "History of " .. id)
  table.insert(hls, { lnum = 0, col_start = 0, col_end = -1, hl_group = "BeadsSection" })
  table.insert(lines, "")
  if #rows == 0 then
    table.insert(lines, "(no recorded changes)")
    return lines, hls
  end
  for _, row in ipairs(rows) do
    local head = ("%s  %s"):format(row.date, row.committer)
    table.insert(lines, head)
    table.insert(hls, { lnum = #lines - 1, col_start = 0, col_end = -1, hl_group = "BeadsMeta" })
    table.insert(lines, "  " .. row.summary)
  end
  return lines, hls
end

--- Open a read-only float showing the issue's change history.
---@param id string
function M.open(id)
  render.define_highlights()
  cli.run_json({ "history", id }, function(ok, entries)
    if not ok or type(entries) ~= "table" then
      return
    end
    local lines, hls = M.lines(id, M.changes(entries))

    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "wipe"
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    float.apply_highlights(buf, "beads_history", hls)
    vim.bo[buf].modifiable = false

    local function geometry()
      return float.center(float.width("palette", 100), float.height("palette", #lines + 1))
    end
    local win = vim.api.nvim_open_win(
      buf,
      true,
      float.decorate(
        geometry(),
        { title = " history ", pane = "palette_output", style = "minimal" }
      )
    )
    vim.wo[win].wrap = true
    float.auto_resize(win, geometry)

    for _, lhs in ipairs({ "q", "<Esc>" }) do
      vim.keymap.set("n", lhs, function()
        if vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_win_close(win, true)
        end
      end, { buffer = buf, silent = true, nowait = true })
    end
  end)
end

return M
