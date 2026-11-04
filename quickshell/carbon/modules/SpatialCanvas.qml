import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Mpris
import "../Singletons"
import "../components"

/**
 * CommandCenter:
 * Sleek, modern bottom-up Notch Command Center for Carbon Shell.
 *
 * Sits anchored to the bottom with organic Material Design 3 / Caelestia styling:
 *   - Row 1: Obsidian Notes Tile (Left) + Events / Schedule Tile (Right)
 *   - Row 2: Recent Apps Tile (Compact Dock with icons only, dynamic length) + Clipboard History Tile (Right)
 *
 * Uses Theme.font ("Plus Jakarta Sans") and Theme.fontIcon ("Material Symbols Rounded")
 * to match Carbon Shell perfectly.
 */
PanelWindow {
    id: spatialCanvasWindow

    property bool isOpen: false
    property bool animatingOut: false
    signal closeRequested()
    signal animationFinished()

    property string barEdge: "top"
    property string barMode: "notch"
    readonly property bool isTopBarUp: barEdge !== "bottom"

    WlrLayershell.namespace: "carbon-spatial-canvas"
    WlrLayershell.layer: WlrLayer.Overlay
    aboveWindows: true
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }

    FileView {
        id: barPosWatcher
        path: (Quickshell.env("HOME") || "") + "/.config/carbon/carbon-bar-position.json"
        watchChanges: true
        blockLoading: true
        printErrors: false
        onLoaded: spatialCanvasWindow.updateBarPos(barPosWatcher.text())
        onFileChanged: {
            reload()
            spatialCanvasWindow.updateBarPos(barPosWatcher.text())
        }
    }

    function updateBarPos(txt) {
        if (!txt) return
        try {
            var d = JSON.parse(txt)
            if (d.mainBarEdge) spatialCanvasWindow.barEdge = d.mainBarEdge
            else if (d.edge) spatialCanvasWindow.barEdge = d.edge
        } catch(e) {}
    }

    FileView {
        id: barModeWatcher
        path: (Quickshell.env("HOME") || "") + "/.config/carbon/carbon-bar-mode.json"
        watchChanges: true
        blockLoading: true
        printErrors: false
        onLoaded: spatialCanvasWindow.updateBarMode(barModeWatcher.text())
        onFileChanged: {
            reload()
            spatialCanvasWindow.updateBarMode(barModeWatcher.text())
        }
    }

    function updateBarMode(txt) {
        if (!txt) return
        try {
            var d = JSON.parse(txt)
            if (d.mode) spatialCanvasWindow.barMode = d.mode
            if (d.mainBarEdge) spatialCanvasWindow.barEdge = d.mainBarEdge
        } catch(e) {}
    }

    // Only visible when open or during slide-out animation to completely prevent blocking clicks/scrolls
    visible: isOpen || animatingOut
    WlrLayershell.keyboardFocus: (isOpen && !animatingOut) ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    property real rootOpacity: 0.0

    onIsOpenChanged: {
        if (!isOpen) {
            rootOpacity = 0.0
            animatingOut = true
            closeAnimTimer.restart()
            activeGridX = 0
            activeGridY = 0
            isOverview = true
            viewport.zoomScale = 0.31
        } else {
            animatingOut = false
            closeAnimTimer.stop()
            rootOpacity = 1.0
            viewport.zoomScale = isOverview ? 0.31 : 1.0
            spatialCanvasWindow.refreshWeather()
            spatialCanvasWindow.refreshBrowserFiles()
            spatialCanvasWindow.refreshUpdaterStats()
            spatialCanvasWindow.refreshUptime()
            calSyncProc.running = true
            centerKeyHandler.forceActiveFocus()
            if (radarEngineProc.running) {
                radarEngineProc.write("refresh\n")
            }
            streamAnim.restart()
        }
    }

    Component.onCompleted: {
        refreshBrowserFiles();
        refreshUpdaterStats();
        refreshUptime();
    }

    Timer {
        id: entranceTimer
        interval: 16
        onTriggered: {
            if (spatialCanvasWindow.isOverview) {
                viewport.zoomScale = 0.31
            }
        }
    }

    Timer {
        id: closeAnimTimer
        interval: 260
        onTriggered: {
            spatialCanvasWindow.animatingOut = false
            spatialCanvasWindow.animationFinished()
        }
    }

    // System Clock for aesthetic time display
    SystemClock {
        id: sysClock
        precision: SystemClock.Seconds
    }
    property bool use24h: false

    // Weather state
    property string weatherTemp: "22°C"
    property string weatherDesc: "Clear Sky"
    property string weatherCity: "Patna"

    FileView {
        id: weatherCacheWatcher
        path: "/tmp/carbon-weather-cache.json"
        watchChanges: true
        printErrors: false
        onFileChanged: weatherCacheWatcher.reload()
        onLoaded: {
            try {
                const raw = weatherCacheWatcher.text().trim()
                if (raw) {
                    const d = JSON.parse(raw)
                    if (d.temp) spatialCanvasWindow.weatherTemp = d.temp
                    if (d.description) spatialCanvasWindow.weatherDesc = d.description
                    if (d.city) spatialCanvasWindow.weatherCity = d.city
                }
            } catch (e) {}
        }
    }

    Process {
        id: weatherFetcherProc
        command: [
            "sh", "-c",
            "if [ -f \"$HOME/.local/share/quickshell/carbon/scripts/carbon-weather.py\" ]; then python3 \"$HOME/.local/share/quickshell/carbon/scripts/carbon-weather.py\"; elif [ -f \"$HOME/carbon-shell/hypr/scripts/carbon-weather.py\" ]; then python3 \"$HOME/carbon-shell/hypr/scripts/carbon-weather.py\"; elif [ -f \"$HOME/.config/hypr/scripts/carbon-weather.py\" ]; then python3 \"$HOME/.config/hypr/scripts/carbon-weather.py\"; fi"
        ]
        running: false
        stdout: StdioCollector {
            waitForEnd: true
            onTextChanged: {
                if (text && text.trim().length > 0) {
                    try {
                        var d = JSON.parse(text.trim())
                        if (d) {
                            if (d.temp) spatialCanvasWindow.weatherTemp = d.temp
                            if (d.condition) spatialCanvasWindow.weatherDesc = d.condition
                            else if (d.description) spatialCanvasWindow.weatherDesc = d.description
                            if (d.city) {
                                var c = d.city.split(",")[0].trim()
                                spatialCanvasWindow.weatherCity = c
                            }
                        }
                    } catch (e) {}
                }
            }
        }
    }

    function refreshWeather() {
        if (!weatherFetcherProc.running) {
            weatherFetcherProc.running = true
        }
        weatherCacheWatcher.reload()
    }

    function resolveWeatherIcon(desc) {
        if (!desc) return "wb_sunny"
        var d = desc.toLowerCase()
        if (d.indexOf("rain") !== -1 || d.indexOf("drizzle") !== -1) return "rainy"
        if (d.indexOf("thunder") !== -1 || d.indexOf("storm") !== -1) return "thunderstorm"
        if (d.indexOf("snow") !== -1 || d.indexOf("ice") !== -1) return "ac_unit"
        if (d.indexOf("fog") !== -1 || d.indexOf("haze") !== -1 || d.indexOf("mist") !== -1 || d.indexOf("smoke") !== -1) return "foggy"
        if (d.indexOf("partly") !== -1 || d.indexOf("scattered") !== -1) return "partly_cloudy_day"
        if (d.indexOf("cloud") !== -1 || d.indexOf("overcast") !== -1) return "cloud"
        if (d.indexOf("clear") !== -1 || d.indexOf("sun") !== -1) return "wb_sunny"
        return "wb_sunny"
    }

    // Data models populated by carbon-radar-engine
    property string currentChannel: "overview" // "overview" | "github" | "telemetry"
    property var vaultItems: []
    property var clipboardItems: []
    property var appsItems: []
    property var agendaItems: []
    property var githubPayload: ({
        authenticated: false,
        username: "",
        total_contributions: 0,
        contributions: [],
        pull_requests: [],
        repositories: [],
        workspace: {
            repo_name: "",
            branch: "",
            dirty: false,
            ahead: 0,
            behind: 0,
            last_commit: "",
            sync_status: ""
        },
        feedback: ""
    })
    property var telemetryPayload: ({
        cpu_usage: 0.0,
        cpu_cores: [],
        cpu_temp: 0.0,
        ram_used_bytes: 0,
        ram_total_bytes: 0,
        swap_used_bytes: 0,
        swap_total_bytes: 0,
        net_rx_bps: 0,
        net_tx_bps: 0,
        kernel_version: "Linux",
        uptime_seconds: 0,
        uptime_formatted: "--"
    })

    property string telemetrySubMode: "cpu" // "cpu" | "ram"
    property var cpuHistory: [14, 16, 15, 20, 18, 14, 15, 22, 19, 14, 16, 25, 20, 16, 14, 18, 15, 22, 19, 14, 15, 17, 14, 15, 16, 18, 15, 16]
    property var ramHistory: [74, 74, 75, 75, 76, 76, 76, 77, 77, 77, 78, 78, 78, 77, 78, 78, 78, 78, 78, 78, 78, 78, 78, 78, 78, 78, 78, 78]

    property real streamPhase: 0.0
    property real lastTelemetryTickTime: 0
    property real telemetryTickInterval: 2000

    NumberAnimation {
        id: streamAnim
        target: spatialCanvasWindow
        property: "streamPhase"
        from: 0.0
        to: 1.0
        duration: spatialCanvasWindow.telemetryTickInterval
        easing.type: Easing.Linear
        running: spatialCanvasWindow.isOpen && spatialCanvasWindow.currentChannel === "telemetry"
    }


    function nextChannel() {
        if (currentChannel === "overview") {
            currentChannel = "github"
            githubUplinkView.contentY = 0
        } else if (currentChannel === "github") {
            currentChannel = "telemetry"
        } else {
            currentChannel = "overview"
        }
    }

    function prevChannel() {
        if (currentChannel === "telemetry") {
            currentChannel = "github"
            githubUplinkView.contentY = 0
        } else if (currentChannel === "github") {
            currentChannel = "overview"
        } else {
            currentChannel = "telemetry"
        }
    }

    function toggleTelemetrySubMode() {
        telemetrySubMode = (telemetrySubMode === "cpu" ? "ram" : "cpu")
    }

    property real lastTelemetryScrollTime: 0
    function handleTelemetryScroll(delta) {
        var now = Date.now()
        if (now - lastTelemetryScrollTime < 220) return
        lastTelemetryScrollTime = now
        toggleTelemetrySubMode()
    }

    function pushTelemetryHistory(cpu, ram) {
        var now = Date.now()
        if (lastTelemetryTickTime > 0) {
            var diff = now - lastTelemetryTickTime
            if (diff >= 500 && diff <= 5000) {
                telemetryTickInterval = diff
            }
        }
        lastTelemetryTickTime = now

        var newCpu = cpuHistory.slice()
        newCpu.push(cpu)
        while (newCpu.length > 28) newCpu.shift()
        cpuHistory = newCpu

        var newRam = ramHistory.slice()
        newRam.push(ram)
        while (newRam.length > 28) newRam.shift()
        ramHistory = newRam

        streamPhase = 0.0
        if (spatialCanvasWindow.isOpen && spatialCanvasWindow.currentChannel === "telemetry") {
            streamAnim.stop()
            streamAnim.duration = telemetryTickInterval
            streamAnim.start()
        }
    }

    function formatBytesSpeed(bytes) {
        if (!bytes || bytes <= 0) return "0.0 B/s"
        if (bytes >= 1073741824) return (bytes / 1073741824).toFixed(1) + " GB/s"
        if (bytes >= 1048576) return (bytes / 1048576).toFixed(1) + " MB/s"
        if (bytes >= 1024) return (bytes / 1024).toFixed(1) + " KB/s"
        return bytes + " B/s"
    }
    readonly property var filteredAgenda: {
        if (!agendaItems || !Array.isArray(agendaItems)) return []
        var now = new Date()
        var today = Qt.formatDate(now, "yyyy-MM-dd")
        var curYearMonth = Qt.formatDate(now, "yyyy-MM")
        var curMonthName = Qt.formatDate(now, "MMM")
        return agendaItems.filter(function(item) {
            if (!item) return false
            if (item.raw_date) {
                return item.raw_date >= today && item.raw_date.indexOf(curYearMonth) === 0
            }
            if (item.date) {
                return item.date.indexOf(curMonthName) === 0
            }
            return false
        })
    }
    function getFilteredAgenda() {
        return filteredAgenda
    }

    property bool engineConnected: false
    property string feedbackMessage: ""

    onCurrentChannelChanged: {
        if (currentChannel === "github") {
            githubUplinkView.contentY = 0
            if (repoInput) repoInput.forceActiveFocus()
        } else if (currentChannel === "telemetry" && isOpen) {
            streamAnim.restart()
        }
    }

    Timer {
        id: feedbackClearTimer
        interval: 2000
        onTriggered: spatialCanvasWindow.feedbackMessage = ""
    }

    function scrollGithubBottom() {
        githubUplinkView.contentY = Math.max(0, githubUplinkView.contentHeight - githubUplinkView.height)
    }

    function scrollGithubTop() {
        githubUplinkView.contentY = 0
    }

    function showFeedback(msg) {
        if (!msg || msg.indexOf("Opening URL") !== -1) return
        spatialCanvasWindow.feedbackMessage = msg
        feedbackClearTimer.restart()
    }

    // ── Engine Subprocess Pipe ──
    Process {
        id: radarEngineProc
        command: [
            "sh", "-c",
            "if command -v carbon-radar-engine >/dev/null 2>&1; then exec carbon-radar-engine; elif [ -x \"$HOME/.local/bin/carbon-radar-engine\" ]; then exec \"$HOME/.local/bin/carbon-radar-engine\"; elif [ -x \"$HOME/carbon-shell/apps/carbon-radar/target/release/carbon-radar-engine\" ]; then exec \"$HOME/carbon-shell/apps/carbon-radar/target/release/carbon-radar-engine\"; else exec carbon-radar-engine; fi"
        ]
        running: true
        stdinEnabled: true

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) {
                var raw = (line || "").trim()
                if (!raw) return
                try {
                    var payload = JSON.parse(raw)
                    if (!payload) return
                    if (payload.workspaces !== undefined) spatialCanvasWindow.workspacesData = payload.workspaces
                    if (payload.active_workspace_id !== undefined) spatialCanvasWindow.activeWorkspaceId = payload.active_workspace_id
                    if (payload.vault !== undefined) spatialCanvasWindow.vaultItems = payload.vault
                    if (payload.clipboard !== undefined) spatialCanvasWindow.clipboardItems = payload.clipboard
                    if (payload.apps !== undefined) spatialCanvasWindow.appsItems = payload.apps
                    if (payload.agenda !== undefined) spatialCanvasWindow.agendaItems = payload.agenda
                    if (payload.github !== undefined) {
                        spatialCanvasWindow.githubPayload = payload.github
                        if (payload.github.feedback) {
                            spatialCanvasWindow.showFeedback(payload.github.feedback)
                        }
                    }
                    if (payload.telemetry !== undefined) {
                        spatialCanvasWindow.telemetryPayload = payload.telemetry
                        var cpu = payload.telemetry.cpu_usage || 0
                        var ram = (payload.telemetry.ram_total_bytes > 0) 
                            ? ((payload.telemetry.ram_used_bytes / payload.telemetry.ram_total_bytes) * 100) 
                            : 0
                        spatialCanvasWindow.pushTelemetryHistory(cpu, ram)
                    }
                    spatialCanvasWindow.engineConnected = true
                } catch(e) {}
            }
        }
    }

    // ── Live Calendar Agenda Synchronization ──
    FileView {
        id: agendaFileWatcher
        path: Quickshell.env("HOME") + "/.config/carbon/agenda.json"
        watchChanges: true
        blockLoading: false
        printErrors: false
        onFileChanged: {
            reload()
            try {
                var parsed = JSON.parse(text())
                if (Array.isArray(parsed) && parsed.length > 0) {
                    spatialCanvasWindow.agendaItems = parsed
                }
            } catch(e) {}
        }
        onLoaded: {
            try {
                var parsed = JSON.parse(text())
                if (Array.isArray(parsed) && parsed.length > 0) {
                    spatialCanvasWindow.agendaItems = parsed
                }
            } catch(e) {}
        }
    }

    Process {
        id: calSyncProc
        command: [
            "sh", "-c",
            "if [ -f \"$HOME/.config/hypr/scripts/carbon-calendar.py\" ]; then python3 \"$HOME/.config/hypr/scripts/carbon-calendar.py\" --agenda; elif [ -f \"$HOME/carbon-shell/hypr/scripts/carbon-calendar.py\" ]; then python3 \"$HOME/carbon-shell/hypr/scripts/carbon-calendar.py\" --agenda; fi"
        ]
        running: false
    }


    // Shell runner process for one-off actions
    Process {
        id: actionRunner
    }

    function execCommand(cmd) {
        actionRunner.command = ["sh", "-c", cmd]
        actionRunner.running = true
    }

    function openUrl(url) {
        if (!url) return
        spatialCanvasWindow.feedbackMessage = ""
        if (radarEngineProc.running) {
            radarEngineProc.write("OPEN_URL " + url + "\n")
        } else {
            execCommand("xdg-open " + JSON.stringify(url) + " 2>/dev/null || true")
        }
    }

    function pushLocalWorkspace() {
        if (radarEngineProc.running) {
            radarEngineProc.write("PUSH_LOCAL\n")
        } else {
            var ws = (spatialCanvasWindow.githubPayload && spatialCanvasWindow.githubPayload.workspace && spatialCanvasWindow.githubPayload.workspace.repo_name) ? (Theme.home + "/" + spatialCanvasWindow.githubPayload.workspace.repo_name) : (Theme.home + "/carbon-shell")
            execCommand("git -C \"" + ws + "\" push 2>/dev/null || true")
        }
        showFeedback("Syncing local workspace...")
    }

    function mergePullRequest(repo, prNumber) {
        if (!repo || !prNumber) return
        if (radarEngineProc.running) {
            radarEngineProc.write("MERGE_PR " + repo + " " + prNumber + "\n")
        }
        if (spatialCanvasWindow.githubPayload && spatialCanvasWindow.githubPayload.pull_requests) {
            var updatedPrs = []
            for (var i = 0; i < spatialCanvasWindow.githubPayload.pull_requests.length; i++) {
                var p = spatialCanvasWindow.githubPayload.pull_requests[i]
                if (p.number !== prNumber) updatedPrs.push(p)
            }
            spatialCanvasWindow.githubPayload.pull_requests = updatedPrs
        }
        showFeedback("Merging PR #" + prNumber + "...")
    }

    function searchRepositories(query) {
        if (radarEngineProc.running) {
            radarEngineProc.write("SEARCH_REPOS " + (query || "") + "\n")
        }
    }

    function openNote(notePath) {
        if (!notePath) return
        execCommand("xdg-open " + JSON.stringify(notePath) + " 2>/dev/null || true")
        showFeedback("Opening note")
    }

    function copyClipboard(clipId) {
        if (!clipId) return
        execCommand("echo -n " + JSON.stringify(clipId) + " | cliphist decode | wl-copy 2>/dev/null || true")
        showFeedback("Copied to clipboard")
    }

    function focusApp(appClass) {
        if (!appClass) return
        var c = appClass.replace(/"/g, '\\"')
        var cmd = 'if hyprctl dispatch focuswindow "class:' + c + '" 2>/dev/null; then exit 0; fi; ' +
                  'res=$(hyprctl repl \'for _, w in ipairs(hl.get_windows()) do if string.find(string.lower(w.class), string.lower("' + c + '"), 1, true) then hl.dispatch(hl.dsp.focus{ window = w }) return "ok" end end; return "not_found"\' 2>/dev/null); ' +
                  'if [ "$res" != "ok" ]; then gtk-launch ' + c + ' 2>/dev/null || hyprctl dispatch exec ' + c + ' 2>/dev/null || true; fi'
        execCommand(cmd)
        showFeedback("Focused: " + appClass)
    }

    function triggerManualRefresh() {
        if (radarEngineProc.running) {
            radarEngineProc.write("refresh\n")
        }
        spatialCanvasWindow.refreshWeather()
    }


    
    // ══════════════════════════════════════════════════════════════════
    // OS SUITE HELPER DATA SOURCES & PROCESSES
    // ══════════════════════════════════════════════════════════════════

    // ── 1. Live Hyprland Clients (Workspace Hub) ──
    property var liveClients: []
    property string appFilterQuery: ""

    Process {
        id: clientsFetcherProc
        command: ["sh", "-c", "hyprctl clients -j"]
        running: false
        stdout: StdioCollector {
            waitForEnd: true
            onTextChanged: {
                if (text && text.trim().length > 0) {
                    try {
                        var parsed = JSON.parse(text.trim());
                        if (Array.isArray(parsed)) {
                            spatialCanvasWindow.liveClients = parsed.filter(function(c) {
                                return c.mapped && !c.hidden && c.workspace && c.workspace.id > 0 && c.class && c.class.length > 0;
                            });
                        }
                    } catch(e) {}
                }
            }
        }
    }

    function refreshClients() {
        if (!clientsFetcherProc.running) clientsFetcherProc.running = true;
    }

    readonly property var allOpenWindows: {
        if (liveClients && liveClients.length > 0) return liveClients;
        var res = [];
        var raw = workspacesData || [];
        for (var i = 0; i < raw.length; i++) {
            var ws = raw[i];
            if (ws && ws.windows && Array.isArray(ws.windows)) {
                for (var j = 0; j < ws.windows.length; j++) {
                    var w = ws.windows[j];
                    res.push({
                        address: w.address,
                        class: w.class,
                        title: w.title,
                        workspace: { id: ws.id, name: ws.name || String(ws.id) },
                        is_focused: w.is_focused === true,
                        at: w.at,
                        size: w.size
                    });
                }
            }
        }
        return res;
    }

    readonly property var filteredWindows: {
        var list = allOpenWindows;
        var q = (appFilterQuery || "").trim().toLowerCase();
        if (!q) return list;
        return list.filter(function(w) {
            var cls = (w.class || "").toLowerCase();
            var ttl = (w.title || "").toLowerCase();
            var wsName = w.workspace ? String(w.workspace.name || w.workspace.id).toLowerCase() : "";
            return cls.indexOf(q) !== -1 || ttl.indexOf(q) !== -1 || wsName.indexOf(q) !== -1;
        });
    }

    // ── 2. Wallpaper Studio Data ──
    property var wallpaperList: []

    Process {
        id: wallpaperListProc
        command: [
            "python3", "-c",
            "import os, glob, json; " +
            "files = [f for ext in ('*.jpg', '*.png', '*.jpeg') for f in glob.glob(os.path.expanduser('~/Pictures/Wallpapers/' + ext))]; " +
            "print(json.dumps(files[:16]))"
        ]
        running: false
        stdout: StdioCollector {
            waitForEnd: true
            onTextChanged: {
                if (text && text.trim().length > 0) {
                    try {
                        var parsed = JSON.parse(text.trim());
                        if (Array.isArray(parsed)) spatialCanvasWindow.wallpaperList = parsed;
                    } catch(e) {}
                }
            }
        }
    }

    function refreshWallpapers() {
        if (!wallpaperListProc.running) wallpaperListProc.running = true;
    }

    // ── 3. App Launcher (DesktopEntries) ──
    property string appLauncherSearchQuery: ""

    readonly property var allInstalledApps: {
        if (typeof DesktopEntries === "undefined" || !DesktopEntries || !DesktopEntries.applications) return [];
        var values = DesktopEntries.applications.values || [];
        var res = [];
        for (var i = 0; i < values.length; i++) {
            var e = values[i];
            if (e && !e.noDisplay && e.name && e.command) {
                res.push({
                    name: e.name,
                    icon: e.icon || "application-x-executable",
                    comment: e.comment || e.genericName || (Array.isArray(e.categories) ? e.categories.join(", ") : ""),
                    entry: e
                });
            }
        }
        res.sort(function(a, b) { return a.name.localeCompare(b.name); });
        return res;
    }

    readonly property var filteredApps: {
        var list = allInstalledApps;
        var q = (appLauncherSearchQuery || "").trim().toLowerCase();
        if (!q) return list;
        return list.filter(function(a) {
            return a.name.toLowerCase().indexOf(q) !== -1 || (a.comment && a.comment.toLowerCase().indexOf(q) !== -1);
        });
    }

    // ── 4. Quick File Browser ──
    property string currentBrowserPath: (Quickshell.env("HOME") || "/home/shogun")
    property var currentBrowserFiles: []
    property string storageUsageText: "Storage Capacity"
    property real storageUsageFraction: 0.50

    Process {
        id: fileBrowserProc
        command: [
            "python3", "-c",
            "import os, sys, json; " +
            "p = os.path.expanduser(sys.argv[1]); " +
            "entries = []; " +
            "try: " +
            "    for e in os.scandir(p): " +
            "        if not e.name.startswith('.'): " +
            "            entries.append({'name': e.name, 'isDir': e.is_dir(), 'size': e.stat().st_size if not e.is_dir() else 0}); " +
            "except Exception: pass; " +
            "entries.sort(key=lambda x: (not x['isDir'], x['name'].lower())); " +
            "print(json.dumps(entries[:45]))",
            spatialCanvasWindow.currentBrowserPath
        ]
        running: false
        stdout: StdioCollector {
            waitForEnd: true
            onTextChanged: {
                if (text && text.trim().length > 0) {
                    try {
                        var parsed = JSON.parse(text.trim());
                        if (Array.isArray(parsed)) spatialCanvasWindow.currentBrowserFiles = parsed;
                    } catch(e) {}
                }
            }
        }
    }

    Process {
        id: storageCapacityProc
        command: [
            "python3", "-c",
            "import shutil, os; t, u, f = shutil.disk_usage(os.path.expanduser('~')); p = int(u/t*100); print(f'{u//(1024**3)}G / {t//(1024**3)}G ({p}%)|{p}%')"
        ]
        running: false
        stdout: StdioCollector {
            waitForEnd: true
            onTextChanged: {
                if (text && text.trim().length > 0) {
                    var parts = text.trim().split("|");
                    if (parts.length > 0) spatialCanvasWindow.storageUsageText = parts[0];
                    if (parts.length > 1) {
                        var pct = parseInt(parts[1]) || 50;
                        spatialCanvasWindow.storageUsageFraction = Math.max(0.0, Math.min(1.0, pct / 100.0));
                    }
                }
            }
        }
    }

    function refreshBrowserFiles() {
        if (!fileBrowserProc.running) fileBrowserProc.running = true;
        if (!storageCapacityProc.running) storageCapacityProc.running = true;
    }

    onCurrentBrowserPathChanged: refreshBrowserFiles()

    // ── 5. Arch System & Package Updater Data ──
    property var updaterStats: ({
        updates: [],
        total: "1222",
        disk_size: "109G",
        disk_used: "81G",
        disk_avail: "23G",
        disk_percent: "74%"
    })

    Process {
        id: updaterStatsProc
        command: [
            "python3", "-c",
            "import subprocess, json, shutil; " +
            "up = subprocess.run(['checkupdates'], capture_output=True, text=True).stdout.strip().splitlines() if shutil.which('checkupdates') else []; " +
            "total = subprocess.run(['sh', '-c', 'pacman -Q 2>/dev/null | wc -l'], capture_output=True, text=True).stdout.strip(); " +
            "df = subprocess.run(['df', '-h', '/'], capture_output=True, text=True).stdout.strip().splitlines(); " +
            "root_df = df[1].split() if len(df) > 1 else []; " +
            "print(json.dumps({'updates': up, 'total': total, 'disk_size': root_df[1] if len(root_df)>1 else '', 'disk_used': root_df[2] if len(root_df)>2 else '', 'disk_avail': root_df[3] if len(root_df)>3 else '', 'disk_percent': root_df[4] if len(root_df)>4 else ''}))"
        ]
        running: false
        stdout: StdioCollector {
            waitForEnd: true
            onTextChanged: {
                if (text && text.trim().length > 0) {
                    try {
                        var parsed = JSON.parse(text.trim());
                        if (parsed) spatialCanvasWindow.updaterStats = parsed;
                    } catch(e) {}
                }
            }
        }
    }

    function refreshUpdaterStats() {
        if (!updaterStatsProc.running) updaterStatsProc.running = true;
    }

    // ── 6. Weather Forecast Cache Parser ──
    property var weatherForecastList: []
    property string weatherWind: "7 km/h"
    property string weatherHumidity: "85%"
    property string weatherFeelsLike: "23°C"

    FileView {
        id: weatherFullCacheWatcher
        path: "/tmp/carbon-weather-cache.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                var raw = weatherFullCacheWatcher.text().trim();
                if (raw) {
                    var d = JSON.parse(raw);
                    if (d.temp) spatialCanvasWindow.weatherTemp = d.temp;
                    if (d.description) spatialCanvasWindow.weatherDesc = d.description;
                    if (d.city) spatialCanvasWindow.weatherCity = d.city;
                    if (d.wind) spatialCanvasWindow.weatherWind = d.wind;
                    if (d.humidity) spatialCanvasWindow.weatherHumidity = d.humidity;
                    if (d.feels_like) spatialCanvasWindow.weatherFeelsLike = d.feels_like;
                    if (d.forecast && Array.isArray(d.forecast)) spatialCanvasWindow.weatherForecastList = d.forecast;
                }
            } catch(e) {}
        }
    }

    // ── 7. System Uptime ──
    property string systemUptime: "Up 2h 45m"

    Process {
        id: uptimeProc
        command: ["uptime", "-p"]
        running: false
        stdout: StdioCollector {
            waitForEnd: true
            onTextChanged: {
                if (text && text.trim().length > 0) {
                    spatialCanvasWindow.systemUptime = text.trim();
                }
            }
        }
    }

    function refreshUptime() {
        if (!uptimeProc.running) uptimeProc.running = true;
    }

    // ── 8. Media / Volume Controls ──
    readonly property var activeMprisPlayer: {
        var list = (typeof Mpris !== "undefined" && Mpris && Mpris.players && Mpris.players.values !== undefined) ? Mpris.players.values : [];
        for (var i = 0; i < list.length; i++) {
            if (list[i] && list[i].playbackState === MprisPlaybackState.Playing) return list[i];
        }
        return list.length > 0 ? list[0] : null;
    }
    property real masterOutputVolume: 0.75
    property bool masterOutputMuted: false

    Process {
        id: masterVolumeWatcherProc
        command: ["bash", "-c", "wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null || echo 'Volume: 0.75'"]
        running: false
        stdout: StdioCollector {
            waitForEnd: true
            onTextChanged: {
                if (text && text.trim().length > 0) {
                    var t = text.trim();
                    spatialCanvasWindow.masterOutputMuted = t.indexOf("[MUTED]") !== -1;
                    var match = t.match(/([0-9]+(\.[0-9]+)?)/);
                    if (match) {
                        var val = parseFloat(match[1]);
                        spatialCanvasWindow.masterOutputVolume = Math.max(0.0, Math.min(1.0, val));
                    }
                }
            }
        }
    }

    function refreshVolume() {
        if (!masterVolumeWatcherProc.running) masterVolumeWatcherProc.running = true;
    }

    Timer {
        id: themeReloadTimer
        interval: 800
        onTriggered: Theme.reload(true)
    }

    function triggerThemeReload() {
        themeReloadTimer.restart()
    }

    // ── 2D Spatial Zoom State ──
    property int activeGridX: 0
    property int activeGridY: 0
    property bool isOverview: true

    property var workspacesData: []
    property int activeWorkspaceId: 1

    function getNodeTitle(gx, gy) {
        if (gx === 0 && gy === 0) return "WORKSPACE BLUEPRINT";
        if (gx === -1 && gy === 0) return "LOCAL RADAR";
        if (gx === 0 && gy === -1) return "GITHUB UPLINK";
        if (gx === 0 && gy === 1) return "SYSTEM TELEMETRY";
        if (gx === 1 && gy === 0) return "CARBON ENGINE";
        return "NODE [" + gx + ", " + gy + "]";
    }

    function getNodeDesc(gx, gy) {
        if (gx === 0 && gy === 0) return "Live 3x3 Workspace Blueprint & Zero-VRAM Wireframe Monitor";
        if (gx === -1 && gy === 0) return "Obsidian Vault, Agenda, Dock & System Clipboard History";
        if (gx === 0 && gy === -1) return "52-Week Contributions, Git Sync & PR Gatekeeper";
        if (gx === 0 && gy === 1) return "Kernel Stream, Hardware CPU/RAM Wave & Network Telemetry";
        if (gx === 1 && gy === 0) return "Shell Mode Switcher, Wallpaper Engine & Visual Tuner";
        return "";
    }

    onIsOverviewChanged: {
        if (!entranceTimer.running) {
            viewport.zoomScale = isOverview ? 0.31 : 1.0;
        }
    }

    function zoomToNode(gx, gy) {
        entranceTimer.stop();
        activeGridX = gx;
        activeGridY = gy;
        isOverview = false;
        viewport.zoomScale = 1.0;
    }

    function zoomToOverview() {
        entranceTimer.stop();
        isOverview = true;
        viewport.zoomScale = 0.31;
    }

    function focusNode(gx, gy) {
        zoomToNode(gx, gy);
    }

    function toggleNodeZoom(gx, gy) {
        if (!isOverview && activeGridX === gx && activeGridY === gy) {
            zoomToOverview();
        } else {
            zoomToNode(gx, gy);
        }
    }

    function switchToWorkspace(wsId) {
        execCommand("hyprctl dispatch workspace " + wsId);
        spatialCanvasWindow.closeRequested();
    }

    function moveGrid(dx, dy) {
        var nx = Math.max(-1, Math.min(1, activeGridX + dx));
        var ny = Math.max(-1, Math.min(1, activeGridY + dy));
        activeGridX = nx;
        activeGridY = ny;
    }

    function isValidNode(gx, gy) {
        return gx >= -1 && gx <= 1 && gy >= -1 && gy <= 1;
    }

    function applyBarMode(mode) {
        execCommand("sh ~/.config/hypr/scripts/carbon-mode-keybinds.sh " + mode);
        spatialCanvasWindow.showFeedback("Switched to " + mode + " mode");
    }

    function getWorkspaces() {
        var res = [];
        var raw = workspacesData || [];
        for (var i = 1; i <= 9; i++) {
            var match = null;
            for (var j = 0; j < raw.length; j++) {
                if (raw[j].id === i) {
                    match = raw[j];
                    break;
                }
            }
            if (match) {
                res.push(match);
            } else {
                res.push({
                    id: i,
                    name: String(i),
                    is_active: (i === activeWorkspaceId),
                    has_windows: false,
                    windows: []
                });
            }
        }
        return res;
    }

    function resolveAppIcon(cls) {
        if (!cls) return ""
        var raw = cls.trim()
        var c = raw.toLowerCase()

        // 1. Obsidian special handling
        if (c.indexOf("obsidian") !== -1) {
            var o = Quickshell.iconPath("obsidian", "") || Quickshell.iconPath("md.obsidian.Obsidian", "")
            if (o) return o
            return "file://" + Theme.home + "/.local/share/icons/hicolor/scalable/apps/obsidian.svg"
        }

        // 2. Direct well-known application mappings
        if (c === "antigravity") {
            return Quickshell.iconPath("antigravity", "")
        }
        if (c === "cz.viceverse.serein" || c === "serein") {
            return Quickshell.iconPath("serein", "")
        }

        // 3. Resolve using DesktopEntries if available
        if (typeof DesktopEntries !== "undefined" && DesktopEntries && DesktopEntries.applications) {
            var apps = DesktopEntries.applications.values || []
            var parts = c.split(".")
            var lastSegment = parts[parts.length - 1]

            // By startupWmClass
            for (var i = 0; i < apps.length; i++) {
                var a = apps[i]
                if (a && a.startupWmClass && a.startupWmClass.toLowerCase() === c) {
                    if (a.icon) {
                        if (a.icon.startsWith("/")) return "file://" + a.icon
                        return Quickshell.iconPath(a.icon.toLowerCase(), "")
                    }
                }
            }

            // By app ID
            for (var i = 0; i < apps.length; i++) {
                var a = apps[i]
                var aid = (a && a.id ? a.id : "").toLowerCase()
                if (aid === c || aid === c + ".desktop" || aid === lastSegment || aid === lastSegment + ".desktop") {
                    if (a.icon) {
                        if (a.icon.startsWith("/")) return "file://" + a.icon
                        return Quickshell.iconPath(a.icon.toLowerCase(), "")
                    }
                }
            }
        }

        // 4. Reverse DNS stripping (e.g. org.mozilla.firefox -> firefox)
        var parts = c.split(".")
        var last = parts[parts.length - 1]
        if (last && last.length > 0 && last !== c) {
            return Quickshell.iconPath(last, "")
        }

        // 5. Default lowercase
        return Quickshell.iconPath(c, "application-x-executable")
    }



    Item {
        id: container
        anchors.fill: parent
        opacity: spatialCanvasWindow.rootOpacity
        Behavior on opacity {
            NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
        }

        // ── Full-surface Keyboard Handler for Instant Navigation ──
        Item {
            id: centerKeyHandler
            anchors.fill: parent
            focus: spatialCanvasWindow.isOpen
            Keys.enabled: spatialCanvasWindow.isOpen
            Keys.priority: Keys.BeforeItem

            Keys.onPressed: (event) => {
                // Direct workspace switch via 1-9
                if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
                    var num = event.key - Qt.Key_0;
                    spatialCanvasWindow.switchToWorkspace(num);
                    event.accepted = true;
                    return;
                }

                if (event.key === Qt.Key_Escape) {
                    if (!spatialCanvasWindow.isOverview) {
                        spatialCanvasWindow.zoomToOverview();
                    } else {
                        spatialCanvasWindow.closeRequested();
                    }
                    event.accepted = true;
                    return;
                }

                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                    if (spatialCanvasWindow.isOverview) {
                        spatialCanvasWindow.zoomToNode(spatialCanvasWindow.activeGridX, spatialCanvasWindow.activeGridY);
                        event.accepted = true;
                        return;
                    }
                }

                if (event.key === Qt.Key_Up || event.key === Qt.Key_W) {
                    spatialCanvasWindow.moveGrid(0, -1);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Down || event.key === Qt.Key_S) {
                    spatialCanvasWindow.moveGrid(0, 1);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Left || event.key === Qt.Key_A) {
                    spatialCanvasWindow.moveGrid(-1, 0);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Right || event.key === Qt.Key_D) {
                    spatialCanvasWindow.moveGrid(1, 0);
                    event.accepted = true;
                }
            }
        }

        // ── Translucent Backdrop Over Live Wallpaper ──
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(6/255, 7/255, 10/255, 0.35)
        }

        // ── 2D Spatial Viewport ──
        Item {
            id: viewport
            anchors.fill: parent
            clip: true

            property alias activeX: spatialCanvasWindow.activeGridX
            property alias activeY: spatialCanvasWindow.activeGridY
            property alias isOverview: spatialCanvasWindow.isOverview
            property real zoomScale: 0.31

            readonly property real stepX: Math.round(width * 0.78)
            readonly property real stepY: Math.round(height * 0.78)
            readonly property real cardWidth: Math.round(width * 0.70)
            readonly property real cardHeight: Math.round(height * 0.70)

            // Background click & wheel controls
            MouseArea {
                anchors.fill: parent
                z: 0
                onClicked: {
                    if (!spatialCanvasWindow.isOverview) {
                        spatialCanvasWindow.zoomToOverview()
                    } else {
                        spatialCanvasWindow.closeRequested()
                    }
                }
                onWheel: (wheel) => {
                    if (wheel.angleDelta.y < 0) {
                        spatialCanvasWindow.zoomToOverview()
                    } else if (wheel.angleDelta.y > 0) {
                        spatialCanvasWindow.zoomToNode(spatialCanvasWindow.activeGridX, spatialCanvasWindow.activeGridY)
                    }
                }
            }

            // ── Outer Zoom Rig (cameraZoomRig) ──
            Item {
                id: cameraZoomRig
                anchors.fill: parent
                z: 1

                transform: Scale {
                    origin.x: cameraZoomRig.width / 2
                    origin.y: cameraZoomRig.height / 2
                    xScale: viewport.zoomScale
                    yScale: viewport.zoomScale
                    Behavior on xScale {
                        NumberAnimation {
                            duration: 550
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: [0.16, 1.0, 0.3, 1.0, 1.0, 1.0]
                        }
                    }
                    Behavior on yScale {
                        NumberAnimation {
                            duration: 550
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: [0.16, 1.0, 0.3, 1.0, 1.0, 1.0]
                        }
                    }
                }

                // ── Inner World Pan (spatialWorld) ──
                Item {
                    id: spatialWorld
                    width: viewport.width
                    height: viewport.height

                    x: spatialCanvasWindow.isOverview ? (-spatialCanvasWindow.activeGridX * viewport.stepX * 0.12) : (-spatialCanvasWindow.activeGridX * viewport.stepX)
                    y: spatialCanvasWindow.isOverview ? (-spatialCanvasWindow.activeGridY * viewport.stepY * 0.12) : (-spatialCanvasWindow.activeGridY * viewport.stepY)

                    Behavior on x {
                        NumberAnimation {
                            duration: 550
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: [0.16, 1.0, 0.3, 1.0, 1.0, 1.0]
                        }
                    }
                    Behavior on y {
                        NumberAnimation {
                            duration: 550
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: [0.16, 1.0, 0.3, 1.0, 1.0, 1.0]
                        }
                    }

                // ══════════════════════════════════════════════════════════
                // NODE (0, 0) :: WORKSPACE BLUEPRINT
                // ══════════════════════════════════════════════════════════
                // ══════════════════════════════════════════════════════════
                // NODE (0, 0) :: WORKSPACE BLUEPRINT
                // ══════════════════════════════════════════════════════════
                Rectangle {
                    id: cardNode0_0
                    readonly property int nodeX: 0
                    readonly property int nodeY: 0
                    readonly property bool isCurrentTarget: (spatialCanvasWindow.activeGridX === cardNode0_0.nodeX && spatialCanvasWindow.activeGridY === cardNode0_0.nodeY)
                    readonly property string cardIcon: "grid_view"
                    readonly property string cardTitle: "Workspace Blueprint"
                    readonly property string cardSubtitle: "3x3 Virtual Desktops & Live Windows"

                    width: viewport.cardWidth
                    height: viewport.cardHeight
                    x: Math.round((viewport.width - width) / 2 + (cardNode0_0.nodeX * viewport.stepX))
                    y: Math.round((viewport.height - height) / 2 + (cardNode0_0.nodeY * viewport.stepY))
                    radius: 22

                    // Matugen-tinted frosted glass surface
                    color: Qt.rgba(Theme.surface.r * 0.8 + Theme.primary.r * 0.2, Theme.surface.g * 0.8 + Theme.primary.g * 0.2, Theme.surface.b * 0.8 + Theme.primary.b * 0.2, 0.78)
                    border.width: cardNode0_0.isCurrentTarget && !viewport.isOverview ? 1.5 : 1
                    border.color: (cardNode0_0Hover.hovered || cardNode0_0.isCurrentTarget) ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.55) : Qt.rgba(1, 1, 1, 0.08)
                    clip: true

                    HoverHandler { id: cardNode0_0Hover }

                    // Top Specular Highlight Line
                    Rectangle {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: Theme.px(22)
                        anchors.rightMargin: Theme.px(22)
                        height: 1
                        color: Qt.rgba(255, 255, 255, 0.18)
                        z: 5
                    }

                    // Inner Soft Top-Left Gradient Overlay
                    Rectangle {
                        anchors.fill: parent
                        radius: 22
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12) }
                            GradientStop { position: 1.0; color: "transparent" }
                        }
                        opacity: 0.85
                        z: 1
                    }

                    // Corner Crosshairs for tech / OS aesthetic
                    Text { text: "+"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(11); font.bold: true; color: cardNode0_0.isCurrentTarget ? Theme.primary : Qt.rgba(Theme.fgDim.r, Theme.fgDim.g, Theme.fgDim.b, 0.35); anchors.left: parent.left; anchors.top: parent.top; anchors.margins: Theme.px(10); z: 10 }
                    Text { text: "+"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(11); font.bold: true; color: cardNode0_0.isCurrentTarget ? Theme.primary : Qt.rgba(Theme.fgDim.r, Theme.fgDim.g, Theme.fgDim.b, 0.35); anchors.right: parent.right; anchors.top: parent.top; anchors.margins: Theme.px(10); z: 10 }
                    Text { text: "+"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(11); font.bold: true; color: cardNode0_0.isCurrentTarget ? Theme.primary : Qt.rgba(Theme.fgDim.r, Theme.fgDim.g, Theme.fgDim.b, 0.35); anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: Theme.px(10); z: 10 }
                    Text { text: "+"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(11); font.bold: true; color: cardNode0_0.isCurrentTarget ? Theme.primary : Qt.rgba(Theme.fgDim.r, Theme.fgDim.g, Theme.fgDim.b, 0.35); anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: Theme.px(10); z: 10 }

                    // Modern Unified Header Bar
                    RowLayout {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.topMargin: Theme.px(14)
                        anchors.leftMargin: Theme.px(22)
                        anchors.rightMargin: Theme.px(22)
                        height: Theme.px(28)
                        spacing: Theme.px(10)
                        z: 10

                        // Glowing Matugen Accent Dot
                        Rectangle {
                            Layout.preferredWidth: Theme.px(8)
                            Layout.preferredHeight: Theme.px(8)
                            radius: Theme.px(4)
                            color: cardNode0_0.isCurrentTarget ? Theme.primary : Qt.rgba(Theme.fgDim.r, Theme.fgDim.g, Theme.fgDim.b, 0.50)

                            Rectangle {
                                anchors.centerIn: parent
                                width: Theme.px(14)
                                height: Theme.px(14)
                                radius: Theme.px(7)
                                color: cardNode0_0.isCurrentTarget ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.25) : "transparent"
                                z: -1
                            }
                        }

                        Text {
                            text: cardNode0_0.cardIcon
                            font.family: Theme.fontIcon
                            font.pixelSize: Theme.fontPx(16)
                            color: cardNode0_0.isCurrentTarget ? Theme.primary : Theme.fgDim
                        }

                        // Bold Title
                        Text {
                            text: cardNode0_0.cardTitle
                            font.family: Theme.font
                            font.pixelSize: Theme.fontPx(13.5)
                            font.weight: Font.Bold
                            color: cardNode0_0.isCurrentTarget ? Theme.fg : Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.75)
                        }

                        // Muted Subtitle Pill
                        Rectangle {
                            Layout.preferredHeight: Theme.px(18)
                            Layout.preferredWidth: cardNode0_0SubText.implicitWidth + Theme.px(12)
                            radius: Theme.px(9)
                            color: Qt.rgba(255, 255, 255, 0.05)
                            border.color: Qt.rgba(255, 255, 255, 0.08)
                            border.width: 1

                            Text {
                                id: cardNode0_0SubText
                                anchors.centerIn: parent
                                text: cardNode0_0.cardSubtitle
                                font.family: Theme.fontMono || "monospace"
                                font.pixelSize: Theme.fontPx(8.5)
                                color: Theme.fgDim
                            }
                        }

                        Item { Layout.fillWidth: true }

                        // Sleek rounded pill button for Overview [ESC]
                        Rectangle {
                            visible: cardNode0_0.isCurrentTarget && !spatialCanvasWindow.isOverview
                            Layout.preferredHeight: Theme.px(22)
                            Layout.preferredWidth: cardNode0_0OverviewBtnText.implicitWidth + Theme.px(16)
                            radius: Theme.px(11)
                            color: cardNode0_0OverviewHover.hovered ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15) : Qt.rgba(255, 255, 255, 0.06)
                            border.color: cardNode0_0OverviewHover.hovered ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.40) : Qt.rgba(255, 255, 255, 0.12)
                            border.width: 1

                            HoverHandler { id: cardNode0_0OverviewHover }
                            Text {
                                id: cardNode0_0OverviewBtnText
                                anchors.centerIn: parent
                                text: "Overview [ESC]"
                                font.family: Theme.fontMono || "monospace"
                                font.pixelSize: Theme.fontPx(9)
                                font.bold: true
                                color: cardNode0_0OverviewHover.hovered ? Theme.primary : Theme.fgDim
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: spatialCanvasWindow.zoomToOverview()
                            }
                        }
                    }

                    // Inner Content Container: Opacity 1.0 AT ALL TIMES!
                    Item {
                        id: cardNode0_0Inner
                        anchors.fill: parent
                        anchors.margins: Theme.px(16)
                        anchors.topMargin: Theme.px(48)
                        clip: true
                        opacity: 1.0
                        z: 2

                        RowLayout {
                            anchors.fill: parent
                            spacing: Theme.px(14)

                            // ─────────────────────────────────────────────────────────────
                            // LEFT SECTION (68% width): 3x3 Workspace Blueprint Grid
                            // ─────────────────────────────────────────────────────────────
                            Item {
                                Layout.fillWidth: true
                                Layout.preferredWidth: Math.round(parent.width * 0.68)
                                Layout.fillHeight: true

                                GridLayout {
                                    anchors.fill: parent
                                    columns: 3
                                    rows: 3
                                    columnSpacing: Theme.px(10)
                                    rowSpacing: Theme.px(10)

                                    Repeater {
                                        model: spatialCanvasWindow.getWorkspaces()

                                        Rectangle {
                                            id: wsCard
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            radius: Theme.px(8)
                                            opacity: (modelData.windows && modelData.windows.length > 0) || modelData.is_active ? 1.0 : 0.35
                                            color: modelData.is_active 
                                                ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12) 
                                                : Qt.rgba(0.06, 0.08, 0.11, 0.85)
                                            border.color: modelData.is_active 
                                                ? Theme.primary 
                                                : (tileHover.hovered ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.50) : Qt.rgba(255, 255, 255, 0.12))
                                            border.width: modelData.is_active ? 1.5 : 1
                                            clip: true

                                            HoverHandler { id: tileHover }

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: spatialCanvasWindow.switchToWorkspace(modelData.id)
                                            }

                                            // Tile Header Row
                                            RowLayout {
                                                anchors.top: parent.top
                                                anchors.left: parent.left
                                                anchors.right: parent.right
                                                anchors.topMargin: Theme.px(6)
                                                anchors.leftMargin: Theme.px(8)
                                                anchors.rightMargin: Theme.px(8)
                                                height: Theme.px(18)
                                                spacing: Theme.px(6)
                                                z: 10

                                                Text {
                                                    text: "WS " + (modelData.id < 10 ? "0" + modelData.id : modelData.id)
                                                    font.family: Theme.fontMono || "monospace"
                                                    font.pixelSize: Theme.fontPx(11)
                                                    font.weight: Font.Bold
                                                    color: modelData.is_active ? Theme.primary : (tileHover.hovered ? Theme.primary : Theme.fg)
                                                }

                                                Rectangle {
                                                    visible: modelData.is_active
                                                    width: Theme.px(6)
                                                    height: Theme.px(6)
                                                    radius: Theme.px(3)
                                                    color: Theme.primary
                                                }

                                                Item { Layout.fillWidth: true }

                                                Text {
                                                    text: (modelData.windows ? modelData.windows.length : 0) + " WIN"
                                                    font.family: Theme.fontMono || "monospace"
                                                    font.pixelSize: Theme.fontPx(9)
                                                    color: modelData.is_active ? Theme.primary : Qt.rgba(Theme.fgDim.r, Theme.fgDim.g, Theme.fgDim.b, 0.6)
                                                }
                                            }

                                            // Blueprint Proportional Wireframe Canvas Area
                                            Item {
                                                anchors.top: parent.top
                                                anchors.topMargin: Theme.px(26)
                                                anchors.bottom: parent.bottom
                                                anchors.bottomMargin: Theme.px(6)
                                                anchors.left: parent.left
                                                anchors.leftMargin: Theme.px(6)
                                                anchors.right: parent.right
                                                anchors.rightMargin: Theme.px(6)
                                                clip: true

                                                Rectangle {
                                                    anchors.fill: parent
                                                    color: "transparent"
                                                    border.color: Qt.rgba(255, 255, 255, 0.05)
                                                    border.width: 1
                                                    radius: Theme.px(4)
                                                }

                                                // Proportional Windows
                                                Repeater {
                                                    model: modelData.windows || []

                                                    Rectangle {
                                                        width: Math.max(Theme.px(20), Math.min(parent.width, Math.round((modelData.size && modelData.size.length > 0 ? modelData.size[0] : 0.25) * parent.width)))
                                                        height: Math.max(Theme.px(14), Math.min(parent.height, Math.round((modelData.size && modelData.size.length > 1 ? modelData.size[1] : 0.25) * parent.height)))
                                                        x: Math.max(0, Math.min(parent.width - width, Math.round((modelData.at && modelData.at.length > 0 ? modelData.at[0] : 0) * parent.width)))
                                                        y: Math.max(0, Math.min(parent.height - height, Math.round((modelData.at && modelData.at.length > 1 ? modelData.at[1] : 0) * parent.height)))
                                                        radius: Theme.px(4)
                                                        color: (modelData.is_focused === true) 
                                                            ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.22) 
                                                            : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.08)
                                                        border.color: (modelData.is_focused === true) 
                                                            ? Theme.primary 
                                                            : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.35)
                                                        border.width: 1
                                                        clip: true

                                                        RowLayout {
                                                            anchors.centerIn: parent
                                                            width: Math.min(implicitWidth, parent.width - Theme.px(4))
                                                            spacing: Theme.px(4)

                                                            Image {
                                                                visible: parent.parent.width > Theme.px(28) && parent.parent.height > Theme.px(18)
                                                                Layout.preferredWidth: Theme.px(12)
                                                                Layout.preferredHeight: Theme.px(12)
                                                                source: spatialCanvasWindow.resolveAppIcon(modelData.class)
                                                                sourceSize: Qt.size(24, 24)
                                                                fillMode: Image.PreserveAspectFit
                                                            }

                                                            Text {
                                                                text: modelData.title || modelData.class || ""
                                                                font.family: Theme.font
                                                                font.pixelSize: Theme.fontPx(8.5)
                                                                font.weight: Font.Medium
                                                                color: (modelData.is_focused === true) ? Theme.primary : Qt.rgba(255, 255, 255, 0.90)
                                                                elide: Text.ElideRight
                                                                Layout.maximumWidth: parent.parent.width - (parent.parent.width > Theme.px(28) ? Theme.px(18) : Theme.px(4))
                                                            }
                                                        }
                                                    }
                                                }

                                                Text {
                                                    anchors.centerIn: parent
                                                    visible: !modelData.windows || modelData.windows.length === 0
                                                    text: "[ ∅ EMPTY BUFFER ]"
                                                    font.family: Theme.fontMono || "monospace"
                                                    font.pixelSize: Theme.fontPx(9.5)
                                                    color: Qt.rgba(255, 255, 255, 0.16)
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // ─────────────────────────────────────────────────────────────
                            // VERTICAL DIVIDER
                            // ─────────────────────────────────────────────────────────────
                            Rectangle {
                                Layout.preferredWidth: 1
                                Layout.fillHeight: true
                                color: Qt.rgba(255, 255, 255, 0.08)
                            }

                            // ─────────────────────────────────────────────────────────────
                            // RIGHT SECTION (32% width): OPENED APPS & WINDOWS LIVE SWITCHER
                            // ─────────────────────────────────────────────────────────────
                            Item {
                                Layout.fillWidth: true
                                Layout.preferredWidth: Math.round(parent.width * 0.32)
                                Layout.fillHeight: true

                                ColumnLayout {
                                    anchors.fill: parent
                                    spacing: Theme.px(8)

                                    // Header Row: Title & Active Windows Count
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Theme.px(8)

                                        Text {
                                            text: "grid_view"
                                            font.family: Theme.fontIcon
                                            font.pixelSize: Theme.fontPx(14)
                                            color: Theme.primary
                                        }

                                        Text {
                                            text: "OPENED APPS & WINDOWS"
                                            font.family: Theme.fontMono || "monospace"
                                            font.pixelSize: Theme.fontPx(11)
                                            font.weight: Font.Bold
                                            color: Theme.fg
                                        }

                                        Item { Layout.fillWidth: true }

                                        Rectangle {
                                            Layout.preferredHeight: Theme.px(18)
                                            Layout.preferredWidth: winCountText.implicitWidth + Theme.px(12)
                                            radius: Theme.px(9)
                                            color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12)
                                            border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.25)
                                            border.width: 1

                                            Text {
                                                id: winCountText
                                                anchors.centerIn: parent
                                                text: spatialCanvasWindow.filteredWindows.length + " ACTIVE"
                                                font.family: Theme.fontMono || "monospace"
                                                font.pixelSize: Theme.fontPx(8.5)
                                                font.bold: true
                                                color: Theme.primary
                                            }
                                        }
                                    }

                                    // Quick Filter / Search Bar
                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: Theme.px(30)
                                        radius: Theme.px(6)
                                        color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.05)
                                        border.color: appFilterInput.activeFocus ? Theme.primary : Qt.rgba(255, 255, 255, 0.12)
                                        border.width: 1

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: Theme.px(8)
                                            anchors.rightMargin: Theme.px(8)
                                            spacing: Theme.px(6)

                                            Text {
                                                text: "search"
                                                font.family: Theme.fontIcon
                                                font.pixelSize: Theme.fontPx(13)
                                                color: appFilterInput.activeFocus ? Theme.primary : Theme.fgDim
                                            }

                                            TextInput {
                                                id: appFilterInput
                                                Layout.fillWidth: true
                                                font.family: Theme.font
                                                font.pixelSize: Theme.fontPx(11)
                                                color: Theme.fg
                                                clip: true
                                                selectByMouse: true
                                                text: spatialCanvasWindow.appFilterQuery
                                                onTextChanged: spatialCanvasWindow.appFilterQuery = text

                                                Text {
                                                    visible: !appFilterInput.text && !appFilterInput.activeFocus
                                                    text: "Filter open apps or windows..."
                                                    font.family: Theme.font
                                                    font.pixelSize: Theme.fontPx(11)
                                                    color: Qt.rgba(Theme.fgDim.r, Theme.fgDim.g, Theme.fgDim.b, 0.5)
                                                }
                                            }

                                            Text {
                                                visible: appFilterInput.text.length > 0
                                                text: "close"
                                                font.family: Theme.fontIcon
                                                font.pixelSize: Theme.fontPx(12)
                                                color: Theme.fgDim
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        appFilterInput.text = "";
                                                        spatialCanvasWindow.appFilterQuery = "";
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // ListView of running windows
                                    ListView {
                                        id: appsListView
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        clip: true
                                        spacing: Theme.px(4)
                                        model: spatialCanvasWindow.filteredWindows

                                        boundsBehavior: Flickable.StopAtBounds

                                        ScrollBar.vertical: ScrollBar {
                                            active: appsListView.moving || appsListView.dragging
                                            policy: ScrollBar.AsNeeded
                                        }

                                        delegate: Rectangle {
                                            id: appItemRow
                                            width: appsListView.width
                                            height: Theme.px(44)
                                            radius: Theme.px(6)
                                            color: itemHover.hovered 
                                                ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12) 
                                                : ((modelData.is_focused === true) ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.06) : Qt.rgba(255, 255, 255, 0.03))
                                            border.color: itemHover.hovered 
                                                ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.35) 
                                                : ((modelData.is_focused === true) ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.25) : Qt.rgba(255, 255, 255, 0.06))
                                            border.width: 1

                                            HoverHandler { id: itemHover }

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    spatialCanvasWindow.execCommand("hyprctl dispatch focuswindow address:" + modelData.address);
                                                    spatialCanvasWindow.closeRequested();
                                                }
                                            }

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: Theme.px(8)
                                                anchors.rightMargin: Theme.px(8)
                                                spacing: Theme.px(8)

                                                // App Icon
                                                Image {
                                                    Layout.preferredWidth: Theme.px(24)
                                                    Layout.preferredHeight: Theme.px(24)
                                                    source: spatialCanvasWindow.resolveAppIcon(modelData.class)
                                                    sourceSize: Qt.size(48, 48)
                                                    fillMode: Image.PreserveAspectFit
                                                }

                                                // Title and App Class
                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    spacing: Theme.px(1)

                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: modelData.title || modelData.class || "Untitled Window"
                                                        font.family: Theme.font
                                                        font.pixelSize: Theme.fontPx(11)
                                                        font.weight: Font.DemiBold
                                                        color: itemHover.hovered ? Theme.primary : Theme.fg
                                                        elide: Text.ElideRight
                                                    }

                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: modelData.class || ""
                                                        font.family: Theme.fontMono || "monospace"
                                                        font.pixelSize: Theme.fontPx(8.5)
                                                        color: Theme.fgDim
                                                        elide: Text.ElideRight
                                                    }
                                                }

                                                // Workspace Pill (WS 01, etc.)
                                                Rectangle {
                                                    Layout.preferredHeight: Theme.px(18)
                                                    Layout.preferredWidth: wsPillText.implicitWidth + Theme.px(10)
                                                    radius: Theme.px(4)
                                                    color: Qt.rgba(255, 255, 255, 0.06)
                                                    border.color: Qt.rgba(255, 255, 255, 0.12)
                                                    border.width: 1

                                                    Text {
                                                        id: wsPillText
                                                        anchors.centerIn: parent
                                                        readonly property var wsVal: (modelData.workspace && modelData.workspace.id !== undefined) ? modelData.workspace.id : (modelData.workspaceId !== undefined ? modelData.workspaceId : "?")
                                                        text: "WS " + (typeof wsVal === "number" ? (wsVal < 10 ? "0" + wsVal : wsVal) : wsVal)
                                                        font.family: Theme.fontMono || "monospace"
                                                        font.pixelSize: Theme.fontPx(8.5)
                                                        font.bold: true
                                                        color: Theme.fgDim
                                                    }
                                                }

                                                // Close Button (revealed on hover)
                                                Rectangle {
                                                    visible: itemHover.hovered
                                                    Layout.preferredWidth: Theme.px(20)
                                                    Layout.preferredHeight: Theme.px(20)
                                                    radius: Theme.px(4)
                                                    color: closeHover.hovered ? Qt.rgba(Theme.err.r, Theme.err.g, Theme.err.b, 0.25) : Qt.rgba(255, 255, 255, 0.08)
                                                    border.color: closeHover.hovered ? Theme.err : Qt.rgba(255, 255, 255, 0.15)
                                                    border.width: 1

                                                    HoverHandler { id: closeHover }

                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: "close"
                                                        font.family: Theme.fontIcon
                                                        font.pixelSize: Theme.fontPx(12)
                                                        color: closeHover.hovered ? Theme.err : Theme.fgDim
                                                    }

                                                    MouseArea {
                                                        anchors.fill: parent
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            spatialCanvasWindow.closeWindow(modelData.address);
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Transparent click interceptor when card is NOT focused
                    MouseArea {
                        anchors.fill: parent
                        z: 90
                        enabled: viewport.isOverview || (!cardNode0_0.isCurrentTarget)
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            spatialCanvasWindow.zoomToNode(cardNode0_0.nodeX, cardNode0_0.nodeY)
                        }
                    }
                }
                // ══════════════════════════════════════════════════════════
                // NODE (1, 0) :: CARBON ENGINE
                // ══════════════════════════════════════════════════════════
                Rectangle {
                    id: cardNode1_0
                    readonly property int nodeX: 1
                    readonly property int nodeY: 0
                    readonly property bool isCurrentTarget: (spatialCanvasWindow.activeGridX === cardNode1_0.nodeX && spatialCanvasWindow.activeGridY === cardNode1_0.nodeY)
                    readonly property string cardIcon: "tune"
                    readonly property string cardTitle: "Carbon Engine"
                    readonly property string cardSubtitle: "Shell Architecture & Wallpaper Studio"

                    width: viewport.cardWidth
                    height: viewport.cardHeight
                    x: Math.round((viewport.width - width) / 2 + (cardNode1_0.nodeX * viewport.stepX))
                    y: Math.round((viewport.height - height) / 2 + (cardNode1_0.nodeY * viewport.stepY))
                    radius: 22

                    // Matugen-tinted frosted glass surface
                    color: Qt.rgba(Theme.surface.r * 0.8 + Theme.primary.r * 0.2, Theme.surface.g * 0.8 + Theme.primary.g * 0.2, Theme.surface.b * 0.8 + Theme.primary.b * 0.2, 0.78)
                    border.width: cardNode1_0.isCurrentTarget && !viewport.isOverview ? 1.5 : 1
                    border.color: (cardNode1_0Hover.hovered || cardNode1_0.isCurrentTarget) ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.55) : Qt.rgba(1, 1, 1, 0.08)
                    clip: true

                    HoverHandler { id: cardNode1_0Hover }

                    // Top Specular Highlight Line
                    Rectangle {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: Theme.px(22)
                        anchors.rightMargin: Theme.px(22)
                        height: 1
                        color: Qt.rgba(255, 255, 255, 0.18)
                        z: 5
                    }

                    // Inner Soft Top-Left Gradient Overlay
                    Rectangle {
                        anchors.fill: parent
                        radius: 22
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12) }
                            GradientStop { position: 1.0; color: "transparent" }
                        }
                        opacity: 0.85
                        z: 1
                    }

                    // Corner Crosshairs for tech / OS aesthetic
                    Text { text: "+"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(11); font.bold: true; color: cardNode1_0.isCurrentTarget ? Theme.primary : Qt.rgba(Theme.fgDim.r, Theme.fgDim.g, Theme.fgDim.b, 0.35); anchors.left: parent.left; anchors.top: parent.top; anchors.margins: Theme.px(10); z: 10 }
                    Text { text: "+"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(11); font.bold: true; color: cardNode1_0.isCurrentTarget ? Theme.primary : Qt.rgba(Theme.fgDim.r, Theme.fgDim.g, Theme.fgDim.b, 0.35); anchors.right: parent.right; anchors.top: parent.top; anchors.margins: Theme.px(10); z: 10 }
                    Text { text: "+"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(11); font.bold: true; color: cardNode1_0.isCurrentTarget ? Theme.primary : Qt.rgba(Theme.fgDim.r, Theme.fgDim.g, Theme.fgDim.b, 0.35); anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: Theme.px(10); z: 10 }
                    Text { text: "+"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(11); font.bold: true; color: cardNode1_0.isCurrentTarget ? Theme.primary : Qt.rgba(Theme.fgDim.r, Theme.fgDim.g, Theme.fgDim.b, 0.35); anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: Theme.px(10); z: 10 }

                    // Modern Unified Header Bar
                    RowLayout {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.topMargin: Theme.px(14)
                        anchors.leftMargin: Theme.px(22)
                        anchors.rightMargin: Theme.px(22)
                        height: Theme.px(28)
                        spacing: Theme.px(10)
                        z: 10

                        // Glowing Matugen Accent Dot
                        Rectangle {
                            Layout.preferredWidth: Theme.px(8)
                            Layout.preferredHeight: Theme.px(8)
                            radius: Theme.px(4)
                            color: cardNode1_0.isCurrentTarget ? Theme.primary : Qt.rgba(Theme.fgDim.r, Theme.fgDim.g, Theme.fgDim.b, 0.50)

                            Rectangle {
                                anchors.centerIn: parent
                                width: Theme.px(14)
                                height: Theme.px(14)
                                radius: Theme.px(7)
                                color: cardNode1_0.isCurrentTarget ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.25) : "transparent"
                                z: -1
                            }
                        }

                        Text {
                            text: cardNode1_0.cardIcon
                            font.family: Theme.fontIcon
                            font.pixelSize: Theme.fontPx(16)
                            color: cardNode1_0.isCurrentTarget ? Theme.primary : Theme.fgDim
                        }

                        // Bold Title
                        Text {
                            text: cardNode1_0.cardTitle
                            font.family: Theme.font
                            font.pixelSize: Theme.fontPx(13.5)
                            font.weight: Font.Bold
                            color: cardNode1_0.isCurrentTarget ? Theme.fg : Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.75)
                        }

                        // Muted Subtitle Pill
                        Rectangle {
                            Layout.preferredHeight: Theme.px(18)
                            Layout.preferredWidth: cardNode1_0SubText.implicitWidth + Theme.px(12)
                            radius: Theme.px(9)
                            color: Qt.rgba(255, 255, 255, 0.05)
                            border.color: Qt.rgba(255, 255, 255, 0.08)
                            border.width: 1

                            Text {
                                id: cardNode1_0SubText
                                anchors.centerIn: parent
                                text: cardNode1_0.cardSubtitle
                                font.family: Theme.fontMono || "monospace"
                                font.pixelSize: Theme.fontPx(8.5)
                                color: Theme.fgDim
                            }
                        }

                        Item { Layout.fillWidth: true }

                        // Sleek rounded pill button for Overview [ESC]
                        Rectangle {
                            visible: cardNode1_0.isCurrentTarget && !spatialCanvasWindow.isOverview
                            Layout.preferredHeight: Theme.px(22)
                            Layout.preferredWidth: cardNode1_0OverviewBtnText.implicitWidth + Theme.px(16)
                            radius: Theme.px(11)
                            color: cardNode1_0OverviewHover.hovered ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15) : Qt.rgba(255, 255, 255, 0.06)
                            border.color: cardNode1_0OverviewHover.hovered ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.40) : Qt.rgba(255, 255, 255, 0.12)
                            border.width: 1

                            HoverHandler { id: cardNode1_0OverviewHover }
                            Text {
                                id: cardNode1_0OverviewBtnText
                                anchors.centerIn: parent
                                text: "Overview [ESC]"
                                font.family: Theme.fontMono || "monospace"
                                font.pixelSize: Theme.fontPx(9)
                                font.bold: true
                                color: cardNode1_0OverviewHover.hovered ? Theme.primary : Theme.fgDim
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: spatialCanvasWindow.zoomToOverview()
                            }
                        }
                    }

                    // Inner Content Container: Opacity 1.0 AT ALL TIMES!
                    Item {
                        id: cardNode1_0Inner
                        anchors.fill: parent
                        anchors.margins: Theme.px(16)
                        anchors.topMargin: Theme.px(48)
                        clip: true
                        opacity: 1.0
                        z: 2

                        RowLayout {
                            anchors.fill: parent
                            spacing: Theme.px(16)

                            // ─────────────────────────────────────────────────────────────
                            // LEFT SIDE (40% width): Active Preview & Shell Architecture
                            // ─────────────────────────────────────────────────────────────
                            ColumnLayout {
                                Layout.preferredWidth: Math.round(parent.width * 0.40)
                                Layout.fillHeight: true
                                spacing: Theme.px(12)

                                // Active Wallpaper Preview Card
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: Theme.px(160)
                                    radius: Theme.px(10)
                                    color: "#050608"
                                    border.color: Qt.rgba(255, 255, 255, 0.12)
                                    border.width: 1
                                    clip: true

                                    Image {
                                        anchors.fill: parent
                                        source: "file://" + (Quickshell.env("HOME") || "") + "/.config/hypr/current_wallpaper"
                                        fillMode: Image.PreserveAspectCrop
                                        cache: false
                                    }

                                    Rectangle {
                                        anchors.fill: parent
                                        gradient: Gradient {
                                            orientation: Gradient.Vertical
                                            GradientStop { position: 0.0; color: "transparent" }
                                            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.65) }
                                        }
                                    }

                                    RowLayout {
                                        anchors.bottom: parent.bottom
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.margins: Theme.px(10)
                                        spacing: Theme.px(6)

                                        Text {
                                            text: "image"
                                            font.family: Theme.fontIcon
                                            font.pixelSize: Theme.fontPx(14)
                                            color: Theme.primary
                                        }

                                        Text {
                                            text: "ACTIVE WALLPAPER"
                                            font.family: Theme.fontMono || "monospace"
                                            font.pixelSize: Theme.fontPx(9.5)
                                            font.bold: true
                                            color: Theme.fg
                                        }
                                    }
                                }

                                // Shell Architecture Mode Switcher
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: Theme.px(6)

                                    Text {
                                        text: "SHELL ARCHITECTURE & MODES"
                                        font.family: Theme.fontMono || "monospace"
                                        font.pixelSize: Theme.fontPx(9.5)
                                        font.bold: true
                                        color: Theme.primary
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Theme.px(6)

                                        Repeater {
                                            model: [
                                                { id: "notch", name: "Notch", icon: "dock_to_bottom" },
                                                { id: "vanish", name: "Vanish", icon: "visibility_off" },
                                                { id: "minimal", name: "Minimal", icon: "horizontal_rule" }
                                            ]

                                            Rectangle {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: Theme.px(32)
                                                radius: Theme.px(6)
                                                readonly property bool isActive: (spatialCanvasWindow.barMode === modelData.id)
                                                color: isActive ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.18) : (modeHov.hovered ? Qt.rgba(255, 255, 255, 0.08) : Qt.rgba(255, 255, 255, 0.04))
                                                border.color: isActive ? Theme.primary : Qt.rgba(255, 255, 255, 0.10)
                                                border.width: 1

                                                HoverHandler { id: modeHov }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: spatialCanvasWindow.applyBarMode(modelData.id)
                                                }

                                                RowLayout {
                                                    anchors.centerIn: parent
                                                    spacing: Theme.px(4)
                                                    Text { text: modelData.icon; font.family: Theme.fontIcon; font.pixelSize: Theme.fontPx(13); color: isActive ? Theme.primary : Theme.fgDim }
                                                    Text { text: modelData.name; font.family: Theme.font; font.pixelSize: Theme.fontPx(10.5); font.bold: isActive; color: isActive ? Theme.fg : Theme.fgDim }
                                                }
                                            }
                                        }
                                    }
                                }

                                // Matugen Palette Swatches
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: Theme.px(6)

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text {
                                            text: "EXTRACTED PALETTE"
                                            font.family: Theme.fontMono || "monospace"
                                            font.pixelSize: Theme.fontPx(9.5)
                                            font.bold: true
                                            color: Theme.primary
                                        }
                                        Item { Layout.fillWidth: true }
                                        Text {
                                            text: "REGEN"
                                            font.family: Theme.fontMono || "monospace"
                                            font.pixelSize: Theme.fontPx(9)
                                            color: regenHov.hovered ? Theme.primary : Theme.fgDim
                                            HoverHandler { id: regenHov }
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    spatialCanvasWindow.execCommand("python3 ~/.config/hypr/scripts/theme-mk.py ~/.config/hypr/current_wallpaper");
                                                    spatialCanvasWindow.triggerThemeReload();
                                                    spatialCanvasWindow.showFeedback("Regenerating theme palette (Matugen)...");
                                                }
                                            }
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Theme.px(8)

                                        Repeater {
                                            model: [
                                                { name: "Primary", col: Theme.primary },
                                                { name: "Accent", col: Theme.accent },
                                                { name: "Surface", col: Theme.surface },
                                                { name: "Container", col: Theme.container },
                                                { name: "Muted", col: Theme.fgDim },
                                                { name: "Error", col: Theme.err }
                                            ]

                                            Rectangle {
                                                width: Theme.px(26)
                                                height: Theme.px(26)
                                                radius: Theme.px(13)
                                                color: modelData.col
                                                border.color: Qt.rgba(255, 255, 255, 0.20)
                                                border.width: 1
                                            }
                                        }
                                    }
                                }

                                Item { Layout.fillHeight: true }
                            }

                            // ─────────────────────────────────────────────────────────────
                            // RIGHT SIDE (60% width): Visual Wallpaper Grid
                            // ─────────────────────────────────────────────────────────────
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                spacing: Theme.px(8)

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Theme.px(6)

                                    Text { text: "photo_library"; font.family: Theme.fontIcon; font.pixelSize: Theme.fontPx(14); color: Theme.primary }
                                    Text { text: "WALLPAPER STUDIO & THUMBNAILS"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(11); font.bold: true; color: Theme.fg }
                                    Item { Layout.fillWidth: true }
                                    Text {
                                        text: (spatialCanvasWindow.wallpaperList.length) + " WALLPAPERS"
                                        font.family: Theme.fontMono || "monospace"
                                        font.pixelSize: Theme.fontPx(9)
                                        color: Theme.fgDim
                                    }
                                }

                                // Wallpaper Grid View
                                GridView {
                                    id: wpGridView
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    clip: true
                                    cellWidth: Math.floor(width / 3)
                                    cellHeight: Math.floor(cellWidth * 0.65)
                                    model: spatialCanvasWindow.wallpaperList

                                    ScrollBar.vertical: ScrollBar {
                                        active: wpGridView.moving || wpGridView.dragging
                                        policy: ScrollBar.AsNeeded
                                    }

                                    delegate: Rectangle {
                                        width: wpGridView.cellWidth - Theme.px(6)
                                        height: wpGridView.cellHeight - Theme.px(6)
                                        radius: Theme.px(8)
                                        color: "#08090d"
                                        border.color: wpHover.hovered ? Theme.primary : Qt.rgba(255, 255, 255, 0.10)
                                        border.width: wpHover.hovered ? 2 : 1
                                        clip: true

                                        HoverHandler { id: wpHover }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                spatialCanvasWindow.execCommand("bash ~/.config/hypr/scripts/wp-apply.sh \"" + modelData + "\"");
                                                spatialCanvasWindow.showFeedback("Applying wallpaper...");
                                                spatialCanvasWindow.triggerThemeReload();
                                            }
                                        }

                                        Image {
                                            anchors.fill: parent
                                            source: "file://" + modelData
                                            sourceSize: Qt.size(160, 100)
                                            fillMode: Image.PreserveAspectCrop
                                            asynchronous: true
                                        }

                                        Rectangle {
                                            anchors.fill: parent
                                            color: wpHover.hovered ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15) : "transparent"
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Transparent click interceptor when card is NOT focused
                    MouseArea {
                        anchors.fill: parent
                        z: 90
                        enabled: viewport.isOverview || (!cardNode1_0.isCurrentTarget)
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            spatialCanvasWindow.zoomToNode(cardNode1_0.nodeX, cardNode1_0.nodeY)
                        }
                    }
                }
                // ══════════════════════════════════════════════════════════
                // NODE (-1, 0) :: APPLICATION LAUNCHER
                // ══════════════════════════════════════════════════════════
                Rectangle {
                    id: cardNodeMinus1_0
                    readonly property int nodeX: -1
                    readonly property int nodeY: 0
                    readonly property bool isCurrentTarget: (spatialCanvasWindow.activeGridX === cardNodeMinus1_0.nodeX && spatialCanvasWindow.activeGridY === cardNodeMinus1_0.nodeY)
                    readonly property string cardIcon: "apps"
                    readonly property string cardTitle: "Application Launcher"
                    readonly property string cardSubtitle: "Desktop Applications & Fast Search"

                    width: viewport.cardWidth
                    height: viewport.cardHeight
                    x: Math.round((viewport.width - width) / 2 + (cardNodeMinus1_0.nodeX * viewport.stepX))
                    y: Math.round((viewport.height - height) / 2 + (cardNodeMinus1_0.nodeY * viewport.stepY))
                    radius: 22

                    // Matugen-tinted frosted glass surface
                    color: Qt.rgba(Theme.surface.r * 0.8 + Theme.primary.r * 0.2, Theme.surface.g * 0.8 + Theme.primary.g * 0.2, Theme.surface.b * 0.8 + Theme.primary.b * 0.2, 0.78)
                    border.width: cardNodeMinus1_0.isCurrentTarget && !viewport.isOverview ? 1.5 : 1
                    border.color: (cardNodeMinus1_0Hover.hovered || cardNodeMinus1_0.isCurrentTarget) ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.55) : Qt.rgba(1, 1, 1, 0.08)
                    clip: true

                    HoverHandler { id: cardNodeMinus1_0Hover }

                    // Top Specular Highlight Line
                    Rectangle {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: Theme.px(22)
                        anchors.rightMargin: Theme.px(22)
                        height: 1
                        color: Qt.rgba(255, 255, 255, 0.18)
                        z: 5
                    }

                    // Inner Soft Top-Left Gradient Overlay
                    Rectangle {
                        anchors.fill: parent
                        radius: 22
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12) }
                            GradientStop { position: 1.0; color: "transparent" }
                        }
                        opacity: 0.85
                        z: 1
                    }

                    // Corner Crosshairs for tech / OS aesthetic
                    Text { text: "+"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(11); font.bold: true; color: cardNodeMinus1_0.isCurrentTarget ? Theme.primary : Qt.rgba(Theme.fgDim.r, Theme.fgDim.g, Theme.fgDim.b, 0.35); anchors.left: parent.left; anchors.top: parent.top; anchors.margins: Theme.px(10); z: 10 }
                    Text { text: "+"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(11); font.bold: true; color: cardNodeMinus1_0.isCurrentTarget ? Theme.primary : Qt.rgba(Theme.fgDim.r, Theme.fgDim.g, Theme.fgDim.b, 0.35); anchors.right: parent.right; anchors.top: parent.top; anchors.margins: Theme.px(10); z: 10 }
                    Text { text: "+"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(11); font.bold: true; color: cardNodeMinus1_0.isCurrentTarget ? Theme.primary : Qt.rgba(Theme.fgDim.r, Theme.fgDim.g, Theme.fgDim.b, 0.35); anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: Theme.px(10); z: 10 }
                    Text { text: "+"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(11); font.bold: true; color: cardNodeMinus1_0.isCurrentTarget ? Theme.primary : Qt.rgba(Theme.fgDim.r, Theme.fgDim.g, Theme.fgDim.b, 0.35); anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: Theme.px(10); z: 10 }

                    // Modern Unified Header Bar
                    RowLayout {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.topMargin: Theme.px(14)
                        anchors.leftMargin: Theme.px(22)
                        anchors.rightMargin: Theme.px(22)
                        height: Theme.px(28)
                        spacing: Theme.px(10)
                        z: 10

                        // Glowing Matugen Accent Dot
                        Rectangle {
                            Layout.preferredWidth: Theme.px(8)
                            Layout.preferredHeight: Theme.px(8)
                            radius: Theme.px(4)
                            color: cardNodeMinus1_0.isCurrentTarget ? Theme.primary : Qt.rgba(Theme.fgDim.r, Theme.fgDim.g, Theme.fgDim.b, 0.50)

                            Rectangle {
                                anchors.centerIn: parent
                                width: Theme.px(14)
                                height: Theme.px(14)
                                radius: Theme.px(7)
                                color: cardNodeMinus1_0.isCurrentTarget ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.25) : "transparent"
                                z: -1
                            }
                        }

                        Text {
                            text: cardNodeMinus1_0.cardIcon
                            font.family: Theme.fontIcon
                            font.pixelSize: Theme.fontPx(16)
                            color: cardNodeMinus1_0.isCurrentTarget ? Theme.primary : Theme.fgDim
                        }

                        // Bold Title
                        Text {
                            text: cardNodeMinus1_0.cardTitle
                            font.family: Theme.font
                            font.pixelSize: Theme.fontPx(13.5)
                            font.weight: Font.Bold
                            color: cardNodeMinus1_0.isCurrentTarget ? Theme.fg : Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.75)
                        }

                        // Muted Subtitle Pill
                        Rectangle {
                            Layout.preferredHeight: Theme.px(18)
                            Layout.preferredWidth: cardNodeMinus1_0SubText.implicitWidth + Theme.px(12)
                            radius: Theme.px(9)
                            color: Qt.rgba(255, 255, 255, 0.05)
                            border.color: Qt.rgba(255, 255, 255, 0.08)
                            border.width: 1

                            Text {
                                id: cardNodeMinus1_0SubText
                                anchors.centerIn: parent
                                text: cardNodeMinus1_0.cardSubtitle
                                font.family: Theme.fontMono || "monospace"
                                font.pixelSize: Theme.fontPx(8.5)
                                color: Theme.fgDim
                            }
                        }

                        Item { Layout.fillWidth: true }

                        // Sleek rounded pill button for Overview [ESC]
                        Rectangle {
                            visible: cardNodeMinus1_0.isCurrentTarget && !spatialCanvasWindow.isOverview
                            Layout.preferredHeight: Theme.px(22)
                            Layout.preferredWidth: cardNodeMinus1_0OverviewBtnText.implicitWidth + Theme.px(16)
                            radius: Theme.px(11)
                            color: cardNodeMinus1_0OverviewHover.hovered ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15) : Qt.rgba(255, 255, 255, 0.06)
                            border.color: cardNodeMinus1_0OverviewHover.hovered ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.40) : Qt.rgba(255, 255, 255, 0.12)
                            border.width: 1

                            HoverHandler { id: cardNodeMinus1_0OverviewHover }
                            Text {
                                id: cardNodeMinus1_0OverviewBtnText
                                anchors.centerIn: parent
                                text: "Overview [ESC]"
                                font.family: Theme.fontMono || "monospace"
                                font.pixelSize: Theme.fontPx(9)
                                font.bold: true
                                color: cardNodeMinus1_0OverviewHover.hovered ? Theme.primary : Theme.fgDim
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: spatialCanvasWindow.zoomToOverview()
                            }
                        }
                    }

                    // Inner Content Container: Opacity 1.0 AT ALL TIMES!
                    Item {
                        id: cardNodeMinus1_0Inner
                        anchors.fill: parent
                        anchors.margins: Theme.px(16)
                        anchors.topMargin: Theme.px(48)
                        clip: true
                        opacity: 1.0
                        z: 2

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: Theme.px(10)

                            // Search bar
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Theme.px(34)
                                radius: Theme.px(8)
                                color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.05)
                                border.color: appLauncherInput.activeFocus ? Theme.primary : Qt.rgba(255, 255, 255, 0.12)
                                border.width: 1

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.px(10)
                                    anchors.rightMargin: Theme.px(10)
                                    spacing: Theme.px(8)

                                    Text {
                                        text: "search"
                                        font.family: Theme.fontIcon
                                        font.pixelSize: Theme.fontPx(14)
                                        color: appLauncherInput.activeFocus ? Theme.primary : Theme.fgDim
                                    }

                                    TextInput {
                                        id: appLauncherInput
                                        Layout.fillWidth: true
                                        font.family: Theme.font
                                        font.pixelSize: Theme.fontPx(12)
                                        color: Theme.fg
                                        clip: true
                                        selectByMouse: true
                                        text: spatialCanvasWindow.appLauncherSearchQuery
                                        onTextChanged: spatialCanvasWindow.appLauncherSearchQuery = text

                                        Text {
                                            visible: !appLauncherInput.text && !appLauncherInput.activeFocus
                                            text: "Search installed applications..."
                                            font.family: Theme.font
                                            font.pixelSize: Theme.fontPx(12)
                                            color: Qt.rgba(Theme.fgDim.r, Theme.fgDim.g, Theme.fgDim.b, 0.5)
                                        }
                                    }

                                    Text {
                                        visible: appLauncherInput.text.length > 0
                                        text: "close"
                                        font.family: Theme.fontIcon
                                        font.pixelSize: Theme.fontPx(13)
                                        color: Theme.fgDim
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                appLauncherInput.text = "";
                                                spatialCanvasWindow.appLauncherSearchQuery = "";
                                            }
                                        }
                                    }
                                }
                            }

                            // App list
                            ListView {
                                id: appLauncherListView
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                clip: true
                                spacing: Theme.px(4)
                                model: spatialCanvasWindow.filteredApps

                                boundsBehavior: Flickable.StopAtBounds

                                ScrollBar.vertical: ScrollBar {
                                    active: appLauncherListView.moving || appLauncherListView.dragging
                                    policy: ScrollBar.AsNeeded
                                }

                                delegate: Rectangle {
                                    width: appLauncherListView.width
                                    height: Theme.px(46)
                                    radius: Theme.px(8)
                                    color: appRowHov.hovered ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12) : Qt.rgba(255, 255, 255, 0.03)
                                    border.color: appRowHov.hovered ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.35) : Qt.rgba(255, 255, 255, 0.06)
                                    border.width: 1

                                    HoverHandler { id: appRowHov }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (modelData.entry && modelData.entry.execute) {
                                                modelData.entry.execute();
                                            } else {
                                                spatialCanvasWindow.execCommand("gtk-launch " + modelData.entry.id);
                                            }
                                            spatialCanvasWindow.closeRequested();
                                        }
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: Theme.px(10)
                                        anchors.rightMargin: Theme.px(10)
                                        spacing: Theme.px(10)

                                        Image {
                                            Layout.preferredWidth: Theme.px(28)
                                            Layout.preferredHeight: Theme.px(28)
                                            source: spatialCanvasWindow.resolveAppIcon(modelData.icon)
                                            sourceSize: Qt.size(56, 56)
                                            fillMode: Image.PreserveAspectFit
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: Theme.px(1)

                                            Text {
                                                Layout.fillWidth: true
                                                text: modelData.name
                                                font.family: Theme.font
                                                font.pixelSize: Theme.fontPx(12)
                                                font.weight: Font.DemiBold
                                                color: appRowHov.hovered ? Theme.primary : Theme.fg
                                                elide: Text.ElideRight
                                            }

                                            Text {
                                                Layout.fillWidth: true
                                                text: modelData.comment || "Application"
                                                font.family: Theme.font
                                                font.pixelSize: Theme.fontPx(9)
                                                color: Theme.fgDim
                                                elide: Text.ElideRight
                                            }
                                        }

                                        Text {
                                            visible: appRowHov.hovered
                                            text: "play_arrow"
                                            font.family: Theme.fontIcon
                                            font.pixelSize: Theme.fontPx(16)
                                            color: Theme.primary
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Transparent click interceptor when card is NOT focused
                    MouseArea {
                        anchors.fill: parent
                        z: 90
                        enabled: viewport.isOverview || (!cardNodeMinus1_0.isCurrentTarget)
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            spatialCanvasWindow.zoomToNode(cardNodeMinus1_0.nodeX, cardNodeMinus1_0.nodeY)
                        }
                    }
                }
                // ══════════════════════════════════════════════════════════
                // NODE (-1, -1) :: NETWORK & WI-FI
                // ══════════════════════════════════════════════════════════
                Rectangle {
                    id: cardNodeMinus1_Minus1
                    readonly property int nodeX: -1
                    readonly property int nodeY: -1
                    readonly property bool isCurrentTarget: (spatialCanvasWindow.activeGridX === cardNodeMinus1_Minus1.nodeX && spatialCanvasWindow.activeGridY === cardNodeMinus1_Minus1.nodeY)
                    readonly property string cardIcon: "wifi"
                    readonly property string cardTitle: "Network & Wi-Fi"
                    readonly property string cardSubtitle: "Interface Status & Wireless Access Points"

                    width: viewport.cardWidth
                    height: viewport.cardHeight
                    x: Math.round((viewport.width - width) / 2 + (cardNodeMinus1_Minus1.nodeX * viewport.stepX))
                    y: Math.round((viewport.height - height) / 2 + (cardNodeMinus1_Minus1.nodeY * viewport.stepY))
                    radius: 22

                    // Matugen-tinted frosted glass surface
                    color: Qt.rgba(Theme.surface.r * 0.8 + Theme.primary.r * 0.2, Theme.surface.g * 0.8 + Theme.primary.g * 0.2, Theme.surface.b * 0.8 + Theme.primary.b * 0.2, 0.78)
                    border.width: cardNodeMinus1_Minus1.isCurrentTarget && !viewport.isOverview ? 1.5 : 1
                    border.color: (cardNodeMinus1_Minus1Hover.hovered || cardNodeMinus1_Minus1.isCurrentTarget) ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.55) : Qt.rgba(1, 1, 1, 0.08)
                    clip: true

                    HoverHandler { id: cardNodeMinus1_Minus1Hover }

                    // Top Specular Highlight Line
                    Rectangle {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: Theme.px(22)
                        anchors.rightMargin: Theme.px(22)
                        height: 1
                        color: Qt.rgba(255, 255, 255, 0.18)
                        z: 5
                    }

                    // Inner Soft Top-Left Gradient Overlay
                    Rectangle {
                        anchors.fill: parent
                        radius: 22
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12) }
                            GradientStop { position: 1.0; color: "transparent" }
                        }
                        opacity: 0.85
                        z: 1
                    }

                    // Corner Crosshairs for tech / OS aesthetic
                    Text { text: "+"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(11); font.bold: true; color: cardNodeMinus1_Minus1.isCurrentTarget ? Theme.primary : Qt.rgba(Theme.fgDim.r, Theme.fgDim.g, Theme.fgDim.b, 0.35); anchors.left: parent.left; anchors.top: parent.top; anchors.margins: Theme.px(10); z: 10 }
                    Text { text: "+"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(11); font.bold: true; color: cardNodeMinus1_Minus1.isCurrentTarget ? Theme.primary : Qt.rgba(Theme.fgDim.r, Theme.fgDim.g, Theme.fgDim.b, 0.35); anchors.right: parent.right; anchors.top: parent.top; anchors.margins: Theme.px(10); z: 10 }
                    Text { text: "+"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(11); font.bold: true; color: cardNodeMinus1_Minus1.isCurrentTarget ? Theme.primary : Qt.rgba(Theme.fgDim.r, Theme.fgDim.g, Theme.fgDim.b, 0.35); anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: Theme.px(10); z: 10 }
                    Text { text: "+"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(11); font.bold: true; color: cardNodeMinus1_Minus1.isCurrentTarget ? Theme.primary : Qt.rgba(Theme.fgDim.r, Theme.fgDim.g, Theme.fgDim.b, 0.35); anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: Theme.px(10); z: 10 }

                    // Modern Unified Header Bar
                    RowLayout {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.topMargin: Theme.px(14)
                        anchors.leftMargin: Theme.px(22)
                        anchors.rightMargin: Theme.px(22)
                        height: Theme.px(28)
                        spacing: Theme.px(10)
                        z: 10

                        // Glowing Matugen Accent Dot
                        Rectangle {
                            Layout.preferredWidth: Theme.px(8)
                            Layout.preferredHeight: Theme.px(8)
                            radius: Theme.px(4)
                            color: cardNodeMinus1_Minus1.isCurrentTarget ? Theme.primary : Qt.rgba(Theme.fgDim.r, Theme.fgDim.g, Theme.fgDim.b, 0.50)

                            Rectangle {
                                anchors.centerIn: parent
                                width: Theme.px(14)
                                height: Theme.px(14)
                                radius: Theme.px(7)
                                color: cardNodeMinus1_Minus1.isCurrentTarget ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.25) : "transparent"
                                z: -1
                            }
                        }

                        Text {
                            text: cardNodeMinus1_Minus1.cardIcon
                            font.family: Theme.fontIcon
                            font.pixelSize: Theme.fontPx(16)
                            color: cardNodeMinus1_Minus1.isCurrentTarget ? Theme.primary : Theme.fgDim
                        }

                        // Bold Title
                        Text {
                            text: cardNodeMinus1_Minus1.cardTitle
                            font.family: Theme.font
                            font.pixelSize: Theme.fontPx(13.5)
                            font.weight: Font.Bold
                            color: cardNodeMinus1_Minus1.isCurrentTarget ? Theme.fg : Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.75)
                        }

                        // Muted Subtitle Pill
                        Rectangle {
                            Layout.preferredHeight: Theme.px(18)
                            Layout.preferredWidth: cardNodeMinus1_Minus1SubText.implicitWidth + Theme.px(12)
                            radius: Theme.px(9)
                            color: Qt.rgba(255, 255, 255, 0.05)
                            border.color: Qt.rgba(255, 255, 255, 0.08)
                            border.width: 1

                            Text {
                                id: cardNodeMinus1_Minus1SubText
                                anchors.centerIn: parent
                                text: cardNodeMinus1_Minus1.cardSubtitle
                                font.family: Theme.fontMono || "monospace"
                                font.pixelSize: Theme.fontPx(8.5)
                                color: Theme.fgDim
                            }
                        }

                        Item { Layout.fillWidth: true }

                        // Sleek rounded pill button for Overview [ESC]
                        Rectangle {
                            visible: cardNodeMinus1_Minus1.isCurrentTarget && !spatialCanvasWindow.isOverview
                            Layout.preferredHeight: Theme.px(22)
                            Layout.preferredWidth: cardNodeMinus1_Minus1OverviewBtnText.implicitWidth + Theme.px(16)
                            radius: Theme.px(11)
                            color: cardNodeMinus1_Minus1OverviewHover.hovered ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15) : Qt.rgba(255, 255, 255, 0.06)
                            border.color: cardNodeMinus1_Minus1OverviewHover.hovered ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.40) : Qt.rgba(255, 255, 255, 0.12)
                            border.width: 1

                            HoverHandler { id: cardNodeMinus1_Minus1OverviewHover }
                            Text {
                                id: cardNodeMinus1_Minus1OverviewBtnText
                                anchors.centerIn: parent
                                text: "Overview [ESC]"
                                font.family: Theme.fontMono || "monospace"
                                font.pixelSize: Theme.fontPx(9)
                                font.bold: true
                                color: cardNodeMinus1_Minus1OverviewHover.hovered ? Theme.primary : Theme.fgDim
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: spatialCanvasWindow.zoomToOverview()
                            }
                        }
                    }

                    // Inner Content Container: Opacity 1.0 AT ALL TIMES!
                    Item {
                        id: cardNodeMinus1_Minus1Inner
                        anchors.fill: parent
                        anchors.margins: Theme.px(16)
                        anchors.topMargin: Theme.px(48)
                        clip: true
                        opacity: 1.0
                        z: 2

                        RowLayout {
                            anchors.fill: parent
                            spacing: Theme.px(14)

                            // ─────────────────────────────────────────────────────────────
                            // LEFT PANE (45% width): Active Connection Card
                            // ─────────────────────────────────────────────────────────────
                            Rectangle {
                                Layout.preferredWidth: Math.round(parent.width * 0.45)
                                Layout.fillHeight: true
                                radius: Theme.px(10)
                                color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.04)
                                border.color: Qt.rgba(255, 255, 255, 0.08)
                                border.width: 1

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: Theme.px(14)
                                    spacing: Theme.px(12)

                                    RowLayout {
                                        spacing: Theme.px(8)
                                        Text {
                                            text: (typeof WifiController !== "undefined" && WifiController && WifiController.currentSsid.length > 0) ? "wifi" : "wifi_off"
                                            font.family: Theme.fontIcon
                                            font.pixelSize: Theme.fontPx(32)
                                            color: (typeof WifiController !== "undefined" && WifiController && WifiController.currentSsid.length > 0) ? Theme.primary : Theme.fgDim
                                        }
                                        ColumnLayout {
                                            spacing: Theme.px(2)
                                            Text {
                                                text: (typeof WifiController !== "undefined" && WifiController && WifiController.currentSsid.length > 0) ? WifiController.currentSsid : "Disconnected"
                                                font.family: Theme.font
                                                font.pixelSize: Theme.fontPx(14)
                                                font.bold: true
                                                color: Theme.fg
                                                elide: Text.ElideRight
                                            }
                                            Text {
                                                text: (typeof WifiController !== "undefined" && WifiController && WifiController.currentSsid.length > 0) ? "Connected • Active" : "No active connection"
                                                font.family: Theme.font
                                                font.pixelSize: Theme.fontPx(9.5)
                                                color: (typeof WifiController !== "undefined" && WifiController && WifiController.currentSsid.length > 0) ? Theme.primary : Theme.fgDim
                                            }
                                        }
                                    }

                                    // Signal meter
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: Theme.px(4)
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Text { text: "Signal Quality"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(9); color: Theme.fgDim }
                                            Item { Layout.fillWidth: true }
                                            Text {
                                                text: (typeof WifiController !== "undefined" && WifiController ? WifiController.currentSignal : 0) + "%"
                                                font.family: Theme.fontMono || "monospace"
                                                font.pixelSize: Theme.fontPx(9); font.bold: true
                                                color: Theme.primary
                                            }
                                        }
                                        Rectangle {
                                            Layout.fillWidth: true
                                            height: Theme.px(6)
                                            radius: Theme.px(3)
                                            color: Qt.rgba(255, 255, 255, 0.08)
                                            Rectangle {
                                                height: parent.height
                                                radius: parent.radius
                                                width: Math.round(parent.width * (typeof WifiController !== "undefined" && WifiController ? (WifiController.currentSignal / 100.0) : 0))
                                                color: Theme.primary
                                            }
                                        }
                                    }

                                    // Security readout
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text { text: "Security:"; font.family: Theme.font; font.pixelSize: Theme.fontPx(10); color: Theme.fgDim }
                                        Text {
                                            text: (typeof WifiController !== "undefined" && WifiController && WifiController.currentSecurity) ? WifiController.currentSecurity : "WPA2/WPA3 Personal"
                                            font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(9.5); color: Theme.fg
                                        }
                                    }

                                    Item { Layout.fillHeight: true }

                                    // Controls (Toggle / Disconnect)
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Theme.px(8)

                                        Rectangle {
                                            Layout.fillWidth: true
                                            height: Theme.px(30)
                                            radius: Theme.px(6)
                                            color: togHov.hovered ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.20) : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.10)
                                            border.color: Theme.primary
                                            border.width: 1

                                            HoverHandler { id: togHov }
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (typeof WifiController !== "undefined" && WifiController) {
                                                        WifiController.setEnabled(!WifiController.enabled);
                                                    }
                                                }
                                            }
                                            Text {
                                                anchors.centerIn: parent
                                                text: (typeof WifiController !== "undefined" && WifiController && WifiController.enabled) ? "Disable Wi-Fi" : "Enable Wi-Fi"
                                                font.family: Theme.font; font.pixelSize: Theme.fontPx(10.5); font.bold: true; color: Theme.primary
                                            }
                                        }

                                        Rectangle {
                                            Layout.fillWidth: true
                                            height: Theme.px(30)
                                            radius: Theme.px(6)
                                            visible: typeof WifiController !== "undefined" && WifiController && WifiController.currentSsid.length > 0
                                            color: discHov.hovered ? Qt.rgba(Theme.err.r, Theme.err.g, Theme.err.b, 0.25) : Qt.rgba(255, 255, 255, 0.06)
                                            border.color: discHov.hovered ? Theme.err : Qt.rgba(255, 255, 255, 0.12)
                                            border.width: 1

                                            HoverHandler { id: discHov }
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    if (typeof WifiController !== "undefined" && WifiController) {
                                                        WifiController.disconnectCurrent();
                                                    }
                                                }
                                            }
                                            Text {
                                                anchors.centerIn: parent
                                                text: "Disconnect"
                                                font.family: Theme.font; font.pixelSize: Theme.fontPx(10.5); font.bold: true
                                                color: discHov.hovered ? Theme.err : Theme.fgDim
                                            }
                                        }
                                    }
                                }
                            }

                            // ─────────────────────────────────────────────────────────────
                            // RIGHT PANE (55% width): Available Networks List
                            // ─────────────────────────────────────────────────────────────
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                spacing: Theme.px(8)

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text { text: "NEARBY NETWORKS"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(10); font.bold: true; color: Theme.primary }
                                    Item { Layout.fillWidth: true }
                                    Text {
                                        text: "RESCAN"
                                        font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(9); color: rescanHov.hovered ? Theme.primary : Theme.fgDim
                                        HoverHandler { id: rescanHov }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (typeof WifiController !== "undefined" && WifiController) WifiController.refreshNetworks(true)
                                            }
                                        }
                                    }
                                }

                                ListView {
                                    id: wifiListView
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    clip: true
                                    spacing: Theme.px(4)
                                    model: (typeof WifiController !== "undefined" && WifiController) ? WifiController.networks : []

                                    ScrollBar.vertical: ScrollBar {
                                        active: wifiListView.moving || wifiListView.dragging
                                        policy: ScrollBar.AsNeeded
                                    }

                                    delegate: Rectangle {
                                        width: wifiListView.width
                                        height: Theme.px(38)
                                        radius: Theme.px(6)
                                        color: netHov.hovered ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12) : Qt.rgba(255, 255, 255, 0.03)
                                        border.color: modelData.connected ? Theme.primary : (netHov.hovered ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.35) : Qt.rgba(255, 255, 255, 0.06))
                                        border.width: 1

                                        HoverHandler { id: netHov }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (typeof WifiController !== "undefined" && WifiController) {
                                                    WifiController.connectToNetwork(modelData.ssid);
                                                }
                                            }
                                        }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: Theme.px(8)
                                            anchors.rightMargin: Theme.px(8)
                                            spacing: Theme.px(8)

                                            Text {
                                                text: modelData.signal > 60 ? "signal_wifi_4_bar" : (modelData.signal > 30 ? "network_wifi_3_bar" : "network_wifi_1_bar")
                                                font.family: Theme.fontIcon; font.pixelSize: Theme.fontPx(14); color: modelData.connected ? Theme.primary : Theme.fgDim
                                            }

                                            Text {
                                                Layout.fillWidth: true
                                                text: modelData.ssid
                                                font.family: Theme.font; font.pixelSize: Theme.fontPx(11); font.bold: modelData.connected; color: modelData.connected ? Theme.primary : Theme.fg
                                                elide: Text.ElideRight
                                            }

                                            Text {
                                                visible: !!(modelData && modelData.secure)
                                                text: "lock"
                                                font.family: Theme.fontIcon; font.pixelSize: Theme.fontPx(12); color: Theme.fgDim
                                            }

                                            Text {
                                                text: modelData.signal + "%"
                                                font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(8.5); color: Theme.fgDim
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Transparent click interceptor when card is NOT focused
                    MouseArea {
                        anchors.fill: parent
                        z: 90
                        enabled: viewport.isOverview || (!cardNodeMinus1_Minus1.isCurrentTarget)
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            spatialCanvasWindow.zoomToNode(cardNodeMinus1_Minus1.nodeX, cardNodeMinus1_Minus1.nodeY)
                        }
                    }
                }
                // ══════════════════════════════════════════════════════════
                // NODE (0, -1) :: QUICK FILE BROWSER
                // ══════════════════════════════════════════════════════════
                Rectangle {
                    id: cardNode0_Minus1
                    readonly property int nodeX: 0
                    readonly property int nodeY: -1
                    readonly property bool isCurrentTarget: (spatialCanvasWindow.activeGridX === cardNode0_Minus1.nodeX && spatialCanvasWindow.activeGridY === cardNode0_Minus1.nodeY)
                    readonly property string cardIcon: "folder"
                    readonly property string cardTitle: "Quick File Browser"
                    readonly property string cardSubtitle: "Filesystem Navigation & Storage Capacity"

                    width: viewport.cardWidth
                    height: viewport.cardHeight
                    x: Math.round((viewport.width - width) / 2 + (cardNode0_Minus1.nodeX * viewport.stepX))
                    y: Math.round((viewport.height - height) / 2 + (cardNode0_Minus1.nodeY * viewport.stepY))
                    radius: 22

                    // Matugen-tinted frosted glass surface
                    color: Qt.rgba(Theme.surface.r * 0.8 + Theme.primary.r * 0.2, Theme.surface.g * 0.8 + Theme.primary.g * 0.2, Theme.surface.b * 0.8 + Theme.primary.b * 0.2, 0.78)
                    border.width: cardNode0_Minus1.isCurrentTarget && !viewport.isOverview ? 1.5 : 1
                    border.color: (cardNode0_Minus1Hover.hovered || cardNode0_Minus1.isCurrentTarget) ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.55) : Qt.rgba(1, 1, 1, 0.08)
                    clip: true

                    HoverHandler { id: cardNode0_Minus1Hover }

                    // Top Specular Highlight Line
                    Rectangle {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: Theme.px(22)
                        anchors.rightMargin: Theme.px(22)
                        height: 1
                        color: Qt.rgba(255, 255, 255, 0.18)
                        z: 5
                    }

                    // Inner Soft Top-Left Gradient Overlay
                    Rectangle {
                        anchors.fill: parent
                        radius: 22
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12) }
                            GradientStop { position: 1.0; color: "transparent" }
                        }
                        opacity: 0.85
                        z: 1
                    }

                    // Corner Crosshairs for tech / OS aesthetic
                    Text { text: "+"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(11); font.bold: true; color: cardNode0_Minus1.isCurrentTarget ? Theme.primary : Qt.rgba(Theme.fgDim.r, Theme.fgDim.g, Theme.fgDim.b, 0.35); anchors.left: parent.left; anchors.top: parent.top; anchors.margins: Theme.px(10); z: 10 }
                    Text { text: "+"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(11); font.bold: true; color: cardNode0_Minus1.isCurrentTarget ? Theme.primary : Qt.rgba(Theme.fgDim.r, Theme.fgDim.g, Theme.fgDim.b, 0.35); anchors.right: parent.right; anchors.top: parent.top; anchors.margins: Theme.px(10); z: 10 }
                    Text { text: "+"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(11); font.bold: true; color: cardNode0_Minus1.isCurrentTarget ? Theme.primary : Qt.rgba(Theme.fgDim.r, Theme.fgDim.g, Theme.fgDim.b, 0.35); anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: Theme.px(10); z: 10 }
                    Text { text: "+"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(11); font.bold: true; color: cardNode0_Minus1.isCurrentTarget ? Theme.primary : Qt.rgba(Theme.fgDim.r, Theme.fgDim.g, Theme.fgDim.b, 0.35); anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: Theme.px(10); z: 10 }

                    // Modern Unified Header Bar
                    RowLayout {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.topMargin: Theme.px(14)
                        anchors.leftMargin: Theme.px(22)
                        anchors.rightMargin: Theme.px(22)
                        height: Theme.px(28)
                        spacing: Theme.px(10)
                        z: 10

                        // Glowing Matugen Accent Dot
                        Rectangle {
                            Layout.preferredWidth: Theme.px(8)
                            Layout.preferredHeight: Theme.px(8)
                            radius: Theme.px(4)
                            color: cardNode0_Minus1.isCurrentTarget ? Theme.primary : Qt.rgba(Theme.fgDim.r, Theme.fgDim.g, Theme.fgDim.b, 0.50)

                            Rectangle {
                                anchors.centerIn: parent
                                width: Theme.px(14)
                                height: Theme.px(14)
                                radius: Theme.px(7)
                                color: cardNode0_Minus1.isCurrentTarget ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.25) : "transparent"
                                z: -1
                            }
                        }

                        Text {
                            text: cardNode0_Minus1.cardIcon
                            font.family: Theme.fontIcon
                            font.pixelSize: Theme.fontPx(16)
                            color: cardNode0_Minus1.isCurrentTarget ? Theme.primary : Theme.fgDim
                        }

                        // Bold Title
                        Text {
                            text: cardNode0_Minus1.cardTitle
                            font.family: Theme.font
                            font.pixelSize: Theme.fontPx(13.5)
                            font.weight: Font.Bold
                            color: cardNode0_Minus1.isCurrentTarget ? Theme.fg : Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.75)
                        }

                        // Muted Subtitle Pill
                        Rectangle {
                            Layout.preferredHeight: Theme.px(18)
                            Layout.preferredWidth: cardNode0_Minus1SubText.implicitWidth + Theme.px(12)
                            radius: Theme.px(9)
                            color: Qt.rgba(255, 255, 255, 0.05)
                            border.color: Qt.rgba(255, 255, 255, 0.08)
                            border.width: 1

                            Text {
                                id: cardNode0_Minus1SubText
                                anchors.centerIn: parent
                                text: cardNode0_Minus1.cardSubtitle
                                font.family: Theme.fontMono || "monospace"
                                font.pixelSize: Theme.fontPx(8.5)
                                color: Theme.fgDim
                            }
                        }

                        Item { Layout.fillWidth: true }

                        // Sleek rounded pill button for Overview [ESC]
                        Rectangle {
                            visible: cardNode0_Minus1.isCurrentTarget && !spatialCanvasWindow.isOverview
                            Layout.preferredHeight: Theme.px(22)
                            Layout.preferredWidth: cardNode0_Minus1OverviewBtnText.implicitWidth + Theme.px(16)
                            radius: Theme.px(11)
                            color: cardNode0_Minus1OverviewHover.hovered ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15) : Qt.rgba(255, 255, 255, 0.06)
                            border.color: cardNode0_Minus1OverviewHover.hovered ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.40) : Qt.rgba(255, 255, 255, 0.12)
                            border.width: 1

                            HoverHandler { id: cardNode0_Minus1OverviewHover }
                            Text {
                                id: cardNode0_Minus1OverviewBtnText
                                anchors.centerIn: parent
                                text: "Overview [ESC]"
                                font.family: Theme.fontMono || "monospace"
                                font.pixelSize: Theme.fontPx(9)
                                font.bold: true
                                color: cardNode0_Minus1OverviewHover.hovered ? Theme.primary : Theme.fgDim
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: spatialCanvasWindow.zoomToOverview()
                            }
                        }
                    }

                    // Inner Content Container: Opacity 1.0 AT ALL TIMES!
                    Item {
                        id: cardNode0_Minus1Inner
                        anchors.fill: parent
                        anchors.margins: Theme.px(16)
                        anchors.topMargin: Theme.px(48)
                        clip: true
                        opacity: 1.0
                        z: 2

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: Theme.px(8)

                            // Top Breadcrumb & Actions Bar
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.px(8)

                                Rectangle {
                                    Layout.preferredHeight: Theme.px(26)
                                    Layout.preferredWidth: Theme.px(26)
                                    radius: Theme.px(4)
                                    color: upHov.hovered ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.20) : Qt.rgba(255, 255, 255, 0.05)
                                    border.color: Qt.rgba(255, 255, 255, 0.10)
                                    border.width: 1

                                    HoverHandler { id: upHov }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            var cur = spatialCanvasWindow.currentBrowserPath;
                                            var parentPath = cur.substring(0, cur.lastIndexOf("/")) || "/";
                                            spatialCanvasWindow.currentBrowserPath = parentPath;
                                        }
                                    }
                                    Text { anchors.centerIn: parent; text: "arrow_upward"; font.family: Theme.fontIcon; font.pixelSize: Theme.fontPx(13); color: Theme.primary }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: Theme.px(26)
                                    radius: Theme.px(4)
                                    color: Qt.rgba(255, 255, 255, 0.04)
                                    border.color: Qt.rgba(255, 255, 255, 0.08)
                                    border.width: 1

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: Theme.px(8)
                                        anchors.rightMargin: Theme.px(8)
                                        spacing: Theme.px(6)
                                        Text { text: "folder_open"; font.family: Theme.fontIcon; font.pixelSize: Theme.fontPx(13); color: Theme.primary }
                                        Text {
                                            Layout.fillWidth: true
                                            text: spatialCanvasWindow.currentBrowserPath
                                            font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(10); color: Theme.fg
                                            elide: Text.ElideMiddle
                                        }
                                    }
                                }

                                Rectangle {
                                    Layout.preferredHeight: Theme.px(26)
                                    Layout.preferredWidth: openExternText.implicitWidth + Theme.px(14)
                                    radius: Theme.px(4)
                                    color: openExtHov.hovered ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.20) : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.10)
                                    border.color: Theme.primary
                                    border.width: 1

                                    HoverHandler { id: openExtHov }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            spatialCanvasWindow.execCommand("xdg-open \"" + spatialCanvasWindow.currentBrowserPath + "\"");
                                            spatialCanvasWindow.closeRequested();
                                        }
                                    }
                                    Text {
                                        id: openExternText
                                        anchors.centerIn: parent
                                        text: "OPEN IN FM"
                                        font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(8.5); font.bold: true; color: Theme.primary
                                    }
                                }
                            }

                            // Main Layout: Quick Places + File Grid
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                spacing: Theme.px(12)

                                // Quick Places (24% width)
                                ColumnLayout {
                                    Layout.preferredWidth: Math.round(parent.width * 0.24)
                                    Layout.fillHeight: true
                                    spacing: Theme.px(4)

                                    Text { text: "QUICK PLACES"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(9); font.bold: true; color: Theme.primary }

                                    Repeater {
                                        model: [
                                            { name: "Home", path: (Quickshell.env("HOME") || "/home/shogun"), icon: "home" },
                                            { name: "Desktop", path: (Quickshell.env("HOME") || "/home/shogun") + "/Desktop", icon: "desktop_windows" },
                                            { name: "Downloads", path: (Quickshell.env("HOME") || "/home/shogun") + "/Downloads", icon: "download" },
                                            { name: "Documents", path: (Quickshell.env("HOME") || "/home/shogun") + "/Documents", icon: "description" },
                                            { name: "Pictures", path: (Quickshell.env("HOME") || "/home/shogun") + "/Pictures", icon: "photo" },
                                            { name: ".config", path: (Quickshell.env("HOME") || "/home/shogun") + "/.config", icon: "settings" }
                                        ]

                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: Theme.px(28)
                                            radius: Theme.px(4)
                                            readonly property bool isCur: (spatialCanvasWindow.currentBrowserPath === modelData.path)
                                            color: isCur ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.16) : (plHov.hovered ? Qt.rgba(255, 255, 255, 0.06) : "transparent")
                                            border.color: isCur ? Theme.primary : "transparent"
                                            border.width: 1

                                            HoverHandler { id: plHov }
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: spatialCanvasWindow.currentBrowserPath = modelData.path
                                            }

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: Theme.px(8)
                                                spacing: Theme.px(6)
                                                Text { text: modelData.icon; font.family: Theme.fontIcon; font.pixelSize: Theme.fontPx(13); color: isCur ? Theme.primary : Theme.fgDim }
                                                Text { text: modelData.name; font.family: Theme.font; font.pixelSize: Theme.fontPx(10.5); font.bold: isCur; color: isCur ? Theme.fg : Theme.fgDim }
                                            }
                                        }
                                    }

                                    Item { Layout.fillHeight: true }

                                    // Storage meter
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: Theme.px(3)
                                        Text { text: spatialCanvasWindow.storageUsageText; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(8); color: Theme.fgDim }
                                        Rectangle {
                                            Layout.fillWidth: true
                                            height: Theme.px(4)
                                            radius: Theme.px(2)
                                            color: Qt.rgba(255, 255, 255, 0.08)
                                            Rectangle {
                                                height: parent.height
                                                radius: parent.radius
                                                width: Math.round(parent.width * spatialCanvasWindow.storageUsageFraction)
                                                color: Theme.primary
                                            }
                                        }
                                    }
                                }

                                // 5-Column Grid of Folders / Files (76% width)
                                GridView {
                                    id: fileGridView
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    clip: true
                                    cellWidth: Math.floor(width / 5)
                                    cellHeight: Theme.px(70)
                                    model: spatialCanvasWindow.currentBrowserFiles

                                    ScrollBar.vertical: ScrollBar {
                                        active: fileGridView.moving || fileGridView.dragging
                                        policy: ScrollBar.AsNeeded
                                    }

                                    delegate: Rectangle {
                                        width: fileGridView.cellWidth - Theme.px(6)
                                        height: fileGridView.cellHeight - Theme.px(6)
                                        radius: Theme.px(6)
                                        color: fHov.hovered ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12) : Qt.rgba(255, 255, 255, 0.03)
                                        border.color: fHov.hovered ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.35) : Qt.rgba(255, 255, 255, 0.06)
                                        border.width: 1

                                        HoverHandler { id: fHov }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (modelData.isDir) {
                                                    var cur = spatialCanvasWindow.currentBrowserPath;
                                                    spatialCanvasWindow.currentBrowserPath = (cur === "/" ? "" : cur) + "/" + modelData.name;
                                                } else {
                                                    var full = spatialCanvasWindow.currentBrowserPath + "/" + modelData.name;
                                                    spatialCanvasWindow.execCommand("xdg-open \"" + full + "\"");
                                                    spatialCanvasWindow.closeRequested();
                                                }
                                            }
                                        }

                                        ColumnLayout {
                                            anchors.centerIn: parent
                                            width: parent.width - Theme.px(8)
                                            spacing: Theme.px(2)

                                            Text {
                                                Layout.alignment: Qt.AlignHCenter
                                                text: modelData.isDir ? "folder" : "description"
                                                font.family: Theme.fontIcon
                                                font.pixelSize: Theme.fontPx(22)
                                                color: modelData.isDir ? Theme.primary : Theme.fgDim
                                            }

                                            Text {
                                                Layout.fillWidth: true
                                                text: modelData.name
                                                font.family: Theme.font
                                                font.pixelSize: Theme.fontPx(9.5)
                                                font.bold: modelData.isDir
                                                color: fHov.hovered ? Theme.primary : Theme.fg
                                                horizontalAlignment: Text.AlignHCenter
                                                elide: Text.ElideMiddle
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Transparent click interceptor when card is NOT focused
                    MouseArea {
                        anchors.fill: parent
                        z: 90
                        enabled: viewport.isOverview || (!cardNode0_Minus1.isCurrentTarget)
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            spatialCanvasWindow.zoomToNode(cardNode0_Minus1.nodeX, cardNode0_Minus1.nodeY)
                        }
                    }
                }
                // ══════════════════════════════════════════════════════════
                // NODE (1, -1) :: WEATHER & ATMOSPHERE
                // ══════════════════════════════════════════════════════════
                Rectangle {
                    id: cardNode1_Minus1
                    readonly property int nodeX: 1
                    readonly property int nodeY: -1
                    readonly property bool isCurrentTarget: (spatialCanvasWindow.activeGridX === cardNode1_Minus1.nodeX && spatialCanvasWindow.activeGridY === cardNode1_Minus1.nodeY)
                    readonly property string cardIcon: "wb_sunny"
                    readonly property string cardTitle: "Weather & Atmosphere"
                    readonly property string cardSubtitle: "Current Temperature & 7-Day Forecast"

                    width: viewport.cardWidth
                    height: viewport.cardHeight
                    x: Math.round((viewport.width - width) / 2 + (cardNode1_Minus1.nodeX * viewport.stepX))
                    y: Math.round((viewport.height - height) / 2 + (cardNode1_Minus1.nodeY * viewport.stepY))
                    radius: 22

                    // Matugen-tinted frosted glass surface
                    color: Qt.rgba(Theme.surface.r * 0.8 + Theme.primary.r * 0.2, Theme.surface.g * 0.8 + Theme.primary.g * 0.2, Theme.surface.b * 0.8 + Theme.primary.b * 0.2, 0.78)
                    border.width: cardNode1_Minus1.isCurrentTarget && !viewport.isOverview ? 1.5 : 1
                    border.color: (cardNode1_Minus1Hover.hovered || cardNode1_Minus1.isCurrentTarget) ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.55) : Qt.rgba(1, 1, 1, 0.08)
                    clip: true

                    HoverHandler { id: cardNode1_Minus1Hover }

                    // Top Specular Highlight Line
                    Rectangle {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: Theme.px(22)
                        anchors.rightMargin: Theme.px(22)
                        height: 1
                        color: Qt.rgba(255, 255, 255, 0.18)
                        z: 5
                    }

                    // Inner Soft Top-Left Gradient Overlay
                    Rectangle {
                        anchors.fill: parent
                        radius: 22
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12) }
                            GradientStop { position: 1.0; color: "transparent" }
                        }
                        opacity: 0.85
                        z: 1
                    }

                    // Corner Crosshairs for tech / OS aesthetic
                    Text { text: "+"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(11); font.bold: true; color: cardNode1_Minus1.isCurrentTarget ? Theme.primary : Qt.rgba(Theme.fgDim.r, Theme.fgDim.g, Theme.fgDim.b, 0.35); anchors.left: parent.left; anchors.top: parent.top; anchors.margins: Theme.px(10); z: 10 }
                    Text { text: "+"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(11); font.bold: true; color: cardNode1_Minus1.isCurrentTarget ? Theme.primary : Qt.rgba(Theme.fgDim.r, Theme.fgDim.g, Theme.fgDim.b, 0.35); anchors.right: parent.right; anchors.top: parent.top; anchors.margins: Theme.px(10); z: 10 }
                    Text { text: "+"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(11); font.bold: true; color: cardNode1_Minus1.isCurrentTarget ? Theme.primary : Qt.rgba(Theme.fgDim.r, Theme.fgDim.g, Theme.fgDim.b, 0.35); anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: Theme.px(10); z: 10 }
                    Text { text: "+"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(11); font.bold: true; color: cardNode1_Minus1.isCurrentTarget ? Theme.primary : Qt.rgba(Theme.fgDim.r, Theme.fgDim.g, Theme.fgDim.b, 0.35); anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: Theme.px(10); z: 10 }

                    // Modern Unified Header Bar
                    RowLayout {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.topMargin: Theme.px(14)
                        anchors.leftMargin: Theme.px(22)
                        anchors.rightMargin: Theme.px(22)
                        height: Theme.px(28)
                        spacing: Theme.px(10)
                        z: 10

                        // Glowing Matugen Accent Dot
                        Rectangle {
                            Layout.preferredWidth: Theme.px(8)
                            Layout.preferredHeight: Theme.px(8)
                            radius: Theme.px(4)
                            color: cardNode1_Minus1.isCurrentTarget ? Theme.primary : Qt.rgba(Theme.fgDim.r, Theme.fgDim.g, Theme.fgDim.b, 0.50)

                            Rectangle {
                                anchors.centerIn: parent
                                width: Theme.px(14)
                                height: Theme.px(14)
                                radius: Theme.px(7)
                                color: cardNode1_Minus1.isCurrentTarget ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.25) : "transparent"
                                z: -1
                            }
                        }

                        Text {
                            text: cardNode1_Minus1.cardIcon
                            font.family: Theme.fontIcon
                            font.pixelSize: Theme.fontPx(16)
                            color: cardNode1_Minus1.isCurrentTarget ? Theme.primary : Theme.fgDim
                        }

                        // Bold Title
                        Text {
                            text: cardNode1_Minus1.cardTitle
                            font.family: Theme.font
                            font.pixelSize: Theme.fontPx(13.5)
                            font.weight: Font.Bold
                            color: cardNode1_Minus1.isCurrentTarget ? Theme.fg : Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.75)
                        }

                        // Muted Subtitle Pill
                        Rectangle {
                            Layout.preferredHeight: Theme.px(18)
                            Layout.preferredWidth: cardNode1_Minus1SubText.implicitWidth + Theme.px(12)
                            radius: Theme.px(9)
                            color: Qt.rgba(255, 255, 255, 0.05)
                            border.color: Qt.rgba(255, 255, 255, 0.08)
                            border.width: 1

                            Text {
                                id: cardNode1_Minus1SubText
                                anchors.centerIn: parent
                                text: cardNode1_Minus1.cardSubtitle
                                font.family: Theme.fontMono || "monospace"
                                font.pixelSize: Theme.fontPx(8.5)
                                color: Theme.fgDim
                            }
                        }

                        Item { Layout.fillWidth: true }

                        // Sleek rounded pill button for Overview [ESC]
                        Rectangle {
                            visible: cardNode1_Minus1.isCurrentTarget && !spatialCanvasWindow.isOverview
                            Layout.preferredHeight: Theme.px(22)
                            Layout.preferredWidth: cardNode1_Minus1OverviewBtnText.implicitWidth + Theme.px(16)
                            radius: Theme.px(11)
                            color: cardNode1_Minus1OverviewHover.hovered ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15) : Qt.rgba(255, 255, 255, 0.06)
                            border.color: cardNode1_Minus1OverviewHover.hovered ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.40) : Qt.rgba(255, 255, 255, 0.12)
                            border.width: 1

                            HoverHandler { id: cardNode1_Minus1OverviewHover }
                            Text {
                                id: cardNode1_Minus1OverviewBtnText
                                anchors.centerIn: parent
                                text: "Overview [ESC]"
                                font.family: Theme.fontMono || "monospace"
                                font.pixelSize: Theme.fontPx(9)
                                font.bold: true
                                color: cardNode1_Minus1OverviewHover.hovered ? Theme.primary : Theme.fgDim
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: spatialCanvasWindow.zoomToOverview()
                            }
                        }
                    }

                    // Inner Content Container: Opacity 1.0 AT ALL TIMES!
                    Item {
                        id: cardNode1_Minus1Inner
                        anchors.fill: parent
                        anchors.margins: Theme.px(16)
                        anchors.topMargin: Theme.px(48)
                        clip: true
                        opacity: 1.0
                        z: 2

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: Theme.px(10)

                            // Top Hero Card: Current Weather
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Math.round(parent.height * 0.40)
                                radius: Theme.px(10)
                                color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.08)
                                border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.20)
                                border.width: 1

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: Theme.px(16)
                                    spacing: Theme.px(16)

                                    Text {
                                        text: spatialCanvasWindow.resolveWeatherIcon(spatialCanvasWindow.weatherDesc)
                                        font.family: Theme.fontIcon
                                        font.pixelSize: Theme.fontPx(52)
                                        color: Theme.primary
                                    }

                                    ColumnLayout {
                                        spacing: Theme.px(2)
                                        Text {
                                            text: spatialCanvasWindow.weatherTemp || "23°C"
                                            font.family: Theme.font
                                            font.pixelSize: Theme.fontPx(38)
                                            font.bold: true
                                            color: Theme.fg
                                        }
                                        Text {
                                            text: (spatialCanvasWindow.weatherDesc || "Clear Sky") + " • Feels like " + (spatialCanvasWindow.weatherFeelsLike || spatialCanvasWindow.weatherTemp || "23°C")
                                            font.family: Theme.font
                                            font.pixelSize: Theme.fontPx(11)
                                            color: Theme.fgDim
                                        }
                                        Text {
                                            text: (spatialCanvasWindow.weatherCity || "Patna") + ", Live Atmosphere"
                                            font.family: Theme.fontMono || "monospace"
                                            font.pixelSize: Theme.fontPx(9.5)
                                            color: Theme.primary
                                        }
                                    }

                                    Item { Layout.fillWidth: true }

                                    Rectangle {
                                        Layout.preferredHeight: Theme.px(28)
                                        Layout.preferredWidth: Theme.px(28)
                                        radius: Theme.px(14)
                                        color: rHov.hovered ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.25) : Qt.rgba(255, 255, 255, 0.06)
                                        border.color: Theme.primary
                                        border.width: 1

                                        HoverHandler { id: rHov }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: spatialCanvasWindow.refreshWeather()
                                        }
                                        Text { anchors.centerIn: parent; text: "refresh"; font.family: Theme.fontIcon; font.pixelSize: Theme.fontPx(14); color: Theme.primary }
                                    }
                                }
                            }

                            // Bottom Area: 7-Day Forecast + Atmosphere Grid
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                spacing: Theme.px(12)

                                // 7-Day Forecast (55% width)
                                ColumnLayout {
                                    Layout.preferredWidth: Math.round(parent.width * 0.55)
                                    Layout.fillHeight: true
                                    spacing: Theme.px(4)

                                    Text { text: "7-DAY EXTENDED FORECAST"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(9.5); font.bold: true; color: Theme.primary }

                                    ListView {
                                        id: forecastListView
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        clip: true
                                        spacing: Theme.px(3)
                                        model: (spatialCanvasWindow.weatherForecastList && spatialCanvasWindow.weatherForecastList.length > 0) ? spatialCanvasWindow.weatherForecastList : [
                                            { day: "Today", desc: "Overcast", temp_range: "22° - 29°", icon: "cloud" },
                                            { day: "Thu", desc: "Mainly Clear", temp_range: "20° - 29°", icon: "wb_sunny" },
                                            { day: "Fri", desc: "Clear", temp_range: "18° - 28°", icon: "wb_sunny" },
                                            { day: "Sat", desc: "Clear", temp_range: "18° - 28°", icon: "wb_sunny" },
                                            { day: "Sun", desc: "Clear", temp_range: "18° - 28°", icon: "wb_sunny" },
                                            { day: "Mon", desc: "Foggy", temp_range: "18° - 28°", icon: "foggy" }
                                        ]

                                        delegate: Rectangle {
                                            width: forecastListView.width
                                            height: Theme.px(26)
                                            radius: Theme.px(4)
                                            color: Qt.rgba(255, 255, 255, 0.03)

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: Theme.px(8)
                                                anchors.rightMargin: Theme.px(8)
                                                spacing: Theme.px(8)

                                                Text { text: modelData.day; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(10); font.bold: true; color: Theme.fg; Layout.preferredWidth: Theme.px(44) }
                                                Text { text: spatialCanvasWindow.resolveWeatherIcon(modelData.desc || ""); font.family: Theme.fontIcon; font.pixelSize: Theme.fontPx(12); color: Theme.primary }
                                                Text { text: modelData.desc || ""; font.family: Theme.font; font.pixelSize: Theme.fontPx(9.5); color: Theme.fgDim; Layout.fillWidth: true; elide: Text.ElideRight }
                                                Text { text: modelData.temp_range || (modelData.temp_min + "° - " + modelData.temp_max + "°"); font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(9); color: Theme.primary }
                                            }
                                        }
                                    }
                                }

                                // 2x2 Atmosphere Metric Cards (45% width)
                                GridLayout {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    columns: 2
                                    columnSpacing: Theme.px(8)
                                    rowSpacing: Theme.px(8)

                                    Repeater {
                                        model: [
                                            { label: "WIND SPEED", val: spatialCanvasWindow.weatherWind, icon: "air" },
                                            { label: "HUMIDITY", val: spatialCanvasWindow.weatherHumidity, icon: "water_drop" },
                                            { label: "UV INDEX", val: "Moderate (4)", icon: "wb_sunny" },
                                            { label: "PRESSURE", val: "1014 hPa", icon: "compress" }
                                        ]

                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            radius: Theme.px(8)
                                            color: Qt.rgba(255, 255, 255, 0.04)
                                            border.color: Qt.rgba(255, 255, 255, 0.08)
                                            border.width: 1

                                            ColumnLayout {
                                                anchors.centerIn: parent
                                                spacing: Theme.px(3)
                                                Text { Layout.alignment: Qt.AlignHCenter; text: modelData.icon; font.family: Theme.fontIcon; font.pixelSize: Theme.fontPx(18); color: Theme.primary }
                                                Text { Layout.alignment: Qt.AlignHCenter; text: modelData.val; font.family: Theme.font; font.pixelSize: Theme.fontPx(12); font.bold: true; color: Theme.fg }
                                                Text { Layout.alignment: Qt.AlignHCenter; text: modelData.label; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(8); color: Theme.fgDim }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Transparent click interceptor when card is NOT focused
                    MouseArea {
                        anchors.fill: parent
                        z: 90
                        enabled: viewport.isOverview || (!cardNode1_Minus1.isCurrentTarget)
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            spatialCanvasWindow.zoomToNode(cardNode1_Minus1.nodeX, cardNode1_Minus1.nodeY)
                        }
                    }
                }
                // ══════════════════════════════════════════════════════════
                // NODE (-1, 1) :: ARCH SYSTEM UPDATER
                // ══════════════════════════════════════════════════════════
                Rectangle {
                    id: cardNodeMinus1_1
                    readonly property int nodeX: -1
                    readonly property int nodeY: 1
                    readonly property bool isCurrentTarget: (spatialCanvasWindow.activeGridX === cardNodeMinus1_1.nodeX && spatialCanvasWindow.activeGridY === cardNodeMinus1_1.nodeY)
                    readonly property string cardIcon: "system_update"
                    readonly property string cardTitle: "Arch System Updater"
                    readonly property string cardSubtitle: "Pacman Package Audit & Kernel State"

                    width: viewport.cardWidth
                    height: viewport.cardHeight
                    x: Math.round((viewport.width - width) / 2 + (cardNodeMinus1_1.nodeX * viewport.stepX))
                    y: Math.round((viewport.height - height) / 2 + (cardNodeMinus1_1.nodeY * viewport.stepY))
                    radius: 22

                    // Matugen-tinted frosted glass surface
                    color: Qt.rgba(Theme.surface.r * 0.8 + Theme.primary.r * 0.2, Theme.surface.g * 0.8 + Theme.primary.g * 0.2, Theme.surface.b * 0.8 + Theme.primary.b * 0.2, 0.78)
                    border.width: cardNodeMinus1_1.isCurrentTarget && !viewport.isOverview ? 1.5 : 1
                    border.color: (cardNodeMinus1_1Hover.hovered || cardNodeMinus1_1.isCurrentTarget) ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.55) : Qt.rgba(1, 1, 1, 0.08)
                    clip: true

                    HoverHandler { id: cardNodeMinus1_1Hover }

                    // Top Specular Highlight Line
                    Rectangle {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: Theme.px(22)
                        anchors.rightMargin: Theme.px(22)
                        height: 1
                        color: Qt.rgba(255, 255, 255, 0.18)
                        z: 5
                    }

                    // Inner Soft Top-Left Gradient Overlay
                    Rectangle {
                        anchors.fill: parent
                        radius: 22
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12) }
                            GradientStop { position: 1.0; color: "transparent" }
                        }
                        opacity: 0.85
                        z: 1
                    }

                    // Corner Crosshairs for tech / OS aesthetic
                    Text { text: "+"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(11); font.bold: true; color: cardNodeMinus1_1.isCurrentTarget ? Theme.primary : Qt.rgba(Theme.fgDim.r, Theme.fgDim.g, Theme.fgDim.b, 0.35); anchors.left: parent.left; anchors.top: parent.top; anchors.margins: Theme.px(10); z: 10 }
                    Text { text: "+"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(11); font.bold: true; color: cardNodeMinus1_1.isCurrentTarget ? Theme.primary : Qt.rgba(Theme.fgDim.r, Theme.fgDim.g, Theme.fgDim.b, 0.35); anchors.right: parent.right; anchors.top: parent.top; anchors.margins: Theme.px(10); z: 10 }
                    Text { text: "+"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(11); font.bold: true; color: cardNodeMinus1_1.isCurrentTarget ? Theme.primary : Qt.rgba(Theme.fgDim.r, Theme.fgDim.g, Theme.fgDim.b, 0.35); anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: Theme.px(10); z: 10 }
                    Text { text: "+"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(11); font.bold: true; color: cardNodeMinus1_1.isCurrentTarget ? Theme.primary : Qt.rgba(Theme.fgDim.r, Theme.fgDim.g, Theme.fgDim.b, 0.35); anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: Theme.px(10); z: 10 }

                    // Modern Unified Header Bar
                    RowLayout {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.topMargin: Theme.px(14)
                        anchors.leftMargin: Theme.px(22)
                        anchors.rightMargin: Theme.px(22)
                        height: Theme.px(28)
                        spacing: Theme.px(10)
                        z: 10

                        // Glowing Matugen Accent Dot
                        Rectangle {
                            Layout.preferredWidth: Theme.px(8)
                            Layout.preferredHeight: Theme.px(8)
                            radius: Theme.px(4)
                            color: cardNodeMinus1_1.isCurrentTarget ? Theme.primary : Qt.rgba(Theme.fgDim.r, Theme.fgDim.g, Theme.fgDim.b, 0.50)

                            Rectangle {
                                anchors.centerIn: parent
                                width: Theme.px(14)
                                height: Theme.px(14)
                                radius: Theme.px(7)
                                color: cardNodeMinus1_1.isCurrentTarget ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.25) : "transparent"
                                z: -1
                            }
                        }

                        Text {
                            text: cardNodeMinus1_1.cardIcon
                            font.family: Theme.fontIcon
                            font.pixelSize: Theme.fontPx(16)
                            color: cardNodeMinus1_1.isCurrentTarget ? Theme.primary : Theme.fgDim
                        }

                        // Bold Title
                        Text {
                            text: cardNodeMinus1_1.cardTitle
                            font.family: Theme.font
                            font.pixelSize: Theme.fontPx(13.5)
                            font.weight: Font.Bold
                            color: cardNodeMinus1_1.isCurrentTarget ? Theme.fg : Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.75)
                        }

                        // Muted Subtitle Pill
                        Rectangle {
                            Layout.preferredHeight: Theme.px(18)
                            Layout.preferredWidth: cardNodeMinus1_1SubText.implicitWidth + Theme.px(12)
                            radius: Theme.px(9)
                            color: Qt.rgba(255, 255, 255, 0.05)
                            border.color: Qt.rgba(255, 255, 255, 0.08)
                            border.width: 1

                            Text {
                                id: cardNodeMinus1_1SubText
                                anchors.centerIn: parent
                                text: cardNodeMinus1_1.cardSubtitle
                                font.family: Theme.fontMono || "monospace"
                                font.pixelSize: Theme.fontPx(8.5)
                                color: Theme.fgDim
                            }
                        }

                        Item { Layout.fillWidth: true }

                        // Sleek rounded pill button for Overview [ESC]
                        Rectangle {
                            visible: cardNodeMinus1_1.isCurrentTarget && !spatialCanvasWindow.isOverview
                            Layout.preferredHeight: Theme.px(22)
                            Layout.preferredWidth: cardNodeMinus1_1OverviewBtnText.implicitWidth + Theme.px(16)
                            radius: Theme.px(11)
                            color: cardNodeMinus1_1OverviewHover.hovered ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15) : Qt.rgba(255, 255, 255, 0.06)
                            border.color: cardNodeMinus1_1OverviewHover.hovered ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.40) : Qt.rgba(255, 255, 255, 0.12)
                            border.width: 1

                            HoverHandler { id: cardNodeMinus1_1OverviewHover }
                            Text {
                                id: cardNodeMinus1_1OverviewBtnText
                                anchors.centerIn: parent
                                text: "Overview [ESC]"
                                font.family: Theme.fontMono || "monospace"
                                font.pixelSize: Theme.fontPx(9)
                                font.bold: true
                                color: cardNodeMinus1_1OverviewHover.hovered ? Theme.primary : Theme.fgDim
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: spatialCanvasWindow.zoomToOverview()
                            }
                        }
                    }

                    // Inner Content Container: Opacity 1.0 AT ALL TIMES!
                    Item {
                        id: cardNodeMinus1_1Inner
                        anchors.fill: parent
                        anchors.margins: Theme.px(16)
                        anchors.topMargin: Theme.px(48)
                        clip: true
                        opacity: 1.0
                        z: 2

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: Theme.px(12)

                            // Top Hero 3-Stat Row
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Theme.px(80)
                                spacing: Theme.px(10)

                                // Pending updates card
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: Theme.px(8)
                                    color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.10)
                                    border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.25)
                                    border.width: 1

                                    ColumnLayout {
                                        anchors.centerIn: parent
                                        spacing: Theme.px(2)
                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: String(spatialCanvasWindow.updaterStats.updates ? spatialCanvasWindow.updaterStats.updates.length : 0)
                                            font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(26); font.bold: true; color: Theme.primary
                                        }
                                        Text { Layout.alignment: Qt.AlignHCenter; text: "PENDING UPDATES"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(8.5); color: Theme.fg }
                                    }
                                }

                                // Total installed packages
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: Theme.px(8)
                                    color: Qt.rgba(255, 255, 255, 0.04)
                                    border.color: Qt.rgba(255, 255, 255, 0.08)
                                    border.width: 1

                                    ColumnLayout {
                                        anchors.centerIn: parent
                                        spacing: Theme.px(2)
                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: String(spatialCanvasWindow.updaterStats.total || "1222")
                                            font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(26); font.bold: true; color: Theme.fg
                                        }
                                        Text { Layout.alignment: Qt.AlignHCenter; text: "INSTALLED PACKAGES"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(8.5); color: Theme.fgDim }
                                    }
                                }

                                // Root Disk Usage
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: Theme.px(8)
                                    color: Qt.rgba(255, 255, 255, 0.04)
                                    border.color: Qt.rgba(255, 255, 255, 0.08)
                                    border.width: 1

                                    ColumnLayout {
                                        anchors.centerIn: parent
                                        spacing: Theme.px(4)
                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: (spatialCanvasWindow.updaterStats.disk_used || "81G") + " / " + (spatialCanvasWindow.updaterStats.disk_size || "109G")
                                            font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(14); font.bold: true; color: Theme.fg
                                        }
                                        Rectangle {
                                            Layout.preferredWidth: Theme.px(90)
                                            height: Theme.px(5)
                                            radius: Theme.px(2.5)
                                            color: Qt.rgba(255, 255, 255, 0.10)
                                            Rectangle {
                                                height: parent.height
                                                radius: parent.radius
                                                width: Math.round(parent.width * (parseInt(spatialCanvasWindow.updaterStats.disk_percent) || 74) / 100.0)
                                                color: Theme.primary
                                            }
                                        }
                                        Text { Layout.alignment: Qt.AlignHCenter; text: "ROOT DISK USAGE (" + (spatialCanvasWindow.updaterStats.disk_percent || "74%") + ")"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(8); color: Theme.fgDim }
                                    }
                                }
                            }

                            // Bottom List / Status
                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true

                                ColumnLayout {
                                    anchors.fill: parent
                                    spacing: Theme.px(8)

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text { text: "PENDING SYSTEM UPGRADES"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(10); font.bold: true; color: Theme.primary }
                                        Item { Layout.fillWidth: true }
                                        Text {
                                            text: "CHECK NOW"
                                            font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(9); color: checkHov.hovered ? Theme.primary : Theme.fgDim
                                            HoverHandler { id: checkHov }
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: spatialCanvasWindow.refreshUpdaterStats()
                                            }
                                        }
                                    }

                                    // If no updates:
                                    Rectangle {
                                        visible: !spatialCanvasWindow.updaterStats.updates || spatialCanvasWindow.updaterStats.updates.length === 0
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        radius: Theme.px(8)
                                        color: Qt.rgba(255, 255, 255, 0.02)
                                        border.color: Qt.rgba(255, 255, 255, 0.06)
                                        border.width: 1

                                        ColumnLayout {
                                            anchors.centerIn: parent
                                            spacing: Theme.px(6)
                                            Text { Layout.alignment: Qt.AlignHCenter; text: "verified"; font.family: Theme.fontIcon; font.pixelSize: Theme.fontPx(32); color: Theme.primary }
                                            Text { Layout.alignment: Qt.AlignHCenter; text: "System is Fully Up to Date"; font.family: Theme.font; font.pixelSize: Theme.fontPx(13); font.bold: true; color: Theme.fg }
                                            Text { Layout.alignment: Qt.AlignHCenter; text: "All core pacman repositories synchronized"; font.family: Theme.font; font.pixelSize: Theme.fontPx(9.5); color: Theme.fgDim }
                                        }
                                    }

                                    // If updates present:
                                    ListView {
                                        visible: spatialCanvasWindow.updaterStats.updates && spatialCanvasWindow.updaterStats.updates.length > 0
                                        id: updatesListView
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        clip: true
                                        spacing: Theme.px(4)
                                        model: spatialCanvasWindow.updaterStats.updates || []

                                        ScrollBar.vertical: ScrollBar {
                                            active: updatesListView.moving || updatesListView.dragging
                                            policy: ScrollBar.AsNeeded
                                        }

                                        delegate: Rectangle {
                                            width: updatesListView.width
                                            height: Theme.px(28)
                                            radius: Theme.px(4)
                                            color: Qt.rgba(255, 255, 255, 0.03)

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: Theme.px(8)
                                                anchors.rightMargin: Theme.px(8)
                                                spacing: Theme.px(8)

                                                Text { text: "system_update"; font.family: Theme.fontIcon; font.pixelSize: Theme.fontPx(13); color: Theme.primary }
                                                Text { text: modelData; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(10); color: Theme.fg; Layout.fillWidth: true; elide: Text.ElideRight }
                                            }
                                        }
                                    }

                                    // Update Button
                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: Theme.px(34)
                                        radius: Theme.px(6)
                                        color: upBtnHov.hovered ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.25) : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                                        border.color: Theme.primary
                                        border.width: 1

                                        HoverHandler { id: upBtnHov }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                spatialCanvasWindow.execCommand("kitty -e sudo pacman -Syu");
                                                spatialCanvasWindow.closeRequested();
                                            }
                                        }

                                        RowLayout {
                                            anchors.centerIn: parent
                                            spacing: Theme.px(6)
                                            Text { text: "rocket_launch"; font.family: Theme.fontIcon; font.pixelSize: Theme.fontPx(14); color: Theme.primary }
                                            Text { text: "UPDATE SYSTEM (SUDO PACMAN -SYU)"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(10); font.bold: true; color: Theme.primary }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Transparent click interceptor when card is NOT focused
                    MouseArea {
                        anchors.fill: parent
                        z: 90
                        enabled: viewport.isOverview || (!cardNodeMinus1_1.isCurrentTarget)
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            spatialCanvasWindow.zoomToNode(cardNodeMinus1_1.nodeX, cardNodeMinus1_1.nodeY)
                        }
                    }
                }
                // ══════════════════════════════════════════════════════════
                // NODE (0, 1) :: MEDIA & AUDIO STUDIO
                // ══════════════════════════════════════════════════════════
                Rectangle {
                    id: cardNode0_1
                    readonly property int nodeX: 0
                    readonly property int nodeY: 1
                    readonly property bool isCurrentTarget: (spatialCanvasWindow.activeGridX === cardNode0_1.nodeX && spatialCanvasWindow.activeGridY === cardNode0_1.nodeY)
                    readonly property string cardIcon: "equalizer"
                    readonly property string cardTitle: "Media & Audio Studio"
                    readonly property string cardSubtitle: "MPRIS Playback & Master PipeWire Output"

                    width: viewport.cardWidth
                    height: viewport.cardHeight
                    x: Math.round((viewport.width - width) / 2 + (cardNode0_1.nodeX * viewport.stepX))
                    y: Math.round((viewport.height - height) / 2 + (cardNode0_1.nodeY * viewport.stepY))
                    radius: 22

                    // Matugen-tinted frosted glass surface
                    color: Qt.rgba(Theme.surface.r * 0.8 + Theme.primary.r * 0.2, Theme.surface.g * 0.8 + Theme.primary.g * 0.2, Theme.surface.b * 0.8 + Theme.primary.b * 0.2, 0.78)
                    border.width: cardNode0_1.isCurrentTarget && !viewport.isOverview ? 1.5 : 1
                    border.color: (cardNode0_1Hover.hovered || cardNode0_1.isCurrentTarget) ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.55) : Qt.rgba(1, 1, 1, 0.08)
                    clip: true

                    HoverHandler { id: cardNode0_1Hover }

                    // Top Specular Highlight Line
                    Rectangle {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: Theme.px(22)
                        anchors.rightMargin: Theme.px(22)
                        height: 1
                        color: Qt.rgba(255, 255, 255, 0.18)
                        z: 5
                    }

                    // Inner Soft Top-Left Gradient Overlay
                    Rectangle {
                        anchors.fill: parent
                        radius: 22
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12) }
                            GradientStop { position: 1.0; color: "transparent" }
                        }
                        opacity: 0.85
                        z: 1
                    }

                    // Corner Crosshairs for tech / OS aesthetic
                    Text { text: "+"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(11); font.bold: true; color: cardNode0_1.isCurrentTarget ? Theme.primary : Qt.rgba(Theme.fgDim.r, Theme.fgDim.g, Theme.fgDim.b, 0.35); anchors.left: parent.left; anchors.top: parent.top; anchors.margins: Theme.px(10); z: 10 }
                    Text { text: "+"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(11); font.bold: true; color: cardNode0_1.isCurrentTarget ? Theme.primary : Qt.rgba(Theme.fgDim.r, Theme.fgDim.g, Theme.fgDim.b, 0.35); anchors.right: parent.right; anchors.top: parent.top; anchors.margins: Theme.px(10); z: 10 }
                    Text { text: "+"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(11); font.bold: true; color: cardNode0_1.isCurrentTarget ? Theme.primary : Qt.rgba(Theme.fgDim.r, Theme.fgDim.g, Theme.fgDim.b, 0.35); anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: Theme.px(10); z: 10 }
                    Text { text: "+"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(11); font.bold: true; color: cardNode0_1.isCurrentTarget ? Theme.primary : Qt.rgba(Theme.fgDim.r, Theme.fgDim.g, Theme.fgDim.b, 0.35); anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: Theme.px(10); z: 10 }

                    // Modern Unified Header Bar
                    RowLayout {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.topMargin: Theme.px(14)
                        anchors.leftMargin: Theme.px(22)
                        anchors.rightMargin: Theme.px(22)
                        height: Theme.px(28)
                        spacing: Theme.px(10)
                        z: 10

                        // Glowing Matugen Accent Dot
                        Rectangle {
                            Layout.preferredWidth: Theme.px(8)
                            Layout.preferredHeight: Theme.px(8)
                            radius: Theme.px(4)
                            color: cardNode0_1.isCurrentTarget ? Theme.primary : Qt.rgba(Theme.fgDim.r, Theme.fgDim.g, Theme.fgDim.b, 0.50)

                            Rectangle {
                                anchors.centerIn: parent
                                width: Theme.px(14)
                                height: Theme.px(14)
                                radius: Theme.px(7)
                                color: cardNode0_1.isCurrentTarget ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.25) : "transparent"
                                z: -1
                            }
                        }

                        Text {
                            text: cardNode0_1.cardIcon
                            font.family: Theme.fontIcon
                            font.pixelSize: Theme.fontPx(16)
                            color: cardNode0_1.isCurrentTarget ? Theme.primary : Theme.fgDim
                        }

                        // Bold Title
                        Text {
                            text: cardNode0_1.cardTitle
                            font.family: Theme.font
                            font.pixelSize: Theme.fontPx(13.5)
                            font.weight: Font.Bold
                            color: cardNode0_1.isCurrentTarget ? Theme.fg : Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.75)
                        }

                        // Muted Subtitle Pill
                        Rectangle {
                            Layout.preferredHeight: Theme.px(18)
                            Layout.preferredWidth: cardNode0_1SubText.implicitWidth + Theme.px(12)
                            radius: Theme.px(9)
                            color: Qt.rgba(255, 255, 255, 0.05)
                            border.color: Qt.rgba(255, 255, 255, 0.08)
                            border.width: 1

                            Text {
                                id: cardNode0_1SubText
                                anchors.centerIn: parent
                                text: cardNode0_1.cardSubtitle
                                font.family: Theme.fontMono || "monospace"
                                font.pixelSize: Theme.fontPx(8.5)
                                color: Theme.fgDim
                            }
                        }

                        Item { Layout.fillWidth: true }

                        // Sleek rounded pill button for Overview [ESC]
                        Rectangle {
                            visible: cardNode0_1.isCurrentTarget && !spatialCanvasWindow.isOverview
                            Layout.preferredHeight: Theme.px(22)
                            Layout.preferredWidth: cardNode0_1OverviewBtnText.implicitWidth + Theme.px(16)
                            radius: Theme.px(11)
                            color: cardNode0_1OverviewHover.hovered ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15) : Qt.rgba(255, 255, 255, 0.06)
                            border.color: cardNode0_1OverviewHover.hovered ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.40) : Qt.rgba(255, 255, 255, 0.12)
                            border.width: 1

                            HoverHandler { id: cardNode0_1OverviewHover }
                            Text {
                                id: cardNode0_1OverviewBtnText
                                anchors.centerIn: parent
                                text: "Overview [ESC]"
                                font.family: Theme.fontMono || "monospace"
                                font.pixelSize: Theme.fontPx(9)
                                font.bold: true
                                color: cardNode0_1OverviewHover.hovered ? Theme.primary : Theme.fgDim
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: spatialCanvasWindow.zoomToOverview()
                            }
                        }
                    }

                    // Inner Content Container: Opacity 1.0 AT ALL TIMES!
                    Item {
                        id: cardNode0_1Inner
                        anchors.fill: parent
                        anchors.margins: Theme.px(16)
                        anchors.topMargin: Theme.px(48)
                        clip: true
                        opacity: 1.0
                        z: 2

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: Theme.px(14)

                            // MPRIS Player Card
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Math.round(parent.height * 0.58)
                                radius: Theme.px(10)
                                color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.08)
                                border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.20)
                                border.width: 1

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: Theme.px(16)
                                    spacing: Theme.px(16)

                                    // Album art thumbnail
                                    Rectangle {
                                        Layout.preferredWidth: Theme.px(90)
                                        Layout.preferredHeight: Theme.px(90)
                                        radius: Theme.px(8)
                                        color: "#08090d"
                                        border.color: Qt.rgba(255, 255, 255, 0.10)
                                        border.width: 1
                                        clip: true

                                        Image {
                                            anchors.fill: parent
                                            source: (spatialCanvasWindow.activeMprisPlayer && spatialCanvasWindow.activeMprisPlayer.trackArtUrl) ? spatialCanvasWindow.activeMprisPlayer.trackArtUrl : ""
                                            fillMode: Image.PreserveAspectCrop
                                            visible: !!source
                                        }

                                        Text {
                                            anchors.centerIn: parent
                                            visible: !spatialCanvasWindow.activeMprisPlayer || !spatialCanvasWindow.activeMprisPlayer.trackArtUrl
                                            text: "music_note"
                                            font.family: Theme.fontIcon
                                            font.pixelSize: Theme.fontPx(36)
                                            color: Theme.primary
                                        }
                                    }

                                    // Track details & controls
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: Theme.px(6)

                                        Text {
                                            Layout.fillWidth: true
                                            text: (spatialCanvasWindow.activeMprisPlayer && spatialCanvasWindow.activeMprisPlayer.trackTitle) ? spatialCanvasWindow.activeMprisPlayer.trackTitle : "No Media Playing"
                                            font.family: Theme.font
                                            font.pixelSize: Theme.fontPx(14)
                                            font.bold: true
                                            color: Theme.fg
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: (spatialCanvasWindow.activeMprisPlayer && spatialCanvasWindow.activeMprisPlayer.trackArtist) ? spatialCanvasWindow.activeMprisPlayer.trackArtist : "MPRIS Audio Service"
                                            font.family: Theme.font
                                            font.pixelSize: Theme.fontPx(11)
                                            color: Theme.fgDim
                                            elide: Text.ElideRight
                                        }

                                        // Progress bar
                                        Rectangle {
                                            Layout.fillWidth: true
                                            height: Theme.px(4)
                                            radius: Theme.px(2)
                                            color: Qt.rgba(255, 255, 255, 0.10)

                                            Rectangle {
                                                height: parent.height
                                                radius: parent.radius
                                                width: Math.round(parent.width * 0.45)
                                                color: Theme.primary
                                            }
                                        }

                                        // Transport buttons
                                        RowLayout {
                                            spacing: Theme.px(12)

                                            Rectangle {
                                                width: Theme.px(30)
                                                height: Theme.px(30)
                                                radius: Theme.px(15)
                                                color: prevHov.hovered ? Qt.rgba(255, 255, 255, 0.12) : Qt.rgba(255, 255, 255, 0.05)
                                                HoverHandler { id: prevHov }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        if (spatialCanvasWindow.activeMprisPlayer) spatialCanvasWindow.activeMprisPlayer.previous();
                                                    }
                                                }
                                                Text { anchors.centerIn: parent; text: "skip_previous"; font.family: Theme.fontIcon; font.pixelSize: Theme.fontPx(16); color: Theme.fg }
                                            }

                                            Rectangle {
                                                width: Theme.px(36)
                                                height: Theme.px(36)
                                                radius: Theme.px(18)
                                                color: Theme.primary
                                                HoverHandler { id: playHov }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        if (spatialCanvasWindow.activeMprisPlayer) {
                                                            if (spatialCanvasWindow.activeMprisPlayer.playbackState === MprisPlaybackState.Playing) spatialCanvasWindow.activeMprisPlayer.pause();
                                                            else spatialCanvasWindow.activeMprisPlayer.play();
                                                        }
                                                    }
                                                }
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: (spatialCanvasWindow.activeMprisPlayer && spatialCanvasWindow.activeMprisPlayer.playbackState === MprisPlaybackState.Playing) ? "pause" : "play_arrow"
                                                    font.family: Theme.fontIcon
                                                    font.pixelSize: Theme.fontPx(20)
                                                    color: (Theme.m3onPrimary || Theme.accentFg || "#000000")
                                                }
                                            }

                                            Rectangle {
                                                width: Theme.px(30)
                                                height: Theme.px(30)
                                                radius: Theme.px(15)
                                                color: nextHov.hovered ? Qt.rgba(255, 255, 255, 0.12) : Qt.rgba(255, 255, 255, 0.05)
                                                HoverHandler { id: nextHov }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        if (spatialCanvasWindow.activeMprisPlayer) spatialCanvasWindow.activeMprisPlayer.next();
                                                    }
                                                }
                                                Text { anchors.centerIn: parent; text: "skip_next"; font.family: Theme.fontIcon; font.pixelSize: Theme.fontPx(16); color: Theme.fg }
                                            }
                                        }
                                    }
                                }
                            }

                            // PipeWire Master Output Mixer
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: Theme.px(10)
                                color: Qt.rgba(255, 255, 255, 0.04)
                                border.color: Qt.rgba(255, 255, 255, 0.08)
                                border.width: 1

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: Theme.px(16)
                                    spacing: Theme.px(8)

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text { text: "PIPEWIRE MASTER OUTPUT MIXER"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(9.5); font.bold: true; color: Theme.primary }
                                        Item { Layout.fillWidth: true }
                                        Text {
                                            text: spatialCanvasWindow.masterOutputMuted ? "MUTED" : Math.round(spatialCanvasWindow.masterOutputVolume * 100) + "%"
                                            font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(10); font.bold: true; color: spatialCanvasWindow.masterOutputMuted ? Theme.err : Theme.primary
                                        }
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Theme.px(12)

                                        Text {
                                            text: spatialCanvasWindow.masterOutputMuted ? "volume_off" : (spatialCanvasWindow.masterOutputVolume > 0.5 ? "volume_up" : "volume_down")
                                            font.family: Theme.fontIcon
                                            font.pixelSize: Theme.fontPx(22)
                                            color: spatialCanvasWindow.masterOutputMuted ? Theme.err : Theme.primary

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    spatialCanvasWindow.execCommand("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle");
                                                    spatialCanvasWindow.refreshVolume();
                                                }
                                            }
                                        }

                                        // Volume track
                                        Rectangle {
                                            id: volTrack
                                            Layout.fillWidth: true
                                            height: Theme.px(8)
                                            radius: Theme.px(4)
                                            color: Qt.rgba(255, 255, 255, 0.10)

                                            Rectangle {
                                                height: parent.height
                                                radius: parent.radius
                                                width: Math.round(parent.width * (spatialCanvasWindow.masterOutputMuted ? 0 : spatialCanvasWindow.masterOutputVolume))
                                                color: spatialCanvasWindow.masterOutputMuted ? Theme.err : Theme.primary
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: (mouse) => {
                                                    var frac = Math.max(0.0, Math.min(1.0, mouse.x / volTrack.width));
                                                    spatialCanvasWindow.masterOutputVolume = frac;
                                                    spatialCanvasWindow.execCommand("wpctl set-volume @DEFAULT_AUDIO_SINK@ " + frac.toFixed(2));
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Transparent click interceptor when card is NOT focused
                    MouseArea {
                        anchors.fill: parent
                        z: 90
                        enabled: viewport.isOverview || (!cardNode0_1.isCurrentTarget)
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            spatialCanvasWindow.zoomToNode(cardNode0_1.nodeX, cardNode0_1.nodeY)
                        }
                    }
                }
                // ══════════════════════════════════════════════════════════
                // NODE (1, 1) :: SESSION & POWER DECK
                // ══════════════════════════════════════════════════════════
                Rectangle {
                    id: cardNode1_1
                    readonly property int nodeX: 1
                    readonly property int nodeY: 1
                    readonly property bool isCurrentTarget: (spatialCanvasWindow.activeGridX === cardNode1_1.nodeX && spatialCanvasWindow.activeGridY === cardNode1_1.nodeY)
                    readonly property string cardIcon: "power_settings_new"
                    readonly property string cardTitle: "Session & Power Deck"
                    readonly property string cardSubtitle: "Digital Clock, System Uptime & Actions"

                    width: viewport.cardWidth
                    height: viewport.cardHeight
                    x: Math.round((viewport.width - width) / 2 + (cardNode1_1.nodeX * viewport.stepX))
                    y: Math.round((viewport.height - height) / 2 + (cardNode1_1.nodeY * viewport.stepY))
                    radius: 22

                    // Matugen-tinted frosted glass surface
                    color: Qt.rgba(Theme.surface.r * 0.8 + Theme.primary.r * 0.2, Theme.surface.g * 0.8 + Theme.primary.g * 0.2, Theme.surface.b * 0.8 + Theme.primary.b * 0.2, 0.78)
                    border.width: cardNode1_1.isCurrentTarget && !viewport.isOverview ? 1.5 : 1
                    border.color: (cardNode1_1Hover.hovered || cardNode1_1.isCurrentTarget) ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.55) : Qt.rgba(1, 1, 1, 0.08)
                    clip: true

                    HoverHandler { id: cardNode1_1Hover }

                    // Top Specular Highlight Line
                    Rectangle {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: Theme.px(22)
                        anchors.rightMargin: Theme.px(22)
                        height: 1
                        color: Qt.rgba(255, 255, 255, 0.18)
                        z: 5
                    }

                    // Inner Soft Top-Left Gradient Overlay
                    Rectangle {
                        anchors.fill: parent
                        radius: 22
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12) }
                            GradientStop { position: 1.0; color: "transparent" }
                        }
                        opacity: 0.85
                        z: 1
                    }

                    // Corner Crosshairs for tech / OS aesthetic
                    Text { text: "+"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(11); font.bold: true; color: cardNode1_1.isCurrentTarget ? Theme.primary : Qt.rgba(Theme.fgDim.r, Theme.fgDim.g, Theme.fgDim.b, 0.35); anchors.left: parent.left; anchors.top: parent.top; anchors.margins: Theme.px(10); z: 10 }
                    Text { text: "+"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(11); font.bold: true; color: cardNode1_1.isCurrentTarget ? Theme.primary : Qt.rgba(Theme.fgDim.r, Theme.fgDim.g, Theme.fgDim.b, 0.35); anchors.right: parent.right; anchors.top: parent.top; anchors.margins: Theme.px(10); z: 10 }
                    Text { text: "+"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(11); font.bold: true; color: cardNode1_1.isCurrentTarget ? Theme.primary : Qt.rgba(Theme.fgDim.r, Theme.fgDim.g, Theme.fgDim.b, 0.35); anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: Theme.px(10); z: 10 }
                    Text { text: "+"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(11); font.bold: true; color: cardNode1_1.isCurrentTarget ? Theme.primary : Qt.rgba(Theme.fgDim.r, Theme.fgDim.g, Theme.fgDim.b, 0.35); anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: Theme.px(10); z: 10 }

                    // Modern Unified Header Bar
                    RowLayout {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.topMargin: Theme.px(14)
                        anchors.leftMargin: Theme.px(22)
                        anchors.rightMargin: Theme.px(22)
                        height: Theme.px(28)
                        spacing: Theme.px(10)
                        z: 10

                        // Glowing Matugen Accent Dot
                        Rectangle {
                            Layout.preferredWidth: Theme.px(8)
                            Layout.preferredHeight: Theme.px(8)
                            radius: Theme.px(4)
                            color: cardNode1_1.isCurrentTarget ? Theme.primary : Qt.rgba(Theme.fgDim.r, Theme.fgDim.g, Theme.fgDim.b, 0.50)

                            Rectangle {
                                anchors.centerIn: parent
                                width: Theme.px(14)
                                height: Theme.px(14)
                                radius: Theme.px(7)
                                color: cardNode1_1.isCurrentTarget ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.25) : "transparent"
                                z: -1
                            }
                        }

                        Text {
                            text: cardNode1_1.cardIcon
                            font.family: Theme.fontIcon
                            font.pixelSize: Theme.fontPx(16)
                            color: cardNode1_1.isCurrentTarget ? Theme.primary : Theme.fgDim
                        }

                        // Bold Title
                        Text {
                            text: cardNode1_1.cardTitle
                            font.family: Theme.font
                            font.pixelSize: Theme.fontPx(13.5)
                            font.weight: Font.Bold
                            color: cardNode1_1.isCurrentTarget ? Theme.fg : Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.75)
                        }

                        // Muted Subtitle Pill
                        Rectangle {
                            Layout.preferredHeight: Theme.px(18)
                            Layout.preferredWidth: cardNode1_1SubText.implicitWidth + Theme.px(12)
                            radius: Theme.px(9)
                            color: Qt.rgba(255, 255, 255, 0.05)
                            border.color: Qt.rgba(255, 255, 255, 0.08)
                            border.width: 1

                            Text {
                                id: cardNode1_1SubText
                                anchors.centerIn: parent
                                text: cardNode1_1.cardSubtitle
                                font.family: Theme.fontMono || "monospace"
                                font.pixelSize: Theme.fontPx(8.5)
                                color: Theme.fgDim
                            }
                        }

                        Item { Layout.fillWidth: true }

                        // Sleek rounded pill button for Overview [ESC]
                        Rectangle {
                            visible: cardNode1_1.isCurrentTarget && !spatialCanvasWindow.isOverview
                            Layout.preferredHeight: Theme.px(22)
                            Layout.preferredWidth: cardNode1_1OverviewBtnText.implicitWidth + Theme.px(16)
                            radius: Theme.px(11)
                            color: cardNode1_1OverviewHover.hovered ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15) : Qt.rgba(255, 255, 255, 0.06)
                            border.color: cardNode1_1OverviewHover.hovered ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.40) : Qt.rgba(255, 255, 255, 0.12)
                            border.width: 1

                            HoverHandler { id: cardNode1_1OverviewHover }
                            Text {
                                id: cardNode1_1OverviewBtnText
                                anchors.centerIn: parent
                                text: "Overview [ESC]"
                                font.family: Theme.fontMono || "monospace"
                                font.pixelSize: Theme.fontPx(9)
                                font.bold: true
                                color: cardNode1_1OverviewHover.hovered ? Theme.primary : Theme.fgDim
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: spatialCanvasWindow.zoomToOverview()
                            }
                        }
                    }

                    // Inner Content Container: Opacity 1.0 AT ALL TIMES!
                    Item {
                        id: cardNode1_1Inner
                        anchors.fill: parent
                        anchors.margins: Theme.px(16)
                        anchors.topMargin: Theme.px(48)
                        clip: true
                        opacity: 1.0
                        z: 2

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: Theme.px(12)

                            // Hero Clock & System Uptime
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Math.round(parent.height * 0.44)
                                radius: Theme.px(10)
                                color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.08)
                                border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.20)
                                border.width: 1

                                ColumnLayout {
                                    anchors.centerIn: parent
                                    spacing: Theme.px(4)

                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: Qt.formatTime(new Date(), "HH:mm")
                                        font.family: Theme.fontMono || "monospace"
                                        font.pixelSize: Theme.fontPx(44)
                                        font.bold: true
                                        color: Theme.primary
                                    }

                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: Qt.formatDate(new Date(), "dddd, MMMM d, yyyy")
                                        font.family: Theme.font
                                        font.pixelSize: Theme.fontPx(12)
                                        font.bold: true
                                        color: Theme.fg
                                    }

                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: spatialCanvasWindow.systemUptime + " • shogun@Raid"
                                        font.family: Theme.fontMono || "monospace"
                                        font.pixelSize: Theme.fontPx(9.5)
                                        color: Theme.fgDim
                                    }
                                }
                            }

                            // 4 Power Actions Grid
                            GridLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                columns: 2
                                columnSpacing: Theme.px(10)
                                rowSpacing: Theme.px(10)

                                // 1. Lock Screen
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: Theme.px(8)
                                    color: p1Hov.hovered ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.16) : Qt.rgba(255, 255, 255, 0.04)
                                    border.color: p1Hov.hovered ? Theme.primary : Qt.rgba(255, 255, 255, 0.10)
                                    border.width: 1

                                    HoverHandler { id: p1Hov }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            spatialCanvasWindow.execCommand("hyprlock");
                                            spatialCanvasWindow.closeRequested();
                                        }
                                    }

                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: Theme.px(10)
                                        Text { text: "lock"; font.family: Theme.fontIcon; font.pixelSize: Theme.fontPx(22); color: Theme.primary }
                                        ColumnLayout {
                                            spacing: Theme.px(1)
                                            Text { text: "Lock Screen"; font.family: Theme.font; font.pixelSize: Theme.fontPx(12); font.bold: true; color: Theme.fg }
                                            Text { text: "Secure workstation"; font.family: Theme.font; font.pixelSize: Theme.fontPx(8.5); color: Theme.fgDim }
                                        }
                                    }
                                }

                                // 2. Suspend
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: Theme.px(8)
                                    color: p2Hov.hovered ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.16) : Qt.rgba(255, 255, 255, 0.04)
                                    border.color: p2Hov.hovered ? Theme.primary : Qt.rgba(255, 255, 255, 0.10)
                                    border.width: 1

                                    HoverHandler { id: p2Hov }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            spatialCanvasWindow.execCommand("systemctl suspend");
                                            spatialCanvasWindow.closeRequested();
                                        }
                                    }

                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: Theme.px(10)
                                        Text { text: "bedtime"; font.family: Theme.fontIcon; font.pixelSize: Theme.fontPx(22); color: Theme.primary }
                                        ColumnLayout {
                                            spacing: Theme.px(1)
                                            Text { text: "Suspend"; font.family: Theme.font; font.pixelSize: Theme.fontPx(12); font.bold: true; color: Theme.fg }
                                            Text { text: "Low power sleep"; font.family: Theme.font; font.pixelSize: Theme.fontPx(8.5); color: Theme.fgDim }
                                        }
                                    }
                                }

                                // 3. Reboot
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: Theme.px(8)
                                    color: p3Hov.hovered ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.16) : Qt.rgba(255, 255, 255, 0.04)
                                    border.color: p3Hov.hovered ? Theme.primary : Qt.rgba(255, 255, 255, 0.10)
                                    border.width: 1

                                    HoverHandler { id: p3Hov }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            spatialCanvasWindow.execCommand("systemctl reboot");
                                            spatialCanvasWindow.closeRequested();
                                        }
                                    }

                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: Theme.px(10)
                                        Text { text: "restart_alt"; font.family: Theme.fontIcon; font.pixelSize: Theme.fontPx(22); color: Theme.primary }
                                        ColumnLayout {
                                            spacing: Theme.px(1)
                                            Text { text: "Reboot"; font.family: Theme.font; font.pixelSize: Theme.fontPx(12); font.bold: true; color: Theme.fg }
                                            Text { text: "Restart system"; font.family: Theme.font; font.pixelSize: Theme.fontPx(8.5); color: Theme.fgDim }
                                        }
                                    }
                                }

                                // 4. Power Off
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: Theme.px(8)
                                    color: p4Hov.hovered ? Qt.rgba(Theme.err.r, Theme.err.g, Theme.err.b, 0.22) : Qt.rgba(255, 255, 255, 0.04)
                                    border.color: p4Hov.hovered ? Theme.err : Qt.rgba(255, 255, 255, 0.10)
                                    border.width: 1

                                    HoverHandler { id: p4Hov }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            spatialCanvasWindow.execCommand("systemctl poweroff");
                                            spatialCanvasWindow.closeRequested();
                                        }
                                    }

                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: Theme.px(10)
                                        Text { text: "power_settings_new"; font.family: Theme.fontIcon; font.pixelSize: Theme.fontPx(22); color: p4Hov.hovered ? Theme.err : Theme.fgDim }
                                        ColumnLayout {
                                            spacing: Theme.px(1)
                                            Text { text: "Power Off"; font.family: Theme.font; font.pixelSize: Theme.fontPx(12); font.bold: true; color: p4Hov.hovered ? Theme.err : Theme.fg }
                                            Text { text: "Shut down hardware"; font.family: Theme.font; font.pixelSize: Theme.fontPx(8.5); color: Theme.fgDim }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Transparent click interceptor when card is NOT focused
                    MouseArea {
                        anchors.fill: parent
                        z: 90
                        enabled: viewport.isOverview || (!cardNode1_1.isCurrentTarget)
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            spatialCanvasWindow.zoomToNode(cardNode1_1.nodeX, cardNode1_1.nodeY)
                        }
                    }
                }
                } // spatialWorld
            } // cameraZoomRig
        } // viewport
    } // container
}
