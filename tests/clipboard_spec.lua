local clipboard = require("beads.clipboard")
local config = require("beads.config")

describe("beads.clipboard", function()
  local saved_clipboard, saved_ssh, saved_tmux

  before_each(function()
    saved_clipboard = vim.g.clipboard
    saved_ssh = vim.env.SSH_TTY
    saved_tmux = vim.env.TMUX
    vim.g.clipboard = nil
    vim.env.SSH_TTY = nil
    vim.env.TMUX = nil
    config.setup({})
  end)

  after_each(function()
    vim.g.clipboard = saved_clipboard
    vim.env.SSH_TTY = saved_ssh
    vim.env.TMUX = saved_tmux
    config.setup({})
  end)

  it("detects a remote session from SSH/tmux env", function()
    assert.is_false(clipboard.is_remote())
    vim.env.SSH_TTY = "/dev/pts/3"
    assert.is_true(clipboard.is_remote())
    vim.env.SSH_TTY = nil
    vim.env.TMUX = "/tmp/tmux-1000/default,1,0"
    assert.is_true(clipboard.is_remote())
  end)

  it("treats an explicit vim.g.clipboard as a working provider", function()
    assert.is_true(clipboard.has_provider() == (vim.fn.has("clipboard_working") == 1))
    vim.g.clipboard = { name = "fake", copy = {}, paste = {} }
    assert.is_true(clipboard.has_provider())
  end)

  it("maybe_enable is a no-op when edit.osc52 is off", function()
    config.setup({ edit = { osc52 = false } })
    vim.env.SSH_TTY = "/dev/pts/3"
    assert.is_false(clipboard.maybe_enable())
    assert.is_nil(vim.g.clipboard)
  end)

  it("maybe_enable is a no-op for a local session even when enabled", function()
    config.setup({ edit = { osc52 = true } })
    -- env cleared in before_each -> not remote
    assert.is_false(clipboard.maybe_enable())
    assert.is_nil(vim.g.clipboard)
  end)

  it("installs the OSC52 provider when enabled, remote, and unprovided", function()
    config.setup({ edit = { osc52 = true } })
    vim.env.SSH_TTY = "/dev/pts/3"
    if clipboard.has_provider() then
      return -- a real provider is present in this env; positive path not exercisable
    end
    assert.is_true(clipboard.maybe_enable())
    assert.is_table(vim.g.clipboard)
    assert.equals("osc52", vim.g.clipboard.name)
  end)
end)
