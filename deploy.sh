#!/bin/bash
# deploy.sh — Build production dist for CCPacker
# Usage: ./deploy.sh
#
# Produces a clean /dist/ directory with only the files needed
# on a CC:Tweaked computer.
set -euo pipefail

SOURCE="$(cd "$(dirname "$0")" && pwd)"
DIST="$SOURCE/dist"

echo "==> CCPacker Deploy"
echo "    Source: $SOURCE"
echo "    Output: $DIST"
echo ""

# Clean previous build
rm -rf "$DIST"

# Rsync production files into /dist/
# NOTE: specific excludes MUST come before include patterns
rsync -a --delete \
  --exclude='pixelui_example.lua' \
  --exclude='todo.md' \
  --exclude='CLAUDE.md' \
  --exclude='deploy.sh' \
  --exclude='.gitignore' \
  --exclude='.claude/' \
  --exclude='.git/' \
  --exclude='.DS_Store' \
  --exclude='dist/' \
  --include='*/' \
  --include='*.lua' \
  --exclude='*' \
  "$SOURCE/" "$DIST/"

# Verify DEBUG = false in production config
if grep -q '^DEBUG\s*=\s*true' "$DIST/config.lua"; then
    echo "ERROR: dist/config.lua has DEBUG = true. Set DEBUG = false for production."
    exit 1
fi

echo "==> Production files:"
echo ""
(
  cd "$DIST"
  find . -type f | sort | while read -r f; do
    size=$(wc -c < "$f" | tr -d ' ')
    printf "    %-30s %s bytes\n" "$f" "$size"
  done
)

echo ""
total=$(find "$DIST" -type f -exec wc -c {} + | tail -1 | awk '{print $1}')
echo "    Total: $total bytes across $(find "$DIST" -type f | wc -l | tr -d ' ') files"
echo ""
echo "==> Deploy to CC:Tweaked:"
echo "    Copy the contents of $DIST/"
echo "    to the /ccpacker/ directory on your computer."
