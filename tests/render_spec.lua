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
      { author = "Demo User", text = "first\nsecond", created_at = "2026-06-11T13:00:37Z" },
    }
    local lines = render.detail_lines(issue, comments)
    assert.is_truthy(find_line(lines, "^## Comments %(1%)"))
    assert.is_truthy(find_line(lines, "Demo User — 2026%-06%-11"))
    assert.is_truthy(find_line(lines, "^  first$"))
    assert.is_truthy(find_line(lines, "^  second$"))
  end)

  it("omits comments section when empty or nil", function()
    local issue = issues.normalize(fixtures.show_issue)
    assert.is_nil(find_line(render.detail_lines(issue, {}), "^## Comments"))
    assert.is_nil(find_line(render.detail_lines(issue), "^## Comments"))
  end)
end)

describe("render.sidebar_lines", function()
  local DEFAULT_SECTIONS = { "overview", "parent", "children", "depends_on", "blocks" }

  local function build(sections)
    local issue = issues.normalize(fixtures.show_child_issue)
    local links = issues.partition_links(issue, fixtures.dependents)
    return render.sidebar_lines(
      issue,
      links,
      { sections = sections or DEFAULT_SECTIONS, width = 34 }
    )
  end

  local function find_line(lines, pattern)
    for i, l in ipairs(lines) do
      if l:match(pattern) then
        return i, l
      end
    end
    return nil
  end

  it("renders all populated sections in configured order", function()
    local lines = build()
    local overview = find_line(lines, "^Overview$")
    local parent = find_line(lines, "^Parent$")
    local children = find_line(lines, "^Children$")
    local depends = find_line(lines, "^Depends on$")
    local blocks = find_line(lines, "^Blocks$")
    assert.is_truthy(overview)
    assert.is_true(
      overview < parent and parent < children and children < depends and depends < blocks
    )
  end)

  it("respects custom section selection and order", function()
    local lines = build({ "blocks", "parent" })
    assert.is_nil(find_line(lines, "^Overview$"))
    assert.is_nil(find_line(lines, "^Children"))
    local blocks = find_line(lines, "^Blocks$")
    local parent = find_line(lines, "^Parent$")
    assert.is_true(blocks < parent)
  end)

  it("omits empty sections", function()
    local issue = issues.normalize(fixtures.sparse_issue)
    local links = issues.partition_links(issue, {})
    local lines = render.sidebar_lines(issue, links, { sections = DEFAULT_SECTIONS, width = 34 })
    assert.is_nil(find_line(lines, "^Parent$"))
    assert.is_nil(find_line(lines, "^Children"))
    assert.is_truthy(find_line(lines, "^Overview$"))
  end)

  it("counts multi-entry sections in the header", function()
    local issue = issues.normalize(fixtures.show_child_issue)
    local two_children = {
      fixtures.dependents[1],
      vim.tbl_extend("force", vim.deepcopy(fixtures.dependents[1]), { id = "beads_nvim-u2f.1.2" }),
    }
    local links = issues.partition_links(issue, two_children)
    local lines = render.sidebar_lines(issue, links, { sections = { "children" }, width = 34 })
    assert.is_truthy(find_line(lines, "^Children %(2%)$"))
  end)

  it("ids are standalone cWORDs with BeadsLink spans", function()
    local lines, hls = build()
    local _, entry = find_line(lines, "beads_nvim%-u2f%.1%.1")
    local found = false
    for word in entry:gmatch("%S+") do
      if word == "beads_nvim-u2f.1.1" then
        found = true
      end
    end
    assert.is_true(found)
    local linked = false
    for _, h in ipairs(hls) do
      if h.hl_group == "BeadsLink" then
        linked = true
        local span = lines[h.lnum + 1]:sub(h.col_start + 1, h.col_end)
        assert.equals(span, issues.match_issue_id(span))
      end
    end
    assert.is_true(linked)
  end)

  it("truncates long titles to the configured width", function()
    local issue = issues.normalize(fixtures.show_child_issue)
    local long = {
      {
        id = "beads_nvim-l0ng",
        title = string.rep("very long title ", 10),
        status = "open",
        dependency_type = "blocks",
      },
    }
    local links = issues.partition_links(issue, long)
    local lines = render.sidebar_lines(issue, links, { sections = { "blocks" }, width = 30 })
    local _, title_line = find_line(lines, "very long")
    assert.is_true(vim.fn.strdisplaywidth(title_line) <= 30)
    assert.is_truthy(title_line:find("…"))
  end)

  it("dims closed entries", function()
    local lines, hls = build()
    local closed_lnum = find_line(lines, "beads_nvim%-ay7") - 1
    local dimmed = false
    for _, h in ipairs(hls) do
      if h.lnum == closed_lnum and h.hl_group == "Comment" then
        dimmed = true
      end
    end
    assert.is_true(dimmed)
  end)

  it("renders placeholder when nothing to show", function()
    local issue = issues.normalize(fixtures.sparse_issue)
    local links = issues.partition_links(issue, {})
    local lines =
      render.sidebar_lines(issue, links, { sections = { "parent", "children" }, width = 34 })
    assert.are.same({ "(no links)" }, lines)
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
