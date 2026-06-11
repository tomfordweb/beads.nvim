#!/usr/bin/env bash
# Shared helpers for the launch-asset capture scripts. Source this; do not run.
#
#   source "$(dirname "$0")/lib.sh"
#
# Provides: repo_root, seed_demo, send, wait_for, checkpoint, cleanup_demo.

set -uo pipefail

# Resolve the repo root from this file's own location (robust to cwd and to
# BASH_SOURCE being relative/unset under `set -u`). Prefers git, falls back to
# walking up from launch/scripts/.
_lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
_lib_dir="${_lib_dir:-$PWD}"
REPO="$(git -C "$_lib_dir" rev-parse --show-toplevel 2>/dev/null || (cd "$_lib_dir/../.." && pwd))"
FIXTURE="$REPO/tests/fixtures/demo/issues.jsonl"

# Pacing: seconds to sleep after each `send`. Bump via SLEEP=1.5 for slow boxes.
SLEEP="${SLEEP:-1.0}"

DEMO_DIR=""

# Seed a throwaway demo bd DB in a tmp dir (bd init + bd import the fixture,
# matching tests/integration_spec.lua:144-146). Echoes the dir; sets DEMO_DIR.
seed_demo() {
  [ -f "$FIXTURE" ] || { echo "fixture missing: $FIXTURE" >&2; return 1; }
  DEMO_DIR="$(mktemp -d /tmp/beads_demo_XXXXXX)"
  ( cd "$DEMO_DIR" && bd init >/dev/null 2>&1 && bd import "$FIXTURE" >/dev/null 2>&1 ) \
    || { echo "seed failed in $DEMO_DIR" >&2; return 1; }
  # sanity: the epic must be present or the journeys have nothing to show
  ( cd "$DEMO_DIR" && bd show acme-web-1 >/dev/null 2>&1 ) \
    || { echo "demo seed has no acme-web-1 epic" >&2; return 1; }
  echo "$DEMO_DIR"
}

cleanup_demo() {
  [ -n "$DEMO_DIR" ] && [ -d "$DEMO_DIR" ] && rm -rf "$DEMO_DIR"
}

# send PANE token...   -- send keys to a tmux pane, then pace.
# Pass tmux send-keys tokens: literal strings + key names (Enter, C-s, BSpace,
# Escape, Down). e.g. send "$pane" ':Beads' Enter   /   send "$pane" C-s
send() {
  local pane="$1"; shift
  tmux send-keys -t "$pane" "$@"
  sleep "$SLEEP"
}

# wait_for PANE PATTERN [TRIES] -- poll the pane until PATTERN appears (0.4s
# steps). Returns 0 on match, 1 on timeout. Lets the script tolerate variable
# bd latency instead of guessing one big sleep.
wait_for() {
  local pane="$1" pat="$2" tries="${3:-15}" i
  for ((i = 0; i < tries; i++)); do
    if tmux capture-pane -p -t "$pane" | grep -qF "$pat"; then
      return 0
    fi
    sleep 0.4
  done
  return 1
}

# checkpoint PANE PATTERN LABEL -- assert PATTERN is on the pane; dump + fail
# loudly otherwise. This is the self-verification: the script proves the UI
# reached each expected state even though no one can see the cast yet.
checkpoint() {
  local pane="$1" pat="$2" label="$3"
  if wait_for "$pane" "$pat"; then
    echo "  ✓ $label (saw '$pat')"
    return 0
  fi
  echo "  ✗ $label — '$pat' never appeared. Pane dump:" >&2
  tmux capture-pane -p -t "$pane" >&2
  return 1
}
