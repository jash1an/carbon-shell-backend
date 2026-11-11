#!/usr/bin/env bash
# Carbon Shell — Matugen Scheme Changer
set -euo pipefail

SCHEME="${1:-Tonal Spot}"
CONFIG_DIR="${CARBON_CONFIG_DIR:-$HOME/.config/carbon}"
HYPR_DIR="$HOME/.config/hypr"
mkdir -p "$CONFIG_DIR" "$HYPR_DIR"

# Save selected scheme
echo "$SCHEME" > "$CONFIG_DIR/carbon-scheme.txt"
echo "$SCHEME" > "$HYPR_DIR/carbon-scheme.txt"

# Kill any previous theme generator to prevent queuing lag
pkill -f "python3.*theme-mk.py" 2>/dev/null || true

# Get wallpaper path (prefer cached display-scaled image for instant color quantization)
WP=""
SCALED="$HOME/.cache/carbon/wallpaper_scaled.jpg"
if [ -f "$SCALED" ] && [ -s "$SCALED" ]; then
    WP="$SCALED"
fi

if [ -z "$WP" ] || [ ! -f "$WP" ]; then
    for p in "$CONFIG_DIR/current_wallpaper_path" "$HYPR_DIR/current_wallpaper_path"; do
        if [ -f "$p" ]; then
            WP="$(cat "$p" 2>/dev/null | tr -d '\r\n')"
            [ -f "$WP" ] && break
        fi
    done
fi

if [ -z "$WP" ] || [ ! -f "$WP" ]; then
    WP="$HOME/.cache/carbon/wallpaper_scaled.jpg"
fi

THEME_SCRIPT="$CONFIG_DIR/scripts/theme-mk.py"
[ -f "$THEME_SCRIPT" ] || THEME_SCRIPT="$HOME/carbon-shell/hypr/scripts/theme-mk.py"

if [ -f "$THEME_SCRIPT" ]; then
    python3 "$THEME_SCRIPT" --scheme "$SCHEME" "$WP"
fi

# Direct IPC notify to Quickshell
IPC_SCRIPT="$CONFIG_DIR/scripts/carbon-ipc.sh"
[ -f "$IPC_SCRIPT" ] || IPC_SCRIPT="$HOME/carbon-shell/hypr/scripts/carbon-ipc.sh"
if [ -f "$IPC_SCRIPT" ] && [ -S "/tmp/carbon-shell.sock" ]; then
    sh "$IPC_SCRIPT" "theme-reload" 2>/dev/null || true
fi
