#!/usr/bin/env python3
import os, sys, json, subprocess

CONFIG_DIR = os.environ.get("CARBON_CONFIG_DIR", os.path.expanduser("~/.config/carbon"))
HYPR_DIR = os.path.expanduser("~/.config/hypr")

MOUSE_JSON = os.path.join(CONFIG_DIR, "carbon-mouse-touchpad.json")
KB_JSON = os.path.join(CONFIG_DIR, "carbon-keyboard.json")
INPUT_CONF = os.path.join(CONFIG_DIR, "input.conf")
TOUCHPAD_CONF = os.path.join(CONFIG_DIR, "touchpad.conf")

DEFAULT_MOUSE = {
    "sensitivity": 0.0,
    "accel_profile": "adaptive",
    "left_handed": False,
    "natural_scroll_mouse": False,
    "follow_mouse": 1,
    "touchpad_enabled": True,
    "tap_to_click": True,
    "natural_scroll_touchpad": True,
    "disable_while_typing": True,
    "tap_and_drag": True,
    "clickfinger_behavior": False,
    "scroll_factor": 1.0,
}

DEFAULT_KB = {
    "kb_layout": "us",
    "kb_variant": "",
    "kb_model": "",
    "kb_options": "",
    "repeat_delay": 600,
    "repeat_rate": 25,
    "numlock_by_default": False,
    "layout_switch_shortcut": "none",
    "caps_behavior": "default"
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

def sync_confs(mouse_cfg, kb_cfg):
    options_list = []
    base_options = kb_cfg.get("kb_options", "").strip()
    if base_options:
        for opt in base_options.split(","):
            opt = opt.strip()
            if opt and opt not in options_list:
                options_list.append(opt)

    switch_sh = kb_cfg.get("layout_switch_shortcut", "none")
    if switch_sh == "alt_shift" and "grp:alt_shift_toggle" not in options_list:
        options_list.append("grp:alt_shift_toggle")
    elif switch_sh == "win_space" and "grp:win_space_toggle" not in options_list:
        options_list.append("grp:win_space_toggle")
    elif switch_sh == "caps" and "grp:caps_toggle" not in options_list:
        options_list.append("grp:caps_toggle")

    caps_b = kb_cfg.get("caps_behavior", "default")
    if caps_b == "caps:escape" and "caps:escape" not in options_list:
        options_list.append("caps:escape")
    elif caps_b == "caps:swapescape" and "caps:swapescape" not in options_list:
        options_list.append("caps:swapescape")
    elif caps_b == "ctrl:nocaps" and "ctrl:nocaps" not in options_list:
        options_list.append("ctrl:nocaps")

    xkb_opts = ",".join(options_list)
    accel = mouse_cfg.get("accel_profile", "adaptive")

    lines = [
        "# ==============================================================================",
        "# Carbon Shell — Input Configuration (Mouse, Touchpad & Keyboard)",
        "# Managed by Carbon Settings Hub",
        "# ==============================================================================",
        "",
        "input {",
        f"    kb_layout = {kb_cfg.get('kb_layout', 'us')}",
        f"    kb_variant = {kb_cfg.get('kb_variant', '')}",
        f"    kb_model = {kb_cfg.get('kb_model', '')}",
        f"    kb_options = {xkb_opts}",
        f"    repeat_rate = {int(kb_cfg.get('repeat_rate', 25))}",
        f"    repeat_delay = {int(kb_cfg.get('repeat_delay', 600))}",
        f"    numlock_by_default = {'true' if kb_cfg.get('numlock_by_default') else 'false'}",
        "",
        f"    sensitivity = {float(mouse_cfg.get('sensitivity', 0.0)):.2f}",
        f"    accel_profile = {accel if accel != 'default' else ''}",
        f"    left_handed = {'true' if mouse_cfg.get('left_handed') else 'false'}",
        f"    follow_mouse = {int(mouse_cfg.get('follow_mouse', 1))}",
        f"    natural_scroll = {'true' if mouse_cfg.get('natural_scroll_mouse') else 'false'}",
        "",
        "    touchpad {",
        f"        disable_while_typing = {'true' if mouse_cfg.get('disable_while_typing', True) else 'false'}",
        f"        natural_scroll = {'true' if mouse_cfg.get('natural_scroll_touchpad', True) else 'false'}",
        f"        tap-to-click = {'true' if mouse_cfg.get('tap_to_click', True) else 'false'}",
        f"        tap-and-drag = {'true' if mouse_cfg.get('tap_and_drag', True) else 'false'}",
        f"        clickfinger_behavior = {'true' if mouse_cfg.get('clickfinger_behavior') else 'false'}",
        f"        scroll_factor = {float(mouse_cfg.get('scroll_factor', 1.0)):.2f}",
        "    }",
        "}",
        ""
    ]
    content = "\n".join(lines)
    for p in [INPUT_CONF, os.path.join(HYPR_DIR, "input.conf")]:
        try:
            with open(p, "w", encoding="utf-8") as f:
                f.write(content)
        except Exception:
            pass

    # Touchpad per-device override
    tp_enabled = mouse_cfg.get("touchpad_enabled", True)
    tp_content = (
        "# ==============================================================================\n"
        "# Per-device overrides — Touchpad\n"
        "# Managed by Carbon Settings Hub\n"
        "# ==============================================================================\n\n"
        "device {\n"
        "    name = dll07d0:01-044e:120b\n"
        f"    enabled = {'true' if tp_enabled else 'false'}\n"
        "}\n"
    )
    for p in [TOUCHPAD_CONF, os.path.join(HYPR_DIR, "touchpad.conf")]:
        try:
            with open(p, "w", encoding="utf-8") as f:
                f.write(tp_content)
        except Exception:
            pass

    # Live hyprctl reload for instant compositor application
    try:
        subprocess.run(["hyprctl", "reload", "config-only"], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception:
        pass

def main():
    if len(sys.argv) < 2:
        print("Usage: carbon-input-apply.py {get|set-mouse <key> <val>|set-kb <key> <val>}")
        sys.exit(1)

    cmd = sys.argv[1]
    mouse_cfg = load_json(MOUSE_JSON, DEFAULT_MOUSE)
    kb_cfg = load_json(KB_JSON, DEFAULT_KB)

    if cmd == "get":
        out = {"mouse": mouse_cfg, "keyboard": kb_cfg}
        print(json.dumps(out))
        sys.exit(0)

    if cmd == "set-mouse" and len(sys.argv) >= 4:
        key = sys.argv[2]
        val_str = sys.argv[3]
        if val_str.lower() == "true": val = True
        elif val_str.lower() == "false": val = False
        else:
            try:
                val = float(val_str) if "." in val_str else int(val_str)
            except ValueError:
                val = val_str
        mouse_cfg[key] = val
        save_json(MOUSE_JSON, mouse_cfg)
        sync_confs(mouse_cfg, kb_cfg)
        print("ok")
        sys.exit(0)

    if cmd == "set-kb" and len(sys.argv) >= 4:
        key = sys.argv[2]
        val_str = sys.argv[3]
        if val_str.lower() == "true": val = True
        elif val_str.lower() == "false": val = False
        else:
            try:
                val = int(val_str)
            except ValueError:
                val = val_str
        kb_cfg[key] = val
        save_json(KB_JSON, kb_cfg)
        sync_confs(mouse_cfg, kb_cfg)
        print("ok")
        sys.exit(0)

if __name__ == "__main__":
    main()
