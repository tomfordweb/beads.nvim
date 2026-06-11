#!/usr/bin/env bash
# Record the launch asciinema casts by driving the real beads.nvim UI with
# tmux send-keys, then convert each to a GIF. Hermetic: each journey runs
# against a fresh throwaway demo bd DB.
#
#   launch/scripts/record.sh [journey...]      # default: triage deps epic
#
# Env:
#   WATCH=0   (default) detached session at a fixed, consistent geometry — the
#             clean asset. Attach to watch: tmux attach -t beadsrec
#   WATCH=1   split THIS window to watch live (geometry varies with the window;
#             fine for a preview, not for the final asset).
#   REC_COLS / REC_LINES   detached geometry (default 120x34).
#   SLEEP=1.2 per-keystroke pacing (see lib.sh).
#
# Requires: tmux, nvim, bd, asciinema (+ agg for GIFs). Run from inside tmux.

cd "$(dirname "$0")"
source ./lib.sh

WATCH="${WATCH:-0}"
REC_COLS="${REC_COLS:-120}"
REC_LINES="${REC_LINES:-34}"
CASTS="$REPO/launch/casts"
ASSETS="$REPO/launch/assets"
INIT="$REPO/launch/scripts/capture-init.lua"
mkdir -p "$CASTS" "$ASSETS"

# DRY=1 validates the journeys + checkpoints by driving plain nvim (no
# asciinema, no cast/gif) — useful before the recording tools are installed.
DRY="${DRY:-0}"
[ "$DRY" = 1 ] || command -v asciinema >/dev/null || { echo "asciinema not installed (or run with DRY=1)" >&2; exit 1; }
[ -n "${TMUX:-}" ] || { echo "run me from inside tmux" >&2; exit 1; }
HAVE_AGG=1; command -v agg >/dev/null || { echo "note: agg missing — casts only, no GIFs"; HAVE_AGG=0; }

# Close any recording pane/session left over from a previous run, and the
# current one on exit, so panes never stack up across runs.
CUR_PANE=""; CUR_DIR=""
# Tear down the current recording surface: detached session by name, or the
# WATCH split pane by id. Waits until it's actually gone so the next journey
# can recreate it without a "duplicate session" clash.
close_rec() {
  if [ "$WATCH" = "1" ]; then
    local p="$CUR_PANE"
    [ -n "$p" ] && tmux list-panes -a -F '#{pane_id}' 2>/dev/null | grep -qx "$p" \
      && { tmux send-keys -t "$p" Escape ':qa!' Enter 2>/dev/null; sleep 0.5; \
           tmux kill-pane -t "$p" 2>/dev/null; }
  else
    local i
    tmux kill-session -t beadsrec 2>/dev/null
    for ((i = 0; i < 10; i++)); do
      tmux has-session -t beadsrec 2>/dev/null || break
      sleep 0.2
    done
  fi
  CUR_PANE=""
}
on_exit() { close_rec; [ -n "$CUR_DIR" ] && rm -rf "$CUR_DIR"; }
trap on_exit EXIT
tmux kill-session -t beadsrec 2>/dev/null
tmux kill-session -t beadsshot 2>/dev/null

# Open a recording pane with cwd in the demo dir; echo the pane id. WATCH=1 →
# split THIS window (preview, geometry varies). WATCH=0 → a detached session
# forced to exactly REC_COLS×REC_LINES *before* asciinema starts, so the cast
# header captures the right size (tmux otherwise sizes the first session to the
# client, giving inconsistent widths across journeys).
open_rec_pane() {
  local dir="$1" cast="$2" inner cmd pane
  if [ "$DRY" = 1 ]; then
    inner="nvim -u \"$INIT\""
  else
    inner="asciinema rec --overwrite -c 'nvim -u \"$INIT\"' \"$cast\""
  fi
  if [ "$WATCH" = "1" ]; then
    tmux split-window -v -l 36 -c "$dir" -P -F '#{pane_id}' "$inner"
    return
  fi
  # detached: create the sized shell, let the pane settle at REC_COLS×REC_LINES,
  # THEN send-keys the recorder so asciinema reads the final size (launching it
  # via new-session -c captures a transient client-sized width instead).
  local i w
  tmux kill-session -t beadsrec 2>/dev/null
  for ((i = 0; i < 10; i++)); do tmux has-session -t beadsrec 2>/dev/null || break; sleep 0.1; done
  tmux new-session -d -s beadsrec -x "$REC_COLS" -y "$REC_LINES" -c "$dir"
  sleep 0.3
  w="$(tmux display -p -t beadsrec '#{window_width}' 2>/dev/null)"
  [ "$w" = "$REC_COLS" ] || echo "  ! window width is ${w:-?} (wanted $REC_COLS)" >&2
  pane="$(tmux display-message -p -t beadsrec '#{pane_id}')"
  tmux send-keys -t "$pane" "$inner" Enter
  echo "$pane"
}

