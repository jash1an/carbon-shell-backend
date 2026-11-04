#!/usr/bin/env bash
# Carbon Shell — Toggle Focus Mode / Focus HUD (Super + Shift + F)

if [ -x "${HOME}/.config/carbon/scripts/carbon-ipc.sh" ]; then
    exec sh "${HOME}/.config/carbon/scripts/carbon-ipc.sh" focus
elif [ -x "${HOME}/.config/hypr/scripts/carbon-ipc.sh" ]; then
    exec sh "${HOME}/.config/hypr/scripts/carbon-ipc.sh" focus
fi

exit 0
