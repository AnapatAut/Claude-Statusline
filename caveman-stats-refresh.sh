#!/bin/bash
# Stop hook: refresh caveman stats each turn so the statusline's
# "⛏ <saved> (<pct>%)" tracks the live session instead of going stale until the
# next /caveman-stats. Reads the Stop event JSON on stdin for the exact
# transcript_path; falls back to caveman-stats' own most-recent-session finder.
# All output discarded — this only updates ~/.claude/.caveman-history.jsonl.

# Hooks run in a non-interactive shell where nvm isn't sourced, so PATH may
# lack node — fall back to the newest nvm-installed node.
NODE="$(command -v node 2>/dev/null)"
[ -n "$NODE" ] || NODE=$(ls -1 "$HOME"/.nvm/versions/node/*/bin/node 2>/dev/null | sort -V | tail -1)
STATS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/caveman-stats.js"
[ -n "$NODE" ] && [ -f "$STATS" ] || exit 0

input=$(cat)
tp=$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null)

if [ -n "$tp" ]; then
  "$NODE" "$STATS" --session-file "$tp" >/dev/null 2>&1
else
  "$NODE" "$STATS" >/dev/null 2>&1
fi
exit 0
