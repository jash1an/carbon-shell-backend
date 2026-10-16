#!/usr/bin/env bash

export PATH="$HOME/.local/bin:$PATH"

pkill -x waybar
pkill -x waybar-bin
pkill -x swaync

sleep 0.2

setsid -f "$HOME/.local/bin/waybar" -c "$HOME/.config/waybar/config.jsonc" -s "$HOME/.config/waybar/style.css" >/tmp/waybar.log 2>&1
setsid -f "$HOME/.local/bin/swaync" >/dev/null 2>&1
