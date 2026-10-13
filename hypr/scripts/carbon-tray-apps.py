#!/usr/bin/env python3
"""
carbon-tray-apps.py
Collects all active background applications and running desktop apps
for the Carbon Shell Windows-style system tray popup.
"""

import os
import sys
import json
import glob
import subprocess
import shutil

def build_desktop_map():
    d_map = {}
    search_dirs = [
        "/usr/share/applications",
        os.path.expanduser("~/.local/share/applications")
    ]
    for d in search_dirs:
        if not os.path.isdir(d):
            continue
        for f in glob.glob(os.path.join(d, "*.desktop")):
            try:
                base = os.path.splitext(os.path.basename(f))[0].lower()
                name, icon, exec_cmd = "", "", ""
                with open(f, "r", errors="ignore") as fp:
                    for line in fp:
                        if line.startswith("Name=") and not name:
                            name = line.strip().split("=", 1)[1]
                        elif line.startswith("Icon=") and not icon:
                            icon = line.strip().split("=", 1)[1]
                        elif line.startswith("Exec=") and not exec_cmd:
                            exec_cmd = line.strip().split("=", 1)[1]
                entry = {"name": name, "icon": icon, "exec": exec_cmd}
                d_map[base] = entry
                if exec_cmd:
                    exe = os.path.basename(exec_cmd.split()[0]).lower()
                    if exe not in d_map:
                        d_map[exe] = entry
            except Exception:
                pass
    return d_map

def resolve_icon_path(icon_name):
    if not icon_name:
        return ""
    if os.path.isabs(icon_name) and os.path.exists(icon_name):
        return f"file://{icon_name}"
    
    local_icons = os.path.expanduser("~/.local/share/icons")
    kitty_icons = os.path.expanduser("~/.local/opt/kitty/share/icons")
    candidates = [
        f"{local_icons}/hicolor/scalable/apps/{icon_name}.svg",
        f"{local_icons}/hicolor/256x256/apps/{icon_name}.png",
        f"{local_icons}/hicolor/128x128/apps/{icon_name}.png",
        f"{kitty_icons}/hicolor/scalable/apps/{icon_name}.svg",
        f"{kitty_icons}/hicolor/256x256/apps/{icon_name}.png",
        f"/usr/share/icons/Papirus/64x64@2x/apps/{icon_name}.svg",
        f"/usr/share/icons/Papirus/64x64/apps/{icon_name}.svg",
        f"/usr/share/icons/Papirus/64x64@2x/categories/{icon_name}.svg",
        f"/usr/share/icons/hicolor/scalable/apps/{icon_name}.svg",
        f"/usr/share/icons/hicolor/512x512/apps/{icon_name}.png",
        f"/usr/share/icons/hicolor/256x256/apps/{icon_name}.png",
        f"/usr/share/icons/hicolor/128x128/apps/{icon_name}.png",
        f"/usr/share/icons/hicolor/64x64/apps/{icon_name}.png",
        f"/usr/share/icons/hicolor/48x48/apps/{icon_name}.png",
        f"/usr/share/icons/breeze/apps/64/{icon_name}.svg",
        f"/usr/share/icons/breeze/apps/48/{icon_name}.svg",
        f"/usr/share/icons/breeze/devices/64/{icon_name}.svg",
        f"/usr/share/icons/breeze/devices/22/{icon_name}.svg",
        f"/usr/share/icons/breeze/preferences/22/{icon_name}.svg",
        f"/usr/share/pixmaps/{icon_name}.svg",
        f"/usr/share/pixmaps/{icon_name}.png",
    ]
    for c in candidates:
        if os.path.exists(c):
            return f"file://{c}"
            
    user_match = glob.glob(os.path.expanduser(f"~/.local/share/icons/**/{icon_name}.*"), recursive=True)
    if user_match and os.path.exists(user_match[0]):
        return f"file://{user_match[0]}"
        
    p_match = glob.glob(f"/usr/share/icons/Papirus/**/{icon_name}.*", recursive=True)
    if p_match and os.path.exists(p_match[0]):
        return f"file://{p_match[0]}"

    h_match = glob.glob(f"/usr/share/icons/hicolor/**/{icon_name}.*", recursive=True)
    if h_match and os.path.exists(h_match[0]):
        return f"file://{h_match[0]}"

    return ""

