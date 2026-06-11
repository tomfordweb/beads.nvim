local cli = require("beads.cli")
local config = require("beads.config")

describe("beads.cli", function()
  local recorded
  local fake_out

  local function fake_runner(argv, sys_opts, on_exit)
    recorded = { argv = argv, sys_opts = sys_opts }
    on_exit(fake_out)
  end

  local notifications
  local orig_notify = vim.notify

  before_each(function()
    config.setup({ bd_bin = "bd", cwd = "/tmp" })
    cli._runner = fake_runner
    recorded = nil
    fake_out = { code = 0, stdout = "", stderr = "" }
    notifications = {}
    vim.notify = function(msg, level)
      table.insert(notifications, { msg = msg, level = level })
    end
  end)

  after_each(function()
    vim.notify = orig_notify
    config.setup({})
  end)

  local function drain()
    vim.wait(100, function()
      return false
    end, 5)
  end

  it("appends --json for run_json and decodes", function()
    fake_out.stdout = '[{"id":"bd-1","title":"t"}]'
    local got
    cli.run_json({ "list", "--all" }, function(ok, result)
      got = { ok = ok, result = result }
    end)
    drain()
    assert.are.same({ "bd", "list", "--all", "--json" }, recorded.argv)
    assert.equals("/tmp", recorded.sys_opts.cwd)
    assert.is_true(got.ok)
    assert.equals("bd-1", got.result[1].id)
  end)

  it("does not append --json for run_plain", function()
    fake_out.stdout = "raw text"
    local got
    cli.run_plain({ "status" }, function(ok, stdout)
      got = { ok = ok, stdout = stdout }
    end)
    drain()
    assert.are.same({ "bd", "status" }, recorded.argv)
    assert.is_true(got.ok)
    assert.equals("raw text", got.stdout)
  end)

  it("plumbs stdin for run_stdin", function()
    local got
    cli.run_stdin({ "update", "bd-1", "--body-file", "-" }, "new body", function(ok)
      got = ok
    end)
    drain()
    assert.equals("new body", recorded.sys_opts.stdin)
    assert.is_true(got)
  end)

  it("surfaces nonzero exit as cb(false) plus one notification", function()
    fake_out = { code = 1, stdout = "", stderr = "boom" }
    local got
    cli.run_json({ "list" }, function(ok, result, err)
      got = { ok = ok, result = result, err = err }
    end)
    drain()
    assert.is_false(got.ok)
    assert.is_nil(got.result)
    assert.equals("boom", got.err)
    assert.equals(1, #notifications)
    assert.equals(vim.log.levels.ERROR, notifications[1].level)
  end)

  it("surfaces malformed JSON as cb(false)", function()
    fake_out.stdout = "not json {"
    local got
    cli.run_json({ "list" }, function(ok, _, err)
      got = { ok = ok, err = err }
    end)
    drain()
    assert.is_false(got.ok)
    assert.is_truthy(got.err:match("invalid JSON"))
    assert.equals(1, #notifications)
  end)

  it("uses config.runner when provided", function()
    local used = false
    config.setup({
      cwd = "/tmp",
      runner = function(_, _, on_exit)
        used = true
        on_exit({ code = 0, stdout = "[]", stderr = "" })
      end,
    })
    cli.run_json({ "list" }, function() end)
    drain()
    assert.is_true(used)
  end)
end)
