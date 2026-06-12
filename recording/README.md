# Demo recording (E9)

Headless, reproducible pipeline that renders the README demo GIF
(`assets/demo.gif`) by driving the real plugin UI with
[VHS](https://github.com/charmbracelet/vhs) inside Docker. No interactive
terminal needed — re-record per Neovim version by rebuilding the image.

## Render

```bash
recording/record.sh
```

That builds the image (`recording/Dockerfile`), seeds a throwaway `bd` DB from
the synthetic fixture in `tests/fixtures/demo/`, runs `recording/beads.tape`,
and writes `assets/demo.gif`. Commit the GIF; nothing here auto-pushes.

Requires `docker` and `bd` on your `$PATH` (the host `bd` binary is
bind-mounted into the container — `bd` embeds Dolt, so nothing else is needed).

## Files

| File          | Role                                                          |
|---------------|---------------------------------------------------------------|
| `record.sh`   | Build image, seed demo DB, run the tape, emit the GIF.        |
| `Dockerfile`  | VHS base + stable Neovim tarball + plenary/telescope deps.    |
| `beads.tape`  | The VHS script: the picker → detail+sidebar → graph journey.  |
| `init.lua`    | Minimal recording-only Neovim config (deps + clean chrome).   |

## Notes

- **Neovim version**: the Dockerfile installs the official *stable* tarball, not
  Debian's package — the telescope.nvim version it clones needs Neovim ≥ 0.11,
  while Debian trixie ships 0.10.x. This constrains the recording image only; the
  plugin itself supports Neovim ≥ 0.10. To pin a specific Neovim, edit the
  download URL in `Dockerfile`.
- **Synthetic data only**: the demo DB is seeded from `tests/fixtures/demo/`
  (`acme-web-*`, `demo@example.com`) so no personal tracking appears on screen.
- **Editing the journey**: the detail view is a real editable buffer, so issue
  action keys (`D` graph, `s` status, …) only fire from the **sidebar**. Never
  send them to the view in the tape or Neovim eats them as buffer edits.
- The interactive tmux+asciinema harness under `notes/scripts/` (gitignored) is
  a separate, owner-run path for the launch screenshots/casts; this committed
  VHS pipeline is the one the README GIF comes from.
