-- Telescope picker over bd issues with client-side filter cycling.
-- Fetches once (bd list --all), filters in Lua, refreshes the finder in place.

local cli = require("beads.cli")
local config = require("beads.config")
local float = require("beads.float")
local helpbar = require("beads.helpbar")
local issues = require("beads.issues")
local render = require("beads.render")
local ui = require("beads.ui")

local M = {}

-- Builtin picker action names (the ones bound explicitly below). Custom
-- user actions are any mappings.picker entry whose name is NOT in this set.
local builtin_picker_actions = {
  open = true,
  status = true,
  priority = true,
  type = true,
  label = true,
  defer = true,
  closed = true,
  refetch = true,
}

-- Bind a configurable mapping (string | list | false) inside attach_mappings.
local function map_action(map, lhs_value, fn)
  for _, lhs in ipairs(config.lhs(lhs_value)) do
    map({ "i", "n" }, lhs, fn)
  end
end

-- Previewer cache: issue id -> normalized full issue (from bd show --json),
-- or false when the fetch failed. Cleared on every M.open.
local preview_cache = {}

-- Keystrokes within this window coalesce into one `bd search` call.
local SEARCH_DEBOUNCE_MS = 120

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
        local lines, hls
        if issue == false then
          lines = { "Failed to load " .. id }
        else
          lines, hls = render.detail_lines(issue)
        end
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
        vim.bo[self.state.bufnr].filetype = "markdown"
        -- color the preview to match the detail view; clear-before-apply keeps
        -- it bounded as Telescope reuses this preview buffer across entries.
        float.apply_highlights(self.state.bufnr, "beads_picker_preview", hls or {})
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
  if filters.label then
    table.insert(parts, "#" .. filters.label)
  end
  if filters.all then
    table.insert(parts, "+closed")
  end
  -- telescope draws its own borders, so the keybind help bar lives in the
  -- prompt title (bottom separator line under the ivy theme)
  local help = helpbar.line(source == "ready" and "picker_ready" or "picker")
  local title = table.concat(parts, " ")
  return help ~= "" and (title .. " │ " .. help) or title
end

--- Live search picker over `bd search` (covers description text the
--- cached fuzzy picker can't reach). Re-queries bd as the prompt changes,
--- asynchronously and debounced so typing never blocks on bd.
---@param opts { default_text: string|nil }|nil
function M.search(opts)
  opts = opts or {}
  local pickers = require("telescope.pickers")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  render.define_highlights()
  preview_cache = {}

  local include_closed = false

  local function title()
    local base = "Beads Search" .. (include_closed and " +closed" or "")
    local help = helpbar.line("picker_search")
    return help ~= "" and (base .. " │ " .. help) or base
  end

  -- Async finder implementing telescope's finder protocol directly (callable
  -- + close), instead of finders.new_dynamic whose fn must return
  -- synchronously: each prompt change debounces, then runs `bd search` in the
  -- background and streams entries in on completion. A generation counter
  -- drops responses whose prompt is stale. The UI thread never blocks on bd.
  local entry_maker = make_entry_maker()
  local gen = 0
  local timer = assert(vim.uv.new_timer())
  local finder = setmetatable({
    close = function() -- telescope calls this when the picker closes
      timer:stop()
      if not timer:is_closing() then
        timer:close()
      end
    end,
  }, {
    __call = function(_, prompt, process_result, process_complete)
      gen = gen + 1
      local this = gen
      timer:stop()
      if not prompt or vim.trim(prompt) == "" then
        process_complete()
        return
      end
      timer:start(SEARCH_DEBOUNCE_MS, 0, function()
        -- timer callbacks run in a fast context; bd + buffer APIs need the
        -- main loop
        vim.schedule(function()
          if this ~= gen then
            return
          end
          cli.run_json(
            issues.build_search_args(prompt, { all = include_closed }),
            function(ok, results)
              if this ~= gen then
                return
              end
              if ok and type(results) == "table" then
                for _, r in ipairs(results) do
                  -- process_result returns true when the picker has moved on
                  if process_result(entry_maker(issues.normalize(r))) then
                    return
                  end
                end
              end
              process_complete()
            end
          )
        end)
      end)
    end,
  })

  pickers
    .new(ui.picker_opts(), {
      prompt_title = title(),
      default_text = opts.default_text,
      finder = finder,
      sorter = conf.generic_sorter({}),
      previewer = issue_previewer(),
      attach_mappings = function(prompt_bufnr, map)
        local m = config.get().mappings.picker
        actions.select_default:replace(function()
          local entry = action_state.get_selected_entry()
          local p = action_state.get_current_picker(prompt_bufnr)
          local prompt = p and p:_get_prompt() or ""
          actions.close(prompt_bufnr)
          if entry then
            require("beads.view").open(entry.value.id, {
              on_close = function()
                M.search({ default_text = prompt })
              end,
            })
          end
        end)
        for _, lhs in ipairs(config.lhs(m.open)) do
          if lhs ~= "<CR>" then
            map({ "i", "n" }, lhs, actions.select_default)
          end
        end

        map_action(map, m.closed, function()
          include_closed = not include_closed
          local p = action_state.get_current_picker(prompt_bufnr)
          if p then
            p:refresh(finder, { reset_prompt = false })
            if p.prompt_border then
              p.prompt_border:change_title(title())
            end
          end
        end)

        return true
      end,
    })
    :find()
