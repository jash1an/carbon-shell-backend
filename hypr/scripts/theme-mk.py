#!/usr/bin/env python3
"""Carbon theme generator with intelligent Material You wallpaper adaptation.

Reads the current wallpaper and generates an intelligent Material You palette
using PIL color analysis (with fallback to matugen/caelestia if present).
Ensures vibrant, harmonious accent colors across Quickshell, GTK, Hyprland,
and terminal.

Usage: theme-mk.py [/path/to/wallpaper]
"""

import colorsys
import json
import os
import subprocess
import sys
from PIL import Image

CARBON_CONFIG_DIR = os.environ.get("CARBON_CONFIG_DIR", os.path.expanduser("~/.config/carbon"))
HYPR_CONFIG_DIR = os.path.expanduser("~/.config/hypr")
JSON_PATH = os.path.join(CARBON_CONFIG_DIR, "theme.json")
HYPR_JSON_PATH = os.path.join(HYPR_CONFIG_DIR, "theme.json")
CACHE_DIR = os.path.expanduser("~/.cache/carbon")

OK = "#a6e3a1"
WARN = "#f9e2af"
ERR = "#f38ba8"


def to_255(v):
    return max(0, min(255, int(round(v))))


def hexs(rgb):
    return "#%02X%02X%02X" % tuple(to_255(c) for c in rgb)


def alpha(hexc, a):
    return "#%02X%s" % (int(round(a * 255)), hexc.lstrip("#"))


def get_luminance(hex_str):
    h = hex_str.lstrip("#")
    if len(h) < 6:
        return 0.5
    r = int(h[0:2], 16) / 255.0
    g = int(h[2:4], 16) / 255.0
    b = int(h[4:6], 16) / 255.0
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def resolve_source_wallpaper():
    # 1. Command-line argument
    if len(sys.argv) > 1 and os.path.isfile(sys.argv[1]):
        return os.path.abspath(sys.argv[1])

    # 2. current_wallpaper_path file
    for p_dir in [CARBON_CONFIG_DIR, os.path.expanduser("~/.config/carbon"), os.path.expanduser("~/.config/hypr")]:
        path_file = os.path.join(p_dir, "current_wallpaper_path")
        if os.path.isfile(path_file):
            try:
                with open(path_file, "r", encoding="utf-8") as f:
                    p = f.read().strip()
                if os.path.isfile(p):
                    return p
            except Exception:
                pass

    # 3. current_wallpaper file/copy
    for p_dir in [CARBON_CONFIG_DIR, os.path.expanduser("~/.config/carbon"), os.path.expanduser("~/.config/hypr")]:
        c_wall = os.path.join(p_dir, "current_wallpaper")
        if os.path.isfile(c_wall):
            return c_wall

    # 4. Cached scaled wallpaper
    scaled = os.path.expanduser("~/.cache/carbon/wallpaper_scaled.jpg")
    if os.path.isfile(scaled):
        return scaled

    return None


def get_image_frame_for_analysis(src_path):
    """If the wallpaper is a video or gif, return a static frame path."""
    ext = os.path.splitext(src_path)[1].lower()
    if ext in {".mp4", ".m4v", ".webm", ".mkv", ".gif"}:
        thumb = os.path.join(CACHE_DIR, "wp_temp_frame.jpg")
        if os.path.isfile(thumb) and os.path.getsize(thumb) > 0:
            return thumb
        try:
            if ext == ".gif":
                subprocess.run(["magick", f"{src_path}[0]", "-resize", "800x", thumb], timeout=3.0)
            else:
                subprocess.run(
                    ["ffmpeg", "-y", "-i", src_path, "-vframes", "1", "-ss", "00:00:00.500", thumb],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=4.0
                )
            if os.path.isfile(thumb):
                return thumb
        except Exception:
            pass
    return src_path


def is_monochrome_image(img_path):
    """Check if an image has very low midtone color saturation."""
    try:
        im = Image.open(img_path).convert("RGB")
        small = im.resize((48, 27), Image.LANCZOS)
        try:
            px = list(small.get_flattened_data()) if hasattr(small, "get_flattened_data") else list(small.getdata())
        except Exception:
            return False

        mid_sats = []
        for r, g, b in px:
            mx = max(r, g, b)
            mn = min(r, g, b)
            if 25 < mx < 230:
                sat = (mx - mn) / float(mx)
                mid_sats.append(sat)
        if mid_sats:
            mean_sat = sum(mid_sats) / len(mid_sats)
            return mean_sat < 0.08
        return False
    except Exception:
        pass
    return False


