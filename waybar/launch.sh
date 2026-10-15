#!/usr/bin/env bash

pkill -x waybar
pkill -x waybar-bin
pkill -x swaync

waybar -c "$HOME/.config/waybar/config.jsonc" -s "$HOME/.config/waybar/style.css" &
swaync &
