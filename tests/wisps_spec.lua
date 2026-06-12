local render = require("beads.render")
local wisps = require("beads.wisps")
local cli = require("beads.cli")
local config = require("beads.config")

describe("render.wisp_lines", function()
  local list = {
    { id = "w-1", title = "beat", status = "open", priority = 2, wisp_type = "heartbeat" },
    { id = "w-2", title = "patrol run", status = "open", priority = 1, wisp_type = "patrol" },
    { id = "w-3", title = "beat two", status = "open", priority = 2, wisp_type = "heartbeat" },
  }
  local types = { "heartbeat", "ping", "patrol" }

  it("groups wisps by type in the given order, omitting empty types", function()
    local lines, _, rows = render.wisp_lines(list, types, 60)
    assert.matches("heartbeat %(2%)", lines[1])
    -- ping has no wisps -> no header for it anywhere
    for _, l in ipairs(lines) do
      assert.is_nil(l:match("ping"))
    end
    -- the two heartbeat ids map back, then patrol later
    assert.equals("w-1", rows[2])
    assert.equals("w-3", rows[3])
  end)

  it("link-highlights each wisp id", function()
    local _, hls = render.wisp_lines(list, types, 60)
    local links = 0
    for _, h in ipairs(hls) do
      if h.hl_group == "BeadsLink" then
        links = links + 1
      end
    end
    assert.equals(3, links)
  end)

  it("shows an explanatory placeholder when there are no wisps", function()
    local lines, _, rows = render.wisp_lines({}, types, 60)
    assert.matches("No wisps", lines[1])
    assert.is_nil(next(rows))
  end)
end)

describe("wisps._fetch", function()
  local orig_notify
  before_each(function()
    config.setup({ cwd = "/tmp" })
    orig_notify = vim.notify
    vim.notify = function() end
  end)
  after_each(function()
    vim.notify = orig_notify
    config.setup({})
  end)

  it("fans out one list call per wisp type, tags, and flattens", function()
    cli._runner = function(argv, _, on_exit)
      -- argv: { "bd", "list", "--wisp-type", <t>, "--json" }
      local t = argv[4]
      if t == "heartbeat" then
        on_exit({ code = 0, stdout = '[{"id":"w-1","title":"beat"}]', stderr = "" })
      elseif t == "patrol" then
        on_exit({
          code = 0,
          stdout = '[{"id":"w-2","title":"a"},{"id":"w-3","title":"b"}]',
          stderr = "",
        })
      else
        on_exit({ code = 0, stdout = "[]", stderr = "" })
      end
    end

    local got
    wisps._fetch(function(list)
      got = list
    end)
    vim.wait(500, function()
      return got ~= nil
    end, 5)

    assert.equals(3, #got)
    local by_id = {}
    for _, w in ipairs(got) do
      by_id[w.id] = w.wisp_type
    end
    assert.equals("heartbeat", by_id["w-1"])
    assert.equals("patrol", by_id["w-2"])
    assert.equals("patrol", by_id["w-3"])
  end)
end)
