#!/usr/bin/env python3
"""
Carbon Pulse — System & Task Monitor
Part of Carbon Shell ecosystem for Hyprland.
Features:
- Live Hardware Vitals: CPU %, RAM (used/total/swap), Root & Home Storage
- Categorized Views: Applications (active Hyprland windows) vs Background Processes
- Instant Filter & Search
- Right-click Context Actions: Focus Window, Open Working Directory in Nautilus, Pause/Resume
- Guaranteed Recursive Tree Kill (SIGKILL process tree and process group)
"""

import os
import sys
import shutil
import signal
import subprocess
import json
import time

import gi
gi.require_version('Gtk', '4.0')
gi.require_version('Adw', '1')
from gi.repository import Gtk, Adw, GLib, Gio, Gdk

GLib.set_prgname("carbon-pulse")
GLib.set_application_name("Carbon Pulse")

PAGE_SIZE = os.sysconf("SC_PAGE_SIZE")
NUM_CORES = os.cpu_count() or 1

def get_process_descendants(pid):
    """Recursively collect all descendant PIDs of a process."""
    descendants = set()
    queue = [pid]
    while queue:
        curr = queue.pop(0)
        try:
            res = subprocess.run(["pgrep", "-P", str(curr)], capture_output=True, text=True, timeout=1)
            if res.returncode == 0:
                for child_str in res.stdout.strip().split():
                    if child_str.isdigit():
                        child = int(child_str)
                        if child not in descendants and child != pid:
                            descendants.add(child)
                            queue.append(child)
        except Exception:
            pass
    return list(descendants)

def force_kill_tree(pid, win_address=None):
    """Guaranteed termination of process and all background helpers."""
    killed_count = 1
    if win_address:
        try:
            subprocess.run(["hyprctl", "dispatch", "closewindow", f"address:{win_address}"], timeout=1)
        except Exception:
            pass

    descendants = get_process_descendants(pid)

    # Process group kill
    try:
        pgid = os.getpgid(pid)
        if pgid > 1 and pgid != os.getpid():
            os.killpg(pgid, signal.SIGKILL)
    except Exception:
        pass

    # Reverse order kill (leaves first)
    for child in reversed(descendants):
        try:
            os.kill(child, signal.SIGKILL)
            killed_count += 1
        except Exception:
            pass

    try:
        os.kill(pid, signal.SIGKILL)
    except Exception:
        pass

    return killed_count

def read_system_cpu_ticks():
    try:
        with open("/proc/stat", "r") as f:
            fields = [float(x) for x in f.readline().split()[1:]]
            idle = fields[3] + fields[4]
            total = sum(fields)
            return idle, total
    except Exception:
        return 0.0, 1.0

def read_mem_info():
    mem = {"total": 1.0, "available": 1.0, "swap_total": 0.0, "swap_free": 0.0}
    try:
        with open("/proc/meminfo", "r") as f:
            for line in f:
                parts = line.split()
                if not parts:
                    continue
                key = parts[0].rstrip(":")
                val = float(parts[1])
                if key == "MemTotal":
                    mem["total"] = val
                elif key == "MemAvailable":
                    mem["available"] = val
                elif key == "SwapTotal":
                    mem["swap_total"] = val
                elif key == "SwapFree":
                    mem["swap_free"] = val
    except Exception:
        pass
    return mem

def read_proc_rss_mb(pid):
    try:
        with open(f"/proc/{pid}/statm", "r") as f:
            res_pages = int(f.readline().split()[1])
            return (res_pages * PAGE_SIZE) / (1024 * 1024)
    except Exception:
        return 0.0

def read_proc_ticks(pid):
    try:
        with open(f"/proc/{pid}/stat", "r") as f:
            content = f.readline()
            parts = content.split(") ")[1].split()
            utime = float(parts[11])
            stime = float(parts[12])
            return utime + stime
    except Exception:
        return 0.0

