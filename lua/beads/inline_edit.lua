-- Inline description editing inside the detail view's own float (M4/M5/M7/M9).
--
-- Two modes share one save core (`bd update --body-file -`, debounced
-- autosave, persistent undo, :w/:q intercepts):
--
--  * attach mode (view.editable_description=true, the default): the detail
--    view's main buffer IS the description editor for the whole life of the
--    float. M.attach(buf, issue, opts) wires the save machinery onto the
--    view-owned buffer; M.set_issue(issue) re-targets it when the view
--    navigates to another issue (dep-jump/back) or refreshes. Quit verbs
--    (:q/:wq/ZZ/…) call opts.on_quit so the view closes the float.
--
--  * swap mode (legacy, view.editable_description=false): enter(ctx) swaps an
--    `acwrite` buffer INTO the detail window over the read-only view, and
--    exit() restores it. Because the edit buffer is a separate buffer, the
--    detail view's normal-mode handlers simply do not exist on it — the "gate
--    every view handler while editing" requirement (M4) is satisfied
--    structurally rather than with a flag.
--
-- The view passes callbacks via ctx/opts so this module never depends on
-- beads.view (no require cycle).

local cli = require("beads.cli")
local config = require("beads.config")
local util = require("beads.util")

local M = {}

-- Single active editor (the view owns one float at a time).
-- active = { mode = "swap"|"attach", win, view_buf, edit_buf, issue, ctx,
--            timer, undofile, saving, dirty_again, after_save, on_quit }
local active = nil

--- True while an inline edit submode is open (swap mode) or an editor is
--- attached (attach mode).
---@return boolean
function M.is_active()
  return active ~= nil
end

--- Id of the issue the active editor targets, or nil.
---@return string|nil
function M.current_id()
  return active and active.issue and active.issue.id or nil
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
  -- capture the issue NOW: attach mode can re-target the buffer to another
  -- issue (set_issue) while this write is in flight
  local target = active.issue
  local id = target.id
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
      -- only clear the flag when the buffer still shows the saved issue
      if active.issue == target and vim.api.nvim_buf_is_valid(buf) then
        vim.bo[buf].modified = false
      end
      target.description = body
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

-- Replace the buffer's content without recording the swap in its undo tree
-- (undolevels=-1 trick). Used on issue switch so `u` can never resurrect a
-- DIFFERENT issue's description and then autosave it into this one.
local function set_lines_no_undo(buf, lines)
  local saved = vim.bo[buf].undolevels
  vim.bo[buf].undolevels = -1
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].undolevels = saved
end

local function restore_undo(buf, undofile)
  if config.get().edit.persistent_undo then
    vim.api.nvim_buf_call(buf, function()
      pcall(vim.cmd, "silent! rundo " .. vim.fn.fnameescape(undofile))
    end)
  end
end

--- Point the attached editor at `issue`: flush any unsaved text of the
--- previous issue, swap the buffer content/name/undo over, and mark the
--- buffer clean. Also used for same-issue refreshes (content reload).
---@param issue table normalized issue
function M.set_issue(issue)
  if not active then
    return
  end
  local buf = active.edit_buf
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    return
  end
  local switching = active.issue and active.issue.id ~= issue.id
  if switching then
    if vim.bo[buf].modified then
      if active.saving then
        -- a save is already in flight: the coalescing queue would only
        -- capture the body AFTER the swap below replaced it — ship this
        -- issue's body directly instead so the edit can't be lost
        local old_id = active.issue.id
        cli.run_stdin({ "update", old_id, "--body-file", "-" }, body_of(buf), function(ok)
          if ok then
            util.emit("BeadsIssueUpdated", { id = old_id, action = "update" })
          end
        end)
      else
        do_save() -- body captured synchronously; write completes in flight
      end
    end
    persist_undo(buf, active.undofile)
    active.undofile = undo_path(issue.id)
    pcall(vim.api.nvim_buf_set_name, buf, ("beads://%s/description"):format(issue.id))
    set_lines_no_undo(buf, description_lines(issue))
    restore_undo(buf, active.undofile)
  else
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, description_lines(issue))
  end
  active.issue = issue
  vim.bo[buf].modified = false
end

--- Attach the description editor to a buffer the view owns (attach mode).
--- The buffer becomes the issue's description for the float's whole life;
--- quit verbs (:q/:wq/ZZ/…) call opts.on_quit instead of restoring a view
--- buffer. Content/undo are loaded for `issue` immediately.
---@param buf integer
---@param issue table normalized issue
---@param opts { on_quit: fun()|nil }|nil
function M.attach(buf, issue, opts)
  if active then
    return
  end
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    return
  end
  active = {
    mode = "attach",
    edit_buf = buf,
    issue = issue,
    undofile = undo_path(issue.id),
    on_quit = opts and opts.on_quit,
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

  set_lines_no_undo(buf, description_lines(issue))
  restore_undo(buf, active.undofile)
  vim.bo[buf].modified = false
end

--- Save now (attach mode helper for the view's close path). cb(ok) once the
--- buffer is in sync; a clean buffer succeeds immediately.
---@param cb fun(ok: boolean)|nil
function M.save(cb)
  do_save(cb)
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
    mode = "swap",
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
    pcall(function()
      a.timer:stop()
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
--- us, e.g. the view's WinClosed reset). No restore, no on_exit. Attach mode
--- flushes unsaved text first — the float closing must not lose typed work.
function M.abort()
  if not active then
    return
  end
  if
    active.mode == "attach"
    and active.edit_buf
    and vim.api.nvim_buf_is_valid(active.edit_buf)
    and vim.bo[active.edit_buf].modified
  then
    do_save() -- body captured synchronously; the write completes in flight
  end
  local a = teardown()
  -- swap mode: enter() set view_buf to bufhidden=hide so it survives the
  -- buffer swap; the window is now gone, so nothing will ever wipe it. Delete
  -- it explicitly to avoid leaking one hidden scratch buffer per aborted edit
  -- (mirrors exit(), which restores view_buf to the window instead).
  if a and a.view_buf and vim.api.nvim_buf_is_valid(a.view_buf) then
    pcall(vim.api.nvim_buf_delete, a.view_buf, { force = true })
  end
end

-- Leave the editor: swap mode restores the read-only detail view; attach mode
-- hands control back to the view (which closes the float).
local function leave()
  if active and active.mode == "attach" then
    local on_quit = active.on_quit
    -- keep `active` set: the view's close path (WinClosed -> abort) does the
    -- actual teardown, and a cleared modified flag means abort won't re-save.
    if active.edit_buf and vim.api.nvim_buf_is_valid(active.edit_buf) then
      pcall(function()
        vim.bo[active.edit_buf].modified = false
      end)
    end
    if on_quit then
      on_quit()
    end
  else
    M.exit()
  end
end

-- :w — save and stay in the editor.
function M.cmd_write()
  do_save()
end

-- :wq / :x — save then leave.
function M.cmd_save_exit()
  do_save(function()
    leave()
  end)
end

-- :q — leave; saves first unless edit.discard_on_quit.
function M.cmd_quit()
  if config.get().edit.discard_on_quit then
    leave()
  else
    do_save(function()
      leave()
    end)
  end
end

-- :q! / ZQ — leave without saving.
function M.cmd_discard_exit()
  leave()
end

return M
