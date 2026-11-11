#!/usr/bin/env python3
"""Carbon Shell — Default Applications Manager.

Queries and configures system default applications for:
- Web Browser
- File Manager
- Terminal Emulator
- Text & Code Editor
- Image Viewer
- Media & Video Player
"""

import glob
import json
import os
import re
import subprocess
import sys

CONFIG_DIR = os.environ.get("CARBON_CONFIG_DIR", os.path.expanduser("~/.config/carbon"))
HYPR_DIR = os.path.expanduser("~/.config/hypr")
STATE_FILE = os.path.join(CONFIG_DIR, "carbon-default-apps.json")
TERMINAL_JSON = os.path.join(CONFIG_DIR, "carbon-terminal.json")

MIME_MAP = {
    "browser": [
        "x-scheme-handler/http",
        "x-scheme-handler/https",
        "text/html",
        "text/xml",
        "application/xhtml+xml",
        "x-scheme-handler/about",
        "x-scheme-handler/unknown",
    ],
    "filemanager": [
        "inode/directory",
    ],
    "editor": [
        "text/plain",
        "text/markdown",
        "application/octet-stream",
    ],
    "image": [
        "image/png",
        "image/jpeg",
        "image/webp",
        "image/gif",
        "image/svg+xml",
        "image/bmp",
    ],
    "video": [
        "video/mp4",
        "video/mkv",
        "video/webm",
        "video/x-matroska",
        "audio/mpeg",
        "audio/flac",
        "audio/ogg",
        "audio/wav",
    ],
}


def ensure_dirs():
    os.makedirs(CONFIG_DIR, exist_ok=True)
    os.makedirs(HYPR_DIR, exist_ok=True)


