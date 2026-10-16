#!/bin/sh
# Carbon night light controller
# Usage: carbon-night.sh <on|off|toggle|status|set <pct>|get|restore>

ACTION="$1"
LEVEL_ARG="$2"
LOCKFILE="/tmp/carbon-night.on"
LEVELFILE="/tmp/carbon-night.level"
MUTEX="/tmp/carbon-night.lock"
PERSIST_LEVEL="$HOME/.config/hypr/carbon-night.level"
SHADER_DIR="$HOME/.config/hypr/shaders"
SHADER="$SHADER_DIR/nightlight.frag"

sanitize_pct() {
    p=$(printf '%s' "$1" | tr -cd '0-9')
    [ -z "$p" ] && p=50
    if [ "$p" -lt 5 ]; then p=5; fi
    if [ "$p" -gt 100 ]; then p=100; fi
    echo "$p"
}

generate_shader() {
    pct=$(sanitize_pct "$1")

    # Green: 1.0 down to 0.80 (warm amber reduction)
    # Blue: 1.0 down to 0.35 (blue light filter)
    green=$(awk "BEGIN { printf \"%.3f\", 1.0 - (0.20 * $pct / 100.0) }")
    blue=$(awk "BEGIN { printf \"%.3f\", 1.0 - (0.65 * $pct / 100.0) }")

    mkdir -p "$SHADER_DIR"
    tmp_shader="$SHADER_DIR/.nightlight.$$.frag"
    cat <<EOF > "$tmp_shader"
#version 300 es
precision mediump float;
in vec2 v_texcoord;
uniform sampler2D tex;
out vec4 fragColor;
void main() {
    vec4 pixColor = texture(tex, v_texcoord);
    pixColor.r = min(1.0, pixColor.r * 1.0);
    pixColor.g = min(1.0, pixColor.g * ${green});
    pixColor.b = min(1.0, pixColor.b * ${blue});
    fragColor = pixColor;
}
EOF
    mv -f "$tmp_shader" "$SHADER"
}

get_level() {
    raw=""
    if [ -f "$LEVELFILE" ]; then
        raw=$(cat "$LEVELFILE" 2>/dev/null)
    fi
    if [ -z "$raw" ] && [ -f "$PERSIST_LEVEL" ]; then
        raw=$(cat "$PERSIST_LEVEL" 2>/dev/null)
    fi
    sanitize_pct "$raw"
}

save_level() {
    pct=$(sanitize_pct "$1")
    tmp_lvl="/tmp/.carbon-night-level.$$"
    printf '%s\n' "$pct" > "$tmp_lvl" && mv -f "$tmp_lvl" "$LEVELFILE"
    mkdir -p "$(dirname "$PERSIST_LEVEL")"
    tmp_persist="$PERSIST_LEVEL.$$"
    printf '%s\n' "$pct" > "$tmp_persist" 2>/dev/null && mv -f "$tmp_persist" "$PERSIST_LEVEL" 2>/dev/null || rm -f "$tmp_persist"
}

apply_on() {
    lvl=$(get_level)
    generate_shader "$lvl"
    if command -v hyprsunset >/dev/null 2>&1; then
        pkill -x hyprsunset >/dev/null 2>&1
        sleep 0.05
        # 6000K down to 2500K based on level
        temp=$((6000 - lvl * 35))
        (nohup hyprsunset -t "$temp" </dev/null >/dev/null 2>&1 9>&- &)
    else
        hyprctl keyword decoration:screen_shader "$SHADER" >/dev/null 2>&1
    fi
    touch "$LOCKFILE"
}

apply_off() {
    pkill -x hyprsunset >/dev/null 2>&1
    hyprctl keyword decoration:screen_shader "" >/dev/null 2>&1
    rm -f "$LOCKFILE"
}

case "$ACTION" in
    on)
        exec 9>"$MUTEX"
        flock -x 9
        apply_on
        ;;
    off)
        exec 9>"$MUTEX"
        flock -x 9
        apply_off
        ;;
    toggle)
        exec 9>"$MUTEX"
        flock -x 9
        if [ -f "$LOCKFILE" ]; then
            apply_off
        else
            apply_on
        fi
        ;;
    restore)
        exec 9>"$MUTEX"
        flock -x 9
        if [ -f "$LOCKFILE" ]; then
            apply_on
        fi
        ;;
    status)
        if [ -f "$LOCKFILE" ]; then
            echo "on"
        else
            echo "off"
        fi
        ;;
    set)
        save_level "$LEVEL_ARG"
        exec 9>"$MUTEX"
        flock -x 9
        val=$(get_level)
        generate_shader "$val"
        if [ -f "$LOCKFILE" ]; then
            if command -v hyprsunset >/dev/null 2>&1; then
                pkill -x hyprsunset >/dev/null 2>&1
                temp=$((6000 - val * 35))
                (nohup hyprsunset -t "$temp" </dev/null >/dev/null 2>&1 9>&- &)
            else
                hyprctl keyword decoration:screen_shader "$SHADER" >/dev/null 2>&1
            fi
        fi
        ;;
    get)
        get_level
        ;;
    *)
        echo "Usage: $0 {on|off|toggle|status|set <pct>|get|restore}"
        exit 1
        ;;
esac
exit 0
