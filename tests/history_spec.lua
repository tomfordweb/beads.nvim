local history = require("beads.history")

-- bd history returns newest-first; build entries that way.
local function entry(date, committer, issue)
  return { CommitDate = date, Committer = committer, CommitHash = "h" .. date, Issue = issue }
end

describe("history.changes", function()
  it("collapses a newest-first stream to chronological transitions", function()
    local entries = {
      entry(
        "2026-06-11T12:00:00-04:00",
        "dev",
        { status = "in_progress", priority = 2, title = "t" }
      ),
      entry("2026-06-11T11:00:00-04:00", "dev", { status = "open", priority = 2, title = "t" }),
      entry("2026-06-11T10:30:00-04:00", "dev", { status = "open", priority = 2, title = "t" }), -- no change
      entry("2026-06-11T10:00:00-04:00", "dev", { status = "open", priority = 3, title = "t" }), -- creation
    }
    local rows = history.changes(entries)
    -- creation + priority change + status change = 3 rows (the no-op is dropped)
    assert.equals(3, #rows)
    assert.is_truthy(rows[1].summary:match("^created"))
    assert.is_truthy(rows[2].summary:match("priority: P3 → P2"))
    assert.is_truthy(rows[3].summary:match("status: open → in_progress"))
  end)

  it("flags description edits without dumping the body", function()
    local entries = {
      entry(
        "2026-06-11T11:00:00-04:00",
        "dev",
        { status = "open", priority = 2, description = "new long body" }
      ),
      entry(
        "2026-06-11T10:00:00-04:00",
        "dev",
        { status = "open", priority = 2, description = "old" }
      ),
    }
    local rows = history.changes(entries)
    assert.equals(2, #rows)
    assert.is_truthy(rows[2].summary:match("description edited"))
    assert.is_nil(rows[2].summary:match("long body"))
  end)

  it("formats empty assignee as ∅", function()
    local entries = {
      entry(
        "2026-06-11T11:00:00-04:00",
        "dev",
        { status = "open", priority = 2, assignee = "alice" }
      ),
      entry("2026-06-11T10:00:00-04:00", "dev", { status = "open", priority = 2, assignee = nil }),
    }
    local rows = history.changes(entries)
    assert.is_truthy(rows[2].summary:match("assignee: ∅ → alice"))
  end)
end)

describe("history.lines", function()
  it("renders a header and two lines per row", function()
    local rows = {
      { date = "2026-06-11 10:00", committer = "dev", summary = "created (open, P2)" },
    }
    local lines, hls = history.lines("bd-1", rows)
    assert.equals("History of bd-1", lines[1])
    assert.is_truthy(vim.tbl_contains(lines, "  created (open, P2)"))
    assert.is_true(#hls > 0)
  end)

  it("shows a placeholder when there are no changes", function()
    local lines = history.lines("bd-1", {})
    assert.is_truthy(vim.tbl_contains(lines, "(no recorded changes)"))
  end)
end)
