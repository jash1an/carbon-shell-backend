#!/usr/bin/env python3
import os, sys, json

CONFIG_DIR = os.environ.get("CARBON_CONFIG_DIR", os.path.expanduser("~/.config/carbon"))
HYPR_DIR = os.path.expanduser("~/.config/hypr")

STARTUP_JSON = os.path.join(CONFIG_DIR, "carbon-startup-apps.json")
AUTOSTART_CONF = os.path.join(CONFIG_DIR, "autostart.conf")

def load_apps():
    if os.path.exists(STARTUP_JSON):
        try:
            with open(STARTUP_JSON, "r", encoding="utf-8") as f:
                data = json.load(f)
                if isinstance(data, list):
                    return data
        except Exception:
            pass
    return []

def save_apps(apps):
    for p in [STARTUP_JSON, os.path.join(HYPR_DIR, "carbon-startup-apps.json")]:
        try:
            os.makedirs(os.path.dirname(p), exist_ok=True)
            with open(p, "w", encoding="utf-8") as f:
                json.dump(apps, f, indent=2)
        except Exception:
            pass

    lines = [
        "# ==============================================================================",
        "# Carbon Shell — User Startup Applications & Daemons",
        "# Managed by Carbon Settings Hub",
        "# ==============================================================================",
        ""
    ]
    for app in apps:
        if app.get("enabled", True):
            name = app.get("name", "Application")
            cmd = app.get("command", "").strip()
            if cmd:
                lines.append(f"# {name}")
                lines.append(f"exec-once = {cmd}")
                lines.append("")

    content = "\n".join(lines)
    for p in [AUTOSTART_CONF, os.path.join(HYPR_DIR, "autostart.conf")]:
        try:
            with open(p, "w", encoding="utf-8") as f:
                f.write(content)
        except Exception:
            pass

def main():
    if len(sys.argv) < 2:
        print("Usage: carbon-startup-apply.py {list|toggle <index>|add <name> <command>|remove <index>}")
        sys.exit(1)

    cmd = sys.argv[1]
    apps = load_apps()

    def resolve_idx(arg):
        try:
            i = int(arg)
            return i if 0 <= i < len(apps) else -1
        except ValueError:
            for i, a in enumerate(apps):
                if a.get("name", "").lower() == arg.lower():
                    return i
            return -1

    if cmd == "list":
        print(json.dumps(apps))
        sys.exit(0)

    if cmd == "toggle" and len(sys.argv) >= 3:
        idx = resolve_idx(sys.argv[2])
        if idx != -1:
            apps[idx]["enabled"] = not apps[idx].get("enabled", True)
            save_apps(apps)
            print("ok")
        else:
            print("invalid index")
        sys.exit(0)

    if cmd == "remove" and len(sys.argv) >= 3:
        idx = resolve_idx(sys.argv[2])
        if idx != -1:
            apps.pop(idx)
            save_apps(apps)
            print("ok")
        else:
            print("invalid index")
        sys.exit(0)

    if cmd == "add" and len(sys.argv) >= 4:
        name = sys.argv[2]
        command = sys.argv[3]
        apps.append({
            "name": name,
            "command": command,
            "icon": "application-x-executable",
            "enabled": True
        })
        save_apps(apps)
        print("ok")
        sys.exit(0)

if __name__ == "__main__":
    main()
