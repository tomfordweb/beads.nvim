local create = require("beads.create")
local cli = require("beads.cli")
local config = require("beads.config")

describe("beads.create", function()
  local recorded
  local orig_input, orig_select, orig_notify

  before_each(function()
    config.setup({ cwd = "/tmp" })
    recorded = {}
    cli._runner = function(argv, sys_opts, on_exit)
      table.insert(recorded, { argv = argv, sys_opts = sys_opts })
      on_exit({ code = 0, stdout = '{"id":"bd-99","title":"t"}', stderr = "" })
    end
    orig_input, orig_select, orig_notify = vim.ui.input, vim.ui.select, vim.notify
    vim.notify = function() end
  end)

  after_each(function()
    vim.ui.input, vim.ui.select, vim.notify = orig_input, orig_select, orig_notify
    config.setup({})
  end)

  local function drain()
    vim.wait(200, function()
      return #recorded > 0
    end, 5)
    vim.wait(50, function()
      return false
    end, 5)
  end

  it("quick runs bd q with given title", function()
    create.quick("fix the thing")
    drain()
    assert.are.same({ "bd", "q", "fix the thing" }, recorded[1].argv)
  end)

  it("quick prompts when no title", function()
    vim.ui.input = function(opts, cb)
      assert.is_truthy(opts.prompt:match("bd q"))
      cb("prompted title")
    end
    create.quick()
    drain()
    assert.are.same({ "bd", "q", "prompted title" }, recorded[1].argv)
  end)

  it("quick aborts on empty input", function()
    vim.ui.input = function(_, cb)
      cb(nil)
    end
    create.quick()
    vim.wait(100, function()
      return false
    end, 5)
    assert.equals(0, #recorded)
  end)

  it("form chain assembles full create args", function()
    vim.ui.input = function(opts, cb)
      if opts.prompt:match("^Title") then
        cb("new feature")
      else
        cb("blocks:bd-15")
      end
    end
    vim.ui.select = function(items, opts, cb)
      if opts.prompt == "Type" then
        cb("feature")
      else
        cb(items[1], 1) -- P0
      end
    end
    -- stub view.open so the post-create hook doesn't spawn another bd call
    package.loaded["beads.view"] = { open = function() end }
    create.open_form()
    drain()
    package.loaded["beads.view"] = nil
    assert.are.same(
      { "bd", "create", "new feature", "-t", "feature", "-p", "0", "--deps", "blocks:bd-15", "--json" },
      recorded[1].argv
    )
  end)

  it("form aborts when title empty", function()
    vim.ui.input = function(_, cb)
      cb("")
    end
    create.open_form()
    vim.wait(100, function()
      return false
    end, 5)
    assert.equals(0, #recorded)
  end)
end)
