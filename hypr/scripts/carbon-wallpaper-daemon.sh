#!/bin/bash
# ==============================================================================
# Carbon Shell — Safe Wallpaper Daemon Starter
# Ensures awww-daemon starts cleanly without crashing on stale/missing cache files
# ==============================================================================

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

# If daemon is already running and responding, exit 0
if pgrep -x awww-daemon >/dev/null 2>&1; then
    if awww query >/dev/null 2>&1; then
        exit 0
    else
        # Stale/unresponsive daemon
        pkill -9 -x awww-daemon 2>/dev/null || true
    fi
fi

# Clean stale sockets that prevent awww-daemon from binding
rm -f "$RUNTIME_DIR"/*awww*.sock 2>/dev/null || true

# Check cache files: if any cached image file does not exist, wipe awww cache so it won't crash
for f in "$HOME/.cache/awww/"*/*; do
    if [ -f "$f" ]; then
        CACHED_IMG=$(tr -d '\0' < "$f" 2>/dev/null | awk '{print $NF}')
        if [ -n "$CACHED_IMG" ] && [ ! -f "$CACHED_IMG" ]; then
            rm -rf "$HOME/.cache/awww"/* 2>/dev/null || true
            break
        fi
    fi
done

# Start daemon
/usr/bin/awww-daemon --format argb >/dev/null 2>&1 &
disown

# Wait up to 2 seconds for daemon socket to be ready
for i in {1..20}; do
    if awww query >/dev/null 2>&1; then
        break
    fi
    sleep 0.1
done

# Restore current valid wallpaper
CONFIG_DIR="${CARBON_CONFIG_DIR:-$HOME/.config/carbon}"
WALL="$CONFIG_DIR/current_wallpaper"
[ -f "$WALL" ] || WALL="$HOME/.config/hypr/current_wallpaper"
[ -f "$WALL" ] || WALL=$(find "$HOME/Pictures/Wallpapers" -type f \( -iname "*.jpg" -o -iname "*.png" \) 2>/dev/null | head -n 1)

if [ -f "$WALL" ]; then
    REAL_WALL="$(readlink -f "$WALL" 2>/dev/null || echo "$WALL")"
    if [ -f "$REAL_WALL" ]; then
        awww img "$REAL_WALL" --transition-type fade --transition-duration 0.5 >/dev/null 2>&1 || true
    fi
fi