def main():
    desktop_map = build_desktop_map()
    apps = []
    seen_classes = set()
    seen_pids = set()

    # 1. Fetch Hyprland active client windows
    try:
        clients = json.loads(subprocess.check_output(["hyprctl", "clients", "-j"], timeout=1.5))
        for c in clients:
            cls = (c.get("class") or "").strip()
            if not cls:
                continue
            cls_lower = cls.lower()
            if cls_lower in seen_classes:
                continue
            seen_classes.add(cls_lower)
            pid = c.get("pid")
            if pid:
                seen_pids.add(pid)
                
            meta = desktop_map.get(cls_lower)
            if not meta:
                for k, v in desktop_map.items():
                    if k in cls_lower or cls_lower in k:
                        meta = v
                        break
                        
            name = (meta.get("name") if meta else "") or c.get("initialTitle") or cls.capitalize()
            icon_key = (meta.get("icon") if meta else "") or cls_lower
            icon_url = resolve_icon_path(icon_key)

            apps.append({
                "id": f"{cls_lower}-{pid}",
                "name": name,
                "title": c.get("title") or name,
                "class": cls,
                "icon": icon_key,
                "iconPath": icon_url,
                "pid": pid,
                "address": c.get("address", ""),
                "workspace": c.get("workspace", {}).get("id", 1),
                "hasWindow": True,
                "type": "window"
            })
    except Exception:
        pass

    # 2. Check Background GUI processes (minimized to tray or background services)
    try:
        user = os.environ.get("USER") or os.path.basename(os.path.expanduser("~"))
        ps_out = subprocess.check_output(["ps", "-u", user, "-o", "pid,comm,args"], timeout=1.5).decode()
        discord_path = shutil.which("discord") or os.path.expanduser("~/.local/bin/discord") or "discord"
        known_bg_patterns = [
            ("discord", "Discord", "discord", discord_path),
            ("spotify", "Spotify", "spotify", "spotify"),
            ("steam", "Steam", "steam", "steam"),
            ("telegram", "Telegram", "telegram", "telegram-desktop"),
            ("slack", "Slack", "slack", "slack"),
            ("obs", "OBS Studio", "obs", "obs")
        ]
        for line in ps_out.splitlines():
            parts = line.strip().split(None, 2)
            if len(parts) < 3:
                continue
            p_pid, comm, args = parts[0], parts[1], parts[2]
            try:
                p_pid_int = int(p_pid)
            except ValueError:
                continue
            if p_pid_int in seen_pids:
                continue
            
            for key, default_name, default_icon, default_exec in known_bg_patterns:
                if key in comm.lower() or key in args.lower():
                    if key in seen_classes:
                        break
                    seen_classes.add(key)
                    seen_pids.add(p_pid_int)
                    meta = desktop_map.get(key, {})
                    icon_key = meta.get("icon") or default_icon
                    icon_url = resolve_icon_path(icon_key)
                    
                    apps.append({
                        "id": f"{key}-{p_pid_int}",
                        "name": meta.get("name") or default_name,
                        "title": meta.get("name") or default_name,
                        "class": key,
                        "icon": icon_key,
                        "iconPath": icon_url,
                        "pid": p_pid_int,
                        "address": "",
                        "workspace": -1,
                        "hasWindow": False,
                        "exec": meta.get("exec") or default_exec,
                        "type": "background"
                    })
                    break
    except Exception:
        pass

    print(json.dumps(apps))

if __name__ == "__main__":
    main()