def extract_wallpaper_palette(img_path):
    """Extract an intelligent Material You style palette from wallpaper using PIL."""
    im = Image.open(img_path).convert("RGB")
    small = im.resize((120, 120), Image.LANCZOS)
    try:
        raw = list(small.get_flattened_data()) if hasattr(small, "get_flattened_data") else list(small.getdata())
    except Exception:
        raw = []

    bins = {}
    for r, g, b in raw:
        h, l, s = colorsys.rgb_to_hls(r / 255.0, g / 255.0, b / 255.0)
        if s > 0.16 and 0.12 < l < 0.88:
            hb = round(h * 36) % 36
            score = (s ** 1.2) * (1.0 - abs(l - 0.55) * 0.6)
            if hb not in bins:
                bins[hb] = [0, 0.0, []]
            bins[hb][0] += 1
            bins[hb][1] += score
            if len(bins[hb][2]) < 60:
                bins[hb][2].append((h, s, l))

    if not bins:
        h_pri, s_pri = 0.58, 0.65
    else:
        top_bucket = sorted(bins.values(), key=lambda x: x[1], reverse=True)[0]
        samples = top_bucket[2]
        h_pri = sum(x[0] for x in samples) / len(samples)
        s_pri = sum(x[1] for x in samples) / len(samples)

    # Accent (primary): High-legibility, vibrant dark mode color (L: 0.72)
    sat = min(0.92, max(0.58, s_pri * 1.25))
    r, g, b = colorsys.hls_to_rgb(h_pri, 0.72, sat)
    accent_hex = hexs((r * 255, g * 255, b * 255))

    # AccentLit (primary_container): Lighter pastel tint (L: 0.86)
    r, g, b = colorsys.hls_to_rgb(h_pri, 0.86, min(0.85, sat * 0.90))
    accent_lit_hex = hexs((r * 255, g * 255, b * 255))

    # OnAccent (on_primary): Dark text on bright accent
    lum = get_luminance(accent_hex)
    on_accent_hex = "#101116" if lum > 0.45 else "#FFFFFF"

    # Surface & background subtly tinted with wallpaper's dominant hue
    bg_sat = min(0.32, max(0.18, sat * 0.38))
    r, g, b = colorsys.hls_to_rgb(h_pri, 0.08, bg_sat)
    bg_hex = hexs((r * 255, g * 255, b * 255))

    r, g, b = colorsys.hls_to_rgb(h_pri, 0.13, min(0.30, bg_sat * 0.90))
    bg_alt_hex = hexs((r * 255, g * 255, b * 255))

    fg_hex = "#E6E4F0"

    # Outline
    r, g, b = colorsys.hls_to_rgb(h_pri, 0.28, min(0.30, bg_sat * 0.90))
    outline_hex = hexs((r * 255, g * 255, b * 255))

    # Tertiary: Harmonious secondary hue (+55° hue shift) for vibrant multi-color accents
    h_ter = (h_pri + 0.15) % 1.0
    r, g, b = colorsys.hls_to_rgb(h_ter, 0.76, min(0.85, sat * 0.90))
    tertiary_hex = hexs((r * 255, g * 255, b * 255))

    return {
        "accent": accent_hex,
        "accentLit": accent_lit_hex,
        "tertiary": tertiary_hex,
        "onAccent": on_accent_hex,
        "bg": bg_hex,
        "bgAlt": bg_alt_hex,
        "fg": fg_hex,
        "outline": outline_hex,
        "isDark": True,
        "h_pri": h_pri
    }


def update_fastfetch_logo(accent_hex, fg_hex):
    """Generate theme-sensitive ANSI Bohr atom logo for fastfetch."""
    try:
        h = accent_hex.lstrip("#")
        if len(h) >= 6:
            r = int(h[0:2], 16)
            g = int(h[2:4], 16)
            b = int(h[4:6], 16)
        else:
            r, g, b = (56, 189, 248)

        rr, rg, rb = int(r * 0.55), int(g * 0.55), int(b * 0.55)
        DOT = f"\033[1;38;2;{r};{g};{b}m●\033[0m"
        RING = f"\033[38;2;{rr};{rg};{rb}m"
        GLYPH = f"\033[1;37mC\033[0m"
        RST = "\033[0m"

        lines = [
            f"           {DOT}           ",
            f"       {RING}╭───────╮{RST}       ",
            f"     {RING}╭─╯{RST}   {DOT}   {RING}╰─╮{RST}     ",
            f"    {RING}╭╯   ╭───╮   ╰╮{RST}    ",
            f"  {DOT} {RING}│    │{RST} {GLYPH} {RING}│    │{RST} {DOT}  ",
            f"    {RING}╰╮   ╰───╯   ╭╯{RST}    ",
            f"     {RING}╰─╮{RST}   {DOT}   {RING}╭─╯{RST}     ",
            f"       {RING}╰───────╯{RST}       ",
            f"           {DOT}           ",
        ]

        logo_path = os.path.expanduser("~/.config/fastfetch/carbon-bohr.txt")
        os.makedirs(os.path.dirname(logo_path), exist_ok=True)
        with open(logo_path, "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")
    except Exception:
        pass


