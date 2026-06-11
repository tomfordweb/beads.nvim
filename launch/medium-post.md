# Medium long-form — outline + section hooks

**Stage:** feedback. Long-form "why I built it + how it works" post. Outline and
hooks only — **you write the prose.** Aim 1,200-1,800 words, 4-6 screenshots,
1-2 asciinema embeds.

**Working titles:**
- `Tracking AI-agent work without leaving Neovim: building beads.nvim`
- `A Neovim UI for bd, the dependency-aware issue tracker`

---

## Section map

**1. Lede (the itch).**
- Hook: agents file issues, leave memories, build dependency graphs — and you
  were reading all of it through `bd` in a terminal split. Editor-native was the
  obvious missing piece.
- [owner: the specific moment that pushed you to build it.]

**2. What Beads is (set context, credit upstream).**
- One paragraph on [`bd`](https://github.com/gastownhall/beads): dependency-aware,
  agent-first, local Dolt DB, JSONL export. Link it. Make clear beads.nvim is a
  *UI for* it, not a reimplementation.

**3. What beads.nvim does (the tour — one screenshot per beat).**
- Issue browser + live filter cycling → screenshot.
- Detail view: fields, comments, deps, the actions (status/priority/assign/
  label/defer) → screenshot.
- Links sidebar + dependency graph → screenshot/cast.
- Epics: children section + `epic status` dashboard → screenshot.
- Change history + agent-memory browser → screenshot.

**4. How it's built (the engineering angle — this is the Medium differentiator).**
- Single choke point: everything shells through one async `bd` wrapper
  (`vim.system`), nothing else spawns processes.
- One fetch, client-side filtering — no subprocess per keystroke; why that
  matters for picker responsiveness.
- Pure render layer (issue table → lines + highlights) kept separate from window
  code, so it's unit-testable headlessly.
- Single-source docs: README → `:help beads` + Pages via panvimdoc.
- [owner: one honest "what was hard" — async callback ordering, telescope
  internals, float geometry, whatever rang true.]

**5. Design choices worth defending.**
- Telescope as the surface (and the trade-off vs a bespoke UI).
- Why a thin wrapper beats caching `bd` state in the plugin.
- Keeping all writes in `bd` so the agent and the human never diverge.

**6. Install + try it.**
- lazy.nvim snippet (copy from README), requirements (nvim ≥ 0.10, telescope,
  plenary, `bd`).
- Link repo, `:help beads`, the issue tracker.

**7. Close.**
- Honest status (early, what's next), feedback CTA, credit `bd` again.
- [owner: where you're taking it.]

---

## Reuse / consistency

- Pull the blurb + feature wording from `blurb.md`; don't re-describe features
  in fresh words or the brand drifts across posts.
- Same screenshots as the Reddit/Discord posts (shot list in `blurb.md`).
- Mention `nvim-beads` only if you frame a "why another plugin" section — and
  only on features, never as a knock.
