local actions = require("beads.actions")
local config = require("beads.config")

describe("beads.actions", function()
  it("every builtin action has a desc and fn", function()
    for name, action in pairs(actions.actions) do
      assert.is_string(action.desc, name .. " desc")
      assert.is_function(action.fn, name .. " fn")
    end
  end)

  it("resolves builtin action names", function()
    local fn, desc = actions.resolve("browse")
    assert.is_function(fn)
    assert.equals("browse issues", desc)
  end)

  it("returns nil for unknown action names", function()
    local fn, desc = actions.resolve("nope")
    assert.is_nil(fn)
    assert.is_nil(desc)
  end)

  it("resolves plain functions", function()
    local marker = function() end
    local fn, desc = actions.resolve(marker)
    assert.equals(marker, fn)
    assert.equals("custom action", desc)
  end)

  it("resolves { desc, fn } tables", function()
    local marker = function() end
    local fn, desc = actions.resolve({ fn = marker, desc = "mine" })
    assert.equals(marker, fn)
    assert.equals("mine", desc)
  end)
end)

describe("keymaps config normalization", function()
  after_each(function()
    config.setup({})
  end)

  it("expands keymaps = true to base + default menus", function()
    config.setup({ keymaps = true })
    local km = config.get().keymaps
    assert.equals("<leader>bd", km.base)
    assert.equals("browse", km.menus.l)
    assert.equals("palette", km.menus.p)
  end)

  it("custom base keeps default menus", function()
    config.setup({ keymaps = { base = "<leader>b" } })
    local km = config.get().keymaps
    assert.equals("<leader>b", km.base)
    assert.equals("browse", km.menus.l)
  end)

  it("custom menus replace defaults wholesale", function()
    config.setup({ keymaps = { menus = { i = "all" } } })
    local km = config.get().keymaps
    assert.equals("<leader>bd", km.base)
    assert.equals("all", km.menus.i)
    assert.is_nil(km.menus.l)
  end)

  it("keymaps = false stays disabled", function()
    config.setup({ keymaps = false })
    assert.is_false(config.get().keymaps)
  end)
end)

describe("setup keymap registration", function()
  it("registers base..key for named and custom actions", function()
    require("beads").setup({
      keymaps = {
        base = "zB",
        menus = {
          i = "browse",
          x = { desc = "custom", fn = function() end },
          d = false,
        },
      },
    })
    assert.is_truthy(vim.fn.maparg("zBi", "n"))
    assert.not_equals("", vim.fn.maparg("zBi", "n"))
    assert.not_equals("", vim.fn.maparg("zBx", "n"))
    assert.equals("", vim.fn.maparg("zBd", "n"))
    vim.keymap.del("n", "zBi")
    vim.keymap.del("n", "zBx")
    config.setup({})
  end)
end)
