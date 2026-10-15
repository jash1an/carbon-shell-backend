#!/usr/bin/env python3
"""
Carbon Config Editor — SaneAspect / Tide Island Edition
A modern GTK4 + Libadwaita settings application for Carbon Shell & Hyprland.
Mirrors the clean, category-driven UI with Hero Cards and grouped settings cards.
"""

import os
import sys
import json
import subprocess
import shutil
import re

# Ensure fast GTK4 launch without GPU enumeration stalls
os.environ["GSK_RENDERER"] = "cairo"

import gi
gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Gtk, Adw, Gio, GLib, Gdk
import time

try:
    from carbon_tile_cropper import (
        ImageCropDialog,
        BLANK_TILE_CONFIG_PATH,
        BLANK_TILE_CROP_PATH,
        BLANK_TILE_HYPR_PATH,
        BLANK_TILE_HYPR_CROP_PATH
    )
except ImportError:
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from carbon_tile_cropper import (
        ImageCropDialog,
        BLANK_TILE_CONFIG_PATH,
        BLANK_TILE_CROP_PATH,
        BLANK_TILE_HYPR_PATH,
        BLANK_TILE_HYPR_CROP_PATH
    )

# ── Configuration Paths (Isolated Carbon Runtime with Hypr fallback) ────
CONFIG_DIR = os.environ.get("CARBON_CONFIG_DIR", os.path.expanduser("~/.config/carbon"))
HYPR_DIR = os.path.expanduser("~/.config/hypr")

BAR_MODE_PATH = os.path.join(CONFIG_DIR, "carbon-bar-mode.json")
BAR_POS_PATH = os.path.join(CONFIG_DIR, "carbon-bar-position.json")
CLOCK_STYLE_PATH = os.path.join(CONFIG_DIR, "carbon-clock-style.json")
MOTION_CONFIG_PATH = os.path.join(CONFIG_DIR, "carbon-motion.json")
LAUNCHER_CONFIG_PATH = os.path.join(CONFIG_DIR, "carbon-launcher.json")
NOTIF_CONFIG_PATH = os.path.join(CONFIG_DIR, "carbon-notifications.json")
CONTROL_CONFIG_PATH = os.path.join(CONFIG_DIR, "carbon-control-center.json")
LOCKSCREEN_CONFIG_PATH = os.path.join(CONFIG_DIR, "carbon-lockscreen.json")
VANISH_SHORTCUTS_PATH = os.path.join(CONFIG_DIR, "carbon-vanish-shortcuts.json")
VANISH_KEYBINDS_CONF_PATH = os.path.join(CONFIG_DIR, "vanish-keybinds.conf")
VANISH_KEYBINDS_LUA_PATH = os.path.expanduser("~/.config/hypr/hyprland/vanish_keybinds.lua")
VANISH_DISPATCH_SCRIPT = os.path.join(CONFIG_DIR, "scripts/carbon-vanish-dispatch.sh")
VARIABLES_PATH = os.path.join(CONFIG_DIR, "variables.lua")
THEME_PATH = os.path.join(CONFIG_DIR, "theme.json")
WALLPAPER_SOURCE_PATH = os.path.join(CONFIG_DIR, "carbon-wallpaper-source.json")

DEFAULT_VANISH_SHORTCUTS = {
    "hub_toggle": {
        "title": "Toggle Vanish Hub",
        "desc": "Open or close central clock orb and radial satellites",
        "category": "Primary Triggers",
        "mods": "",
        "key": "Super_L",
        "display_str": "SUPER",
        "action": "toggle-hub",
        "icon": "view-reveal-symbolic"
    },
    "app_search": {
        "title": "App Search and Launcher",
        "desc": "Directly open App Launcher satellite with keyboard search focus",
        "category": "Primary Triggers",
        "mods": "$mainMod",
        "key": "Alt_L",
        "display_str": "SUPER + Alt",
        "action": "launcher",
        "icon": "applications-system-symbolic"
    },
    "lyrics_toggle": {
        "title": "Toggle Synced Lyrics",
        "desc": "Morph bottom caption between calendar date and live lyrics",
        "category": "Primary Triggers",
        "mods": "$mainMod",
        "key": "M",
        "display_str": "SUPER + M",
        "action": "lyrics",
        "icon": "media-playback-start-symbolic"
    },
    "wallpaper_ring": {
        "title": "Wallpaper Ring",
        "desc": "Open circular wallpaper gallery lobe",
        "category": "Primary Triggers",
        "mods": "$mainMod",
        "key": "W",
        "display_str": "SUPER + W",
        "action": "wallpaper",
        "icon": "preferences-desktop-wallpaper-symbolic"
    },
    "focus_connect": {
        "title": "Focus Connect Lobe",
        "desc": "Directly bloom Audio, Network, and Battery satellite",
        "category": "Orbital Satellites",
        "mods": "$mainMod",
        "key": "C",
        "display_str": "SUPER + C",
        "action": "focus-connect",
        "icon": "network-wireless-symbolic"
    },
    "focus_spaces": {
        "title": "Focus Spaces Lobe",
        "desc": "Directly bloom Hyprland Workspaces satellite",
        "category": "Orbital Satellites",
        "mods": "$mainMod",
        "key": "S",
        "display_str": "SUPER + S",
        "action": "focus-spaces",
        "icon": "view-grid-symbolic"
    },
    "focus_alerts": {
        "title": "Focus Alerts Lobe",
        "desc": "Directly bloom System Alerts & Notifications satellite",
        "category": "Orbital Satellites",
        "mods": "$mainMod",
        "key": "A",
        "display_str": "SUPER + A",
        "action": "focus-alerts",
        "icon": "preferences-system-notifications-symbolic"
    }
}

def generate_vanish_keybinds_conf(shortcuts):
    dispatch_path = VANISH_DISPATCH_SCRIPT if os.path.exists(VANISH_DISPATCH_SCRIPT) else os.path.expanduser("~/.config/hypr/scripts/carbon-vanish-dispatch.sh")
    lines = [
        "#################################################################\n",
        "# VANISH MODE DEDICATED SHORTCUTS                               #\n",
        "# Auto-generated by Carbon Config Editor                        #\n",
        "#################################################################\n\n",
    ]
    for key_id, info in shortcuts.items():
        mods = info.get("mods", "").strip()
        key = info.get("key", "").strip()
        action = info.get("action", "").strip()
        if not key or not action:
            continue
        cmd = f"sh {dispatch_path} {action}"
        if key in ("Alt_L", "Alt_R", "Meta_L", "Meta_R", "Super_L", "Super_R"):
            if mods:
                lines.append(f"bindr = {mods}, {key}, exec, {cmd}\n")
            else:
                lines.append(f"bindr = , {key}, exec, {cmd}\n")
            if "$mainMod" in mods or "SUPER" in mods:
                if "Alt" in key:
                    lines.append(f"bindr = ALT, Super_L, exec, {cmd}\n")
                    lines.append(f"bindr = ALT, Super_R, exec, {cmd}\n")
        else:
            if mods:
                lines.append(f"bind = {mods}, {key}, exec, {cmd}\n")
            else:
                lines.append(f"bind = , {key}, exec, {cmd}\n")
    try:
        os.makedirs(os.path.dirname(VANISH_KEYBINDS_CONF_PATH), exist_ok=True)
        with open(VANISH_KEYBINDS_CONF_PATH, "w", encoding="utf-8") as f:
            f.writelines(lines)
    except Exception as e:
        print("Error writing vanish-keybinds.conf:", e, file=sys.stderr)

    lua_lines = [
        "-- Vanish Mode Dedicated Keybindings\n",
        "-- Auto-generated by Carbon Config Editor (Vanish Shortcuts tab)\n",
        "-- Decoupled from standard keybinds.lua and variables.lua\n\n",
        'local fn = require("hyprland.functions")\n\n',
    ]
    for key_id, info in shortcuts.items():
        mods = info.get("mods", "").strip().replace("$mainMod", "SUPER")
        key = info.get("key", "").strip()
        action = info.get("action", "").strip()
        if not key or not action:
            continue
        cmd = f'hl.dsp.exec_cmd("sh {dispatch_path} {action}")'
        if key in ("Alt_L", "Alt_R", "Meta_L", "Meta_R", "Super_L", "Super_R"):
            combo = f"{mods} + {key}" if mods else f"SUPER + {key}"
            lua_lines.append(f'hl.bind("{combo}", {cmd}, {{ release = true }})\n')
            if "Alt" in key:
                lua_lines.append(f'hl.bind("{combo}", {cmd})\n')
                lua_lines.append(f'hl.bind("ALT + Super_L", {cmd})\n')
                lua_lines.append(f'hl.bind("ALT + Super_R", {cmd})\n')
                lua_lines.append(f'hl.bind("ALT + Super_L", {cmd}, {{ release = true }})\n')
                lua_lines.append(f'hl.bind("ALT + Super_R", {cmd}, {{ release = true }})\n')
            elif "Super" in key:
                other_key = "Super_R" if key == "Super_L" else "Super_L"
                lua_lines.append(f'hl.bind("SUPER + {other_key}", {cmd}, {{ release = true }})\n')
        else:
            combo = f"{mods} + {key}" if mods else key
            lua_lines.append(f'hl.bind("{combo}", {cmd})\n')

    try:
        os.makedirs(os.path.dirname(VANISH_KEYBINDS_LUA_PATH), exist_ok=True)
        with open(VANISH_KEYBINDS_LUA_PATH, "w", encoding="utf-8") as f:
            f.writelines(lua_lines)
        repo_lua = os.path.expanduser("~/carbon-shell/hypr/hyprland/vanish_keybinds.lua")
        if os.path.exists(os.path.dirname(repo_lua)):
            with open(repo_lua, "w", encoding="utf-8") as f:
                f.writelines(lua_lines)
    except Exception as e:
        print("Error writing vanish_keybinds.lua:", e, file=sys.stderr)

def read_json(path, default=None):
    if default is None:
        default = {}
    candidates = [path]
    basename = os.path.basename(path)
    hypr_alt = os.path.join(HYPR_DIR, basename)
    if hypr_alt not in candidates:
        candidates.append(hypr_alt)
    for c in candidates:
        if os.path.exists(c):
            try:
                with open(c, "r", encoding="utf-8") as f:
                    return json.load(f)
            except Exception:
                pass
    return default

