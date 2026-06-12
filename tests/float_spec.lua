local float = require("beads.float")

describe("beads.float.center", function()
  it("respects maxima and centers", function()
    local geo = float.center(40, 10)
    assert.equals("editor", geo.relative)
    assert.is_true(geo.width <= 40)
    assert.is_true(geo.height <= 10)
    assert.is_true(geo.row >= 0)
    assert.is_true(geo.col >= 0)
  end)

  it("clamps to the screen when maxima exceed it", function()
    local geo = float.center(10000, 10000)
    assert.is_true(geo.width <= vim.o.columns - 8)
    assert.is_true(geo.height <= vim.o.lines - 6)
    assert.is_true(geo.row >= 0)
    assert.is_true(geo.col >= 0)
  end)
end)

describe("beads.float.resolve_dim", function()
  it("treats a fraction 0<n<=1 as a percentage of total", function()
    assert.equals(80, float.resolve_dim(0.8, 100))
    assert.equals(100, float.resolve_dim(1, 100))
    assert.equals(25, float.resolve_dim(0.25, 100))
  end)

  it("parses a percent string", function()
    assert.equals(80, float.resolve_dim("80%", 100))
    assert.equals(50, float.resolve_dim(" 50 % ", 100))
  end)

  it("treats a number >1 as an absolute count", function()
    assert.equals(96, float.resolve_dim(96, 200))
    assert.equals(110, float.resolve_dim(110, 80))
  end)

  it("returns nil for nil/invalid so callers can fall back", function()
    assert.is_nil(float.resolve_dim(nil, 100))
    assert.is_nil(float.resolve_dim("nonsense", 100))
  end)

  it("never returns less than 1 cell", function()
    assert.equals(1, float.resolve_dim(0.0001, 100))
  end)
end)

describe("beads.float.width/height", function()
  local config = require("beads.config")
  after_each(function()
    config.setup({}) -- restore defaults
  end)

  it("resolves a configured percentage against the editor", function()
    config.setup({ float = { view = { width = 0.5, height = 0.5 } } })
    assert.equals(math.floor(vim.o.columns * 0.5), float.width("view", 96))
    assert.equals(math.floor(vim.o.lines * 0.5), float.height("view", 24))
  end)

  it("falls back when unset (height stays content-sized)", function()
    config.setup({ float = { palette = { width = 0.7 } } })
    assert.equals(42, float.height("palette", 42)) -- no palette.height -> fallback
  end)
end)

describe("beads.float.auto_resize", function()
  local config = require("beads.config")
  after_each(function()
    config.setup({})
  end)

  local function tracked_win()
    local buf = vim.api.nvim_create_buf(false, true)
    return vim.api.nvim_open_win(
      buf,
      false,
      vim.tbl_extend("force", float.center(30, 5), { border = "single" })
    )
  end

  it("reapplies geometry on VimResized and detaches on close", function()
    local win = tracked_win()
    local calls = 0
    float.auto_resize(win, function()
      calls = calls + 1
      return float.center(30, 5)
    end)

    vim.cmd("doautocmd VimResized")
    assert.equals(1, calls)
    assert.is_true(vim.api.nvim_win_is_valid(win))

    vim.api.nvim_win_close(win, true)
    vim.cmd("doautocmd VimResized")
    assert.equals(1, calls)
  end)

  it("reapplies geometry on focus-resume events (M2)", function()
    local win = tracked_win()
    local calls = 0
    float.auto_resize(win, function()
      calls = calls + 1
      return float.center(30, 5)
    end)

    vim.api.nvim_exec_autocmds("FocusGained", {})
    vim.api.nvim_exec_autocmds("VimResume", {})
    assert.equals(2, calls)
    vim.api.nvim_win_close(win, true)
  end)

  it("skips focus events when refresh_on_focus=false but keeps VimResized", function()
    config.setup({ refresh_on_focus = false })
    local win = tracked_win()
    local calls = 0
    float.auto_resize(win, function()
      calls = calls + 1
      return float.center(30, 5)
    end)

    vim.api.nvim_exec_autocmds("FocusGained", {})
    assert.equals(0, calls) -- focus ignored
    vim.cmd("doautocmd VimResized")
    assert.equals(1, calls) -- resize still honored
    vim.api.nvim_win_close(win, true)
  end)
end)
