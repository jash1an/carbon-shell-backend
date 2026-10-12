#!/bin/sh
# Carbon night light controller
# Usage: carbon-night.sh <on|off|toggle|status>

ACTION="$1"
LOCKFILE="/tmp/carbon-night.on"

case "$ACTION" in
    on)
        pkill -x hyprsunset >/dev/null 2>&1
        sleep 0.15
        (nohup hyprsunset -t 3500 </dev/null >/dev/null 2>&1 &)
        touch "$LOCKFILE"
        ;;
    off)
        pkill -x hyprsunset >/dev/null 2>&1
        sleep 0.15
        (nohup hyprsunset -i </dev/null >/dev/null 2>&1 & PID=$!; sleep 0.35; kill $PID 2>/dev/null) &
        rm -f "$LOCKFILE"
        ;;
    toggle)
        if [ -f "$LOCKFILE" ] && pgrep -f "hyprsunset.*-t" >/dev/null 2>&1; then
            pkill -x hyprsunset >/dev/null 2>&1
            sleep 0.15
            (nohup hyprsunset -i </dev/null >/dev/null 2>&1 & PID=$!; sleep 0.35; kill $PID 2>/dev/null) &
            rm -f "$LOCKFILE"
        else
            pkill -x hyprsunset >/dev/null 2>&1
            sleep 0.15
            (nohup hyprsunset -t 3500 </dev/null >/dev/null 2>&1 &)
            touch "$LOCKFILE"
        fi
        ;;
    status)
        if ! command -v hyprsunset >/dev/null 2>&1; then
            echo "missing"
        elif [ -f "$LOCKFILE" ] && pgrep -f "hyprsunset.*-t" >/dev/null 2>&1; then
            echo "on"
        else
            echo "off"
        fi
        ;;
    *)
        echo "Usage: $0 {on|off|toggle|status}"
        exit 1
        ;;
esac
exit 0
