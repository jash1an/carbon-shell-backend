#!/usr/bin/env bash
# Vanish Mode Dedicated Dispatcher
# Routes keybinds exclusively when Vanish Mode (nucleus) is active.
# Keeps standard desktop modes (Pill, Notch, Minimal) completely unhindered.

ACTION="$1"
CONFIG_DIR="${CARBON_CONFIG_DIR:-$HOME/.config/carbon}"
if [ ! -d "$CONFIG_DIR" ] && [ -d "$HOME/.config/hypr" ]; then
    CONFIG_DIR="$HOME/.config/hypr"
fi
MODE_FILE="$CONFIG_DIR/carbon-bar-mode.json"

CURRENT_MODE="nucleus"
if [ -f "$MODE_FILE" ]; then
    CURRENT_MODE=$(python3 -c "import json; print(json.load(open('$MODE_FILE')).get('mode', 'nucleus'))" 2>/dev/null || echo "nucleus")
fi

if [ "$CURRENT_MODE" != "nucleus" ]; then
    # In non-vanish modes, vanish shortcuts do not trigger, preventing key collisions
    exit 0
fi

IPC_SCRIPT="$CONFIG_DIR/scripts/carbon-ipc.sh"
[ -f "$IPC_SCRIPT" ] || IPC_SCRIPT="$HOME/.config/hypr/scripts/carbon-ipc.sh"

# ── Anti-Clash & Debounce State Management ───────────────────────────────────
# Prevents Super key release (toggle-hub) from firing immediately after a combo
# (e.g. SUPER+M, SUPER+W, SUPER+C, SUPER+S, SUPER+A, SUPER+Alt), and prevents
# rapid duplicate triggers.
STATE_FILE="${XDG_RUNTIME_DIR:-/tmp}/.carbon-vanish-last-action"
NOW_MS=$(date +%s%3N 2>/dev/null)
if [ -z "$NOW_MS" ] || [ ${#NOW_MS} -lt 10 ]; then
    NOW_MS=$(python3 -c 'import time; print(int(time.time() * 1000))' 2>/dev/null || echo 0)
fi

LAST_ACTION=""
LAST_TIME=0
if [ -f "$STATE_FILE" ]; then
    read -r LAST_ACTION LAST_TIME < "$STATE_FILE" 2>/dev/null
    LAST_TIME="${LAST_TIME:-0}"
fi

DIFF_MS=$(( NOW_MS - LAST_TIME ))

# 1. If another vanish shortcut was triggered within the last 450ms,
#    suppress toggle-hub (as it is just the residual Super release of that combo).
if [ "$ACTION" = "toggle-hub" ]; then
    if [ -n "$LAST_ACTION" ] && [ "$LAST_ACTION" != "toggle-hub" ] && [ "$DIFF_MS" -ge 0 ] && [ "$DIFF_MS" -lt 450 ]; then
        exit 0
    fi
    # Debounce toggle-hub if fired in rapid succession (< 250ms)
    if [ "$LAST_ACTION" = "toggle-hub" ] && [ "$DIFF_MS" -ge 0 ] && [ "$DIFF_MS" -lt 250 ]; then
        exit 0
    fi
fi

# 2. Debounce launcher if fired in rapid succession (< 250ms)
if [ "$ACTION" = "launcher" ]; then
    if [ "$LAST_ACTION" = "launcher" ] && [ "$DIFF_MS" -ge 0 ] && [ "$DIFF_MS" -lt 250 ]; then
        exit 0
    fi
fi

# Save current action and timestamp
printf "%s %s\n" "$ACTION" "$NOW_MS" > "$STATE_FILE" 2>/dev/null

case "$ACTION" in
    toggle-hub)
        sh "$IPC_SCRIPT" "nucleus toggle"
        ;;
    launcher)
        sh "$IPC_SCRIPT" "nucleus launcher"
        ;;
    lyrics)
        sh "$IPC_SCRIPT" "nucleus lyrics"
        ;;
    wallpaper)
        sh "$IPC_SCRIPT" "wallpaper"
        ;;
    focus-connect)
        sh "$IPC_SCRIPT" "nucleus focus connect"
        ;;
    focus-spaces)
        sh "$IPC_SCRIPT" "nucleus focus spaces"
        ;;
    focus-alerts)
        sh "$IPC_SCRIPT" "nucleus focus alerts"
        ;;
    *)
        exit 0
        ;;
esac
