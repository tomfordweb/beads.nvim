local cli = require("beads.cli")
local config = require("beads.config")
local events = require("beads.events")

describe("beads.events", function()
  local spawned -- every follower the fake runner started
  local refreshes
  local orig = {}

  local function fake_runner(argv, sys_opts, on_exit)
    local proc = { argv = argv, sys_opts = sys_opts, on_exit = on_exit, killed = false }
    function proc:kill()
      self.killed = true
    end
    table.insert(spawned, proc)
    return proc
  end

  local function drain(ms)
    vim.wait(ms or 60, function()
      return false
    end, 5)
  end

  local function record(seq, ts, extra)
    local rec = vim.tbl_extend("force", {
      seq = seq,
      ts = ts,
      op = "update",
      issue_id = "bd-" .. seq,
      issue = { id = "bd-" .. seq, status = "open" },
    }, extra or {})
    return vim.json.encode(rec) .. "\n"
  end

  local FUTURE = "2999-01-01T00:00:00Z"
  local PAST = "2000-01-01T00:00:00Z"

  before_each(function()
    events._reset()
    config.setup({ cwd = "/tmp/ws", events = { enabled = true, debounce_ms = 10 } })
    spawned, refreshes = {}, 0
    cli._runner = fake_runner
    for _, name in ipairs({ "beads.view", "beads.board", "beads.wisps" }) do
      local mod = require(name)
      orig[name] = mod.refresh
      mod.refresh = function()
        refreshes = refreshes + 1
      end
    end
  end)

  after_each(function()
    events._reset()
    for name, fn in pairs(orig) do
      require(name).refresh = fn
    end
    config.setup({})
  end)

  it("does nothing unless enabled", function()
    config.setup({ cwd = "/tmp/ws" })
    events.ensure()
    assert.equals(0, #spawned)
    assert.is_false(events.is_running())
  end)

  it("starts one follower from seq 0 with a stdin pipe", function()
    events.ensure()
    events.ensure()
    assert.equals(1, #spawned)
    assert.same({
      "bd",
      "events",
      "tail",
      "--since",
      "0",
      "--follow",
      "--exit-on-stdin-eof",
      "--json",
    }, spawned[1].argv)
    assert.is_true(spawned[1].sys_opts.stdin)
    assert.equals("/tmp/ws", spawned[1].sys_opts.cwd)
  end)

  it("refreshes open views once per burst of live records", function()
    local got
    local id = vim.api.nvim_create_autocmd("User", {
      pattern = "BeadsEventsChanged",
      callback = function(ev)
        got = ev.data
      end,
    })
    events.ensure()
    spawned[1].sys_opts.stdout(nil, record(1, FUTURE) .. record(2, FUTURE))
    drain()
    vim.api.nvim_del_autocmd(id)
    assert.equals(3, refreshes) -- view + board + wisps, once each
    assert.equals(2, #got.events)
    assert.equals(2, got.seq)
    assert.equals("bd-1", got.events[1].issue_id)
  end)

  it("reassembles records split across chunks", function()
    events.ensure()
    local line = record(7, FUTURE)
    spawned[1].sys_opts.stdout(nil, line:sub(1, 20))
    spawned[1].sys_opts.stdout(nil, line:sub(21))
    drain()
    assert.equals(3, refreshes)
    assert.equals(7, events._state.seq)
  end)

  it("replayed history advances the checkpoint without refreshing", function()
    events.ensure()
    spawned[1].sys_opts.stdout(nil, record(1, PAST) .. record(2, PAST))
    drain()
    assert.equals(0, refreshes)
    assert.equals(2, events._state.seq)
  end)

  it("goes quiet when bd has no events command or the journal is off", function()
    events.ensure()
    spawned[1].on_exit({ code = 1, stderr = 'Error: unknown command "events" for "bd"' })
    drain()
    assert.is_false(events.is_running())
    events.ensure()
    assert.equals(1, #spawned) -- no retry in this workspace
  end)

  it("resumes from head and rebuilds after a truncation error", function()
    events.ensure()
    spawned[1].sys_opts.stdout(nil, record(12, FUTURE))
    drain()
    refreshes = 0
    spawned[1].sys_opts.stdout(
      nil,
      '{"code":"events_journal_truncated","error":"x","floor":41,"head":980,"since":12}\n'
    )
    spawned[1].on_exit({ code = 1, stderr = "" })
    drain()
    assert.equals(2, #spawned)
    assert.equals("980", spawned[2].argv[5])
    assert.equals(3, refreshes)
  end)

  it("restarts for a new workspace and kills the old follower", function()
    events.ensure()
    config.merge({ cwd = "/tmp/other" })
    events.ensure()
    assert.equals(2, #spawned)
    assert.is_true(spawned[1].killed)
    assert.equals("/tmp/other", spawned[2].sys_opts.cwd)
  end)

  it("stop kills the follower and ignores its late output", function()
    events.ensure()
    local proc = spawned[1]
    events.stop()
    assert.is_true(proc.killed)
    proc.sys_opts.stdout(nil, record(1, FUTURE))
    drain()
    assert.equals(0, refreshes)
  end)
end)
