#!/bin/bash
# Installs the custom Claude Code statusline on this machine:
#   - copies statusline.sh into ~/.claude (or $CLAUDE_CONFIG_DIR)
#   - merges the statusLine setting into settings.json, preserving everything else
#   - removes the caveman stats Stop hook older versions wired (caveman 4
#     dropped its savings estimate, so the badge shows the mode only)
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
CMD="bash \"$CFG/statusline.sh\""
# A read-only target (the Nix store) can't be edited here. If it already has our
# statusLine (and not the old Stop hook), only the script needs copying;
# otherwise stop before changing anything.
SETTINGS_RO=0
if { [ -e "$SETTINGS_W" ] && [ ! -w "$SETTINGS_W" ]; } || { [ -d "$(dirname "$SETTINGS_W")" ] && [ ! -w "$(dirname "$SETTINGS_W")" ]; }; then
  if [ -f "$SETTINGS_W" ] && jq -e --arg cmd "$CMD" '.statusLine.command == $cmd
       and ([.hooks.Stop[]?.hooks[]?.command // empty] | any(contains("caveman-stats-refresh.sh")) | not)' "$SETTINGS_W" >/dev/null 2>&1; then
    SETTINGS_RO=1
  else
    echo "error: can't edit $SETTINGS_W: read-only (managed by Nix home-manager or"
    echo "  similar?). Set this in the settings source instead, then rerun:"
    jq -nc --arg cmd "$CMD" '{statusLine: {type: "command", command: $cmd, refreshInterval: 5}}' | sed 's/^/  /'
    echo "  (and drop any Stop hook entry that runs caveman-stats-refresh.sh)"
    exit 1
  fi
fi

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

if [ "$SETTINGS_RO" = 0 ]; then
  [ -f "$SETTINGS_W" ] || echo '{}' > "$SETTINGS_W"
  tmp=$(mktemp "$SETTINGS_W.XXXXXX")
  jq --arg cmd "$CMD" '.statusLine = {type: "command", command: $cmd, refreshInterval: 5}' \
     "$SETTINGS_W" > "$tmp" && mv "$tmp" "$SETTINGS_W" || { rm -f "$tmp"; exit 1; }
fi

# Older versions wired a Stop hook to refresh caveman's savings estimate for the
# badge. Caveman 4 dropped that estimate, so unwire our entry (only ours: its
# command names caveman-stats-refresh.sh) and delete our bundled script.
# Caveman's own hook files in hooks/ are left alone.
if [ "$SETTINGS_RO" = 0 ] && jq -e '[.hooks.Stop[]?.hooks[]?.command // empty] | any(contains("caveman-stats-refresh.sh"))' "$SETTINGS_W" >/dev/null 2>&1; then
  tmp=$(mktemp "$SETTINGS_W.XXXXXX")
  jq '
    .hooks.Stop = [.hooks.Stop[] | select(([.hooks[]?.command // empty] | any(contains("caveman-stats-refresh.sh"))) | not)]
    | if .hooks.Stop == [] then del(.hooks.Stop) else . end
    | if .hooks == {} then del(.hooks) else . end
  ' "$SETTINGS_W" > "$tmp" && mv "$tmp" "$SETTINGS_W" || { rm -f "$tmp"; exit 1; }
  echo "removed the old caveman stats Stop hook (no longer needed)"
fi
rm -f "$CFG/hooks/caveman-stats-refresh.sh"

echo "Installed. Statusline active in new Claude Code sessions."
echo "  script:   $CFG/statusline.sh"
if [ "$SETTINGS_RO" = 1 ]; then
  echo "  settings: $SETTINGS (read-only, already set up; not changed)"
else
  echo "  settings: $SETTINGS (statusLine key merged; nothing else changed except the old caveman Stop hook, if one was there)"
fi
