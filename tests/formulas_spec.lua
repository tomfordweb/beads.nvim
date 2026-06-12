local formulas = require("beads.formulas")

describe("formulas.normalize", function()
  it("returns an empty list for nil / non-table (the dev-repo null case)", function()
    assert.same({}, formulas.normalize(nil))
    assert.same({}, formulas.normalize("null"))
    assert.same({}, formulas.normalize(42))
  end)

  it("accepts a bare-string array of names", function()
    local out = formulas.normalize({ "mol-review", "mol-feature" })
    assert.equals(2, #out)
    -- sorted by name
    assert.equals("mol-feature", out[1].name)
    assert.equals("mol-review", out[2].name)
    assert.equals("", out[1].description)
  end)

  it("accepts a name->description map", function()
    local out = formulas.normalize({ ["mol-feature"] = "feature work" })
    assert.equals(1, #out)
    assert.equals("mol-feature", out[1].name)
    assert.equals("feature work", out[1].description)
  end)

  it("accepts a list of tables with name/id + description/summary", function()
    local out = formulas.normalize({
      { name = "mol-a", description = "alpha" },
      { id = "mol-b", summary = "beta" },
      { formula = "mol-c", phase = "vapor" },
    })
    assert.equals(3, #out)
    assert.equals("mol-a", out[1].name)
    assert.equals("alpha", out[1].description)
    assert.equals("mol-b", out[2].name)
    assert.equals("beta", out[2].description)
    assert.equals("mol-c", out[3].name)
    assert.equals("vapor", out[3].description)
  end)

  it("skips entries with no usable name", function()
    local out = formulas.normalize({ { description = "nameless" }, { name = "keep" } })
    assert.equals(1, #out)
    assert.equals("keep", out[1].name)
  end)
end)

describe("formulas.pour_args", function()
  it("builds mol pour with no vars", function()
    assert.same({ "mol", "pour", "mol-x" }, formulas.pour_args("mol-x", nil))
    assert.same({ "mol", "pour", "mol-x" }, formulas.pour_args("mol-x", {}))
  end)

  it("appends one --var per substitution", function()
    assert.same(
      { "mol", "pour", "mol-x", "--var", "name=auth", "--var", "pr=123" },
      formulas.pour_args("mol-x", { "name=auth", "pr=123" })
    )
  end)
end)

describe("palette mol/formula commands", function()
  local palette = require("beads.palette")
  local function find(pat)
    for _, cmd in ipairs(palette.commands) do
      if cmd.label:match(pat) then
        return cmd
      end
    end
  end

  it("exposes formula list, mol current and mol progress", function()
    assert.same({ "formula", "list" }, find("^formula list").args)
    assert.same({ "mol", "current" }, find("^mol current").args)
    assert.same({ "mol", "progress" }, find("^mol progress").args)
  end)
end)