end

--- Open the issue browser.
---@param opts { source: "list"|"ready"|nil, filters: table|nil, default_text: string|nil }|nil
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
  -- warm the statuses/types caches so the filter-cycle mappings bound in
  -- _open_picker never hit the synchronous fetch path
  issues.prefetch()

  cli.run_json(fetch_args, function(ok, raw)
    if not ok then
      return
    end
    raw = raw or {}
    local all_issues = {}
    for _, r in ipairs(raw) do
      table.insert(all_issues, issues.normalize(r))
    end
    M._open_picker(all_issues, filters, source, { default_text = opts.default_text })
  end)
end

---@param all_issues table[]
---@param filters table
---@param source string
---@param picker_opts { default_text: string|nil }|nil
function M._open_picker(all_issues, filters, source, picker_opts)
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

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

  pickers
    .new(ui.picker_opts(), {
      prompt_title = title_for(filters, source),
      default_text = picker_opts and picker_opts.default_text or nil,
      finder = make_finder(),
      sorter = conf.generic_sorter({}),
      previewer = issue_previewer(),
      attach_mappings = function(prompt_bufnr, map)
        local m = config.get().mappings.picker
        actions.select_default:replace(function()
          local entry = action_state.get_selected_entry()
          local p = action_state.get_current_picker(prompt_bufnr)
          local prompt = p and p:_get_prompt() or ""
          actions.close(prompt_bufnr)
          if entry then
            require("beads.view").open(entry.value.id, {
              -- closing the view (q / <Esc> / <BS> with empty history)
              -- lands back in the picker: same filters and prompt, fresh
              -- fetch so status/priority edits made in the view show up
              on_close = function()
                M.open({ source = source, filters = filters, default_text = prompt })
              end,
            })
          end
        end)
        for _, lhs in ipairs(config.lhs(m.open)) do
          if lhs ~= "<CR>" then
            map({ "i", "n" }, lhs, actions.select_default)
          end
        end

        -- values may be a function (statuses/types) resolved at keypress so
        -- the async prefetch has landed by then — building the picker never
        -- waits on bd
        local function cycle_filter(key, values)
          return function()
            local vals = type(values) == "function" and values() or values
            filters[key] = issues.cycle(filters[key], vals)
            refresh(prompt_bufnr)
          end
        end

        if source ~= "ready" then
          map_action(map, m.status, cycle_filter("status", issues.statuses))
          map_action(map, m.closed, function()
            filters.all = not filters.all
            refresh(prompt_bufnr)
          end)
        end
        map_action(map, m.priority, cycle_filter("priority", issues.PRIORITIES))
        map_action(map, m.type, cycle_filter("type", issues.types))
        -- label values track the loaded issues, recomputed each cycle so a
        -- refetch that adds/removes labels stays in sync
        map_action(map, m.label, function()
          filters.label = issues.cycle(filters.label, issues.collect_labels(all_issues))
          refresh(prompt_bufnr)
        end)

        -- Refetch from bd and re-render in place (shared by refetch + writes
        -- like defer that need fresh status afterward).
        local function reload()
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
        end

        map_action(map, m.refetch, reload)

        -- Defer / undefer the selected issue (toggles on its current status),
        -- then reload so the new status/icon shows.
        map_action(map, m.defer, function()
          local entry = action_state.get_selected_entry()
          if not entry then
            return
          end
          local issue = entry.value
          if issue.status == "deferred" then
            cli.run_plain({ "undefer", issue.id }, function(ok)
              if ok then
                reload()
              end
            end)
            return
          end
          vim.ui.input(
            { prompt = "Defer " .. issue.id .. " until (empty = no date): " },
            function(expr)
              if expr == nil then
                return
              end
              expr = vim.trim(expr)
              local args = { "defer", issue.id }
              if expr ~= "" then
                table.insert(args, "--until=" .. expr)
              end
              cli.run_plain(args, function(ok)
                if ok then
                  reload()
                end
              end)
            end
          )
        end)

        -- User-defined custom picker actions: any non-builtin name whose value
        -- is a { key, fn, desc } spec. fn receives the selected issue. Builtin
        -- names win on collision.
        local beads_actions = require("beads.actions")
        for action, value in pairs(m) do
          if not builtin_picker_actions[action] and beads_actions.is_custom_spec(value) then
            local fn = beads_actions.resolve(value)
            map_action(map, value.key, function()
              local entry = action_state.get_selected_entry()
              if not entry then
                return
              end
              local ok, err = pcall(fn, entry.value)
              if not ok then
                vim.notify(
                  "beads: custom action '" .. action .. "' error: " .. tostring(err),
                  vim.log.levels.WARN
                )
              end
            end)
          end
        end

        return true
      end,
    })
    :find()
end

return M
