#!/usr/bin/env python3
"""
Carbon Shell — Keyboard Shortcuts Manager Backend
Handles storage, presets, custom user shortcuts, conflict detection,
Tap Super modifier-only trigger, mode-specific shortcuts, export/import,
and generation of Hyprland Lua keybindings.
"""

import os
import sys
import json
import subprocess
from datetime import datetime

HOME = os.path.expanduser("~")
CARBON_DIR = os.environ.get("CARBON_CONFIG_DIR", os.path.join(HOME, ".config", "carbon"))
HYPR_DIR = os.path.join(HOME, ".config", "hypr")
REPO_HYPR_DIR = os.path.join(HOME, "carbon-shell", "hypr")

SHORTCUTS_JSON = os.path.join(CARBON_DIR, "carbon-shortcuts.json")
CUSTOM_SHORTCUTS_JSON = os.path.join(CARBON_DIR, "carbon-custom-shortcuts.json")
BAR_MODE_JSON = os.path.join(CARBON_DIR, "carbon-bar-mode.json")
KEYBINDS_LUA = os.path.join(HYPR_DIR, "keybinds.lua")
REPO_KEYBINDS_LUA = os.path.join(REPO_HYPR_DIR, "carbon", "keybinds.lua")

def get_active_bar_mode():
    if os.path.exists(BAR_MODE_JSON):
        try:
            with open(BAR_MODE_JSON, "r", encoding="utf-8") as f:
                d = json.load(f)
                return d.get("mode", "nucleus")
        except Exception:
            pass
    return "nucleus"

