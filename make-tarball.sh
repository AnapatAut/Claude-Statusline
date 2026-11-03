#!/bin/bash
# Builds the release tarball with only what's needed to run, install, and
# uninstall — no docs. Output: claude-statusline.tar.gz next to this script
# (gitignored; ships as a GitHub release asset, not a committed file).
#
# Usage: ./make-tarball.sh
set -euo pipefail
cd "$(dirname "$0")"
# owner 0/0 and gzip -n: the archive carries no local user name, group or
# file name (GNU tar)
tar cf - --transform 's,^,claude-statusline/,' --owner=0 --group=0 --numeric-owner \
  statusline.sh install.sh uninstall.sh | gzip -n > claude-statusline.tar.gz
echo "built: $(pwd)/claude-statusline.tar.gz"
tar tzf claude-statusline.tar.gz
