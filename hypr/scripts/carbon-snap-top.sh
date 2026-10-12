#!/usr/bin/env bash
# ==============================================================================
# carbon-snap-top.sh
#
# Drag a floating window up until it hits the top edge of the screen and it
# "snaps" into fullscreen — Windows-style drag-to-top = maximize.
#
# Hyprland (0.56) can't do this natively (upstream feature request still open)
# and socket2 emits nothing during window drags, so this tiny daemon polls
# window geometry and force-fullscreens a floating window the moment its top
# crosses INTO a thin band at the screen top. With `general:snap` enabled
# (edge snapping for floating windows) the drag snaps to the edge precisely.
#
# Only the downward crossing counts (a transition), so windows that merely
# rest near the top are never touched. Already-fullscreen windows (hyprctl
# `fullscreen` field 2/3 = real fullscreen) are skipped; field 1 is the
# "maximized/covering" float state which still benefits from real fullscreen.
#
# Started via `exec-once` in carbon.conf. Exits when the Hyprland session
# disappears. Idempotent.
# ==============================================================================

set -u

[[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] || exit 0

readonly HYS="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE"
readonly THRESH=18   # px from the top edge that counts as "hitting the top"
readonly POLL=0.12   # poll interval (seconds)

# Last observed top-y per window address (transition tracking).
declare -A PREV_Y=()

while true; do
    # Hyprland session gone (logout / restart) -> stop cleanly.
    [[ -d "$HYS" ]] || exit 0

    # Candidates: floating, mapped, not on a special (scratchpad) workspace,
    # and not in real fullscreen.
    data="$(hyprctl clients -j 2>/dev/null | jq -r '.[] |
        select(.floating == true
            and .mapped == true
            and ((.special // false) == false)
            and ((.fullscreen // 0) < 2)) |
        "\(.address) \(.at[1])"')"

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        set -- $line
        addr="$1"
        y="$2"

        if [[ -n "${PREV_Y[$addr]+set}" ]]; then
            prev="${PREV_Y[$addr]}"
            # Window top crossed INTO the top band -> snap it to fullscreen.
            if (( y <= THRESH && prev > THRESH )); then
                hyprctl dispatch fullscreen 1,address:"$addr" >/dev/null 2>&1
            fi
        fi
        # First sighting only records the position (no spurious trigger).
        PREV_Y[$addr]="$y"
    done <<< "$data"

    # Drop stale state if windows churn a lot.
    (( ${#PREV_Y[@]} > 256 )) && PREV_Y=()

    sleep "$POLL"
done