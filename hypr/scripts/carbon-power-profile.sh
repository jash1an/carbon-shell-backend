#!/usr/bin/env bash
# ==============================================================================
# carbon-power-profile.sh: Manages power profiles and Ultra Game Mode
# Profiles:
#   power-saver : Power Saving (Eco)
#   balanced    : Balanced
#   performance : Performance
#   ultra       : Ultra (Game Mode via hypr-gamemode)
# ==============================================================================

STATE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/carbon"
PROFILE_FILE="$STATE_DIR/power-profile"
GM_STATE="${XDG_RUNTIME_DIR:-/tmp}/hypr_gamemode_state.json"

mkdir -p "$STATE_DIR"

is_gamemode_active() {
    if [ -f "$GM_STATE" ] || [ -f "/tmp/hypr_gamemode_state.json" ] || [ -f "${XDG_RUNTIME_DIR:-/run/user/1000}/hypr_gamemode_state.json" ]; then
        return 0
    fi
    return 1
}

get_profile() {
    if is_gamemode_active; then
        echo "ultra"
        return
    fi
    if [ -f "$PROFILE_FILE" ]; then
        local p
        p=$(cat "$PROFILE_FILE" 2>/dev/null | tr -d '[:space:]')
        if [ "$p" = "ultra" ]; then
            echo "balanced" > "$PROFILE_FILE"
            echo "balanced"
            return
        elif [ -n "$p" ]; then
            echo "$p"
            return
        fi
    fi
    echo "balanced"
}

set_profile() {
    local target="$1"
    case "$target" in
        ultra|game|gamemode)
            echo "ultra" > "$PROFILE_FILE"
            if ! is_gamemode_active; then
                ~/.local/bin/hypr-gamemode on >/dev/null 2>&1 || true
            fi
            if command -v powerprofilesctl >/dev/null 2>&1; then
                powerprofilesctl set performance >/dev/null 2>&1 || true
            fi
            for f in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
                [ -w "$f" ] && echo performance > "$f" 2>/dev/null || true
            done
            for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
                [ -w "$f" ] && echo performance > "$f" 2>/dev/null || true
            done
            notify-send -u low -i preferences-system-power "Power Profile: Ultra" "Game Mode activated. Maximum performance & minimum latency." 2>/dev/null || true
            ;;
        power-saver|powersave|eco)
            if is_gamemode_active; then
                ~/.local/bin/hypr-gamemode off >/dev/null 2>&1 || true
            fi
            echo "power-saver" > "$PROFILE_FILE"
            if command -v powerprofilesctl >/dev/null 2>&1; then
                powerprofilesctl set power-saver >/dev/null 2>&1 || true
            fi
            for f in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
                [ -w "$f" ] && echo power > "$f" 2>/dev/null || true
            done
            for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
                [ -w "$f" ] && echo powersave > "$f" 2>/dev/null || true
            done
            notify-send -u low -i battery "Power Profile: Power Saving" "Reduced power consumption and battery saver active." 2>/dev/null || true
            ;;
        performance)
            if is_gamemode_active; then
                ~/.local/bin/hypr-gamemode off >/dev/null 2>&1 || true
            fi
            echo "performance" > "$PROFILE_FILE"
            if command -v powerprofilesctl >/dev/null 2>&1; then
                powerprofilesctl set performance >/dev/null 2>&1 || true
            fi
            for f in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
                [ -w "$f" ] && echo performance > "$f" 2>/dev/null || true
            done
            for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
                [ -w "$f" ] && echo performance > "$f" 2>/dev/null || true
            done
            notify-send -u low -i preferences-system-power "Power Profile: Performance" "High performance profile active." 2>/dev/null || true
            ;;
        balanced|*)
            if is_gamemode_active; then
                ~/.local/bin/hypr-gamemode off >/dev/null 2>&1 || true
            fi
            echo "balanced" > "$PROFILE_FILE"
            if command -v powerprofilesctl >/dev/null 2>&1; then
                powerprofilesctl set balanced >/dev/null 2>&1 || true
            fi
            for f in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
                [ -w "$f" ] && echo balance_performance > "$f" 2>/dev/null || true
            done
            for f in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
                [ -w "$f" ] && echo powersave > "$f" 2>/dev/null || true
            done
            notify-send -u low -i battery "Power Profile: Balanced" "Standard balanced power profile active." 2>/dev/null || true
            ;;
    esac
}

case "$1" in
    get)
        get_profile
        ;;
    set)
        set_profile "$2"
        ;;
    *)
        get_profile
        ;;
esac
