local render = require("beads.render")
local issues = require("beads.issues")
local fixtures = require("tests.fixtures.issues")

describe("render.strip_ansi", function()
  it("removes SGR sequences", function()
    assert.equals("bold", render.strip_ansi("\27[1mbold\27[0m"))
    assert.equals("BLOCKED", render.strip_ansi("\27[1mBLOCKED\27[m"))
    assert.equals("plain", render.strip_ansi("plain"))
  end)
end)

describe("render.entry_columns", function()
  it("renders full issue columns", function()
    local cols = render.entry_columns(issues.normalize(fixtures.show_issue))
    assert.equals("beads_nvim-hcl", cols.id)
    assert.equals("◐", cols.icon)
    assert.equals("P2", cols.priority)
    assert.equals("task", cols.type)
    assert.equals("↓1 ↑1", cols.deps)
  end)

  it("renders empty deps column when no relations", function()
    local issue = issues.normalize(fixtures.sparse_issue)
    assert.equals("", render.entry_columns(issue).deps)
  end)

  it("renders only dependents", function()
    local cols = render.entry_columns(issues.normalize(fixtures.list_issue))
    assert.equals("↑5", cols.deps)
  end)
end)

describe("render.detail_lines", function()
  local function find_line(lines, pattern)
    for i, l in ipairs(lines) do
      if l:match(pattern) then
        return i, l
      end
    end
    return nil
  end

  it("renders header, status line, and description", function()
    local issue = issues.normalize(fixtures.show_issue)
    local lines = render.detail_lines(issue)
    assert.equals("# Phase 2: render module + picker", lines[1])
    assert.is_truthy(lines[2]:match("in_progress"))
    assert.is_truthy(lines[2]:match("P2"))
    assert.is_truthy(find_line(lines, "^## Description"))
    assert.is_truthy(find_line(lines, "Build the telescope picker%."))
    assert.is_truthy(find_line(lines, "With filter cycling%."))
  end)

  it("renders dep ids as standalone cWORDs", function()
    local issue = issues.normalize(fixtures.show_issue)
    local lines = render.detail_lines(issue)
    local _, dep_line = find_line(lines, "beads_nvim%-ay7")
    assert.is_truthy(dep_line)
    -- id must be whitespace-delimited so expand("<cWORD>") yields it exactly
    local found = false
    for word in dep_line:gmatch("%S+") do
      if word == "beads_nvim-ay7" then
        found = true
      end
    end
    assert.is_true(found)
    assert.equals("beads_nvim-ay7", issues.match_issue_id("beads_nvim-ay7"))
  end)

  it("renders placeholder for empty description and no dep section", function()
    local issue = issues.normalize(fixtures.sparse_issue)
    local lines = render.detail_lines(issue)
    assert.is_truthy(find_line(lines, "_%(none%)_"))
    assert.is_nil(find_line(lines, "^## Depends on"))
  end)

  it("styles dep ids as links spanning exactly the id", function()
    local issue = issues.normalize(fixtures.show_issue)
    local lines, hls = render.detail_lines(issue)
    local found = false
    for _, h in ipairs(hls) do
      if h.hl_group == "BeadsLink" then
        found = true
        local span = lines[h.lnum + 1]:sub(h.col_start + 1, h.col_end)
        assert.equals(span, issues.match_issue_id(span))
      end
    end
    assert.is_true(found, "no BeadsLink highlight emitted")
  end)

  it("returns highlights within line bounds", function()
    local issue = issues.normalize(fixtures.show_issue)
    local lines, hls = render.detail_lines(issue)
    assert.is_true(#hls > 0)
    for _, h in ipairs(hls) do
      assert.is_true(h.lnum >= 0 and h.lnum < #lines, "lnum in range")
      assert.is_string(h.hl_group)
    end
  end)

  it("shows dependent count", function()
    local issue = issues.normalize(fixtures.list_issue)
    local lines = render.detail_lines(issue)
    assert.is_truthy(find_line(lines, "Blocks 5 other issue"))
  end)

  it("renders comments section with author, date, and indented body", function()
    local issue = issues.normalize(fixtures.show_issue)
    local comments = {
      { author = "Tom Ford", text = "first\nsecond", created_at = "2026-06-11T13:00:37Z" },
    }
    local lines = render.detail_lines(issue, comments)
    assert.is_truthy(find_line(lines, "^## Comments %(1%)"))
    assert.is_truthy(find_line(lines, "Tom Ford — 2026%-06%-11"))
    assert.is_truthy(find_line(lines, "^  first$"))
    assert.is_truthy(find_line(lines, "^  second$"))
  end)

  it("omits comments section when empty or nil", function()
    local issue = issues.normalize(fixtures.show_issue)
    assert.is_nil(find_line(render.detail_lines(issue, {}), "^## Comments"))
    assert.is_nil(find_line(render.detail_lines(issue), "^## Comments"))
  end)
end)

describe("render.link_spans", function()
  it("links the first id per line, byte-accurate", function()
    local lines = {
      "  ├── ✓ beads_nvim-ay7 ● P2 Phase 1: dep-jump polish",
      "  no ids here",
      "bundle-analyzer-v2y something",
    }
    local hls = render.link_spans(lines)
    assert.equals(2, #hls)
    assert.equals("beads_nvim-ay7", lines[1]:sub(hls[1].col_start + 1, hls[1].col_end))
    assert.equals(2, hls[2].lnum)
    assert.equals("bundle-analyzer-v2y", lines[3]:sub(hls[2].col_start + 1, hls[2].col_end))
    for _, h in ipairs(hls) do
      assert.equals("BeadsLink", h.hl_group)
    end
  end)
end)
