-- Live refresh from the bd events journal (bd >= 1.3.0, opt-in per
-- workspace with `bd config set events-journal true`).
--
-- One `bd events tail --follow` process per Neovim instance streams the
-- ordered change journal. Each new record schedules a debounced refresh of
-- whichever views are open, so a bead changed by another agent or terminal
-- shows up without pressing the refresh key.
--
-- The journal has no "start from head" option, so the follower starts at seq 0
-- and replays what is retained. Replayed records only advance the checkpoint;
-- a record counts as live when its timestamp is not older than the follower.

local cli = require("beads.cli")
local config = require("beads.config")
local util = require("beads.util")

local M = {}

local MAX_RESTARTS = 3
local RESTART_DELAY_MS = 2000
-- how long a workspace that refused the journal is left alone before the next
-- view open tries again (so enabling the journal needs no Neovim restart)
local RETRY_MS = 30000
local STDERR_KEEP = 4096
local EOF_FLAG = "--exit-on-stdin-eof"

local state = {
  handle = nil, -- running follower
  cwd = nil, -- workspace the follower watches
  gen = 0, -- bumped on every start/stop; stale callbacks compare and bail
  seq = 0, -- highest journal seq seen (the checkpoint)
  seq_resumed = false, -- following from a checkpoint: nothing is a replay
  buf = "", -- partial stdout line carried between chunks
  err = "", -- tail of the follower's stderr
  stdin_eof = true, -- bd accepts --exit-on-stdin-eof (newer than 1.3.x)
  got_output = false, -- follower produced at least one record
  started_at = nil, -- UTC second the first follower started, for replay detection
  pending = {}, -- live records waiting for the debounce
  timer = nil,
  restarts = 0,
  truncated_head = nil, -- head reported by a truncation error
  unsupported = {}, -- cwd -> { at, reason } once bd refused the journal there
}

local function opts()
  return config.get().events or {}
end

local function stop_timer()
  if state.timer then
    state.timer:stop()
    state.timer:close()
    state.timer = nil
  end
end

--- Refresh every open view. Each refresh is a no-op when its view is closed.
local function refresh_views()
  for _, name in ipairs({ "beads.view", "beads.board", "beads.wisps" }) do
    local ok, err = pcall(function()
      require(name).refresh()
    end)
    if not ok then
      util.debug(("events: %s refresh failed: %s"):format(name, tostring(err)))
    end
  end
end

local function flush()
  stop_timer()
  local records = state.pending
  state.pending = {}
  if #records == 0 then
    return
  end
  util.emit("BeadsEventsChanged", { events = records, seq = state.seq })
  refresh_views()
end

local function schedule_flush()
  stop_timer()
  state.timer = vim.uv.new_timer()
  state.timer:start(opts().debounce_ms or 200, 0, vim.schedule_wrap(flush))
end

--- A replayed record is one written before the follower started.
---@param ts string|nil
local function is_replay(ts)
  if state.seq_resumed or type(ts) ~= "string" or not state.started_at then
    return false
  end
  return ts:sub(1, 19) < state.started_at
end

---@param line string
local function handle_line(line)
  if line == "" then
    return
  end
  -- fast path: skip the JSON decode for replayed history
  local seq = tonumber(line:match('^{"seq":(%d+)'))
  if seq and is_replay(line:match('"ts":"([^"]+)"')) then
    state.got_output = true
    state.seq = math.max(state.seq, seq)
    return
  end
  local ok, rec = pcall(vim.json.decode, line, { luanil = { object = true, array = true } })
  if not ok or type(rec) ~= "table" then
    return
  end
  if rec.code == "events_journal_truncated" then
    -- the checkpoint fell out of the retained window: resume from head and
    -- rebuild the views from current state
    state.truncated_head = tonumber(rec.head) or 0
    return
  end
  if type(rec.seq) ~= "number" then
    return
  end
  state.got_output = true
  state.restarts = 0
  state.seq = math.max(state.seq, rec.seq)
  if is_replay(rec.ts) then
    return
  end
  table.insert(state.pending, rec)
  schedule_flush()
end

---@param data string
local function handle_chunk(data)
  local text = state.buf .. data
  local start = 1
  while true do
    local nl = text:find("\n", start, true)
    if not nl then
      break
    end
    handle_line(text:sub(start, nl - 1))
    start = nl + 1
  end
  state.buf = text:sub(start)
end

local start

--- Stop following this workspace for a while; `reason` is shown by
--- :checkhealth.
---@param reason string
local function give_up(reason)
  state.unsupported[state.cwd] = { at = vim.uv.now(), reason = reason }
  util.debug("events: " .. reason)
  M.stop()
