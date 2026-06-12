-- Drives the inline description editor (M4/M5/M7/M9) against real windows and
-- buffers with a fake bd runner, so no bd binary is needed.

local inline = require("beads.inline_edit")
local config = require("beads.config")

describe("beads.inline_edit", function()
  local captured
  local open = {} -- windows/buffers to clean up

  local function fake_runner(argv, opts, on_exit)
    table.insert(captured, { argv = argv, stdin = opts.stdin })
    on_exit({ code = 0, stdout = "", stderr = "" })
  end

  local function setup(extra_edit)
    config.setup({ runner = fake_runner, edit = extra_edit or {} })
  end

  local function make_ctx(issue)
    local view_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[view_buf].bufhidden = "wipe"
    vim.api.nvim_buf_set_lines(view_buf, 0, -1, false, { "# " .. issue.title, issue.id })
    local win = vim.api.nvim_open_win(view_buf, true, {
      relative = "editor",
      row = 1,
      col = 1,
      width = 40,
      height = 10,
    })
    table.insert(open, { win = win, buf = view_buf })
    return {
      win = win,
      view_buf = view_buf,
      issue = issue,
      reconfigure = function() end,
      on_exit = function() end,
    }
  end

  before_each(function()
    captured = {}
    setup()
  end)

  after_each(function()
    inline.abort()
    for _, o in ipairs(open) do
      pcall(vim.api.nvim_win_close, o.win, true)
      if vim.api.nvim_buf_is_valid(o.buf) then
        pcall(vim.api.nvim_buf_delete, o.buf, { force = true })
      end
    end
    open = {}
    config.setup({})
  end)

  local function update_calls()
    local out = {}
    for _, c in ipairs(captured) do
      if c.argv[2] == "update" then
        table.insert(out, c)
      end
    end
    return out
  end

  it("swaps an editable, description-only buffer into the same window (M4)", function()
    local ctx = make_ctx({ id = "beads_nvim-x9s", title = "T", description = "line one\nline two" })
    inline.enter(ctx)
    assert.is_true(inline.is_active())
    local cur = vim.api.nvim_win_get_buf(ctx.win)
    assert.are_not.equals(ctx.view_buf, cur) -- a different buffer, same window
    assert.equals("acwrite", vim.bo[cur].buftype)
    assert.are.same({ "line one", "line two" }, vim.api.nvim_buf_get_lines(cur, 0, -1, false))
  end)

  it("deletes the hidden view buffer on abort — no leak (M1)", function()
    local ctx = make_ctx({ id = "beads_nvim-x9s", title = "T", description = "x" })
    inline.enter(ctx)
    assert.is_true(inline.is_active())
    -- enter() flipped view_buf to bufhidden=hide; simulate the float being
    -- force-closed out from under the submode (reset_state -> abort()).
    inline.abort()
    assert.is_false(inline.is_active())
    assert.is_false(vim.api.nvim_buf_is_valid(ctx.view_buf))
  end)

  it("sets filetype=markdown on the edit buffer (M6)", function()
    local ctx = make_ctx({ id = "beads_nvim-x9s", title = "T", description = "x" })
    inline.enter(ctx)
    local cur = vim.api.nvim_win_get_buf(ctx.win)
    assert.equals("markdown", vim.bo[cur].filetype)
  end)

  it("persists the edited body through bd update on :w (M5)", function()
    local ctx = make_ctx({ id = "beads_nvim-x9s", title = "T", description = "old" })
    inline.enter(ctx)
    local cur = vim.api.nvim_win_get_buf(ctx.win)
    vim.api.nvim_buf_set_lines(cur, 0, -1, false, { "new body" })
    vim.bo[cur].modified = true
    inline.cmd_write()
    vim.wait(200, function()
      return #update_calls() > 0
    end)
    local calls = update_calls()
    assert.equals(1, #calls)
    assert.equals("new body", calls[1].stdin)
    assert.is_true(inline.is_active(), ":w stays in the submode")
  end)

  it("saves then restores the detail buffer on :wq (M5)", function()
    local ctx = make_ctx({ id = "beads_nvim-x9s", title = "T", description = "old" })
    inline.enter(ctx)
    local cur = vim.api.nvim_win_get_buf(ctx.win)
    vim.api.nvim_buf_set_lines(cur, 0, -1, false, { "done" })
    vim.bo[cur].modified = true
    inline.cmd_save_exit()
    vim.wait(200, function()
      return not inline.is_active()
    end)
    assert.is_false(inline.is_active())
    assert.equals(ctx.view_buf, vim.api.nvim_win_get_buf(ctx.win))
    assert.equals(1, #update_calls())
  end)

  it("does not save an unchanged buffer on :q (M5)", function()
    local ctx = make_ctx({ id = "beads_nvim-x9s", title = "T", description = "keep" })
    inline.enter(ctx)
    inline.cmd_quit() -- discard_on_quit=false, but nothing changed
    vim.wait(200, function()
      return not inline.is_active()
    end)
    assert.is_false(inline.is_active())
    assert.equals(0, #update_calls())
  end)

  it("discards changes on :q when edit.discard_on_quit=true", function()
    setup({ discard_on_quit = true })
    local ctx = make_ctx({ id = "beads_nvim-x9s", title = "T", description = "old" })
    inline.enter(ctx)
    local cur = vim.api.nvim_win_get_buf(ctx.win)
    vim.api.nvim_buf_set_lines(cur, 0, -1, false, { "unsaved" })
    vim.bo[cur].modified = true
    inline.cmd_quit()
    vim.wait(200, function()
      return not inline.is_active()
    end)
    assert.equals(0, #update_calls())
  end)

  it("shadows configured guard_keys in the edit buffer only (M9)", function()
    setup({ guard_keys = { "-" } })
    local ctx = make_ctx({ id = "beads_nvim-x9s", title = "T", description = "x" })
    inline.enter(ctx)
    local cur = vim.api.nvim_win_get_buf(ctx.win)
    local guarded = false
    for _, m in ipairs(vim.api.nvim_buf_get_keymap(cur, "n")) do
      if m.lhs == "-" then
        guarded = true
      end
    end
    assert.is_true(guarded)
  end)

  it("autosaves after the debounce when edit.autosave=true (M7)", function()
    setup({ autosave = true, autosave_debounce_ms = 20 })
    local ctx = make_ctx({ id = "beads_nvim-x9s", title = "T", description = "old" })
    inline.enter(ctx)
    local cur = vim.api.nvim_win_get_buf(ctx.win)
    vim.api.nvim_buf_set_lines(cur, 0, -1, false, { "typed" })
    vim.bo[cur].modified = true
    vim.api.nvim_exec_autocmds("TextChangedI", { buffer = cur })
    vim.wait(400, function()
      return #update_calls() > 0
    end)
    assert.is_true(#update_calls() >= 1)
    assert.equals("typed", update_calls()[1].stdin)
  end)

  describe("attach mode (editable-description buffer)", function()
    local function make_attached(issue, opts)
      local buf = vim.api.nvim_create_buf(false, false)
      vim.bo[buf].buftype = "acwrite"
      pcall(vim.api.nvim_buf_set_name, buf, ("beads://%s/description"):format(issue.id))
      vim.bo[buf].bufhidden = "wipe"
      local win = vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        row = 1,
        col = 1,
        width = 40,
        height = 10,
      })
      table.insert(open, { win = win, buf = buf })
      inline.attach(buf, issue, opts)
      return buf, win
    end

    it("loads the description into the attached buffer, unmodified", function()
      local buf = make_attached({ id = "beads_nvim-a1", title = "T", description = "one\ntwo" })
      assert.is_true(inline.is_active())
      assert.equals("beads_nvim-a1", inline.current_id())
      assert.are.same({ "one", "two" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
      assert.is_false(vim.bo[buf].modified)
    end)

    it("persists through bd update on :w and stays attached", function()
      local buf = make_attached({ id = "beads_nvim-a1", title = "T", description = "old" })
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "new body" })
      vim.bo[buf].modified = true
      inline.cmd_write()
      vim.wait(200, function()
        return #update_calls() > 0 and not vim.bo[buf].modified
      end)
      assert.equals(1, #update_calls())
      assert.equals("new body", update_calls()[1].stdin)
      assert.equals("beads_nvim-a1", update_calls()[1].argv[3])
      assert.is_true(inline.is_active())
      assert.is_false(vim.bo[buf].modified)
    end)

    it(":wq saves then calls on_quit instead of restoring a view buffer", function()
      local quit = false
      local buf = make_attached({ id = "beads_nvim-a1", title = "T", description = "old" }, {
        on_quit = function()
          quit = true
        end,
      })
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "done" })
      vim.bo[buf].modified = true
      inline.cmd_save_exit()
      vim.wait(200, function()
        return quit
      end)
      assert.is_true(quit)
      assert.equals(1, #update_calls())
      assert.is_true(inline.is_active(), "teardown is the view's close path, not :wq")
    end)

    it("set_issue flushes unsaved text of the previous issue, then re-targets", function()
      local buf = make_attached({ id = "beads_nvim-a1", title = "T", description = "old a1" })
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "edited a1" })
      vim.bo[buf].modified = true
      inline.set_issue({ id = "beads_nvim-b2", title = "U", description = "body b2" })
      vim.wait(200, function()
        return #update_calls() > 0
      end)
      -- the old issue's edit was saved...
      assert.equals(1, #update_calls())
      assert.equals("edited a1", update_calls()[1].stdin)
      assert.equals("beads_nvim-a1", update_calls()[1].argv[3])
      -- ...and the buffer now shows the new issue, clean
      assert.equals("beads_nvim-b2", inline.current_id())
      assert.are.same({ "body b2" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
      assert.is_false(vim.bo[buf].modified)
    end)

    it("set_issue flushes even when another save is already in flight", function()
      -- slow runner: holds the first update so the second switch happens
      -- while saving=true (the coalescing-queue blind spot)
      local pending = {}
      config.setup({
        runner = function(argv, opts, on_exit)
          table.insert(captured, { argv = argv, stdin = opts.stdin })
          if argv[2] == "update" and #pending == 0 then
            table.insert(pending, on_exit) -- hold the first save open
            return
          end
          on_exit({ code = 0, stdout = "", stderr = "" })
        end,
      })
      local buf = make_attached({ id = "beads_nvim-a1", title = "T", description = "a1" })
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "edited a1" })
      vim.bo[buf].modified = true
      inline.set_issue({ id = "beads_nvim-b2", title = "U", description = "b2" }) -- save in flight
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "edited b2" })
      vim.bo[buf].modified = true
      inline.set_issue({ id = "beads_nvim-c3", title = "V", description = "c3" }) -- saving=true path
      pending[1]({ code = 0, stdout = "", stderr = "" }) -- release the first save
      vim.wait(300, function()
        return #update_calls() >= 2
      end)
      local bodies = {}
      for _, c in ipairs(update_calls()) do
        bodies[c.argv[3]] = c.stdin
      end
      assert.equals("edited a1", bodies["beads_nvim-a1"])
      assert.equals("edited b2", bodies["beads_nvim-b2"], "in-flight switch must not lose the edit")
    end)

    it("set_issue with the same id reloads content (external refresh)", function()
      local buf = make_attached({ id = "beads_nvim-a1", title = "T", description = "v1" })
      inline.set_issue({ id = "beads_nvim-a1", title = "T", description = "v2" })
      assert.are.same({ "v2" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
      assert.equals(0, #update_calls())
    end)

    it("abort flushes a modified attached buffer (float closed under us)", function()
      local buf = make_attached({ id = "beads_nvim-a1", title = "T", description = "old" })
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "typed then closed" })
      vim.bo[buf].modified = true
      inline.abort()
      vim.wait(200, function()
        return #update_calls() > 0
      end)
      assert.equals(1, #update_calls())
      assert.equals("typed then closed", update_calls()[1].stdin)
      assert.is_false(inline.is_active())
    end)

    it("discard exit clears modified so nothing is saved on abort", function()
      local quit = false
      local buf = make_attached({ id = "beads_nvim-a1", title = "T", description = "old" }, {
        on_quit = function()
          quit = true
        end,
      })
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "throwaway" })
      vim.bo[buf].modified = true
      inline.cmd_discard_exit()
      assert.is_true(quit)
      inline.abort()
      vim.wait(100)
      assert.equals(0, #update_calls())
    end)
  end)
end)
