#!/bin/sh
# Launch hyprlock directly
pidof hyprlock >/dev/null 2>&1 && exit 0

if [ -x /usr/bin/hyprlock ]; then
    exec /usr/bin/hyprlock "$@"
elif command -v hyprlock >/dev/null 2>&1; then
    exec hyprlock "$@"
fi
