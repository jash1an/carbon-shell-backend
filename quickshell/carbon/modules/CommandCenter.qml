import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
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
    id: commandCenterWindow

    property bool isOpen: false
    property bool animatingOut: false
    signal closeRequested()
    signal animationFinished()

    property string barEdge: "top"
    property string barMode: "notch"
    readonly property bool isTopBarUp: barEdge !== "bottom"

    WlrLayershell.namespace: "carbon-command-center"
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
        onLoaded: commandCenterWindow.updateBarPos(barPosWatcher.text())
        onFileChanged: {
            reload()
            commandCenterWindow.updateBarPos(barPosWatcher.text())
        }
    }

    function updateBarPos(txt) {
        if (!txt) return
        try {
            var d = JSON.parse(txt)
            if (d.mainBarEdge) commandCenterWindow.barEdge = d.mainBarEdge
            else if (d.edge) commandCenterWindow.barEdge = d.edge
        } catch(e) {}
    }

    FileView {
        id: barModeWatcher
        path: (Quickshell.env("HOME") || "") + "/.config/carbon/carbon-bar-mode.json"
        watchChanges: true
        blockLoading: true
        printErrors: false
        onLoaded: commandCenterWindow.updateBarMode(barModeWatcher.text())
        onFileChanged: {
            reload()
            commandCenterWindow.updateBarMode(barModeWatcher.text())
        }
    }

    function updateBarMode(txt) {
        if (!txt) return
        try {
            var d = JSON.parse(txt)
            if (d.mode) commandCenterWindow.barMode = d.mode
            if (d.mainBarEdge) commandCenterWindow.barEdge = d.mainBarEdge
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
            viewport.zoomScale = 0.38
        } else {
            animatingOut = false
            closeAnimTimer.stop()
            rootOpacity = 1.0
            if (isOverview) {
                viewport.zoomScale = 0.85
                entranceTimer.restart()
            }
            commandCenterWindow.refreshWeather()
            calSyncProc.running = true
            centerKeyHandler.forceActiveFocus()
            if (radarEngineProc.running) {
                radarEngineProc.write("refresh\n")
            }
            streamAnim.restart()
        }
    }

    Timer {
        id: entranceTimer
        interval: 16
        onTriggered: {
            viewport.zoomScale = 0.38
        }
    }

    Timer {
        id: closeAnimTimer
        interval: 260
        onTriggered: {
            commandCenterWindow.animatingOut = false
            commandCenterWindow.animationFinished()
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
                    if (d.temp) commandCenterWindow.weatherTemp = d.temp
                    if (d.description) commandCenterWindow.weatherDesc = d.description
                    if (d.city) commandCenterWindow.weatherCity = d.city
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
                            if (d.temp) commandCenterWindow.weatherTemp = d.temp
                            if (d.condition) commandCenterWindow.weatherDesc = d.condition
                            else if (d.description) commandCenterWindow.weatherDesc = d.description
                            if (d.city) {
                                var c = d.city.split(",")[0].trim()
                                commandCenterWindow.weatherCity = c
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
        target: commandCenterWindow
        property: "streamPhase"
        from: 0.0
        to: 1.0
        duration: commandCenterWindow.telemetryTickInterval
        easing.type: Easing.Linear
        running: commandCenterWindow.isOpen && commandCenterWindow.currentChannel === "telemetry"
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
        if (commandCenterWindow.isOpen && commandCenterWindow.currentChannel === "telemetry") {
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
        onTriggered: commandCenterWindow.feedbackMessage = ""
    }

    function scrollGithubBottom() {
        githubUplinkView.contentY = Math.max(0, githubUplinkView.contentHeight - githubUplinkView.height)
    }

    function scrollGithubTop() {
        githubUplinkView.contentY = 0
    }

    function showFeedback(msg) {
        if (!msg || msg.indexOf("Opening URL") !== -1) return
        commandCenterWindow.feedbackMessage = msg
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
                    if (payload.workspaces !== undefined) commandCenterWindow.workspacesData = payload.workspaces
                    if (payload.active_workspace_id !== undefined) commandCenterWindow.activeWorkspaceId = payload.active_workspace_id
                    if (payload.vault !== undefined) commandCenterWindow.vaultItems = payload.vault
                    if (payload.clipboard !== undefined) commandCenterWindow.clipboardItems = payload.clipboard
                    if (payload.apps !== undefined) commandCenterWindow.appsItems = payload.apps
                    if (payload.agenda !== undefined) commandCenterWindow.agendaItems = payload.agenda
                    if (payload.github !== undefined) {
                        commandCenterWindow.githubPayload = payload.github
                        if (payload.github.feedback) {
                            commandCenterWindow.showFeedback(payload.github.feedback)
                        }
                    }
                    if (payload.telemetry !== undefined) {
                        commandCenterWindow.telemetryPayload = payload.telemetry
                        var cpu = payload.telemetry.cpu_usage || 0
                        var ram = (payload.telemetry.ram_total_bytes > 0) 
                            ? ((payload.telemetry.ram_used_bytes / payload.telemetry.ram_total_bytes) * 100) 
                            : 0
                        commandCenterWindow.pushTelemetryHistory(cpu, ram)
                    }
                    commandCenterWindow.engineConnected = true
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
                    commandCenterWindow.agendaItems = parsed
                }
            } catch(e) {}
        }
        onLoaded: {
            try {
                var parsed = JSON.parse(text())
                if (Array.isArray(parsed) && parsed.length > 0) {
                    commandCenterWindow.agendaItems = parsed
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
        commandCenterWindow.feedbackMessage = ""
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
            var ws = (commandCenterWindow.githubPayload && commandCenterWindow.githubPayload.workspace && commandCenterWindow.githubPayload.workspace.repo_name) ? (Theme.home + "/" + commandCenterWindow.githubPayload.workspace.repo_name) : (Theme.home + "/carbon-shell")
            execCommand("git -C \"" + ws + "\" push 2>/dev/null || true")
        }
        showFeedback("Syncing local workspace...")
    }

    function mergePullRequest(repo, prNumber) {
        if (!repo || !prNumber) return
        if (radarEngineProc.running) {
            radarEngineProc.write("MERGE_PR " + repo + " " + prNumber + "\n")
        }
        if (commandCenterWindow.githubPayload && commandCenterWindow.githubPayload.pull_requests) {
            var updatedPrs = []
            for (var i = 0; i < commandCenterWindow.githubPayload.pull_requests.length; i++) {
                var p = commandCenterWindow.githubPayload.pull_requests[i]
                if (p.number !== prNumber) updatedPrs.push(p)
            }
            commandCenterWindow.githubPayload.pull_requests = updatedPrs
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
        commandCenterWindow.refreshWeather()
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
            viewport.zoomScale = isOverview ? 0.38 : 1.0;
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
        viewport.zoomScale = 0.38;
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
        commandCenterWindow.closeRequested();
    }

    function moveGrid(dx, dy) {
        if (isOverview) {
            if (dx !== 0) {
                if (activeGridX === 0) activeGridX = dx;
                else if (activeGridX === -dx) activeGridX = 0;
                else if (activeGridX === dx) activeGridX = 0;
            }
            if (dy !== 0) {
                if (activeGridY === 0) activeGridY = dy;
                else if (activeGridY === -dy) activeGridY = 0;
                else if (activeGridY === dy) activeGridY = 0;
            }
        } else {
            var nx = activeGridX + dx;
            var ny = activeGridY + dy;
            if (isValidNode(nx, ny)) {
                activeGridX = nx;
                activeGridY = ny;
            } else if (isValidNode(nx, 0)) {
                activeGridX = nx;
                activeGridY = 0;
            } else if (isValidNode(0, ny)) {
                activeGridX = 0;
                activeGridY = ny;
            }
        }
    }

    function isValidNode(gx, gy) {
        if (gx === 0 && gy === 0) return true;
        if (gx === -1 && gy === 0) return true;
        if (gx === 1 && gy === 0) return true;
        if (gx === 0 && gy === -1) return true;
        if (gx === 0 && gy === 1) return true;
        return false;
    }

    function applyBarMode(mode) {
        execCommand("sh ~/.config/hypr/scripts/carbon-mode-keybinds.sh " + mode);
        commandCenterWindow.showFeedback("Switched to " + mode + " mode");
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
        opacity: commandCenterWindow.rootOpacity
        Behavior on opacity {
            NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
        }

        // ── Full-surface Keyboard Handler for Instant Navigation ──
        Item {
            id: centerKeyHandler
            anchors.fill: parent
            focus: commandCenterWindow.isOpen
            Keys.enabled: commandCenterWindow.isOpen
            Keys.priority: Keys.BeforeItem

            Keys.onPressed: (event) => {
                // Direct workspace switch via 1-9
                if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
                    var num = event.key - Qt.Key_0;
                    commandCenterWindow.switchToWorkspace(num);
                    event.accepted = true;
                    return;
                }

                if (event.key === Qt.Key_Escape) {
                    if (!commandCenterWindow.isOverview) {
                        commandCenterWindow.zoomToOverview();
                    } else {
                        commandCenterWindow.closeRequested();
                    }
                    event.accepted = true;
                    return;
                }

                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                    if (commandCenterWindow.isOverview) {
                        commandCenterWindow.zoomToNode(commandCenterWindow.activeGridX, commandCenterWindow.activeGridY);
                        event.accepted = true;
                        return;
                    }
                }

                if (event.key === Qt.Key_Up || event.key === Qt.Key_W) {
                    commandCenterWindow.moveGrid(0, -1);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Down || event.key === Qt.Key_S) {
                    commandCenterWindow.moveGrid(0, 1);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Left || event.key === Qt.Key_A) {
                    commandCenterWindow.moveGrid(-1, 0);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Right || event.key === Qt.Key_D) {
                    commandCenterWindow.moveGrid(1, 0);
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

            property alias activeX: commandCenterWindow.activeGridX
            property alias activeY: commandCenterWindow.activeGridY
            property alias isOverview: commandCenterWindow.isOverview
            property real zoomScale: 0.38

            readonly property real stepX: width * 0.82
            readonly property real stepY: height * 0.82
            readonly property real cardWidth: width * 0.72
            readonly property real cardHeight: height * 0.72

            // Background click & wheel controls
            MouseArea {
                anchors.fill: parent
                z: 0
                onClicked: {
                    if (!commandCenterWindow.isOverview) {
                        commandCenterWindow.zoomToOverview()
                    } else {
                        commandCenterWindow.closeRequested()
                    }
                }
                onWheel: (wheel) => {
                    if (wheel.angleDelta.y < 0) {
                        commandCenterWindow.zoomToOverview()
                    } else if (wheel.angleDelta.y > 0) {
                        commandCenterWindow.zoomToNode(commandCenterWindow.activeGridX, commandCenterWindow.activeGridY)
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

                    x: commandCenterWindow.isOverview ? (-commandCenterWindow.activeGridX * viewport.stepX * 0.12) : (-commandCenterWindow.activeGridX * viewport.stepX)
                    y: commandCenterWindow.isOverview ? (-commandCenterWindow.activeGridY * viewport.stepY * 0.12) : (-commandCenterWindow.activeGridY * viewport.stepY)

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
                Rectangle {
                    id: cardNodeCenter
                    readonly property int nodeX: 0
                    readonly property int nodeY: 0
                    readonly property bool isCurrentTarget: (commandCenterWindow.activeGridX === cardNodeCenter.nodeX && commandCenterWindow.activeGridY === cardNodeCenter.nodeY)
                    readonly property string cardTitle: "WORKSPACE BLUEPRINT SWITCHER"
                    readonly property string lodIcon: "grid_view"
                    readonly property string lodTitle: "WORKSPACE BLUEPRINT"
                    readonly property string lodSubtitle: "3x3 Virtual Desktops & Wireframe Monitor"

                    width: viewport.cardWidth
                    height: viewport.cardHeight
                    x: Math.round((viewport.width - width) / 2 + (cardNodeCenter.nodeX * viewport.stepX))
                    y: Math.round((viewport.height - height) / 2 + (cardNodeCenter.nodeY * viewport.stepY))
                    radius: 16
                    color: Qt.rgba(0.047, 0.055, 0.07, 0.82)
                    border.color: cardNodeCenter.isCurrentTarget ? "#8ee8a8" : ((commandCenterWindow.isOverview && cardNodeCenterClickArea.containsMouse) ? Qt.rgba(0.557, 0.91, 0.659, 0.6) : Qt.rgba(1, 1, 1, 0.12))
                    border.width: cardNodeCenter.isCurrentTarget ? 2 : 1
                    scale: (commandCenterWindow.isOverview && cardNodeCenterClickArea.containsMouse) ? 1.03 : 1.0
                    transformOrigin: Item.Center
                    Behavior on scale {
                        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                    }
                    clip: true

                    // Click interception for overview or peeking neighbor cards
                    MouseArea {
                        id: cardNodeCenterClickArea
                        anchors.fill: parent
                        enabled: commandCenterWindow.isOverview || (!cardNodeCenter.isCurrentTarget)
                        cursorShape: (commandCenterWindow.isOverview || !cardNodeCenter.isCurrentTarget) ? Qt.PointingHandCursor : Qt.ArrowCursor
                        hoverEnabled: true
                        z: 500
                        onClicked: {
                            commandCenterWindow.zoomToNode(cardNodeCenter.nodeX, cardNodeCenter.nodeY)
                        }
                    }

                    // Level-of-Detail (LOD) Watermark Overlay for Overview Mode
                    Item {
                        id: cardNodeCenterLodOverlay
                        anchors.fill: parent
                        z: 400
                        opacity: commandCenterWindow.isOverview ? 0.92 : 0.0
                        visible: opacity > 0.01
                        Behavior on opacity {
                            NumberAnimation { duration: 350; easing.type: Easing.OutCubic }
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: 16
                            color: Qt.rgba(0.04, 0.05, 0.07, 0.78)
                        }

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: Theme.px(10)

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: cardNodeCenter.lodIcon
                                font.family: Theme.fontIcon
                                font.pixelSize: Theme.fontPx(64)
                                color: cardNodeCenter.isCurrentTarget ? "#8ee8a8" : Qt.rgba(255, 255, 255, 0.90)
                            }

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: cardNodeCenter.lodTitle
                                font.family: Theme.fontMono || "monospace"
                                font.pixelSize: Theme.fontPx(20)
                                font.bold: true
                                color: cardNodeCenter.isCurrentTarget ? "#8ee8a8" : Theme.fg
                            }

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: cardNodeCenter.lodSubtitle
                                font.family: Theme.font
                                font.pixelSize: Theme.fontPx(13)
                                color: Theme.fgDim
                            }
                        }
                    }

                    // Corner brackets (+)
                    Text { text: "+"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(11); font.bold: true; color: cardNodeCenter.isCurrentTarget ? "#8ee8a8" : Qt.rgba(255,255,255,0.4); anchors.left: parent.left; anchors.top: parent.top; anchors.margins: Theme.px(8); z: 10 }
                    Text { text: "+"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(11); font.bold: true; color: cardNodeCenter.isCurrentTarget ? "#8ee8a8" : Qt.rgba(255,255,255,0.4); anchors.right: parent.right; anchors.top: parent.top; anchors.margins: Theme.px(8); z: 10 }
                    Text { text: "+"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(11); font.bold: true; color: cardNodeCenter.isCurrentTarget ? "#8ee8a8" : Qt.rgba(255,255,255,0.4); anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: Theme.px(8); z: 10 }
                    Text { text: "+"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(11); font.bold: true; color: cardNodeCenter.isCurrentTarget ? "#8ee8a8" : Qt.rgba(255,255,255,0.4); anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: Theme.px(8); z: 10 }

                    // Card Header Bar
                    RowLayout {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.topMargin: Theme.px(10)
                        anchors.leftMargin: Theme.px(20)
                        anchors.rightMargin: Theme.px(20)
                        height: Theme.px(24)
                        spacing: Theme.px(8)
                        z: 10

                        Text {
                            text: "// NODE [" + cardNodeCenter.nodeX + ", " + cardNodeCenter.nodeY + "] :: " + cardNodeCenter.cardTitle
                            font.family: Theme.fontMono || "monospace"
                            font.pixelSize: Theme.fontPx(11)
                            font.weight: Font.Bold
                            color: cardNodeCenter.isCurrentTarget ? "#8ee8a8" : Theme.fg
                        }

                        Item { Layout.fillWidth: true }

                        Rectangle {
                            visible: cardNodeCenter.isCurrentTarget && !commandCenterWindow.isOverview
                            Layout.preferredHeight: Theme.px(18)
                            Layout.preferredWidth: cardNodeCenterHintText.implicitWidth + Theme.px(12)
                            radius: Theme.px(4)
                            color: cardNodeCenterHintHover.hovered ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.12) : Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.05)
                            border.color: Qt.rgba(255, 255, 255, 0.15)
                            border.width: 1

                            HoverHandler { id: cardNodeCenterHintHover }
                            Text {
                                id: cardNodeCenterHintText
                                anchors.centerIn: parent
                                text: "OVERVIEW (ESC)"
                                font.family: Theme.fontMono || "monospace"
                                font.pixelSize: Theme.fontPx(8.5)
                                font.bold: true
                                color: Theme.fgDim
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: commandCenterWindow.zoomToOverview()
                            }
                        }
                    }

                Item {
                    anchors.fill: parent
                    anchors.margins: Theme.px(16)
                    anchors.topMargin: Theme.px(44)

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: Theme.px(10)

                        // 3x3 Grid of 9 Workspaces
                        GridLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            columns: 3
                            rows: 3
                            columnSpacing: Theme.px(10)
                            rowSpacing: Theme.px(10)

                            Repeater {
                                model: commandCenterWindow.getWorkspaces()

                                Rectangle {
                                    id: wsCard
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: Theme.px(8)
                                    color: modelData.is_active ? Qt.rgba(0.55, 0.91, 0.66, 0.10) : Qt.rgba(0.06, 0.08, 0.11, 0.85)
                                    border.color: modelData.is_active ? "#8ee8a8" : (tileHover.hovered ? Qt.rgba(0.55, 0.91, 0.66, 0.5) : Qt.rgba(255, 255, 255, 0.12))
                                    border.width: modelData.is_active ? 1.5 : 1
                                    clip: true

                                    HoverHandler { id: tileHover }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: commandCenterWindow.switchToWorkspace(modelData.id)
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

                                        Text {
                                            text: "WS " + (modelData.id < 10 ? "0" + modelData.id : modelData.id)
                                            font.family: Theme.fontMono || "monospace"
                                            font.pixelSize: Theme.fontPx(11)
                                            font.weight: Font.Bold
                                            color: modelData.is_active ? "#8ee8a8" : (tileHover.hovered ? "#8ee8a8" : Theme.fg)
                                        }

                                        Rectangle {
                                            visible: modelData.is_active
                                            width: Theme.px(6)
                                            height: Theme.px(6)
                                            radius: Theme.px(3)
                                            color: "#8ee8a8"
                                        }

                                        Item { Layout.fillWidth: true }

                                        Text {
                                            text: (modelData.windows ? modelData.windows.length : 0) + " WND"
                                            font.family: Theme.fontMono || "monospace"
                                            font.pixelSize: Theme.fontPx(9)
                                            color: Qt.rgba(Theme.fgDim.r, Theme.fgDim.g, Theme.fgDim.b, 0.6)
                                        }
                                    }

                                    // Blueprint Wireframe Canvas
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

                                        // Windows Wireframe Boxes
                                        Repeater {
                                            model: modelData.windows || []

                                            Rectangle {
                                                x: Math.round(modelData.at[0] * parent.width)
                                                y: Math.round(modelData.at[1] * parent.height)
                                                width: Math.max(Theme.px(22), Math.round(modelData.size[0] * parent.width))
                                                height: Math.max(Theme.px(14), Math.round(modelData.size[1] * parent.height))
                                                radius: Theme.px(3)
                                                color: modelData.is_focused ? Qt.rgba(0.55, 0.91, 0.66, 0.22) : Qt.rgba(255, 255, 255, 0.06)
                                                border.color: modelData.is_focused ? "#8ee8a8" : Qt.rgba(255, 255, 255, 0.35)
                                                border.width: 1
                                                clip: true

                                                RowLayout {
                                                    anchors.centerIn: parent
                                                    width: Math.min(implicitWidth, parent.width - Theme.px(4))
                                                    spacing: Theme.px(3)

                                                    Image {
                                                        visible: parent.parent.width > Theme.px(36) && parent.parent.height > Theme.px(22)
                                                        Layout.preferredWidth: Theme.px(12)
                                                        Layout.preferredHeight: Theme.px(12)
                                                        source: commandCenterWindow.resolveAppIcon(modelData.class)
                                                        sourceSize: Qt.size(24, 24)
                                                        fillMode: Image.PreserveAspectFit
                                                    }

                                                    Text {
                                                        text: modelData.class || modelData.title || ""
                                                        font.family: Theme.font
                                                        font.pixelSize: Theme.fontPx(8.5)
                                                        font.weight: Font.Medium
                                                        color: modelData.is_focused ? "#8ee8a8" : Qt.rgba(255, 255, 255, 0.85)
                                                        elide: Text.ElideRight
                                                        Layout.maximumWidth: parent.parent.width - (parent.parent.width > Theme.px(36) ? Theme.px(18) : Theme.px(4))
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
                }

                }

                // ══════════════════════════════════════════════════════════
                // NODE (-1, 0) :: LOCAL RADAR
                // ══════════════════════════════════════════════════════════
                Rectangle {
                    id: cardNodeLeft
                    readonly property int nodeX: -1
                    readonly property int nodeY: 0
                    readonly property bool isCurrentTarget: (commandCenterWindow.activeGridX === cardNodeLeft.nodeX && commandCenterWindow.activeGridY === cardNodeLeft.nodeY)
                    readonly property string cardTitle: "LOCAL RADAR (VAULT / AGENDA / APPS / CLIPBOARD)"
                    readonly property string lodIcon: "radar"
                    readonly property string lodTitle: "LOCAL RADAR"
                    readonly property string lodSubtitle: "Obsidian Vault, Agenda, Dock & Clipboard"

                    width: viewport.cardWidth
                    height: viewport.cardHeight
                    x: Math.round((viewport.width - width) / 2 + (cardNodeLeft.nodeX * viewport.stepX))
                    y: Math.round((viewport.height - height) / 2 + (cardNodeLeft.nodeY * viewport.stepY))
                    radius: 16
                    color: Qt.rgba(0.047, 0.055, 0.07, 0.82)
                    border.color: cardNodeLeft.isCurrentTarget ? "#8ee8a8" : ((commandCenterWindow.isOverview && cardNodeLeftClickArea.containsMouse) ? Qt.rgba(0.557, 0.91, 0.659, 0.6) : Qt.rgba(1, 1, 1, 0.12))
                    border.width: cardNodeLeft.isCurrentTarget ? 2 : 1
                    scale: (commandCenterWindow.isOverview && cardNodeLeftClickArea.containsMouse) ? 1.03 : 1.0
                    transformOrigin: Item.Center
                    Behavior on scale {
                        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                    }
                    clip: true

                    // Click interception for overview or peeking neighbor cards
                    MouseArea {
                        id: cardNodeLeftClickArea
                        anchors.fill: parent
                        enabled: commandCenterWindow.isOverview || (!cardNodeLeft.isCurrentTarget)
                        cursorShape: (commandCenterWindow.isOverview || !cardNodeLeft.isCurrentTarget) ? Qt.PointingHandCursor : Qt.ArrowCursor
                        hoverEnabled: true
                        z: 500
                        onClicked: {
                            commandCenterWindow.zoomToNode(cardNodeLeft.nodeX, cardNodeLeft.nodeY)
                        }
                    }

                    // Level-of-Detail (LOD) Watermark Overlay for Overview Mode
                    Item {
                        id: cardNodeLeftLodOverlay
                        anchors.fill: parent
                        z: 400
                        opacity: commandCenterWindow.isOverview ? 0.92 : 0.0
                        visible: opacity > 0.01
                        Behavior on opacity {
                            NumberAnimation { duration: 350; easing.type: Easing.OutCubic }
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: 16
                            color: Qt.rgba(0.04, 0.05, 0.07, 0.78)
                        }

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: Theme.px(10)

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: cardNodeLeft.lodIcon
                                font.family: Theme.fontIcon
                                font.pixelSize: Theme.fontPx(64)
                                color: cardNodeLeft.isCurrentTarget ? "#8ee8a8" : Qt.rgba(255, 255, 255, 0.90)
                            }

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: cardNodeLeft.lodTitle
                                font.family: Theme.fontMono || "monospace"
                                font.pixelSize: Theme.fontPx(20)
                                font.bold: true
                                color: cardNodeLeft.isCurrentTarget ? "#8ee8a8" : Theme.fg
                            }

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: cardNodeLeft.lodSubtitle
                                font.family: Theme.font
                                font.pixelSize: Theme.fontPx(13)
                                color: Theme.fgDim
                            }
                        }
                    }

                    // Corner brackets (+)
                    Text { text: "+"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(11); font.bold: true; color: cardNodeLeft.isCurrentTarget ? "#8ee8a8" : Qt.rgba(255,255,255,0.4); anchors.left: parent.left; anchors.top: parent.top; anchors.margins: Theme.px(8); z: 10 }
                    Text { text: "+"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(11); font.bold: true; color: cardNodeLeft.isCurrentTarget ? "#8ee8a8" : Qt.rgba(255,255,255,0.4); anchors.right: parent.right; anchors.top: parent.top; anchors.margins: Theme.px(8); z: 10 }
                    Text { text: "+"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(11); font.bold: true; color: cardNodeLeft.isCurrentTarget ? "#8ee8a8" : Qt.rgba(255,255,255,0.4); anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: Theme.px(8); z: 10 }
                    Text { text: "+"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(11); font.bold: true; color: cardNodeLeft.isCurrentTarget ? "#8ee8a8" : Qt.rgba(255,255,255,0.4); anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: Theme.px(8); z: 10 }

                    // Card Header Bar
                    RowLayout {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.topMargin: Theme.px(10)
                        anchors.leftMargin: Theme.px(20)
                        anchors.rightMargin: Theme.px(20)
                        height: Theme.px(24)
                        spacing: Theme.px(8)
                        z: 10

                        Text {
                            text: "// NODE [" + cardNodeLeft.nodeX + ", " + cardNodeLeft.nodeY + "] :: " + cardNodeLeft.cardTitle
                            font.family: Theme.fontMono || "monospace"
                            font.pixelSize: Theme.fontPx(11)
                            font.weight: Font.Bold
                            color: cardNodeLeft.isCurrentTarget ? "#8ee8a8" : Theme.fg
                        }

                        Item { Layout.fillWidth: true }

                        Rectangle {
                            visible: cardNodeLeft.isCurrentTarget && !commandCenterWindow.isOverview
                            Layout.preferredHeight: Theme.px(18)
                            Layout.preferredWidth: cardNodeLeftHintText.implicitWidth + Theme.px(12)
                            radius: Theme.px(4)
                            color: cardNodeLeftHintHover.hovered ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.12) : Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.05)
                            border.color: Qt.rgba(255, 255, 255, 0.15)
                            border.width: 1

                            HoverHandler { id: cardNodeLeftHintHover }
                            Text {
                                id: cardNodeLeftHintText
                                anchors.centerIn: parent
                                text: "OVERVIEW (ESC)"
                                font.family: Theme.fontMono || "monospace"
                                font.pixelSize: Theme.fontPx(8.5)
                                font.bold: true
                                color: Theme.fgDim
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: commandCenterWindow.zoomToOverview()
                            }
                        }
                    }

                    Item {
                        anchors.fill: parent
                        anchors.margins: Theme.px(16)
                        anchors.topMargin: Theme.px(44)

                        GridLayout {
                            anchors.fill: parent
                            columns: 2
                            rows: 2
                            columnSpacing: Theme.px(10)
                            rowSpacing: Theme.px(10)

                            // Tile 1: Obsidian Notes
                                            Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.035) : Qt.rgba(0, 0, 0, 0.03)
                    border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.12)
                    border.width: 1
                    radius: Theme.px(12)
                    clip: true

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.px(10)
                        spacing: Theme.px(6)

                        // Tile Header
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.px(6)

                            Image {
                                Layout.preferredWidth: Theme.px(16)
                                Layout.preferredHeight: Theme.px(16)
                                Layout.alignment: Qt.AlignVCenter
                                source: commandCenterWindow.resolveAppIcon("obsidian")
                                sourceSize: Qt.size(32, 32)
                                fillMode: Image.PreserveAspectFit
                            }

                            Text {
                                text: "Obsidian Notes"
                                Layout.alignment: Qt.AlignVCenter
                                font.family: Theme.font
                                font.pixelSize: Theme.fontPx(11)
                                font.weight: Font.DemiBold
                                color: Theme.fg
                            }

                            Item { Layout.fillWidth: true }

                            Rectangle {
                                Layout.preferredHeight: Theme.px(16)
                                Layout.preferredWidth: vCountText.implicitWidth + Theme.px(10)
                                radius: Theme.px(8)
                                color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.06)

                                Text {
                                    id: vCountText
                                    anchors.centerIn: parent
                                    text: commandCenterWindow.vaultItems.length
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontPx(9)
                                    font.weight: Font.Bold
                                    color: Theme.fgDim
                                }
                            }
                        }

                        // Notes ListView
                        ListView {
                            id: vaultListView
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            model: commandCenterWindow.vaultItems
                            spacing: Theme.px(2)

                            property bool scrollInitialized: false
                            Component.onCompleted: scrollInitialized = true
                            onContentYChanged: if (scrollInitialized) vaultScrollTimer.restart()

                            Timer {
                                id: vaultScrollTimer
                                interval: 700
                                running: false
                            }

                            ScrollBar.vertical: ScrollBar {
                                id: vaultScroll
                                policy: ScrollBar.AsNeeded
                                contentItem: Rectangle {
                                    implicitWidth: Theme.px(3)
                                    radius: Theme.px(2)
                                    color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.4)
                                    opacity: (vaultScroll.active || vaultScrollTimer.running) ? 1.0 : 0.0
                                    Behavior on opacity { NumberAnimation { duration: 200 } }
                                }
                            }

                            delegate: Item {
                                width: vaultListView.width
                                height: Theme.px(28)

                                HoverHandler { id: noteHover }

                                Rectangle {
                                    anchors.fill: parent
                                    radius: Theme.px(6)
                                    color: noteHover.hovered ? (Theme.isDark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(0, 0, 0, 0.06)) : "transparent"

                                    Behavior on color { ColorAnimation { duration: 120 } }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: Theme.px(6)
                                        anchors.rightMargin: Theme.px(6)
                                        spacing: Theme.px(8)

                                        Text {
                                            text: "draft"
                                            font.family: Theme.fontIcon
                                            font.pixelSize: Theme.fontPx(13)
                                            color: noteHover.hovered ? Theme.accent : Theme.fgDim
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.name
                                            elide: Text.ElideRight
                                            font.family: Theme.font
                                            font.pixelSize: Theme.fontPx(11)
                                            font.weight: noteHover.hovered ? Font.Medium : Font.Normal
                                            color: noteHover.hovered ? Theme.accentLit : Theme.fg
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: commandCenterWindow.openNote(modelData.path)
                                    }
                                }
                            }
                        }
                    }
                }



                            // Tile 2: Events / Schedule
                                            Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.035) : Qt.rgba(0, 0, 0, 0.03)
                    border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.12)
                    border.width: 1
                    radius: Theme.px(12)
                    clip: true

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.px(10)
                        spacing: Theme.px(6)

                        // Tile Header
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.px(6)

                            Text {
                                text: "calendar_today"
                                font.family: Theme.fontIcon
                                font.pixelSize: Theme.fontPx(14)
                                color: Theme.accent
                            }

                            Text {
                                text: "Events & Agenda"
                                font.family: Theme.font
                                font.pixelSize: Theme.fontPx(11)
                                font.weight: Font.DemiBold
                                color: Theme.fg
                            }

                            Item { Layout.fillWidth: true }

                            Rectangle {
                                Layout.preferredHeight: Theme.px(16)
                                Layout.preferredWidth: aCountText.implicitWidth + Theme.px(10)
                                radius: Theme.px(8)
                                color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.06)

                                Text {
                                    id: aCountText
                                    anchors.centerIn: parent
                                    text: commandCenterWindow.filteredAgenda.length
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontPx(9)
                                    font.weight: Font.Bold
                                    color: Theme.fgDim
                                }
                            }
                        }

                        // Agenda ListView
                        ListView {
                            id: agendaListView
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            model: commandCenterWindow.filteredAgenda
                            spacing: Theme.px(2)

                            property bool scrollInitialized: false
                            Component.onCompleted: scrollInitialized = true
                            onContentYChanged: if (scrollInitialized) agendaScrollTimer.restart()

                            Timer {
                                id: agendaScrollTimer
                                interval: 700
                                running: false
                            }

                            ScrollBar.vertical: ScrollBar {
                                id: agendaScroll
                                policy: ScrollBar.AsNeeded
                                contentItem: Rectangle {
                                    implicitWidth: Theme.px(3)
                                    radius: Theme.px(2)
                                    color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.4)
                                    opacity: (agendaScroll.active || agendaScrollTimer.running) ? 1.0 : 0.0
                                    Behavior on opacity { NumberAnimation { duration: 200 } }
                                }
                            }

                            delegate: Item {
                                width: agendaListView.width
                                height: Theme.px(28)

                                HoverHandler { id: aHover }

                                Rectangle {
                                    anchors.fill: parent
                                    radius: Theme.px(6)
                                    color: aHover.hovered ? (Theme.isDark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(0, 0, 0, 0.06)) : "transparent"

                                    Behavior on color { ColorAnimation { duration: 120 } }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: Theme.px(6)
                                        anchors.rightMargin: Theme.px(6)
                                        spacing: Theme.px(8)

                                        // Date Pill
                                        Rectangle {
                                            Layout.preferredHeight: Theme.px(18)
                                            Layout.preferredWidth: dText.implicitWidth + Theme.px(10)
                                            radius: Theme.px(4)
                                            color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18)
                                            border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.40)
                                            border.width: 1

                                            Text {
                                                id: dText
                                                anchors.centerIn: parent
                                                text: modelData.date
                                                font.family: Theme.font
                                                font.pixelSize: Theme.fontPx(9)
                                                font.weight: Font.Bold
                                                color: Theme.accent
                                            }
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: (modelData.icon ? (modelData.icon + " ") : "") + modelData.title
                                            elide: Text.ElideRight
                                            font.family: Theme.font
                                            font.pixelSize: Theme.fontPx(11)
                                            color: aHover.hovered ? Theme.fg : Theme.fgDim
                                        }
                                    }
                                }
                            }
                        }
                    }
                }


                            // Tile 3: Recent Apps Dock & Clock/Weather
                                            Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: Theme.px(6)

                        // ── Top: Dynamic Recent Apps Landscape Dock ──
                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Theme.px(40)
                            Layout.maximumHeight: Theme.px(40)

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.left: parent.left
                                height: Theme.px(36)
                                // Length dynamically hugs active apps (up to 8 max)
                                width: Math.min(parent.width, Math.max(Theme.px(42), commandCenterWindow.appsItems.length * Theme.px(32) + (commandCenterWindow.appsItems.length > 0 ? (commandCenterWindow.appsItems.length - 1) * Theme.px(3) : 0) + Theme.px(10)))

                                color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.035) : Qt.rgba(0, 0, 0, 0.03)
                                border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.12)
                                border.width: 1
                                radius: Theme.px(10)

                                Row {
                                    anchors.centerIn: parent
                                    spacing: Theme.px(3)

                                    Repeater {
                                        model: commandCenterWindow.appsItems

                                        delegate: Item {
                                            width: Theme.px(28)
                                            height: Theme.px(28)

                                            HoverHandler { id: appHover }

                                            Rectangle {
                                                id: iconBg
                                                anchors.centerIn: parent
                                                width: Theme.px(26)
                                                height: Theme.px(26)
                                                radius: Theme.px(6)
                                                color: appHover.hovered ? (Theme.isDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08)) : "transparent"
                                                scale: appHover.hovered ? 1.15 : 1.0

                                                Behavior on scale {
                                                    NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
                                                }
                                                Behavior on color {
                                                    ColorAnimation { duration: 120 }
                                                }

                                                Image {
                                                    id: appImg
                                                    anchors.centerIn: parent
                                                    width: Theme.px(18)
                                                    height: Theme.px(18)
                                                    source: commandCenterWindow.resolveAppIcon(modelData)
                                                    sourceSize: Qt.size(36, 36)
                                                    fillMode: Image.PreserveAspectFit
                                                    visible: status === Image.Ready
                                                }

                                                Text {
                                                    anchors.centerIn: parent
                                                    visible: appImg.status !== Image.Ready
                                                    text: "apps"
                                                    font.family: Theme.fontIcon
                                                    font.pixelSize: Theme.fontPx(16)
                                                    color: appHover.hovered ? Theme.accent : Theme.fgDim
                                                }

                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: commandCenterWindow.focusApp(modelData)
                                                }
                                            }

                                            // App Name Tooltip
                                            Rectangle {
                                                visible: appHover.hovered
                                                anchors.bottom: iconBg.top
                                                anchors.horizontalCenter: iconBg.horizontalCenter
                                                anchors.bottomMargin: Theme.px(4)
                                                width: appTipText.implicitWidth + Theme.px(10)
                                                height: Theme.px(18)
                                                radius: Theme.px(4)
                                                color: Qt.rgba(0, 0, 0, 0.88)
                                                border.color: Qt.rgba(1, 1, 1, 0.2)
                                                border.width: 1
                                                z: 100

                                                Text {
                                                    id: appTipText
                                                    anchors.centerIn: parent
                                                    text: {
                                                        var raw = modelData || ""
                                                        var parts = raw.split(".")
                                                        return parts[parts.length - 1]
                                                    }
                                                    font.family: Theme.font
                                                    font.pixelSize: Theme.fontPx(9)
                                                    color: Theme.fg
                                                }
                                            }
                                        }
                                    }
                                }

                                // Placeholder icon if no active apps detected
                                Text {
                                    anchors.centerIn: parent
                                    visible: commandCenterWindow.appsItems.length === 0
                                    text: "apps"
                                    font.family: Theme.fontIcon
                                    font.pixelSize: Theme.fontPx(16)
                                    color: Theme.fgDim
                                }
                            }
                        }

                        // ── Bottom: Aesthetic Floating Clock & Weather (Transparent, not in a tile) ──
                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: Theme.px(4)
                                spacing: Theme.px(6)

                                // Clock Section (Left)
                                Item {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true

                                    HoverHandler { id: clockHover }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            commandCenterWindow.use24h = !commandCenterWindow.use24h
                                            commandCenterWindow.showFeedback(commandCenterWindow.use24h ? "24-Hour Clock" : "12-Hour Clock")
                                        }
                                    }

                                    ColumnLayout {
                                        anchors.centerIn: parent
                                        spacing: Theme.px(2)

                                        RowLayout {
                                            Layout.alignment: Qt.AlignHCenter
                                            spacing: Theme.px(4)

                                            Text {
                                                text: Qt.formatDateTime(sysClock.date, commandCenterWindow.use24h ? "HH:mm" : "hh:mm")
                                                font.family: Theme.font
                                                font.pixelSize: Theme.fontPx(22)
                                                font.weight: Font.Bold
                                                color: clockHover.hovered ? Theme.accent : Theme.fg
                                                Behavior on color { ColorAnimation { duration: 120 } }
                                            }

                                            Rectangle {
                                                visible: !commandCenterWindow.use24h
                                                Layout.preferredHeight: Theme.px(16)
                                                Layout.preferredWidth: amPmText.implicitWidth + Theme.px(8)
                                                Layout.alignment: Qt.AlignVCenter
                                                radius: Theme.px(4)
                                                color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18)
                                                border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.40)
                                                border.width: 1

                                                Text {
                                                    id: amPmText
                                                    anchors.centerIn: parent
                                                    text: Qt.formatDateTime(sysClock.date, "AP")
                                                    font.family: Theme.font
                                                    font.pixelSize: Theme.fontPx(9)
                                                    font.weight: Font.Bold
                                                    color: Theme.accent
                                                }
                                            }
                                        }

                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: Qt.formatDateTime(sysClock.date, "dddd, MMM d")
                                            font.family: Theme.font
                                            font.pixelSize: Theme.fontPx(10)
                                            font.weight: Font.Medium
                                            color: Theme.fgDim
                                        }
                                    }
                                }

                                // Subtle Hairline Divider
                                Rectangle {
                                    Layout.preferredWidth: 1
                                    Layout.preferredHeight: Theme.px(34)
                                    Layout.alignment: Qt.AlignVCenter
                                    color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.15)
                                }

                                // Weather Section (Right)
                                Item {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true

                                    HoverHandler { id: weatherHover }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            commandCenterWindow.refreshWeather()
                                            commandCenterWindow.showFeedback("Refreshing Weather...")
                                        }
                                    }

                                    ColumnLayout {
                                        anchors.centerIn: parent
                                        spacing: Theme.px(2)

                                        RowLayout {
                                            Layout.alignment: Qt.AlignHCenter
                                            spacing: Theme.px(6)

                                            Text {
                                                text: commandCenterWindow.resolveWeatherIcon(commandCenterWindow.weatherDesc)
                                                font.family: Theme.fontIcon
                                                font.pixelSize: Theme.fontPx(20)
                                                color: Theme.accent
                                            }

                                            Text {
                                                text: commandCenterWindow.weatherTemp !== "" ? commandCenterWindow.weatherTemp : "--"
                                                font.family: Theme.font
                                                font.pixelSize: Theme.fontPx(18)
                                                font.weight: Font.Bold
                                                color: weatherHover.hovered ? Theme.accent : Theme.fg
                                                Behavior on color { ColorAnimation { duration: 120 } }
                                            }
                                        }

                                        RowLayout {
                                            Layout.alignment: Qt.AlignHCenter
                                            spacing: Theme.px(4)

                                            Text {
                                                text: commandCenterWindow.weatherDesc || "Clear Sky"
                                                font.family: Theme.font
                                                font.pixelSize: Theme.fontPx(10)
                                                font.weight: Font.Medium
                                                color: Theme.fgDim
                                                elide: Text.ElideRight
                                                Layout.maximumWidth: Theme.px(70)
                                            }

                                            Text {
                                                text: "•"
                                                font.family: Theme.font
                                                font.pixelSize: Theme.fontPx(9)
                                                color: Qt.rgba(Theme.fgDim.r, Theme.fgDim.g, Theme.fgDim.b, 0.4)
                                                visible: commandCenterWindow.weatherCity !== ""
                                            }

                                            Text {
                                                text: commandCenterWindow.weatherCity
                                                font.family: Theme.font
                                                font.pixelSize: Theme.fontPx(9)
                                                font.weight: Font.Normal
                                                color: Theme.fgDim
                                                elide: Text.ElideRight
                                                visible: commandCenterWindow.weatherCity !== ""
                                                Layout.maximumWidth: Theme.px(45)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }



                            // Tile 4: Clipboard History
                                            Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.035) : Qt.rgba(0, 0, 0, 0.03)
                    border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.12)
                    border.width: 1
                    radius: Theme.px(12)
                    clip: true

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.px(10)
                        spacing: Theme.px(6)

                        // Tile Header
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.px(6)

                            Text {
                                text: "content_paste"
                                font.family: Theme.fontIcon
                                font.pixelSize: Theme.fontPx(14)
                                color: Theme.accent
                            }

                            Text {
                                text: "Clipboard Buffer"
                                font.family: Theme.font
                                font.pixelSize: Theme.fontPx(11)
                                font.weight: Font.DemiBold
                                color: Theme.fg
                            }

                            Item { Layout.fillWidth: true }

                            Rectangle {
                                Layout.preferredHeight: Theme.px(16)
                                Layout.preferredWidth: cCountText.implicitWidth + Theme.px(10)
                                radius: Theme.px(8)
                                color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.06)

                                Text {
                                    id: cCountText
                                    anchors.centerIn: parent
                                    text: commandCenterWindow.clipboardItems.length
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontPx(9)
                                    font.weight: Font.Bold
                                    color: Theme.fgDim
                                }
                            }
                        }

                        // Clipboard ListView
                        ListView {
                            id: clipListView
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            model: commandCenterWindow.clipboardItems
                            spacing: Theme.px(2)

                            property bool scrollInitialized: false
                            Component.onCompleted: scrollInitialized = true
                            onContentYChanged: if (scrollInitialized) clipScrollTimer.restart()

                            Timer {
                                id: clipScrollTimer
                                interval: 700
                                running: false
                            }

                            ScrollBar.vertical: ScrollBar {
                                id: clipScroll
                                policy: ScrollBar.AsNeeded
                                contentItem: Rectangle {
                                    implicitWidth: Theme.px(3)
                                    radius: Theme.px(2)
                                    color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.4)
                                    opacity: (clipScroll.active || clipScrollTimer.running) ? 1.0 : 0.0
                                    Behavior on opacity { NumberAnimation { duration: 200 } }
                                }
                            }

                            delegate: Item {
                                width: clipListView.width
                                height: Theme.px(28)

                                HoverHandler { id: clipHover }

                                Rectangle {
                                    anchors.fill: parent
                                    radius: Theme.px(6)
                                    color: clipHover.hovered ? (Theme.isDark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(0, 0, 0, 0.06)) : "transparent"

                                    Behavior on color { ColorAnimation { duration: 120 } }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: Theme.px(6)
                                        anchors.rightMargin: Theme.px(6)
                                        spacing: Theme.px(8)

                                        Text {
                                            text: "content_copy"
                                            font.family: Theme.fontIcon
                                            font.pixelSize: Theme.fontPx(13)
                                            color: clipHover.hovered ? Theme.accent : Theme.fgDim
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.preview
                                            elide: Text.ElideRight
                                            font.family: Theme.font
                                            font.pixelSize: Theme.fontPx(11)
                                            color: clipHover.hovered ? Theme.fg : Theme.fgDim
                                        }

                                        Text {
                                            visible: clipHover.hovered
                                            text: "Copy"
                                            font.family: Theme.font
                                            font.pixelSize: Theme.fontPx(9)
                                            font.weight: Font.Bold
                                            color: Theme.accent
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: commandCenterWindow.copyClipboard(modelData.id)
                                    }
                                }
                            }
                        }
                    }
                }

                        }
                    }

                }

                // ══════════════════════════════════════════════════════════
                // NODE (0, -1) :: GITHUB UPLINK
                // ══════════════════════════════════════════════════════════
                Rectangle {
                    id: cardNodeTop
                    readonly property int nodeX: 0
                    readonly property int nodeY: -1
                    readonly property bool isCurrentTarget: (commandCenterWindow.activeGridX === cardNodeTop.nodeX && commandCenterWindow.activeGridY === cardNodeTop.nodeY)
                    readonly property string cardTitle: "GITHUB UPLINK (HEATMAP / COMMITS / PR GATEKEEPER)"
                    readonly property string lodIcon: "hub"
                    readonly property string lodTitle: "GITHUB UPLINK"
                    readonly property string lodSubtitle: "Contributions, Git Sync & PR Gatekeeper"

                    width: viewport.cardWidth
                    height: viewport.cardHeight
                    x: Math.round((viewport.width - width) / 2 + (cardNodeTop.nodeX * viewport.stepX))
                    y: Math.round((viewport.height - height) / 2 + (cardNodeTop.nodeY * viewport.stepY))
                    radius: 16
                    color: Qt.rgba(0.047, 0.055, 0.07, 0.82)
                    border.color: cardNodeTop.isCurrentTarget ? "#8ee8a8" : ((commandCenterWindow.isOverview && cardNodeTopClickArea.containsMouse) ? Qt.rgba(0.557, 0.91, 0.659, 0.6) : Qt.rgba(1, 1, 1, 0.12))
                    border.width: cardNodeTop.isCurrentTarget ? 2 : 1
                    scale: (commandCenterWindow.isOverview && cardNodeTopClickArea.containsMouse) ? 1.03 : 1.0
                    transformOrigin: Item.Center
                    Behavior on scale {
                        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                    }
                    clip: true

                    // Click interception for overview or peeking neighbor cards
                    MouseArea {
                        id: cardNodeTopClickArea
                        anchors.fill: parent
                        enabled: commandCenterWindow.isOverview || (!cardNodeTop.isCurrentTarget)
                        cursorShape: (commandCenterWindow.isOverview || !cardNodeTop.isCurrentTarget) ? Qt.PointingHandCursor : Qt.ArrowCursor
                        hoverEnabled: true
                        z: 500
                        onClicked: {
                            commandCenterWindow.zoomToNode(cardNodeTop.nodeX, cardNodeTop.nodeY)
                        }
                    }

                    // Level-of-Detail (LOD) Watermark Overlay for Overview Mode
                    Item {
                        id: cardNodeTopLodOverlay
                        anchors.fill: parent
                        z: 400
                        opacity: commandCenterWindow.isOverview ? 0.92 : 0.0
                        visible: opacity > 0.01
                        Behavior on opacity {
                            NumberAnimation { duration: 350; easing.type: Easing.OutCubic }
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: 16
                            color: Qt.rgba(0.04, 0.05, 0.07, 0.78)
                        }

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: Theme.px(10)

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: cardNodeTop.lodIcon
                                font.family: Theme.fontIcon
                                font.pixelSize: Theme.fontPx(64)
                                color: cardNodeTop.isCurrentTarget ? "#8ee8a8" : Qt.rgba(255, 255, 255, 0.90)
                            }

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: cardNodeTop.lodTitle
                                font.family: Theme.fontMono || "monospace"
                                font.pixelSize: Theme.fontPx(20)
                                font.bold: true
                                color: cardNodeTop.isCurrentTarget ? "#8ee8a8" : Theme.fg
                            }

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: cardNodeTop.lodSubtitle
                                font.family: Theme.font
                                font.pixelSize: Theme.fontPx(13)
                                color: Theme.fgDim
                            }
                        }
                    }

                    // Corner brackets (+)
                    Text { text: "+"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(11); font.bold: true; color: cardNodeTop.isCurrentTarget ? "#8ee8a8" : Qt.rgba(255,255,255,0.4); anchors.left: parent.left; anchors.top: parent.top; anchors.margins: Theme.px(8); z: 10 }
                    Text { text: "+"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(11); font.bold: true; color: cardNodeTop.isCurrentTarget ? "#8ee8a8" : Qt.rgba(255,255,255,0.4); anchors.right: parent.right; anchors.top: parent.top; anchors.margins: Theme.px(8); z: 10 }
                    Text { text: "+"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(11); font.bold: true; color: cardNodeTop.isCurrentTarget ? "#8ee8a8" : Qt.rgba(255,255,255,0.4); anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: Theme.px(8); z: 10 }
                    Text { text: "+"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(11); font.bold: true; color: cardNodeTop.isCurrentTarget ? "#8ee8a8" : Qt.rgba(255,255,255,0.4); anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: Theme.px(8); z: 10 }

                    // Card Header Bar
                    RowLayout {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.topMargin: Theme.px(10)
                        anchors.leftMargin: Theme.px(20)
                        anchors.rightMargin: Theme.px(20)
                        height: Theme.px(24)
                        spacing: Theme.px(8)
                        z: 10

                        Text {
                            text: "// NODE [" + cardNodeTop.nodeX + ", " + cardNodeTop.nodeY + "] :: " + cardNodeTop.cardTitle
                            font.family: Theme.fontMono || "monospace"
                            font.pixelSize: Theme.fontPx(11)
                            font.weight: Font.Bold
                            color: cardNodeTop.isCurrentTarget ? "#8ee8a8" : Theme.fg
                        }

                        Item { Layout.fillWidth: true }

                        Rectangle {
                            visible: cardNodeTop.isCurrentTarget && !commandCenterWindow.isOverview
                            Layout.preferredHeight: Theme.px(18)
                            Layout.preferredWidth: cardNodeTopHintText.implicitWidth + Theme.px(12)
                            radius: Theme.px(4)
                            color: cardNodeTopHintHover.hovered ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.12) : Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.05)
                            border.color: Qt.rgba(255, 255, 255, 0.15)
                            border.width: 1

                            HoverHandler { id: cardNodeTopHintHover }
                            Text {
                                id: cardNodeTopHintText
                                anchors.centerIn: parent
                                text: "OVERVIEW (ESC)"
                                font.family: Theme.fontMono || "monospace"
                                font.pixelSize: Theme.fontPx(8.5)
                                font.bold: true
                                color: Theme.fgDim
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: commandCenterWindow.zoomToOverview()
                            }
                        }
                    }

                    Item {
                        anchors.fill: parent
                        anchors.margins: Theme.px(16)
                        anchors.topMargin: Theme.px(44)
                        clip: true

                                    Flickable {
                id: githubUplinkView
                width: parent.width
                height: parent.height
                x: 0
                opacity: 1.0
                visible: true
                clip: true
                contentWidth: width
                contentHeight: githubScrollCol.implicitHeight
                boundsBehavior: Flickable.StopAtBounds

                Behavior on contentY {
                    NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                }

                WheelHandler {
                    target: githubUplinkView
                    orientation: Qt.Vertical
                    onWheel: function(event) {
                        var dy = event.angleDelta.y
                        var maxScroll = Math.max(0, githubUplinkView.contentHeight - githubUplinkView.height)
                        var newY = githubUplinkView.contentY - dy
                        githubUplinkView.contentY = Math.max(0, Math.min(maxScroll, newY))
                    }
                }

                ScrollBar.vertical: ScrollBar {
                    id: ghScroll
                    policy: ScrollBar.AsNeeded
                    contentItem: Rectangle {
                        implicitWidth: Theme.px(3)
                        radius: Theme.px(2)
                        color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.4)
                        opacity: ghScroll.active ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 200 } }
                    }
                }

                Behavior on x {
                    NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                }
                Behavior on opacity {
                    NumberAnimation { duration: 200 }
                }

                ColumnLayout {
                    id: githubScrollCol
                    width: githubUplinkView.width
                    implicitHeight: (githubSplitPanes ? githubSplitPanes.implicitHeight : githubUplinkView.height) + Theme.px(8) + (githubContribMatrix ? githubContribMatrix.implicitHeight : Theme.px(160))
                    spacing: Theme.px(8)

                    // 1. TOP: SPLIT PANES (Covers full visible panel height)
                    RowLayout {
                        id: githubSplitPanes
                        Layout.fillWidth: true
                        Layout.preferredHeight: githubUplinkView.height - Theme.px(6)
                        Layout.minimumHeight: githubUplinkView.height - Theme.px(6)
                        implicitHeight: githubUplinkView.height - Theme.px(6)
                        spacing: Theme.px(8)

                        // LEFT: REPOSITORIES TILE (40% width)
                        Rectangle {
                            Layout.preferredWidth: Math.round(githubUplinkView.width * 0.40)
                            Layout.fillHeight: true
                            color: Qt.rgba(1, 1, 1, 0.02)
                            border.color: Qt.rgba(1, 1, 1, 0.15)
                            border.width: 1
                            radius: Theme.px(12)
                            clip: true

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: Theme.px(10)
                                spacing: Theme.px(8)

                                // Search Tile Header
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Theme.px(6)

                                    Text {
                                        text: "book"
                                        font.family: Theme.fontIcon
                                        font.pixelSize: Theme.fontPx(14)
                                        color: Theme.accent
                                    }

                                    Text {
                                        text: "Repositories"
                                        font.family: Theme.font
                                        font.pixelSize: Theme.fontPx(12)
                                        font.weight: Font.DemiBold
                                        color: Theme.fg
                                    }
                                }

                                // Search Input Field
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: Theme.px(28)
                                    color: Qt.rgba(1, 1, 1, 0.04)
                                    border.color: repoInput.activeFocus ? Theme.accent : Qt.rgba(1, 1, 1, 0.12)
                                    border.width: 1
                                    radius: Theme.px(6)

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: Theme.px(8)
                                        anchors.rightMargin: Theme.px(8)
                                        spacing: Theme.px(6)

                                        Text {
                                            text: "filter_list"
                                            font.family: Theme.fontIcon
                                            font.pixelSize: Theme.fontPx(12)
                                            color: Theme.fgDim
                                        }

                                        Timer {
                                            id: searchDebounceTimer
                                            interval: 350
                                            repeat: false
                                            onTriggered: {
                                                commandCenterWindow.searchRepositories(repoInput.text)
                                            }
                                        }

                                        TextField {
                                            id: repoInput
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            placeholderText: "Search repositories..."
                                            font.family: Theme.font
                                            font.pixelSize: Theme.fontPx(11)
                                            color: Theme.fg
                                            placeholderTextColor: Qt.rgba(Theme.fgDim.r, Theme.fgDim.g, Theme.fgDim.b, 0.6)
                                            background: Item {}
                                            leftPadding: 0
                                            rightPadding: 0
                                            topPadding: 0
                                            bottomPadding: 0
                                            verticalAlignment: TextInput.AlignVCenter
                                            onTextChanged: {
                                                if (text.trim().length === 0) {
                                                    searchDebounceTimer.stop()
                                                    commandCenterWindow.searchRepositories("")
                                                } else {
                                                    searchDebounceTimer.restart()
                                                }
                                            }
                                            onAccepted: {
                                                searchDebounceTimer.stop()
                                                commandCenterWindow.searchRepositories(text)
                                            }
                                            Keys.onDownPressed: function(event) {
                                                commandCenterWindow.scrollGithubBottom()
                                                if (event) event.accepted = true
                                            }
                                            Keys.onUpPressed: function(event) {
                                                commandCenterWindow.scrollGithubTop()
                                                if (event) event.accepted = true
                                            }
                                            Keys.onLeftPressed: function(event) {
                                                if (cursorPosition === 0) {
                                                    commandCenterWindow.currentChannel = "overview"
                                                    escHandler.forceActiveFocus()
                                                    if (event) event.accepted = true
                                                } else {
                                                    if (event) event.accepted = false
                                                }
                                            }
                                            Keys.onEscapePressed: function(event) {
                                                if (text.length > 0) {
                                                    text = ""
                                                } else {
                                                    commandCenterWindow.closeRequested()
                                                }
                                                if (event) event.accepted = true
                                            }
                                        }

                                        Text {
                                            visible: repoInput.text.length > 0
                                            text: "close"
                                            font.family: Theme.fontIcon
                                            font.pixelSize: Theme.fontPx(12)
                                            color: Theme.fgDim
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: repoInput.text = ""
                                            }
                                        }
                                    }
                                }

                                // Repositories List Container
                                Item {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true

                                    ListView {
                                        id: reposList
                                        anchors.fill: parent
                                        clip: true
                                        spacing: Theme.px(4)
                                        interactive: true
                                        model: (commandCenterWindow.githubPayload && commandCenterWindow.githubPayload.repositories) ? commandCenterWindow.githubPayload.repositories : []

                                        delegate: Rectangle {
                                        width: reposList.width
                                        height: Theme.px(40)
                                        radius: Theme.px(6)
                                        color: repoHover.hovered ? Qt.rgba(1, 1, 1, 0.05) : "transparent"

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: Theme.px(8)
                                            anchors.rightMargin: Theme.px(8)
                                            spacing: Theme.px(8)

                                            Text {
                                                text: "book"
                                                font.family: Theme.fontIcon
                                                font.pixelSize: Theme.fontPx(14)
                                                color: repoHover.hovered ? Theme.accent : Theme.fgDim
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 1

                                                Text {
                                                    Layout.fillWidth: true
                                                    text: modelData.name
                                                    font.family: Theme.font
                                                    font.pixelSize: Theme.fontPx(11)
                                                    font.weight: Font.DemiBold
                                                    color: repoHover.hovered ? Theme.fg : Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.85)
                                                    elide: Text.ElideRight
                                                }

                                                Text {
                                                    Layout.fillWidth: true
                                                    text: modelData.owner + (modelData.language ? (" • " + modelData.language) : "")
                                                    font.family: Theme.font
                                                    font.pixelSize: Theme.fontPx(9)
                                                    color: Theme.fgDim
                                                    elide: Text.ElideRight
                                                }
                                            }

                                            RowLayout {
                                                spacing: 2
                                                Text {
                                                    text: "star"
                                                    font.family: Theme.fontIcon
                                                    font.pixelSize: Theme.fontPx(10)
                                                    color: "#f5b86e"
                                                }
                                                Text {
                                                    text: modelData.stars
                                                    font.family: Theme.font
                                                    font.pixelSize: Theme.fontPx(9)
                                                    color: Theme.fgDim
                                                }
                                            }
                                        }

                                        HoverHandler { id: repoHover }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: commandCenterWindow.openUrl(modelData.url)
                                        }
                                    }
                                } // closes ListView

                                Text {
                                    visible: reposList.count === 0
                                    anchors.centerIn: parent
                                    text: "No repositories found"
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontPx(11)
                                    color: Theme.fgDim
                                }
                            } // closes Item
                        } // closes ColumnLayout
                    } // closes Rectangle

                        // RIGHT: WORKSPACE & PR GATEKEEPER
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: Theme.px(8)

                            // TOP RIGHT: WORKSPACE NODE
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Theme.px(108)
                                color: Qt.rgba(1, 1, 1, 0.02)
                                border.color: Qt.rgba(1, 1, 1, 0.15)
                                border.width: 1
                                radius: Theme.px(12)
                                clip: true

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: Theme.px(10)
                                    spacing: Theme.px(6)

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Theme.px(6)

                                        Text {
                                            text: "deployed_code"
                                            font.family: Theme.fontIcon
                                            font.pixelSize: Theme.fontPx(14)
                                            color: Theme.accent
                                        }

                                        Text {
                                            text: "Workspace Node"
                                            font.family: Theme.font
                                            font.pixelSize: Theme.fontPx(12)
                                            font.weight: Font.DemiBold
                                            color: Theme.fg
                                        }

                                        Item { Layout.fillWidth: true }

                                        // Sync Button
                                        Rectangle {
                                            height: Theme.px(24)
                                            width: syncBtnText.implicitWidth + Theme.px(16)
                                            radius: Theme.px(6)
                                            color: syncHover.hovered ? Theme.accent : Qt.rgba(1, 1, 1, 0.05)
                                            border.color: syncHover.hovered ? Theme.accent : Qt.rgba(1, 1, 1, 0.18)
                                            border.width: 1

                                            RowLayout {
                                                anchors.centerIn: parent
                                                spacing: Theme.px(4)

                                                Text {
                                                    text: "sync"
                                                    font.family: Theme.fontIcon
                                                    font.pixelSize: Theme.fontPx(11)
                                                    color: syncHover.hovered ? "#000000" : Theme.fg
                                                }

                                                Text {
                                                    id: syncBtnText
                                                    text: "SYNC LOCAL WORKSPACE"
                                                    font.family: Theme.font
                                                    font.pixelSize: Theme.fontPx(9)
                                                    font.weight: Font.Bold
                                                    color: syncHover.hovered ? "#000000" : Theme.fg
                                                }
                                            }

                                            HoverHandler { id: syncHover }
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: commandCenterWindow.pushLocalWorkspace()
                                            }
                                        }
                                    }

                                    // Workspace Status Information
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Theme.px(10)

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2

                                            RowLayout {
                                                spacing: Theme.px(6)
                                                Text {
                                                    text: (commandCenterWindow.githubPayload && commandCenterWindow.githubPayload.workspace && commandCenterWindow.githubPayload.workspace.repo_name) ? commandCenterWindow.githubPayload.workspace.repo_name : "Workspace"
                                                    font.family: Theme.font
                                                    font.pixelSize: Theme.fontPx(11)
                                                    font.weight: Font.DemiBold
                                                    color: Theme.fg
                                                }
                                                Rectangle {
                                                    height: Theme.px(14)
                                                    width: branchText.implicitWidth + Theme.px(8)
                                                    radius: Theme.px(3)
                                                    color: Qt.rgba(1, 1, 1, 0.08)
                                                    Text {
                                                        id: branchText
                                                        anchors.centerIn: parent
                                                        text: (commandCenterWindow.githubPayload && commandCenterWindow.githubPayload.workspace && commandCenterWindow.githubPayload.workspace.branch) ? commandCenterWindow.githubPayload.workspace.branch : "-"
                                                        font.family: Theme.font
                                                        font.pixelSize: Theme.fontPx(9)
                                                        color: Theme.accent
                                                    }
                                                }
                                            }

                                            Text {
                                                Layout.fillWidth: true
                                                text: (commandCenterWindow.githubPayload && commandCenterWindow.githubPayload.workspace) ? commandCenterWindow.githubPayload.workspace.last_commit : ""
                                                font.family: Theme.font
                                                font.pixelSize: Theme.fontPx(9)
                                                color: Theme.fgDim
                                                elide: Text.ElideRight
                                            }

                                            Text {
                                                Layout.fillWidth: true
                                                text: (commandCenterWindow.githubPayload && commandCenterWindow.githubPayload.workspace) ? commandCenterWindow.githubPayload.workspace.sync_status : ""
                                                font.family: Theme.font
                                                font.pixelSize: Theme.fontPx(9)
                                                font.weight: Font.Medium
                                                color: {
                                                    if (!commandCenterWindow.githubPayload || !commandCenterWindow.githubPayload.workspace) return Theme.fgDim
                                                    if (commandCenterWindow.githubPayload.workspace.dirty) return "#f5b86e"
                                                    if (commandCenterWindow.githubPayload.workspace.ahead > 0) return Theme.accent
                                                    return "#8ee8a8"
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // BOTTOM RIGHT: PR GATEKEEPER
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                color: Qt.rgba(1, 1, 1, 0.02)
                                border.color: Qt.rgba(1, 1, 1, 0.15)
                                border.width: 1
                                radius: Theme.px(12)
                                clip: true

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: Theme.px(10)
                                    spacing: Theme.px(8)

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Theme.px(6)

                                        Text {
                                            text: "call_merge"
                                            font.family: Theme.fontIcon
                                            font.pixelSize: Theme.fontPx(14)
                                            color: "#8ee8a8"
                                        }

                                        Text {
                                            text: "PR Gatekeeper"
                                            font.family: Theme.font
                                            font.pixelSize: Theme.fontPx(12)
                                            font.weight: Font.DemiBold
                                            color: Theme.fg
                                        }

                                        Text {
                                            text: "(" + ((commandCenterWindow.githubPayload && commandCenterWindow.githubPayload.pull_requests) ? commandCenterWindow.githubPayload.pull_requests.length : 0) + " incoming)"
                                            font.family: Theme.font
                                            font.pixelSize: Theme.fontPx(10)
                                            color: Theme.fgDim
                                        }
                                    }

                                    ListView {
                                        id: prsList
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        clip: true
                                        spacing: Theme.px(6)
                                        interactive: false
                                        model: (commandCenterWindow.githubPayload && commandCenterWindow.githubPayload.pull_requests) ? commandCenterWindow.githubPayload.pull_requests : []

                                        Text {
                                            visible: prsList.count === 0
                                            anchors.centerIn: parent
                                            text: "No open pull requests"
                                            font.family: Theme.font
                                            font.pixelSize: Theme.fontPx(11)
                                            color: Theme.fgDim
                                        }

                                        delegate: Rectangle {
                                            width: prsList.width
                                            height: Theme.px(42)
                                            radius: Theme.px(6)
                                            color: prHover.hovered ? Qt.rgba(1, 1, 1, 0.04) : Qt.rgba(1, 1, 1, 0.015)
                                            border.color: Qt.rgba(1, 1, 1, 0.08)
                                            border.width: 1

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: Theme.px(8)
                                                anchors.rightMargin: Theme.px(8)
                                                spacing: Theme.px(8)

                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 1

                                                    RowLayout {
                                                        spacing: Theme.px(6)

                                                        Text {
                                                            text: "#" + modelData.number
                                                            font.family: Theme.font
                                                            font.pixelSize: Theme.fontPx(10)
                                                            font.weight: Font.Bold
                                                            color: "#8ee8a8"
                                                        }

                                                        Text {
                                                            Layout.fillWidth: true
                                                            text: modelData.title
                                                            font.family: Theme.font
                                                            font.pixelSize: Theme.fontPx(11)
                                                            font.weight: Font.DemiBold
                                                            color: Theme.fg
                                                            elide: Text.ElideRight
                                                        }
                                                    }

                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: modelData.repo + " by " + modelData.author + " • " + modelData.created_at
                                                        font.family: Theme.font
                                                        font.pixelSize: Theme.fontPx(9)
                                                        color: Theme.fgDim
                                                        elide: Text.ElideRight
                                                    }
                                                }

                                                // Merge Button
                                                Rectangle {
                                                    height: Theme.px(24)
                                                    width: mergeText.implicitWidth + Theme.px(14)
                                                    radius: Theme.px(4)
                                                    color: mergeHover.hovered ? "#8ee8a8" : Qt.rgba(0.557, 0.910, 0.659, 0.15)
                                                    border.color: "#8ee8a8"
                                                    border.width: 1

                                                    Text {
                                                        id: mergeText
                                                        anchors.centerIn: parent
                                                        text: "MERGE"
                                                        font.family: Theme.font
                                                        font.pixelSize: Theme.fontPx(9)
                                                        font.weight: Font.Bold
                                                        color: mergeHover.hovered ? "#000000" : "#8ee8a8"
                                                    }

                                                    HoverHandler { id: mergeHover }
                                                    MouseArea {
                                                        anchors.fill: parent
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: commandCenterWindow.mergePullRequest(modelData.repo, modelData.number)
                                                    }
                                                }
                                            }

                                            HoverHandler { id: prHover }
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: commandCenterWindow.openUrl(modelData.url)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // 2. BOTTOM: FULL-WIDTH CONTRIBUTION MATRIX (Authentic GitHub Square Calendar)
                    Rectangle {
                        id: githubContribMatrix
                        Layout.fillWidth: true
                        Layout.preferredHeight: Theme.px(160)
                        implicitHeight: Theme.px(160)
                        color: Qt.rgba(1, 1, 1, 0.02)
                        border.color: Qt.rgba(1, 1, 1, 0.15)
                        border.width: 1
                        radius: Theme.px(10)
                        clip: false

                        property var hoveredDay: null
                        property real tooltipX: 0
                        property real tooltipY: 0

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: Theme.px(10)
                            spacing: Theme.px(6)

                            // Matrix Header & Legend
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.px(8)

                                Text {
                                    text: "commit"
                                    font.family: Theme.fontIcon
                                    font.pixelSize: Theme.fontPx(14)
                                    color: Theme.accent
                                }

                                Text {
                                    text: "Contribution Matrix"
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontPx(12)
                                    font.weight: Font.DemiBold
                                    color: Theme.fg
                                }

                                Text {
                                    text: {
                                        if (githubContribMatrix.hoveredDay && !githubContribMatrix.hoveredDay.is_future) {
                                            var c = githubContribMatrix.hoveredDay.count
                                            var d = githubContribMatrix.hoveredDay.date
                                            return "•  " + d + ": " + (c > 0 ? (c + (c === 1 ? " commit" : " commits")) : "No commits")
                                        }
                                        var total = (commandCenterWindow.githubPayload && commandCenterWindow.githubPayload.total_contributions !== undefined) ? commandCenterWindow.githubPayload.total_contributions : 0
                                        return "•  " + total + " contributions in last 36 weeks"
                                    }
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontPx(11)
                                    font.weight: githubContribMatrix.hoveredDay ? Font.Medium : Font.Normal
                                    color: githubContribMatrix.hoveredDay ? Theme.accent : Theme.fgDim
                                }

                                Item { Layout.fillWidth: true }

                                // Legend Dots
                                RowLayout {
                                    spacing: Theme.px(4)
                                    Layout.alignment: Qt.AlignVCenter

                                    Text {
                                        text: "Less"
                                        font.family: Theme.font
                                        font.pixelSize: Theme.fontPx(9)
                                        color: Theme.fgDim
                                    }
                                    Rectangle { width: Theme.px(10); height: Theme.px(10); radius: Theme.px(2); color: Qt.rgba(1, 1, 1, 0.04); border.color: Qt.rgba(1, 1, 1, 0.1); border.width: 1 }
                                    Rectangle { width: Theme.px(10); height: Theme.px(10); radius: Theme.px(2); color: Qt.rgba(0.557, 0.910, 0.659, 0.28) }
                                    Rectangle { width: Theme.px(10); height: Theme.px(10); radius: Theme.px(2); color: Qt.rgba(0.557, 0.910, 0.659, 0.58) }
                                    Rectangle { width: Theme.px(10); height: Theme.px(10); radius: Theme.px(2); color: "#8ee8a8" }
                                    Rectangle { width: Theme.px(10); height: Theme.px(10); radius: Theme.px(2); color: "#39d353" }
                                    Text {
                                        text: "More"
                                        font.family: Theme.font
                                        font.pixelSize: Theme.fontPx(9)
                                        color: Theme.fgDim
                                    }
                                }
                            }

                            // Calendar Grid Area
                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true

                                Row {
                                    anchors.centerIn: parent
                                    spacing: Theme.px(5)

                                    // Day of Week Labels (Left Column)
                                    Column {
                                        spacing: Theme.px(3)
                                        // Offset for month header row
                                        Item { width: Theme.px(1); height: Theme.px(14) }
                                        // Sun
                                        Item { width: Theme.px(20); height: Theme.px(11) }
                                        // Mon
                                        Text {
                                            width: Theme.px(20); height: Theme.px(11)
                                            text: "Mon"
                                            font.family: Theme.font
                                            font.pixelSize: Theme.fontPx(8)
                                            color: Theme.fgDim
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                        // Tue
                                        Item { width: Theme.px(20); height: Theme.px(11) }
                                        // Wed
                                        Text {
                                            width: Theme.px(20); height: Theme.px(11)
                                            text: "Wed"
                                            font.family: Theme.font
                                            font.pixelSize: Theme.fontPx(8)
                                            color: Theme.fgDim
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                        // Thu
                                        Item { width: Theme.px(20); height: Theme.px(11) }
                                        // Fri
                                        Text {
                                            width: Theme.px(20); height: Theme.px(11)
                                            text: "Fri"
                                            font.family: Theme.font
                                            font.pixelSize: Theme.fontPx(8)
                                            color: Theme.fgDim
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                        // Sat
                                        Item { width: Theme.px(20); height: Theme.px(11) }
                                    }

                                    // Week Columns
                                    Row {
                                        spacing: Theme.px(3)

                                        Repeater {
                                            model: (commandCenterWindow.githubPayload && commandCenterWindow.githubPayload.weeks && commandCenterWindow.githubPayload.weeks.length > 0) ? commandCenterWindow.githubPayload.weeks : []

                                            Column {
                                                id: weekCol
                                                spacing: Theme.px(3)

                                                // Month label header
                                                Item {
                                                    width: Theme.px(11)
                                                    height: Theme.px(14)

                                                    Text {
                                                        visible: modelData.month_label && modelData.month_label.length > 0
                                                        text: modelData.month_label || ""
                                                        font.family: Theme.font
                                                        font.pixelSize: Theme.fontPx(8)
                                                        font.weight: Font.Medium
                                                        color: Theme.fgDim
                                                        anchors.left: parent.left
                                                        anchors.bottom: parent.bottom
                                                    }
                                                }

                                                // 7 Days in Week (Sun to Sat)
                                                Repeater {
                                                    model: modelData.days || []

                                                    Rectangle {
                                                        id: dayCell
                                                        width: Theme.px(11)
                                                        height: Theme.px(11)
                                                        radius: Theme.px(2)
                                                        opacity: modelData.is_future ? 0.0 : 1.0

                                                        color: {
                                                            if (!modelData || modelData.is_future) return "transparent"
                                                            var lvl = modelData.level || 0
                                                            if (lvl === 4) return "#39d353"
                                                            if (lvl === 3) return "#8ee8a8"
                                                            if (lvl === 2) return Qt.rgba(0.557, 0.910, 0.659, 0.58)
                                                            if (lvl === 1) return Qt.rgba(0.557, 0.910, 0.659, 0.28)
                                                            return Qt.rgba(1, 1, 1, 0.04)
                                                        }
                                                        border.color: (cellHover.hovered && !modelData.is_future) ? Theme.accent : ((modelData && modelData.level > 0 && !modelData.is_future) ? "transparent" : Qt.rgba(1, 1, 1, 0.08))
                                                        border.width: (cellHover.hovered && !modelData.is_future) ? 1.5 : 1
                                                        scale: (cellHover.hovered && !modelData.is_future) ? 1.25 : 1.0
                                                        z: cellHover.hovered ? 50 : 1

                                                        Behavior on scale { NumberAnimation { duration: 120 } }
                                                        Behavior on border.color { ColorAnimation { duration: 100 } }

                                                        HoverHandler {
                                                            id: cellHover
                                                            enabled: !modelData.is_future
                                                            onHoveredChanged: {
                                                                if (hovered) {
                                                                    githubContribMatrix.hoveredDay = modelData
                                                                    var pt = dayCell.mapToItem(githubContribMatrix, dayCell.width / 2, 0)
                                                                    githubContribMatrix.tooltipX = pt.x
                                                                    githubContribMatrix.tooltipY = pt.y
                                                                } else if (githubContribMatrix.hoveredDay === modelData) {
                                                                    githubContribMatrix.hoveredDay = null
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
                        }

                        // Floating Tooltip above hovered square
                        Rectangle {
                            id: matrixTooltip
                            visible: githubContribMatrix.hoveredDay !== null && !githubContribMatrix.hoveredDay.is_future
                            x: Math.max(Theme.px(8), Math.min(githubContribMatrix.width - width - Theme.px(8), githubContribMatrix.tooltipX - width / 2))
                            y: Math.max(Theme.px(4), githubContribMatrix.tooltipY - height - Theme.px(5))
                            z: 200
                            width: matrixTipText.implicitWidth + Theme.px(12)
                            height: Theme.px(22)
                            radius: Theme.px(4)
                            color: Qt.rgba(0, 0, 0, 0.90)
                            border.color: Qt.rgba(1, 1, 1, 0.25)
                            border.width: 1

                            Text {
                                id: matrixTipText
                                anchors.centerIn: parent
                                text: {
                                    if (!githubContribMatrix.hoveredDay) return ""
                                    var c = githubContribMatrix.hoveredDay.count
                                    var d = githubContribMatrix.hoveredDay.date
                                    return (c > 0 ? (c + (c === 1 ? " commit" : " commits")) : "No commits") + " on " + d
                                }
                                font.family: Theme.font
                                font.pixelSize: Theme.fontPx(9)
                                font.weight: Font.Medium
                                color: Theme.fg
                            }
                        }
                    }
                }
        }

                    }

                }

                // ══════════════════════════════════════════════════════════
                // NODE (0, 1) :: SYSTEM TELEMETRY
                // ══════════════════════════════════════════════════════════
                Rectangle {
                    id: cardNodeBottom
                    readonly property int nodeX: 0
                    readonly property int nodeY: 1
                    readonly property bool isCurrentTarget: (commandCenterWindow.activeGridX === cardNodeBottom.nodeX && commandCenterWindow.activeGridY === cardNodeBottom.nodeY)
                    readonly property string cardTitle: "SYSTEM TELEMETRY (HARDWARE KERNEL & PERFORMANCE GAUGES)"
                    readonly property string lodIcon: "monitoring"
                    readonly property string lodTitle: "SYSTEM TELEMETRY"
                    readonly property string lodSubtitle: "Kernel Stream, Hardware Wave & Network"

                    width: viewport.cardWidth
                    height: viewport.cardHeight
                    x: Math.round((viewport.width - width) / 2 + (cardNodeBottom.nodeX * viewport.stepX))
                    y: Math.round((viewport.height - height) / 2 + (cardNodeBottom.nodeY * viewport.stepY))
                    radius: 16
                    color: Qt.rgba(0.047, 0.055, 0.07, 0.82)
                    border.color: cardNodeBottom.isCurrentTarget ? "#8ee8a8" : ((commandCenterWindow.isOverview && cardNodeBottomClickArea.containsMouse) ? Qt.rgba(0.557, 0.91, 0.659, 0.6) : Qt.rgba(1, 1, 1, 0.12))
                    border.width: cardNodeBottom.isCurrentTarget ? 2 : 1
                    scale: (commandCenterWindow.isOverview && cardNodeBottomClickArea.containsMouse) ? 1.03 : 1.0
                    transformOrigin: Item.Center
                    Behavior on scale {
                        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                    }
                    clip: true

                    // Click interception for overview or peeking neighbor cards
                    MouseArea {
                        id: cardNodeBottomClickArea
                        anchors.fill: parent
                        enabled: commandCenterWindow.isOverview || (!cardNodeBottom.isCurrentTarget)
                        cursorShape: (commandCenterWindow.isOverview || !cardNodeBottom.isCurrentTarget) ? Qt.PointingHandCursor : Qt.ArrowCursor
                        hoverEnabled: true
                        z: 500
                        onClicked: {
                            commandCenterWindow.zoomToNode(cardNodeBottom.nodeX, cardNodeBottom.nodeY)
                        }
                    }

                    // Level-of-Detail (LOD) Watermark Overlay for Overview Mode
                    Item {
                        id: cardNodeBottomLodOverlay
                        anchors.fill: parent
                        z: 400
                        opacity: commandCenterWindow.isOverview ? 0.92 : 0.0
                        visible: opacity > 0.01
                        Behavior on opacity {
                            NumberAnimation { duration: 350; easing.type: Easing.OutCubic }
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: 16
                            color: Qt.rgba(0.04, 0.05, 0.07, 0.78)
                        }

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: Theme.px(10)

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: cardNodeBottom.lodIcon
                                font.family: Theme.fontIcon
                                font.pixelSize: Theme.fontPx(64)
                                color: cardNodeBottom.isCurrentTarget ? "#8ee8a8" : Qt.rgba(255, 255, 255, 0.90)
                            }

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: cardNodeBottom.lodTitle
                                font.family: Theme.fontMono || "monospace"
                                font.pixelSize: Theme.fontPx(20)
                                font.bold: true
                                color: cardNodeBottom.isCurrentTarget ? "#8ee8a8" : Theme.fg
                            }

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: cardNodeBottom.lodSubtitle
                                font.family: Theme.font
                                font.pixelSize: Theme.fontPx(13)
                                color: Theme.fgDim
                            }
                        }
                    }

                    // Corner brackets (+)
                    Text { text: "+"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(11); font.bold: true; color: cardNodeBottom.isCurrentTarget ? "#8ee8a8" : Qt.rgba(255,255,255,0.4); anchors.left: parent.left; anchors.top: parent.top; anchors.margins: Theme.px(8); z: 10 }
                    Text { text: "+"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(11); font.bold: true; color: cardNodeBottom.isCurrentTarget ? "#8ee8a8" : Qt.rgba(255,255,255,0.4); anchors.right: parent.right; anchors.top: parent.top; anchors.margins: Theme.px(8); z: 10 }
                    Text { text: "+"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(11); font.bold: true; color: cardNodeBottom.isCurrentTarget ? "#8ee8a8" : Qt.rgba(255,255,255,0.4); anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: Theme.px(8); z: 10 }
                    Text { text: "+"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(11); font.bold: true; color: cardNodeBottom.isCurrentTarget ? "#8ee8a8" : Qt.rgba(255,255,255,0.4); anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: Theme.px(8); z: 10 }

                    // Card Header Bar
                    RowLayout {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.topMargin: Theme.px(10)
                        anchors.leftMargin: Theme.px(20)
                        anchors.rightMargin: Theme.px(20)
                        height: Theme.px(24)
                        spacing: Theme.px(8)
                        z: 10

                        Text {
                            text: "// NODE [" + cardNodeBottom.nodeX + ", " + cardNodeBottom.nodeY + "] :: " + cardNodeBottom.cardTitle
                            font.family: Theme.fontMono || "monospace"
                            font.pixelSize: Theme.fontPx(11)
                            font.weight: Font.Bold
                            color: cardNodeBottom.isCurrentTarget ? "#8ee8a8" : Theme.fg
                        }

                        Item { Layout.fillWidth: true }

                        Rectangle {
                            visible: cardNodeBottom.isCurrentTarget && !commandCenterWindow.isOverview
                            Layout.preferredHeight: Theme.px(18)
                            Layout.preferredWidth: cardNodeBottomHintText.implicitWidth + Theme.px(12)
                            radius: Theme.px(4)
                            color: cardNodeBottomHintHover.hovered ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.12) : Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.05)
                            border.color: Qt.rgba(255, 255, 255, 0.15)
                            border.width: 1

                            HoverHandler { id: cardNodeBottomHintHover }
                            Text {
                                id: cardNodeBottomHintText
                                anchors.centerIn: parent
                                text: "OVERVIEW (ESC)"
                                font.family: Theme.fontMono || "monospace"
                                font.pixelSize: Theme.fontPx(8.5)
                                font.bold: true
                                color: Theme.fgDim
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: commandCenterWindow.zoomToOverview()
                            }
                        }
                    }

                    Item {
                        anchors.fill: parent
                        anchors.margins: Theme.px(16)
                        anchors.topMargin: Theme.px(44)
                        clip: true

                                    Item {
                id: systemTelemetryView
                width: parent.width
                height: parent.height
                x: 0
                opacity: 1.0
                visible: true

                Behavior on x {
                    NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                }
                Behavior on opacity {
                    NumberAnimation { duration: 200 }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.px(4)
                    anchors.rightMargin: Theme.px(4)
                    anchors.topMargin: Theme.px(2)
                    anchors.bottomMargin: Theme.px(6)
                    spacing: Theme.px(10)

                    // ═════════════════════════════════════════════════════════
                    // LEFT TILE: COMBINED CPU / THERMALS & RAM / SWAP (SCROLLABLE)
                    // ═════════════════════════════════════════════════════════
                    Rectangle {
                        id: telemetryLeftTile
                        Layout.preferredWidth: Theme.px(204)
                        Layout.preferredHeight: Theme.px(276)
                        Layout.maximumHeight: Theme.px(276)
                        Layout.alignment: Qt.AlignTop
                        radius: Theme.px(10)
                        color: Qt.rgba(12/255, 14/255, 18/255, 0.65)
                        border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.22)
                        border.width: 1

                        // Top rim highlight
                        Rectangle {
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: Theme.px(10)
                            anchors.rightMargin: Theme.px(10)
                            height: 1
                            color: Qt.rgba(255/255, 255/255, 255/255, 0.12)
                        }

                        // Mouse wheel / Touchpad scroll handler to toggle between CPU and RAM
                        WheelHandler {
                            id: leftTileWheel
                            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                            onWheel: (event) => {
                                commandCenterWindow.handleTelemetryScroll(event.angleDelta.y)
                            }
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: Theme.px(10)
                            spacing: Theme.px(6)

                            // ── Header Tabs: CPU vs RAM ──
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.px(4)

                                Text {
                                    text: commandCenterWindow.telemetrySubMode === "cpu" ? "speed" : "memory"
                                    font.family: Theme.fontIcon
                                    font.pixelSize: Theme.fontPx(14)
                                    color: Theme.accent
                                }

                                Text {
                                    text: commandCenterWindow.telemetrySubMode === "cpu" ? "PROCESSOR" : "MEMORY"
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontPx(10)
                                    font.weight: Font.Bold
                                    color: Theme.fgDim
                                }

                                Item { Layout.fillWidth: true }

                                // Interactive Pill Toggle: CPU
                                Rectangle {
                                    Layout.preferredHeight: Theme.px(18)
                                    Layout.preferredWidth: cpuTabTxt.implicitWidth + Theme.px(10)
                                    radius: Theme.px(4)
                                    color: commandCenterWindow.telemetrySubMode === "cpu"
                                        ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.22)
                                        : (cHover.hovered ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.08) : "transparent")
                                    border.color: commandCenterWindow.telemetrySubMode === "cpu"
                                        ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.45)
                                        : Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.12)
                                    border.width: 1

                                    Text {
                                        id: cpuTabTxt
                                        anchors.centerIn: parent
                                        text: "CPU"
                                        font.family: Theme.font
                                        font.pixelSize: Theme.fontPx(8.5)
                                        font.weight: Font.Bold
                                        color: commandCenterWindow.telemetrySubMode === "cpu" ? Theme.accent : Theme.fgDim
                                    }

                                    HoverHandler { id: cHover }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: commandCenterWindow.telemetrySubMode = "cpu"
                                    }
                                }

                                // Interactive Pill Toggle: RAM
                                Rectangle {
                                    Layout.preferredHeight: Theme.px(18)
                                    Layout.preferredWidth: ramTabTxt.implicitWidth + Theme.px(10)
                                    radius: Theme.px(4)
                                    color: commandCenterWindow.telemetrySubMode === "ram"
                                        ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.22)
                                        : (rmHover.hovered ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.08) : "transparent")
                                    border.color: commandCenterWindow.telemetrySubMode === "ram"
                                        ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.45)
                                        : Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.12)
                                    border.width: 1

                                    Text {
                                        id: ramTabTxt
                                        anchors.centerIn: parent
                                        text: "RAM"
                                        font.family: Theme.font
                                        font.pixelSize: Theme.fontPx(8.5)
                                        font.weight: Font.Bold
                                        color: commandCenterWindow.telemetrySubMode === "ram" ? Theme.accent : Theme.fgDim
                                    }

                                    HoverHandler { id: rmHover }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: commandCenterWindow.telemetrySubMode = "ram"
                                    }
                                }
                            }

                            // ── Viewport Area: Cross-fade between CPU & RAM ──
                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                clip: true

                                // ───────────── CPU & THERMALS SUB-VIEW ─────────────
                                Item {
                                    id: cpuSubView
                                    anchors.fill: parent
                                    opacity: commandCenterWindow.telemetrySubMode === "cpu" ? 1.0 : 0.0
                visible: true

                                    Behavior on opacity {
                                        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                                    }

                                    ColumnLayout {
                                        anchors.fill: parent
                                        spacing: Theme.px(5)

                                        // Primary Load % + Temp Badge
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: Theme.px(6)

                                            Text {
                                                text: (commandCenterWindow.telemetryPayload ? commandCenterWindow.telemetryPayload.cpu_usage.toFixed(1) : "0.0") + "%"
                                                font.family: Theme.font
                                                font.pixelSize: Theme.fontPx(25)
                                                font.weight: Font.Bold
                                                color: "white"
                                            }

                                            Item { Layout.fillWidth: true }

                                            // Temp Badge
                                            Rectangle {
                                                id: tempBadgeRect
                                                Layout.preferredHeight: Theme.px(22)
                                                Layout.preferredWidth: tempBadgeRow.implicitWidth + Theme.px(16)
                                                radius: Theme.px(4)
                                                property real t: commandCenterWindow.telemetryPayload ? commandCenterWindow.telemetryPayload.cpu_temp : 0.0
                                                color: t >= 85 ? Qt.rgba(1.0, 0.25, 0.25, 0.20) : (t >= 75 ? Qt.rgba(1.0, 0.7, 0.2, 0.20) : Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18))
                                                border.color: t >= 85 ? Qt.rgba(1.0, 0.35, 0.35, 0.45) : (t >= 75 ? Qt.rgba(1.0, 0.7, 0.2, 0.45) : Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.40))
                                                border.width: 1

                                                RowLayout {
                                                    id: tempBadgeRow
                                                    anchors.centerIn: parent
                                                    spacing: Theme.px(3)

                                                    Text {
                                                        text: "device_thermostat"
                                                        font.family: Theme.fontIcon
                                                        font.pixelSize: Theme.fontPx(11)
                                                        color: tempBadgeRect.t >= 85 ? (Theme.err || "#f87171") : (tempBadgeRect.t >= 75 ? (Theme.warn || "#fbbf24") : Theme.accent)
                                                    }

                                                    Text {
                                                        id: cpuTempText
                                                        text: (commandCenterWindow.telemetryPayload && commandCenterWindow.telemetryPayload.cpu_temp > 0 ? commandCenterWindow.telemetryPayload.cpu_temp.toFixed(0) : "--") + "°C"
                                                        font.family: Theme.fontMono
                                                        font.pixelSize: Theme.fontPx(9.5)
                                                        font.bold: true
                                                        color: tempBadgeRect.t >= 85 ? (Theme.err || "#f87171") : (tempBadgeRect.t >= 75 ? (Theme.warn || "#fbbf24") : Theme.accent)
                                                    }
                                                }
                                            }
                                        }

                                        // Global CPU Progress Bar
                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: Theme.px(5)
                                            radius: Theme.px(2.5)
                                            color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.10)

                                            Rectangle {
                                                height: parent.height
                                                radius: parent.radius
                                                width: parent.width * Math.min(1.0, Math.max(0.0, (commandCenterWindow.telemetryPayload ? commandCenterWindow.telemetryPayload.cpu_usage : 0.0) / 100.0))
                                                color: (commandCenterWindow.telemetryPayload && commandCenterWindow.telemetryPayload.cpu_usage >= 85) ? Theme.error : Theme.accent
                                                Behavior on width { NumberAnimation { duration: 180 } }
                                            }
                                        }

                                        // Luminous Divider
                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 1
                                            color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.16)
                                        }

                                        // Logical Cores Row
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: Theme.px(6)

                                            Text {
                                                text: "developer_board"
                                                font.family: Theme.fontIcon
                                                font.pixelSize: Theme.fontPx(13)
                                                color: Theme.accent
                                            }

                                            Text {
                                                text: "LOGICAL CORES"
                                                font.family: Theme.font
                                                font.pixelSize: Theme.fontPx(9)
                                                font.weight: Font.DemiBold
                                                color: Theme.fgDim
                                            }

                                            Item { Layout.fillWidth: true }

                                            Text {
                                                text: (commandCenterWindow.telemetryPayload && commandCenterWindow.telemetryPayload.cpu_cores ? commandCenterWindow.telemetryPayload.cpu_cores.length : 0) + " Cores"
                                                font.family: Theme.font
                                                font.pixelSize: Theme.fontPx(9.5)
                                                font.weight: Font.Medium
                                                color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.85)
                                            }
                                        }

                                        // System Uptime Row
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: Theme.px(6)

                                            Text {
                                                text: "schedule"
                                                font.family: Theme.fontIcon
                                                font.pixelSize: Theme.fontPx(13)
                                                color: Theme.accent
                                            }

                                            Text {
                                                text: "UPTIME"
                                                font.family: Theme.font
                                                font.pixelSize: Theme.fontPx(9)
                                                font.weight: Font.DemiBold
                                                color: Theme.fgDim
                                            }

                                            Item { Layout.fillWidth: true }

                                            Text {
                                                text: commandCenterWindow.telemetryPayload ? commandCenterWindow.telemetryPayload.uptime_formatted : "--"
                                                font.family: Theme.font
                                                font.pixelSize: Theme.fontPx(9.5)
                                                font.weight: Font.Medium
                                                color: Theme.accent
                                            }
                                        }

                                        // Kernel Row
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: Theme.px(6)

                                            Text {
                                                text: "terminal"
                                                font.family: Theme.fontIcon
                                                font.pixelSize: Theme.fontPx(13)
                                                color: Theme.accent
                                            }

                                            Text {
                                                text: "KERNEL"
                                                font.family: Theme.font
                                                font.pixelSize: Theme.fontPx(9)
                                                font.weight: Font.DemiBold
                                                color: Theme.fgDim
                                            }

                                            Item { Layout.fillWidth: true }

                                            Text {
                                                text: commandCenterWindow.telemetryPayload ? commandCenterWindow.telemetryPayload.kernel_version : "Linux"
                                                font.family: Theme.font
                                                font.pixelSize: Theme.fontPx(9)
                                                font.weight: Font.Medium
                                                color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.85)
                                                elide: Text.ElideRight
                                                Layout.maximumWidth: Theme.px(100)
                                            }
                                        }

                                        Item { Layout.fillHeight: true }

                                        // Bottom Scroll Hint
                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: Theme.px(20)
                                            radius: Theme.px(5)
                                            color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.04)
                                            border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.10)
                                            border.width: 1

                                            RowLayout {
                                                anchors.centerIn: parent
                                                spacing: Theme.px(4)

                                                Text {
                                                    text: "swap_vert"
                                                    font.family: Theme.fontIcon
                                                    font.pixelSize: Theme.fontPx(11)
                                                    color: Theme.accent
                                                }

                                                Text {
                                                    text: "Scroll tile to switch to RAM"
                                                    font.family: Theme.font
                                                    font.pixelSize: Theme.fontPx(8.5)
                                                    font.weight: Font.Medium
                                                    color: Theme.fgDim
                                                }
                                            }
                                        }
                                    }
                                }

                                // ───────────── RAM & SWAP SUB-VIEW ─────────────
                                Item {
                                    id: ramSubView
                                    anchors.fill: parent
                                    opacity: commandCenterWindow.telemetrySubMode === "ram" ? 1.0 : 0.0
                visible: true

                                    property real ramUsed: commandCenterWindow.telemetryPayload ? (commandCenterWindow.telemetryPayload.ram_used_bytes / 1073741824) : 0
                                    property real ramTotal: commandCenterWindow.telemetryPayload ? (commandCenterWindow.telemetryPayload.ram_total_bytes / 1073741824) : 0
                                    property real ramPct: ramTotal > 0 ? (ramUsed / ramTotal * 100) : 0
                                    property real ramFree: Math.max(0, ramTotal - ramUsed)

                                    property real swapUsed: commandCenterWindow.telemetryPayload ? (commandCenterWindow.telemetryPayload.swap_used_bytes / 1073741824) : 0
                                    property real swapTotal: commandCenterWindow.telemetryPayload ? (commandCenterWindow.telemetryPayload.swap_total_bytes / 1073741824) : 0
                                    property real swapPct: swapTotal > 0 ? (swapUsed / swapTotal * 100) : 0

                                    Behavior on opacity {
                                        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                                    }

                                    ColumnLayout {
                                        anchors.fill: parent
                                        spacing: Theme.px(5)

                                        // Primary Load % + Free Badge
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: Theme.px(6)

                                            Text {
                                                text: ramSubView.ramPct.toFixed(0) + "%"
                                                font.family: Theme.font
                                                font.pixelSize: Theme.fontPx(25)
                                                font.weight: Font.Bold
                                                color: "white"
                                            }

                                            Item { Layout.fillWidth: true }

                                            // Free Badge
                                            Rectangle {
                                                id: ramFreeBadgeRect
                                                Layout.preferredHeight: Theme.px(22)
                                                Layout.preferredWidth: ramFreeBadgeRow.implicitWidth + Theme.px(16)
                                                radius: Theme.px(4)
                                                color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18)
                                                border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.40)
                                                border.width: 1

                                                RowLayout {
                                                    id: ramFreeBadgeRow
                                                    anchors.centerIn: parent
                                                    spacing: Theme.px(3)

                                                    Text {
                                                        text: "check_circle"
                                                        font.family: Theme.fontIcon
                                                        font.pixelSize: Theme.fontPx(11)
                                                        color: Theme.accent
                                                    }

                                                    Text {
                                                        id: ramFreeText
                                                        text: ramSubView.ramFree.toFixed(1) + " GB Free"
                                                        font.family: Theme.fontMono
                                                        font.pixelSize: Theme.fontPx(9.5)
                                                        font.bold: true
                                                        color: Theme.accent
                                                    }
                                                }
                                            }
                                        }

                                        // RAM Progress Bar
                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: Theme.px(5)
                                            radius: Theme.px(2.5)
                                            color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.10)

                                            Rectangle {
                                                height: parent.height
                                                radius: parent.radius
                                                width: parent.width * Math.min(1.0, Math.max(0.0, ramSubView.ramPct / 100.0))
                                                color: (ramSubView.ramPct >= 90) ? Theme.error : Theme.accent
                                                Behavior on width { NumberAnimation { duration: 180 } }
                                            }
                                        }

                                        // Used / Total RAM Detail
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Text {
                                                text: ramSubView.ramUsed.toFixed(2) + " / " + ramSubView.ramTotal.toFixed(2) + " GB"
                                                font.family: Theme.font
                                                font.pixelSize: Theme.fontPx(9.5)
                                                font.weight: Font.Medium
                                                color: Theme.fgDim
                                            }
                                            Item { Layout.fillWidth: true }
                                            Text {
                                                text: "RAM"
                                                font.family: Theme.font
                                                font.pixelSize: Theme.fontPx(8.5)
                                                font.weight: Font.Bold
                                                color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.50)
                                            }
                                        }

                                        // Luminous Divider
                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 1
                                            color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.16)
                                        }

                                        // ── SWAP Section ──
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: Theme.px(4)

                                            RowLayout {
                                                Layout.fillWidth: true

                                                Text {
                                                    text: "SWAP ALLOCATION"
                                                    font.family: Theme.font
                                                    font.pixelSize: Theme.fontPx(9)
                                                    font.weight: Font.DemiBold
                                                    color: Theme.fgDim
                                                }

                                                Item { Layout.fillWidth: true }

                                                Text {
                                                    text: ramSubView.swapPct.toFixed(0) + "%"
                                                    font.family: Theme.fontMono
                                                    font.pixelSize: Theme.fontPx(10)
                                                    font.bold: true
                                                    color: ramSubView.swapPct > 75 ? (Theme.warn || "#fbbf24") : Theme.accent
                                                }
                                            }

                                            // SWAP Bar
                                            Rectangle {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: Theme.px(5)
                                                radius: Theme.px(2.5)
                                                color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.10)

                                                Rectangle {
                                                    height: parent.height
                                                    radius: parent.radius
                                                    width: parent.width * Math.min(1.0, Math.max(0.0, ramSubView.swapPct / 100.0))
                                                    color: (ramSubView.swapPct >= 80) ? (Theme.warn || "#fbbf24") : Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.75)
                                                    Behavior on width { NumberAnimation { duration: 180 } }
                                                }
                                            }

                                            RowLayout {
                                                Layout.fillWidth: true
                                                Text {
                                                    text: ramSubView.swapUsed.toFixed(2) + " / " + ramSubView.swapTotal.toFixed(2) + " GB"
                                                    font.family: Theme.font
                                                    font.pixelSize: Theme.fontPx(9)
                                                    color: Theme.fgDim
                                                }
                                                Item { Layout.fillWidth: true }
                                                Text {
                                                    text: Math.max(0, ramSubView.swapTotal - ramSubView.swapUsed).toFixed(1) + " GB free"
                                                    font.family: Theme.font
                                                    font.pixelSize: Theme.fontPx(8.5)
                                                    color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.50)
                                                }
                                            }
                                        }

                                        Item { Layout.fillHeight: true }

                                        // Bottom Scroll Hint
                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: Theme.px(20)
                                            radius: Theme.px(5)
                                            color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.04)
                                            border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.10)
                                            border.width: 1

                                            RowLayout {
                                                anchors.centerIn: parent
                                                spacing: Theme.px(4)

                                                Text {
                                                    text: "swap_vert"
                                                    font.family: Theme.fontIcon
                                                    font.pixelSize: Theme.fontPx(11)
                                                    color: Theme.accent
                                                }

                                                Text {
                                                    text: "Scroll tile to switch to CPU"
                                                    font.family: Theme.font
                                                    font.pixelSize: Theme.fontPx(8.5)
                                                    font.weight: Font.Medium
                                                    color: Theme.fgDim
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ═════════════════════════════════════════════════════════
                    // RIGHT TILE: EXPANSIVE SMOOTH ANIMATED TELEMETRY GRAPH
                    // ═════════════════════════════════════════════════════════
                    Rectangle {
                        id: telemetryRightTile
                        Layout.fillWidth: true
                        Layout.preferredHeight: Theme.px(276)
                        Layout.maximumHeight: Theme.px(276)
                        Layout.alignment: Qt.AlignTop
                        radius: Theme.px(10)
                        color: Qt.rgba(12/255, 14/255, 18/255, 0.65)
                        border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.22)
                        border.width: 1

                        // Top rim highlight
                        Rectangle {
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: Theme.px(10)
                            anchors.rightMargin: Theme.px(10)
                            height: 1
                            color: Qt.rgba(255/255, 255/255, 255/255, 0.12)
                        }

                        // Allow scrolling on the graph tile to switch submodes as well
                        WheelHandler {
                            id: rightTileWheel
                            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                            onWheel: (event) => {
                                commandCenterWindow.handleTelemetryScroll(event.angleDelta.y)
                            }
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: Theme.px(10)
                            spacing: Theme.px(6)

                            // ── Header Row: Dynamic Title & Live Value Badge ──
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.px(6)

                                Text {
                                    text: commandCenterWindow.telemetrySubMode === "cpu" ? "show_chart" : "stacked_line_chart"
                                    font.family: Theme.fontIcon
                                    font.pixelSize: Theme.fontPx(15)
                                    color: Theme.accent
                                }

                                Text {
                                    text: commandCenterWindow.telemetrySubMode === "cpu" ? "CPU UTILIZATION HISTORY" : "MEMORY USAGE HISTORY"
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontPx(10.5)
                                    font.weight: Font.DemiBold
                                    color: Theme.fg
                                }

                                Item { Layout.fillWidth: true }

                                // Live Pulsing Status Badge
                                Rectangle {
                                    Layout.preferredHeight: Theme.px(20)
                                    Layout.preferredWidth: liveStatusRow.implicitWidth + Theme.px(14)
                                    radius: Theme.px(10)
                                    color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.12)
                                    border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.28)
                                    border.width: 1

                                    RowLayout {
                                        id: liveStatusRow
                                        anchors.centerIn: parent
                                        spacing: Theme.px(5)

                                        Rectangle {
                                            width: Theme.px(5)
                                            height: Theme.px(5)
                                            radius: Theme.px(2.5)
                                            color: Theme.accent

                                            SequentialAnimation on opacity {
                                                loops: Animation.Infinite
                                                running: commandCenterWindow.currentChannel === "telemetry"
                                                NumberAnimation { to: 0.25; duration: 800; easing.type: Easing.InOutQuad }
                                                NumberAnimation { to: 1.0; duration: 800; easing.type: Easing.InOutQuad }
                                            }
                                        }

                                        Text {
                                            property real curCpu: commandCenterWindow.telemetryPayload ? commandCenterWindow.telemetryPayload.cpu_usage : 0.0
                                            property real curRam: (commandCenterWindow.telemetryPayload && commandCenterWindow.telemetryPayload.ram_total_bytes > 0)
                                                ? ((commandCenterWindow.telemetryPayload.ram_used_bytes / commandCenterWindow.telemetryPayload.ram_total_bytes) * 100)
                                                : 0.0
                                            text: commandCenterWindow.telemetrySubMode === "cpu" 
                                                ? ("LIVE: " + curCpu.toFixed(1) + "%") 
                                                : ("LIVE: " + curRam.toFixed(1) + "%")
                                            font.family: Theme.fontMono
                                            font.pixelSize: Theme.fontPx(9)
                                            font.bold: true
                                            color: Theme.accent
                                        }
                                    }
                                }

                                // Polling Interval Pill
                                Rectangle {
                                    Layout.preferredHeight: Theme.px(20)
                                    Layout.preferredWidth: pollText.implicitWidth + Theme.px(10)
                                    radius: Theme.px(4)
                                    color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.04)
                                    border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.10)
                                    border.width: 1

                                    Text {
                                        id: pollText
                                        anchors.centerIn: parent
                                        text: "2s TICK"
                                        font.family: Theme.font
                                        font.pixelSize: Theme.fontPx(8.5)
                                        font.weight: Font.Medium
                                        color: Theme.fgDim
                                    }
                                }
                            }

                            // ── The Smooth Animated Canvas Area ──
                            Item {
                                id: canvasContainer
                                Layout.fillWidth: true
                                Layout.fillHeight: true

                                // Smooth morph factor between CPU (0.0) and RAM (1.0)
                                property real morphFactor: commandCenterWindow.telemetrySubMode === "ram" ? 1.0 : 0.0

                                Behavior on morphFactor {
                                    NumberAnimation { duration: 320; easing.type: Easing.OutCubic }
                                }

                                onMorphFactorChanged: graphCanvas.requestPaint()

                                Connections {
                                    target: commandCenterWindow
                                    function onCpuHistoryChanged() { graphCanvas.requestPaint() }
                                    function onRamHistoryChanged() { graphCanvas.requestPaint() }
                                    function onStreamPhaseChanged() { graphCanvas.requestPaint() }
                                }

                                Canvas {
                                    id: graphCanvas
                                    anchors.fill: parent
                                    antialiasing: true

                                    onWidthChanged: requestPaint()
                                    onHeightChanged: requestPaint()
                                    onAvailableChanged: { if (available) requestPaint() }

                                    onPaint: {
                                        var ctx = getContext("2d")
                                        ctx.reset()
                                        var w = width
                                        var h = height
                                        if (w <= 0 || h <= 0) return

                                        var leftPad = Theme.px(28)
                                        var rightPad = Theme.px(12)
                                        var topPad = Theme.px(10)
                                        var bottomPad = Theme.px(22)
                                        var plotW = Math.max(10, w - leftPad - rightPad)
                                        var plotH = Math.max(10, h - topPad - bottomPad)

                                        // 1. Draw horizontal grid lines & labels
                                        ctx.lineWidth = 1
                                        var gridSteps = [1.0, 0.75, 0.50, 0.25, 0.0]
                                        for (var g = 0; g < gridSteps.length; g++) {
                                            var step = gridSteps[g]
                                            var gy = topPad + plotH * (1.0 - step)

                                            // Grid Line
                                            ctx.strokeStyle = (step === 0.0)
                                                ? "rgba(255, 255, 255, 0.12)"
                                                : "rgba(255, 255, 255, 0.05)"
                                            ctx.beginPath()
                                            ctx.moveTo(leftPad, gy)
                                            ctx.lineTo(w - rightPad, gy)
                                            ctx.stroke()

                                            // Label
                                            ctx.fillStyle = "rgba(255, 255, 255, 0.32)"
                                            ctx.font = Theme.fontPx(7.5) + "px 'Plus Jakarta Sans', sans-serif"
                                            ctx.textAlign = "right"
                                            ctx.textBaseline = "middle"
                                            ctx.fillText(Math.round(step * 100) + "%", leftPad - Theme.px(4), gy)
                                        }

                                        // 2. Fetch history and interpolate with morphFactor and continuous streamPhase
                                        var cpuArr = commandCenterWindow.cpuHistory || []
                                        var ramArr = commandCenterWindow.ramHistory || []
                                        var count = Math.max(cpuArr.length, ramArr.length)
                                        if (count < 2) return

                                        var morph = canvasContainer.morphFactor
                                        var phase = commandCenterWindow.streamPhase || 0.0
                                        var denom = count - 2
                                        if (denom <= 0) denom = 1

                                        var points = []
                                        for (var i = 0; i < count; i++) {
                                            var cVal = i < cpuArr.length ? cpuArr[i] : 0
                                            var rVal = i < ramArr.length ? ramArr[i] : 0
                                            var val = (1.0 - morph) * cVal + morph * rVal
                                            val = Math.max(0, Math.min(100, val))

                                            var px = leftPad + ((i - phase) / denom) * plotW
                                            var py = topPad + plotH * (1.0 - (val / 100.0))
                                            points.push({ x: px, y: py, val: val })
                                        }

                                        // Compute dynamic active colors (CPU accent -> RAM vibrant accent)
                                        var cpuR = Math.round((Theme.accent.r || 0.3) * 255)
                                        var cpuG = Math.round((Theme.accent.g || 0.8) * 255)
                                        var cpuB = Math.round((Theme.accent.b || 0.9) * 255)

                                        var ramR = 56
                                        var ramG = 189
                                        var ramB = 248

                                        var curR = Math.round((1.0 - morph) * cpuR + morph * ramR)
                                        var curG = Math.round((1.0 - morph) * cpuG + morph * ramG)
                                        var curB = Math.round((1.0 - morph) * cpuB + morph * ramB)

                                        // 3. Draw spline & gradient clipped to plot area
                                        ctx.save()
                                        ctx.beginPath()
                                        ctx.rect(leftPad, topPad - Theme.px(4), plotW, plotH + Theme.px(8))
                                        ctx.clip()

                                        // 3a. Draw smooth Bézier curve spline path
                                        ctx.beginPath()
                                        ctx.moveTo(points[0].x, points[0].y)
                                        for (var j = 0; j < points.length - 1; j++) {
                                            var p0 = j > 0 ? points[j - 1] : points[j]
                                            var p1 = points[j]
                                            var p2 = points[j + 1]
                                            var p3 = j < points.length - 2 ? points[j + 2] : p2

                                            var cp1x = p1.x + (p2.x - p0.x) / 6
                                            var cp1y = p1.y + (p2.y - p0.y) / 6
                                            var cp2x = p2.x - (p3.x - p1.x) / 6
                                            var cp2y = p2.y - (p3.y - p1.y) / 6

                                            ctx.bezierCurveTo(cp1x, cp1y, cp2x, cp2y, p2.x, p2.y)
                                        }

                                        // 4. Fill gradient area under the curve
                                        ctx.lineTo(points[points.length - 1].x, topPad + plotH)
                                        ctx.lineTo(points[0].x, topPad + plotH)
                                        ctx.closePath()

                                        var grad = ctx.createLinearGradient(0, topPad, 0, topPad + plotH)
                                        grad.addColorStop(0.0, "rgba(" + curR + "," + curG + "," + curB + ", 0.32)")
                                        grad.addColorStop(0.65, "rgba(" + curR + "," + curG + "," + curB + ", 0.08)")
                                        grad.addColorStop(1.0, "rgba(" + curR + "," + curG + "," + curB + ", 0.00)")
                                        ctx.fillStyle = grad
                                        ctx.fill()

                                        // 5. Stroke glowing curve outline
                                        ctx.beginPath()
                                        ctx.moveTo(points[0].x, points[0].y)
                                        for (var k = 0; k < points.length - 1; k++) {
                                            var q0 = k > 0 ? points[k - 1] : points[k]
                                            var q1 = points[k]
                                            var q2 = points[k + 1]
                                            var q3 = k < points.length - 2 ? points[k + 2] : q2

                                            var c1x = q1.x + (q2.x - q0.x) / 6
                                            var c1y = q1.y + (q2.y - q0.y) / 6
                                            var c2x = q2.x - (q3.x - q1.x) / 6
                                            var c2y = q2.y - (q3.y - q1.y) / 6

                                            ctx.bezierCurveTo(c1x, c1y, c2x, c2y, q2.x, q2.y)
                                        }
                                        ctx.lineWidth = Theme.px(2)
                                        ctx.strokeStyle = "rgb(" + curR + "," + curG + "," + curB + ")"
                                        ctx.stroke()

                                        ctx.restore() // restore clipping

                                        // 6. Draw Glowing Endpoint Radar Pip at exact right edge of plot
                                        var pPrev = points[count - 2]
                                        var pNext = points[count - 1]
                                        var rightVal = (1.0 - phase) * pPrev.val + phase * pNext.val
                                        var pipY = topPad + plotH * (1.0 - (rightVal / 100.0))
                                        var pipX = leftPad + plotW

                                        // Halo
                                        ctx.beginPath()
                                        ctx.arc(pipX, pipY, Theme.px(5.5), 0, Math.PI * 2)
                                        ctx.fillStyle = "rgba(" + curR + "," + curG + "," + curB + ", 0.35)"
                                        ctx.fill()
                                        // Core
                                        ctx.beginPath()
                                        ctx.arc(pipX, pipY, Theme.px(2.8), 0, Math.PI * 2)
                                        ctx.fillStyle = "rgb(" + curR + "," + curG + "," + curB + ")"
                                        ctx.fill()
                                        // White center
                                        ctx.beginPath()
                                        ctx.arc(pipX, pipY, Theme.px(1.4), 0, Math.PI * 2)
                                        ctx.fillStyle = "#ffffff"
                                        ctx.fill()

                                        // 7. Time axis legend at the bottom
                                        ctx.fillStyle = "rgba(255, 255, 255, 0.35)"
                                        ctx.font = Theme.fontPx(7.5) + "px 'Plus Jakarta Sans', sans-serif"
                                        ctx.textBaseline = "bottom"
                                        ctx.textAlign = "left"
                                        ctx.fillText("-60s", leftPad, h - Theme.px(4))
                                        ctx.textAlign = "center"
                                        ctx.fillText("-30s", leftPad + plotW / 2, h - Theme.px(4))
                                        ctx.textAlign = "right"
                                        ctx.fillText("NOW", leftPad + plotW, h - Theme.px(4))
                                    }
                                }
                            }
                        }
                    }
                }
            }

                    }
                }

                // ══════════════════════════════════════════════════════════
                // NODE (1, 0) :: CARBON ENGINE
                // ══════════════════════════════════════════════════════════
                Rectangle {
                    id: cardNodeRight
                    readonly property int nodeX: 1
                    readonly property int nodeY: 0
                    readonly property bool isCurrentTarget: (commandCenterWindow.activeGridX === cardNodeRight.nodeX && commandCenterWindow.activeGridY === cardNodeRight.nodeY)
                    readonly property string cardTitle: "CARBON ENGINE & SHELL CONTROLS"
                    readonly property string lodIcon: "tune"
                    readonly property string lodTitle: "CARBON ENGINE"
                    readonly property string lodSubtitle: "Shell Modes, Wallpaper Engine & Visuals"

                    width: viewport.cardWidth
                    height: viewport.cardHeight
                    x: Math.round((viewport.width - width) / 2 + (cardNodeRight.nodeX * viewport.stepX))
                    y: Math.round((viewport.height - height) / 2 + (cardNodeRight.nodeY * viewport.stepY))
                    radius: 16
                    color: Qt.rgba(0.047, 0.055, 0.07, 0.82)
                    border.color: cardNodeRight.isCurrentTarget ? "#8ee8a8" : ((commandCenterWindow.isOverview && cardNodeRightClickArea.containsMouse) ? Qt.rgba(0.557, 0.91, 0.659, 0.6) : Qt.rgba(1, 1, 1, 0.12))
                    border.width: cardNodeRight.isCurrentTarget ? 2 : 1
                    scale: (commandCenterWindow.isOverview && cardNodeRightClickArea.containsMouse) ? 1.03 : 1.0
                    transformOrigin: Item.Center
                    Behavior on scale {
                        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                    }
                    clip: true

                    // Click interception for overview or peeking neighbor cards
                    MouseArea {
                        id: cardNodeRightClickArea
                        anchors.fill: parent
                        enabled: commandCenterWindow.isOverview || (!cardNodeRight.isCurrentTarget)
                        cursorShape: (commandCenterWindow.isOverview || !cardNodeRight.isCurrentTarget) ? Qt.PointingHandCursor : Qt.ArrowCursor
                        hoverEnabled: true
                        z: 500
                        onClicked: {
                            commandCenterWindow.zoomToNode(cardNodeRight.nodeX, cardNodeRight.nodeY)
                        }
                    }

                    // Level-of-Detail (LOD) Watermark Overlay for Overview Mode
                    Item {
                        id: cardNodeRightLodOverlay
                        anchors.fill: parent
                        z: 400
                        opacity: commandCenterWindow.isOverview ? 0.92 : 0.0
                        visible: opacity > 0.01
                        Behavior on opacity {
                            NumberAnimation { duration: 350; easing.type: Easing.OutCubic }
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: 16
                            color: Qt.rgba(0.04, 0.05, 0.07, 0.78)
                        }

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: Theme.px(10)

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: cardNodeRight.lodIcon
                                font.family: Theme.fontIcon
                                font.pixelSize: Theme.fontPx(64)
                                color: cardNodeRight.isCurrentTarget ? "#8ee8a8" : Qt.rgba(255, 255, 255, 0.90)
                            }

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: cardNodeRight.lodTitle
                                font.family: Theme.fontMono || "monospace"
                                font.pixelSize: Theme.fontPx(20)
                                font.bold: true
                                color: cardNodeRight.isCurrentTarget ? "#8ee8a8" : Theme.fg
                            }

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: cardNodeRight.lodSubtitle
                                font.family: Theme.font
                                font.pixelSize: Theme.fontPx(13)
                                color: Theme.fgDim
                            }
                        }
                    }

                    // Corner brackets (+)
                    Text { text: "+"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(11); font.bold: true; color: cardNodeRight.isCurrentTarget ? "#8ee8a8" : Qt.rgba(255,255,255,0.4); anchors.left: parent.left; anchors.top: parent.top; anchors.margins: Theme.px(8); z: 10 }
                    Text { text: "+"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(11); font.bold: true; color: cardNodeRight.isCurrentTarget ? "#8ee8a8" : Qt.rgba(255,255,255,0.4); anchors.right: parent.right; anchors.top: parent.top; anchors.margins: Theme.px(8); z: 10 }
                    Text { text: "+"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(11); font.bold: true; color: cardNodeRight.isCurrentTarget ? "#8ee8a8" : Qt.rgba(255,255,255,0.4); anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.margins: Theme.px(8); z: 10 }
                    Text { text: "+"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(11); font.bold: true; color: cardNodeRight.isCurrentTarget ? "#8ee8a8" : Qt.rgba(255,255,255,0.4); anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: Theme.px(8); z: 10 }

                    // Card Header Bar
                    RowLayout {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.topMargin: Theme.px(10)
                        anchors.leftMargin: Theme.px(20)
                        anchors.rightMargin: Theme.px(20)
                        height: Theme.px(24)
                        spacing: Theme.px(8)
                        z: 10

                        Text {
                            text: "// NODE [" + cardNodeRight.nodeX + ", " + cardNodeRight.nodeY + "] :: " + cardNodeRight.cardTitle
                            font.family: Theme.fontMono || "monospace"
                            font.pixelSize: Theme.fontPx(11)
                            font.weight: Font.Bold
                            color: cardNodeRight.isCurrentTarget ? "#8ee8a8" : Theme.fg
                        }

                        Item { Layout.fillWidth: true }

                        Rectangle {
                            visible: cardNodeRight.isCurrentTarget && !commandCenterWindow.isOverview
                            Layout.preferredHeight: Theme.px(18)
                            Layout.preferredWidth: cardNodeRightHintText.implicitWidth + Theme.px(12)
                            radius: Theme.px(4)
                            color: cardNodeRightHintHover.hovered ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.12) : Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.05)
                            border.color: Qt.rgba(255, 255, 255, 0.15)
                            border.width: 1

                            HoverHandler { id: cardNodeRightHintHover }
                            Text {
                                id: cardNodeRightHintText
                                anchors.centerIn: parent
                                text: "OVERVIEW (ESC)"
                                font.family: Theme.fontMono || "monospace"
                                font.pixelSize: Theme.fontPx(8.5)
                                font.bold: true
                                color: Theme.fgDim
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: commandCenterWindow.zoomToOverview()
                            }
                        }
                    }

                Item {
                    anchors.fill: parent
                    anchors.margins: Theme.px(16)
                    anchors.topMargin: Theme.px(44)

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: Theme.px(12)

                        // Section 1: Shell Mode Switcher
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.px(6)

                            Text {
                                text: "SHELL ARCHITECTURE & BAR MODES"
                                font.family: Theme.fontMono || "monospace"
                                font.pixelSize: Theme.fontPx(10)
                                font.weight: Font.Bold
                                color: "#8ee8a8"
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.px(10)

                                // Mode 1: Notch
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: Theme.px(76)
                                    radius: Theme.px(8)
                                    color: commandCenterWindow.barMode === "notch" ? Qt.rgba(0.55, 0.91, 0.66, 0.12) : Qt.rgba(0.08, 0.10, 0.14, 0.7)
                                    border.color: commandCenterWindow.barMode === "notch" ? "#8ee8a8" : (m1Hover.hovered ? Qt.rgba(0.55, 0.91, 0.66, 0.4) : Qt.rgba(255, 255, 255, 0.12))
                                    border.width: commandCenterWindow.barMode === "notch" ? 1.5 : 1

                                    HoverHandler { id: m1Hover }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: commandCenterWindow.applyBarMode("notch")
                                    }

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: Theme.px(10)
                                        spacing: Theme.px(4)

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: Theme.px(6)
                                            Text { text: "dock_to_bottom"; font.family: Theme.fontIcon; font.pixelSize: Theme.fontPx(16); color: commandCenterWindow.barMode === "notch" ? "#8ee8a8" : Theme.fg }
                                            Text { text: "Notch Dynamic Island"; font.family: Theme.font; font.pixelSize: Theme.fontPx(12.5); font.bold: true; color: commandCenterWindow.barMode === "notch" ? "#8ee8a8" : Theme.fg }
                                            Item { Layout.fillWidth: true }
                                            Rectangle {
                                                visible: commandCenterWindow.barMode === "notch"
                                                Layout.preferredHeight: Theme.px(16)
                                                Layout.preferredWidth: a1Text.implicitWidth + Theme.px(8)
                                                radius: Theme.px(3)
                                                color: Qt.rgba(0.55, 0.91, 0.66, 0.25)
                                                Text { id: a1Text; anchors.centerIn: parent; text: "ACTIVE"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(8); font.bold: true; color: "#8ee8a8" }
                                            }
                                        }
                                        Text {
                                            text: "Dynamic adaptive top notch with fluid organic spring physics"
                                            font.family: Theme.font
                                            font.pixelSize: Theme.fontPx(9.5)
                                            color: Theme.fgDim
                                            wrapMode: Text.WordWrap
                                            Layout.fillWidth: true
                                        }
                                    }
                                }

                                // Mode 2: Vanish
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: Theme.px(76)
                                    radius: Theme.px(8)
                                    color: commandCenterWindow.barMode === "vanish" ? Qt.rgba(0.55, 0.91, 0.66, 0.12) : Qt.rgba(0.08, 0.10, 0.14, 0.7)
                                    border.color: commandCenterWindow.barMode === "vanish" ? "#8ee8a8" : (m2Hover.hovered ? Qt.rgba(0.55, 0.91, 0.66, 0.4) : Qt.rgba(255, 255, 255, 0.12))
                                    border.width: commandCenterWindow.barMode === "vanish" ? 1.5 : 1

                                    HoverHandler { id: m2Hover }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: commandCenterWindow.applyBarMode("vanish")
                                    }

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: Theme.px(10)
                                        spacing: Theme.px(4)

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: Theme.px(6)
                                            Text { text: "visibility_off"; font.family: Theme.fontIcon; font.pixelSize: Theme.fontPx(16); color: commandCenterWindow.barMode === "vanish" ? "#8ee8a8" : Theme.fg }
                                            Text { text: "Vanish"; font.family: Theme.font; font.pixelSize: Theme.fontPx(12.5); font.bold: true; color: commandCenterWindow.barMode === "vanish" ? "#8ee8a8" : Theme.fg }
                                            Item { Layout.fillWidth: true }
                                            Rectangle {
                                                visible: commandCenterWindow.barMode === "vanish"
                                                Layout.preferredHeight: Theme.px(16)
                                                Layout.preferredWidth: a2Text.implicitWidth + Theme.px(8)
                                                radius: Theme.px(3)
                                                color: Qt.rgba(0.55, 0.91, 0.66, 0.25)
                                                Text { id: a2Text; anchors.centerIn: parent; text: "ACTIVE"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(8); font.bold: true; color: "#8ee8a8" }
                                            }
                                        }
                                        Text {
                                            text: "Zero desktop clutter with smart gesture reveal and border glow"
                                            font.family: Theme.font
                                            font.pixelSize: Theme.fontPx(9.5)
                                            color: Theme.fgDim
                                            wrapMode: Text.WordWrap
                                            Layout.fillWidth: true
                                        }
                                    }
                                }

                                // Mode 3: Minimal
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: Theme.px(76)
                                    radius: Theme.px(8)
                                    color: commandCenterWindow.barMode === "minimal" ? Qt.rgba(0.55, 0.91, 0.66, 0.12) : Qt.rgba(0.08, 0.10, 0.14, 0.7)
                                    border.color: commandCenterWindow.barMode === "minimal" ? "#8ee8a8" : (m3Hover.hovered ? Qt.rgba(0.55, 0.91, 0.66, 0.4) : Qt.rgba(255, 255, 255, 0.12))
                                    border.width: commandCenterWindow.barMode === "minimal" ? 1.5 : 1

                                    HoverHandler { id: m3Hover }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: commandCenterWindow.applyBarMode("minimal")
                                    }

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: Theme.px(10)
                                        spacing: Theme.px(4)

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: Theme.px(6)
                                            Text { text: "horizontal_distribute"; font.family: Theme.fontIcon; font.pixelSize: Theme.fontPx(16); color: commandCenterWindow.barMode === "minimal" ? "#8ee8a8" : Theme.fg }
                                            Text { text: "Minimal Monoline"; font.family: Theme.font; font.pixelSize: Theme.fontPx(12.5); font.bold: true; color: commandCenterWindow.barMode === "minimal" ? "#8ee8a8" : Theme.fg }
                                            Item { Layout.fillWidth: true }
                                            Rectangle {
                                                visible: commandCenterWindow.barMode === "minimal"
                                                Layout.preferredHeight: Theme.px(16)
                                                Layout.preferredWidth: a3Text.implicitWidth + Theme.px(8)
                                                radius: Theme.px(3)
                                                color: Qt.rgba(0.55, 0.91, 0.66, 0.25)
                                                Text { id: a3Text; anchors.centerIn: parent; text: "ACTIVE"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(8); font.bold: true; color: "#8ee8a8" }
                                            }
                                        }
                                        Text {
                                            text: "Ultra-slim 26px compact persistent bar for maximal screen efficiency"
                                            font.family: Theme.font
                                            font.pixelSize: Theme.fontPx(9.5)
                                            color: Theme.fgDim
                                            wrapMode: Text.WordWrap
                                            Layout.fillWidth: true
                                        }
                                    }
                                }
                            }
                        }

                        // Section 2: Wallpaper Engine & Visual Tuner
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: Theme.px(10)

                            // Current Wallpaper Preview Box
                            Rectangle {
                                Layout.preferredWidth: Theme.px(280)
                                Layout.fillHeight: true
                                radius: Theme.px(8)
                                color: Qt.rgba(0.06, 0.08, 0.11, 0.8)
                                border.color: Qt.rgba(255, 255, 255, 0.12)
                                border.width: 1
                                clip: true

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: Theme.px(10)
                                    spacing: Theme.px(6)

                                    Text {
                                        text: "CURRENT ACTIVE WALLPAPER"
                                        font.family: Theme.fontMono || "monospace"
                                        font.pixelSize: Theme.fontPx(9.5)
                                        font.bold: true
                                        color: "#8ee8a8"
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        radius: Theme.px(6)
                                        color: "#050608"
                                        clip: true

                                        Image {
                                            anchors.fill: parent
                                            source: "file://" + (Quickshell.env("HOME") || "") + "/.config/hypr/current_wallpaper"
                                            fillMode: Image.PreserveAspectCrop
                                        }
                                    }

                                    // Open Wallpaper Picker Button
                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: Theme.px(28)
                                        radius: Theme.px(4)
                                        color: wpBtnHover.hovered ? Qt.rgba(0.55, 0.91, 0.66, 0.25) : Qt.rgba(0.55, 0.91, 0.66, 0.12)
                                        border.color: "#8ee8a8"
                                        border.width: 1

                                        HoverHandler { id: wpBtnHover }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                commandCenterWindow.execCommand("sh ~/.config/hypr/scripts/carbon-ipc.sh wallpaper")
                                                commandCenterWindow.closeRequested()
                                            }
                                        }

                                        RowLayout {
                                            anchors.centerIn: parent
                                            spacing: Theme.px(6)
                                            Text { text: "wallpaper"; font.family: Theme.fontIcon; font.pixelSize: Theme.fontPx(14); color: "#8ee8a8" }
                                            Text { text: "OPEN WALLPAPER PICKER"; font.family: Theme.fontMono || "monospace"; font.pixelSize: Theme.fontPx(9.5); font.bold: true; color: "#8ee8a8" }
                                        }
                                    }
                                }
                            }

                            // Quick Actions & Compositor Controls
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: Theme.px(8)
                                color: Qt.rgba(0.06, 0.08, 0.11, 0.8)
                                border.color: Qt.rgba(255, 255, 255, 0.12)
                                border.width: 1
                                clip: true

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: Theme.px(12)
                                    spacing: Theme.px(10)

                                    Text {
                                        text: "ENGINE CONTROLS & UTILITIES"
                                        font.family: Theme.fontMono || "monospace"
                                        font.pixelSize: Theme.fontPx(10)
                                        font.bold: true
                                        color: "#8ee8a8"
                                    }

                                    GridLayout {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        columns: 2
                                        columnSpacing: Theme.px(10)
                                        rowSpacing: Theme.px(10)

                                        // 1. Matugen Palette Rebuild
                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            radius: Theme.px(6)
                                            color: b1Hover.hovered ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.08) : Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.04)
                                            border.color: Qt.rgba(255, 255, 255, 0.12)
                                            border.width: 1

                                            HoverHandler { id: b1Hover }
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    commandCenterWindow.execCommand("python3 ~/.config/hypr/scripts/theme-mk.py ~/.config/hypr/current_wallpaper")
                                                    commandCenterWindow.showFeedback("Regenerating theme palette (Matugen)...")
                                                }
                                            }

                                            ColumnLayout {
                                                anchors.centerIn: parent
                                                spacing: Theme.px(4)
                                                Text { Layout.alignment: Qt.AlignHCenter; text: "palette"; font.family: Theme.fontIcon; font.pixelSize: Theme.fontPx(20); color: "#8ee8a8" }
                                                Text { Layout.alignment: Qt.AlignHCenter; text: "Regenerate Palette"; font.family: Theme.font; font.pixelSize: Theme.fontPx(11.5); font.bold: true; color: Theme.fg }
                                                Text { Layout.alignment: Qt.AlignHCenter; text: "Matugen M3 extraction"; font.family: Theme.font; font.pixelSize: Theme.fontPx(8.5); color: Theme.fgDim }
                                            }
                                        }

                                        // 2. Video Wallpaper Toggle (mpvpaper)
                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            radius: Theme.px(6)
                                            color: b2Hover.hovered ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.08) : Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.04)
                                            border.color: Qt.rgba(255, 255, 255, 0.12)
                                            border.width: 1

                                            HoverHandler { id: b2Hover }
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    commandCenterWindow.execCommand("if pgrep -x mpvpaper >/dev/null; then pkill -f mpvpaper; else sh ~/.config/hypr/scripts/carbon-ipc.sh wallpaper-live; fi")
                                                    commandCenterWindow.showFeedback("Toggling live wallpaper...")
                                                }
                                            }

                                            ColumnLayout {
                                                anchors.centerIn: parent
                                                spacing: Theme.px(4)
                                                Text { Layout.alignment: Qt.AlignHCenter; text: "smart_display"; font.family: Theme.fontIcon; font.pixelSize: Theme.fontPx(20); color: "#8ee8a8" }
                                                Text { Layout.alignment: Qt.AlignHCenter; text: "Live Video Wallpaper"; font.family: Theme.font; font.pixelSize: Theme.fontPx(11.5); font.bold: true; color: Theme.fg }
                                                Text { Layout.alignment: Qt.AlignHCenter; text: "mpvpaper engine"; font.family: Theme.font; font.pixelSize: Theme.fontPx(8.5); color: Theme.fgDim }
                                            }
                                        }

                                        // 3. Night Light Toggle
                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            radius: Theme.px(6)
                                            color: b3Hover.hovered ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.08) : Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.04)
                                            border.color: Qt.rgba(255, 255, 255, 0.12)
                                            border.width: 1

                                            HoverHandler { id: b3Hover }
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    commandCenterWindow.execCommand("sh ~/.config/hypr/scripts/carbon-night.sh toggle")
                                                    commandCenterWindow.showFeedback("Toggled Night Light")
                                                }
                                            }

                                            ColumnLayout {
                                                anchors.centerIn: parent
                                                spacing: Theme.px(4)
                                                Text { Layout.alignment: Qt.AlignHCenter; text: "nightlight"; font.family: Theme.fontIcon; font.pixelSize: Theme.fontPx(20); color: "#8ee8a8" }
                                                Text { Layout.alignment: Qt.AlignHCenter; text: "Night Light"; font.family: Theme.font; font.pixelSize: Theme.fontPx(11.5); font.bold: true; color: Theme.fg }
                                                Text { Layout.alignment: Qt.AlignHCenter; text: "Warm temperature filter"; font.family: Theme.font; font.pixelSize: Theme.fontPx(8.5); color: Theme.fgDim }
                                            }
                                        }

                                        // 4. Reload Hyprland Compositor
                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            radius: Theme.px(6)
                                            color: b4Hover.hovered ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.08) : Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.04)
                                            border.color: Qt.rgba(255, 255, 255, 0.12)
                                            border.width: 1

                                            HoverHandler { id: b4Hover }
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    commandCenterWindow.execCommand("hyprctl reload")
                                                    commandCenterWindow.showFeedback("Hyprland reloaded")
                                                }
                                            }

                                            ColumnLayout {
                                                anchors.centerIn: parent
                                                spacing: Theme.px(4)
                                                Text { Layout.alignment: Qt.AlignHCenter; text: "refresh"; font.family: Theme.fontIcon; font.pixelSize: Theme.fontPx(20); color: "#8ee8a8" }
                                                Text { Layout.alignment: Qt.AlignHCenter; text: "Reload Compositor"; font.family: Theme.font; font.pixelSize: Theme.fontPx(11.5); font.bold: true; color: Theme.fg }
                                                Text { Layout.alignment: Qt.AlignHCenter; text: "hyprctl reload"; font.family: Theme.font; font.pixelSize: Theme.fontPx(8.5); color: Theme.fgDim }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                }
            } // cardNodeRight

        } // spatialWorld
    } // cameraZoomRig
} // viewport
} // container
}
