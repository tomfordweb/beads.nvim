-- Integration tests against a real bd binary in a throwaway database.
-- Skipped entirely when bd is not on PATH.

local cli = require("beads.cli")
local config = require("beads.config")
local issues = require("beads.issues")

local has_bd = vim.fn.executable("bd") == 1

describe("integration (real bd)", function()
  if not has_bd then
    pending("bd binary not found on PATH — skipping integration suite", function() end)
    return
  end

  -- plenary's busted port has no setup/teardown; init once at collection
  -- time, clean up in the final test below.
  local dir = vim.uv.fs_mkdtemp(vim.uv.os_tmpdir() .. "/beads_nvim_XXXXXX")
  -- bd init writes CLAUDE.md/hooks noise too; all confined to tmpdir.
  local init_ok, _, init_err = cli.run_sync({ "init" }, { cwd = dir })
  assert(init_ok, "bd init failed: " .. tostring(init_err))
  config.setup({ cwd = dir })

  it("creates and lists an issue", function()
    local ok, out = cli.run_sync({ "q", "integration test issue" })
    assert.is_true(ok)
    local id = vim.trim(out)
    assert.is_truthy(issues.match_issue_id(id))

    local lok, list = cli.run_sync({ "list" }, { json = true })
    assert.is_true(lok)
    assert.equals(1, #list)
    local n = issues.normalize(list[1])
    assert.equals(id, n.id)
    assert.equals("integration test issue", n.title)
    assert.equals("open", n.status)
  end)

  it("updates status and round-trips description via stdin", function()
    local _, out = cli.run_sync({ "q", "second issue" })
    local id = vim.trim(out)

    assert.is_true(cli.run_sync({ "update", id, "-s", "in_progress" }))
    assert.is_true(cli.run_sync({ "update", id, "--body-file", "-" }, { input = "line one\n\nline three" }))

    local ok, shown = cli.run_sync({ "show", id }, { json = true })
    assert.is_true(ok)
    local n = issues.normalize(shown[1])
    assert.equals("in_progress", n.status)
    assert.equals("line one\n\nline three", n.description)
  end)

  it("wires dependencies visible in show --json", function()
    local _, a_out = cli.run_sync({ "q", "blocked issue" })
    local _, b_out = cli.run_sync({ "q", "blocker issue" })
    local a, b = vim.trim(a_out), vim.trim(b_out)

    assert.is_true(cli.run_sync({ "dep", "add", a, b }))

    local ok, shown = cli.run_sync({ "show", a }, { json = true })
    assert.is_true(ok)
    local n = issues.normalize(shown[1])
    assert.equals(1, #n.dependencies)
    assert.equals(b, n.dependencies[1].id)
    assert.equals("blocks", n.dependencies[1].dependency_type)
  end)

  it("close and reopen cycle", function()
    local _, out = cli.run_sync({ "q", "closable" })
    local id = vim.trim(out)

    assert.is_true(cli.run_sync({ "close", id }))
    local _, shown = cli.run_sync({ "show", id }, { json = true })
    assert.equals("closed", issues.normalize(shown[1]).status)

    assert.is_true(cli.run_sync({ "reopen", id }))
    _, shown = cli.run_sync({ "show", id }, { json = true })
    assert.equals("open", issues.normalize(shown[1]).status)
  end)

  it("memories round-trip: remember, list, recall, forget", function()
    local memories = require("beads.memories")

    assert.is_true(cli.run_sync({ "remember", "integration memory body", "--key", "int-mem" }))

    local ok, raw = cli.run_sync({ "memories" }, { json = true })
    assert.is_true(ok)
    local list = memories.normalize(raw)
    assert.equals(1, #list)
    assert.equals("int-mem", list[1].key)
    assert.equals("integration memory body", list[1].value)

    local rok, recalled = cli.run_sync({ "recall", "int-mem" }, { json = true })
    assert.is_true(rok)
    assert.equals("integration memory body", recalled.value)

    assert.is_true(cli.run_sync({ "forget", "int-mem" }))
    local _, after = cli.run_sync({ "memories" }, { json = true })
    assert.are.same({}, memories.normalize(after))
  end)

  it("comment round-trip via stdin", function()
    local _, out = cli.run_sync({ "q", "commented issue" })
    local id = vim.trim(out)

    assert.is_true(cli.run_sync({ "comment", id, "--stdin" }, { input = "a comment\nwith two lines" }))

    local ok, comments = cli.run_sync({ "comments", id }, { json = true })
    assert.is_true(ok)
    assert.equals(1, #comments)
    assert.equals("a comment\nwith two lines", comments[1].text)
    assert.is_string(comments[1].author)
    assert.is_string(comments[1].created_at)
  end)

  it("cleans up the throwaway database", function()
    config.setup({})
    vim.fn.delete(dir, "rf")
    assert.equals(0, vim.fn.isdirectory(dir))
  end)
end)