def load_state():
    if os.path.exists(STATE_FILE):
        try:
            with open(STATE_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass
    return {}


def save_state(data):
    ensure_dirs()
    for d in [CONFIG_DIR, HYPR_DIR]:
        p = os.path.join(d, "carbon-default-apps.json")
        try:
            with open(p, "w", encoding="utf-8") as f:
                json.dump(data, f, indent=2)
        except Exception:
            pass


def get_installed_desktop_apps():
    apps = {}
    search_dirs = [
        "/usr/share/applications",
        os.path.expanduser("~/.local/share/applications"),
    ]
    for d in search_dirs:
        for p in glob.glob(d + "/*.desktop"):
            fn = os.path.basename(p)
            try:
                with open(p, "r", encoding="utf-8", errors="ignore") as f:
                    name, exec_cmd, icon, cats, mimes, nodisp = "", "", "", "", "", False
                    for line in f:
                        line = line.strip()
                        if line.startswith("Name=") and not name:
                            name = line.split("=", 1)[1]
                        elif line.startswith("Exec=") and not exec_cmd:
                            exec_cmd = line.split("=", 1)[1]
                        elif line.startswith("Icon=") and not icon:
                            icon = line.split("=", 1)[1]
                        elif line.startswith("Categories="):
                            cats = line.split("=", 1)[1]
                        elif line.startswith("MimeType="):
                            mimes = line.split("=", 1)[1]
                        elif line == "NoDisplay=true":
                            nodisp = True
                    if not nodisp and name and exec_cmd:
                        apps[fn] = {
                            "id": fn,
                            "name": name,
                            "exec": exec_cmd,
                            "icon": icon,
                            "categories": cats,
                            "mimes": mimes,
                        }
            except Exception:
                pass
    return apps


def query_mime(mime):
    try:
        r = subprocess.run(["xdg-mime", "query", "default", mime], capture_output=True, text=True, timeout=1.0)
        return r.stdout.strip()
    except Exception:
        return ""


def get_current_default(cat, state, apps):
    # Check custom state override first
    if cat in state and state[cat]:
        val = state[cat]
        if val in apps:
            return val

    if cat == "browser":
        try:
            r = subprocess.run(["xdg-settings", "get", "default-web-browser"], capture_output=True, text=True, timeout=1.0)
            cur = r.stdout.strip()
            if cur and (cur in apps or cur.endswith(".desktop")):
                return cur
        except Exception:
            pass
        return query_mime("x-scheme-handler/https") or query_mime("text/html") or "librewolf.desktop"

    if cat == "filemanager":
        cur = query_mime("inode/directory")
        if cur and cur != "codium.desktop":
            return cur
        return "org.gnome.Nautilus.desktop"

    if cat == "terminal":
        # Check carbon-terminal.json or state
        if os.path.exists(TERMINAL_JSON):
            try:
                with open(TERMINAL_JSON, "r", encoding="utf-8") as f:
                    t_data = json.load(f)
                    if isinstance(t_data, dict) and "terminal" in t_data:
                        t = t_data["terminal"].lower()
                        for app_id in apps:
                            if t in app_id.lower():
                                return app_id
            except Exception:
                pass
        return "kitty.desktop"

    if cat == "editor":
        cur = query_mime("text/plain")
        if cur:
            return cur
        return "org.xfce.mousepad.desktop"

    if cat == "image":
        cur = query_mime("image/png") or query_mime("image/jpeg")
        if cur and "firefox" not in cur.lower():
            return cur
        return "org.kde.gwenview.desktop"

    if cat == "video":
        cur = query_mime("video/mp4")
        if cur:
            return cur
        return "mpv.desktop"

    return ""


def filter_candidates(cat, apps):
    out = []
    for app_id, app in apps.items():
        matched = False
        cats = app.get("categories", "")
        mimes = app.get("mimes", "")
        low_id = app_id.lower()

        if cat == "browser":
            if "WebBrowser" in cats or "x-scheme-handler/http" in mimes or any(x in low_id for x in ["browser", "firefox", "librewolf", "chrome", "chromium", "zen", "brave"]):
                matched = True
        elif cat == "filemanager":
            if "FileManager" in cats or "inode/directory" in mimes or any(x in low_id for x in ["nautilus", "dolphin", "thunar", "yazi", "pcmanfm", "nemo"]):
                if low_id not in ["codium.desktop", "org.kde.gwenview.desktop"]:
                    matched = True
        elif cat == "terminal":
            if "TerminalEmulator" in cats or any(x in low_id for x in ["kitty", "alacritty", "foot", "ghostty", "wezterm", "terminal"]):
                matched = True
        elif cat == "editor":
            if "TextEditor" in cats or "text/plain" in mimes or any(x in low_id for x in ["code", "codium", "mousepad", "kate", "kwrite", "nvim", "gedit", "sublime", "atom"]):
                matched = True
        elif cat == "image":
            if "image/png" in mimes or "image/jpeg" in mimes or "ImageViewer" in cats or any(x in low_id for x in ["gwenview", "loupe", "eog", "viewnior", "feh", "imv", "ristretto"]):
                if "firefox" not in low_id and "librewolf" not in low_id:
                    matched = True
        elif cat == "video":
            if "video/mp4" in mimes or any(x in low_id for x in ["mpv", "vlc", "celluloid", "totem", "smplayer", "parole", "haruna"]):
                if not any(x in low_id for x in ["pavucontrol", "easyeffects", "qv4l2", "qvidcap", "muse"]):
                    matched = True

        if matched:
            out.append({
                "id": app["id"],
                "name": app["name"],
                "exec": app["exec"].split()[0] if app["exec"] else app["id"],
                "icon": app["icon"] or "application-x-executable"
            })

    # Sort candidates by name
    out.sort(key=lambda x: x["name"].lower())
    return out


def update_hypr_browser_keybind(browser_cmd):
    """Keep Hyprland keybinds aligned when user selects a default browser."""
    keybind_files = [
        os.path.join(HYPR_DIR, "keybinds.lua"),
        os.path.join(os.path.expanduser("~/carbon-shell/hypr"), "keybinds.lua"),
        os.path.join(os.path.expanduser("~/carbon-shell/hypr"), "variables.lua"),
    ]
    for kf in keybind_files:
        if not os.path.exists(kf):
            continue
        try:
            with open(kf, "r", encoding="utf-8") as f:
                content = f.read()

            # Update lua keybind
            updated = re.sub(
                r'hl\.bind\(mainMod\s*\.\.\s*"\s*\+\s*F",\s*hl\.dsp\.exec_cmd\(".*?"\)\)',
                f'hl.bind(mainMod .. " + F", hl.dsp.exec_cmd("{browser_cmd}"))',
                content
            )
            # Update local browser variable if present
            updated = re.sub(
                r'local\s+browser\s*=\s*".*?"',
                f'local browser = "{browser_cmd}"',
                updated
            )
            if updated != content:
                with open(kf, "w", encoding="utf-8") as f:
                    f.write(updated)
        except Exception:
            pass

    # Keybinds conf
    conf_files = [
        os.path.join(HYPR_DIR, "keybinds.conf"),
        os.path.join(HYPR_DIR, "configs/keybinds.conf"),
        os.path.join(os.path.expanduser("~/carbon-shell/hypr"), "keybinds.conf"),
        os.path.join(os.path.expanduser("~/carbon-shell/hypr"), "configs/keybinds.conf"),
    ]
    for cf in conf_files:
        if not os.path.exists(cf):
            continue
        try:
            with open(cf, "r", encoding="utf-8") as f:
                content = f.read()
            updated = re.sub(
                r'(bind\s*=\s*\$mainMod,\s*F,\s*exec,\s*).*',
                rf'\g<1>{browser_cmd}',
                content
            )
            if updated != content:
                with open(cf, "w", encoding="utf-8") as f:
                    f.write(updated)
        except Exception:
            pass

    try:
        subprocess.run(["hyprctl", "reload"], capture_output=True, timeout=1.0)
    except Exception:
        pass


def set_default(cat, app_id):
    apps = get_installed_desktop_apps()
    state = load_state()
    state[cat] = app_id

    # Remember custom chosen options
    custom_opts = state.setdefault("custom_options", {})
    cat_opts = custom_opts.setdefault(cat, [])
    if app_id not in cat_opts:
        cat_opts.append(app_id)

    save_state(state)

    mimes = MIME_MAP.get(cat, [])
    for m in mimes:
        try:
            subprocess.run(["xdg-mime", "default", app_id, m], capture_output=True, timeout=1.5)
        except Exception:
            pass

    if cat == "browser":
        try:
            subprocess.run(["xdg-settings", "set", "default-web-browser", app_id], capture_output=True, timeout=1.5)
        except Exception:
            pass
        # Extract command
        app_obj = apps.get(app_id, {})
        cmd = app_obj.get("exec", "").split()[0] if app_obj.get("exec") else app_id.replace(".desktop", "")
        if cmd:
            update_hypr_browser_keybind(cmd)

    elif cat == "terminal":
        app_obj = apps.get(app_id, {})
        cmd = app_obj.get("exec", "").split()[0] if app_obj.get("exec") else app_id.replace(".desktop", "")
        if cmd:
            t_data = {"terminal": cmd}
            for d in [CONFIG_DIR, HYPR_DIR]:
                try:
                    with open(os.path.join(d, "carbon-terminal.json"), "w", encoding="utf-8") as f:
                        json.dump(t_data, f, indent=2)
                except Exception:
                    pass

    return True


def get_all_apps():
    apps = get_installed_desktop_apps()
    out = []
    for app_id, app in apps.items():
        out.append({
            "id": app["id"],
            "name": app["name"],
            "exec": app["exec"].split()[0] if app["exec"] else app["id"],
            "icon": app.get("icon", "application-x-executable") or "application-x-executable",
            "categories": app.get("categories", "")
        })
    out.sort(key=lambda x: x["name"].lower())
    return out


def pick_file_and_set(cat):
    try:
        r = subprocess.run([
            "zenity", "--file-selection",
            "--title=Select Application (.desktop or executable)",
            "--file-filter=Desktop Launchers (*.desktop) | *.desktop",
            "--file-filter=All Files (*) | *"
        ], capture_output=True, text=True, timeout=120.0)
        chosen = r.stdout.strip()
        if chosen and os.path.exists(chosen):
            app_id = os.path.basename(chosen)
            if not app_id.endswith(".desktop"):
                desk_name = os.path.splitext(app_id)[0].title()
                app_id = f"custom-{app_id.lower()}.desktop"
                desk_dir = os.path.expanduser("~/.local/share/applications")
                os.makedirs(desk_dir, exist_ok=True)
                desk_path = os.path.join(desk_dir, app_id)
                with open(desk_path, "w", encoding="utf-8") as f:
                    f.write(f"[Desktop Entry]\nName={desk_name}\nExec={chosen} %U\nType=Application\nTerminal=false\n")
            set_default(cat, app_id)
            return {"status": "ok", "category": cat, "app": app_id}
    except Exception as e:
        return {"status": "error", "error": str(e)}
    return {"status": "cancelled"}


def get_data():
    apps = get_installed_desktop_apps()
    state = load_state()

    cats_meta = [
        {
            "id": "browser",
            "title": "Web Browser",
            "glyph": "󰈹",
            "desc": "Default browser for opening hyperlinks, URLs, and web pages"
        },
        {
            "id": "filemanager",
            "title": "File Manager",
            "glyph": "󰉋",
            "desc": "Default file browser for navigating directories, folders, and storage"
        },
        {
            "id": "terminal",
            "title": "Terminal Emulator",
            "glyph": "󰞷",
            "desc": "Default command-line shell and terminal window environment"
        },
        {
            "id": "editor",
            "title": "Text & Code Editor",
            "glyph": "󰅩",
            "desc": "Default application for editing text files, scripts, and source code"
        },
        {
            "id": "image",
            "title": "Image Viewer",
            "glyph": "󰋩",
            "desc": "Default viewer for photographs, PNG, JPEG, SVG, and raster art"
        },
        {
            "id": "video",
            "title": "Media & Video Player",
            "glyph": "󰕼",
            "desc": "Default multimedia player for video clips, movies, and sound streams"
        }
    ]

    result = []
    for meta in cats_meta:
        cat_id = meta["id"]
        cur_id = get_current_default(cat_id, state, apps)
        cur_app = apps.get(cur_id, {})
        cur_name = cur_app.get("name", cur_id.replace(".desktop", "").title())
        cur_icon = cur_app.get("icon", "application-x-executable")
        options = filter_candidates(cat_id, apps)

        # Include custom remembered options
        custom_ids = state.get("custom_options", {}).get(cat_id, [])
        for cid in custom_ids:
            if cid in apps and not any(o["id"] == cid for o in options):
                capp = apps[cid]
                options.append({
                    "id": cid,
                    "name": capp["name"],
                    "exec": capp.get("exec", cid).split()[0] if capp.get("exec") else cid,
                    "icon": capp.get("icon", "application-x-executable") or "application-x-executable"
                })

        # Ensure current is in options if not already
        if cur_id and not any(o["id"] == cur_id for o in options):
            options.insert(0, {
                "id": cur_id,
                "name": cur_name,
                "exec": cur_app.get("exec", cur_id).split()[0] if cur_app else cur_id,
                "icon": cur_icon
            })

        result.append({
            "category": cat_id,
            "title": meta["title"],
            "glyph": meta["glyph"],
            "desc": meta["desc"],
            "current": cur_id,
            "currentName": cur_name,
            "currentIcon": cur_icon,
            "options": options
        })

    return result


def main():
    if len(sys.argv) < 2:
        print(json.dumps(get_data()))
        sys.exit(0)

    cmd = sys.argv[1]
    if cmd in ("get", "list", "dump"):
        print(json.dumps(get_data()))
        sys.exit(0)

    if cmd in ("all-apps", "all"):
        print(json.dumps(get_all_apps()))
        sys.exit(0)

    if cmd == "pick-file" and len(sys.argv) >= 3:
        cat = sys.argv[2]
        res = pick_file_and_set(cat)
        print(json.dumps(res))
        sys.exit(0)

    if cmd == "set" and len(sys.argv) >= 4:
        cat = sys.argv[2]
        app_id = sys.argv[3]
        set_default(cat, app_id)
        print(json.dumps({"status": "ok", "category": cat, "app": app_id}))
        sys.exit(0)

    print("Usage: carbon-default-apps.py {get|all-apps|pick-file <cat>|set <cat> <app_id>}")
    sys.exit(1)


if __name__ == "__main__":
    main()
