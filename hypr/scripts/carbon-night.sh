#!/bin/sh
# Carbon night light controller
# Usage: carbon-night.sh <on [temp]|off|toggle|status|get|set <pct>|temp <K>>

ACTION="$1"
VALUE="$2"

LOCKFILE="/tmp/carbon-night.on"
SHADER="${HOME:-/root}/.config/hypr/shaders/nightlight.frag"
LEVEL_FILE="${HOME:-/root}/.config/hypr/carbon-night.level"
LEVEL_FILE_ALT="${HOME:-/root}/.config/carbon/carbon-night.level"
MONITORS_JSON="${HOME:-/root}/.config/carbon/carbon-monitors.json"
MONITORS_JSON_ALT="${HOME:-/root}/.config/hypr/carbon-monitors.json"

# Auto-detect Hyprland instance and Wayland display if not in current environment
export PATH="$HOME/.local/bin:$PATH"
if [ -z "$WAYLAND_DISPLAY" ]; then
    for wd in wayland-1 wayland-0; do
        if [ -S "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/$wd" ]; then
            export WAYLAND_DISPLAY="$wd"
            break
        fi
    done
fi

if [ -z "$HYPRLAND_INSTANCE_SIGNATURE" ]; then
    hypr_base="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/hypr"
    if [ -d "$hypr_base" ]; then
        for sig in "$hypr_base"/*; do
            if [ -S "$sig/.socket.sock" ]; then
                export HYPRLAND_INSTANCE_SIGNATURE="$(basename "$sig")"
                break
            fi
        done
    fi
fi

get_saved_level() {
    if [ -f "$LEVEL_FILE" ]; then
        val=$(cat "$LEVEL_FILE" 2>/dev/null | tr -cd '0-9')
        if [ -n "$val" ]; then
            echo "$val"
            return
        fi
    fi
    if [ -f "$LEVEL_FILE_ALT" ]; then
        val=$(cat "$LEVEL_FILE_ALT" 2>/dev/null | tr -cd '0-9')
        if [ -n "$val" ]; then
            echo "$val"
            return
        fi
    fi
    if [ -f "$MONITORS_JSON" ] && command -v jq >/dev/null 2>&1; then
        val=$(jq -r '.night_light_level // empty' "$MONITORS_JSON" 2>/dev/null)
        if [ -n "$val" ] && [ "$val" != "null" ]; then
            echo "$val"
            return
        fi
    fi
    echo "50"
}

save_level() {
    lvl="$1"
    mkdir -p "$(dirname "$LEVEL_FILE")" "$(dirname "$LEVEL_FILE_ALT")" 2>/dev/null
    echo "$lvl" > "$LEVEL_FILE" 2>/dev/null || true
    echo "$lvl" > "$LEVEL_FILE_ALT" 2>/dev/null || true
}

update_config() {
    en="$1"
    lvl="$2"
    tmp="$3"
    for jf in "$MONITORS_JSON" "$MONITORS_JSON_ALT"; do
        if [ -f "$jf" ] && command -v jq >/dev/null 2>&1; then
            tmp_j="${jf}.tmp.$$"
            filter="."
            if [ "$en" = "true" ]; then
                filter="$filter | .night_light_enabled = true"
            elif [ "$en" = "false" ]; then
                filter="$filter | .night_light_enabled = false"
            fi
            if [ -n "$lvl" ]; then
                filter="$filter | .night_light_level = ($lvl | tonumber)"
            fi
            if [ -n "$tmp" ]; then
                filter="$filter | .night_light_temp = ($tmp | tonumber)"
            fi
            jq "$filter" "$jf" > "$tmp_j" 2>/dev/null && mv "$tmp_j" "$jf" || rm -f "$tmp_j"
        fi
    done
}

get_status() {
    if pgrep -x hyprsunset >/dev/null 2>&1 || [ -f "$LOCKFILE" ]; then
        echo "on"
    else
        echo "off"
    fi
}

apply_temperature() {
    target_temp="$1"
    # Try hyprctl hyprsunset first (works if hyprsunset daemon is active)
    if hyprctl hyprsunset temperature "$target_temp" >/dev/null 2>&1; then
        return 0
    fi
    # If hyprsunset daemon is not running, launch it
    if command -v hyprsunset >/dev/null 2>&1; then
        pkill -x hyprsunset >/dev/null 2>&1 || true
        sleep 0.05
        (nohup hyprsunset -t "$target_temp" </dev/null >/dev/null 2>&1 &)
        return 0
    fi
    # Fallback to screen shader
    if [ -f "$SHADER" ]; then
        hyprctl keyword decoration:screen_shader "$SHADER" >/dev/null 2>&1
    fi
}

apply_on() {
    temp_to_use="$1"
    if [ -z "$temp_to_use" ]; then
        if [ -f "$MONITORS_JSON" ] && command -v jq >/dev/null 2>&1; then
            saved_temp=$(jq -r '.night_light_temp // empty' "$MONITORS_JSON" 2>/dev/null)
            if [ -n "$saved_temp" ] && [ "$saved_temp" != "null" ]; then
                temp_to_use="$saved_temp"
            fi
        fi
    fi
    if [ -z "$temp_to_use" ]; then
        lvl=$(get_saved_level)
        temp_to_use=$((6500 - (lvl * 40)))
    fi
    [ -z "$temp_to_use" ] && temp_to_use=4500
    [ "$temp_to_use" -ge 6500 ] && temp_to_use=4500

    apply_temperature "$temp_to_use"
    touch "$LOCKFILE"
    calc_lvl=$(( (6500 - temp_to_use) / 40 ))
    [ "$calc_lvl" -lt 0 ] && calc_lvl=0
    [ "$calc_lvl" -gt 100 ] && calc_lvl=100
    save_level "$calc_lvl"
    update_config true "$calc_lvl" "$temp_to_use"
}

apply_off() {
    hyprctl hyprsunset identity >/dev/null 2>&1 || true
    pkill -x hyprsunset >/dev/null 2>&1 || true
    hyprctl keyword decoration:screen_shader "" >/dev/null 2>&1 || true
    rm -f "$LOCKFILE"
    update_config false "" ""
}

case "$ACTION" in
    on)
        apply_on "$VALUE"
        ;;
    off)
        apply_off
        ;;
    toggle)
        if [ "$(get_status)" = "on" ]; then
            apply_off
        else
            apply_on "$VALUE"
        fi
        ;;
    status)
        get_status
        ;;
    get)
        get_saved_level
        ;;
    set)
        pct="$VALUE"
        [ -z "$pct" ] && pct=50
        [ "$pct" -lt 0 ] && pct=0
        [ "$pct" -gt 100 ] && pct=100
        save_level "$pct"
        temp=$((6500 - (pct * 40)))
        update_config "" "$pct" "$temp"
        if [ "$(get_status)" = "on" ]; then
            apply_temperature "$temp"
        fi
        ;;
    temp)
        k="$VALUE"
        [ -z "$k" ] && k=4500
        [ "$k" -lt 2000 ] && k=2000
        [ "$k" -gt 6500 ] && k=6500
        pct=$(( (6500 - k) / 40 ))
        [ "$pct" -lt 0 ] && pct=0
        [ "$pct" -gt 100 ] && pct=100
        save_level "$pct"
        if [ "$k" -ge 6500 ]; then
            apply_off
        else
            apply_temperature "$k"
            touch "$LOCKFILE"
            update_config true "$pct" "$k"
        fi
        ;;
    *)
        echo "Usage: $0 {on [temp]|off|toggle|status|get|set <pct>|temp <K>}"
        exit 1
        ;;
esac
exit 0