def update_gtk_theme(accent_hex, on_accent_hex):
    """Update GTK 3 and GTK 4 accent color CSS to adapt entire desktop."""
    css_content = f"""/* Dynamically generated by Carbon theme-mk */
@define-color accent_color {accent_hex};
@define-color accent_bg_color {accent_hex};
@define-color accent_fg_color {on_accent_hex};
@define-color destructive_color #f38ba8;
@define-color success_color #a6e3a1;
@define-color warning_color #f9e2af;
@define-color error_color #f38ba8;
"""
    for gtk_dir in [os.path.expanduser("~/.config/gtk-3.0"), os.path.expanduser("~/.config/gtk-4.0")]:
        os.makedirs(gtk_dir, exist_ok=True)
        css_file = os.path.join(gtk_dir, "gtk.css")
        try:
            with open(css_file, "w", encoding="utf-8") as f:
                f.write(css_content)
        except Exception:
            pass


def update_waybar_theme(accent_hex, accent_lit_hex, on_accent_hex, bg_hex, bg_alt_hex, fg_hex, outline_hex, tertiary_hex):
    def hex_to_rgb(h):
        h = h.lstrip("#")
        if len(h) == 6:
            return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
        return 25, 20, 16

    opacity = 0.88
    try:
        bar_pos_path = os.path.expanduser("~/.config/carbon/carbon-bar-position.json")
        if os.path.isfile(bar_pos_path):
            with open(bar_pos_path, "r", encoding="utf-8") as f:
                d = json.load(f)
                if "shellOpacity" in d:
                    opacity = max(0.1, min(1.0, float(d["shellOpacity"])))
    except Exception:
        pass

    bg_r, bg_g, bg_b = hex_to_rgb(bg_hex)
    bga_r, bga_g, bga_b = hex_to_rgb(bg_alt_hex)
    out_r, out_g, out_b = hex_to_rgb(outline_hex)
    acc_r, acc_g, acc_b = hex_to_rgb(accent_hex)

    css_content = f"""@define-color background rgba({bg_r}, {bg_g}, {bg_b}, {opacity:.2f});
@define-color surface rgba({bga_r}, {bga_g}, {bga_b}, 0.75);
@define-color surface-container rgba({bga_r}, {bga_g}, {bga_b}, 0.90);
@define-color text {fg_hex};
@define-color primary {accent_hex};
@define-color secondary {accent_lit_hex};
@define-color tertiary {tertiary_hex};
@define-color primary-container rgba({acc_r}, {acc_g}, {acc_b}, 0.25);
@define-color on-primary {on_accent_hex};
@define-color border rgba({out_r}, {out_g}, {out_b}, 0.45);
@define-color shadow rgba(0, 0, 0, 0.4);
"""
    for wb_dir in [os.path.expanduser("~/.config/waybar"), os.path.expanduser("~/carbon-shell/waybar")]:
        os.makedirs(wb_dir, exist_ok=True)
        colors_file = os.path.join(wb_dir, "colors.css")
        try:
            with open(colors_file, "w", encoding="utf-8") as f:
                f.write(css_content)
        except Exception:
            pass

    subprocess.run(["pkill", "-SIGUSR2", "-f", "waybar"], capture_output=True)
    subprocess.run(["pkill", "-SIGUSR2", "-x", "waybar-bin"], capture_output=True)
    subprocess.run(["pkill", "-SIGUSR2", "-x", "waybar"], capture_output=True)


