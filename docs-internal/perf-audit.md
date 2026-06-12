# M1 Resource-Lifecycle Audit

Final audit (M1) over the inline-edit (M4/M5/M7/M9), focus-resize (M2), graph
(M10), and hooks/custom-actions (M11) work. Goal: prove that floats, timers,
extmarks, async handles, and buffers/windows are created and destroyed in
balanced pairs, with no leak or unbounded growth across rapid open/close and
externally-driven teardown.

## Scope / surface audited

- **Autocmds & augroups** — per-window `beads_float_resize_<win>` augroups and
  every `WinClosed` callback across view, sidebar, graphview, history, palette.
- **vim.uv timers** — the inline-edit autosave timer (lazy-init, stop+close on
  every exit/abort path).
- **Extmarks & namespaces** — `render`/`float.apply_highlights` and all callers
  (view, sidebar, graphview, history, picker).
- **Async handles** — `cli.lua` `vim.system` spawns and their callbacks.
- **Buffer & window lifecycle** — detail/edit/scratch buffer `bufhidden`
  states, the view↔edit buffer swap, `win_set_config` churn.

## Findings

### Fixed

- **Hidden scratch-buffer leak in `inline_edit.M.abort`** (`lua/beads/inline_edit.lua:307`)
  — When the view float was force-closed while an inline edit was active
  (another plugin closing the window, `:q!` from outside, terminal close), the
  view window's `WinClosed` fired → `reset_state` → `abort()` → `teardown()`.
  `teardown()` stopped/closed the timer and nil'd `active` but never touched
  `view_buf`. `enter()` had flipped `view_buf` to `bufhidden=hide` so it would
  survive the buffer swap; with the window now gone there was nothing left to
  trigger a wipe, and no Lua reference once `reset_state` nil'd `state.buf`. The
  result: one orphaned hidden `nofile` scratch buffer leaked per externally
  -closed-during-edit session. (The `edit_buf` is safe — it is `bufhidden=wipe`
  and was displayed in the closed window, so Neovim wipes it as part of
  `nvim_win_close`.) The audit raised this as two findings; they were the same
  leak.

  *Resolution:* `M.abort()` now captures `teardown()`'s returned state snapshot
  and force-deletes `view_buf` when valid (`nvim_buf_is_valid` +
  `pcall(nvim_buf_delete, ..., {force=true})`). This mirrors `exit()`, which
  restores `view_buf` to the window instead of deleting it. Force-delete is
  safe because the window is already gone — there is nothing to restore to, and
  `teardown()` nils `state` before returning, so there is no double-close path.

- **Asymmetric timer teardown in `inline_edit` `teardown()`** (`lua/beads/inline_edit.lua:265`)
  — `a.timer:stop()` was a bare call *outside* the `pcall` that wrapped
  `a.timer:close()`. If a future libuv contract (or a handle closed externally)
  ever made `stop()` throw on an already-stopped timer, the uncaught error
  would abort `teardown()` before `persist_undo` ran.

  *Resolution:* Both calls are now wrapped together in a single `pcall` so a
  `stop()` error can no longer abort teardown. Functionally identical on the
  happy path.

### Skipped (false positive / out of scope)

- **Discarded highlight specs in `picker.issue_previewer`** (`lua/beads/picker.lua:85`)
  — `render.detail_lines(issue)` returns `(lines, hls)`; the previewer uses only
  `lines`, so the Telescope preview renders plain (uncoloured) markdown while
  the view float and sidebar are highlighted. This is **not a resource leak** —
  it is a cosmetic functional gap. Adding highlighting would be an out-of-scope
  behaviour change for a lifecycle audit. Documented for a future contributor:
  if added, call `float.apply_highlights(self.state.bufnr, 'beads_picker_preview', hls)`
  after `set_lines` and rely on the existing clear-before-apply to handle
  Telescope's `self.state.bufnr` reuse.

### Confirmed clean

- **`float.auto_resize`** (`lua/beads/float.lua:128-163`) — augroup
  `beads_float_resize_<win>` is created with `{ clear = true }` (handles the
  degenerate win-ID-reuse case); the inner `WinClosed` is `once = true`, pattern
  -matched to the exact window ID, and self-deletes the augroup via
  `pcall(nvim_del_augroup_by_id)`. `VimResized`/`FocusGained`/`VimResume` live
  inside the augroup and die with it; their handler guards with
  `nvim_win_is_valid` before `set_config`, so delayed delivery to a stale win is
  a no-op. Exactly-once cleanup across rapid open/close.