def write_json(path, data):
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, indent=2)
    except Exception as e:
        print(f"Error saving {path}: {e}", file=sys.stderr)

def read_variables():
    data = {}
    if os.path.exists(VARIABLES_PATH):
        try:
            with open(VARIABLES_PATH, "r", encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if "=" in line and not line.startswith("--"):
                        k, v = line.split("=", 1)
                        k = k.strip().replace("local ", "")
                        v = v.strip().rstrip(",;").strip('"\'')
                        data[k] = v
        except Exception:
            pass
    return data

def write_variable(key, val):
    if not os.path.exists(VARIABLES_PATH):
        return
    try:
        with open(VARIABLES_PATH, "r", encoding="utf-8") as f:
            lines = f.readlines()
        new_lines = []
        found = False
        for line in lines:
            stripped = line.strip()
            if stripped.startswith(key + " ") or stripped.startswith(key + "=") or stripped.startswith("local " + key):
                if isinstance(val, (int, float)):
                    new_lines.append(f"{key} = {val}\n")
                elif isinstance(val, bool):
                    new_lines.append(f"{key} = {'true' if val else 'false'}\n")
                else:
                    new_lines.append(f'{key} = "{val}"\n')
                found = True
            else:
                new_lines.append(line)
        if not found:
            if isinstance(val, (int, float)):
                new_lines.append(f"{key} = {val}\n")
            elif isinstance(val, bool):
                new_lines.append(f"{key} = {'true' if val else 'false'}\n")
            else:
                new_lines.append(f'{key} = "{val}"\n')
        with open(VARIABLES_PATH, "w", encoding="utf-8") as f:
            f.writelines(new_lines)
    except Exception as e:
        print(f"Error updating variables.lua: {e}", file=sys.stderr)

def apply_hyprland_layer_blur(enable: bool):
    blur_conf = os.path.expanduser("~/.config/hypr/configs/carbon-layer-blur.conf")
    try:
        with open(blur_conf, "w", encoding="utf-8") as f:
            if enable:
                f.write(
                    "layerrule = blur, carbon-.*\n"
                    "layerrule = ignorezero, carbon-.*\n"
                    "layerrule = blur, quickshell\n"
                    "layerrule = ignorezero, quickshell\n"
                    "layerrule = blur, tide-island\n"
                    "layerrule = ignorezero, tide-island\n"
                )
            else:
                f.write("# blur disabled\n")
        # Ensure windowrules.lua reloads with the new state
        subprocess.run(["hyprctl", "eval", 'dofile("/home/reduct/.config/hypr/carbon/windowrules.lua")'], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(["hyprctl", "reload"], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception as e:
        print(f"Error updating layer blur: {e}", file=sys.stderr)

def is_layer_blur_enabled():
    try:
        bp = read_json(BAR_POS_PATH, {})
        if "shellBlur" in bp:
            return bool(bp["shellBlur"])
    except Exception:
        pass
    blur_conf = os.path.expanduser("~/.config/hypr/configs/carbon-layer-blur.conf")
    if os.path.exists(blur_conf):
        try:
            with open(blur_conf, "r", encoding="utf-8") as f:
                content = f.read()
            return "layerrule = blur" in content
        except Exception:
            pass
    return True

def update_looknfeel_setting(key: str, val_str: str):
    look_path = os.path.expanduser("~/.config/hypr/configs/looknfeel.conf")
    if os.path.exists(look_path):
        try:
            with open(look_path, "r", encoding="utf-8") as f:
                content = f.read()
            pattern = rf"({key}\s*=\s*)([^\n]+)"
            if re.search(pattern, content):
                new_content = re.sub(pattern, rf"\g<1>{val_str}", content)
                with open(look_path, "w", encoding="utf-8") as f:
                    f.write(new_content)
        except Exception as e:
            print(f"Error updating looknfeel.conf: {e}", file=sys.stderr)

    lua_path = os.path.expanduser("~/.config/hypr/carbon/looknfeel.lua")
    if os.path.exists(lua_path):
        try:
            with open(lua_path, "r", encoding="utf-8") as f:
                content = f.read()
            pattern = rf"({key}\s*=\s*)([^\n,]+)(,?)"
            if re.search(pattern, content):
                new_content = re.sub(pattern, rf"\g<1>{val_str}\g<3>", content)
                with open(lua_path, "w", encoding="utf-8") as f:
                    f.write(new_content)
        except Exception as e:
            print(f"Error updating looknfeel.lua: {e}", file=sys.stderr)

# ── Config App Window ────────────────────────────────────────────────────
class CarbonConfigApp(Adw.Application):
    def __init__(self):
        super().__init__(application_id="org.carbon.configeditor", flags=Gio.ApplicationFlags.FLAGS_NONE)
        self.connect("activate", self.on_activate)

    def on_activate(self, app):
        win = self.props.active_window
        if not win:
            win = ConfigEditorWindow(self)
        win.present()

class ConfigEditorWindow(Adw.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Settings")
        self.set_default_size(860, 560)
        self.set_size_request(600, 440)

        # Theme & Accent
        theme = read_json(THEME_PATH, {})
        self.accent_hex = theme.get("accent", "#f4a7b5")
        self.accent_lit = theme.get("accentLit", "#fcd5dc")
        self.is_dark = theme.get("isDark", True)

        # Loaded Configs
        self.bar_mode = read_json(BAR_MODE_PATH, {"mode": "notch", "islandStyle": "notch"})
        self.bar_pos = read_json(BAR_POS_PATH, {})
        self.clock_cfg = read_json(CLOCK_STYLE_PATH, {"style": "titan", "format": "12"})
        self.motion_cfg = read_json(MOTION_CONFIG_PATH, {
            "reduceMotion": False,
            "movementDuration": 400,
            "fadeDuration": 200,
            "hoverResponse": 150,
            "bounce": 40
        })
        self.launcher_cfg = read_json(LAUNCHER_CONFIG_PATH, {
            "animationSpeed": 170,
            "showRecents": True,
            "clipboardHistory": True,
            "maxResults": 8
        })
        self.notif_cfg = read_json(NOTIF_CONFIG_PATH, {
            "enabled": True,
            "dnd": False,
            "timeout": 5,
            "compactIsland": True
        })
        self.control_cfg = read_json(CONTROL_CONFIG_PATH, {
            "volumeStep": 5,
            "brightnessStep": 5,
            "showBatteryPercent": True,
            "showQuickToggles": True
        })
        self.lock_cfg = read_json(LOCKSCREEN_CONFIG_PATH, {
            "layout": "modern",
            "blurRadius": 10,
            "showMedia": True
        })
        self.vanish_shortcuts = read_json(VANISH_SHORTCUTS_PATH, {})
        for k, v in DEFAULT_VANISH_SHORTCUTS.items():
            if k not in self.vanish_shortcuts:
                self.vanish_shortcuts[k] = v
        if not self.bar_mode.get("nucleus"):
            self.bar_mode["nucleus"] = {"transition": True, "animation": "quantum", "transitionWord": "Wooshh!!"}
        if "musicVisualizer" not in self.bar_mode:
            self.bar_mode["musicVisualizer"] = "liquidHalo"
        self.wallpaper_source_cfg = read_json(WALLPAPER_SOURCE_PATH, {
            "provider": "unsplash",
            "unsplash_access_key": ""
        })
        if "provider" not in self.wallpaper_source_cfg:
            self.wallpaper_source_cfg["provider"] = "unsplash"
        self.tile_cfg = read_json(BLANK_TILE_CONFIG_PATH, {
            "enabled": False,
            "imagePath": "",
            "cropPath": "",
            "cropRect": {"x": 0, "y": 0, "width": 0, "height": 0},
            "opacity": 1.0,
            "timestamp": 0
        })
        self.var_data = read_variables()

        # Navigation History
        self.nav_history = []
        self.history_index = -1
        self.is_navigating = False

        self.apply_css()
        self.build_ui()

    def apply_css(self):
        css = f"""
        window {{
            background-color: #0c0c10;
            color: #e2e2e9;
        }}
        .sidebar-container {{
            background-color: #08080c;
            border-right: 1px solid rgba(255, 255, 255, 0.05);
            padding: 12px 8px;
        }}
        .search-entry {{
            background-color: rgba(255, 255, 255, 0.05);
            border: 1px solid rgba(255, 255, 255, 0.08);
            border-radius: 12px;
            color: #ffffff;
            padding: 6px 10px;
            margin-bottom: 8px;
        }}
        .search-entry:focus {{
            border-color: {self.accent_hex};
            background-color: rgba(255, 255, 255, 0.08);
        }}
        .nav-item-row {{
            border-radius: 12px;
            padding: 6px 10px;
            margin: 2px 4px;
            transition: all 120ms ease;
        }}
        .nav-item-row:hover {{
            background-color: rgba(255, 255, 255, 0.04);
        }}
        .nav-item-row:selected {{
            background-color: rgba(255, 255, 255, 0.08);
            color: {self.accent_hex};
        }}
        .nav-item-row:selected label {{
            color: {self.accent_hex};
            font-weight: 600;
        }}
        .nav-icon-badge {{
            background-color: rgba(255, 255, 255, 0.05);
            border-radius: 16px;
            min-width: 28px;
            min-height: 28px;
        }}
        .hero-card {{
            background-color: #131318;
            border: 1px solid rgba(255, 255, 255, 0.06);
            border-radius: 18px;
            padding: 24px 20px;
            margin-bottom: 16px;
        }}
        .hero-icon-circle {{
            background-color: rgba(244, 167, 181, 0.12);
            border-radius: 28px;
            min-width: 54px;
            min-height: 54px;
        }}
        .hero-title {{
            font-size: 20px;
            font-weight: 700;
            color: #ffffff;
            margin-top: 10px;
        }}
        .hero-subtitle {{
            font-size: 12px;
            color: rgba(255, 255, 255, 0.55);
            margin-top: 2px;
        }}
        .settings-card {{
            background-color: #131318;
            border: 1px solid rgba(255, 255, 255, 0.06);
            border-radius: 18px;
            padding: 16px 20px;
            margin-bottom: 16px;
        }}
        .settings-row {{
            padding: 8px 0px;
            border-bottom: 1px solid rgba(255, 255, 255, 0.04);
        }}
        .settings-row:last-child {{
            border-bottom: none;
        }}
        .row-title {{
            font-size: 13px;
            font-weight: 500;
            color: #f0f0f5;
        }}
        .row-subtitle {{
            font-size: 11px;
            color: rgba(255, 255, 255, 0.45);
        }}
        .value-label {{
            font-size: 12px;
            font-weight: 600;
            color: {self.accent_hex};
            min-width: 60px;
        }}
        .nav-circle-btn {{
            background-color: rgba(255, 255, 255, 0.06);
            border-radius: 16px;
            min-width: 32px;
            min-height: 32px;
            padding: 0;
            border: none;
            color: #ffffff;
        }}
        .nav-circle-btn:hover {{
            background-color: rgba(255, 255, 255, 0.12);
        }}
        .nav-circle-btn:disabled {{
            opacity: 0.35;
        }}
        scale highlight {{
            background-color: {self.accent_hex};
            border-radius: 3px;
        }}
        scale trough {{
            background-color: rgba(255, 255, 255, 0.10);
            border-radius: 3px;
            min-height: 5px;
        }}
        scale slider {{
            background-color: #ffffff;
            border: 2px solid {self.accent_hex};
            border-radius: 8px;
            min-width: 14px;
            min-height: 14px;
        }}
        switch:checked {{
            background-color: {self.accent_hex};
        }}
        .blank-tile-preview {{
            background-color: #111116;
            border: 1px solid rgba(255, 255, 255, 0.12);
            border-radius: 14px;
            overflow: hidden;
        }}
        .blank-tile-preview picture, .blank-tile-preview image {{
            border-radius: 14px;
        }}
        .accent-label {{
            color: #5eead4;
            font-weight: 600;
        }}
        """
        provider = Gtk.CssProvider()
        provider.load_from_data(css.encode("utf-8"))
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_USER + 50
        )

    def build_ui(self):
        root_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.set_content(root_box)

        # Header Bar
        header = Adw.HeaderBar()
        header.set_show_end_title_buttons(True)
        title_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        t_lbl = Gtk.Label(label="Settings")
        t_lbl.add_css_class("heading")
        title_box.append(t_lbl)
        header.set_title_widget(title_box)

        # Reload Shell Button
        reload_btn = Gtk.Button(label="Apply Changes")
        reload_btn.add_css_class("suggested-action")
        reload_btn.connect("clicked", self.on_reload_shell)
        header.pack_end(reload_btn)

        root_box.append(header)

        # Main Layout: Sidebar (Left) + Content (Right)
        main_paned = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        main_paned.set_vexpand(True)
        root_box.append(main_paned)

        # ── Sidebar ────────────────────────────────────────────────────────
        sidebar_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        sidebar_box.set_size_request(230, -1)
        sidebar_box.add_css_class("sidebar-container")
        main_paned.append(sidebar_box)

        # Search Settings Entry
        self.search_entry = Gtk.SearchEntry()
        self.search_entry.set_placeholder_text("Search Settings")
        self.search_entry.add_css_class("search-entry")
        self.search_entry.connect("search-changed", self.on_search_changed)
        sidebar_box.append(self.search_entry)

        # Category List
        scrolled_nav = Gtk.ScrolledWindow()
        scrolled_nav.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scrolled_nav.set_vexpand(True)
        sidebar_box.append(scrolled_nav)

        self.nav_list = Gtk.ListBox()
        self.nav_list.set_selection_mode(Gtk.SelectionMode.SINGLE)
        self.nav_list.connect("row-selected", self.on_category_selected)
        scrolled_nav.set_child(self.nav_list)

        # ── Content Pane ───────────────────────────────────────────────────
        content_frame = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        content_frame.set_hexpand(True)
        content_frame.set_vexpand(True)
        main_paned.append(content_frame)

        # Content Top Bar: < > Navigation Buttons
        top_nav_bar = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        top_nav_bar.set_margin_start(20)
        top_nav_bar.set_margin_top(12)
        top_nav_bar.set_margin_bottom(8)
        content_frame.append(top_nav_bar)

        self.btn_back = Gtk.Button()
        self.btn_back.set_icon_name("go-previous-symbolic")
        self.btn_back.add_css_class("nav-circle-btn")
        self.btn_back.connect("clicked", self.on_go_back)
        top_nav_bar.append(self.btn_back)

        self.btn_forward = Gtk.Button()
        self.btn_forward.set_icon_name("go-next-symbolic")
        self.btn_forward.add_css_class("nav-circle-btn")
        self.btn_forward.connect("clicked", self.on_go_forward)
        top_nav_bar.append(self.btn_forward)

        # Scrolled Stack for Category Pages
        scrolled_content = Gtk.ScrolledWindow()
        scrolled_content.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        scrolled_content.set_vexpand(True)
        content_frame.append(scrolled_content)

        self.stack = Gtk.Stack()
        self.stack.set_transition_type(Gtk.StackTransitionType.CROSSFADE)
        self.stack.set_transition_duration(180)
        scrolled_content.set_child(self.stack)

        # Define the 10 SaneAspect Categories
        self.categories = [
            ("bar", "Bar & Island", "user-desktop-symbolic", "Bar & Island", "Configure bar style, island shape, position, and dimensions.", self.build_bar_page),
            ("vanish", "Vanish Mode", "view-reveal-symbolic", "Vanish Mode", "Barless atomic desktop with animated clock orb, radial satellites, and gestures.", self.build_vanish_page),
            ("blank_tile", "Blank Tile", "image-x-generic-symbolic", "Blank Tile Customization", "Personalize the top hero tile in Spotlight & Vanish launcher with custom image regions.", self.build_blank_tile_page),
            ("media", "Media", "folder-music-symbolic", "Media", "Media player controls, spinning vinyl disc, and audio visualizer.", self.build_media_page),
            ("clock", "Clock & Date", "preferences-system-time-symbolic", "Clock & Date", "Time formatting, clock typography designs, and calendar integration.", self.build_clock_page),
            ("appearance", "Appearance", "preferences-desktop-appearance-symbolic", "Appearance", "Window decorations, blur, opacity, and system themes.", self.build_appearance_page),
            ("motion", "Motion", "media-playlist-repeat-symbolic", "Motion", "How fast the shell animates, or whether it animates at all.", self.build_motion_page),
            ("launcher", "Launcher", "system-search-symbolic", "Launcher", "Spotlight search, application launcher, and quick actions.", self.build_launcher_page),
            ("notifications", "Notifications", "preferences-system-notifications-symbolic", "Notifications", "Banner popups, notification badges, and Do Not Disturb.", self.build_notifications_page),
            ("control_center", "Control Center", "emblem-system-symbolic", "Control Center", "Quick toggles, volume mixer, brightness, and network trays.", self.build_control_center_page),
            ("lockscreen", "Lock Screen", "system-lock-screen-symbolic", "Lock Screen", "Hyprlock layout, background blur, and biometric authentication.", self.build_lockscreen_page),
            ("system", "System", "preferences-system-symbolic", "System", "Performance profiles, default applications, and shell diagnostics.", self.build_system_page),
        ]

        self.nav_rows = {}
        for cat_id, title, icon_name, hero_title, hero_sub, builder_func in self.categories:
            # Add to sidebar
            row = Gtk.ListBoxRow()
            row.cat_id = cat_id
            row.title_text = title
            row.add_css_class("nav-item-row")

            row_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
            
            # Icon in circular badge
            icon_badge = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
            icon_badge.add_css_class("nav-icon-badge")
            icon_badge.set_halign(Gtk.Align.CENTER)
            icon_badge.set_valign(Gtk.Align.CENTER)
            img = Gtk.Image.new_from_icon_name(icon_name)
            img.set_pixel_size(16)
            icon_badge.append(img)
            row_box.append(icon_badge)

            lbl = Gtk.Label(label=title)
            lbl.set_halign(Gtk.Align.START)
            row_box.append(lbl)

            row.set_child(row_box)
            self.nav_list.append(row)
            self.nav_rows[cat_id] = row

            # Add page to stack
            page_widget = builder_func(icon_name, hero_title, hero_sub)
            self.stack.add_named(page_widget, cat_id)

        # Default to Motion page (matching reference screenshot)
        initial_cat = "motion"
        if initial_cat in self.nav_rows:
            self.nav_list.select_row(self.nav_rows[initial_cat])
            self.stack.set_visible_child_name(initial_cat)
            GLib.idle_add(lambda: (scrolled_content.get_vadjustment().set_value(0), False)[1])

    # ── Navigation & Search ────────────────────────────────────────────────
    def on_category_selected(self, listbox, row):
        if not row:
            return
        cat_id = row.cat_id
        if not self.is_navigating:
            if self.history_index < len(self.nav_history) - 1:
                self.nav_history = self.nav_history[:self.history_index + 1]
            self.nav_history.append(cat_id)
            self.history_index += 1
            self.update_nav_buttons()

        self.stack.set_visible_child_name(cat_id)

    def on_go_back(self, btn):
        if self.history_index > 0:
            self.history_index -= 1
            self.is_navigating = True
            cat_id = self.nav_history[self.history_index]
            self.nav_list.select_row(self.nav_rows[cat_id])
            self.is_navigating = False
            self.update_nav_buttons()

    def on_go_forward(self, btn):
        if self.history_index < len(self.nav_history) - 1:
            self.history_index += 1
            self.is_navigating = True
            cat_id = self.nav_history[self.history_index]
            self.nav_list.select_row(self.nav_rows[cat_id])
            self.is_navigating = False
            self.update_nav_buttons()

    def update_nav_buttons(self):
        self.btn_back.set_sensitive(self.history_index > 0)
        self.btn_forward.set_sensitive(self.history_index < len(self.nav_history) - 1)

    def on_search_changed(self, entry):
        query = entry.get_text().strip().lower()
        for cat_id, row in self.nav_rows.items():
            if not query or query in row.title_text.lower():
                row.set_visible(True)
            else:
                row.set_visible(False)

    # ── UI Builder Helpers ─────────────────────────────────────────────────
    def create_page_container(self, icon_name, title, subtitle):
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
        box.set_margin_start(20)
        box.set_margin_end(24)
        box.set_margin_top(4)
        box.set_margin_bottom(24)

        # Hero Card
        hero = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        hero.add_css_class("hero-card")
        hero.set_halign(Gtk.Align.FILL)

        # Centered Circle Icon
        icon_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        icon_box.set_halign(Gtk.Align.CENTER)
        icon_box.add_css_class("hero-icon-circle")
        img = Gtk.Image.new_from_icon_name(icon_name)
        img.set_pixel_size(26)
        img.set_halign(Gtk.Align.CENTER)
        img.set_valign(Gtk.Align.CENTER)
        icon_box.append(img)
        hero.append(icon_box)

        # Title
        t_lbl = Gtk.Label(label=title)
        t_lbl.add_css_class("hero-title")
        t_lbl.set_halign(Gtk.Align.CENTER)
        hero.append(t_lbl)

        # Subtitle
        s_lbl = Gtk.Label(label=subtitle)
        s_lbl.add_css_class("hero-subtitle")
        s_lbl.set_halign(Gtk.Align.CENTER)
        hero.append(s_lbl)

        box.append(hero)
        return box

    def create_settings_card(self):
        card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        card.add_css_class("settings-card")
        return card

    def add_switch_row(self, card, title, subtitle, is_active, on_toggle):
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        row.add_css_class("settings-row")

        label_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        label_box.set_hexpand(True)
        lbl_t = Gtk.Label(label=title)
        lbl_t.set_halign(Gtk.Align.START)
        lbl_t.add_css_class("row-title")
        label_box.append(lbl_t)

        if subtitle:
            lbl_s = Gtk.Label(label=subtitle)
            lbl_s.set_halign(Gtk.Align.START)
            lbl_s.add_css_class("row-subtitle")
            label_box.append(lbl_s)
        row.append(label_box)

        sw = Gtk.Switch()
        sw.set_valign(Gtk.Align.CENTER)
        sw.set_active(bool(is_active))
        if on_toggle:
            sw.connect("notify::active", lambda s, p: on_toggle(s.get_active()))
        row.append(sw)

        card.append(row)
        return sw

    def add_slider_row(self, card, title, subtitle, min_val, max_val, step, cur_val, unit="ms", on_change=None):
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        row.add_css_class("settings-row")

        label_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        label_box.set_hexpand(True)
        lbl_t = Gtk.Label(label=title)
        lbl_t.set_halign(Gtk.Align.START)
        lbl_t.add_css_class("row-title")
        label_box.append(lbl_t)

        if subtitle:
            lbl_s = Gtk.Label(label=subtitle)
            lbl_s.set_halign(Gtk.Align.START)
            lbl_s.add_css_class("row-subtitle")
            label_box.append(lbl_s)
        row.append(label_box)

        # Scale Control
        scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, min_val, max_val, step)
        scale.set_value(cur_val)
        scale.set_hexpand(True)
        scale.set_draw_value(False)
        scale.set_valign(Gtk.Align.CENTER)
        row.append(scale)

        # Live Formatted Value Label
        fmt = f"{int(cur_val)} {unit}" if unit != "x" else f"{cur_val:.2f}x"
        val_lbl = Gtk.Label(label=fmt)
        val_lbl.add_css_class("value-label")
        val_lbl.set_size_request(65, -1)
        val_lbl.set_halign(Gtk.Align.END)
        val_lbl.set_valign(Gtk.Align.CENTER)
        row.append(val_lbl)

        def on_slider_val_changed(sc):
            v = sc.get_value()
            if step >= 1:
                v = int(round(v))
                val_lbl.set_text(f"{v} {unit}")
            else:
                v = round(v, 2)
                val_lbl.set_text(f"{v:.2f}{unit}")
            if on_change:
                on_change(v)

        scale.connect("value-changed", on_slider_val_changed)
        card.append(row)
        return scale

    def add_combo_row(self, card, title, subtitle, options, cur_idx, on_change=None):
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        row.add_css_class("settings-row")

        label_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        label_box.set_hexpand(True)
        lbl_t = Gtk.Label(label=title)
        lbl_t.set_halign(Gtk.Align.START)
        lbl_t.add_css_class("row-title")
        label_box.append(lbl_t)

        if subtitle:
            lbl_s = Gtk.Label(label=subtitle)
            lbl_s.set_halign(Gtk.Align.START)
            lbl_s.add_css_class("row-subtitle")
            label_box.append(lbl_s)
        row.append(label_box)

        dropdown = Gtk.DropDown.new_from_strings(options)
        dropdown.set_selected(cur_idx if 0 <= cur_idx < len(options) else 0)
        dropdown.set_valign(Gtk.Align.CENTER)
        if on_change:
            dropdown.connect("notify::selected", lambda d, p: on_change(d.get_selected()))
        row.append(dropdown)

        card.append(row)
        return dropdown

    def add_entry_row(self, card, title, subtitle, cur_val, placeholder="", on_change=None):
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        row.add_css_class("settings-row")

        label_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        label_box.set_hexpand(True)
        lbl_t = Gtk.Label(label=title)
        lbl_t.set_halign(Gtk.Align.START)
        lbl_t.add_css_class("row-title")
        label_box.append(lbl_t)

        if subtitle:
            lbl_s = Gtk.Label(label=subtitle)
            lbl_s.set_halign(Gtk.Align.START)
            lbl_s.add_css_class("row-subtitle")
            label_box.append(lbl_s)
        row.append(label_box)

        entry = Gtk.Entry()
        entry.set_text(cur_val or "")
        if placeholder:
            entry.set_placeholder_text(placeholder)
        entry.set_valign(Gtk.Align.CENTER)
        entry.set_size_request(220, -1)
        if on_change:
            entry.connect("changed", lambda e: on_change(e.get_text()))
        row.append(entry)

        card.append(row)
        return entry

    # ── Category 1: Bar & Island ───────────────────────────────────────────
    def build_bar_page(self, icon, title, subtitle):
        page = self.create_page_container(icon, title, subtitle)

        card = self.create_settings_card()
        # Bar Mode
        modes = ["Notch Mode", "Pill Mode", "Minimal Island", "Vanish Mode (Nucleus)"]
        mode_ids = ["notch", "pill", "minimal", "nucleus"]
        cur_mode = self.bar_mode.get("mode", "notch")
        cur_idx = mode_ids.index(cur_mode) if cur_mode in mode_ids else 0

        def on_mode_selected(idx):
            mode_id = mode_ids[idx]
            self.bar_mode["mode"] = mode_id
            self.bar_mode["islandStyle"] = mode_id
            write_json(BAR_MODE_PATH, self.bar_mode)
            hypr_bar_mode = os.path.expanduser("~/.config/hypr/carbon-bar-mode.json")
            if hypr_bar_mode != BAR_MODE_PATH:
                write_json(hypr_bar_mode, self.bar_mode)
            ipc_script = os.path.join(CONFIG_DIR, "scripts/carbon-ipc.sh")
            if not os.path.exists(ipc_script):
                ipc_script = os.path.expanduser("~/.config/hypr/scripts/carbon-ipc.sh")
            if not os.path.exists(ipc_script):
                ipc_script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "carbon-ipc.sh")
            if mode_id == "nucleus":
                # Check if transition is enabled
                if self.bar_mode.get("nucleus", {}).get("transition", True):
                    subprocess.run(["sh", ipc_script, "nucleus transition"], check=False)
                else:
                    subprocess.run(["sh", ipc_script, "set-bar-mode nucleus"], check=False)
            else:
                subprocess.run(["sh", ipc_script, f"set-bar-mode {mode_id}"], check=False)

        self.add_combo_row(card, "Bar Style", "Choose screen notch, floating pill, or single dynamic island", modes, cur_idx, on_mode_selected)

        # Bar Position
        edges = ["Top", "Bottom"]
        cur_edge = self.bar_pos.get("mainBarEdge", "top")
        edge_idx = 1 if cur_edge == "bottom" else 0
        def on_edge_selected(idx):
            e = "bottom" if idx == 1 else "top"
            self.bar_pos["mainBarEdge"] = e
            write_json(BAR_POS_PATH, self.bar_pos)
        self.add_combo_row(card, "Screen Position", "Anchor bar to top or bottom edge", edges, edge_idx, on_edge_selected)

        # Bar Height
        cur_h = int(self.bar_pos.get("notchHeight", 32))
        def on_h_changed(v):
            self.bar_pos["notchHeight"] = v
            self.bar_pos["barHeight"] = v
            write_json(BAR_POS_PATH, self.bar_pos)
        self.add_slider_row(card, "Bar Height", "Vertical height of the notch / bar", 24, 48, 1, cur_h, "px", on_h_changed)

        # Notch Ear Fillet Radius
        cur_ear = int(self.bar_pos.get("notchEarRadius", 10))
        def on_ear_changed(v):
            self.bar_pos["notchEarRadius"] = v
            write_json(BAR_POS_PATH, self.bar_pos)
        self.add_slider_row(card, "Notch Ear Radius", "SaneAspect top concave fillet curve", 0, 16, 1, cur_ear, "px", on_ear_changed)

        # Notch Bottom Corner Radius
        cur_bot = int(self.bar_pos.get("notchBottomRadius", 14))
        def on_bot_changed(v):
            self.bar_pos["notchBottomRadius"] = v
            write_json(BAR_POS_PATH, self.bar_pos)
        self.add_slider_row(card, "Notch Corner Radius", "Convex rounded bottom corners", 8, 24, 1, cur_bot, "px", on_bot_changed)

        # Opacity
        cur_o = int(float(self.bar_pos.get("notchOpacity", 0.96)) * 100)
        def on_o_changed(v):
            val = round(v / 100.0, 2)
            self.bar_pos["notchOpacity"] = val
            self.bar_pos["shellOpacity"] = val
            self.bar_pos["pillOpacity"] = val
            self.bar_pos["minimalOpacity"] = val
            write_json(BAR_POS_PATH, self.bar_pos)
        self.add_slider_row(card, "Background Opacity", "Surface darkness / transparency", 20, 100, 5, cur_o, "%", on_o_changed)

        # Background Blur
        cur_blur = is_layer_blur_enabled()
        def on_blur_toggle(act):
            self.bar_pos["notchBlur"] = act
            self.bar_pos["shellBlur"] = act
            self.bar_pos["pillBlur"] = act
            write_json(BAR_POS_PATH, self.bar_pos)
            apply_hyprland_layer_blur(act)
        self.add_switch_row(card, "Frosted Glass Blur", "Enable backdrop blur behind the bar", cur_blur, on_blur_toggle)

        page.append(card)
        return page

    # ── Category: Vanish Mode ───────────────────────────────────────────────
    def build_vanish_page(self, icon, title, subtitle):
        page = self.create_page_container(icon, title, subtitle)

        # ── Card 1: Transition & Experience ──
        card1 = self.create_settings_card()

        # Switch to Vanish Mode Button
        row_mode = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        row_mode.add_css_class("settings-row")
        lbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        lbox.set_hexpand(True)
        lbl_t = Gtk.Label(label="Activate Vanish Mode")
        lbl_t.set_halign(Gtk.Align.START)
        lbl_t.add_css_class("row-title")
        lbox.append(lbl_t)
        lbl_s = Gtk.Label(label="Switch desktop to barless orbital nucleus")
        lbl_s.set_halign(Gtk.Align.START)
        lbl_s.add_css_class("row-subtitle")
        lbox.append(lbl_s)
        row_mode.append(lbox)

        btn_act = Gtk.Button(label="Switch to Vanish")
        btn_act.add_css_class("suggested-action")
        btn_act.set_valign(Gtk.Align.CENTER)
        def on_switch_vanish(b):
            self.bar_mode["mode"] = "nucleus"
            self.bar_mode["islandStyle"] = "nucleus"
            write_json(BAR_MODE_PATH, self.bar_mode)
            hypr_bar_mode = os.path.expanduser("~/.config/hypr/carbon-bar-mode.json")
            if hypr_bar_mode != BAR_MODE_PATH:
                write_json(hypr_bar_mode, self.bar_mode)
            ipc = os.path.join(CONFIG_DIR, "scripts/carbon-ipc.sh")
            if not os.path.exists(ipc):
                ipc = os.path.expanduser("~/.config/hypr/scripts/carbon-ipc.sh")
            if not os.path.exists(ipc):
                ipc = os.path.join(os.path.dirname(os.path.abspath(__file__)), "carbon-ipc.sh")
            if self.bar_mode.get("nucleus", {}).get("transition", True):
                subprocess.run(["sh", ipc, "nucleus transition"], check=False)
            else:
                subprocess.run(["sh", ipc, "set-bar-mode nucleus"], check=False)
        btn_act.connect("clicked", on_switch_vanish)
        row_mode.append(btn_act)
        card1.append(row_mode)

        # Mode-Switch Transition
        nuc_cfg = self.bar_mode.get("nucleus", {})
        trans_act = bool(nuc_cfg.get("transition", True))
        def on_trans_toggle(act):
            if "nucleus" not in self.bar_mode or not isinstance(self.bar_mode["nucleus"], dict):
                self.bar_mode["nucleus"] = {}
            self.bar_mode["nucleus"]["transition"] = bool(act)
            write_json(BAR_MODE_PATH, self.bar_mode)
            hypr_bar_mode = os.path.expanduser("~/.config/hypr/carbon-bar-mode.json")
            if hypr_bar_mode != BAR_MODE_PATH:
                write_json(hypr_bar_mode, self.bar_mode)
        self.add_switch_row(card1, "Mode-Switch Transition", "Play fullscreen transition sequence when entering Vanish", trans_act, on_trans_toggle)

        # Transition Animation Style (Quantum Collapse vs Instant Crossfade)
        anim_options = ["Quantum Collapse (~2.4s)", "Instant Crossfade (300ms)"]
        anim_ids = ["quantum", "crossfade"]
        cur_anim = nuc_cfg.get("animation", "quantum")
        cur_a_idx = anim_ids.index(cur_anim) if cur_anim in anim_ids else 0
        def on_anim_sel(idx):
            a = anim_ids[idx]
            if "nucleus" not in self.bar_mode or not isinstance(self.bar_mode["nucleus"], dict):
                self.bar_mode["nucleus"] = {}
            self.bar_mode["nucleus"]["animation"] = a
            write_json(BAR_MODE_PATH, self.bar_mode)
            hypr_bar_mode = os.path.expanduser("~/.config/hypr/carbon-bar-mode.json")
            if hypr_bar_mode != BAR_MODE_PATH:
                write_json(hypr_bar_mode, self.bar_mode)
        self.add_combo_row(card1, "Transition Animation", "Visual effect style played during mode switch", anim_options, cur_a_idx, on_anim_sel)

        # Dynamic Transition Word
        cur_word = nuc_cfg.get("transitionWord", "Wooshh!!")
        word_options = ["Wooshh!!", "Vanish!", "Hyperspace!", "Hyperdrive!", "Disappear!"]
        cur_w_idx = word_options.index(cur_word) if cur_word in word_options else 0
        def on_word_sel(idx):
            w = word_options[idx]
            if "nucleus" not in self.bar_mode or not isinstance(self.bar_mode["nucleus"], dict):
                self.bar_mode["nucleus"] = {}
            self.bar_mode["nucleus"]["transitionWord"] = w
            write_json(BAR_MODE_PATH, self.bar_mode)
            hypr_bar_mode = os.path.expanduser("~/.config/hypr/carbon-bar-mode.json")
            if hypr_bar_mode != BAR_MODE_PATH:
                write_json(hypr_bar_mode, self.bar_mode)
        self.add_combo_row(card1, "Transition Dynamic Word", "Text banner displayed during speed blur impact", word_options, cur_w_idx, on_word_sel)

        # Play Preview Button
        row_prev = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        row_prev.add_css_class("settings-row")
        lbox_p = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        lbox_p.set_hexpand(True)
        lbl_pt = Gtk.Label(label="Test Transition Animation")
        lbl_pt.set_halign(Gtk.Align.START)
        lbl_pt.add_css_class("row-title")
        lbox_p.append(lbl_pt)
        lbl_ps = Gtk.Label(label="Play the transition overlay right now")
        lbl_ps.set_halign(Gtk.Align.START)
        lbl_ps.add_css_class("row-subtitle")
        lbox_p.append(lbl_ps)
        row_prev.append(lbox_p)

        btn_prev = Gtk.Button(label="Play Transition")
        btn_prev.set_valign(Gtk.Align.CENTER)
        def on_play_prev(b):
            ipc = os.path.join(CONFIG_DIR, "scripts/carbon-ipc.sh")
            if not os.path.exists(ipc):
                ipc = os.path.expanduser("~/.config/hypr/scripts/carbon-ipc.sh")
            subprocess.run(["sh", ipc, "nucleus transition"], check=False)
        btn_prev.connect("clicked", on_play_prev)
        row_prev.append(btn_prev)
        card1.append(row_prev)

        page.append(card1)

        # ── Card 2: Visualizer & Audio ──
        card2 = self.create_settings_card()
        vis_options = ["Liquid Halo (Siri Ring)", "None"]
        vis_val = self.bar_mode.get("musicVisualizer", "liquidHalo")
        vis_idx = 0 if vis_val == "liquidHalo" else 1
        def on_v2_changed(idx):
            v = "liquidHalo" if idx == 0 else "none"
            self.bar_mode["musicVisualizer"] = v
            write_json(BAR_MODE_PATH, self.bar_mode)
        self.add_combo_row(card2, "Desktop Music Visualizer", "Organic reactive halo pulsing behind central clock orb", vis_options, vis_idx, on_v2_changed)
        page.append(card2)

        # ── Card 3: Dedicated Vanish Shortcuts ──
        card3 = self.create_settings_card()
        lbl_st = Gtk.Label(label="Vanish Mode Dedicated Keybinds")
        lbl_st.set_halign(Gtk.Align.START)
        lbl_st.add_css_class("heading")
        card3.append(lbl_st)

        for s_id, s_info in self.vanish_shortcuts.items():
            row_s = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
            row_s.add_css_class("settings-row")
            lb = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
            lb.set_hexpand(True)
            st = Gtk.Label(label=s_info.get("title", s_id))
            st.set_halign(Gtk.Align.START)
            st.add_css_class("row-title")
            lb.append(st)
            ss = Gtk.Label(label=s_info.get("desc", ""))
            ss.set_halign(Gtk.Align.START)
            ss.add_css_class("row-subtitle")
            lb.append(ss)
            row_s.append(lb)

            lbl_key = Gtk.Label(label=s_info.get("display_str", "Unset"))
            lbl_key.add_css_class("value-label")
            lbl_key.set_valign(Gtk.Align.CENTER)
            row_s.append(lbl_key)
            card3.append(row_s)

        # Reset button
        row_rst = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        row_rst.add_css_class("settings-row")
        lbr = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        lbr.set_hexpand(True)
        str_lbl = Gtk.Label(label="Reset Vanish Shortcuts")
        str_lbl.set_halign(Gtk.Align.START)
        str_lbl.add_css_class("row-title")
        lbr.append(str_lbl)
        row_rst.append(lbr)

        btn_rst = Gtk.Button(label="Reset Defaults")
        btn_rst.set_valign(Gtk.Align.CENTER)
        def on_reset_vanish_keys(b):
            import copy
            self.vanish_shortcuts = copy.deepcopy(DEFAULT_VANISH_SHORTCUTS)
            write_json(VANISH_SHORTCUTS_PATH, self.vanish_shortcuts)
            generate_vanish_keybinds_conf(self.vanish_shortcuts)
            subprocess.run(["hyprctl", "reload"], check=False)
        btn_rst.connect("clicked", on_reset_vanish_keys)
        row_rst.append(btn_rst)
        page.append(card3)

        # ── Card 4: Launcher Blank Tile ──
        card4 = self.create_settings_card()
        row_bt = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        row_bt.add_css_class("settings-row")
        lb_bt = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        lb_bt.set_hexpand(True)
        lbl_btt = Gtk.Label(label="Launcher Blank Tile Customization")
        lbl_btt.set_halign(Gtk.Align.START)
        lbl_btt.add_css_class("row-title")
        lb_bt.append(lbl_btt)
        lbl_bts = Gtk.Label(label="Customize image background and crop region for the top idle tile")
        lbl_bts.set_halign(Gtk.Align.START)
        lbl_bts.add_css_class("row-subtitle")
        lb_bt.append(lbl_bts)
        row_bt.append(lb_bt)

        btn_goto_bt = Gtk.Button(label="Customize Tile ->")
        btn_goto_bt.set_valign(Gtk.Align.CENTER)
        btn_goto_bt.connect("clicked", lambda b: self.nav_list.select_row(self.nav_rows["blank_tile"]))
        row_bt.append(btn_goto_bt)
        card4.append(row_bt)
        page.append(card4)

        return page

    # ── Category: Blank Tile Customization ──────────────────────────────────
    def build_blank_tile_page(self, icon, title, subtitle):
        page = self.create_page_container(icon, title, subtitle)

        # ── Card 1: Configuration ──
        card_config = self.create_settings_card()

        # Switch: Use Image Background
        is_en = bool(self.tile_cfg.get("enabled", False))
        def on_enable_toggle(act):
            self.tile_cfg["enabled"] = bool(act)
            self.tile_cfg["timestamp"] = int(time.time() * 1000)
            self.save_tile_config()
            self.update_tile_preview()
        self.sw_tile_enable = self.add_switch_row(
            card_config,
            "Use Image Background",
            "Show a selected image region in the blank tile instead of solid black",
            is_en,
            on_enable_toggle
        )

        # Row: Source Image File
        row_img = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        row_img.add_css_class("settings-row")
        lbox_i = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        lbox_i.set_hexpand(True)
        lbl_it = Gtk.Label(label="Source Image")
        lbl_it.set_halign(Gtk.Align.START)
        lbl_it.add_css_class("row-title")
        lbox_i.append(lbl_it)

        cur_img = self.tile_cfg.get("imagePath", "")
        img_name = os.path.basename(cur_img) if cur_img else "No image chosen"
        self.lbl_img_path = Gtk.Label(label=img_name)
        self.lbl_img_path.set_halign(Gtk.Align.START)
        self.lbl_img_path.add_css_class("row-subtitle")
        lbox_i.append(self.lbl_img_path)
        row_img.append(lbox_i)

        btn_choose = Gtk.Button(label="Choose Image...")
        btn_choose.set_valign(Gtk.Align.CENTER)
        btn_choose.connect("clicked", self.on_choose_tile_image)
        row_img.append(btn_choose)
        card_config.append(row_img)

        # Row: Crop & Region Selection
        row_crop = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        row_crop.add_css_class("settings-row")
        lbox_c = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        lbox_c.set_hexpand(True)
        lbl_ct = Gtk.Label(label="Selected Region")
        lbl_ct.set_halign(Gtk.Align.START)
        lbl_ct.add_css_class("row-title")
        lbox_c.append(lbl_ct)

        cr = self.tile_cfg.get("cropRect", {})
        crop_str = f"{cr.get('width', 0)}×{cr.get('height', 0)} px at ({cr.get('x', 0)}, {cr.get('y', 0)})" if cr.get("width", 0) > 0 else "Select any region of the image (crop)"
        self.lbl_crop_desc = Gtk.Label(label=crop_str)
        self.lbl_crop_desc.set_halign(Gtk.Align.START)
        self.lbl_crop_desc.add_css_class("row-subtitle")
        lbox_c.append(self.lbl_crop_desc)
        row_crop.append(lbox_c)

        self.btn_crop = Gtk.Button(label="Select / Adjust Region...")
        self.btn_crop.set_valign(Gtk.Align.CENTER)
        self.btn_crop.connect("clicked", self.on_open_tile_cropper)
        self.btn_crop.set_sensitive(bool(self.tile_cfg.get("imagePath") and os.path.exists(self.tile_cfg.get("imagePath"))))
        row_crop.append(self.btn_crop)
        card_config.append(row_crop)

        # Slider: Image Opacity
        cur_op = int(float(self.tile_cfg.get("opacity", 1.0)) * 100)
        def on_op_changed(v):
            val = round(v / 100.0, 2)
            self.tile_cfg["opacity"] = val
            self.tile_cfg["timestamp"] = int(time.time() * 1000)
            self.save_tile_config()
            self.update_tile_preview()
        self.add_slider_row(card_config, "Tile Image Opacity", "Transparency of cropped image in blank tile", 20, 100, 5, cur_op, "%", on_op_changed)

        # Button: Reset to Blank Tile
        row_rst = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        row_rst.add_css_class("settings-row")
        lbox_r = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        lbox_r.set_hexpand(True)
        lbl_rt = Gtk.Label(label="Reset to Default Blank Tile")
        lbl_rt.set_halign(Gtk.Align.START)
        lbl_rt.add_css_class("row-title")
        lbox_r.append(lbl_rt)
        lbl_rs = Gtk.Label(label="Revert to original clean #111116 dark container")
        lbl_rs.set_halign(Gtk.Align.START)
        lbl_rs.add_css_class("row-subtitle")
        lbox_r.append(lbl_rs)
        row_rst.append(lbox_r)

        btn_rst = Gtk.Button(label="Reset Tile")
        btn_rst.set_valign(Gtk.Align.CENTER)
        def on_reset_tile(b):
            self.tile_cfg = {
                "enabled": False,
                "imagePath": "",
                "cropPath": "",
                "cropRect": {"x": 0, "y": 0, "width": 0, "height": 0},
                "opacity": 1.0,
                "timestamp": int(time.time() * 1000)
            }
            self.save_tile_config()
            self.lbl_img_path.set_text("No image chosen")
            self.lbl_crop_desc.set_text("Select any region of the image (crop)")
            self.btn_crop.set_sensitive(False)
            if hasattr(self, "sw_tile_enable"):
                self.sw_tile_enable.set_active(False)
            self.update_tile_preview()
        btn_rst.connect("clicked", on_reset_tile)
        row_rst.append(btn_rst)
        card_config.append(row_rst)

        page.append(card_config)

        # ── Card 2: Live Tile Preview ──
        card_prev = self.create_settings_card()
        lbl_pt = Gtk.Label(label="Live Blank Tile Preview")
        lbl_pt.set_halign(Gtk.Align.START)
        lbl_pt.add_css_class("heading")
        card_prev.append(lbl_pt)

        prev_container = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        prev_container.set_halign(Gtk.Align.CENTER)
        prev_container.set_margin_top(12)
        prev_container.set_margin_bottom(8)

        # Frame matching exact tile aspect ratio (408 x 86)
        self.tile_preview_box = Gtk.Overlay()
        self.tile_preview_box.set_size_request(408, 86)
        self.tile_preview_box.add_css_class("blank-tile-preview")

        self.preview_picture = Gtk.Picture()
        self.preview_picture.set_content_fit(Gtk.ContentFit.COVER)
        self.preview_picture.set_size_request(408, 86)
        self.tile_preview_box.set_child(self.preview_picture)

        self.preview_placeholder = Gtk.Label(label="Default Blank Tile (#111116)")
        self.preview_placeholder.set_halign(Gtk.Align.CENTER)
        self.preview_placeholder.set_valign(Gtk.Align.CENTER)
        self.preview_placeholder.add_css_class("row-subtitle")
        self.tile_preview_box.add_overlay(self.preview_placeholder)

        prev_container.append(self.tile_preview_box)
        card_prev.append(prev_container)
        page.append(card_prev)

        self.update_tile_preview()
        return page

    def save_tile_config(self):
        write_json(BLANK_TILE_CONFIG_PATH, self.tile_cfg)
        if BLANK_TILE_HYPR_PATH != BLANK_TILE_CONFIG_PATH:
            write_json(BLANK_TILE_HYPR_PATH, self.tile_cfg)

    def update_tile_preview(self):
        if not hasattr(self, "preview_picture") or not hasattr(self, "preview_placeholder"):
            return
        is_en = self.tile_cfg.get("enabled", False)
        crop_path = self.tile_cfg.get("cropPath", "")
        if is_en and crop_path and os.path.exists(crop_path):
            file = Gio.File.new_for_path(crop_path)
            self.preview_picture.set_file(file)
            self.preview_picture.set_visible(True)
            self.preview_placeholder.set_visible(False)
            op = float(self.tile_cfg.get("opacity", 1.0))
            self.preview_picture.set_opacity(op)
        else:
            self.preview_picture.set_visible(False)
            self.preview_placeholder.set_visible(True)

    def on_choose_tile_image(self, btn):
        dialog = Gtk.FileDialog()
        dialog.set_title("Choose Image for Blank Tile")

        filters = Gio.ListStore.new(Gtk.FileFilter)
        img_filter = Gtk.FileFilter()
        img_filter.set_name("Images (*.png, *.jpg, *.jpeg, *.webp)")
        img_filter.add_mime_type("image/png")
        img_filter.add_mime_type("image/jpeg")
        img_filter.add_mime_type("image/webp")
        filters.append(img_filter)
        dialog.set_filters(filters)

        def on_open_finish(source, res):
            try:
                gfile = source.open_finish(res)
                if gfile:
                    path = gfile.get_path()
                    if path and os.path.exists(path):
                        self.tile_cfg["imagePath"] = path
                        self.lbl_img_path.set_text(os.path.basename(path))
                        self.btn_crop.set_sensitive(True)
                        self.on_open_tile_cropper(None)
            except Exception:
                pass

        dialog.open(self, None, on_open_finish)

    def on_open_tile_cropper(self, btn):
        img_path = self.tile_cfg.get("imagePath", "")
        if not img_path or not os.path.exists(img_path):
            return

        crop_rect = self.tile_cfg.get("cropRect")
        crop_dialog = ImageCropDialog(
            parent_window=self,
            image_path=img_path,
            initial_rect=crop_rect,
            accent_hex=self.accent_hex,
            on_apply=self.on_tile_crop_applied
        )
        crop_dialog.present()

    def on_tile_crop_applied(self, new_cfg):
        self.tile_cfg = new_cfg
        cr = self.tile_cfg.get("cropRect", {})
        crop_str = f"{cr.get('width', 0)}×{cr.get('height', 0)} px at ({cr.get('x', 0)}, {cr.get('y', 0)})"
        self.lbl_crop_desc.set_text(crop_str)
        self.lbl_img_path.set_text(os.path.basename(self.tile_cfg.get("imagePath", "")))
        self.btn_crop.set_sensitive(True)
        if hasattr(self, "sw_tile_enable"):
            self.sw_tile_enable.set_active(True)
        self.update_tile_preview()

    # ── Category 2: Media ──────────────────────────────────────────────────
    def build_media_page(self, icon, title, subtitle):
        page = self.create_page_container(icon, title, subtitle)
        card = self.create_settings_card()

        # Spinning Vinyl Disc
        disc_act = bool(self.bar_pos.get("showVinylDisc", True))
        def on_disc(act):
            self.bar_pos["showVinylDisc"] = act
            write_json(BAR_POS_PATH, self.bar_pos)
        self.add_switch_row(card, "Spinning Album Disc", "Show animated vinyl record with album art", disc_act, on_disc)

        # Equalizer Waveform
        eq_act = bool(self.bar_pos.get("showEqualizer", True))
        def on_eq(act):
            self.bar_pos["showEqualizer"] = act
            write_json(BAR_POS_PATH, self.bar_pos)
        self.add_switch_row(card, "Waveform Equalizer", "Show animated dynamic island audio bars", eq_act, on_eq)

        # Auto-expand on Track Change
        expand_act = bool(self.bar_pos.get("autoExpandOnTrack", False))
        def on_exp(act):
            self.bar_pos["autoExpandOnTrack"] = act
            write_json(BAR_POS_PATH, self.bar_pos)
        self.add_switch_row(card, "Auto-expand on Track Change", "Briefly expand island when song changes", expand_act, on_exp)

        # Audio Visualizer Selector
        vis_options = ["Liquid Halo (Siri Ring)", "None"]
        vis_val = self.bar_mode.get("musicVisualizer", "liquidHalo")
        vis_idx = 0 if vis_val == "liquidHalo" else 1
        def on_vis_changed(idx):
            v = "liquidHalo" if idx == 0 else "none"
            self.bar_mode["musicVisualizer"] = v
            write_json(BAR_MODE_PATH, self.bar_mode)
        self.add_combo_row(card, "Audio Visualizer Effect", "Choose dynamic glowing visualizer for music playback", vis_options, vis_idx, on_vis_changed)

        page.append(card)
        return page

    # ── Category 3: Clock & Date ───────────────────────────────────────────
    def build_clock_page(self, icon, title, subtitle):
        page = self.create_page_container(icon, title, subtitle)
        card = self.create_settings_card()

        # Typography Style
        styles = ["Titan 3D Pop", "Stacked Dual", "Nordic Monospace", "Valley Modern"]
        cur_s = self.clock_cfg.get("style", "titan")
        idx = {"titan": 0, "stacked": 1, "mono_glow": 2, "valley": 3}.get(cur_s, 0)
        def on_s_changed(sel):
            k = ["titan", "stacked", "mono_glow", "valley"][sel]
            self.clock_cfg["style"] = k
            write_json(CLOCK_STYLE_PATH, self.clock_cfg)
        self.add_combo_row(card, "Typography Style", "Visual appearance of center island clock", styles, idx, on_s_changed)

        # Time Format
        fmts = ["12-Hour (AM/PM)", "24-Hour (Military)"]
        cur_fmt = self.clock_cfg.get("format", "12")
        f_idx = 1 if cur_fmt == "24" else 0
        def on_f_changed(sel):
            self.clock_cfg["format"] = "24" if sel == 1 else "12"
            write_json(CLOCK_STYLE_PATH, self.clock_cfg)
        self.add_combo_row(card, "Clock Format", "12-hour or 24-hour time display", fmts, f_idx, on_f_changed)

        # Show Date
        show_d = bool(self.clock_cfg.get("showDate", True))
        def on_d_toggle(act):
            self.clock_cfg["showDate"] = act
            write_json(CLOCK_STYLE_PATH, self.clock_cfg)
        self.add_switch_row(card, "Show Calendar Date", "Display day and date in expanded overview", show_d, on_d_toggle)

        page.append(card)
        return page

    # ── Category 4: Appearance ─────────────────────────────────────────────
    def build_appearance_page(self, icon, title, subtitle):
        page = self.create_page_container(icon, title, subtitle)
        card = self.create_settings_card()

        # Window Opacity
        cur_w_o = int(float(self.var_data.get("windowOpacity", 0.95)) * 100)
        def on_wo_changed(v):
            val = round(v / 100.0, 2)
            self.var_data["windowOpacity"] = val
            write_variable("windowOpacity", val)
            update_looknfeel_setting("active_opacity", f"{val:.2f}")
            update_looknfeel_setting("inactive_opacity", f"{val:.2f}")
            subprocess.run(["hyprctl", "eval", f"hl.config({{ decoration = {{ active_opacity = {val:.2f}, inactive_opacity = {val:.2f} }} }})"], check=False, stdout=subprocess.DEVNULL)
        self.add_slider_row(card, "Window Opacity", "Hyprland active window transparency", 50, 100, 5, cur_w_o, "%", on_wo_changed)

        # Window Corner Rounding
        cur_r = int(self.var_data.get("rounding", 15))
        def on_r_changed(v):
            self.var_data["rounding"] = v
            write_variable("rounding", v)
            update_looknfeel_setting("rounding", str(int(v)))
            subprocess.run(["hyprctl", "eval", f"hl.config({{ decoration = {{ rounding = {int(v)} }} }})"], check=False, stdout=subprocess.DEVNULL)
        self.add_slider_row(card, "Corner Rounding", "Radius of window corners", 0, 24, 1, cur_r, "px", on_r_changed)

        # Window Border Size
        cur_b = int(self.var_data.get("borderSize", 1))
        def on_b_changed(v):
            self.var_data["borderSize"] = v
            write_variable("borderSize", v)
            update_looknfeel_setting("border_size", str(int(v)))
            subprocess.run(["hyprctl", "eval", f"hl.config({{ general = {{ border_size = {int(v)} }} }})"], check=False, stdout=subprocess.DEVNULL)
        self.add_slider_row(card, "Border Width", "Thickness of active window border", 0, 6, 1, cur_b, "px", on_b_changed)

        # Shell UI Scale
        cur_scale = float(self.bar_pos.get("scale", 1.0))
        def on_scale_changed(v):
            self.bar_pos["scale"] = v
            write_json(BAR_POS_PATH, self.bar_pos)
        self.add_slider_row(card, "Shell UI Scale", "Scale bars, menus, and widgets", 0.75, 1.50, 0.05, cur_scale, "x", on_scale_changed)

        page.append(card)

        # ── Online Wallpaper Catalog Settings ──
        wp_card = self.create_settings_card()

        provider_options = ["Unsplash (High-Res Curated Photography)", "Wallhaven (Anime & Digital Art)"]
        provider_ids = ["unsplash", "wallhaven"]
        cur_prov = str(self.wallpaper_source_cfg.get("provider", "unsplash")).lower()
        cur_p_idx = provider_ids.index(cur_prov) if cur_prov in provider_ids else 0

        def on_provider_sel(idx):
            p = provider_ids[idx]
            self.wallpaper_source_cfg["provider"] = p
            write_json(WALLPAPER_SOURCE_PATH, self.wallpaper_source_cfg)
            hypr_wp_path = os.path.expanduser("~/.config/hypr/carbon-wallpaper-source.json")
            if hypr_wp_path != WALLPAPER_SOURCE_PATH:
                write_json(hypr_wp_path, self.wallpaper_source_cfg)

        self.add_combo_row(wp_card, "Online Wallpaper Provider", "Source catalog used for online wallpapers in the wallpaper picker", provider_options, cur_p_idx, on_provider_sel)

        cur_key = self.wallpaper_source_cfg.get("unsplash_access_key", "")
        def on_key_change(val):
            self.wallpaper_source_cfg["unsplash_access_key"] = val.strip()
            write_json(WALLPAPER_SOURCE_PATH, self.wallpaper_source_cfg)
            hypr_wp_path = os.path.expanduser("~/.config/hypr/carbon-wallpaper-source.json")
            if hypr_wp_path != WALLPAPER_SOURCE_PATH:
                write_json(hypr_wp_path, self.wallpaper_source_cfg)

        self.add_entry_row(wp_card, "Unsplash Access Key (Optional)", "Custom developer API key for quotas (leave empty for built-in catalog)", cur_key, "Leave empty for built-in catalog", on_key_change)

        page.append(wp_card)
        return page

    # ── Category 5: Motion (EXACT MATCH FOR SCREENSHOT 2!) ──────────────────
    def build_motion_page(self, icon, title, subtitle):
        page = self.create_page_container(icon, title, subtitle)
        card = self.create_settings_card()

        # Reduce motion switch
        reduce_act = bool(self.motion_cfg.get("reduceMotion", False))
        def on_reduce(act):
            self.motion_cfg["reduceMotion"] = act
            write_json(MOTION_CONFIG_PATH, self.motion_cfg)
            subprocess.run(["hyprctl", "eval", f"hl.config({{ animations = {{ enabled = {'false' if act else 'true'} }} }})"], check=False, stdout=subprocess.DEVNULL)
        self.add_switch_row(card, "Reduce motion", None, reduce_act, on_reduce)

        # Movement (size / position)
        mov_dur = int(self.motion_cfg.get("movementDuration", 400))
        def on_mov(v):
            self.motion_cfg["movementDuration"] = v
            write_json(MOTION_CONFIG_PATH, self.motion_cfg)
        self.add_slider_row(card, "Movement (size / position)", None, 0, 600, 20, mov_dur, "ms", on_mov)

        # Fades & colour
        fade_dur = int(self.motion_cfg.get("fadeDuration", 200))
        def on_fade(v):
            self.motion_cfg["fadeDuration"] = v
            write_json(MOTION_CONFIG_PATH, self.motion_cfg)
        self.add_slider_row(card, "Fades & colour", None, 0, 400, 10, fade_dur, "ms", on_fade)

        # Hover response
        hover_dur = int(self.motion_cfg.get("hoverResponse", 150))
        def on_hover(v):
            self.motion_cfg["hoverResponse"] = v
            write_json(MOTION_CONFIG_PATH, self.motion_cfg)
        self.add_slider_row(card, "Hover response", None, 0, 300, 10, hover_dur, "ms", on_hover)

        # Bounce
        bounce_val = int(self.motion_cfg.get("bounce", 40))
        def on_bounce(v):
            self.motion_cfg["bounce"] = v
            write_json(MOTION_CONFIG_PATH, self.motion_cfg)
        self.add_slider_row(card, "Bounce", None, 0, 100, 5, bounce_val, "%", on_bounce)

        page.append(card)
        return page

    # ── Category 6: Launcher ───────────────────────────────────────────────
    def build_launcher_page(self, icon, title, subtitle):
        page = self.create_page_container(icon, title, subtitle)
        card = self.create_settings_card()

        # Spotlight Opening Animation Speed
        speed = int(self.launcher_cfg.get("animationSpeed", 170))
        def on_speed(v):
            self.launcher_cfg["animationSpeed"] = v
            write_json(LAUNCHER_CONFIG_PATH, self.launcher_cfg)
        self.add_slider_row(card, "Spotlight Speed", "Duration of opening spring animation", 100, 400, 10, speed, "ms", on_speed)

        # Show Recent Applications
        rec_act = bool(self.launcher_cfg.get("showRecents", True))
        def on_rec(act):
            self.launcher_cfg["showRecents"] = act
            write_json(LAUNCHER_CONFIG_PATH, self.launcher_cfg)
        self.add_switch_row(card, "Recent Applications", "Show recently used apps on empty search", rec_act, on_rec)

        # Clipboard History
        clip_act = bool(self.launcher_cfg.get("clipboardHistory", True))
        def on_clip(act):
            self.launcher_cfg["clipboardHistory"] = act
            write_json(LAUNCHER_CONFIG_PATH, self.launcher_cfg)
        self.add_switch_row(card, "Clipboard History Tab", "Enable clipboard manager in Spotlight", clip_act, on_clip)

        # Max Results
        max_r = int(self.launcher_cfg.get("maxResults", 8))
        def on_max(v):
            self.launcher_cfg["maxResults"] = v
            write_json(LAUNCHER_CONFIG_PATH, self.launcher_cfg)
        self.add_slider_row(card, "Maximum Results", "Number of search results to display", 4, 16, 1, max_r, "items", on_max)

        page.append(card)
        return page

    # ── Category 7: Notifications ──────────────────────────────────────────
    def build_notifications_page(self, icon, title, subtitle):
        page = self.create_page_container(icon, title, subtitle)
        card = self.create_settings_card()

        # Enable Notifications
        en_act = bool(self.notif_cfg.get("enabled", True))
        def on_en(act):
            self.notif_cfg["enabled"] = act
            write_json(NOTIF_CONFIG_PATH, self.notif_cfg)
        self.add_switch_row(card, "Enable Notifications", "Show banner popups for new messages", en_act, on_en)

        # Do Not Disturb
        dnd_act = bool(self.notif_cfg.get("dnd", False))
        def on_dnd(act):
            self.notif_cfg["dnd"] = act
            write_json(NOTIF_CONFIG_PATH, self.notif_cfg)
        self.add_switch_row(card, "Do Not Disturb", "Silence all incoming notification popups", dnd_act, on_dnd)

        # Display Timeout
        timeout_val = int(self.notif_cfg.get("timeout", 5))
        def on_t(v):
            self.notif_cfg["timeout"] = v
            write_json(NOTIF_CONFIG_PATH, self.notif_cfg)
        self.add_slider_row(card, "Banner Timeout", "Time before popups dismiss automatically", 2, 10, 1, timeout_val, "s", on_t)

        page.append(card)
        return page

    # ── Category 8: Control Center ─────────────────────────────────────────
    def build_control_center_page(self, icon, title, subtitle):
        page = self.create_page_container(icon, title, subtitle)
        card = self.create_settings_card()

        # Volume Step
        vol_step = int(self.control_cfg.get("volumeStep", 5))
        def on_vol(v):
            self.control_cfg["volumeStep"] = v
            write_json(CONTROL_CONFIG_PATH, self.control_cfg)
        self.add_slider_row(card, "Volume Step", "Step amount for volume keys and sliders", 1, 10, 1, vol_step, "%", on_vol)

        # Brightness Step
        br_step = int(self.control_cfg.get("brightnessStep", 5))
        def on_br(v):
            self.control_cfg["brightnessStep"] = v
            write_json(CONTROL_CONFIG_PATH, self.control_cfg)
        self.add_slider_row(card, "Brightness Step", "Step amount for screen brightness keys", 1, 10, 1, br_step, "%", on_br)

        # Battery Percentage
        bat_act = bool(self.control_cfg.get("showBatteryPercent", True))
        def on_bat(act):
            self.control_cfg["showBatteryPercent"] = act
            write_json(CONTROL_CONFIG_PATH, self.control_cfg)
        self.add_switch_row(card, "Show Battery Percentage", "Display text next to battery icon in notch", bat_act, on_bat)

        page.append(card)
        return page

    # ── Category 9: Lock Screen ────────────────────────────────────────────
    def build_lockscreen_page(self, icon, title, subtitle):
        page = self.create_page_container(icon, title, subtitle)
        card = self.create_settings_card()

        # Style Layout
        layouts = ["Modern Minimal", "Glass Card", "Bold Clock"]
        cur_l = self.lock_cfg.get("layout", "modern")
        idx = {"modern": 0, "glass": 1, "bold": 2}.get(cur_l, 0)
        def on_l_changed(sel):
            k = ["modern", "glass", "bold"][sel]
            self.lock_cfg["layout"] = k
            write_json(LOCKSCREEN_CONFIG_PATH, self.lock_cfg)
        self.add_combo_row(card, "Lock Screen Layout", "Visual layout of hyprlock interface", layouts, idx, on_l_changed)

        # Background Blur Radius
        blur_r = int(self.lock_cfg.get("blurRadius", 2))
        def on_blur_r(v):
            self.lock_cfg["blurRadius"] = v
            write_json(LOCKSCREEN_CONFIG_PATH, self.lock_cfg)
            h_path = os.path.expanduser("~/.config/hypr/hyprlock.conf")
            if os.path.exists(h_path):
                try:
                    with open(h_path, "r", encoding="utf-8") as f:
                        c = f.read()
                    c = re.sub(r"(blur_passes\s*=\s*)\d+", rf"\g<1>{int(v)}", c)
                    with open(h_path, "w", encoding="utf-8") as f:
                        f.write(c)
                except Exception:
                    pass
        self.add_slider_row(card, "Background Blur", "Amount of backdrop blur when locked", 0, 10, 1, blur_r, "passes", on_blur_r)

        # Media Player
        media_act = bool(self.lock_cfg.get("showMedia", True))
        def on_media(act):
            self.lock_cfg["showMedia"] = act
            write_json(LOCKSCREEN_CONFIG_PATH, self.lock_cfg)
        self.add_switch_row(card, "Media Player on Lock Screen", "Show currently playing track when locked", media_act, on_media)

        page.append(card)
        return page

    # ── Category 10: System ────────────────────────────────────────────────
    def build_system_page(self, icon, title, subtitle):
        page = self.create_page_container(icon, title, subtitle)
        card = self.create_settings_card()

        # Actions Row
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        row.add_css_class("settings-row")

        label_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        label_box.set_hexpand(True)
        lbl_t = Gtk.Label(label="Restart Carbon Shell")
        lbl_t.set_halign(Gtk.Align.START)
        lbl_t.add_css_class("row-title")
        label_box.append(lbl_t)
        lbl_s = Gtk.Label(label="Reload quickshell daemon and apply all visual updates")
        lbl_s.set_halign(Gtk.Align.START)
        lbl_s.add_css_class("row-subtitle")
        label_box.append(lbl_s)
        row.append(label_box)

        btn = Gtk.Button(label="Restart")
        btn.set_valign(Gtk.Align.CENTER)
        btn.connect("clicked", self.on_reload_shell)
        row.append(btn)
        card.append(row)

        # Reload Hyprland Row
        row_hl = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        row_hl.add_css_class("settings-row")

        label_box_hl = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        label_box_hl.set_hexpand(True)
        lbl_hl_t = Gtk.Label(label="Reload Hyprland")
        lbl_hl_t.set_halign(Gtk.Align.START)
        lbl_hl_t.add_css_class("row-title")
        label_box_hl.append(lbl_hl_t)
        lbl_hl_s = Gtk.Label(label="Reload compositor rules, keybinds, and variables")
        lbl_hl_s.set_halign(Gtk.Align.START)
        lbl_hl_s.add_css_class("row-subtitle")
        label_box_hl.append(lbl_hl_s)
        row_hl.append(label_box_hl)

        btn_hl = Gtk.Button(label="Reload")
        btn_hl.set_valign(Gtk.Align.CENTER)
        btn_hl.connect("clicked", lambda b: subprocess.run(["hyprctl", "reload"], check=False))
        row_hl.append(btn_hl)
        card.append(row_hl)

        page.append(card)
        return page

    # ── Reload Shell ───────────────────────────────────────────────────────
    def on_reload_shell(self, btn):
        try:
            subprocess.run(["systemctl", "--user", "restart", "carbon-quickshell.service"], check=False)
            subprocess.run(["hyprctl", "reload"], check=False)
        except Exception as e:
            print(f"Error restarting shell: {e}", file=sys.stderr)

def main():
    app = CarbonConfigApp()
    return app.run(sys.argv)

if __name__ == "__main__":
    sys.exit(main())
