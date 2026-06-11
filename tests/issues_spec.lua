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
    assert.are.same({ "list", "--status", "open" }, issues.build_list_args({ status = "open" }))
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
      issues.build_list_args({
        all = true,
        status = "closed",
        priority = 1,
        type = "task",
        limit = 10,
      })
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
    assert.are.same(
      { "search", "x", "--status", "all" },
      issues.build_search_args("x", { all = true })
    )
  end)
end)

describe("issues.match_issue_id", function()
  it("matches numeric-suffix ids", function()
    assert.equals("bd-15", issues.match_issue_id("bd-15"))
  end)

  it("matches hash-suffix ids with underscore prefix", function()
    assert.equals("beads_nvim-x9s", issues.match_issue_id("beads_nvim-x9s"))
  end)

  it("matches hierarchical child ids and strips sentence dots", function()
    assert.equals("beads_nvim-u2f.1", issues.match_issue_id("beads_nvim-u2f.1"))
    assert.equals("beads_nvim-u2f.12", issues.match_issue_id("(beads_nvim-u2f.12)"))
    assert.equals("beads_nvim-u2f", issues.match_issue_id("beads_nvim-u2f."))
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
  local open_bug =
    issues.normalize({ id = "x-1", title = "t", status = "open", issue_type = "bug", priority = 1 })
  local closed_task = issues.normalize({
    id = "x-2",
    title = "t",
    status = "closed",
    issue_type = "task",
    priority = 2,
  })

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

  it("filters by label", function()
    local tagged =
      issues.normalize({ id = "x-3", title = "t", status = "open", labels = { "ui", "perf" } })
    assert.is_true(issues.matches(tagged, { label = "ui" }))
    assert.is_true(issues.matches(tagged, { label = "perf" }))
    assert.is_false(issues.matches(tagged, { label = "docs" }))
    assert.is_false(issues.matches(open_bug, { label = "ui" }))
  end)
end)

describe("issues.collect_labels", function()
  it("returns unique sorted labels across issues", function()
    local list = {
      issues.normalize({ id = "x-1", labels = { "ui", "perf" } }),
      issues.normalize({ id = "x-2", labels = { "perf", "docs" } }),
      issues.normalize({ id = "x-3" }),
    }
    assert.same({ "docs", "perf", "ui" }, issues.collect_labels(list))
  end)

  it("returns empty for no labels", function()
    assert.same({}, issues.collect_labels({ issues.normalize({ id = "x-1" }) }))
    assert.same({}, issues.collect_labels({}))
  end)
end)

describe("issues.partition_links", function()
  it("splits show dependencies into parent and depends_on", function()
    local issue = issues.normalize(fixtures.show_child_issue)
    local links = issues.partition_links(issue, nil)
    assert.equals("beads_nvim-u2f", links.parent.id)
    assert.equals(1, #links.depends_on)
    assert.equals("beads_nvim-ay7", links.depends_on[1].id)
    assert.are.same({}, links.children)
    assert.are.same({}, links.blocks)
  end)

  it("splits dependents into children and blocks", function()
    local issue = issues.normalize(fixtures.show_child_issue)
    local links = issues.partition_links(issue, fixtures.dependents)
    assert.equals(1, #links.children)
    assert.equals("beads_nvim-u2f.1.1", links.children[1].id)
    assert.equals(1, #links.blocks)
    assert.equals("beads_nvim-zz1", links.blocks[1].id)
  end)

  it("handles issues with no links", function()
    local issue = issues.normalize(fixtures.sparse_issue)
    local links = issues.partition_links(issue, {})
    assert.is_nil(links.parent)
    assert.are.same({}, links.children)
    assert.are.same({}, links.depends_on)
    assert.are.same({}, links.blocks)
  end)

  it("normalizes link entries", function()
    local issue = issues.normalize(fixtures.show_child_issue)
    local links = issues.partition_links(issue, fixtures.dependents)
    assert.equals("task", links.children[1].issue_type)
    assert.equals("parent-child", links.children[1].dependency_type)
  end)
end)

describe("issues.statuses / issues.types", function()
  local cli = require("beads.cli")
  local real_run_sync

  before_each(function()
    real_run_sync = cli.run_sync
    issues._reset_lists()
  end)

  after_each(function()
    cli.run_sync = real_run_sync
    issues._reset_lists()
    require("beads.config").setup({})
  end)

  it("fetches status names and icons from bd", function()
    cli.run_sync = function(args)
      assert.are.same({ "statuses" }, args)
      return true,
        {
          built_in_statuses = {
            { name = "open", icon = "○" },
            { name = "hooked", icon = "◇" },
          },
          schema_version = 1,
        }
    end
    assert.are.same({ "open", "hooked" }, issues.statuses())
    -- not in config icon table -> falls back to bd's icon
    assert.equals("◇", issues.status_icon("hooked"))
  end)

  it("caches after first fetch", function()
    local calls = 0
    cli.run_sync = function()
      calls = calls + 1
      return true, { built_in_statuses = { { name = "open" } } }
    end
    issues.statuses()
    issues.statuses()
    assert.equals(1, calls)
  end)

  it("falls back to hardcoded lists when bd fails", function()
    cli.run_sync = function()
      return false, nil, "no bd"
    end
    assert.are.same(issues.STATUSES, issues.statuses())
    assert.are.same(issues.TYPES, issues.types())
  end)

  it("fetches type names from bd", function()
    cli.run_sync = function(args)
      assert.are.same({ "types" }, args)
      return true, { core_types = { { name = "task" }, { name = "spike" } } }
    end
    assert.are.same({ "task", "spike" }, issues.types())
  end)

  it("fallback lists include deferred and decision", function()
    assert.is_truthy(vim.tbl_contains(issues.STATUSES, "deferred"))
    assert.is_truthy(vim.tbl_contains(issues.TYPES, "decision"))
  end)
end)

describe("issues.status_icon", function()
  after_each(function()
    require("beads.config").setup({})
    issues._reset_lists()
  end)

  it("reads from config", function()
    assert.equals("○", issues.status_icon("open"))
    require("beads.config").setup({ icons = { status = { open = "O" } } })
    assert.equals("O", issues.status_icon("open"))
  end)

  it("returns ? for unknown status", function()
    assert.equals("?", issues.status_icon("bogus"))
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
