#!/bin/bash
# Removes ONLY what install.sh added (including the caveman stats Stop hook entry
# installs before v1.3.0 wired). Explicitly untouched: all other settings.json
# keys and hooks (permissions, model, plugins...), credentials, caveman plugin
# files (the statusline only ever read those), and anything else in ~/.claude.
#
# Safety rails:
#   - settings.json: deletes just the statusLine key, and only if its command
#     points at our script; a timestamped backup is written first
#   - statusline.sh: deleted only if byte-identical to the bundled copy
#   - anything ambiguous is left in place with a message; --force overrides
#
# Usage: ./uninstall.sh [--force]
set -euo pipefail

command -v jq >/dev/null || { echo "error: 'jq' is required (apt install jq)"; exit 1; }

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS="$CFG/settings.json"
SCRIPT="$CFG/statusline.sh"
SRC="$(cd "$(dirname "$0")" && pwd)/statusline.sh"
FORCE="${1:-}"

# settings.json may be a symlink (GNU stow, chezmoi, Nix home-manager): edit the
# file it points to, so the link survives. Plain readlink, one hop at a time
# (macOS before 12.3 has no readlink -f).
SETTINGS_W="$SETTINGS"; hops=0
while [ -L "$SETTINGS_W" ] && [ "$hops" -lt 40 ]; do
  t=$(readlink "$SETTINGS_W")
  case "$t" in /*) SETTINGS_W="$t" ;; *) SETTINGS_W="$(dirname "$SETTINGS_W")/$t" ;; esac
  hops=$((hops + 1))
done
if [ -L "$SETTINGS_W" ]; then echo "error: $SETTINGS is a symlink loop"; exit 1; fi
# a read-only target (the Nix store) can't be edited here: stop before an edit,
# so a rerun after fixing the settings source skips the edit and finishes
_writable_or_stop() {
  if [ ! -w "$SETTINGS_W" ] || [ ! -w "$(dirname "$SETTINGS_W")" ]; then
    echo "error: can't edit $SETTINGS_W: read-only (managed by Nix home-manager or"
    echo "  similar?). Remove $1 from the settings source instead, then rerun."
    exit 1
  fi
}

# 1. settings.json: drop only the statusLine key, only if it references our script
if [ -f "$SETTINGS" ]; then
  cmd=$(jq -r '.statusLine.command // empty' "$SETTINGS")
  if [ -z "$cmd" ]; then
    echo "settings: no statusLine key, nothing to remove"
  elif printf '%s' "$cmd" | grep -qF "$SCRIPT" || [ "$FORCE" = "--force" ]; then
    _writable_or_stop "the statusLine key"
    bak="$SETTINGS.pre-uninstall.$(date +%s)"
    cp "$SETTINGS" "$bak"
    tmp=$(mktemp "$SETTINGS_W.XXXXXX")
    jq 'del(.statusLine)' "$SETTINGS_W" > "$tmp" && mv "$tmp" "$SETTINGS_W" || { rm -f "$tmp"; exit 1; }
    echo "settings: statusLine key removed, every other key untouched (backup: $bak)"
  else
    echo "settings: statusLine points at a different command — left alone:"
    echo "          $cmd"
    echo "          (./uninstall.sh --force to remove it anyway)"
  fi
else
  echo "settings: $SETTINGS not found, skipping"
fi

# 2. the installed script: delete only if it is provably ours and unmodified
if [ -f "$SCRIPT" ]; then
  if [ -f "$SRC" ] && cmp -s "$SCRIPT" "$SRC"; then
    rm "$SCRIPT"
    echo "removed $SCRIPT"
  elif [ "$FORCE" = "--force" ]; then
    rm "$SCRIPT"
    echo "removed $SCRIPT (--force: it differed from the bundled copy)"
  else
    echo "$SCRIPT differs from the bundled copy (modified, newer, or not ours) — left alone"
    echo "          (./uninstall.sh --force to remove it anyway)"
  fi
else
  echo "script: $SCRIPT not found, skipping"
fi

# 3. caveman stats refresh chain (added by installs before v1.3.0 when caveman
#    was present; current installs remove it themselves):
#    drop only Stop-hook entries whose command references our refresh script;
#    all other hooks (SessionStart, UserPromptSubmit, unrelated Stop entries) stay
if [ -f "$SETTINGS" ] && jq -e '[.hooks.Stop[]?.hooks[]?.command // empty] | any(contains("caveman-stats-refresh.sh"))' "$SETTINGS" >/dev/null 2>&1; then
  _writable_or_stop "the Stop hook entry that runs caveman-stats-refresh.sh"
  if [ -z "${bak:-}" ]; then  # not already backed up by the statusLine step
    bak="$SETTINGS.pre-uninstall.$(date +%s)"
    cp "$SETTINGS" "$bak"
    echo "settings backup: $bak"
  fi
  tmp=$(mktemp "$SETTINGS_W.XXXXXX")
  jq '
    .hooks.Stop = [.hooks.Stop[] | select(([.hooks[]?.command // empty] | any(contains("caveman-stats-refresh.sh"))) | not)]
    | if .hooks.Stop == [] then del(.hooks.Stop) else . end
    | if .hooks == {} then del(.hooks) else . end
  ' "$SETTINGS_W" > "$tmp" && mv "$tmp" "$SETTINGS_W" || { rm -f "$tmp"; exit 1; }
  echo "settings: caveman stats Stop hook removed, other hooks untouched"
fi
rm -f "$CFG/hooks/caveman-stats-refresh.sh"

# 4. runtime files the statusline itself created (names are unique to it)
rm -f "$CFG/.statusline-limits-fetch"
rmdir "$CFG/.statusline-limits-fetch.lock" 2>/dev/null || true
echo "runtime store cleaned"

echo "Done. Open sessions drop the statusline once restarted."