def resolve_icon_name(raw_name):
    if not raw_name:
        return "application-x-executable"
    raw_lower = raw_name.lower()
    
    # Custom aliases
    if "nautilus" in raw_lower:
        return "org.gnome.Nautilus"
    if "firefox" in raw_lower:
        return "firefox"
    if "kitty" in raw_lower:
        return "kitty"
    if "code" in raw_lower:
        return "com.visualstudio.code"
    if "discord" in raw_lower:
        return "discord"
    if "spotify" in raw_lower:
        return "spotify"
    if "steam" in raw_lower:
        return "steam"

    display = Gdk.Display.get_default()
    if display:
        theme = Gtk.IconTheme.get_for_display(display)
        if theme.has_icon(raw_name):
            return raw_name
        if theme.has_icon(raw_lower):
            return raw_lower

    return "application-x-executable"


class CarbonPulseWindow(Adw.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="Carbon Pulse")
        self.set_default_size(960, 640)

        # Force Dark Theme
        Adw.StyleManager.get_default().set_color_scheme(Adw.ColorScheme.FORCE_DARK)

        # State tracking
        self.prev_cpu_idle, self.prev_cpu_total = read_system_cpu_ticks()
        self.prev_proc_ticks = {}
        self.search_filter = ""
        self.app_rows = {}   # (pid, address) -> Gtk.ListBoxRow
        self.proc_rows = {}  # pid -> Gtk.ListBoxRow

        self.setup_ui()
        self.apply_css()

        # Initial data load
        self.refresh_all()

        # 1.5s refresh timer
        GLib.timeout_add(1500, self.on_timer_tick)

    def setup_ui(self):
        # Toast overlay for notifications
        self.toast_overlay = Adw.ToastOverlay()
        self.set_content(self.toast_overlay)

        # Root box
        root_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self.toast_overlay.set_child(root_box)

        # Header bar
        header = Adw.HeaderBar()
        root_box.append(header)

        # Title widget: App Title + ViewSwitcher
        self.view_stack = Adw.ViewStack()
        self.view_switcher = Adw.ViewSwitcher()
        self.view_switcher.set_stack(self.view_stack)
        self.view_switcher.set_policy(Adw.ViewSwitcherPolicy.WIDE)
        header.set_title_widget(self.view_switcher)

        # Refresh button in header
        refresh_btn = Gtk.Button.new_from_icon_name("view-refresh-symbolic")
        refresh_btn.set_tooltip_text("Refresh Now")
        refresh_btn.connect("clicked", lambda b: self.refresh_all())
        header.pack_end(refresh_btn)

        # Search bar
        self.search_bar = Gtk.SearchEntry()
        self.search_bar.set_placeholder_text("Search processes, apps, PIDs...")
        self.search_bar.set_hexpand(True)
        self.search_bar.connect("search-changed", self.on_search_changed)
        
        search_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)
        search_box.set_margin_start(18)
        search_box.set_margin_end(18)
        search_box.set_margin_top(8)
        search_box.set_margin_bottom(8)
        search_box.append(self.search_bar)
        root_box.append(search_box)

        # Top Vitals Dashboard
        vitals_card = self.create_vitals_dashboard()
        root_box.append(vitals_card)

        # Content ViewStack
        self.view_stack.set_vexpand(True)
        root_box.append(self.view_stack)

        # Tab 1: Applications Page
        self.app_list_box = Gtk.ListBox()
        self.app_list_box.add_css_class("boxed-list")
        self.app_list_box.set_selection_mode(Gtk.SelectionMode.NONE)
        self.app_list_box.set_filter_func(self.filter_app_row)

        app_scroller = Gtk.ScrolledWindow()
        app_scroller.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        app_scroller.set_child(self.app_list_box)
        app_scroller.set_margin_start(18)
        app_scroller.set_margin_end(18)
        app_scroller.set_margin_bottom(12)

        self.apps_page = self.view_stack.add_titled_with_icon(
            app_scroller, "apps", "Applications", "view-app-grid-symbolic"
        )

        # Tab 2: Background Processes Page
        self.proc_list_box = Gtk.ListBox()
        self.proc_list_box.add_css_class("boxed-list")
        self.proc_list_box.set_selection_mode(Gtk.SelectionMode.NONE)
        self.proc_list_box.set_filter_func(self.filter_proc_row)

        proc_scroller = Gtk.ScrolledWindow()
        proc_scroller.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        proc_scroller.set_child(self.proc_list_box)
        proc_scroller.set_margin_start(18)
        proc_scroller.set_margin_end(18)
        proc_scroller.set_margin_bottom(12)

        self.procs_page = self.view_stack.add_titled_with_icon(
            proc_scroller, "procs", "Background Processes", "system-run-symbolic"
        )

        # Shared Context Popover
        self.popover = Gtk.Popover()
        self.popover.set_parent(root_box)
        self.popover_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        self.popover_box.set_margin_start(6)
        self.popover_box.set_margin_end(6)
        self.popover_box.set_margin_top(6)
        self.popover_box.set_margin_bottom(6)
        self.popover.set_child(self.popover_box)

    def create_vitals_dashboard(self):
        container = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=14)
        container.set_margin_start(18)
        container.set_margin_end(18)
        container.set_margin_bottom(10)
        container.set_homogeneous(True)

        # 1. CPU Card
        self.cpu_card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        self.cpu_card.add_css_class("vital-card")
        
        cpu_header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        cpu_icon = Gtk.Image.new_from_icon_name("computer-symbolic")
        cpu_title = Gtk.Label(label="CPU Utilization")
        cpu_title.add_css_class("card-title")
        self.cpu_pct_lbl = Gtk.Label(label="0.0%")
        self.cpu_pct_lbl.add_css_class("card-value")
        self.cpu_pct_lbl.set_hexpand(True)
        self.cpu_pct_lbl.set_halign(Gtk.Align.END)
        cpu_header.append(cpu_icon)
        cpu_header.append(cpu_title)
        cpu_header.append(self.cpu_pct_lbl)
        
        self.cpu_bar = Gtk.ProgressBar()
        self.cpu_bar.set_fraction(0.0)
        
        self.cpu_sub = Gtk.Label(label=f"{NUM_CORES} Cores Active")
        self.cpu_sub.add_css_class("card-sub")
        self.cpu_sub.set_halign(Gtk.Align.START)

        self.cpu_card.append(cpu_header)
        self.cpu_card.append(self.cpu_bar)
        self.cpu_card.append(self.cpu_sub)
        container.append(self.cpu_card)

        # 2. Memory Card
        self.mem_card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        self.mem_card.add_css_class("vital-card")

        mem_header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        mem_icon = Gtk.Image.new_from_icon_name("drive-multidisk-symbolic")
        mem_title = Gtk.Label(label="Memory (RAM)")
        mem_title.add_css_class("card-title")
        self.mem_pct_lbl = Gtk.Label(label="0.0%")
        self.mem_pct_lbl.add_css_class("card-value")
        self.mem_pct_lbl.set_hexpand(True)
        self.mem_pct_lbl.set_halign(Gtk.Align.END)
        mem_header.append(mem_icon)
        mem_header.append(mem_title)
        mem_header.append(self.mem_pct_lbl)

        self.mem_bar = Gtk.ProgressBar()
        self.mem_bar.set_fraction(0.0)

        self.mem_sub = Gtk.Label(label="0.0 GB / 0.0 GB")
        self.mem_sub.add_css_class("card-sub")
        self.mem_sub.set_halign(Gtk.Align.START)

        self.mem_card.append(mem_header)
        self.mem_card.append(self.mem_bar)
        self.mem_card.append(self.mem_sub)
        container.append(self.mem_card)

        # 3. Storage Card
        self.disk_card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        self.disk_card.add_css_class("vital-card")

        disk_header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        disk_icon = Gtk.Image.new_from_icon_name("drive-harddisk-symbolic")
        disk_title = Gtk.Label(label="Root Storage (/)")
        disk_title.add_css_class("card-title")
        self.disk_pct_lbl = Gtk.Label(label="0.0%")
        self.disk_pct_lbl.add_css_class("card-value")
        self.disk_pct_lbl.set_hexpand(True)
        self.disk_pct_lbl.set_halign(Gtk.Align.END)
        disk_header.append(disk_icon)
        disk_header.append(disk_title)
        disk_header.append(self.disk_pct_lbl)

        self.disk_bar = Gtk.ProgressBar()
        self.disk_bar.set_fraction(0.0)

        self.disk_sub = Gtk.Label(label="0 GB / 0 GB")
        self.disk_sub.add_css_class("card-sub")
        self.disk_sub.set_halign(Gtk.Align.START)

        self.disk_card.append(disk_header)
        self.disk_card.append(self.disk_bar)
        self.disk_card.append(self.disk_sub)
        container.append(self.disk_card)

        return container

    def apply_css(self):
        css = """
        .vital-card {
            background-color: rgba(255, 255, 255, 0.05);
            border-radius: 12px;
            padding: 12px;
            border: 1px solid rgba(255, 255, 255, 0.08);
        }
        .card-title {
            font-size: 13px;
            font-weight: 600;
            color: rgba(255, 255, 255, 0.85);
        }
        .card-value {
            font-size: 13px;
            font-weight: 700;
            color: #58a6ff;
        }
        .card-sub {
            font-size: 11px;
            color: rgba(255, 255, 255, 0.55);
        }
        .stat-pill {
            background-color: rgba(255, 255, 255, 0.08);
            border-radius: 6px;
            padding: 3px 8px;
            font-size: 11px;
            font-weight: 600;
            color: rgba(255, 255, 255, 0.85);
        }
        .kill-quick-btn {
            background-color: rgba(235, 77, 75, 0.12);
            color: #ff7b72;
            border-radius: 6px;
            padding: 4px 8px;
            border: 1px solid rgba(235, 77, 75, 0.25);
        }
        .kill-quick-btn:hover {
            background-color: rgba(235, 77, 75, 0.35);
            color: #ffffff;
        }
        .popover-item {
            border-radius: 6px;
            padding: 6px 12px;
            font-size: 13px;
        }
        .popover-header {
            font-weight: 700;
            font-size: 13px;
            padding: 4px 8px;
            color: #58a6ff;
        }
        """
        provider = Gtk.CssProvider()
        provider.load_from_string(css)
        Gtk.StyleContext.add_provider_for_display(
            Gdk.Display.get_default(), provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

    def on_timer_tick(self):
        self.refresh_all()
        return True

    def refresh_all(self):
        self.update_vitals()
        self.update_applications()
        self.update_background_processes()

    def update_vitals(self):
        # 1. CPU
        idle, total = read_system_cpu_ticks()
        delta_idle = idle - self.prev_cpu_idle
        delta_total = total - self.prev_cpu_total
        self.prev_cpu_idle = idle
        self.prev_cpu_total = total

        cpu_pct = 0.0
        if delta_total > 0:
            cpu_pct = max(0.0, min(100.0, (1.0 - (delta_idle / delta_total)) * 100.0))

        self.cpu_pct_lbl.set_label(f"{cpu_pct:.1f}%")
        self.cpu_bar.set_fraction(cpu_pct / 100.0)

        # 2. RAM
        mem = read_mem_info()
        tot_gb = mem["total"] / (1024.0 * 1024.0)
        avail_gb = mem["available"] / (1024.0 * 1024.0)
        used_gb = max(0.0, tot_gb - avail_gb)
        mem_pct = (used_gb / tot_gb) * 100.0 if tot_gb > 0 else 0.0

        self.mem_pct_lbl.set_label(f"{mem_pct:.1f}%")
        self.mem_bar.set_fraction(min(1.0, mem_pct / 100.0))
        self.mem_sub.set_label(f"{used_gb:.1f} / {tot_gb:.1f} GB")

        # 3. Storage
        try:
            usage = shutil.disk_usage("/")
            disk_tot_gb = usage.total / (1024**3)
            disk_used_gb = usage.used / (1024**3)
            disk_pct = (disk_used_gb / disk_tot_gb) * 100.0 if disk_tot_gb > 0 else 0.0
            free_gb = usage.free / (1024**3)

            self.disk_pct_lbl.set_label(f"{disk_pct:.1f}%")
            self.disk_bar.set_fraction(min(1.0, disk_pct / 100.0))
            self.disk_sub.set_label(f"{disk_used_gb:.0f} / {disk_tot_gb:.0f} GB (Free: {free_gb:.0f} GB)")
        except Exception:
            pass

    def update_applications(self):
        clients = []
        try:
            res = subprocess.run(["hyprctl", "clients", "-j"], capture_output=True, text=True, timeout=1)
            if res.returncode == 0:
                clients = json.loads(res.stdout)
        except Exception:
            pass

        # Filter valid clients with PID > 0
        valid_clients = [c for c in clients if c.get("pid", 0) > 0]
        current_keys = set()

        for c in valid_clients:
            pid = c["pid"]
            address = c.get("address", "")
            key = (pid, address)
            current_keys.add(key)

            title = c.get("title", "") or c.get("initialTitle", "") or "Unnamed Window"
            app_class = c.get("class", "") or c.get("initialClass", "") or "Application"
            ws = c.get("workspace", {}).get("name", "")

            # Memory
            rss_mb = read_proc_rss_mb(pid)
            mem_str = f"{rss_mb:.0f} MB" if rss_mb >= 1.0 else f"{rss_mb * 1024:.0f} KB"

            # Row data
            row_data = {
                "is_app": True,
                "pid": pid,
                "address": address,
                "title": title,
                "class": app_class,
                "workspace": ws,
                "mem_str": mem_str,
            }

            if key in self.app_rows:
                # Update existing row
                row = self.app_rows[key]
                row._data = row_data
                row._mem_lbl.set_label(mem_str)
                row._sub_lbl.set_label(f"{title} • Ws {ws} • PID {pid}")
            else:
                # Create row
                row = self.create_app_row(row_data)
                self.app_rows[key] = row
                self.app_list_box.append(row)

        # Remove dead rows
        dead_keys = [k for k in self.app_rows.keys() if k not in current_keys]
        for k in dead_keys:
            row = self.app_rows.pop(k)
            self.app_list_box.remove(row)

        # Update badge
        self.apps_page.set_badge_number(len(valid_clients))

    def create_app_row(self, data):
        row = Gtk.ListBoxRow()
        row._data = data

        hbox = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        hbox.set_margin_start(12)
        hbox.set_margin_end(12)
        hbox.set_margin_top(8)
        hbox.set_margin_bottom(8)

        # Icon
        icon_name = resolve_icon_name(data["class"])
        img = Gtk.Image.new_from_icon_name(icon_name)
        img.set_pixel_size(32)
        hbox.append(img)

        # Titles
        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        vbox.set_hexpand(True)

        name_lbl = Gtk.Label(label=data["class"])
        name_lbl.set_halign(Gtk.Align.START)
        name_lbl.add_css_class("heading")

        sub_lbl = Gtk.Label(label=f"{data['title']} • Ws {data['workspace']} • PID {data['pid']}")
        sub_lbl.set_halign(Gtk.Align.START)
        sub_lbl.add_css_class("card-sub")
        sub_lbl.set_ellipsize(3) # END ellipsize

        vbox.append(name_lbl)
        vbox.append(sub_lbl)
        hbox.append(vbox)

        row._sub_lbl = sub_lbl

        # Memory Pill
        mem_lbl = Gtk.Label(label=data["mem_str"])
        mem_lbl.add_css_class("stat-pill")
        row._mem_lbl = mem_lbl
        hbox.append(mem_lbl)

        # Quick Force Kill Button
        kill_btn = Gtk.Button.new_from_icon_name("window-close-symbolic")
        kill_btn.set_tooltip_text("Force Quit & Kill All Workers")
        kill_btn.add_css_class("kill-quick-btn")
        kill_btn.connect("clicked", lambda b: self.kill_action(data))
        hbox.append(kill_btn)

        row.set_child(hbox)

        # Right-click gesture for context menu
        gesture = Gtk.GestureClick.new()
        gesture.set_button(3)
        gesture.connect("pressed", lambda g, n, x, y: self.show_context_menu(row, x, y))
        row.add_controller(gesture)

        return row

    def update_background_processes(self):
        # Scan /proc for non-window processes
        app_pids = {k[0] for k in self.app_rows.keys()}
        procs = []

        try:
            for entry in os.listdir("/proc"):
                if not entry.isdigit():
                    continue
                pid = int(entry)
                if pid in app_pids or pid <= 1:
                    continue

                try:
                    # Filter out kernel threads (no cmdline)
                    with open(f"/proc/{pid}/cmdline", "rb") as f:
                        raw_cmd = f.read()
                        if not raw_cmd:
                            continue
                        cmdline = raw_cmd.replace(b"\x00", b" ").decode("utf-8", "replace").strip()

                    with open(f"/proc/{pid}/comm", "r") as f:
                        comm = f.readline().strip()

                    rss_mb = read_proc_rss_mb(pid)
                    procs.append({
                        "pid": pid,
                        "comm": comm,
                        "cmdline": cmdline,
                        "rss_mb": rss_mb
                    })
                except Exception:
                    continue
        except Exception:
            pass

        # Sort by memory usage descending (keep top 80 to remain snappy)
        procs.sort(key=lambda p: p["rss_mb"], reverse=True)
        top_procs = procs[:80]
        current_pids = {p["pid"] for p in top_procs}

        for p in top_procs:
            pid = p["pid"]
            rss_mb = p["rss_mb"]
            mem_str = f"{rss_mb:.0f} MB" if rss_mb >= 1.0 else f"{rss_mb * 1024:.0f} KB"

            row_data = {
                "is_app": False,
                "pid": pid,
                "comm": p["comm"],
                "cmdline": p["cmdline"],
                "mem_str": mem_str,
            }

            if pid in self.proc_rows:
                row = self.proc_rows[pid]
                row._data = row_data
                row._mem_lbl.set_label(mem_str)
            else:
                row = self.create_proc_row(row_data)
                self.proc_rows[pid] = row
                self.proc_list_box.append(row)

        # Remove dead rows
        dead_pids = [pid for pid in self.proc_rows.keys() if pid not in current_pids]
        for pid in dead_pids:
            row = self.proc_rows.pop(pid)
            self.proc_list_box.remove(row)

        self.procs_page.set_badge_number(len(procs))

    def create_proc_row(self, data):
        row = Gtk.ListBoxRow()
        row._data = data

        hbox = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        hbox.set_margin_start(12)
        hbox.set_margin_end(12)
        hbox.set_margin_top(6)
        hbox.set_margin_bottom(6)

        img = Gtk.Image.new_from_icon_name("system-run-symbolic")
        img.set_pixel_size(24)
        hbox.append(img)

        vbox = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        vbox.set_hexpand(True)

        comm_lbl = Gtk.Label(label=data["comm"])
        comm_lbl.set_halign(Gtk.Align.START)
        comm_lbl.add_css_class("heading")

        cmd_sub = data["cmdline"][:100] + ("..." if len(data["cmdline"]) > 100 else "")
        sub_lbl = Gtk.Label(label=f"PID {data['pid']} • {cmd_sub}")
        sub_lbl.set_halign(Gtk.Align.START)
        sub_lbl.add_css_class("card-sub")
        sub_lbl.set_ellipsize(3)

        vbox.append(comm_lbl)
        vbox.append(sub_lbl)
        hbox.append(vbox)

        # Memory Pill
        mem_lbl = Gtk.Label(label=data["mem_str"])
        mem_lbl.add_css_class("stat-pill")
        row._mem_lbl = mem_lbl
        hbox.append(mem_lbl)

        # Quick Force Kill Button
        kill_btn = Gtk.Button.new_from_icon_name("process-stop-symbolic")
        kill_btn.set_tooltip_text("Force Terminate Tree")
        kill_btn.add_css_class("kill-quick-btn")
        kill_btn.connect("clicked", lambda b: self.kill_action(data))
        hbox.append(kill_btn)

        row.set_child(hbox)

        # Right-click gesture
        gesture = Gtk.GestureClick.new()
        gesture.set_button(3)
        gesture.connect("pressed", lambda g, n, x, y: self.show_context_menu(row, x, y))
        row.add_controller(gesture)

        return row

    def show_context_menu(self, row, x, y):
        data = getattr(row, "_data", None)
        if not data:
            return

        # Clear popover items
        child = self.popover_box.get_first_child()
        while child:
            next_child = child.get_next_sibling()
            self.popover_box.remove(child)
            child = next_child

        # Header Title
        title_text = data.get("class") or data.get("comm") or "Process"
        header_lbl = Gtk.Label(label=f"{title_text} (PID {data['pid']})")
        header_lbl.add_css_class("popover-header")
        self.popover_box.append(header_lbl)

        self.popover_box.append(Gtk.Separator())

        # 1. Focus Window (if app)
        if data.get("is_app") and data.get("address"):
            btn_focus = Gtk.Button(label="🗔  Focus / Bring to Front")
            btn_focus.add_css_class("popover-item")
            btn_focus.connect("clicked", lambda b: self.focus_window_action(data["address"]))
            self.popover_box.append(btn_focus)

        # 2. Open Working Dir in Nautilus
        btn_nautilus = Gtk.Button(label="📁  Open Working Directory in Nautilus")
        btn_nautilus.add_css_class("popover-item")
        btn_nautilus.connect("clicked", lambda b: self.open_in_nautilus_action(data["pid"]))
        self.popover_box.append(btn_nautilus)

        # 3. Copy PID & Command
        btn_copy = Gtk.Button(label="📋  Copy PID & Command")
        btn_copy.add_css_class("popover-item")
        btn_copy.connect("clicked", lambda b: self.copy_cmd_action(data))
        self.popover_box.append(btn_copy)

        self.popover_box.append(Gtk.Separator())

        # 4. Pause / Resume
        btn_pause = Gtk.Button(label="⏸️  Pause Process (SIGSTOP)")
        btn_pause.add_css_class("popover-item")
        btn_pause.connect("clicked", lambda b: self.signal_action(data["pid"], signal.SIGSTOP, "Paused"))
        self.popover_box.append(btn_pause)

        btn_resume = Gtk.Button(label="▶️  Resume Process (SIGCONT)")
        btn_resume.add_css_class("popover-item")
        btn_resume.connect("clicked", lambda b: self.signal_action(data["pid"], signal.SIGCONT, "Resumed"))
        self.popover_box.append(btn_resume)

        self.popover_box.append(Gtk.Separator())

        # 5. Graceful Close (if window)
        if data.get("is_app") and data.get("address"):
            btn_close = Gtk.Button(label="❌  Close Window Gracefully")
            btn_close.add_css_class("popover-item")
            btn_close.connect("clicked", lambda b: self.close_window_action(data["address"]))
            self.popover_box.append(btn_close)

        # 6. Force Quit & Kill All Workers (Destructive Tree Kill)
        btn_kill = Gtk.Button(label="💥  Force Quit & Kill All Background Workers")
        btn_kill.add_css_class("destructive-action")
        btn_kill.add_css_class("popover-item")
        btn_kill.connect("clicked", lambda b: self.kill_action(data))
        self.popover_box.append(btn_kill)

        # Position and show
        rect = Gdk.Rectangle()
        rect.x = int(x)
        rect.y = int(y)
        rect.width = 1
        rect.height = 1
        self.popover.set_pointing_to(rect)
        self.popover.popup()

    def focus_window_action(self, address):
        self.popover.popdown()
        try:
            subprocess.run(["hyprctl", "dispatch", "focuswindow", f"address:{address}"], check=False)
        except Exception:
            pass

    def close_window_action(self, address):
        self.popover.popdown()
        try:
            subprocess.run(["hyprctl", "dispatch", "closewindow", f"address:{address}"], check=False)
            self.toast_overlay.add_toast(Adw.Toast(title="Sent close request to window"))
            GLib.timeout_add(300, self.refresh_all)
        except Exception:
            pass

    def open_in_nautilus_action(self, pid):
        self.popover.popdown()
        try:
            cwd_path = os.path.realpath(f"/proc/{pid}/cwd")
            if os.path.exists(cwd_path):
                subprocess.Popen(["nautilus", cwd_path])
                self.toast_overlay.add_toast(Adw.Toast(title=f"Opened {cwd_path} in Nautilus"))
            else:
                self.toast_overlay.add_toast(Adw.Toast(title="Process working directory not accessible"))
        except Exception as e:
            self.toast_overlay.add_toast(Adw.Toast(title=f"Error launching Nautilus: {e}"))

    def copy_cmd_action(self, data):
        self.popover.popdown()
        text = f"PID {data['pid']}: {data.get('cmdline') or data.get('title') or ''}"
        display = Gdk.Display.get_default()
        if display:
            display.get_clipboard().set(text)
            self.toast_overlay.add_toast(Adw.Toast(title="Copied PID & Command to clipboard"))

    def signal_action(self, pid, sig, label):
        self.popover.popdown()
        try:
            os.kill(pid, sig)
            self.toast_overlay.add_toast(Adw.Toast(title=f"{label} PID {pid}"))
        except Exception as e:
            self.toast_overlay.add_toast(Adw.Toast(title=f"Failed to signal PID {pid}: {e}"))

    def kill_action(self, data):
        self.popover.popdown()
        pid = data["pid"]
        name = data.get("class") or data.get("comm") or f"PID {pid}"
        win_addr = data.get("address")

        killed_count = force_kill_tree(pid, win_addr)
        toast_msg = f"Killed {name} and {killed_count - 1} background workers" if killed_count > 1 else f"Terminated {name}"
        self.toast_overlay.add_toast(Adw.Toast(title=toast_msg))

        # Immediately refresh
        GLib.timeout_add(200, self.refresh_all)

    def on_search_changed(self, entry):
        self.search_filter = entry.get_text().strip().lower()
        self.app_list_box.invalidate_filter()
        self.proc_list_box.invalidate_filter()

    def filter_app_row(self, row):
        if not self.search_filter:
            return True
        data = getattr(row, "_data", None)
        if not data:
            return True
        q = self.search_filter
        return (
            q in data.get("class", "").lower()
            or q in data.get("title", "").lower()
            or q in str(data.get("pid", ""))
        )

    def filter_proc_row(self, row):
        if not self.search_filter:
            return True
        data = getattr(row, "_data", None)
        if not data:
            return True
        q = self.search_filter
        return (
            q in data.get("comm", "").lower()
            or q in data.get("cmdline", "").lower()
            or q in str(data.get("pid", ""))
        )


class CarbonPulseApp(Adw.Application):
    def __init__(self):
        super().__init__(
            application_id="org.carbon.Pulse",
            flags=Gio.ApplicationFlags.FLAGS_NONE
        )

    def do_activate(self):
        win = self.props.active_window
        if not win:
            win = CarbonPulseWindow(self)
        win.present()


def main():
    app = CarbonPulseApp()
    return app.run(sys.argv)

if __name__ == "__main__":
    sys.exit(main())
