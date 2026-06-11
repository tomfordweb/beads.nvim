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
end)
