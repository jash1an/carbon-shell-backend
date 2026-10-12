#!/usr/bin/env bash
# Region screenshot: slurp a selection, save a timestamped PNG to
# ~/Pictures/Screenshots and copy it to the clipboard.
set -e

GEOM=$(slurp 2>/dev/null) || exit 1
DIR="$HOME/Pictures/Screenshots"
mkdir -p "$DIR"
FILE="$DIR/screenshot-$(date '+%Y-%m-%d_%H-%M-%S').png"
grim -g "$GEOM" "$FILE"
if command -v wl-copy >/dev/null 2>&1; then
    wl-copy --type image/png < "$FILE" || true
fi
if command -v notify-send >/dev/null 2>&1; then
    notify-send "Screenshot" "$(basename "$FILE")" || true
fi