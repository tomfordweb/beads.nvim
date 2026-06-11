-- Inline description editing inside the detail view's own float (M4/M5/M7/M9).
--
-- Instead of opening a second, overlapping modal (the old beads.edit float),
-- the description is edited in an `acwrite` buffer swapped INTO the detail
-- window. The detail buffer is hidden (not wiped) for the duration and
-- restored on exit, so there is never a nested window. Because the edit buffer
-- is a separate buffer, the detail view's normal-mode handlers simply do not
-- exist on it — the "gate every view handler while editing" requirement (M4)
-- is satisfied structurally rather than with a flag.
--
-- Lifecycle: enter(ctx) -> [edit, :w autosaves/saves] -> exit() restores the
-- detail view. The view passes callbacks via ctx so this module never depends
-- on beads.view (no require cycle).

local cli = require("beads.cli")
local config = require("beads.config")
local util = require("beads.util")

local M = {}

-- Single active submode (the view owns one float at a time).
-- active = { win, view_buf, edit_buf, issue, ctx, timer, undofile,
--            saving, dirty_again, after_save }
local active = nil

--- True while an inline edit submode is open.
---@return boolean
function M.is_active()
  return active ~= nil
end

local function undo_path(id)
  local dir = config.get().edit.undodir or (vim.fn.stdpath("state") .. "/beads/undo")
  vim.fn.mkdir(dir, "p")
  return dir .. "/" .. id:gsub("[/\\]", "_")
end

local function description_lines(issue)
  return vim.split(issue.description or "", "\n", { plain = true })
end

local function body_of(buf)
  return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
end

-- Persist the buffer's undo tree to `undofile`. bufhidden=wipe discards the
-- in-buffer undo history, so it is written out explicitly (M7). No-op unless
-- edit.persistent_undo is on.
local function persist_undo(buf, undofile)
  if not config.get().edit.persistent_undo then
    return
  end
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    return
  end
  vim.api.nvim_buf_call(buf, function()
    pcall(vim.cmd, "silent! wundo! " .. vim.fn.fnameescape(undofile))
  end)
end

local function save_undo(buf)
  if active then
    persist_undo(buf, active.undofile)
  end
end

-- Persist the description through `bd update --body-file -`. Serializes writes
-- (single in-flight; a change arriving mid-save is coalesced into one trailing
-- save) so autosave + :w can never interleave. cb(ok) runs once the buffer is
-- in sync (M7).
local function do_save(cb)
  if not active then
    if cb then
      cb(false)
    end
    return
  end
  local buf = active.edit_buf
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    if cb then
      cb(false)
    end
    return
  end
  if not vim.bo[buf].modified then
    if cb then
      cb(true)
    end
    return
  end
  if active.saving then
    active.dirty_again = true
    if cb then
      active.after_save = cb
    end
    return
  end

  active.saving = true
  local id = active.issue.id
  local body = body_of(buf)
  cli.run_stdin({ "update", id, "--body-file", "-" }, body, function(ok)
    if not active or active.edit_buf ~= buf then
      if cb then
        cb(ok)
      end
      return
    end
    active.saving = false
    if ok then
      if vim.api.nvim_buf_is_valid(buf) then
        vim.bo[buf].modified = false
      end
      active.issue.description = body
      save_undo(buf)
      util.emit("BeadsIssueUpdated", { id = id, action = "update" })
    end
    local again = active.dirty_again
    active.dirty_again = false
    local after = active.after_save
    active.after_save = nil
    if again then
      do_save(after or cb)
    elseif after then
      after(ok)
    elseif cb then
      cb(ok)
    end
  end)
end

local function schedule_autosave()
  local cfg = config.get().edit
  if not (active and cfg.autosave) then
    return
  end
  active.timer = active.timer or vim.uv.new_timer()
  active.timer:stop()
  active.timer:start(cfg.autosave_debounce_ms, 0, function()
    vim.schedule(function()
      if
        active
        and vim.api.nvim_buf_is_valid(active.edit_buf)
        and vim.bo[active.edit_buf].modified
      then
        do_save()
      end
    end)
  end)
end

-- :w / :wq / :q / :x intercepts so the editor's quit verbs return to the
-- read-only detail view instead of closing the whole float (M5). Buffer-local
-- command-line abbreviations keep muscle memory working; ZZ/ZQ mirror them.
local function setup_quit_maps(buf)
  vim.api.nvim_buf_call(buf, function()
    vim.cmd([[cnoreabbrev <buffer> w  lua require('beads.inline_edit').cmd_write()]])
    vim.cmd([[cnoreabbrev <buffer> wq lua require('beads.inline_edit').cmd_save_exit()]])
    vim.cmd([[cnoreabbrev <buffer> x  lua require('beads.inline_edit').cmd_save_exit()]])
    vim.cmd([[cnoreabbrev <buffer> q  lua require('beads.inline_edit').cmd_quit()]])
    vim.cmd([[cnoreabbrev <buffer> q! lua require('beads.inline_edit').cmd_discard_exit()]])
  end)
  vim.keymap.set("n", "ZZ", function()
    M.cmd_save_exit()
  end, { buffer = buf, nowait = true, silent = true, desc = "Beads: save + back" })
  vim.keymap.set("n", "ZQ", function()
    M.cmd_discard_exit()
  end, { buffer = buf, nowait = true, silent = true, desc = "Beads: discard + back" })
