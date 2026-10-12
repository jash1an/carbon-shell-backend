#!/usr/bin/env bash
# Fullscreen screenshot: capture all visible outputs, save a timestamped PNG
# to ~/Pictures/Screenshots, copy it to clipboard as image/png, and notify the user.
set -e

DIR="$HOME/Pictures/Screenshots"
mkdir -p "$DIR"
FILE="$DIR/screenshot-$(date '+%Y-%m-%d_%H-%M-%S').png"

grim "$FILE"
if command -v wl-copy >/dev/null 2>&1; then
    wl-copy --type image/png < "$FILE" || true
fi
if command -v notify-send >/dev/null 2>&1; then
    notify-send -a "Carbon Screenshot" -i "$FILE" "Screenshot Taken" "Full screen saved to $(basename "$FILE")" || true
fi