end

---@param data string
local function handle_stderr(data)
  state.err = (state.err .. data):sub(-STDERR_KEEP)
  -- with the journal off, `--follow` prints a note and then idles forever
  if state.err:find("events journal is disabled", 1, true) then
    give_up("events journal is disabled (bd config set events-journal true)")
  end
end

---@param out { code: integer, stderr: string|nil }
local function handle_exit(out)
  state.handle = nil
  handle_line(state.buf)
  state.buf = ""
  local err = state.err .. (out.stderr or "")
  state.err = ""
  for line in err:gmatch("[^\n]+") do
    if line:find("events_journal_truncated", 1, true) then
      handle_line(line)
    end
  end

  if state.truncated_head then
    local head = state.truncated_head
    state.truncated_head = nil
    state.seq = head
    state.seq_resumed = true
    start(state.cwd)
    refresh_views()
    return
  end

  if state.stdin_eof and err:find("unknown flag: " .. EOF_FLAG, 1, true) then
    -- bd 1.3.x has the journal but not this flag; M.stop on VimLeavePre
    -- covers it instead
    state.stdin_eof = false
    start(state.cwd)
    return
  end

  if not state.got_output and out.code ~= 0 then
    -- bd older than 1.3.0 has no `events` command: stay quiet
    give_up(("bd events unavailable (exit %d): %s"):format(out.code, vim.trim(err)))
    return
  end

  state.restarts = state.restarts + 1
  if state.restarts > MAX_RESTARTS then
    util.debug("events: follower keeps exiting; giving up")
    return
  end
  local gen, cwd = state.gen, state.cwd
  vim.defer_fn(function()
    if gen == state.gen and not state.handle then
      state.seq_resumed = state.seq > 0
      start(cwd)
    end
  end, RESTART_DELAY_MS)
end

---@param cwd string
start = function(cwd)
  state.gen = state.gen + 1
  local gen = state.gen
  state.cwd = cwd
  state.buf, state.err = "", ""
  state.started_at = state.started_at or os.date("!%Y-%m-%dT%H:%M:%S")
  local args = { "events", "tail", "--since", tostring(state.seq), "--follow", "--json" }
  if state.stdin_eof then
    table.insert(args, EOF_FLAG)
  end
  state.handle = cli.spawn_stream(args, {
    cwd = cwd,
    on_stderr = function(data)
      vim.schedule(function()
        if gen == state.gen then
          handle_stderr(data)
        end
      end)
    end,
    on_stdout = function(data)
      vim.schedule(function()
        if gen == state.gen then
          handle_chunk(data)
        end
      end)
    end,
    on_exit = function(out)
      vim.schedule(function()
        if gen == state.gen then
          handle_exit(out)
        end
      end)
    end,
  })
end

--- Stop the follower (no-op when none is running).
function M.stop()
  state.gen = state.gen + 1
  stop_timer()
  state.pending = {}
  if state.handle then
    pcall(function()
      state.handle:kill("sigterm")
    end)
    state.handle = nil
  end
end

--- Make sure a follower is running for the current workspace. Called when a
--- view opens; cheap and idempotent. Does nothing unless `events.enabled`.
function M.ensure()
  if not opts().enabled then
    return
  end
  local cwd = cli.resolve_cwd()
  if state.handle and state.cwd == cwd then
    return
  end
  local refused = state.unsupported[cwd]
  if refused and vim.uv.now() - refused.at < RETRY_MS then
    return
  end
  state.unsupported[cwd] = nil
  -- first start, or the workspace changed: each clone has its own sequence
  M.stop()
  state.seq, state.seq_resumed, state.started_at = 0, false, nil
  state.got_output, state.restarts, state.truncated_head = false, 0, nil
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("beads_events", { clear = true }),
    callback = M.stop,
  })
  start(cwd)
end

---@return boolean
function M.is_running()
  return state.handle ~= nil
end

--- Why the follower is not running in the current workspace, if bd refused.
---@return string|nil
function M.reason()
  local refused = state.unsupported[cli.resolve_cwd()]
  return refused and refused.reason or nil
end

--- Test helper: drop every piece of follower state.
function M._reset()
  M.stop()
  state.cwd, state.seq, state.seq_resumed, state.started_at = nil, 0, false, nil
  state.got_output, state.restarts, state.truncated_head = false, 0, nil
  state.buf, state.err, state.unsupported, state.stdin_eof = "", "", {}, true
end

M._state = state

return M
