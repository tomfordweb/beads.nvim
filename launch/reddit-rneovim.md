# r/neovim — "I built X" post scaffold

**Stage:** feedback (post only after repo is public, CI green, `:help beads`
works). r/neovim permits sharing your own plugins.

**Format:** self-post (text), 1-2 screenshots or an asciinema GIF inline.
Flair: `Plugin`.

---

## Title options (pick/tune one)

- `beads.nvim — a Telescope UI for the bd issue tracker (dependency-aware, built for AI agents)`
- `I built a Neovim front-end for bd, the dependency-aware issue tracker for coding agents`
- `beads.nvim: triage bd issues, deps, and agent memories without leaving the editor`

Keep it descriptive, not hypey. Lead with "what", not "check out my".

---

## Body outline

**1. Hook (1-2 sentences).**
- The problem you hit: tracking agent work / dependency-aware issues from inside
  nvim instead of shelling out to `bd` constantly.
- [owner: one honest sentence on *why you* built it.]

**2. What it is (pull the tight blurb from `blurb.md`).**
- A UI *for* [`bd`](https://github.com/gastownhall/beads) — credit it explicitly.
- One line on the architecture: thin async wrapper, one fetch + client-side
  filtering, no subprocess per keystroke.

**3. Feature bullets (3-4, pulled from `blurb.md` — don't overload).**
- Telescope picker with live filter cycling.
- Floating detail view: status/priority/assign/label/defer, dep-jump with history.
- Dependency graph + epic children/status.
- Agent-memory browser.

**4. Media.**
- [asciinema GIF of the triage loop — see `blurb.md` shot list.]
- One detail-view screenshot.

**5. Honest close / CTA.**
- "Early, feedback wanted" — name a rough edge or two you know about.
- Repo link: `https://github.com/tomfordweb/beads.nvim`.
- Note Neovim ≥ 0.10, needs telescope + plenary + the `bd` CLI.

---

## Comment-prep (have answers ready, don't pre-empt in the post)

- **"How's this different from `nvim-beads`?"** → Answer on scope/features
  (sidebar, graph, epic dashboard, history, palette, memory browser) and repo
  name. Do **not** disparage it; it's a fine plugin that holds the luarocks name.
- **"What's bd?"** → One sentence + link; dependency-aware tracker designed so
  AI agents and humans share one issue graph.
- **"Telescope-only?"** → Yes today; note it honestly.

## Etiquette

- Don't cross-post the same hour to 5 places. r/neovim first, gather feedback.
- Reply to every substantive comment; fold fixes back before the official
  listings.