end

-- Neutralize disruptive global normal-mode maps (e.g. oil.nvim's "-") inside
-- the edit buffer only; insert mode is left untouched (M9).
local function apply_guard_keys(buf)
  for _, key in ipairs(config.get().edit.guard_keys or {}) do
    pcall(vim.keymap.set, "n", key, key, {
      buffer = buf,
      remap = false,
      nowait = true,
      desc = "Beads: guarded key (edit)",
    })
  end
end

--- Enter the inline edit submode for ctx.issue inside ctx.win.
---@param ctx { win: integer, view_buf: integer, issue: table, reconfigure: fun(opts: table), on_exit: fun() }
function M.enter(ctx)
  if active then
    return
  end
  if not (ctx and ctx.win and vim.api.nvim_win_is_valid(ctx.win)) then
    return
  end
  if not (ctx.view_buf and vim.api.nvim_buf_is_valid(ctx.view_buf)) then
    return
  end

  -- the detail buffer is normally bufhidden=wipe; keep it alive across the swap
  pcall(function()
    vim.bo[ctx.view_buf].bufhidden = "hide"
  end)

  local issue = ctx.issue
  local name = ("beads://%s/description"):format(issue.id)
  local stale = vim.fn.bufnr(name)
  if stale ~= -1 and vim.api.nvim_buf_is_valid(stale) then
    pcall(vim.api.nvim_buf_delete, stale, { force = true })
  end

  local buf = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_buf_set_name(buf, name)
  vim.bo[buf].buftype = "acwrite"
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].bufhidden = "wipe"
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, description_lines(issue))
  vim.bo[buf].modified = false

  active = {
    win = ctx.win,
    view_buf = ctx.view_buf,
    edit_buf = buf,
    issue = issue,
    ctx = ctx,
    undofile = undo_path(issue.id),
  }

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    callback = function()
      do_save()
    end,
  })
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    buffer = buf,
    callback = schedule_autosave,
  })

  setup_quit_maps(buf)
  apply_guard_keys(buf)

  vim.api.nvim_win_set_buf(ctx.win, buf)
  if ctx.reconfigure then
    ctx.reconfigure({ title = (" edit %s "):format(issue.id), pane = "view_edit" })
  end

  -- restore undo history (bufhidden=wipe discards the in-buffer undo tree)
  if config.get().edit.persistent_undo then
    vim.api.nvim_buf_call(buf, function()
      pcall(vim.cmd, "silent! rundo " .. vim.fn.fnameescape(active.undofile))
    end)
    vim.bo[buf].modified = false
  end

  util.info("bd: editing " .. issue.id .. "  (:w save · :wq save+back · :q back)")
end

-- Tear down submode bookkeeping (timer, final undo write). Returns the
-- captured state so callers can finish window restoration.
local function teardown()
  local a = active
  active = nil
  if not a then
    return nil
  end
  if a.timer then
    a.timer:stop()
    pcall(function()
      a.timer:close()
    end)
    a.timer = nil
  end
  persist_undo(a.edit_buf, a.undofile)
  return a
end

--- Leave the submode and restore the read-only detail view.
function M.exit()
  local a = teardown()
  if not a then
    return
  end
  -- Drop the modified flag so wiping the acwrite buffer never prompts
  -- "Save changes?": saved paths already cleared it; discard paths mean to
  -- throw the unsaved text away.
  if a.edit_buf and vim.api.nvim_buf_is_valid(a.edit_buf) then
    pcall(function()
      vim.bo[a.edit_buf].modified = false
    end)
  end
  if a.view_buf and vim.api.nvim_buf_is_valid(a.view_buf) then
    pcall(function()
      vim.bo[a.view_buf].bufhidden = "wipe"
    end)
    if a.win and vim.api.nvim_win_is_valid(a.win) then
      pcall(vim.api.nvim_win_set_buf, a.win, a.view_buf)
    end
  end
  if a.edit_buf and vim.api.nvim_buf_is_valid(a.edit_buf) then
    pcall(vim.api.nvim_buf_delete, a.edit_buf, { force = true })
  end
  if a.ctx and a.ctx.on_exit then
    a.ctx.on_exit()
  end
end

--- Tear down without touching windows (the float was closed out from under
--- us, e.g. the view's WinClosed reset). No restore, no on_exit.
function M.abort()
  teardown()
end

-- :w — save and stay in the submode.
function M.cmd_write()
  do_save()
end

-- :wq / :x — save then return to the detail view.
function M.cmd_save_exit()
  do_save(function()
    M.exit()
  end)
end

-- :q — return to the detail view; saves first unless edit.discard_on_quit.
function M.cmd_quit()
  if config.get().edit.discard_on_quit then
    M.exit()
  else
    do_save(function()
      M.exit()
    end)
  end
end

-- :q! / ZQ — return without saving.
function M.cmd_discard_exit()
  M.exit()
end

return M