# Default Base Shortcuts Catalog
DEFAULT_SHORTCUTS = [
    # Shell & Controls
    {
        "id": "spotlight",
        "title": "Spotlight App Launcher",
        "desc": "Open central quick launcher and system calculator",
        "category": "Shell & Controls",
        "combo": "SUPER + Space",
        "default_combo": "SUPER + Space",
        "dispatcher": "exec_cmd",
        "target": "sh ~/.config/carbon/scripts/carbon-ipc.sh spotlight",
        "can_edit": True,
        "is_custom": False
    },
    {
        "id": "settings_hub",
        "title": "Carbon Settings Hub",
        "desc": "Open centralized Carbon Shell configuration center",
        "category": "Shell & Controls",
        "combo": "SUPER + C",
        "default_combo": "SUPER + C",
        "dispatcher": "exec_cmd",
        "target": f"{HOME}/.config/carbon/scripts/carbon-settings-hub",
        "can_edit": True,
        "is_custom": False
    },
    {
        "id": "overview",
        "title": "Carbon Overview",
        "desc": "Fluid Bohr-model workspace overview and window switcher",
        "category": "Shell & Controls",
        "combo": "SUPER + Tab",
        "default_combo": "SUPER + Tab",
        "dispatcher": "exec_cmd",
        "target": "sh ~/.config/carbon/scripts/carbon-ipc.sh toggle-overview",
        "can_edit": True,
        "is_custom": False
    },
    {
        "id": "controls",
        "title": "Control Center / Quick Toggles",
        "desc": "Open network, audio, and device control flyout",
        "category": "Shell & Controls",
        "combo": "SUPER + B",
        "default_combo": "SUPER + B",
        "dispatcher": "exec_cmd",
        "target": "sh ~/.config/carbon/scripts/carbon-ipc.sh controls",
        "can_edit": True,
        "is_custom": False
    },
    {
        "id": "wallpaper_picker",
        "title": "Wallpaper Picker",
        "desc": "Open spatial wallpaper selector and Matugen generator",
        "category": "Shell & Controls",
        "combo": "SUPER + W",
        "default_combo": "SUPER + W",
        "dispatcher": "exec_cmd",
        "target": "sh ~/.config/carbon/scripts/carbon-ipc.sh wallpaper",
        "can_edit": True,
        "is_custom": False
    },
    {
        "id": "clipboard_picker",
        "title": "Clipboard History Picker",
        "desc": "Open Cliphist terminal clipboard picker",
        "category": "Shell & Controls",
        "combo": "SUPER + V",
        "default_combo": "SUPER + V",
        "dispatcher": "exec_cmd",
        "target": f"bash -c 'kitty -e python3 {HOME}/.local/bin/carbon-clip-picker'",
        "can_edit": True,
        "is_custom": False
    },
    {
        "id": "lock_screen",
        "title": "Lock Screen",
        "desc": "Engage Hyprlock with dynamic Carbon ornament",
        "category": "Shell & Controls",
        "combo": "SUPER + L",
        "default_combo": "SUPER + L",
        "dispatcher": "exec_cmd",
        "target": "~/.config/carbon/scripts/hyprlock.sh",
        "can_edit": True,
        "is_custom": False
    },
    {
        "id": "carbon_drop",
        "title": "Carbon Drop",
        "desc": "Quick local and cloud file drop uploader",
        "category": "Shell & Controls",
        "combo": "SUPER + D",
        "default_combo": "SUPER + D",
        "dispatcher": "exec_cmd",
        "target": "~/.config/carbon/scripts/carbon-drop.sh",
        "can_edit": True,
        "is_custom": False
    },
    {
        "id": "pomodoro",
        "title": "Pomodoro Focus Timer",
        "desc": "Start or toggle Carbon interval productivity timer",
        "category": "Shell & Controls",
        "combo": "SUPER + T",
        "default_combo": "SUPER + T",
        "dispatcher": "exec_cmd",
        "target": "~/.config/carbon/scripts/carbon-pomodoro",
        "can_edit": True,
        "is_custom": False
    },
    {
        "id": "command_center",
        "title": "Command Center",
        "desc": "Open quick command runner and system status palette",
        "category": "Shell & Controls",
        "combo": "SUPER + G",
        "default_combo": "SUPER + G",
        "dispatcher": "exec_cmd",
        "target": "sh ~/.config/carbon/scripts/carbon-ipc.sh command-center",
        "can_edit": True,
        "is_custom": False
    },
    {
        "id": "carbon_pulse",
        "title": "System Monitor (Pulse)",
        "desc": "Open real-time system resource monitor",
        "category": "Shell & Controls",
        "combo": "SUPER + Escape",
        "default_combo": "SUPER + Escape",
        "dispatcher": "exec_cmd",
        "target": "~/.local/bin/carbon-pulse",
        "can_edit": True,
        "is_custom": False
    },
    {
        "id": "scratchpad",
        "title": "Special Workspace (Scratchpad)",
        "desc": "Toggle overlay scratchpad workspace",
        "category": "Shell & Controls",
        "combo": "SUPER + S",
        "default_combo": "SUPER + S",
        "dispatcher": "special_workspace",
        "target": "special:special",
        "can_edit": True,
        "is_custom": False
    },
    {
        "id": "move_scratchpad",
        "title": "Move Window to Scratchpad",
        "desc": "Send focused window into special scratchpad overlay",
        "category": "Shell & Controls",
        "combo": "SUPER + ALT + S",
        "default_combo": "SUPER + ALT + S",
        "dispatcher": "move_workspace",
        "target": "special:special",
        "can_edit": True,
        "is_custom": False
    },

    # Applications
    {
        "id": "terminal",
        "title": "Terminal Emulator",
        "desc": "Launch default Kitty terminal emulator",
        "category": "Applications",
        "combo": "SUPER + Return",
        "default_combo": "SUPER + Return",
        "dispatcher": "exec_cmd",
        "target": "kitty",
        "can_edit": True,
        "is_custom": False
    },
    {
        "id": "terminal_float",
        "title": "Floating Terminal",
        "desc": "Launch Kitty terminal in a floating 800x550 geometry",
        "category": "Applications",
        "combo": "SUPER + SHIFT + Return",
        "default_combo": "SUPER + SHIFT + Return",
        "dispatcher": "exec_cmd",
        "target": "[float; size 800 550] kitty",
        "can_edit": True,
        "is_custom": False
    },
    {
        "id": "file_manager_cli",
        "title": "File Manager (Yazi)",
        "desc": "Launch Yazi terminal file manager",
        "category": "Applications",
        "combo": "SUPER + E",
        "default_combo": "SUPER + E",
        "dispatcher": "exec_cmd",
        "target": "kitty -e yazi",
        "can_edit": True,
        "is_custom": False
    },
    {
        "id": "file_manager_gui",
        "title": "File Manager (Nautilus)",
        "desc": "Launch graphical file manager",
        "category": "Applications",
        "combo": "SUPER + N",
        "default_combo": "SUPER + N",
        "dispatcher": "exec_cmd",
        "target": "nautilus",
        "can_edit": True,
        "is_custom": False
    },
    {
        "id": "browser",
        "title": "Web Browser",
        "desc": "Launch default internet browser",
        "category": "Applications",
        "combo": "SUPER + F",
        "default_combo": "SUPER + F",
        "dispatcher": "exec_cmd",
        "target": "librewolf",
        "can_edit": True,
        "is_custom": False
    },
    {
        "id": "screenshot_region",
        "title": "Screenshot Region",
        "desc": "Capture rectangular area and copy to clipboard",
        "category": "Applications",
        "combo": "SUPER + SHIFT + S",
        "default_combo": "SUPER + SHIFT + S",
        "dispatcher": "exec_cmd",
        "target": "~/.config/carbon/scripts/carbon-screenshot-region.sh",
        "can_edit": True,
        "is_custom": False
    },
    {
        "id": "screenshot_full",
        "title": "Screenshot Full Screen",
        "desc": "Capture whole desktop display",
        "category": "Applications",
        "combo": "Print",
        "default_combo": "Print",
        "dispatcher": "exec_cmd",
        "target": "~/.config/carbon/scripts/carbon-screenshot-full.sh",
        "can_edit": True,
        "is_custom": False
    },
    {
        "id": "screenshot_window",
        "title": "Screenshot Active Window",
        "desc": "Capture only the currently focused window",
        "category": "Applications",
        "combo": "ALT + Print",
        "default_combo": "ALT + Print",
        "dispatcher": "exec_cmd",
        "target": "~/.config/carbon/scripts/carbon-screenshot-window.sh",
        "can_edit": True,
        "is_custom": False
    },
    {
        "id": "gamemode",
        "title": "Toggle Game Mode",
        "desc": "Disable blur, animations, and transparency for maximum FPS",
        "category": "Applications",
        "combo": "SUPER + F1",
        "default_combo": "SUPER + F1",
        "dispatcher": "exec_cmd",
        "target": "~/.local/bin/hypr-gamemode toggle",
        "can_edit": True,
        "is_custom": False
    },

    # Window Management
    {
        "id": "close_window",
        "title": "Close Active Window",
        "desc": "Gracefully close currently focused window",
        "category": "Window Management",
        "combo": "SUPER + X",
        "default_combo": "SUPER + X",
        "dispatcher": "close",
        "target": "",
        "can_edit": True,
        "is_custom": False
    },
    {
        "id": "fullscreen",
        "title": "Toggle Fullscreen",
        "desc": "Expand active window to full screen boundaries",
        "category": "Window Management",
        "combo": "F11",
        "default_combo": "F11",
        "dispatcher": "fullscreen",
        "target": "",
        "can_edit": True,
        "is_custom": False
    },
    {
        "id": "alt_tab",
        "title": "Cycle Next Window (Alt+Tab)",
        "desc": "Switch focus to next window in MRU history",
        "category": "Window Management",
        "combo": "ALT + Tab",
        "default_combo": "ALT + Tab",
        "dispatcher": "exec_cmd",
        "target": "hyprctl dispatch cyclenext hist && hyprctl dispatch alterzorder top",
        "can_edit": True,
        "is_custom": False
    },
    {
        "id": "alt_tab_prev",
        "title": "Cycle Previous Window",
        "desc": "Switch focus to previous window in MRU history",
        "category": "Window Management",
        "combo": "ALT + SHIFT + Tab",
        "default_combo": "ALT + SHIFT + Tab",
        "dispatcher": "exec_cmd",
        "target": "hyprctl dispatch cyclenext prev hist && hyprctl dispatch alterzorder top",
        "can_edit": True,
        "is_custom": False
    },
    {
        "id": "force_kill",
        "title": "Force Kill Window",
        "desc": "Unconditionally terminate unresponsive process (xkill style)",
        "category": "Window Management",
        "combo": "SUPER + SHIFT + Q",
        "default_combo": "SUPER + SHIFT + Q",
        "dispatcher": "exec_cmd",
        "target": "~/.config/carbon/scripts/KillActiveProcess.sh",
        "can_edit": True,
        "is_custom": False
    },
    {
        "id": "reload_compositor",
        "title": "Reload Hyprland Config",
        "desc": "Live reload Hyprland lua and conf rules",
        "category": "Window Management",
        "combo": "SUPER + SHIFT + R",
        "default_combo": "SUPER + SHIFT + R",
        "dispatcher": "exec_cmd",
        "target": "hyprctl reload",
        "can_edit": True,
        "is_custom": False
    },
    {
        "id": "exit_session",
        "title": "Exit Hyprland Session",
        "desc": "Terminate compositor session and return to display manager",
        "category": "Window Management",
        "combo": "CTRL + ALT + Delete",
        "default_combo": "CTRL + ALT + Delete",
        "dispatcher": "exec_cmd",
        "target": "hyprctl dispatch exit 0",
        "can_edit": True,
        "is_custom": False
    },
    {
        "id": "focus_left",
        "title": "Focus Window Left",
        "desc": "Move keyboard focus to the window on the left",
        "category": "Window Management",
        "combo": "SUPER + left",
        "default_combo": "SUPER + left",
        "dispatcher": "exec_cmd",
        "target": "hyprctl dispatch movefocus l",
        "can_edit": True,
        "is_custom": False
    },
    {
        "id": "focus_right",
        "title": "Focus Window Right",
        "desc": "Move keyboard focus to the window on the right",
        "category": "Window Management",
        "combo": "SUPER + right",
        "default_combo": "SUPER + right",
        "dispatcher": "exec_cmd",
        "target": "hyprctl dispatch movefocus r",
        "can_edit": True,
        "is_custom": False
    },
    {
        "id": "focus_up",
        "title": "Focus Window Up",
        "desc": "Move keyboard focus to the window above",
        "category": "Window Management",
        "combo": "SUPER + up",
        "default_combo": "SUPER + up",
        "dispatcher": "exec_cmd",
        "target": "hyprctl dispatch movefocus u",
        "can_edit": True,
        "is_custom": False
    },
    {
        "id": "focus_down",
        "title": "Focus Window Down",
        "desc": "Move keyboard focus to the window below",
        "category": "Window Management",
        "combo": "SUPER + down",
        "default_combo": "SUPER + down",
        "dispatcher": "exec_cmd",
        "target": "hyprctl dispatch movefocus d",
        "can_edit": True,
        "is_custom": False
    },
    {
        "id": "resize_left",
        "title": "Resize Window Left",
        "desc": "Contract active window width by 50px",
        "category": "Window Management",
        "combo": "SUPER + SHIFT + left",
        "default_combo": "SUPER + SHIFT + left",
        "dispatcher": "resizeactive",
        "target": "-50 0",
        "repeating": True,
        "can_edit": True,
        "is_custom": False
    },
    {
        "id": "resize_right",
        "title": "Resize Window Right",
        "desc": "Expand active window width by 50px",
        "category": "Window Management",
        "combo": "SUPER + SHIFT + right",
        "default_combo": "SUPER + SHIFT + right",
        "dispatcher": "resizeactive",
        "target": "50 0",
        "repeating": True,
        "can_edit": True,
        "is_custom": False
    },
    {
        "id": "resize_up",
        "title": "Resize Window Up",
        "desc": "Contract active window height by 50px",
        "category": "Window Management",
        "combo": "SUPER + SHIFT + up",
        "default_combo": "SUPER + SHIFT + up",
        "dispatcher": "resizeactive",
        "target": "0 -50",
        "repeating": True,
        "can_edit": True,
        "is_custom": False
    },
    {
        "id": "resize_down",
        "title": "Resize Window Down",
        "desc": "Expand active window height by 50px",
        "category": "Window Management",
        "combo": "SUPER + SHIFT + down",
        "default_combo": "SUPER + SHIFT + down",
        "dispatcher": "resizeactive",
        "target": "0 50",
        "repeating": True,
        "can_edit": True,
        "is_custom": False
    },
    {
        "id": "window_drag",
        "title": "Move Window (Mouse Drag)",
        "desc": "Drag floating or tiled window using mouse pointer",
        "category": "Window Management",
        "combo": "SUPER + mouse:272",
        "default_combo": "SUPER + mouse:272",
        "dispatcher": "drag",
        "target": "",
        "can_edit": False,
        "is_custom": False
    },
    {
        "id": "window_resize_mouse",
        "title": "Resize Window (Mouse Drag)",
        "desc": "Resize floating or tiled window using mouse pointer",
        "category": "Window Management",
        "combo": "SUPER + mouse:273",
        "default_combo": "SUPER + mouse:273",
        "dispatcher": "resize",
        "target": "",
        "can_edit": False,
        "is_custom": False
    },

    # Hardware & Media Keys
    {
        "id": "vol_up",
        "title": "Increase Audio Volume",
        "desc": "Raise master output volume by 5%",
        "category": "Hardware & Media",
        "combo": "XF86AudioRaiseVolume",
        "default_combo": "XF86AudioRaiseVolume",
        "dispatcher": "exec_cmd",
        "target": "~/.config/carbon/scripts/volume.sh --inc",
        "repeating": True,
        "locked": True,
        "can_edit": True,
        "is_custom": False
    },
    {
        "id": "vol_down",
        "title": "Decrease Audio Volume",
        "desc": "Lower master output volume by 5%",
        "category": "Hardware & Media",
        "combo": "XF86AudioLowerVolume",
        "default_combo": "XF86AudioLowerVolume",
        "dispatcher": "exec_cmd",
        "target": "~/.config/carbon/scripts/volume.sh --dec",
        "repeating": True,
        "locked": True,
        "can_edit": True,
        "is_custom": False
    },
    {
        "id": "vol_mute",
        "title": "Toggle Mute Audio",
        "desc": "Silence or unmute master audio output",
        "category": "Hardware & Media",
        "combo": "XF86AudioMute",
        "default_combo": "XF86AudioMute",
        "dispatcher": "exec_cmd",
        "target": "~/.config/carbon/scripts/volume.sh --toggle",
        "repeating": True,
        "locked": True,
        "can_edit": True,
        "is_custom": False
    },
    {
        "id": "mic_mute",
        "title": "Toggle Microphone Mute",
        "desc": "Mute or unmute default capture input device",
        "category": "Hardware & Media",
        "combo": "XF86AudioMicMute",
        "default_combo": "XF86AudioMicMute",
        "dispatcher": "exec_cmd",
        "target": "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle",
        "repeating": True,
        "locked": True,
        "can_edit": True,
        "is_custom": False
    },
    {
        "id": "bright_up",
        "title": "Increase Screen Brightness",
        "desc": "Raise display backlight brightness by 5%",
        "category": "Hardware & Media",
        "combo": "XF86MonBrightnessUp",
        "default_combo": "XF86MonBrightnessUp",
        "dispatcher": "exec_cmd",
        "target": "brightnessctl set +5%",
        "repeating": True,
        "locked": True,
        "can_edit": True,
        "is_custom": False
    },
    {
        "id": "bright_down",
        "title": "Decrease Screen Brightness",
        "desc": "Lower display backlight brightness by 5%",
        "category": "Hardware & Media",
        "combo": "XF86MonBrightnessDown",
        "default_combo": "XF86MonBrightnessDown",
        "dispatcher": "exec_cmd",
        "target": "brightnessctl set 5%-",
        "repeating": True,
        "locked": True,
        "can_edit": True,
        "is_custom": False
    },
    {
        "id": "media_play",
        "title": "Play / Pause Media",
        "desc": "Toggle playback of current media player",
        "category": "Hardware & Media",
        "combo": "XF86AudioPlay",
        "default_combo": "XF86AudioPlay",
        "dispatcher": "exec_cmd",
        "target": "playerctl play-pause",
        "locked": True,
        "can_edit": True,
        "is_custom": False
    },
    {
        "id": "media_next",
        "title": "Next Media Track",
        "desc": "Skip to next track in player queue",
        "category": "Hardware & Media",
        "combo": "XF86AudioNext",
        "default_combo": "XF86AudioNext",
        "dispatcher": "exec_cmd",
        "target": "playerctl next",
        "locked": True,
        "can_edit": True,
        "is_custom": False
    },
    {
        "id": "media_prev",
        "title": "Previous Media Track",
        "desc": "Restart current track or play previous track",
        "category": "Hardware & Media",
        "combo": "XF86AudioPrev",
        "default_combo": "XF86AudioPrev",
        "dispatcher": "exec_cmd",
        "target": "playerctl previous",
        "locked": True,
        "can_edit": True,
        "is_custom": False
    },
    {
        "id": "power_button",
        "title": "Hardware Power Button",
        "desc": "Trigger Carbon power shutdown dialog",
        "category": "Hardware & Media",
        "combo": "XF86PowerOff",
        "default_combo": "XF86PowerOff",
        "dispatcher": "exec_cmd",
        "target": "~/.config/carbon/scripts/carbon-power-handler.sh power_button",
        "locked": True,
        "can_edit": False,
        "is_custom": False
    },
    {
        "id": "sleep_button",
        "title": "Hardware Sleep Button",
        "desc": "Suspend system and lock session",
        "category": "Hardware & Media",
        "combo": "XF86Sleep",
        "default_combo": "XF86Sleep",
        "dispatcher": "exec_cmd",
        "target": "~/.config/carbon/scripts/carbon-power-handler.sh sleep_button",
        "locked": True,
        "can_edit": False,
        "is_custom": False
    },

    # Workspaces
    {
        "id": "workspaces_1_10",
        "title": "Switch to Workspace 1–10",
        "desc": "Instant navigation to virtual workspaces 1 through 10",
        "category": "Workspaces",
        "combo": "SUPER + 1..0",
        "default_combo": "SUPER + 1..0",
        "dispatcher": "workspace",
        "target": "1..10",
        "can_edit": False,
        "is_custom": False
    },
    {
        "id": "moveto_1_10",
        "title": "Move Window to Workspace 1–10",
        "desc": "Transfer active window directly to workspaces 1 through 10",
        "category": "Workspaces",
        "combo": "SUPER + SHIFT + 1..0",
        "default_combo": "SUPER + SHIFT + 1..0",
        "dispatcher": "movetoworkspace",
        "target": "1..10",
        "can_edit": False,
        "is_custom": False
    },
    {
        "id": "scroll_workspace",
        "title": "Scroll Workspaces (Mouse Wheel)",
        "desc": "Switch to adjacent workspace using Super + mouse scroll wheel",
        "category": "Workspaces",
        "combo": "SUPER + mouse_up/down",
        "default_combo": "SUPER + mouse_up/down",
        "dispatcher": "workspace",
        "target": "e+/-1",
        "can_edit": False,
        "is_custom": False
    }
]

