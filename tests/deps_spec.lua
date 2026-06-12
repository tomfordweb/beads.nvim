-- Dependency drift guard (E7.3). The Neovim floor and the runtime dependency
-- set are stated in several places; this spec keeps them consistent across the
-- runtime source of truth (health.lua), the README, and CONTRIBUTING, failing
-- the suite (and CI) the moment one drifts from the others.

local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")

local function read(rel)
  return table.concat(vim.fn.readfile(root .. "/" .. rel), "\n")
end

describe("dependency drift guard (E7.3)", function()
  local health = read("lua/beads/health.lua")
  local readme = read("README.md")
  local contributing = read("CONTRIBUTING.md")

  it("states the Neovim 0.10 floor in health, README, and CONTRIBUTING", function()
    assert.is_truthy(health:find("nvim%-0%.10"), "health.lua must gate on nvim-0.10")
    assert.is_truthy(readme:find("0%.10"), "README must state the 0.10 floor")
    assert.is_truthy(contributing:find("0%.10"), "CONTRIBUTING must state the 0.10 floor")
  end)

  it("lists telescope + plenary as deps in all three", function()
    for _, dep in ipairs({ "telescope", "plenary" }) do
      assert.is_truthy(health:find(dep), "health.lua must reference " .. dep)
      assert.is_truthy(readme:find(dep), "README must reference " .. dep)
      assert.is_truthy(contributing:find(dep), "CONTRIBUTING must reference " .. dep)
    end
  end)

  it("does not present treesitter as a runtime dependency", function()
    -- treesitter is panvimdoc help highlighting (docs.yml) and optional markdown
    -- highlighting only — never a runtime require. health.lua must not gate on it.
    assert.is_nil(health:lower():find("treesitter"), "health.lua must not require treesitter")
  end)
end)
