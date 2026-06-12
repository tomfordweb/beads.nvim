local graphview = require("beads.graphview")
local config = require("beads.config")
local helpbar = require("beads.helpbar")

describe("graphview.argv", function()
  it("graphs a single issue with --compact when scope is issue", function()
    assert.same({ "graph", "bd-7", "--compact" }, graphview.argv("bd-7", "issue"))
  end)

  it("graphs all open issues with --all --compact when scope is all", function()
    assert.same({ "graph", "--all", "--compact" }, graphview.argv("bd-7", "all"))
  end)

  it("ignores the id entirely in all scope", function()
    assert.same({ "graph", "--all", "--compact" }, graphview.argv(nil, "all"))
  end)

  it("never emits a nil-hole argv for a missing id in issue scope", function()
    -- defensive: a nil id in issue scope falls back to the all-graph form
    assert.same({ "graph", "--all", "--compact" }, graphview.argv(nil, "issue"))
  end)
end)

describe("graphview.title", function()
  it("names the single issue in issue scope", function()
    assert.equals(" graph bd-7 ", graphview.title("bd-7", "issue"))
  end)

  it("reads (all) in all scope without an id", function()
    assert.equals(" graph (all) ", graphview.title(nil, "all"))
  end)
end)

describe("graph config", function()
  after_each(function()
    config.setup({})
  end)

  it("defaults graph.scope to issue", function()
    config.setup({})
    assert.equals("issue", config.get().graph.scope)
  end)

  it("accepts an all scope override", function()
    config.setup({ graph = { scope = "all" } })
    assert.equals("all", config.get().graph.scope)
  end)

  it("exposes a scope toggle key on the graph mapping group", function()
    config.setup({})
    assert.equals("a", config.get().mappings.graph.scope)
  end)
end)

describe("graph helpbar", function()
  after_each(function()
    config.setup({})
  end)

  it("advertises the scope toggle key", function()
    config.setup({})
    local line = helpbar.line("graph")
    assert.is_truthy(line:find("a all/issue", 1, true))
  end)
end)
