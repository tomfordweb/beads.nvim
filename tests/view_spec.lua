-- Detail view in editable-description mode (and the legacy fallback), driven
-- against real floats with a fake bd runner — no bd binary needed.

local config = require("beads.config")
local fixtures = require("tests.fixtures.issues")
local inline = require("beads.inline_edit")
local sidebar = require("beads.sidebar")
local view = require("beads.view")

describe("beads.view", function()
  local captured

  -- Canned bd: `show` returns the fixture, mutating/list calls succeed empty.
  local function fake_runner(argv, opts, on_exit)
    table.insert(captured, { argv = argv, stdin = opts.stdin })
    local cmd = argv[2]
    local stdout = "[]"
    if cmd == "show" then
      stdout = vim.json.encode({ fixtures.show_issue })
    end
    on_exit({ code = 0, stdout = stdout, stderr = "" })
  end

  local function setup(extra)
    config.setup(vim.tbl_deep_extend("force", { runner = fake_runner }, extra or {}))
  end

  local function open_and_wait(id)
    view.open(id)
    local opened = vim.wait(1000, function()
      return inline.is_active()
        or #vim.tbl_filter(function(w)
            return vim.api.nvim_win_get_config(w).relative ~= ""
          end, vim.api.nvim_list_wins())
          > 0
    end)
    assert.is_true(opened, "detail float did not open")
  end

  local function main_float_buf()
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_config(w).relative ~= "" and w ~= sidebar.win() then
        return vim.api.nvim_win_get_buf(w), w
      end
    end
    return nil
  end

  local function update_calls()
    local out = {}
    for _, c in ipairs(captured) do
      if c.argv[2] == "update" then
        table.insert(out, c)
      end
    end
    return out
  end

  before_each(function()
    captured = {}
    setup()
  end)

  after_each(function()
    view.close()
    vim.wait(100, function()
      return not inline.is_active()
    end)
    config.setup({})
  end)

  describe("editable-description mode (default)", function()
    it("opens the description as a modifiable acwrite buffer", function()
      open_and_wait("beads_nvim-hcl")
      vim.wait(500, function()
        return inline.is_active()
      end)
      assert.is_true(inline.is_active())
      local buf = main_float_buf()
      assert.is_truthy(buf)
      assert.equals("acwrite", vim.bo[buf].buftype)
      assert.is_true(vim.bo[buf].modifiable)
      assert.is_truthy(vim.api.nvim_buf_get_name(buf):find("beads://beads_nvim%-hcl/description"))
      assert.are.same(
        { "Build the telescope picker.", "", "With filter cycling." },
        vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      )
      assert.equals("markdown", vim.bo[buf].filetype)
    end)

    it("persists edits through bd update on :w", function()
      open_and_wait("beads_nvim-hcl")
      vim.wait(500, function()
        return inline.is_active()
      end)
      local buf = main_float_buf()
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "rewritten body" })
      vim.bo[buf].modified = true
      inline.cmd_write()
      vim.wait(500, function()
        return #update_calls() > 0
      end)
      assert.equals(1, #update_calls())
      assert.equals("rewritten body", update_calls()[1].stdin)
      assert.equals("beads_nvim-hcl", update_calls()[1].argv[3])
    end)

    it("opens the sidebar with action rows and runs one via its callback", function()
      open_and_wait("beads_nvim-hcl")
      vim.wait(500, function()
        return sidebar.is_open()
      end)
      assert.is_true(sidebar.is_open(), "sidebar should open with the view")
      local sb = vim.api.nvim_win_get_buf(sidebar.win())
      local text = table.concat(vim.api.nvim_buf_get_lines(sb, 0, -1, false), "\n")
      assert.is_truthy(text:find("Actions", 1, true))
      assert.is_truthy(text:find("status: in_progress", 1, true))
      assert.is_truthy(text:find("close", 1, true))
      -- the close action row dispatches into the view's handler -> bd close
      sidebar.focus()
      for lnum, line in ipairs(vim.api.nvim_buf_get_lines(sb, 0, -1, false)) do
        if line:find("close", 1, true) and not line:find("status", 1, true) then
          vim.api.nvim_win_set_cursor(sidebar.win(), { lnum, 0 })
          break
        end
      end
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "x", false)
      vim.wait(500, function()
        for _, c in ipairs(captured) do
          if c.argv[2] == "close" then
            return true
          end
        end
        return false
      end)
      local closed = false
      for _, c in ipairs(captured) do
        if c.argv[2] == "close" and c.argv[3] == "beads_nvim-hcl" then
          closed = true
        end
      end
      assert.is_true(closed, "<CR> on the close action row should run bd close")
    end)

    it("keeps unsaved edits across a refresh", function()
      open_and_wait("beads_nvim-hcl")
      vim.wait(500, function()
        return inline.is_active()
      end)
      local buf = main_float_buf()
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "typing in progress" })
      vim.bo[buf].modified = true
      view.refresh()
      vim.wait(200)
      assert.are.same({ "typing in progress" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
      assert.is_true(vim.bo[buf].modified)
    end)

    it("saves unsaved edits when the float is closed out from under it", function()
      open_and_wait("beads_nvim-hcl")
      vim.wait(500, function()
        return inline.is_active()
      end)
      local buf = main_float_buf()
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "almost lost" })
      vim.bo[buf].modified = true
      view.close()
      vim.wait(500, function()
        return #update_calls() > 0
      end)
      assert.equals(1, #update_calls())
      assert.equals("almost lost", update_calls()[1].stdin)
    end)
  end)

  describe("legacy mode (view.editable_description=false)", function()
    it("renders the read-only detail buffer", function()
      setup({ view = { editable_description = false } })
      open_and_wait("beads_nvim-hcl")
      vim.wait(500, function()
        return main_float_buf() ~= nil
      end)
      local buf = main_float_buf()
      assert.is_truthy(buf)
      assert.equals("nofile", vim.bo[buf].buftype)
      assert.is_false(vim.bo[buf].modifiable)
      local first = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
      assert.equals("# Phase 2: render module + picker", first)
      assert.is_false(inline.is_active())
    end)
  end)
end)
