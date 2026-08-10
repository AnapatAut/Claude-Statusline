#!/bin/bash
# Installs the custom Claude Code statusline on this machine:
#   - copies statusline.sh into ~/.claude (or $CLAUDE_CONFIG_DIR)
#   - merges the statusLine setting into settings.json, preserving everything else
#   - if the caveman plugin is installed, wires the Stop-hook stats refresh so
#     the badge's tokens-saved number stays live (icon-only otherwise)
#
# Usage: ./install.sh
set -euo pipefail

for dep in jq curl; do
  command -v "$dep" >/dev/null || { echo "error: '$dep' is required (apt install $dep)"; exit 1; }
done

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SRCDIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$SRCDIR/statusline.sh"
SETTINGS="$CFG/settings.json"

mkdir -p "$CFG"
# never silently clobber a pre-existing, different statusline script
if [ -f "$CFG/statusline.sh" ] && ! cmp -s "$SRC" "$CFG/statusline.sh"; then
  bak="$CFG/statusline.sh.pre-install.$(date +%s)"
  cp "$CFG/statusline.sh" "$bak"
  echo "existing statusline.sh backed up to $bak"
fi
cp "$SRC" "$CFG/statusline.sh"
chmod +x "$CFG/statusline.sh"

# drop any limits store from a prior version: older builds used a tab-separated
# format that the current 0x1f-separated parser would misread once (garbage
# Session%/Weekly% on the first render) before the next 30s fetch overwrites it.
# Removing it forces a clean refetch in the new format.
rm -rf "$CFG/.statusline-limits-fetch" "$CFG/.statusline-limits-fetch.lock" 2>/dev/null || true

[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
tmp=$(mktemp)
jq --arg cmd "bash \"$CFG/statusline.sh\"" \
   '.statusLine = {type: "command", command: $cmd, refreshInterval: 5}' \
   "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"

# Caveman tokens-saved chain: the badge number reads ~/.claude/.caveman-history.jsonl,
# which only stays fresh if a Stop hook reruns caveman-stats after each turn.
# Wire it iff the caveman plugin's hooks are present; merge is idempotent.
if [ -f "$CFG/hooks/caveman-stats.js" ]; then
  cp "$SRCDIR/caveman-stats-refresh.sh" "$CFG/hooks/caveman-stats-refresh.sh"
  chmod +x "$CFG/hooks/caveman-stats-refresh.sh"
  tmp=$(mktemp)
  jq --arg cmd "bash \"$CFG/hooks/caveman-stats-refresh.sh\"" '
    if ([.hooks.Stop[]?.hooks[]?.command // empty] | any(contains("caveman-stats-refresh.sh"))) then .
    else .hooks.Stop = ((.hooks.Stop // []) + [{hooks: [{type: "command", command: $cmd, timeout: 10}]}]) end
  ' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
  echo "caveman stats refresh wired (Stop hook): badge tokens-saved number stays live"
else
  echo "caveman plugin hooks not found: badge will show icon/mode only, no tokens number"
fi

echo "Installed. Statusline active in new Claude Code sessions."
echo "  script:   $CFG/statusline.sh"
echo "  settings: $SETTINGS (statusLine key merged, rest untouched)"