# Mode-Specific Shortcuts (dynamically injected based on active bar mode)
MODE_SHORTCUTS = {
    "vanish": [
        {
            "id": "vanish_hub",
            "title": "Toggle Vanish Hub & Radial Satellites",
            "desc": "Open or close central clock orb and radial satellites (Tap Super)",
            "category": "Active Mode: Vanish",
            "combo": "SUPER (Tap)",
            "default_combo": "SUPER (Tap)",
            "dispatcher": "exec_cmd",
            "target": "sh ~/.config/carbon/scripts/carbon-vanish-dispatch.sh toggle-hub",
            "can_edit": False,
            "is_custom": False
        },
        {
            "id": "vanish_lyrics",
            "title": "Toggle Synced Lyrics",
            "desc": "Morph bottom caption between calendar date and live synced lyrics",
            "category": "Active Mode: Vanish",
            "combo": "SUPER + M",
            "default_combo": "SUPER + M",
            "dispatcher": "exec_cmd",
            "target": "sh ~/.config/carbon/scripts/carbon-vanish-dispatch.sh lyrics",
            "can_edit": True,
            "is_custom": False
        },
        {
            "id": "vanish_alerts",
            "title": "Focus Alerts & Notifications Lobe",
            "desc": "Directly bloom System Alerts & Notifications satellite",
            "category": "Active Mode: Vanish",
            "combo": "SUPER + A",
            "default_combo": "SUPER + A",
            "dispatcher": "exec_cmd",
            "target": "sh ~/.config/carbon/scripts/carbon-vanish-dispatch.sh focus-alerts",
            "can_edit": True,
            "is_custom": False
        },
        {
            "id": "vanish_controls",
            "title": "Vanish Quick Toggles / Control Lobe",
            "desc": "Bloom Audio, Network, and Device control satellite",
            "category": "Active Mode: Vanish",
            "combo": "SUPER + B",
            "default_combo": "SUPER + B",
            "dispatcher": "exec_cmd",
            "target": "sh ~/.config/carbon/scripts/carbon-vanish-dispatch.sh quick-toggles",
            "can_edit": True,
            "is_custom": False
        }
    ],
    "nucleus": [
        {
            "id": "vanish_hub",
            "title": "Toggle Vanish Hub & Radial Satellites",
            "desc": "Open or close central clock orb and radial satellites (Tap Super)",
            "category": "Active Mode: Nucleus",
            "combo": "SUPER (Tap)",
            "default_combo": "SUPER (Tap)",
            "dispatcher": "exec_cmd",
            "target": "sh ~/.config/carbon/scripts/carbon-vanish-dispatch.sh toggle-hub",
            "can_edit": False,
            "is_custom": False
        },
        {
            "id": "vanish_lyrics",
            "title": "Toggle Synced Lyrics",
            "desc": "Morph bottom caption between calendar date and live synced lyrics",
            "category": "Active Mode: Nucleus",
            "combo": "SUPER + M",
            "default_combo": "SUPER + M",
            "dispatcher": "exec_cmd",
            "target": "sh ~/.config/carbon/scripts/carbon-vanish-dispatch.sh lyrics",
            "can_edit": True,
            "is_custom": False
        },
        {
            "id": "vanish_alerts",
            "title": "Focus Alerts & Notifications Lobe",
            "desc": "Directly bloom System Alerts & Notifications satellite",
            "category": "Active Mode: Nucleus",
            "combo": "SUPER + A",
            "default_combo": "SUPER + A",
            "dispatcher": "exec_cmd",
            "target": "sh ~/.config/carbon/scripts/carbon-vanish-dispatch.sh focus-alerts",
            "can_edit": True,
            "is_custom": False
        },
        {
            "id": "vanish_controls",
            "title": "Vanish Quick Toggles / Control Lobe",
            "desc": "Bloom Audio, Network, and Device control satellite",
            "category": "Active Mode: Nucleus",
            "combo": "SUPER + B",
            "default_combo": "SUPER + B",
            "dispatcher": "exec_cmd",
            "target": "sh ~/.config/carbon/scripts/carbon-vanish-dispatch.sh quick-toggles",
            "can_edit": True,
            "is_custom": False
        }
    ],
    "minimal": [
        {
            "id": "minimal_cc",
            "title": "Toggle Tide Control Center",
            "desc": "Open Minimal Island quick settings and controls flyout",
            "category": "Active Mode: Minimal",
            "combo": "SUPER + SHIFT + E",
            "default_combo": "SUPER + SHIFT + E",
            "dispatcher": "exec_cmd",
            "target": "/usr/bin/quickshell ipc --any-display -p ~/.local/share/quickshell/carbon call tide toggleControlCenter",
            "can_edit": True,
            "is_custom": False
        },
        {
            "id": "minimal_player",
            "title": "Toggle Media Player Pill",
            "desc": "Expand media controls pill in island bar",
            "category": "Active Mode: Minimal",
            "combo": "SUPER + M",
            "default_combo": "SUPER + M",
            "dispatcher": "exec_cmd",
            "target": "/usr/bin/quickshell ipc --any-display -p ~/.local/share/quickshell/carbon call tide togglePlayer",
            "can_edit": True,
            "is_custom": False
        },
        {
            "id": "minimal_swipe_r",
            "title": "Island Next Module",
            "desc": "Swipe right to next active module in Minimal Island",
            "category": "Active Mode: Minimal",
            "combo": "SUPER + Right",
            "default_combo": "SUPER + Right",
            "dispatcher": "exec_cmd",
            "target": "/usr/bin/quickshell ipc --any-display -p ~/.local/share/quickshell/carbon call tide swipeRight",
            "can_edit": True,
            "is_custom": False
        },
        {
            "id": "minimal_swipe_l",
            "title": "Island Previous Module",
            "desc": "Swipe left to previous active module in Minimal Island",
            "category": "Active Mode: Minimal",
            "combo": "SUPER + Left",
            "default_combo": "SUPER + Left",
            "dispatcher": "exec_cmd",
            "target": "/usr/bin/quickshell ipc --any-display -p ~/.local/share/quickshell/carbon call tide swipeLeft",
            "can_edit": True,
            "is_custom": False
        }
    ]
}

