#!/bin/bash
# Builds the release tarball with only what's needed to run, install, and
# uninstall — no docs. Output: claude-statusline.tar.gz next to this script
# (gitignored; ships as a GitHub release asset, not a committed file).
#
# Usage: ./make-tarball.sh
set -euo pipefail
cd "$(dirname "$0")"
tar czf claude-statusline.tar.gz --transform 's,^,claude-statusline/,' \
  statusline.sh install.sh uninstall.sh caveman-stats-refresh.sh
echo "built: $(pwd)/claude-statusline.tar.gz"
tar tzf claude-statusline.tar.gz
