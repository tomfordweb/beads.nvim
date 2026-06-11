local issues = require("beads.issues")
local fixtures = require("tests.fixtures.issues")

describe("issues.build_list_args", function()
  it("builds bare list with no filters", function()
    assert.are.same({ "list" }, issues.build_list_args({}))
  end)

  it("includes --all", function()
    assert.are.same({ "list", "--all" }, issues.build_list_args({ all = true }))
  end)

  it("includes status filter", function()
    assert.are.same(
      { "list", "--status", "open" },
      issues.build_list_args({ status = "open" })
    )
  end)

  it("includes priority 0 (falsy-adjacent but valid)", function()
    assert.are.same({ "list", "-p", "0" }, issues.build_list_args({ priority = 0 }))
  end)

  it("omits priority when nil", function()
    assert.are.same({ "list" }, issues.build_list_args({ priority = nil }))
  end)

  it("includes type and limit", function()
    assert.are.same(
      { "list", "--type", "bug", "-n", "50" },
      issues.build_list_args({ type = "bug", limit = 50 })
    )
  end)

  it("combines all filters", function()
    assert.are.same(
      { "list", "--all", "--status", "closed", "-p", "1", "--type", "task", "-n", "10" },
      issues.build_list_args({ all = true, status = "closed", priority = 1, type = "task", limit = 10 })
    )
  end)
end)

describe("issues.build_create_args", function()
  it("builds minimal create", function()
    assert.are.same({ "create", "fix it" }, issues.build_create_args({ title = "fix it" }))
  end)

  it("includes type, priority, description, deps", function()
    assert.are.same(
      { "create", "fix it", "-t", "bug", "-p", "0", "-d", "details", "--deps", "blocks:bd-15" },
      issues.build_create_args({
        title = "fix it",
        type = "bug",
        priority = 0,
        description = "details",
        deps = "blocks:bd-15",
      })
    )
  end)

  it("omits empty deps and description", function()
    assert.are.same(
      { "create", "fix it" },
      issues.build_create_args({ title = "fix it", deps = "", description = "" })
    )
  end)
end)

describe("issues.normalize", function()
  it("passes through full issue", function()
    local n = issues.normalize(fixtures.show_issue)
    assert.equals("beads_nvim-hcl", n.id)
    assert.equals("in_progress", n.status)
    assert.equals(2, n.priority)
    assert.equals(1, #n.dependencies)
    assert.equals("blocks", n.dependencies[1].dependency_type)
  end)

  it("applies defaults to sparse issue", function()
    local n = issues.normalize(fixtures.sparse_issue)
    assert.equals("open", n.status)
    assert.equals(2, n.priority)
    assert.equals("task", n.issue_type)
    assert.equals("", n.description)
    assert.are.same({}, n.dependencies)
    assert.equals(0, n.dependency_count)
  end)
end)

describe("issues.build_search_args", function()
  it("builds plain search args", function()
    assert.are.same({ "search", "auth bug" }, issues.build_search_args("auth bug"))
  end)

  it("appends --status all when requested", function()
    assert.are.same({ "search", "x", "--status", "all" }, issues.build_search_args("x", { all = true }))
  end)
end)

describe("issues.match_issue_id", function()
  it("matches numeric-suffix ids", function()
    assert.equals("bd-15", issues.match_issue_id("bd-15"))
  end)

  it("matches hash-suffix ids with underscore prefix", function()
    assert.equals("beads_nvim-x9s", issues.match_issue_id("beads_nvim-x9s"))
  end)

  it("matches full id when prefix contains hyphens", function()
    assert.equals("bundle-analyzer-v2y", issues.match_issue_id("bundle-analyzer-v2y"))
    assert.equals("my-multi-part-repo-a1b", issues.match_issue_id("my-multi-part-repo-a1b"))
    assert.equals("bundle-analyzer-v2y", issues.match_issue_id("(bundle-analyzer-v2y),"))
  end)

  it("matches id embedded in punctuation", function()
    assert.equals("bd-15", issues.match_issue_id("(bd-15)"))
    assert.equals("beads_nvim-ay7", issues.match_issue_id("beads_nvim-ay7:"))
  end)

  it("rejects non-ids", function()
    assert.is_nil(issues.match_issue_id("hello"))
    assert.is_nil(issues.match_issue_id("123-456"))
    assert.is_nil(issues.match_issue_id(""))
    assert.is_nil(issues.match_issue_id(nil))
  end)
end)

describe("issues.matches", function()
  local open_bug = issues.normalize({ id = "x-1", title = "t", status = "open", issue_type = "bug", priority = 1 })
  local closed_task = issues.normalize({ id = "x-2", title = "t", status = "closed", issue_type = "task", priority = 2 })

  it("hides closed by default", function()
    assert.is_true(issues.matches(open_bug, {}))
    assert.is_false(issues.matches(closed_task, {}))
  end)

  it("shows closed with all=true", function()
    assert.is_true(issues.matches(closed_task, { all = true }))
  end)

  it("explicit closed status filter shows closed", function()
    assert.is_true(issues.matches(closed_task, { status = "closed" }))
    assert.is_false(issues.matches(open_bug, { status = "closed" }))
  end)

  it("filters by priority and type", function()
    assert.is_true(issues.matches(open_bug, { priority = 1, type = "bug" }))
    assert.is_false(issues.matches(open_bug, { priority = 0 }))
    assert.is_false(issues.matches(open_bug, { type = "task" }))
  end)
end)

describe("issues.cycle", function()
  it("starts at first value from nil", function()
    assert.equals("open", issues.cycle(nil, issues.STATUSES))
  end)

  it("advances through values", function()
    assert.equals("in_progress", issues.cycle("open", issues.STATUSES))
  end)

  it("returns nil after last value", function()
    assert.is_nil(issues.cycle("closed", issues.STATUSES))
  end)

  it("cycles priorities including 0", function()
    assert.equals(0, issues.cycle(nil, issues.PRIORITIES))
    assert.equals(1, issues.cycle(0, issues.PRIORITIES))
    assert.is_nil(issues.cycle(4, issues.PRIORITIES))
  end)
end)
