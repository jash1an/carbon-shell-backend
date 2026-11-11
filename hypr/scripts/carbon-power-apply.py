#!/usr/bin/env python3
import os, sys, json, subprocess

CONFIG_DIR = os.environ.get("CARBON_CONFIG_DIR", os.path.expanduser("~/.config/carbon"))
HYPR_DIR = os.path.expanduser("~/.config/hypr")

POWER_JSON = os.path.join(CONFIG_DIR, "carbon-power.json")
POWER_CONF = os.path.join(CONFIG_DIR, "power.conf")
HYPRIDLE_CONF = os.path.join(CONFIG_DIR, "hypridle.conf")

DEFAULT_POWER = {
    "profile": "balanced",
    "powerButtonAction": "poweroff",
    "sleepButtonAction": "suspend",
    "lidActionBattery": "suspend",
    "lidActionAC": "suspend",
    "sleepMode": "suspend",
    "hibernationEnabled": True,
    "dimEnabled": True,
    "dimTimeout": 180,
    "dimBrightnessPercent": 20,
    "screenOffTimeout": 300,
    "autoSuspendTimeout": 1800,
}

def load_json(path, default):
    if os.path.exists(path):
        try:
            with open(path, "r", encoding="utf-8") as f:
                d = json.load(f)
                res = default.copy()
                res.update(d)
                return res
        except Exception:
            pass
    return default.copy()

def save_json(path, data):
    for p in [path, os.path.join(HYPR_DIR, os.path.basename(path))]:
        try:
            os.makedirs(os.path.dirname(p), exist_ok=True)
            with open(p, "w", encoding="utf-8") as f:
                json.dump(data, f, indent=2)
        except Exception:
            pass

def generate_hypridle_conf(cfg):
    lines = [
        "# ==============================================================================",
        "# Carbon Shell — Hypridle Configuration",
        "# Managed by Carbon Settings Hub",
        "# ==============================================================================",
        "",
        "general {",
        "    lock_cmd = ~/.config/hypr/scripts/hyprlock.sh",
        "    before_sleep_cmd = loginctl lock-session",
        "    after_sleep_cmd = hyprctl dispatch dpms on",
        "}",
        ""
    ]
    if cfg.get("dimEnabled", True):
        dt = int(cfg.get("dimTimeout", 180))
        pct = int(cfg.get("dimBrightnessPercent", 20))
        lines.extend([
            "# === MONITOR BACKLIGHT DIM ===",
            "listener {",
            f"    timeout = {dt}",
            f"    on-timeout = brightnessctl -s set {pct}%",
            "    on-resume = brightnessctl -r",
            "}",
            ""
        ])

    s_off = int(cfg.get("screenOffTimeout", 300))
    if s_off > 0:
        lines.extend([
            "# === TURN OFF SCREEN ===",
            "listener {",
            f"    timeout = {s_off}",
            "    on-timeout = hyprctl dispatch dpms off",
            "    on-resume = hyprctl dispatch dpms on && brightnessctl -r",
            "}",
            ""
        ])

    a_susp = int(cfg.get("autoSuspendTimeout", 1800))
    if a_susp > 0:
        mode = cfg.get("sleepMode", "suspend")
        cmd = "systemctl hibernate" if mode == "hibernate" else "systemctl suspend"
        lines.extend([
            "# === AUTO SUSPEND / SLEEP ===",
            "listener {",
            f"    timeout = {a_susp}",
            f"    on-timeout = {cmd}",
            "}",
            ""
        ])

    return "\n".join(lines) + "\n"

def sync_power(cfg):
    save_json(POWER_JSON, cfg)
    
    # Write power.conf
    power_conf_content = (
        "# ==============================================================================\n"
        "# Carbon Shell — Power, Button & Lid Event Bindings\n"
        "# Managed by Carbon Settings Hub\n"
        "# ==============================================================================\n\n"
        "# Physical Power & Sleep Buttons\n"
        "bind = , XF86PowerOff, exec, ~/.config/carbon/scripts/carbon-power-handler.sh power_button\n"
        "bind = , XF86Sleep, exec, ~/.config/carbon/scripts/carbon-power-handler.sh sleep_button\n\n"
        "# Laptop Lid Switch Events (switch:on = closed, switch:off = opened)\n"
        "bindl = , switch:on:Lid Switch, exec, ~/.config/carbon/scripts/carbon-power-handler.sh lid_close\n"
        "bindl = , switch:off:Lid Switch, exec, ~/.config/carbon/scripts/carbon-power-handler.sh lid_open\n"
    )
    for p in [POWER_CONF, os.path.join(HYPR_DIR, "power.conf")]:
        try:
            with open(p, "w", encoding="utf-8") as f:
                f.write(power_conf_content)
        except Exception:
            pass

    # Write hypridle.conf
    idle_content = generate_hypridle_conf(cfg)
    for p in [HYPRIDLE_CONF, os.path.join(HYPR_DIR, "hypridle.conf")]:
        try:
            with open(p, "w", encoding="utf-8") as f:
                f.write(idle_content)
        except Exception:
            pass

    # Restart hypridle
    try:
        subprocess.run(["pkill", "-x", "hypridle"], check=False)
        subprocess.Popen(["hypridle", "-c", HYPRIDLE_CONF], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        pass

    # Apply power profile
    profile = cfg.get("profile", "balanced")
    prof_script = os.path.join(CONFIG_DIR, "scripts/carbon-power-profile.sh")
    if os.path.exists(prof_script):
        try:
            subprocess.run(["bash", prof_script, "set", profile], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception:
            pass

def main():
    if len(sys.argv) < 2:
        print("Usage: carbon-power-apply.py {get|set <key> <val>}")
        sys.exit(1)

    cmd = sys.argv[1]
    cfg = load_json(POWER_JSON, DEFAULT_POWER)

    if cmd == "get":
        print(json.dumps(cfg))
        sys.exit(0)

    if cmd == "set" and len(sys.argv) >= 4:
        key = sys.argv[2]
        val_str = sys.argv[3]
        if val_str.lower() == "true": val = True
        elif val_str.lower() == "false": val = False
        else:
            try:
                val = int(val_str)
            except ValueError:
                val = val_str
        cfg[key] = val
        sync_power(cfg)
        print("ok")
        sys.exit(0)

if __name__ == "__main__":
    main()
