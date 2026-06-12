local config = require("beads.config")
local helpbar = require("beads.helpbar")

describe("beads.helpbar", function()
  before_each(function()
    config.setup({})
  end)

  it("formats a plain help line", function()
    assert.equals(":w save  :q close", helpbar.line("edit"))
  end)

  it("includes every pane mapping in the line", function()
    local line = helpbar.line("view")
    for _, item in ipairs(helpbar.items("view")) do
      assert.is_truthy(line:find(item[1] .. " " .. item[2], 1, true), "missing " .. item[1])
    end
    assert.is_truthy(line:find("e edit", 1, true))
    assert.is_truthy(line:find("gd dep-jump", 1, true))
  end)

  it("returns empty for unknown pane", function()
    assert.equals("", helpbar.line("nope"))
    assert.is_nil(helpbar.footer("nope"))
  end)

  it("builds footer chunks as [text, hl] pairs alternating key/action", function()
    local chunks = helpbar.footer("edit")
    -- 2 items -> key+action chunks each, plus trailing pad
    assert.equals(5, #chunks)
    assert.equals("BeadsHelpKey", chunks[1][2])
    assert.is_truthy(chunks[1][1]:find(":w", 1, true))
    assert.equals("BeadsHelp", chunks[2][2])
    assert.is_truthy(chunks[2][1]:find("save", 1, true))
    for _, c in ipairs(chunks) do
      assert.is_string(c[1])
      assert.is_string(c[2])
    end
  end)

  it("ready picker pane omits status/closed filters", function()
    local line = helpbar.line("picker_ready")
    assert.is_nil(line:find("<C-s>", 1, true))
    assert.is_nil(line:find("<C-a>", 1, true))
    assert.is_truthy(line:find("<C-y> prio", 1, true))
  end)

  it("reflects user mapping overrides", function()
    config.setup({ mappings = { view = { edit = "E" } } })
    local line = helpbar.line("view")
    assert.is_truthy(line:find("E edit", 1, true))
    assert.is_nil(line:find("e edit", 1, true))
    -- untouched defaults survive a partial override
    assert.is_truthy(line:find("s status", 1, true))
  end)

  it("shows the first key of a multi-key action", function()
    local line = helpbar.line("view")
    assert.is_truthy(line:find("gd dep-jump", 1, true))
    assert.is_nil(line:find("<CR> dep-jump", 1, true))
  end)

  it("drops disabled actions", function()
    config.setup({ mappings = { picker = { status = false } } })
    local line = helpbar.line("picker")
    assert.is_nil(line:find("status", 1, true))
    assert.is_truthy(line:find("<C-y> prio", 1, true))
  end)

  it("view pane advertises the sidebar key", function()
    assert.is_truthy(helpbar.line("view"):find("<Tab> links", 1, true))
  end)

  it("sidebar pane resolves its mapping group", function()
    local line = helpbar.line("sidebar")
    assert.is_truthy(line:find("gd run/open", 1, true))
    assert.is_truthy(line:find("<Tab> view", 1, true))
    assert.is_truthy(line:find("q quit", 1, true))
  end)

  it("view_editable pane shows editor verbs and resolves nav actions", function()
    local line = helpbar.line("view_editable")
    assert.is_truthy(line:find(":w save", 1, true))
    assert.is_truthy(line:find(":q close", 1, true))
    assert.is_truthy(line:find("<Tab> actions", 1, true))
    assert.is_truthy(line:find("<BS> back", 1, true))
  end)

  it("helpbar = false suppresses line and footer", function()
    config.setup({ helpbar = false })
    assert.equals("", helpbar.line("view"))
    assert.is_nil(helpbar.footer("view"))
    assert.equals("", helpbar.line("edit"))
  end)
end)
