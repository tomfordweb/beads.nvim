# blurb.md — single-source copy

Everything else pulls from here. Keep it consistent with the README so the
brand reads the same everywhere. Edit here, copy outward.

---

## One-paragraph "what it is" (the elevator pitch)

> **beads.nvim** is a Neovim UI for [Beads (`bd`)](https://github.com/gastownhall/beads),
> the dependency-aware issue tracker built for AI coding agents. It wraps the
> `bd` CLI in a Telescope picker, a floating detail view, a dependency graph,
> and a command palette — so you can triage, edit, and navigate issues
> (and the memories your agents leave behind) without leaving the editor.
> One async fetch, client-side filtering, no subprocess per keystroke.

**Tighter (for Discord / one-liners):**

> A Neovim front-end for the `bd` issue tracker — Telescope picker, detail
> view, dependency graph, and agent memories, all over the `bd` CLI.

*(Owner: tune voice. Keep the "UI for bd", the agent angle, and the credit link.)*

---

## Canonical feature bullets

Pull a subset per platform; don't reword between posts.

- **Issue browser** — Telescope picker over `bd list` with live filter cycling
  (status / priority / type / label / include-closed) and a rendered preview.
  One fetch, client-side filtering — no subprocess per keystroke.
- **Detail view** — floating window with full fields, comments, and
  dependencies. Set status/priority, assign, label, defer, close/reopen, and
  jump through dependency ids in place with history.
- **Links sidebar** — companion pane: parent, children, depends-on, blocks —
  every id jumpable.
- **Epics** — children section with completion count + an `epic status`
  dashboard.
- **Dependency graph** — `bd graph` in a float, ids are clickable jumps.
- **Change history** — an issue's tracked-field transitions over time.
- **Command palette** — repo-level diagnostics (status, ready, blocked, stale,
  lint, preflight, doctor, find-duplicates, orphans, dep cycles, diff).
- **Agent memories** — browse/edit the `bd` memory store the agents write to.
- **Live search**, **markdown description editing**, resize-aware floats, a
  per-pane help bar.

---

## What makes it different (positioning, not for verbatim posting)

- **It's a UI, not a fork.** All state stays in `bd`; the plugin is a thin,
  async wrapper. Credit the official project everywhere.
- **Depth.** Sidebar, dependency graph, epic dashboard, change history, command
  palette, agent-memory browser — more than a list-and-open wrapper.
- **There is another plugin** (`joeblubaugh/nvim-beads`) using the `beads`
  luarocks name. We differ by repo name and scope, and we **never** knock it.
  If asked "why another", answer on features, not on the other plugin.

---

## Asset shot list  *(capture is an owner action — needs a real terminal)*

Record once, reuse across every post. Use the synthetic demo fixture
(`tests/fixtures/demo/`, the `acme-web` data) so nothing personal is on screen.

**Screenshots (PNG, light + dark if easy):**
1. Issue browser — picker open with a filter chip active (e.g. `status:open`).
2. Detail view — an issue with the links sidebar visible.
3. Epic detail — the Children section with a completion count.
4. Dependency graph float.
5. Command palette — the diagnostics list.

**asciinema casts (short, < 60s each):**
1. *Triage loop* — open browser → cycle filters → open detail → change status →
   back to list.
2. *Dependency walk* — detail view → `gd` jump through deps → `<BS>` history.
3. *Epic overview* — open an epic → Children section → `epic status` palette.

**Suggested capture setup:**
- Point nvim at the demo fixture so the data is the synthetic `acme-web` set:
  ```sh
  bd --directory tests/fixtures/demo <command>   # or open nvim with cwd there
  ```
- `asciinema rec --idle-time-limit=2 launch/casts/triage.cast`
- Convert to GIF/SVG for embedding (`agg` for GIF, or asciinema's own player
  embed for the Medium/GitHub copies).
- Store under `launch/assets/` (screenshots) and `launch/casts/` (recordings).

> Reminder: scrub the screen first — demo fixture only, no real `.beads`, no
> personal paths in the prompt.