- **View `ensure_float` `WinClosed`** (`lua/beads/view.lua:586-590`) —
  `once = true` + `pattern = tostring(state.win)`, gated behind `is_open()`, so
  it can't register a second copy while the float is valid. Two `WinClosed`
  callbacks exist for `state.win` (this one's `reset_state` and
  `auto_resize`'s augroup deletion); both are `once = true` and independent, so
  firing order doesn't matter.
- **Sidebar `ensure_win` `WinClosed`** (`lua/beads/sidebar.lua:88-116`) —
  `once = true`, pattern-matched; `M.close()` is idempotent (`is_open()` guard).
  Buffer is `bufhidden=wipe`, so it is wiped when its window closes externally
  or via `close()`. Double-nil of `state.win`/`state.buf` is harmless.
- **Inline-edit autosave timer** (`lua/beads/inline_edit.lua:139-148, 258-273`)
  — lazy-init only when `active` is set; `teardown()` sets `active = nil`
  *before* stop/close, so any already-enqueued `vim.schedule` callback sees
  `active == nil` and no-ops. `a.timer` is nil'd immediately after close. Single
  teardown path unconditionally stops+closes when the timer exists — no leak, no
  double-close.
- **Inline-edit buffer-local autocmds** (`lua/beads/inline_edit.lua:226-235`) —
  `BufWriteCmd` and `TextChanged`/`TextChangedI` are registered with
  `buffer = buf` on the `bufhidden=wipe` edit buffer. The buffer wipe (explicit
  in `exit()`, or Neovim's own wipe in the `abort()` path) destroys all
  buffer-local autocmds. No manual deletion needed.
- **`render`/`float.apply_highlights` + all callers** (`lua/beads/float.lua:107-118`)
  — `nvim_create_namespace` is idempotent (same name → same id; the global
  registry grows zero entries after first load). `nvim_buf_clear_namespace` runs
  before every set-extmark loop, so extmark count is bounded by the current
  render's line count and never accumulates across refreshes. The long-lived
  view/sidebar buffers re-clear on every `set_content`/`open`; short-lived
  graphview/history/palette buffers are `bufhidden=wipe` and free their extmarks
  on close.
- **Inline-edit extmarks** — `inline_edit` creates no extmarks/namespaces.
  During the submode, `view.refresh()` returns early (`is_active()` guard), so
  `beads_view` extmarks on the hidden `view_buf` are untouched; on exit,
  `set_content`→`apply_highlights` clears and re-applies from scratch.
- **`cli.lua` async** (`lua/beads/cli.lua:49-70`) — every `vim.system` `on_exit`
  callback is `vim.schedule`-wrapped (runs on the main thread). The returned
  `SystemObj` is discarded (fire-and-forget), so handles do not accumulate.
  `run_sync` uses `:wait()` and is only called from the Telescope live-search
  finder.
- **Graphview / history / palette floats** (`lua/beads/graphview.lua`,
  `lua/beads/history.lua`, `lua/beads/palette.lua`) — no module-level win/buf
  state; win/buf locals live in the `open()` closure and are GC'd after
  `WinClosed`. `bufhidden=wipe` guarantees cleanup; `auto_resize` installs the
  `once = true` augroup-deletion per float.

## Invariants to preserve (for future contributors)

1. **Every float that calls `float.auto_resize` must let it own resize cleanup.**
   Do not add a second resize augroup or a non-`once` `WinClosed`; rely on the
   `beads_float_resize_<win>` augroup with `clear = true`.
2. **Any `WinClosed`/`BufWinLeave` autocmd tied to a specific window must be
   `once = true` and `pattern`-matched to that window's ID** (or buffer-local).
   No broadcast `WinClosed` without an ID/buffer filter.
3. **vim.uv timers: stop+close together inside one `pcall`, then nil the handle.**
   Set the owning state (`active`) to `nil` *before* stopping so any enqueued
   `vim.schedule` callback short-circuits. Re-check that state at the top of the
   scheduled callback.
4. **`bufhidden=hide` buffers must have an explicit owner that deletes them.**
   If you flip a buffer to `hide` to survive a window/buffer swap (as `enter()`
   does for `view_buf`), every teardown path must either restore it to a window
   (`exit()`) or delete it (`abort()`). A `hide` buffer with no window and no
   reference leaks for the session.
5. **Prefer `bufhidden=wipe` for transient float buffers** (edit, graphview,
   history, palette, sidebar) so window close auto-wipes the buffer and its
   buffer-local autocmds and extmarks.
6. **Always `nvim_buf_clear_namespace(buf, ns, 0, -1)` before re-applying
   extmarks.** Reuse a fixed namespace name (idempotent id); never create a
   per-render namespace.
7. **`vim.system` callbacks must be `vim.schedule`-wrapped**, and the returned
   handle must not be retained (fire-and-forget) unless you also cancel/close it.

## Verification

- `stylua lua tests plugin` then `stylua --check lua tests plugin` — clean
  (exit 0, no output).
- Full plenary suite — 15 spec files, 169 tests, **0 failures, 0 errors**
  (no line matches `Failed : [1-9]` or `Errors : [1-9]`).
- Diff is two minimal edits to `lua/beads/inline_edit.lua` (timer `stop()`
  moved inside the existing `pcall`; `M.abort()` deletes `view_buf`). No
  behaviour change outside the two stated leak-plugging paths.