# After the journey sent :qa! (nvim quit → asciinema wrote the cast): in WATCH
# the -c pane closes on its own; detached leaves a shell, so just give the cast
# a moment to flush. Then build the GIF.
finish_rec() {
  local pane="$1" cast="$2" gif="$3" i
  if [ "$WATCH" = "1" ]; then
    for ((i = 0; i < 25; i++)); do
      tmux list-panes -a -F '#{pane_id}' 2>/dev/null | grep -qx "$pane" || break
      sleep 0.4
    done
  else
    sleep 1.5
  fi
  [ "$DRY" = 1 ] && { echo "  (dry run — no cast/gif)"; return 0; }
  [ -s "$cast" ] || { echo "  ✗ cast not written: $cast" >&2; return 1; }
  if [ "$HAVE_AGG" = 1 ]; then
    agg --theme asciinema "$cast" "$gif" >/dev/null 2>&1 \
      && echo "  → $gif" || echo "  ✗ agg failed for $cast" >&2
  fi
}

# ---- journeys -------------------------------------------------------------
# Each takes the recording pane id. Keys are deterministic: filter the picker
# by typing id fragments rather than relying on cursor position.

journey_triage() {
  local p="$1"
  send "$p" ':Beads' Enter;       checkpoint "$p" 'Beads' 'picker open' || return 1
  send "$p" C-s                                  # cycle status filter (chip appears)
  send "$p" Enter;                checkpoint "$p" '## Description' 'detail open' || return 1
  send "$p" s                                    # status selector (dressing float)
  send "$p" Down; send "$p" Enter                # pick next status -> visible change
  send "$p" BSpace;               checkpoint "$p" 'Beads' 'back to picker' || return 1
  send "$p" ':qa!' Enter
}

journey_deps() {
  local p="$1"
  send "$p" ':Beads' Enter;       checkpoint "$p" 'Beads' 'picker open' || return 1
  send "$p" 'acme-web-4';         checkpoint "$p" 'acme-web-4' 'filtered to blocked task' || return 1
  send "$p" Enter;                checkpoint "$p" 'acme-web-5' 'detail shows blocker' || return 1
  send "$p" '/acme-web-5' Enter   # move cursor onto the dependency id
  send "$p" gd;                   checkpoint "$p" 'Provision' 'jumped to blocker (acme-web-5)' || return 1
  send "$p" BSpace                # back to acme-web-4
  send "$p" D;                    checkpoint "$p" 'acme-web' 'dependency graph' || return 1
  send "$p" q                     # close graph
  send "$p" q                     # close detail
  send "$p" ':qa!' Enter
}

journey_epic() {
  local p="$1"
  send "$p" ':Beads' Enter;       checkpoint "$p" 'Beads' 'picker open' || return 1
  send "$p" 'acme-web-1';         checkpoint "$p" 'acme-web-1' 'filtered to epic' || return 1
  send "$p" Enter;                checkpoint "$p" 'Children' 'epic children section' || return 1
  send "$p" ':BeadsPalette' Enter; checkpoint "$p" 'epic status' 'palette open' || return 1
  send "$p" Down; send "$p" Enter; checkpoint "$p" 'acme-web-1' 'epic status output' || return 1
  send "$p" q                     # close palette output
  send "$p" q                     # close detail
  send "$p" ':qa!' Enter
}

record_one() {
  local name="$1" fn="journey_$1" pane cast="$CASTS/$1.cast" gif="$ASSETS/$1.gif"
  echo "● $name"
  CUR_DIR="$(seed_demo)" || return 1
  pane="$(open_rec_pane "$CUR_DIR" "$cast")"
  [ -n "$pane" ] || { echo "  ✗ no record pane" >&2; rm -rf "$CUR_DIR"; CUR_DIR=""; return 1; }
  CUR_PANE="$pane"
  sleep 2 # let nvim + plugin load
  "$fn" "$pane"; local rc=$?
  finish_rec "$pane" "$cast" "$gif"
  close_rec                # tear down before the next journey
  rm -rf "$CUR_DIR"
  CUR_DIR=""
  return $rc
}

JOURNEYS=("$@"); [ ${#JOURNEYS[@]} -eq 0 ] && JOURNEYS=(triage deps epic)
fail=0
for j in "${JOURNEYS[@]}"; do record_one "$j" || fail=1; done
echo
[ $fail -eq 0 ] && echo "done — casts in launch/casts/, gifs in launch/assets/" || echo "one or more journeys failed (see ✗ above)"
exit $fail
