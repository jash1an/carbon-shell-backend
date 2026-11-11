#!/usr/bin/env python3
"""
Carbon Shell — Comprehensive Settings Backend Dispatcher
Provides unified read/write access for all Carbon Shell subsystems:
- launcher (carbon-launcher.json)
- notifications (carbon-notifications.json)
- lockscreen (carbon-lockscreen.json)
- control_center (carbon-control-center.json)
- clock (carbon-clock-style.json)
- blank_tile (carbon-blank-tile.json)
- fonts (carbon-fonts.json)
- media (carbon-bar-position.json & carbon-bar-mode.json)
- looknfeel (looknfeel.conf)
"""

import sys
import os
import json
import re
import subprocess

CONFIG_DIR = os.environ.get("CARBON_CONFIG_DIR", os.path.expanduser("~/.config/carbon"))
HYPR_DIR = os.path.expanduser("~/.config/hypr")

def ensure_dirs():
    os.makedirs(CONFIG_DIR, exist_ok=True)
    os.makedirs(HYPR_DIR, exist_ok=True)

def load_json(filename, default):
    p = os.path.join(CONFIG_DIR, filename)
    if not os.path.exists(p):
        p_hypr = os.path.join(HYPR_DIR, filename)
        if os.path.exists(p_hypr):
            p = p_hypr
    if os.path.exists(p):
        try:
            with open(p, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass
    return default

def save_json(filename, data):
    ensure_dirs()
    for d in [CONFIG_DIR, HYPR_DIR]:
        p = os.path.join(d, filename)
        try:
            with open(p, "w", encoding="utf-8") as f:
                json.dump(data, f, indent=2)
        except Exception:
            pass

def parse_val(v_str):
    if v_str.lower() == "true": return True
    if v_str.lower() == "false": return False
    try:
        return float(v_str) if "." in v_str else int(v_str)
    except ValueError:
        return v_str

# ── Look & Feel parser & writer ─────────────────────────────────────────────
LOOKNFEEL_CONF = os.path.join(CONFIG_DIR, "looknfeel.conf")

def read_looknfeel():
    data = {
        "gaps_in": 6,
        "gaps_out": 6,
        "border_size": 1,
        "rounding": 0,
        "rounding_power": 2,
        "active_opacity": 0.96,
        "inactive_opacity": 0.78,
        "shadow_enabled": False,
        "shadow_range": 25,
        "shadow_render_power": 2,
        "blur_enabled": False,
        "blur_size": 4,
        "blur_passes": 2,
        "resize_on_border": False,
        "allow_tearing": False,
        "layout": "dwindle"
    }
    if not os.path.exists(LOOKNFEEL_CONF):
        return data
    try:
        with open(LOOKNFEEL_CONF, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"): continue
                m = re.match(r"^([\w\.]+)\s*=\s*(.+)$", line)
                if m:
                    k = m.group(1).replace(" ", "_")
                    v = m.group(2).split("#")[0].strip()
                    if k in data:
                        data[k] = parse_val(v)
                    elif k == "enabled":
                        # depends on context, but let's check shadow / blur
                        pass
    except Exception:
        pass
    return data

def write_looknfeel(data):
    ensure_dirs()
    content = f"""# ==============================================================================
# Carbon Shell — Hyprland Look & Feel Configuration
# Managed automatically by Carbon Settings App
# ==============================================================================

# Dynamic Material You Theme Colors
source = ~/.config/carbon/colors.conf

general {{
    gaps_in = {int(data.get('gaps_in', 6))}
    gaps_out = {int(data.get('gaps_out', 6))}

    border_size = {int(data.get('border_size', 1))}

    col.active_border = $outline
    col.inactive_border = $outline_variant

    resize_on_border = {'true' if data.get('resize_on_border') else 'false'}
    allow_tearing = {'true' if data.get('allow_tearing') else 'false'}

    layout = {data.get('layout', 'dwindle')}
}}

decoration {{
    rounding = {int(data.get('rounding', 0))}
    rounding_power = {int(data.get('rounding_power', 2))}

    active_opacity = {float(data.get('active_opacity', 0.96)):.2f}
    inactive_opacity = {float(data.get('inactive_opacity', 0.78)):.2f}

    shadow {{
        enabled = {'true' if data.get('shadow_enabled') else 'false'}
        range = {int(data.get('shadow_range', 25))}
        render_power = {int(data.get('shadow_render_power', 2))}
        color = rgba(1a1a1aee)
    }}

    blur {{
        enabled = {'true' if data.get('blur_enabled') else 'false'}
        size = {int(data.get('blur_size', 4))}
        passes = {int(data.get('blur_passes', 2))}
        ignore_opacity = true
        new_optimizations = true
        special = false
        popups = true
        xray = true

        vibrancy = 0.1696
    }}
}}
"""
    for target in [LOOKNFEEL_CONF, os.path.join(HYPR_DIR, "looknfeel.conf")]:
        try:
            with open(target, "w", encoding="utf-8") as f:
                f.write(content)
        except Exception:
            pass

    # Instant compositor update
    try:
        subprocess.run(["hyprctl", "reload", "config-only"], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        pass

def main():
    if len(sys.argv) < 2:
        print("Usage: carbon-settings-apply.py {get <section>|set <section> <key> <val>|dump-all}")
        sys.exit(1)

    cmd = sys.argv[1]

    if cmd == "dump-all":
        result = {
            "launcher": load_json("carbon-launcher.json", {}),
            "notifications": load_json("carbon-notifications.json", {}),
            "lockscreen": load_json("carbon-lockscreen.json", {}),
            "control_center": load_json("carbon-control-center.json", {}),
            "clock": load_json("carbon-clock-style.json", {}),
            "blank_tile": load_json("carbon-blank-tile.json", {}),
            "fonts": load_json("carbon-fonts.json", {}),
            "motion": load_json("carbon-motion.json", {}),
            "media": {
                "showVinylDisc": load_json("carbon-bar-position.json", {}).get("showVinylDisc", True),
                "showEqualizer": load_json("carbon-bar-position.json", {}).get("showEqualizer", True),
                "autoExpandOnTrack": load_json("carbon-bar-position.json", {}).get("autoExpandOnTrack", False),
                "musicVisualizer": load_json("carbon-bar-mode.json", {}).get("musicVisualizer", "liquidHalo")
            },
            "looknfeel": read_looknfeel()
        }
        print(json.dumps(result))
        sys.exit(0)

    if cmd == "get" and len(sys.argv) >= 3:
        sec = sys.argv[2]
        if sec == "launcher":
            print(json.dumps(load_json("carbon-launcher.json", {})))
        elif sec == "notifications":
            print(json.dumps(load_json("carbon-notifications.json", {})))
        elif sec == "lockscreen":
            print(json.dumps(load_json("carbon-lockscreen.json", {})))
        elif sec == "control_center":
            print(json.dumps(load_json("carbon-control-center.json", {})))
        elif sec == "clock":
            print(json.dumps(load_json("carbon-clock-style.json", {})))
        elif sec == "motion":
            d = load_json("carbon-motion.json", {})
            d[key] = val
            save_json("carbon-motion.json", d)
            print("ok")

        elif sec == "blank_tile":
            print(json.dumps(load_json("carbon-blank-tile.json", {})))
        elif sec == "fonts":
            print(json.dumps(load_json("carbon-fonts.json", {})))
        elif sec == "motion":
            print(json.dumps(load_json("carbon-motion.json", {})))
        elif sec == "media":
            bp = load_json("carbon-bar-position.json", {})
            bm = load_json("carbon-bar-mode.json", {})
            print(json.dumps({
                "showVinylDisc": bp.get("showVinylDisc", True),
                "showEqualizer": bp.get("showEqualizer", True),
                "autoExpandOnTrack": bp.get("autoExpandOnTrack", False),
                "musicVisualizer": bm.get("musicVisualizer", "liquidHalo")
            }))
        elif sec == "looknfeel":
            print(json.dumps(read_looknfeel()))
        sys.exit(0)

    if cmd == "set" and len(sys.argv) >= 5:
        sec = sys.argv[2]
        key = sys.argv[3]
        val = parse_val(sys.argv[4])

        if sec == "launcher":
            d = load_json("carbon-launcher.json", {})
            d[key] = val
            if key == "launcherStyle":
                d["defaultLauncher"] = val
            save_json("carbon-launcher.json", d)
            print("ok")

        elif sec == "notifications":
            d = load_json("carbon-notifications.json", {})
            d[key] = val
            save_json("carbon-notifications.json", d)
            print("ok")

        elif sec == "lockscreen":
            d = load_json("carbon-lockscreen.json", {})
            d[key] = val
            if key == "cairoModeEnabled":
                d["verciModeEnabled"] = val
                # Trigger IPC
                subprocess.run(["sh", os.path.join(CONFIG_DIR, "scripts/carbon-ipc.sh"), f"set-cairo-mode {'true' if val else 'false'}"], check=False)
            elif key == "mediaOverlay":
                d["showMedia"] = val
            save_json("carbon-lockscreen.json", d)
            print("ok")

        elif sec == "control_center":
            d = load_json("carbon-control-center.json", {})
            d[key] = val
            save_json("carbon-control-center.json", d)
            print("ok")

        elif sec == "clock":
            d = load_json("carbon-clock-style.json", {})
            d[key] = val
            save_json("carbon-clock-style.json", d)
            print("ok")

        elif sec == "motion":
            d = load_json("carbon-motion.json", {})
            d[key] = val
            save_json("carbon-motion.json", d)
            print("ok")

        elif sec == "blank_tile":
            d = load_json("carbon-blank-tile.json", {})
            d[key] = val
            d["timestamp"] = int(time.time() * 1000) if "time" in globals() else 1000
            save_json("carbon-blank-tile.json", d)
            print("ok")

        elif sec == "fonts":
            d = load_json("carbon-fonts.json", {})
            d[key] = val
            save_json("carbon-fonts.json", d)
            # Run font scaling if scaling_factor changed
            if key == "scaling_factor":
                sc_script = os.path.join(CONFIG_DIR, "scripts/carbon-font-scale")
                if os.path.exists(sc_script):
                    subprocess.run(["bash", sc_script, str(val)], check=False)
            print("ok")

        elif sec == "media":
            if key in ["showVinylDisc", "showEqualizer", "autoExpandOnTrack"]:
                bp = load_json("carbon-bar-position.json", {})
                bp[key] = val
                save_json("carbon-bar-position.json", bp)
            elif key == "musicVisualizer":
                bm = load_json("carbon-bar-mode.json", {})
                bm[key] = val
                save_json("carbon-bar-mode.json", bm)
            print("ok")

        elif sec == "looknfeel":
            d = read_looknfeel()
            d[key] = val
            write_looknfeel(d)
            print("ok")

        sys.exit(0)

if __name__ == "__main__":
    import time
    main()