# Preset Variations
PRESET_DEFINITIONS = {
    "carbon_default": {
        "name": "Carbon Default",
        "desc": "Official Carbon Shell workflow (SUPER+Space launcher, SUPER+X close, SUPER+Return terminal)",
        "overrides": {}
    },
    "tiling_i3": {
        "name": "Tiling WM (i3 / Sway style)",
        "desc": "Classic tiling hotkeys (SUPER+Shift+Q close, SUPER+D launcher, vim-style navigation)",
        "overrides": {
            "close_window": "SUPER + SHIFT + Q",
            "spotlight": "SUPER + D",
            "fullscreen": "SUPER + F",
            "terminal": "SUPER + Return",
            "resize_left": "SUPER + SHIFT + H",
            "resize_down": "SUPER + SHIFT + J",
            "resize_up": "SUPER + SHIFT + K",
            "resize_right": "SUPER + SHIFT + L"
        }
    },
    "macos_gnome": {
        "name": "macOS / GNOME style",
        "desc": "Familiar desktop conventions (ALT+Space Spotlight, SUPER overview, CTRL+ALT+T terminal)",
        "overrides": {
            "spotlight": "ALT + Space",
            "overview": "SUPER + S",
            "close_window": "SUPER + W",
            "terminal": "CTRL + ALT + T",
            "screenshot_region": "SUPER + SHIFT + 4",
            "screenshot_full": "SUPER + SHIFT + 3",
            "lock_screen": "SUPER + CTRL + Q"
        }
    }
}

