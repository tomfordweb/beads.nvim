-- Async/sync runner around the bd binary. The only module that spawns
-- processes; everything else goes through here so tests can inject a fake.

local config = require("beads.config")

local M = {}

--- Default process runner; swappable for tests via M._runner or config.runner.
---@param argv string[]
---@param sys_opts table
---@param on_exit fun(out: { code: integer, stdout: string|nil, stderr: string|nil })
M._runner = function(argv, sys_opts, on_exit)
  return vim.system(argv, sys_opts, on_exit)
end

local function runner()
  return config.get().runner or M._runner
end

--- Directory bd commands run in. Walks up from the current buffer so the
--- `.beads` db is found even when nvim's cwd is elsewhere.
---@return string
function M.resolve_cwd()
  local cfg = config.get()
  return cfg.cwd or vim.fs.root(0, ".beads") or vim.uv.cwd()
end

---@param args string[]
---@return string[]
local function argv_for(args)
  local argv = { config.get().bd_bin }
  vim.list_extend(argv, args)
  return argv
end

---@param args string[] argv tail (without bd binary)
---@param input string|nil stdin payload
---@param decode_json boolean
---@param quiet boolean|nil suppress the error notification (caller handles it)
---@param cb fun(ok: boolean, result: any, err: string|nil)
local function run(args, input, decode_json, quiet, cb)
  local argv = argv_for(args)
  if decode_json then
    table.insert(argv, "--json")
  end
  local sys_opts = { cwd = M.resolve_cwd(), text = true }
  if input ~= nil then
    sys_opts.stdin = input
  end
  runner()(argv, sys_opts, function(out)
    vim.schedule(function()
      if out.code ~= 0 then
        local err = out.stderr or ""
        if not quiet then
          vim.notify(("bd %s failed:\n%s"):format(args[1] or "", err), vim.log.levels.ERROR)
        end
        cb(false, nil, err)
        return
      end
      if not decode_json then
        cb(true, out.stdout or "")
        return
      end
      local ok, decoded = pcall(vim.json.decode, out.stdout or "")
      if not ok then
        local err = "bd returned invalid JSON: " .. tostring(decoded)
        if not quiet then
          vim.notify(err, vim.log.levels.ERROR)
        end
        cb(false, nil, err)
        return
      end
      cb(true, decoded)
    end)
  end)
end

--- Run bd with --json appended; cb receives the decoded value.
---@param args string[]
---@param cb fun(ok: boolean, result: any, err: string|nil)
---@param opts { quiet: boolean|nil }|nil quiet skips the failure notification
function M.run_json(args, cb, opts)
  run(args, nil, true, opts and opts.quiet, cb)
end

--- Run bd without --json; cb receives raw stdout.
---@param args string[]
---@param cb fun(ok: boolean, stdout: string|nil, err: string|nil)
function M.run_plain(args, cb)
  run(args, nil, false, nil, cb)
end

--- Run bd with stdin payload (e.g. `update <id> --body-file -`).
---@param args string[]
---@param input string
---@param cb fun(ok: boolean, stdout: string|nil, err: string|nil)
function M.run_stdin(args, input, cb)
  run(args, input, false, nil, cb)
end

--- Synchronous variant for tests and simple scripts. Bounded by
--- `sync_timeout_ms` so a hung bd (e.g. a Dolt lock) can never freeze the
--- editor indefinitely — :wait(timeout) kills the process on expiry.
---@param args string[]
---@param opts { json: boolean|nil, input: string|nil, cwd: string|nil, timeout: integer|nil }|nil
---@return boolean ok, any result, string|nil err
function M.run_sync(args, opts)
  opts = opts or {}
  local argv = argv_for(args)
  if opts.json then
    table.insert(argv, "--json")
  end
  local sys_opts = { cwd = opts.cwd or M.resolve_cwd(), text = true }
  if opts.input ~= nil then
    sys_opts.stdin = opts.input
  end
  local timeout = opts.timeout or config.get().sync_timeout_ms
  local out = vim.system(argv, sys_opts):wait(timeout)
  -- :wait(timeout) kills the process with SIGKILL and reports code 124
  if out.code == 124 and out.signal == 9 then
    return false, nil, ("bd %s timed out after %dms"):format(args[1] or "", timeout)
  end
  if out.code ~= 0 then
    return false, nil, out.stderr
  end
  if not opts.json then
    return true, out.stdout or ""
  end
  local ok, decoded = pcall(vim.json.decode, out.stdout or "")
  if not ok then
    return false, nil, "invalid JSON: " .. tostring(decoded)
  end
  return true, decoded
end

return M
