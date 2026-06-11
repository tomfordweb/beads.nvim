#!/usr/bin/env bash
# Capture the 5 static launch PNGs by driving beads.nvim to each money-shot
# state and rendering the pane's ANSI with charmbracelet/freeze. One seeded
# demo DB, one nvim, navigated between shots. No GUI display needed.
#
#   launch/scripts/screenshots.sh
#
# Env: WATCH=1 (default) split this window so you watch; SLEEP pacing.
# Requires: tmux, nvim, bd, freeze. (Fallback if no freeze: grab a frame from
# the matching GIF, e.g. `ffmpeg -sseof -0.2 -i launch/assets/epic.gif -frames:v 1 shot.png`.)

cd "$(dirname "$0")"
source ./lib.sh

WATCH="${WATCH:-0}"
REC_COLS="${REC_COLS:-120}"
REC_LINES="${REC_LINES:-34}"
ASSETS="$REPO/launch/assets"
INIT="$REPO/launch/scripts/capture-init.lua"
mkdir -p "$ASSETS"

[ -n "${TMUX:-}" ] || { echo "run me from inside tmux" >&2; exit 1; }
command -v freeze >/dev/null || { echo "freeze not installed (see header for ffmpeg fallback)" >&2; exit 1; }

# Close any leftover shot pane/session before starting, and clean up on exit.
tmux kill-session -t beadsshot 2>/dev/null
PANE=""; DIR=""
on_exit() {
  [ -n "$PANE" ] && tmux list-panes -a -F '#{pane_id}' 2>/dev/null | grep -qx "$PANE" \
    && { tmux send-keys -t "$PANE" Escape ':qa!' Enter 2>/dev/null; sleep 0.4; tmux kill-pane -t "$PANE" 2>/dev/null; }
  [ -n "$DIR" ] && rm -rf "$DIR"
}
trap on_exit EXIT

shot() { # shot PANE OUTNAME  -- render current pane ANSI to a framed PNG
  local p="$1" out="$ASSETS/$2.png"
  tmux capture-pane -p -e -J -t "$p" | freeze --output "$out" /dev/stdin >/dev/null 2>&1 \
    && echo "  → $out" || echo "  ✗ freeze failed for $2" >&2
}

DIR="$(seed_demo)" || exit 1
dir="$DIR"
INIT_CMD="nvim -u \"$INIT\""
if [ "$WATCH" = "1" ]; then
  pane="$(tmux split-window -v -l 36 -c "$dir" -P -F '#{pane_id}' "$INIT_CMD")"
else
  tmux new-session -d -s beadsshot -x "$REC_COLS" -y "$REC_LINES" -c "$dir" "$INIT_CMD"
  pane="$(tmux display-message -p -t beadsshot '#{pane_id}')"
fi
[ -n "$pane" ] || { echo "no pane" >&2; exit 1; }
PANE="$pane"
sleep 2 # nvim + plugin load

rc=0
# 1) issue browser with a filter chip
send "$pane" ':Beads' Enter; checkpoint "$pane" 'Beads' 'picker' || rc=1
send "$pane" C-s; shot "$pane" 01-browser

# 2) detail view + links sidebar (acme-web-4 depends on acme-web-5)
send "$pane" 'acme-web-4'; send "$pane" Enter
checkpoint "$pane" 'acme-web-5' 'detail+sidebar' || rc=1
shot "$pane" 02-detail-sidebar

# 3) epic children section (acme-web-1)
send "$pane" BSpace; send "$pane" ':Beads' Enter; send "$pane" 'acme-web-1'; send "$pane" Enter
checkpoint "$pane" 'Children' 'epic children' || rc=1
shot "$pane" 03-epic-children

# 4) dependency graph
send "$pane" D; checkpoint "$pane" 'acme-web' 'graph' || rc=1
shot "$pane" 04-graph
send "$pane" q

# 5) command palette
send "$pane" ':BeadsPalette' Enter; checkpoint "$pane" 'epic status' 'palette' || rc=1
shot "$pane" 05-palette
send "$pane" Escape

send "$pane" ':qa!' Enter
sleep 1
rm -rf "$dir"
echo
[ $rc -eq 0 ] && echo "done — 5 PNGs in launch/assets/" || echo "some checkpoints failed (see ✗)"
exit $rc
