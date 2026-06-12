local render = require("beads.render")
local float = require("beads.float")
local issues = require("beads.issues")

local function norm(list)
  local out = {}
  for _, r in ipairs(list) do
    table.insert(out, issues.normalize(r))
  end
  return out
end

describe("render.status_title", function()
  it("title-cases and de-underscores a status name", function()
    assert.equals("Open", render.status_title("open"))
    assert.equals("In Progress", render.status_title("in_progress"))
    assert.equals("Blocked", render.status_title("blocked"))
  end)

  it("handles nil / empty", function()
    assert.equals("", render.status_title(nil))
    assert.equals("", render.status_title(""))
  end)
end)

describe("render.board_group", function()
  local list = norm({
    { id = "a-1", title = "one", status = "open" },
    { id = "a-2", title = "two", status = "in_progress" },
    { id = "a-3", title = "three", status = "open" },
    { id = "a-4", title = "four", status = "closed" },
    { id = "a-5", title = "five", status = "deferred" },
  })

  it("groups issues into the requested status columns in order", function()
    local groups = render.board_group(list, { "open", "in_progress", "closed" })
    assert.equals(3, #groups)
    assert.equals("open", groups[1].status)
    assert.equals(2, #groups[1].items)
    assert.equals("in_progress", groups[2].status)
    assert.equals(1, #groups[2].items)
    assert.equals("closed", groups[3].status)
    assert.equals(1, #groups[3].items)
  end)

  it("drops issues whose status is outside the subset", function()
    local groups = render.board_group(list, { "open" })
    assert.equals(1, #groups)
    assert.equals(2, #groups[1].items) -- the deferred/closed/in_progress ones gone
  end)

  it("yields an empty column for a status with no issues", function()
    local groups = render.board_group(list, { "blocked" })
    assert.equals(1, #groups)
    assert.equals(0, #groups[1].items)
  end)

  it("defaults a missing status to open", function()
    local groups = render.board_group(norm({ { id = "x-1", title = "t" } }), { "open" })
    assert.equals(1, #groups[1].items)
  end)
end)

describe("render.board_column_lines", function()
  it("renders a header with the count and two lines per card", function()
    local group = {
      status = "open",
      items = norm({
        { id = "a-1", title = "first", status = "open", priority = 1 },
        { id = "a-2", title = "second", status = "open", priority = 3 },
      }),
    }
    local lines, hls, rows = render.board_column_lines(group, 40)
    assert.matches("Open %(2%)", lines[1])
    -- header, blank, then 2 lines per card
    assert.equals(2 + 2 * 2, #lines)
    -- card id rows map back to their issue id
    assert.equals("a-1", rows[3])
    assert.equals("a-1", rows[4])
    assert.equals("a-2", rows[5])
    -- a link highlight exists for the id
    local has_link = false
    for _, h in ipairs(hls) do
      if h.hl_group == "BeadsLink" then
        has_link = true
      end
    end
    assert.is_true(has_link)
  end)

  it("renders an (empty) placeholder for a column with no cards", function()
    local lines, _, rows = render.board_column_lines({ status = "blocked", items = {} }, 40)
    assert.matches("Blocked %(0%)", lines[1])
    assert.matches("empty", lines[#lines])
    assert.is_nil(next(rows))
  end)

  it("truncates long titles to the column width", function()
    local group = {
      status = "open",
      items = norm({ { id = "a-1", title = string.rep("x", 100), status = "open" } }),
    }
    local lines = render.board_column_lines(group, 20)
    for _, l in ipairs(lines) do
      assert.is_true(vim.fn.strdisplaywidth(l) <= 20)
    end
  end)

  it("never emits a highlight past its line, even at a tiny width", function()
    -- regression: a narrow column clips long ids; an id-link highlight spanning
    -- past the clipped line is an extmark out-of-range error at apply time.
    local group = {
      status = "open",
      items = norm({
        { id = "beads_nvim-longidhere", title = "wide title here", status = "open" },
      }),
    }
    local lines, hls = render.board_column_lines(group, 8)
    for _, h in ipairs(hls) do
      assert.is_true(h.col_end <= #lines[h.lnum + 1], "highlight col_end overflows line")
    end
  end)
end)

describe("float.columns", function()
  it("returns n editor-relative columns of equal width", function()
    local cols = float.columns(4, { width = 120, height = 30 })
    assert.equals(4, #cols)
    local w = cols[1].width
    for _, c in ipairs(cols) do
      assert.equals("editor", c.relative)
      assert.equals(w, c.width)
      assert.equals(cols[1].row, c.row)
      assert.equals(cols[1].height, c.height)
    end
  end)

  it("orders columns left to right with a gap between them", function()
    local cols = float.columns(3, { width = 90, gap = 2 })
    assert.is_true(cols[2].col > cols[1].col)
    assert.is_true(cols[3].col > cols[2].col)
    -- each column starts after the previous one's width plus the gap
    assert.equals(cols[1].col + cols[1].width + 2, cols[2].col)
  end)

  it("clamps the row to the screen and never goes negative", function()
    local cols = float.columns(6, { width = 100000 })
    local last = cols[#cols]
    assert.is_true(last.col + last.width <= vim.o.columns)
    for _, c in ipairs(cols) do
      assert.is_true(c.col >= 0)
      assert.is_true(c.row >= 0)
      assert.is_true(c.width >= 1)
    end
  end)

  it("treats n<1 as a single column", function()
    assert.equals(1, #float.columns(0, {}))
    assert.equals(1, #float.columns(-3, {}))
  end)
end)