def load_json(path, default=None):
    if default is None:
        default = {}
    if os.path.exists(path):
        try:
            with open(path, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass
    return default

def save_json(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)

def get_config():
    cfg = load_json(SHORTCUTS_JSON, {})
    custom = load_json(CUSTOM_SHORTCUTS_JSON, [])
    active_mode = get_active_bar_mode()

    tap_super = cfg.get("tap_super", False)
    tap_super_action = cfg.get("tap_super_action", "spotlight")
    preset = cfg.get("preset", "carbon_default")
    user_combos = cfg.get("combos", {})

    shortcuts_map = {}
    # 1. Base shortcuts
    for s in DEFAULT_SHORTCUTS:
        item = s.copy()
        if item["id"] in user_combos:
            item["combo"] = user_combos[item["id"]]
        shortcuts_map[item["id"]] = item

    # 2. Mode-specific shortcuts
    mode_items = MODE_SHORTCUTS.get(active_mode, [])
    for m in mode_items:
        m_item = m.copy()
        if m_item["id"] in user_combos:
            m_item["combo"] = user_combos[m_item["id"]]
        shortcuts_map[m_item["id"]] = m_item

    # 3. Custom shortcuts
    custom_list = []
    for c in custom:
        c_item = {
            "id": c.get("id"),
            "title": c.get("title", "Custom Shortcut"),
            "desc": c.get("command", ""),
            "category": "Custom",
            "combo": c.get("combo", "Unset"),
            "default_combo": c.get("combo", "Unset"),
            "dispatcher": "exec_cmd",
            "target": c.get("command", ""),
            "can_edit": True,
            "is_custom": True
        }
        custom_list.append(c_item)

    all_shortcuts = list(shortcuts_map.values()) + custom_list

    return {
        "active_mode": active_mode,
        "tap_super": tap_super,
        "tap_super_action": tap_super_action,
        "preset": preset,
        "presets_available": [
            {"id": k, "name": v["name"], "desc": v["desc"]} for k, v in PRESET_DEFINITIONS.items()
        ],
        "shortcuts": all_shortcuts,
        "custom": custom
    }

def normalize_combo(combo_str):
    if not combo_str:
        return ""
    parts = [p.strip().upper() for p in combo_str.split("+") if p.strip()]
    mods = []
    key = ""
    for p in parts:
        if p in ("SUPER", "MOD4", "WIN"):
            mods.append("SUPER")
        elif p in ("CTRL", "CONTROL"):
            mods.append("CTRL")
        elif p in ("ALT", "MOD1"):
            mods.append("ALT")
        elif p == "SHIFT":
            mods.append("SHIFT")
        else:
            key = p
    mods.sort()
    return " + ".join(mods + ([key] if key else []))

def find_conflict(new_combo, ignore_id=None):
    """Check if new_combo is already claimed by any active shortcut."""
    if not new_combo or new_combo.strip() in ("", "Unset", "unset", "none"):
        return None
    norm_new = normalize_combo(new_combo)
    cfg = get_config()
    for s in cfg["shortcuts"]:
        if ignore_id and s["id"] == ignore_id:
            continue
        if s.get("combo") in ("", "Unset", "unset", "none"):
            continue
        if normalize_combo(s.get("combo", "")) == norm_new:
            return s
    return None

def generate_lua_bindings(config):
    """
    Generates pristine Hyprland Lua code for all keybindings.
    """
    lines = [
        "-- ==============================================================================",
        "-- CARBON SHELL — HYPRLAND MASTER KEYBINDINGS (LUA)",
        "-- Auto-generated by Carbon Shortcuts Manager",
        f"-- Last Updated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
        "-- ==============================================================================",
        "",
        'local mainMod = "SUPER"',
        f'local home = os.getenv("HOME") or "{HOME}"',
        'local terminal = (function()',
        f'    local opt_kitty = home .. "/.local/opt/kitty/bin/kitty"',
        '    local f = io.open(opt_kitty, "r")',
        '    if f ~= nil then',
        '        f:close()',
        '        return opt_kitty',
        '    end',
        '    return "kitty"',
        'end)()',
        'local fileManager = "kitty -e yazi"',
        ""
    ]

    # Tap Super standalone modifier-only release bind
    if config.get("tap_super"):
        action = config.get("tap_super_action", "spotlight")
        if action == "overview":
            tap_cmd = 'sh ~/.config/carbon/scripts/carbon-ipc.sh toggle-overview'
        elif action == "command-center":
            tap_cmd = 'sh ~/.config/carbon/scripts/carbon-ipc.sh command-center'
        elif action == "carbon-drop":
            tap_cmd = '~/.config/carbon/scripts/carbon-drop.sh'
        else:
            tap_cmd = 'sh ~/.config/carbon/scripts/carbon-ipc.sh spotlight'

        lines.extend([
            "-- ==============================================================================",
            "-- MODIFIER-ONLY TRIGGER (Standalone Super Key Tap)",
            "-- ==============================================================================",
            f'hl.bind("SUPER + Super_L", hl.dsp.exec_cmd("{tap_cmd}"), {{ release = true }})',
            f'hl.bind("SUPER + Super_R", hl.dsp.exec_cmd("{tap_cmd}"), {{ release = true }})',
            ""
        ])

    # Group shortcuts by category
    categories = ["Applications", "Shell & Controls", "Window Management", "Hardware & Media", "Custom"]
    # Add active mode category dynamically
    mode_cat = f"Active Mode: {config.get('active_mode', 'nucleus').capitalize()}"
    if mode_cat not in categories:
        categories.insert(2, mode_cat)

    grouped = {c: [] for c in categories}
    for s in config["shortcuts"]:
        cat = s.get("category", "Shell & Controls")
        if cat in grouped:
            grouped[cat].append(s)
        elif cat.startswith("Active Mode"):
            if mode_cat in grouped:
                grouped[mode_cat].append(s)
            else:
                grouped["Shell & Controls"].append(s)
        else:
            grouped["Shell & Controls"].append(s)

    for cat in categories:
        items = grouped[cat]
        if not items:
            continue
        lines.append(f"-- ==============================================================================")
        lines.append(f"-- {cat.upper()}")
        lines.append(f"-- ==============================================================================")

        for item in items:
            combo = item.get("combo", "").strip()
            # If deleted / unset, skip registering in Lua completely!
            if not combo or combo.lower() in ("unset", "none") or ".." in combo or "mouse" in combo or "Tap" in combo:
                continue

            disp = item.get("dispatcher", "exec_cmd")
            target = item.get("target", "").strip()
            opts = []
            if item.get("repeating"):
                opts.append("repeating = true")
            if item.get("locked"):
                opts.append("locked = true")

            opt_str = f", {{ {', '.join(opts)} }}" if opts else ""

            # Build dispatcher expression
            if disp == "close":
                call_expr = "hl.dsp.window.close()"
            elif disp == "fullscreen":
                call_expr = "hl.dsp.window.fullscreen()"
            elif disp == "toggle_float":
                call_expr = 'hl.dsp.window.float({ action = "toggle" })'
            elif disp == "special_workspace":
                call_expr = f'hl.dsp.focus({{ workspace = "{target}" }})'
            elif disp == "move_workspace":
                call_expr = f'hl.dsp.window.move({{ workspace = "{target}" }})'
            elif disp == "resizeactive":
                call_expr = f'hl.dsp.exec_cmd("hyprctl dispatch resizeactive {target}")'
            elif disp == "exec_cmd":
                clean_target = target.replace('"', '\\"')
                call_expr = f'hl.dsp.exec_cmd("{clean_target}")'
            else:
                clean_target = target.replace('"', '\\"')
                call_expr = f'hl.dsp.exec_cmd("{clean_target}")'

            lines.append(f'hl.bind("{combo}", {call_expr}{opt_str})')

        lines.append("")

    # Workspaces and Mouse Dragging
    lines.extend([
        "-- ==============================================================================",
        "-- WORKSPACES (1-10) & NAVIGATION",
        "-- ==============================================================================",
        'for i = 1, 9 do',
        '    hl.bind(mainMod .. " + " .. i, hl.dsp.focus({ workspace = i }))',
        '    hl.bind(mainMod .. " + SHIFT + " .. i, hl.dsp.window.move({ workspace = i }))',
        'end',
        'hl.bind(mainMod .. " + 0", hl.dsp.focus({ workspace = 10 }))',
        'hl.bind(mainMod .. " + SHIFT + 0", hl.dsp.window.move({ workspace = 10 }))',
        "",
        '-- Scroll workspaces with mouse wheel',
        'hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))',
        'hl.bind(mainMod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }))',
        "",
        '-- Move / resize windows with mouse drag',
        'hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })',
        'hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })',
        "",
        "-- Hardware power & lid switches",
        'hl.bind("XF86PowerOff", hl.dsp.exec_cmd("~/.config/carbon/scripts/carbon-power-handler.sh power_button"), { locked = true })',
        'hl.bind("XF86Sleep", hl.dsp.exec_cmd("~/.config/carbon/scripts/carbon-power-handler.sh sleep_button"), { locked = true })',
        'hl.bind("switch:on:Lid Switch", hl.dsp.exec_cmd("~/.config/carbon/scripts/carbon-power-handler.sh lid_close"), { locked = true })',
        'hl.bind("switch:off:Lid Switch", hl.dsp.exec_cmd("~/.config/carbon/scripts/carbon-power-handler.sh lid_open"), { locked = true })',
        ""
    ])

    return "\n".join(lines)

def apply_and_reload(config):
    """Writes updated configuration files and reloads Hyprland."""
    lua_code = generate_lua_bindings(config)

    for p in [KEYBINDS_LUA, REPO_KEYBINDS_LUA]:
        try:
            os.makedirs(os.path.dirname(p), exist_ok=True)
            with open(p, "w", encoding="utf-8") as f:
                f.write(lua_code)
        except Exception as e:
            print(f"Warning: could not write {p}: {e}", file=sys.stderr)

    try:
        subprocess.run(["hyprctl", "reload", "config-only"], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        pass

def main():
    if len(sys.argv) < 2:
        print("Usage: carbon-shortcuts-apply.py {get|set|unset|add-custom|remove-custom|set-tap-super|apply-preset|reset-all|reset-one|check-conflict|export|import|sync}")
        sys.exit(1)

    cmd = sys.argv[1]

    if cmd == "get":
        cfg = get_config()
        print(json.dumps(cfg))
        sys.exit(0)

    elif cmd == "set" and len(sys.argv) >= 4:
        item_id = sys.argv[2]
        new_combo = sys.argv[3]
        cfg_data = load_json(SHORTCUTS_JSON, {})
        combos = cfg_data.get("combos", {})
        combos[item_id] = new_combo
        cfg_data["combos"] = combos
        save_json(SHORTCUTS_JSON, cfg_data)

        # Check if it is a custom shortcut
        custom = load_json(CUSTOM_SHORTCUTS_JSON, [])
        for c in custom:
            if c.get("id") == item_id:
                c["combo"] = new_combo
        save_json(CUSTOM_SHORTCUTS_JSON, custom)

        full_cfg = get_config()
        apply_and_reload(full_cfg)
        print(json.dumps({"status": "ok", "id": item_id, "combo": new_combo}))
        sys.exit(0)

    elif cmd in ("unset", "disable") and len(sys.argv) >= 3:
        item_id = sys.argv[2]
        cfg_data = load_json(SHORTCUTS_JSON, {})
        combos = cfg_data.get("combos", {})
        combos[item_id] = "Unset"
        cfg_data["combos"] = combos
        save_json(SHORTCUTS_JSON, cfg_data)

        full_cfg = get_config()
        apply_and_reload(full_cfg)
        print(json.dumps({"status": "ok", "unset": item_id}))
        sys.exit(0)

    elif cmd == "add-custom" and len(sys.argv) >= 5:
        title = sys.argv[2]
        command = sys.argv[3]
        combo = sys.argv[4]
        custom_id = f"custom_{int(datetime.now().timestamp() * 1000)}"

        custom = load_json(CUSTOM_SHORTCUTS_JSON, [])
        custom.append({
            "id": custom_id,
            "title": title,
            "command": command,
            "combo": combo
        })
        save_json(CUSTOM_SHORTCUTS_JSON, custom)

        full_cfg = get_config()
        apply_and_reload(full_cfg)
        print(json.dumps({"status": "ok", "id": custom_id}))
        sys.exit(0)

    elif cmd == "remove-custom" and len(sys.argv) >= 3:
        item_id = sys.argv[2]
        custom = load_json(CUSTOM_SHORTCUTS_JSON, [])
        custom = [c for c in custom if c.get("id") != item_id]
        save_json(CUSTOM_SHORTCUTS_JSON, custom)

        full_cfg = get_config()
        apply_and_reload(full_cfg)
        print(json.dumps({"status": "ok", "removed": item_id}))
        sys.exit(0)

    elif cmd == "set-tap-super" and len(sys.argv) >= 3:
        enabled = sys.argv[2].lower() in ("true", "1", "yes")
        action = sys.argv[3] if len(sys.argv) >= 4 else "spotlight"
        cfg_data = load_json(SHORTCUTS_JSON, {})
        cfg_data["tap_super"] = enabled
        cfg_data["tap_super_action"] = action
        save_json(SHORTCUTS_JSON, cfg_data)

        full_cfg = get_config()
        apply_and_reload(full_cfg)
        print(json.dumps({"status": "ok", "tap_super": enabled, "action": action}))
        sys.exit(0)

    elif cmd == "apply-preset" and len(sys.argv) >= 3:
        preset_name = sys.argv[2]
        if preset_name not in PRESET_DEFINITIONS:
            print(json.dumps({"status": "error", "message": f"Unknown preset: {preset_name}"}))
            sys.exit(1)

        preset_data = PRESET_DEFINITIONS[preset_name]
        cfg_data = load_json(SHORTCUTS_JSON, {})
        cfg_data["preset"] = preset_name
        cfg_data["combos"] = preset_data.get("overrides", {}).copy()
        save_json(SHORTCUTS_JSON, cfg_data)

        full_cfg = get_config()
        apply_and_reload(full_cfg)
        print(json.dumps({"status": "ok", "preset": preset_name}))
        sys.exit(0)

    elif cmd == "reset-all":
        cfg_data = load_json(SHORTCUTS_JSON, {})
        cfg_data["combos"] = {}
        cfg_data["preset"] = "carbon_default"
        save_json(SHORTCUTS_JSON, cfg_data)

        full_cfg = get_config()
        apply_and_reload(full_cfg)
        print(json.dumps({"status": "ok", "message": "All shortcuts reset to Carbon defaults."}))
        sys.exit(0)

    elif cmd in ("reset-one", "restore") and len(sys.argv) >= 3:
        item_id = sys.argv[2]
        cfg_data = load_json(SHORTCUTS_JSON, {})
        combos = cfg_data.get("combos", {})
        if item_id in combos:
            del combos[item_id]
            cfg_data["combos"] = combos
            save_json(SHORTCUTS_JSON, cfg_data)

        full_cfg = get_config()
        apply_and_reload(full_cfg)
        print(json.dumps({"status": "ok", "reset": item_id}))
        sys.exit(0)

    elif cmd == "check-conflict" and len(sys.argv) >= 3:
        combo = sys.argv[2]
        ignore_id = sys.argv[3] if len(sys.argv) >= 4 else None
        conflict = find_conflict(combo, ignore_id)
        if conflict:
            print(json.dumps({
                "has_conflict": True,
                "conflicting_id": conflict["id"],
                "conflicting_title": conflict["title"],
                "conflicting_category": conflict.get("category", "")
            }))
        else:
            print(json.dumps({"has_conflict": False}))
        sys.exit(0)

    elif cmd == "export":
        export_path = sys.argv[2] if len(sys.argv) >= 3 else os.path.join(HOME, f"carbon-shortcuts-backup-{datetime.now().strftime('%Y%m%d_%H%M%S')}.json")
        cfg = get_config()
        save_json(export_path, cfg)
        print(json.dumps({"status": "ok", "exported_to": export_path}))
        sys.exit(0)

    elif cmd == "import" and len(sys.argv) >= 3:
        import_path = sys.argv[2]
        if not os.path.exists(import_path):
            print(json.dumps({"status": "error", "message": f"File not found: {import_path}"}))
            sys.exit(1)
        data = load_json(import_path, {})
        if "shortcuts" in data or "combos" in data:
            save_json(SHORTCUTS_JSON, {
                "tap_super": data.get("tap_super", False),
                "tap_super_action": data.get("tap_super_action", "spotlight"),
                "preset": data.get("preset", "carbon_default"),
                "combos": data.get("combos", {})
            })
            if "custom" in data:
                save_json(CUSTOM_SHORTCUTS_JSON, data["custom"])
            full_cfg = get_config()
            apply_and_reload(full_cfg)
            print(json.dumps({"status": "ok", "message": "Imported successfully."}))
        else:
            print(json.dumps({"status": "error", "message": "Invalid shortcuts file format."}))
            sys.exit(1)
        sys.exit(0)

    elif cmd == "sync":
        full_cfg = get_config()
        apply_and_reload(full_cfg)
        print(json.dumps({"status": "ok"}))
        sys.exit(0)

    else:
        print(f"Unknown command: {cmd}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
