-- Browse and manage bd persistent memories: telescope picker over
-- `bd memories`, edit/create in an acwrite float (`bd remember`), delete
-- via `bd forget`.

local cli = require("beads.cli")
local config = require("beads.config")
local float = require("beads.float")
local helpbar = require("beads.helpbar")
local render = require("beads.render")

local M = {}

--- Flatten the `bd memories --json` object ({key: content, schema_version})
--- into a key-sorted list. Pure.
---@param raw table|nil
---@return { key: string, value: string }[]
function M.normalize(raw)
  local list = {}
  for key, value in pairs(raw or {}) do
    if key ~= "schema_version" and type(value) == "string" then
      table.insert(list, { key = key, value = value })
    end
  end
  table.sort(list, function(a, b)
    return a.key < b.key
  end)
  return list
end

--- Open an editable float for a memory; :w persists via bd remember.
---@param key string
---@param value string|nil nil/"" for a new memory
function M.edit(key, value)
  render.define_highlights()
  local name = ("beads://memory/%s"):format(key)

  local function open_float(buf)
    local win = vim.api.nvim_open_win(
      buf,
      true,
      vim.tbl_extend("force", float.center(90, 20), {
        border = "rounded",
        title = (" memory %s "):format(key),
        title_pos = "center",
        footer = helpbar.footer("memory_edit"),
        footer_pos = "center",
      })
    )
    vim.wo[win].wrap = true
    float.auto_resize(win, function()
      return float.center(90, 20)
    end)
  end

  local existing = vim.fn.bufnr(name)
  if existing ~= -1 then
    open_float(existing)
    return
  end

  local buf = vim.api.nvim_create_buf(false, false)
  vim.api.nvim_buf_set_name(buf, name)
  vim.bo[buf].buftype = "acwrite"
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].bufhidden = "wipe"

  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(value or "", "\n", { plain = true }))
  vim.bo[buf].modified = false

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    callback = function()
      local body = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
      if vim.trim(body) == "" then
        vim.notify("bd: refusing to save empty memory " .. key, vim.log.levels.WARN)
        return
      end
      cli.run_plain({ "remember", body, "--key", key }, function(ok)
        if not ok then
          return
        end
        if vim.api.nvim_buf_is_valid(buf) then
          vim.bo[buf].modified = false
        end
        vim.notify("bd: remembered " .. key, vim.log.levels.INFO)
      end)
    end,
  })

  open_float(buf)
end

--- Prompt for a key and open an empty edit float for it.
function M.new()
  vim.ui.input({ prompt = "Memory key (kebab-case): " }, function(key)
    key = key and vim.trim(key) or ""
    if key == "" then
      return
    end
    M.edit(key, "")
  end)
end

---@param entries { key: string, value: string }[]
function M._open_picker(entries)
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local entry_display = require("telescope.pickers.entry_display")
  local previewers = require("telescope.previewers")
  local themes = require("telescope.themes")

  render.define_highlights()

  local displayer = entry_display.create({
    separator = "  ",
    items = { { width = 32 }, { remaining = true } },
  })

  local function entry_maker(mem)
    local first_line = mem.value:match("^[^\n]*") or ""
    return {
      value = mem,
      ordinal = mem.key .. " " .. mem.value,
      display = function()
        return displayer({ { mem.key, "BeadsLink" }, { first_line, "BeadsMeta" } })
      end,
    }
  end

  local function make_finder()
    return finders.new_table({ results = entries, entry_maker = entry_maker })
  end

  local function refetch(prompt_bufnr)
    cli.run_json({ "memories" }, function(ok, raw)
      if not ok or not vim.api.nvim_buf_is_valid(prompt_bufnr) then
        return
      end
      entries = M.normalize(raw)
      local p = action_state.get_current_picker(prompt_bufnr)
      if p then
        p:refresh(make_finder(), { reset_prompt = false })
      end
    end)
  end

  local theme = config.get().picker.theme == "ivy" and themes.get_ivy({}) or {}

  pickers
    .new(theme, {
      prompt_title = "Beads Memories │ " .. helpbar.line("memories"),
      finder = make_finder(),
      sorter = conf.generic_sorter({}),
      previewer = previewers.new_buffer_previewer({
        title = "Memory",
        define_preview = function(self, entry)
          vim.api.nvim_buf_set_lines(
            self.state.bufnr,
            0,
            -1,
            false,
            vim.split(entry.value.value, "\n", { plain = true })
          )
          vim.bo[self.state.bufnr].filetype = "markdown"
          vim.wo[self.state.winid].wrap = true
        end,
      }),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          local entry = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          if entry then
            M.edit(entry.value.key, entry.value.value)
          end
        end)

        map({ "i", "n" }, "<C-n>", function()
          actions.close(prompt_bufnr)
          M.new()
        end)

        map({ "i", "n" }, "<C-d>", function()
          local entry = action_state.get_selected_entry()
          if not entry then
            return
          end
          local key = entry.value.key
          if vim.fn.confirm(("Forget memory %q?"):format(key), "&Yes\n&No", 2) ~= 1 then
            return
          end
          cli.run_plain({ "forget", key }, function(ok)
            if ok then
              vim.notify("bd: forgot " .. key, vim.log.levels.INFO)
              refetch(prompt_bufnr)
            end
          end)
        end)

        map({ "i", "n" }, "<C-r>", refetch)

        return true
      end,
    })
    :find()
end

--- Open the memories browser.
function M.open()
  cli.run_json({ "memories" }, function(ok, raw)
    if not ok then
      return
    end
    M._open_picker(M.normalize(raw))
  end)
end

return M
