local helpbar = require("beads.helpbar")

describe("beads.helpbar", function()
  it("formats a plain help line", function()
    assert.equals(":w save  :q close", helpbar.line("edit"))
  end)

  it("includes every pane mapping in the line", function()
    local line = helpbar.line("view")
    for _, item in ipairs(helpbar.PANES.view) do
      assert.is_truthy(line:find(item[1] .. " " .. item[2], 1, true), "missing " .. item[1])
    end
  end)

  it("returns empty for unknown pane", function()
    assert.equals("", helpbar.line("nope"))
    assert.are.same({}, helpbar.footer("nope"))
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
end)
