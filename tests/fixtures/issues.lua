-- Canned bd JSON output as Lua tables, pinned to bd 1.0.4 shapes.

local M = {}

-- Shape of one element from `bd list --json`.
M.list_issue = {
  id = "beads_nvim-x9s",
  title = "beads.nvim v1",
  status = "open",
  priority = 1,
  issue_type = "epic",
  created_at = "2026-06-11T11:34:00Z",
  updated_at = "2026-06-11T11:34:00Z",
  dependency_count = 0,
  dependent_count = 5,
  comment_count = 0,
}

-- Shape of `bd show <id> --json` (single-element array in real output);
-- dependencies carry full issue objects plus dependency_type.
M.show_issue = {
  id = "beads_nvim-hcl",
  title = "Phase 2: render module + picker",
  status = "in_progress",
  priority = 2,
  issue_type = "task",
  assignee = "Tom Ford",
  description = "Build the telescope picker.\n\nWith filter cycling.",
  labels = { "ui", "telescope" },
  created_at = "2026-06-11T11:34:00Z",
  updated_at = "2026-06-11T12:00:00Z",
  dependencies = {
    {
      id = "beads_nvim-ay7",
      title = "Phase 1: scaffold",
      status = "open",
      priority = 2,
      issue_type = "task",
      created_at = "2026-06-11T11:34:00Z",
      updated_at = "2026-06-11T11:34:00Z",
      dependency_type = "blocks",
    },
  },
  dependency_count = 1,
  dependent_count = 1,
  comment_count = 0,
}

-- Sparse issue with most optional fields absent, exercising normalize defaults.
M.sparse_issue = {
  id = "beads_nvim-b8c",
  title = "Phase 5: polish",
}

return M