def main():
    src_wp = resolve_source_wallpaper()
    if not src_wp or not os.path.exists(src_wp):
        print("theme-mk: no valid wallpaper source found", file=sys.stderr)
        sys.exit(0)

    analysis_img = get_image_frame_for_analysis(src_wp)
    is_mono = is_monochrome_image(analysis_img)
    wp_lower = os.path.basename(src_wp).lower()
    if "carbon" in wp_lower or "black" in wp_lower or "mono" in wp_lower:
        is_mono = True

    # Intelligent color extraction
    if is_mono:
        accent_hex = "#E2E2E8"
        accent_lit_hex = "#FFFFFF"
        tertiary_hex = "#D4D4DC"
        on_accent_hex = "#141418"
        bg_hex = "#121215"
        bg_alt_hex = "#1A1A1F"
        fg_hex = "#E4E4E8"
        outline_hex = "#484852"
    else:
        pal = extract_wallpaper_palette(analysis_img)
        accent_hex = pal["accent"]
        accent_lit_hex = pal["accentLit"]
        tertiary_hex = pal["tertiary"]
        on_accent_hex = pal["onAccent"]
        bg_hex = pal["bg"]
        bg_alt_hex = pal["bgAlt"]
        fg_hex = pal["fg"]
        outline_hex = pal["outline"]

    palette_dict = {
        "bg": alpha(bg_hex, 0.92),
        "bgAlt": alpha(bg_alt_hex, 0.75),
        "bgHover": alpha(accent_hex, 0.20),
        "bgActive": alpha(accent_hex, 0.35),
        "fg": fg_hex,
        "fgDim": alpha(fg_hex, 0.70),
        "fgFaint": alpha(fg_hex, 0.42),
        "accent": accent_hex,
        "accentLit": accent_lit_hex,
        "tertiary": tertiary_hex,
        "onAccent": on_accent_hex,
        "outline": alpha(outline_hex, 0.40),
        "ok": OK,
        "warn": WARN,
        "err": ERR,
        "isDark": True,
    }

    # Write theme.json atomically to both carbon and hypr configs
    for json_p in [JSON_PATH, HYPR_JSON_PATH]:
        os.makedirs(os.path.dirname(json_p), exist_ok=True)
        tmp = json_p + ".tmp"
        try:
            with open(tmp, "w", encoding="utf-8") as f:
                json.dump(palette_dict, f, indent=2)
            os.replace(tmp, json_p)
        except Exception:
            pass

    # Write Caelestia scheme.json so M3 consumers receive full color tokens
    caelestia_scheme_path = os.path.expanduser("~/.local/state/caelestia/scheme.json")
    os.makedirs(os.path.dirname(caelestia_scheme_path), exist_ok=True)
    cael_data = {
        "name": "carbon-dynamic",
        "mode": "dark",
        "colours": {
            "primary": accent_hex.lstrip("#"),
            "onPrimary": on_accent_hex.lstrip("#"),
            "primaryContainer": accent_lit_hex.lstrip("#"),
            "onPrimaryContainer": on_accent_hex.lstrip("#"),
            "accentLit": accent_lit_hex.lstrip("#"),
            "surface": bg_hex.lstrip("#"),
            "onSurface": fg_hex.lstrip("#"),
            "surfaceContainer": bg_hex.lstrip("#"),
            "surfaceContainerHigh": bg_alt_hex.lstrip("#"),
            "surfaceContainerHighest": bg_alt_hex.lstrip("#"),
            "outline": outline_hex.lstrip("#"),
            "outlineVariant": outline_hex.lstrip("#"),
            "success": OK.lstrip("#"),
            "tertiary": tertiary_hex.lstrip("#"),
            "error": ERR.lstrip("#")
        }
    }
    try:
        with open(caelestia_scheme_path + ".tmp", "w", encoding="utf-8") as f:
            json.dump(cael_data, f, indent=2)
        os.replace(caelestia_scheme_path + ".tmp", caelestia_scheme_path)
    except Exception:
        pass

    # 1. Update GTK 3 & 4 Theme
    update_gtk_theme(accent_hex, on_accent_hex)

    # 2. Update Fastfetch Bohr atom logo
    update_fastfetch_logo(accent_hex, fg_hex)

    # 3. Ensure system color-scheme is set to prefer-dark
    subprocess.run(
        ["gsettings", "set", "org.gnome.desktop.interface", "color-scheme", "prefer-dark"],
        capture_output=True
    )

    # 4. Update Hyprland active window border dynamically
    h_acc = accent_hex.lstrip("#")
    h_lit = accent_lit_hex.lstrip("#")
    subprocess.run([
        "hyprctl", "keyword", "general:col.active_border",
        f"rgba({h_acc}ee) rgba({h_lit}aa) 45deg"
    ], capture_output=True)

    # 5. Update Waybar CSS theme
    update_waybar_theme(accent_hex, accent_lit_hex, on_accent_hex, bg_hex, bg_alt_hex, fg_hex, outline_hex, tertiary_hex)

    # 6. Notify Carbon Quickshell to reload Theme singleton immediately
    try:
        ipc_path = os.path.join(CARBON_CONFIG_DIR, "scripts", "carbon-ipc.sh")
        if not os.path.isfile(ipc_path):
            ipc_path = os.path.expanduser("~/.config/carbon/scripts/carbon-ipc.sh")
        if not os.path.isfile(ipc_path):
            ipc_path = os.path.expanduser("~/.config/hypr/scripts/carbon-ipc.sh")
        if os.path.isfile(ipc_path):
            subprocess.run(["sh", ipc_path, "theme-reload"], capture_output=True, timeout=1.5)
    except Exception:
        pass

    print(f"theme-mk: updated theme (accent={accent_hex}, fg={fg_hex}, src={os.path.basename(src_wp)})")


if __name__ == "__main__":
    main()
