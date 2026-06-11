-- Telescope picker over bd issues with client-side filter cycling.
-- Fetches once (bd list --all), filters in Lua, refreshes the finder in place.

local cli = require("beads.cli")
local config = require("beads.config")
local helpbar = require("beads.helpbar")
local issues = require("beads.issues")
local render = require("beads.render")

local M = {}

-- Previewer cache: issue id -> normalized full issue (from bd show --json),
-- or false when the fetch failed. Cleared on every M.open.
local preview_cache = {}

local function make_entry_maker()
  local entry_display = require("telescope.pickers.entry_display")
  local displayer = entry_display.create({
    separator = "  ",
    items = {
      { width = 16 }, -- id
      { width = 2 }, -- status icon
      { width = 2 }, -- priority
      { width = 7 }, -- type
      { remaining = true }, -- title
      { width = 7 }, -- dep counts
    },
  })

  return function(issue)
    local cols = render.entry_columns(issue)
    return {
      value = issue,
      ordinal = issue.id .. " " .. issue.title,
      display = function()
        return displayer({
          { cols.id, "BeadsMeta" },
          { cols.icon, render.status_hl(issue.status) },
          cols.priority,
          { cols.type, "BeadsMeta" },
          cols.title,
          { cols.deps, "BeadsMeta" },
        })
      end,
    }
  end
end

local function issue_previewer()
  local previewers = require("telescope.previewers")
  return previewers.new_buffer_previewer({
    title = "Issue",
    define_preview = function(self, entry)
      local id = entry.value.id

      local function show(issue)
        if not vim.api.nvim_buf_is_valid(self.state.bufnr) then
          return
        end
        local lines
        if issue == false then
          lines = { "Failed to load " .. id }
        else
          lines = render.detail_lines(issue)
        end
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
        vim.bo[self.state.bufnr].filetype = "markdown"
      end

      local cached = preview_cache[id]
      if cached ~= nil then
        return show(cached)
      end

      vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, { "Loading " .. id .. "…" })
      cli.run_json({ "show", id }, function(ok, result)
        local issue = ok and result and result[1] and issues.normalize(result[1]) or false
        preview_cache[id] = issue
        show(issue)
      end)
    end,
  })
end

---@param filters table
---@param source string
---@return string
local function title_for(filters, source)
  local parts = { source == "ready" and "Beads Ready" or "Beads" }
  if filters.status then
    table.insert(parts, "status:" .. filters.status)
  end
  if filters.priority ~= nil then
    table.insert(parts, "P" .. filters.priority)
  end
  if filters.type then
    table.insert(parts, filters.type)
  end
  if filters.all then
    table.insert(parts, "+closed")
  end
  -- telescope draws its own borders, so the keybind help bar lives in the
  -- prompt title (bottom separator line under the ivy theme)
  local help = helpbar.line(source == "ready" and "picker_ready" or "picker")
  return table.concat(parts, " ") .. " │ " .. help
end

--- Open the issue browser.
---@param opts { source: "list"|"ready"|nil, filters: table|nil }|nil
function M.open(opts)
  opts = opts or {}
  local source = opts.source or "list"
  local cfg = config.get()
  local filters = vim.tbl_extend("force", vim.deepcopy(cfg.default_filters), opts.filters or {})

  local fetch_args
  if source == "ready" then
    fetch_args = { "ready" }
  else
    fetch_args = issues.build_list_args({ all = true, limit = cfg.list_limit })
  end

  preview_cache = {}

  cli.run_json(fetch_args, function(ok, raw)
    if not ok then
      return
    end
    raw = raw or {}
    local all_issues = {}
    for _, r in ipairs(raw) do
      table.insert(all_issues, issues.normalize(r))
    end
    M._open_picker(all_issues, filters, source)
  end)
end

---@param all_issues table[]
---@param filters table
---@param source string
function M._open_picker(all_issues, filters, source)
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local themes = require("telescope.themes")

  render.define_highlights()

  local function visible()
    return vim.tbl_filter(function(issue)
      return issues.matches(issue, filters)
    end, all_issues)
  end

  local function make_finder()
    return finders.new_table({ results = visible(), entry_maker = make_entry_maker() })
  end

  local function refresh(prompt_bufnr)
    local p = action_state.get_current_picker(prompt_bufnr)
    if not p then
      return
    end
    p:refresh(make_finder(), { reset_prompt = false })
    if p.prompt_border then
      p.prompt_border:change_title(title_for(filters, source))
    end
  end

  local theme = config.get().picker.theme == "ivy" and themes.get_ivy({}) or {}

  pickers
    .new(theme, {
      prompt_title = title_for(filters, source),
      finder = make_finder(),
      sorter = conf.generic_sorter({}),
      previewer = issue_previewer(),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          local entry = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          if entry then
            require("beads.view").open(entry.value.id)
          end
        end)

        local function cycle_filter(key, values)
          return function()
            filters[key] = issues.cycle(filters[key], values)
            refresh(prompt_bufnr)
          end
        end

        if source ~= "ready" then
          map({ "i", "n" }, "<C-s>", cycle_filter("status", issues.STATUSES))
          map({ "i", "n" }, "<C-a>", function()
            filters.all = not filters.all
            refresh(prompt_bufnr)
          end)
        end
        map({ "i", "n" }, "<C-y>", cycle_filter("priority", issues.PRIORITIES))
        map({ "i", "n" }, "<C-t>", cycle_filter("type", issues.TYPES))

        map({ "i", "n" }, "<C-r>", function()
          local fetch_args = source == "ready" and { "ready" }
            or issues.build_list_args({ all = true, limit = config.get().list_limit })
          cli.run_json(fetch_args, function(ok, raw)
            if not ok or not vim.api.nvim_buf_is_valid(prompt_bufnr) then
              return
            end
            all_issues = {}
            for _, r in ipairs(raw or {}) do
              table.insert(all_issues, issues.normalize(r))
            end
            preview_cache = {}
            refresh(prompt_bufnr)
          end)
        end)

        return true
      end,
    })
    :find()
end

return M
