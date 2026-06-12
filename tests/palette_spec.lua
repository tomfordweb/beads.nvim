local palette = require("beads.palette")

describe("palette.commands", function()
  local function find(label_pat)
    for _, cmd in ipairs(palette.commands) do
      if cmd.label:match(label_pat) then
        return cmd
      end
    end
    return nil
  end

  it("includes the read-only diagnostics", function()
    for _, name in ipairs({ "preflight", "doctor", "find%-duplicates", "orphans", "blocked" }) do
      assert.is_truthy(find("^" .. name), "missing palette command: " .. name)
    end
  end)

  it("exposes epic status and a confirm-gated close-eligible", function()
    assert.is_truthy(find("^epic status"))
    local ce = find("^epic close%-eligible")
    assert.is_truthy(ce)
    assert.is_true(ce.confirm)
  end)

  it("diff prompts for two refs with sensible defaults", function()
    local diff = find("^diff")
    assert.is_truthy(diff)
    assert.equals(2, #diff.inputs)
    assert.equals("HEAD~1", diff.inputs[1].default)
    assert.equals("HEAD", diff.inputs[2].default)
  end)

  it("every command has a non-empty label and args", function()
    for _, cmd in ipairs(palette.commands) do
      assert.is_string(cmd.label)
      assert.is_true(#cmd.label > 0)
      assert.is_true(#cmd.args > 0)
    end
  end)
end)
