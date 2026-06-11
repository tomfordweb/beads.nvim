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

describe("beads.float.auto_resize", function()
  it("reapplies geometry on VimResized and detaches on close", function()
    local buf = vim.api.nvim_create_buf(false, true)
    local win = vim.api.nvim_open_win(
      buf,
      false,
      vim.tbl_extend("force", float.center(30, 5), { border = "single" })
    )

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
end)
