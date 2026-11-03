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

    onIsOpenChanged: {
        if (!isOpen) {
            animatingOut = true
            closeAnimTimer.restart()
        } else {
            animatingOut = false
            closeAnimTimer.stop()
            commandCenterWindow.refreshWeather()
            commandCenterWindow.currentChannel = "overview"
            calSyncProc.running = true
            centerKeyHandler.forceActiveFocus()
        }
    }

    Timer {
        id: closeAnimTimer
        interval: 320
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
    property string currentChannel: "overview" // "overview" | "github"
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
        width: commandCenterWindow.width
        height: commandCenterWindow.height

        // Full-surface keyboard handler for immediate arrow and escape keys
        Item {
            id: centerKeyHandler
            anchors.fill: parent
            focus: commandCenterWindow.isOpen
            Keys.enabled: commandCenterWindow.isOpen
            Keys.onPressed: (event) => {
                if (event.key === Qt.Key_Escape) {
                    commandCenterWindow.closeRequested()
                    event.accepted = true
                } else if (event.key === Qt.Key_Right) {
                    if (commandCenterWindow.currentChannel === "overview") {
                        commandCenterWindow.currentChannel = "github"
                        githubUplinkView.contentY = 0
                        event.accepted = true
                    }
                } else if (event.key === Qt.Key_Left) {
                    if (commandCenterWindow.currentChannel === "github") {
                        commandCenterWindow.currentChannel = "overview"
                        event.accepted = true
                    }
                } else if (event.key === Qt.Key_Down) {
                    if (commandCenterWindow.currentChannel === "github") {
                        commandCenterWindow.scrollGithubBottom()
                        event.accepted = true
                    }
                } else if (event.key === Qt.Key_Up) {
                    if (commandCenterWindow.currentChannel === "github") {
                        commandCenterWindow.scrollGithubTop()
                        event.accepted = true
                    }
                }
            }
        }

        // Transparent dismiss surface (zero screen dimming, matching notch center panel)
        MouseArea {
            anchors.fill: parent
            enabled: commandCenterWindow.isOpen
            onClicked: commandCenterWindow.closeRequested()
        }

        // ── Main Compact Floating Card ──
        Rectangle {
            id: mainPanel
            focus: true
            Keys.onEscapePressed: function(event) {
                commandCenterWindow.closeRequested()
                if (event) event.accepted = true
            }
            Keys.onRightPressed: function(event) {
                if (commandCenterWindow.currentChannel === "overview") {
                    commandCenterWindow.currentChannel = "github"
                    githubUplinkView.contentY = 0
                    if (event) event.accepted = true
                }
            }
            Keys.onLeftPressed: function(event) {
                if (commandCenterWindow.currentChannel === "github") {
                    commandCenterWindow.currentChannel = "overview"
                    if (event) event.accepted = true
                }
            }
            Keys.onDownPressed: function(event) {
                if (commandCenterWindow.currentChannel === "github") {
                    commandCenterWindow.scrollGithubBottom()
                    if (event) event.accepted = true
                }
            }
            Keys.onUpPressed: function(event) {
                if (commandCenterWindow.currentChannel === "github") {
                    commandCenterWindow.scrollGithubTop()
                    if (event) event.accepted = true
                }
            }
            width: Math.min(Theme.px(640), container.width - Theme.px(32))
            height: Theme.px(360)
            x: Math.round((container.width - width) / 2)

            // THE DYNAMIC POSITIONING ENGINE
            y: {
                if (!commandCenterWindow.isOpen || commandCenterWindow.animatingOut) {
                    // Off-screen positions: completely clear screen boundaries (extra 40px buffer)
                    return commandCenterWindow.isTopBarUp ? (container.height + 40) : (-height - 40);
                } else {
                    // On-screen resting positions (floating 20px from edge)
                    return commandCenterWindow.isTopBarUp ? (container.height - height - 20) : 20;
                }
            }

            opacity: 1.0

            Behavior on y {
                NumberAnimation {
                    duration: (commandCenterWindow.isOpen && !commandCenterWindow.animatingOut) ? 380 : 300
                    easing.type: (commandCenterWindow.isOpen && !commandCenterWindow.animatingOut) ? Easing.OutCubic : Easing.InCubic
                }
            }

            // Carbon Shell Modern Frosted Glass Aesthetic
            color: Theme.isDark ? Qt.rgba(0.06, 0.07, 0.09, 0.90) : Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.90)
            border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.16)
            border.width: 1
            radius: Theme.px(16)
            clip: true

        // Absorb clicks inside card so they don't dismiss
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            preventStealing: true
            onClicked: {}
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.px(12)
            spacing: Theme.px(8)

            // ── Minimal Sleek Header ──
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.px(24)
                Layout.maximumHeight: Theme.px(24)
                spacing: Theme.px(8)

                CarbonLogoIcon {
                    width: Theme.px(18)
                    height: Theme.px(18)
                    Layout.alignment: Qt.AlignVCenter
                    color: commandCenterWindow.engineConnected ? Theme.accent : Theme.fgDim
                }

                Text {
                    text: commandCenterWindow.currentChannel === "github" ? "GitHub Uplink" : "View Point"
                    Layout.alignment: Qt.AlignVCenter
                    font.family: Theme.font
                    font.pixelSize: Theme.fontPx(12)
                    font.weight: Font.DemiBold
                    color: Theme.fg
                }

                // Minimal page indicator dots (smooth indicator for Normal vs GitHub)
                RowLayout {
                    Layout.alignment: Qt.AlignVCenter
                    spacing: Theme.px(4)

                    Rectangle {
                        width: commandCenterWindow.currentChannel === "overview" ? Theme.px(12) : Theme.px(5)
                        height: Theme.px(5)
                        radius: Theme.px(2.5)
                        color: commandCenterWindow.currentChannel === "overview" ? Theme.accent : Qt.rgba(Theme.fgDim.r, Theme.fgDim.g, Theme.fgDim.b, 0.3)
                        Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: 200 } }
                    }

                    Rectangle {
                        width: commandCenterWindow.currentChannel === "github" ? Theme.px(12) : Theme.px(5)
                        height: Theme.px(5)
                        radius: Theme.px(2.5)
                        color: commandCenterWindow.currentChannel === "github" ? Theme.accent : Qt.rgba(Theme.fgDim.r, Theme.fgDim.g, Theme.fgDim.b, 0.3)
                        Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                        Behavior on color { ColorAnimation { duration: 200 } }
                    }
                }

                Item { Layout.fillWidth: true }

                // Action Feedback Badge
                Rectangle {
                    visible: commandCenterWindow.feedbackMessage !== ""
                    Layout.preferredHeight: Theme.px(20)
                    Layout.preferredWidth: fbText.implicitWidth + Theme.px(14)
                    radius: Theme.px(10)
                    color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.15)
                    border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.3)
                    border.width: 1

                    Text {
                        id: fbText
                        anchors.centerIn: parent
                        text: commandCenterWindow.feedbackMessage
                        font.family: Theme.font
                        font.pixelSize: Theme.fontPx(10)
                        font.weight: Font.Medium
                        color: Theme.accent
                    }
                }

                // Refresh Button
                Rectangle {
                    width: Theme.px(24)
                    height: Theme.px(24)
                    radius: Theme.px(12)
                    color: rHover.hovered ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.08) : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "refresh"
                        font.family: Theme.fontIcon
                        font.pixelSize: Theme.fontPx(14)
                        color: rHover.hovered ? Theme.accent : Theme.fgDim
                    }

                    HoverHandler { id: rHover }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: commandCenterWindow.triggerManualRefresh()
                    }
                }

                // Close Button
                Rectangle {
                    width: Theme.px(24)
                    height: Theme.px(24)
                    radius: Theme.px(12)
                    color: cBtnHover.hovered ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.15) : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "close"
                        font.family: Theme.fontIcon
                        font.pixelSize: Theme.fontPx(14)
                        color: cBtnHover.hovered ? Theme.error : Theme.fgDim
                    }

                    HoverHandler { id: cBtnHover }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: commandCenterWindow.closeRequested()
                    }
                }
            }

            // ── Channel Content Viewport ──
            Item {
                id: channelViewport
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                // ── CHANNEL 1: OVERVIEW ──
                ColumnLayout {
                    id: overviewChannelView
                    width: parent.width
                    height: parent.height
                    x: commandCenterWindow.currentChannel === "overview" ? 0 : -channelViewport.width
                    opacity: commandCenterWindow.currentChannel === "overview" ? 1.0 : 0.0
                    visible: opacity > 0.01
                    spacing: Theme.px(8)

                    Behavior on x {
                        NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                    }
                    Behavior on opacity {
                        NumberAnimation { duration: 200 }
                    }

                // ── ROW 1: Obsidian Notes (Left) + Events / Schedule (Right) ──
                RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.px(144)
                Layout.maximumHeight: Theme.px(144)
                spacing: Theme.px(8)

                // ══════════════════════════════════════════════════
                // TILE 1: OBSIDIAN NOTES
                // ══════════════════════════════════════════════════
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

                // ══════════════════════════════════════════════════
                // TILE 2: EVENTS / SCHEDULE (Beside Obsidian Notes)
                // ══════════════════════════════════════════════════
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
            }

            // ── ROW 2: Recent Apps Tile (Left, Compact Landscape Dock) + Clipboard Tile (Right) ──
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.px(144)
                Layout.maximumHeight: Theme.px(144)
                spacing: Theme.px(8)

                // ══════════════════════════════════════════════════
                // TILE 3: RECENT APPS & AESTHETIC CLOCK + WEATHER
                // ══════════════════════════════════════════════════
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: (parent.width - Theme.px(8)) / 2

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

                // ══════════════════════════════════════════════════
                // TILE 4: CLIPBOARD HISTORY (Beside Recent Apps)
                // ══════════════════════════════════════════════════
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: (parent.width - Theme.px(8)) / 2
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
        } // end overviewChannelView

            // ── CHANNEL 2: GITHUB UPLINK (Scrollable to fit 360px height) ──
            Flickable {
                id: githubUplinkView
                width: parent.width
                height: parent.height
                x: commandCenterWindow.currentChannel === "github" ? 0 : channelViewport.width
                opacity: commandCenterWindow.currentChannel === "github" ? 1.0 : 0.0
                visible: opacity > 0.01
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
                        Layout.preferredHeight: githubUplinkView.height
                        Layout.minimumHeight: githubUplinkView.height
                        implicitHeight: githubUplinkView.height
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
        } // closes ColumnLayout of mainPanel
        }
    }
}


