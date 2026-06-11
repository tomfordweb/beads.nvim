local memories = require("beads.memories")
local cli = require("beads.cli")
local config = require("beads.config")

describe("memories.normalize", function()
  it("strips schema_version and sorts by key", function()
    local list = memories.normalize({
      ["zebra-key"] = "z content",
      ["alpha-key"] = "a content",
      schema_version = 1,
    })
    assert.equals(2, #list)
    assert.equals("alpha-key", list[1].key)
    assert.equals("a content", list[1].value)
    assert.equals("zebra-key", list[2].key)
  end)

  it("returns empty list for empty store", function()
    assert.are.same({}, memories.normalize({ schema_version = 1 }))
    assert.are.same({}, memories.normalize(nil))
  end)
end)

describe("memories.edit save round-trip", function()
  local recorded
  local orig_notify

  before_each(function()
    config.setup({ cwd = "/tmp" })
    recorded = {}
    cli._runner = function(argv, sys_opts, on_exit)
      table.insert(recorded, { argv = argv, sys_opts = sys_opts })
      on_exit({ code = 0, stdout = "", stderr = "" })
    end
    orig_notify = vim.notify
    vim.notify = function() end
  end)

  after_each(function()
    vim.notify = orig_notify
    config.setup({})
    -- wipe any leftover memory edit buffers
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_get_name(b):match("^beads://memory/") then
        vim.api.nvim_buf_delete(b, { force = true })
      end
    end
  end)

  it(":w runs bd remember with buffer body and key", function()
    memories.edit("test-key", "old content")
    local buf = vim.fn.bufnr("beads://memory/test-key")
    assert.is_true(buf ~= -1)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "new line one", "", "new line three" })
    vim.api.nvim_buf_call(buf, function()
      vim.cmd.write()
    end)
    vim.wait(200, function()
      return #recorded > 0
    end, 5)
    assert.are.same({ "bd", "remember", "new line one\n\nnew line three", "--key", "test-key" }, recorded[1].argv)
  end)

  it("refuses to save empty content", function()
    memories.edit("empty-key", "")
    local buf = vim.fn.bufnr("beads://memory/empty-key")
    vim.api.nvim_buf_call(buf, function()
      vim.cmd.write()
    end)
    vim.wait(100, function()
      return false
    end, 5)
    assert.equals(0, #recorded)
  end)
end)
