import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import "../Singletons"
import "../components"

/**
 * CenterDashboard: Integrated Landscape Control Center
 * Dimensions: 860x260px (fits expanded notch container & centered panel windows)
 *
 * Left Column (Quick Controls & Sliders):
 *   - System shortcuts: Screen recorder (live timer/stop), Screenshot, Settings, Lock, Power
 *   - 2x2 Quick toggles: Wi-Fi, Bluetooth, Night Light, Do Not Disturb (DND)
 *   - Hardware sliders: Volume (mute toggle, interactive track, live %, wheel) & Brightness (interactive track, live %, wheel)
 *
 * Center Column (Hub: Notifications & Calendar):
 *   - Header tabs: Notifications (with unread badge + Clear all) & Calendar
 *   - Notifications View: Scrollable list of active notifications with app icon, title, body, and dismiss
 *   - Calendar View: Month navigation & dynamic calendar grid
 *
 * Right Column (Media Player & Live Info):
 *   - Live Clock & Weather capsule
 *   - Rich Media Player: Album art / vinyl disc, title, artist, seekable progress bar, play/pause/prev/next
 */
Item {
    id: root

    property bool open: false
    property bool minimalCalendarOnly: false
    property bool attachedBottom: false
    property bool showBackground: true
    readonly property bool hovered: (rootHover && rootHover.hovered) || (mainCardHover && mainCardHover.hovered)
    signal closeRequested()

    implicitWidth: root.minimalCalendarOnly ? 310 : 860
    implicitHeight: root.minimalCalendarOnly ? 276 : 260
    width: implicitWidth
    height: implicitHeight
    clip: true

    readonly property string home: Quickshell.env("HOME") || ""

    focus: root.open
    Keys.enabled: root.open
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Escape) {
            root.closeRequested()
            event.accepted = true
        }
    }
    Keys.onEscapePressed: (event) => {
        root.closeRequested()
        event.accepted = true
    }

    HoverHandler {
        id: rootHover
    }

    readonly property var cardItem: mainCard
    property bool animatingOut: false

    /* ── Live Clock & Date State ─────────────────────────────────────── */
    property var currentDate: new Date()
    property string timeStr: Qt.formatTime(currentDate, "hh:mm")
    property string dateStr: Qt.formatDate(currentDate, "ddd, MMM d")
    property int calYear: currentDate.getFullYear()
    property int calMonth: currentDate.getMonth()
    property int selectedDay: currentDate.getDate()

    Timer {
        interval: 1000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            root.currentDate = new Date()
            root.timeStr = Qt.formatTime(root.currentDate, "hh:mm")
            root.dateStr = Qt.formatDate(root.currentDate, "ddd, MMM d")
        }
    }

    onOpenChanged: {
        if (root.open) {
            root.animatingOut = false
            animatingOutTimer.stop()
            root.currentDate = new Date()
            root.refreshStates()
            root.refreshOutputPorts()
            root.loadAudioSettings()
        } else {
            root.animatingOut = true
            animatingOutTimer.restart()
        }
    }

    Timer {
        id: animatingOutTimer
        interval: 220
        onTriggered: root.animatingOut = false
    }

    /* ── Quick Toggles State & Probes ─────────────────────────────────── */
    property bool wifiOn: true
    property string wifiName: ""
    property bool btOn: false
    property string btName: ""
    property bool nightAvailable: true
    property bool nightOn: false
    property bool dndOn: Theme.dnd

    Timer {
        id: settleTimer
        interval: 900
        onTriggered: root.refreshStates()
    }

    function refreshStates() {
        if (!root.open) return
        if (!wifiProbe.running) wifiProbe.running = true
        if (!wifiNameProbe.running) wifiNameProbe.running = true
        if (!btProbe.running) btProbe.running = true
        if (!btNameProbe.running) btNameProbe.running = true
        if (!nightProbe.running) nightProbe.running = true
        if (!dndProbe.running) dndProbe.running = true
        if (!recProbe.running) recProbe.running = true
        root.refreshBrightness()
    }

    // Wi-Fi
    Process {
        id: wifiProbe
        command: ["sh", "-c", "nmcli radio wifi | tr -d ' \\n\\r'"]
        stdout: StdioCollector { id: wifiC; waitForEnd: true }
        onExited: root.wifiOn = String(wifiC.text).trim() === "enabled"
    }
    Process {
        id: wifiNameProbe
        command: ["sh", "-c", "wifi=$(nmcli -t -f IN-USE,SSID dev wifi 2>/dev/null | grep -E '^\\*:|^yes:' | head -1 | cut -d: -f2-); [ -n \"$wifi\" ] && echo \"$wifi\" || nmcli -t -f NAME connection show --active 2>/dev/null | grep -v '^lo:' | head -1 | cut -d: -f1"]
        stdout: StdioCollector { id: wifiNameC; waitForEnd: true }
        onExited: root.wifiName = String(wifiNameC.text).trim()
    }
    function toggleWifi() {
        root.wifiOn = !root.wifiOn
        if (!root.wifiOn) root.wifiName = ""
        Quickshell.execDetached(["sh", "-c", "nmcli radio wifi " + (root.wifiOn ? "on" : "off") + " >/dev/null 2>&1"])
        settleTimer.restart()
    }

    // Bluetooth
    Process {
        id: btProbe
        command: ["sh", "-c", "timeout 4 bluetoothctl show | sed -n 's/.*Powered:[ ]*//p' | tr -d ' \\n\\r'"]
        stdout: StdioCollector { id: btC; waitForEnd: true }
        onExited: root.btOn = String(btC.text).trim() === "yes"
    }
    Process {
        id: btNameProbe
        command: ["sh", "-c", "bluetoothctl devices Connected 2>/dev/null | sed 's/^Device [0-9A-F:]* //'"]
        stdout: StdioCollector { id: btNameC; waitForEnd: true }
        onExited: root.btName = String(btNameC.text).trim()
    }
    function toggleBt() {
        root.btOn = !root.btOn
        if (!root.btOn) root.btName = ""
        Quickshell.execDetached(["sh", "-c", "bluetoothctl power " + (root.btOn ? "on" : "off") + " >/dev/null 2>&1"])
        settleTimer.restart()
    }

    // Night Light
    Process {
        id: nightProbe
        command: [root.home + "/.config/hypr/scripts/carbon-night.sh", "status"]
        stdout: StdioCollector { id: nightC; waitForEnd: true }
        onExited: {
            const v = String(nightC.text).trim()
            root.nightAvailable = v !== "missing"
            root.nightOn = v === "on"
        }
    }
    function toggleNight() {
        if (!root.nightAvailable) return
        root.nightOn = !root.nightOn
        Quickshell.execDetached([root.home + "/.config/hypr/scripts/carbon-night.sh", root.nightOn ? "on" : "off"])
        settleTimer.restart()
    }

    // Do Not Disturb
    Process {
        id: dndProbe
        command: ["sh", "-c", "if [ -f /tmp/carbon-dnd.on ]; then echo true; else echo false; fi"]
        stdout: StdioCollector { id: dndC; waitForEnd: true }
        onExited: {
            root.dndOn = String(dndC.text).trim() === "true"
            Theme.dnd = root.dndOn
        }
    }
    function toggleDnd() {
        root.dndOn = !root.dndOn
        Theme.dnd = root.dndOn
        Quickshell.execDetached(["sh", "-c", root.dndOn ? "touch /tmp/carbon-dnd.on" : "rm -f /tmp/carbon-dnd.on"])
        settleTimer.restart()
    }

    /* ── Screen Recorder ──────────────────────────────────────────────── */
    property bool recWorking: false
    property int recElapsed: 0
    readonly property string recScriptDir: root.home + "/.config/hypr/scripts"

    Process {
        id: recProbe
        command: ["sh", "-c", "if pgrep -x wf-recorder >/dev/null 2>&1 || ([ -f /tmp/rec.pid ] && kill -0 $(cat /tmp/rec.pid 2>/dev/null) 2>/dev/null); then st=$(stat -c %Y /tmp/rec.pid 2>/dev/null || stat -c %Y /tmp/rec.out 2>/dev/null || date +%s); now=$(date +%s); echo \"alive:$((now - st))\"; else echo \"dead:0\"; fi"]
        stdout: StdioCollector { id: recProbeC; waitForEnd: true }
        onExited: {
            const raw = String(recProbeC.text).trim()
            const parts = raw.split(":")
            const isAlive = parts[0] === "alive"
            root.recWorking = isAlive
            if (isAlive && parts.length > 1) {
                const el = parseInt(parts[1]) || 0
                if (el > 0) root.recElapsed = el
            }
        }
    }

    function fmtRec(s) {
        const m = Math.floor(s / 60)
        return String(m).padStart(2, "0") + ":" + String(s % 60).padStart(2, "0")
    }

    function toggleRecorder() {
        if (root.recWorking) {
            Quickshell.execDetached(["/bin/sh", root.recScriptDir + "/carbon-rec-stop.sh"])
            root.recWorking = false
        } else {
            root.recElapsed = 0
            Quickshell.execDetached(["/bin/sh", root.recScriptDir + "/carbon-rec-start.sh", "full", "1", "1"])
            root.recWorking = true
        }
        settleTimer.restart()
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.recWorking
        onTriggered: root.recElapsed++
    }

    /* ── Audio & Brightness Sliders ───────────────────────────────────── */
    readonly property var audioSink: Pipewire.defaultAudioSink
    readonly property var defaultSink: audioSink
    readonly property real volRatio: (audioSink && audioSink.audio) ? Math.max(0, Math.min(1.0, audioSink.audio.volume)) : 0.0
    readonly property bool isMuted: (audioSink && audioSink.audio) ? audioSink.audio.muted : false

    /* ── Audio Settings & Persistent Virtual Devices ─────────────────── */
    property bool showVirtualDevices: false
    readonly property string audioSettingsPath: root.home + "/.config/carbon/carbon-audio.json"

    FileView {
        id: audioSettingsFile
        path: root.audioSettingsPath
        watchChanges: true
        blockLoading: true
        printErrors: false
        onLoaded: root.loadAudioSettings()
        onFileChanged: root.loadAudioSettings()
    }

    function loadAudioSettings() {
        try {
            audioSettingsFile.reload()
            var txt = audioSettingsFile.text().trim()
            if (txt.length > 0) {
                var d = JSON.parse(txt)
                if (d.showVirtualDevices !== undefined) {
                    root.showVirtualDevices = Boolean(d.showVirtualDevices)
                }
            }
        } catch (e) {}
    }

    function toggleVirtualDevices() {
        root.showVirtualDevices = !root.showVirtualDevices
        var obj = { "showVirtualDevices": root.showVirtualDevices }
        var jsonStr = JSON.stringify(obj, null, 2)
        Quickshell.execDetached(["sh", "-c", "mkdir -p $(dirname " + root.audioSettingsPath + ") && printf '%s\\n' '" + jsonStr.replace(/'/g, "'\\''") + "' > " + root.audioSettingsPath])
    }

    /* ── Pipewire Nodes, Streams & Output Ports ───────────────────────── */
    readonly property bool pwReady: Pipewire.ready
    readonly property var allNodes: pwReady ? Pipewire.nodes.values : []

    readonly property var sinks: allNodes.filter(n => {
        if (!n || !n.audio || n.isStream) return false;
        var isSink = (n.properties && n.properties["media.class"] === "Audio/Sink") || (n.isSink && (!n.properties || !n.properties["media.class"]));
        if (!isSink) return false;
        if (root.showVirtualDevices) return true;
        var idStr = String((n.properties && (n.properties["media.class"] || n.properties["node.name"])) || n.name || "");
        return !/virtual|null|stream|easyeffects/i.test(idStr);
    })

    /* Apps currently routed towards the default sink */
    PwNodeLinkTracker {
        id: linkTracker
        node: root.defaultSink
    }

    readonly property var streams: linkTracker.linkGroups

    PwObjectTracker {
        objects: [ root.defaultSink ].filter(n => n !== null)
    }

    readonly property var activeAppStreams: {
        if (!root.pwReady) return []
        let list = []
        let seenIds = {}
        if (root.streams) {
            for (let i = 0; i < root.streams.length; i++) {
                let lg = root.streams[i]
                let src = lg ? lg.source : null
                if (src && src.audio && !seenIds[src.id]) {
                    const name = String((src.properties && (src.properties["application.name"] || src.properties["node.name"])) || src.name || "")
                    if (!/easyeffects|speech-dispatcher/i.test(name) || root.showVirtualDevices) {
                        seenIds[src.id] = true
                        list.push(src)
                    }
                }
            }
        }
        if (root.allNodes) {
            for (let i = 0; i < root.allNodes.length; i++) {
                let n = root.allNodes[i]
                if (n && n.audio && n.isStream && !seenIds[n.id]) {
                    const mClass = String((n.properties && n.properties["media.class"]) || "")
                    if (mClass === "Stream/Output/Audio" || !mClass) {
                        const name = String((n.properties && (n.properties["application.name"] || n.properties["node.name"])) || n.name || "")
                        if (!/easyeffects|speech-dispatcher/i.test(name) || root.showVirtualDevices) {
                            seenIds[n.id] = true
                            list.push(n)
                        }
                    }
                }
            }
        }
        return list
    }

    function nodeName(n) {
        if (!n) return "Default Audio Output";
        const props = n.properties || {};
        const app = String(props["application.name"] || props["application.process.binary"] || "");
        if (n.isStream && app && app.trim() !== "" && app !== "?") return app.trim();
        const alsaChip = String(props["alsa.name"] || props["alsa.mixer_name"] || props["alsa.card_name"] || "");
        const desc = String(props["node.description"] || n.description || props["device.description"] || n.nickname || "");
        if (desc && desc.trim() !== "" && desc !== "?") {
            if (alsaChip && !desc.toLowerCase().includes(alsaChip.toLowerCase())) {
                return desc.trim() + " (" + alsaChip.trim() + ")";
            }
            return desc.trim();
        }
        if (alsaChip) return alsaChip;
        if (app && app.trim() !== "" && app !== "?") return app.trim();
        return String(n.name || "Audio Device");
    }

    /* Output ports (Speakers / Headphones routes on the active card) */
    property var outputPorts: []
    property string activeOutputPort: ""

    Process {
        id: sinkProc
        command: ["pactl", "list", "sinks"]
        stdout: StdioCollector {
            id: sinkCollector
            waitForEnd: true
        }
        onExited: (code, status) => root.parseSinks(sinkCollector.text)
    }

    function refreshOutputPorts() {
        if (!root.pwReady || !root.defaultSink) return
        root.activeOutputPort = ""
        if (!sinkProc.running) sinkProc.running = true
    }

    function parseSinks(text) {
        const name = root.defaultSink ? String(root.defaultSink.name || "") : ""
        let foundPorts = []
        for (const block of String(text).split(/\r?\nSink #/)) {
            const nm = /^\tName: (.+)$/m.exec(block)
            if (name && nm && nm[1] !== name) continue
            const port = /^\s*Active Port: (.+)$/m.exec(block)
            if (port) root.activeOutputPort = port[1].trim()
            const portSection = block.split(/\r?\n\tPorts:\r?\n/)[1]
            if (portSection) {
                const portsText = portSection.split(/\r?\n\tActive Port:/)[0]
                const re = /^\t\t([a-z0-9_.-]+)\s*:\s*([^(]+?)(?:\s*\((.*)\))?$/gmi
                let m
                while ((m = re.exec(portsText))) {
                    const pName = m[1].trim()
                    let pDesc = m[2].trim()
                    if (pDesc.length === 0) pDesc = pName
                    foundPorts.push({ name: pName, desc: pDesc })
                }
                if (foundPorts.length > 0) break
            }
        }
        if (foundPorts.length === 0 && name.includes("analog")) {
            foundPorts = [
                { name: "analog-output-speaker", desc: "Speakers" },
                { name: "analog-output-headphones", desc: "Headphones" }
            ]
        }
        root.outputPorts = foundPorts
    }

    function selectOutputPort(portName) {
        if (!root.defaultSink) return
        Quickshell.execDetached(["pactl", "set-sink-port", root.defaultSink.name, portName])
        Quickshell.execDetached(["amixer", "-q", "sset", "Master", "unmute"])
        if (/speaker/i.test(portName)) {
            Quickshell.execDetached(["amixer", "-q", "sset", "Speaker", "unmute", "100%"])
        } else if (/headphone/i.test(portName)) {
            Quickshell.execDetached(["amixer", "-q", "sset", "Headphone", "unmute", "100%"])
        }
        root.activeOutputPort = portName
    }

    property real brightRatio: 0.5
    property real brightMax: 1
    property real lastBrightWrite: 0

    Process {
        id: brightProbe
        command: ["sh", "-c", 'echo "a b c $(brightnessctl --class backlight get) $(brightnessctl --class backlight max)"']
        stdout: StdioCollector { id: bC; waitForEnd: true }
        onExited: {
            const raw = String(bC.text).trim().split(/\s+/)
            if (raw.length >= 5) {
                const cur = parseFloat(raw[3]) || 0
                const max = parseFloat(raw[4]) || 1
                root.brightMax = max
                root.brightRatio = Math.max(0, Math.min(1.0, cur / max))
            }
        }
    }

    function refreshBrightness() {
        if (!brightProbe.running) brightProbe.running = true
    }

    function setBrightness(r) {
        r = Math.max(0.01, Math.min(1.0, r))
        root.brightRatio = r
        root.lastBrightWrite = Date.now()
        Quickshell.execDetached(["brightnessctl", "--class", "backlight", "s", Math.max(1, Math.round(r * 100)) + "%"])
    }

    /* ── Notifications Integration ────────────────────────────────────── */
    readonly property var notifItems: NotificationService.list || []
    readonly property int notifCount: notifItems.length
    property int centerTab: 0 // 0: Notifications, 1: Calendar, 2: Audio

    function dismissAllNotifs() {
        NotificationService.clearAll()
    }

    /* ── Calendar Integration ─────────────────────────────────────────── */
    readonly property var monthNames: [
        "JANUARY", "FEBRUARY", "MARCH", "APRIL", "MAY", "JUNE",
        "JULY", "AUGUST", "SEPTEMBER", "OCTOBER", "NOVEMBER", "DECEMBER"
    ]
    readonly property var weekdayShortNames: ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]

    function prevMonth() {
        if (calMonth === 0) { calMonth = 11; calYear--; }
        else { calMonth--; }
    }
    function nextMonth() {
        if (calMonth === 11) { calMonth = 0; calYear++; }
        else { calMonth++; }
    }
    function daysInMonth(y, m) { return new Date(y, m + 1, 0).getDate() }
    function firstDayWeekday(y, m) { return new Date(y, m, 1).getDay() }

    /* ── MPRIS Music State ───────────────────────────────────────────── */
    readonly property var mprisPlayer: LyricsService.activePlayer
    readonly property bool isMusicPlaying: LyricsService.isPlaying
    readonly property bool hasMusicTrack: LyricsService.hasTrack
    readonly property string musicTitle: hasMusicTrack ? (LyricsService.trackTitle || "No title") : "No media playing"
    readonly property string musicArtist: hasMusicTrack ? (LyricsService.trackArtist || "Unknown artist") : "Carbon Audio"
    readonly property string musicArtUrl: LyricsService.artUrl
    readonly property real musicPosition: LyricsService.currentPosition
    readonly property real musicLength: LyricsService.totalLength
    readonly property real musicProgress: musicLength > 0 ? Math.max(0, Math.min(1.0, musicPosition / musicLength)) : 0.0

    function formatTime(secs) {
        if (isNaN(secs) || secs < 0) return "00:00"
        let m = Math.floor(secs / 60)
        let s = Math.floor(secs % 60)
        return (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s
    }

    function seekRatio(r) {
        if (!hasMusicTrack || musicLength <= 0) return
        const targetSec = Math.max(0, Math.min(musicLength, r * musicLength))
        Quickshell.execDetached(["playerctl", "position", targetSec.toFixed(2)])
    }

    Component.onCompleted: {
        root.refreshStates()
        root.loadAudioSettings()
    }

    /* ── Main Panel Card ─────────────────────────────────────────────── */
    Item {
        id: mainCard
        anchors.fill: parent

        HoverHandler {
            id: mainCardHover
        }

        MouseArea {
            anchors.fill: parent
            z: 0
        }

        Shape {
            id: cardBgShape
            anchors.fill: parent
            layer.enabled: true
            layer.smooth: true
            preferredRendererType: Shape.CurveRenderer
            visible: root.showBackground

            // 1. Background fill (seamless top, rounded bottom)
            ShapePath {
                fillColor: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, Theme.shellOpacity)
                strokeColor: "transparent"
                strokeWidth: 0
                startX: 0; startY: 0
                PathLine { x: mainCard.width; y: 0 }
                PathLine { x: mainCard.width; y: mainCard.height - 20 }
                PathArc { x: mainCard.width - 20; y: mainCard.height; radiusX: 20; radiusY: 20 }
                PathLine { x: 20; y: mainCard.height }
                PathArc { x: 0; y: mainCard.height - 20; radiusX: 20; radiusY: 20 }
                PathLine { x: 0; y: 0 }
            }

            // 2. Stroke outline (Right, Bottom, Left - open top)
            ShapePath {
                fillColor: "transparent"
                strokeColor: root.open ? Qt.rgba(Theme.accentLit.r, Theme.accentLit.g, Theme.accentLit.b, 0.40) : Theme.outline
                strokeWidth: 1
                startX: mainCard.width; startY: 0
                PathLine { x: mainCard.width; y: mainCard.height - 20 }
                PathArc { x: mainCard.width - 20; y: mainCard.height; radiusX: 20; radiusY: 20 }
                PathLine { x: 20; y: mainCard.height }
                PathArc { x: 0; y: mainCard.height - 20; radiusX: 20; radiusY: 20 }
                PathLine { x: 0; y: 0 }
            }
        }

        opacity: root.showBackground ? (root.open ? 1.0 : 0.0) : 1.0
        y: root.showBackground ? (root.open ? 0 : (root.attachedBottom ? height : -height)) : 0

        Behavior on opacity {
            enabled: root.showBackground
            NumberAnimation { duration: root.open ? 180 : 140; easing.type: Easing.OutCubic }
        }
        Behavior on y {
            NumberAnimation { duration: root.open ? 240 : 160; easing.type: Easing.OutCubic }
        }

        /* ── 3-Column Landscape Layout (860x260px) ─────────────────────── */
        RowLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 12
            z: 1

            /* ========================================================= */
            /* 1. LEFT COLUMN: QUICK CONTROLS & SLIDERS (~270px)        */
            /* ========================================================= */
            ColumnLayout {
                Layout.preferredWidth: 268
                Layout.fillHeight: true
                spacing: 8

                // 1A. Shortcuts Header Row (Recorder, Screenshot, Settings, Lock, Power)
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 26
                    spacing: 6

                    // Screen Recorder
                    Rectangle {
                        width: root.recWorking ? recRow.implicitWidth + 12 : 26
                        height: 26
                        radius: 13
                        color: root.recWorking ? Qt.rgba(1, 0.2, 0.2, 0.25) : (recMH.containsMouse ? Theme.bgHover : Qt.rgba(1, 1, 1, 0.05))
                        border.width: 1
                        border.color: root.recWorking ? "#ff4444" : (recMH.containsMouse ? Theme.accent : Theme.outline)

                        RowLayout {
                            id: recRow
                            anchors.centerIn: parent
                            spacing: 3
                            Text {
                                text: root.recWorking ? "stop_circle" : "videocam"
                                font.family: Theme.fontIcon
                                font.pixelSize: 13
                                color: root.recWorking ? "#ff4444" : (recMH.containsMouse ? Theme.accent : Theme.fgDim)
                            }
                            Text {
                                visible: root.recWorking
                                text: root.fmtRec(root.recElapsed)
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: Theme.fontPx(7.5)
                                font.weight: Font.Bold
                                color: "#ff4444"
                            }
                        }
                        MouseArea {
                            id: recMH
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleRecorder()
                        }
                    }

                    // Screenshot
                    Rectangle {
                        width: 26; height: 26; radius: 13
                        color: shotMH.containsMouse ? Theme.bgHover : Qt.rgba(1, 1, 1, 0.05)
                        border.width: 1
                        border.color: shotMH.containsMouse ? Theme.accent : Theme.outline
                        Text {
                            anchors.centerIn: parent
                            text: "photo_camera"
                            font.family: Theme.fontIcon
                            font.pixelSize: 13
                            color: shotMH.containsMouse ? Theme.accent : Theme.fgDim
                        }
                        MouseArea {
                            id: shotMH
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Quickshell.execDetached([root.home + "/.config/hypr/scripts/carbon-screenshot-region.sh"])
                        }
                    }

                    // Settings
                    Rectangle {
                        width: 26; height: 26; radius: 13
                        color: setMH.containsMouse ? Theme.bgHover : Qt.rgba(1, 1, 1, 0.05)
                        border.width: 1
                        border.color: setMH.containsMouse ? Theme.accent : Theme.outline
                        Text {
                            anchors.centerIn: parent
                            text: "settings"
                            font.family: Theme.fontIcon
                            font.pixelSize: 13
                            color: setMH.containsMouse ? Theme.accent : Theme.fgDim
                        }
                        MouseArea {
                            id: setMH
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Quickshell.execDetached(["sh", "-c", "command -v carbon-config-editor >/dev/null && carbon-config-editor || systemsettings || true"])
                        }
                    }

                    // Lock
                    Rectangle {
                        width: 26; height: 26; radius: 13
                        color: lockMH.containsMouse ? Theme.bgHover : Qt.rgba(1, 1, 1, 0.05)
                        border.width: 1
                        border.color: lockMH.containsMouse ? Theme.accent : Theme.outline
                        Text {
                            anchors.centerIn: parent
                            text: "lock"
                            font.family: Theme.fontIcon
                            font.pixelSize: 13
                            color: lockMH.containsMouse ? Theme.accent : Theme.fgDim
                        }
                        MouseArea {
                            id: lockMH
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Quickshell.execDetached([root.home + "/.config/hypr/scripts/hyprlock.sh"])
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Power
                    Rectangle {
                        width: 26; height: 26; radius: 13
                        color: pwrMH.containsMouse ? Qt.rgba(1, 0.2, 0.2, 0.25) : Qt.rgba(1, 1, 1, 0.05)
                        border.width: 1
                        border.color: pwrMH.containsMouse ? "#ff5555" : Theme.outline
                        Text {
                            anchors.centerIn: parent
                            text: "power_settings_new"
                            font.family: Theme.fontIcon
                            font.pixelSize: 13
                            color: pwrMH.containsMouse ? "#ff5555" : Theme.fgDim
                        }
                        MouseArea {
                            id: pwrMH
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Quickshell.execDetached(["sh", root.home + "/.config/carbon/scripts/carbon-ipc.sh", "power"])
                        }
                    }
                }

                // 1B. 2x2 Quick Toggles Grid (Wi-Fi, Bluetooth, Night Light, DND)
                GridLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 96
                    columns: 2
                    rowSpacing: 6
                    columnSpacing: 6

                    // Tile 1: Wi-Fi
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 45
                        radius: 12
                        color: root.wifiOn ? Theme.accent : (wifiTileHov.containsMouse ? Theme.bgHover : Qt.rgba(Theme.bgAlt.r, Theme.bgAlt.g, Theme.bgAlt.b, 0.65))
                        border.width: 1
                        border.color: root.wifiOn ? Qt.rgba(Theme.accentLit.r, Theme.accentLit.g, Theme.accentLit.b, 0.60) : Theme.outline

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 6
                            spacing: 6

                            Rectangle {
                                width: 28; height: 28; radius: 14
                                color: root.wifiOn ? (Theme.isDark ? Qt.rgba(0,0,0,0.2) : Qt.rgba(1,1,1,0.3)) : Qt.rgba(1, 1, 1, 0.08)
                                Text {
                                    anchors.centerIn: parent
                                    text: "wifi"
                                    font.family: Theme.fontIcon
                                    font.pixelSize: 15
                                    color: root.wifiOn ? (Theme.isDark ? "#101116" : "#ffffff") : Theme.fgDim
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Text {
                                    text: "Wi-Fi"
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: Theme.fontPx(8.5)
                                    font.weight: Font.Bold
                                    color: root.wifiOn ? (Theme.isDark ? "#101116" : "#ffffff") : Theme.fg
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: root.wifiOn ? (root.wifiName.length > 0 ? root.wifiName : "Connected") : "Off"
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: Theme.fontPx(7)
                                    color: root.wifiOn ? (Theme.isDark ? Qt.rgba(0.06,0.07,0.09,0.8) : Qt.rgba(1,1,1,0.85)) : Theme.fgDim
                                    elide: Text.ElideRight
                                }
                            }
                        }
                        MouseArea {
                            id: wifiTileHov
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleWifi()
                        }
                    }

                    // Tile 2: Bluetooth
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 45
                        radius: 12
                        color: root.btOn ? Theme.accent : (btTileHov.containsMouse ? Theme.bgHover : Qt.rgba(Theme.bgAlt.r, Theme.bgAlt.g, Theme.bgAlt.b, 0.65))
                        border.width: 1
                        border.color: root.btOn ? Qt.rgba(Theme.accentLit.r, Theme.accentLit.g, Theme.accentLit.b, 0.60) : Theme.outline

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 6
                            spacing: 6

                            Rectangle {
                                width: 28; height: 28; radius: 14
                                color: root.btOn ? (Theme.isDark ? Qt.rgba(0,0,0,0.2) : Qt.rgba(1,1,1,0.3)) : Qt.rgba(1, 1, 1, 0.08)
                                Text {
                                    anchors.centerIn: parent
                                    text: "bluetooth"
                                    font.family: Theme.fontIcon
                                    font.pixelSize: 15
                                    color: root.btOn ? (Theme.isDark ? "#101116" : "#ffffff") : Theme.fgDim
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Text {
                                    text: "Bluetooth"
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: Theme.fontPx(8.5)
                                    font.weight: Font.Bold
                                    color: root.btOn ? (Theme.isDark ? "#101116" : "#ffffff") : Theme.fg
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: root.btOn ? (root.btName.length > 0 ? root.btName : "On") : "Off"
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: Theme.fontPx(7)
                                    color: root.btOn ? (Theme.isDark ? Qt.rgba(0.06,0.07,0.09,0.8) : Qt.rgba(1,1,1,0.85)) : Theme.fgDim
                                    elide: Text.ElideRight
                                }
                            }
                        }
                        MouseArea {
                            id: btTileHov
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleBt()
                        }
                    }

                    // Tile 3: Night Light
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 45
                        radius: 12
                        color: root.nightOn ? Theme.accent : (nightTileHov.containsMouse ? Theme.bgHover : Qt.rgba(Theme.bgAlt.r, Theme.bgAlt.g, Theme.bgAlt.b, 0.65))
                        border.width: 1
                        border.color: root.nightOn ? Qt.rgba(Theme.accentLit.r, Theme.accentLit.g, Theme.accentLit.b, 0.60) : Theme.outline

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 6
                            spacing: 6

                            Rectangle {
                                width: 28; height: 28; radius: 14
                                color: root.nightOn ? (Theme.isDark ? Qt.rgba(0,0,0,0.2) : Qt.rgba(1,1,1,0.3)) : Qt.rgba(1, 1, 1, 0.08)
                                Text {
                                    anchors.centerIn: parent
                                    text: "nightlight"
                                    font.family: Theme.fontIcon
                                    font.pixelSize: 15
                                    color: root.nightOn ? (Theme.isDark ? "#101116" : "#ffffff") : Theme.fgDim
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Text {
                                    text: "Night Light"
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: Theme.fontPx(8.5)
                                    font.weight: Font.Bold
                                    color: root.nightOn ? (Theme.isDark ? "#101116" : "#ffffff") : Theme.fg
                                }
                                Text {
                                    text: root.nightOn ? "On" : "Off"
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: Theme.fontPx(7)
                                    color: root.nightOn ? (Theme.isDark ? Qt.rgba(0.06,0.07,0.09,0.8) : Qt.rgba(1,1,1,0.85)) : Theme.fgDim
                                }
                            }
                        }
                        MouseArea {
                            id: nightTileHov
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleNight()
                        }
                    }

                    // Tile 4: Do Not Disturb
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 45
                        radius: 12
                        color: root.dndOn ? Theme.accent : (dndTileHov.containsMouse ? Theme.bgHover : Qt.rgba(Theme.bgAlt.r, Theme.bgAlt.g, Theme.bgAlt.b, 0.65))
                        border.width: 1
                        border.color: root.dndOn ? Qt.rgba(Theme.accentLit.r, Theme.accentLit.g, Theme.accentLit.b, 0.60) : Theme.outline

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 6
                            spacing: 6

                            Rectangle {
                                width: 28; height: 28; radius: 14
                                color: root.dndOn ? (Theme.isDark ? Qt.rgba(0,0,0,0.2) : Qt.rgba(1,1,1,0.3)) : Qt.rgba(1, 1, 1, 0.08)
                                Text {
                                    anchors.centerIn: parent
                                    text: root.dndOn ? "notifications_off" : "notifications"
                                    font.family: Theme.fontIcon
                                    font.pixelSize: 15
                                    color: root.dndOn ? (Theme.isDark ? "#101116" : "#ffffff") : Theme.fgDim
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Text {
                                    text: "DND"
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: Theme.fontPx(8.5)
                                    font.weight: Font.Bold
                                    color: root.dndOn ? (Theme.isDark ? "#101116" : "#ffffff") : Theme.fg
                                }
                                Text {
                                    text: root.dndOn ? "On" : "Off"
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: Theme.fontPx(7)
                                    color: root.dndOn ? (Theme.isDark ? Qt.rgba(0.06,0.07,0.09,0.8) : Qt.rgba(1,1,1,0.85)) : Theme.fgDim
                                }
                            }
                        }
                        MouseArea {
                            id: dndTileHov
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleDnd()
                        }
                    }
                }

                // 1C. Hardware Sliders Card (Volume & Brightness)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 88
                    radius: 14
                    color: Qt.rgba(Theme.bgAlt.r, Theme.bgAlt.g, Theme.bgAlt.b, 0.65)
                    border.width: 1
                    border.color: Theme.outline

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 6

                        // Volume Row
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Rectangle {
                                width: 24; height: 24; radius: 12
                                color: muteHov.containsMouse ? Theme.bgHover : "transparent"
                                Text {
                                    anchors.centerIn: parent
                                    text: root.isMuted ? "volume_off" : (root.volRatio <= 0.01 ? "volume_mute" : (root.volRatio < 0.5 ? "volume_down" : "volume_up"))
                                    font.family: Theme.fontIcon
                                    font.pixelSize: 15
                                    color: root.isMuted ? Theme.fgDim : Theme.accent
                                }
                                MouseArea {
                                    id: muteHov
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (root.audioSink && root.audioSink.audio) {
                                            root.audioSink.audio.muted = !root.audioSink.audio.muted
                                        }
                                    }
                                }
                            }

                            Item {
                                id: volTrack
                                Layout.fillWidth: true
                                Layout.preferredHeight: 18

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 9
                                    color: Qt.rgba(1, 1, 1, 0.10)
                                }
                                Rectangle {
                                    height: parent.height
                                    width: Math.max(0, Math.min(parent.width, parent.width * (root.isMuted ? 0 : root.volRatio)))
                                    radius: 9
                                    color: root.isMuted ? Theme.fgFaint : Theme.accent
                                    Behavior on width {
                                        enabled: !volArea.pressed
                                        NumberAnimation { duration: 100 }
                                    }
                                }
                                MouseArea {
                                    id: volArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    function updateVol(mx) {
                                        var r = Math.max(0, Math.min(1.0, mx / volTrack.width))
                                        if (root.audioSink && root.audioSink.audio) {
                                            root.audioSink.audio.volume = r
                                            if (root.audioSink.audio.muted && r > 0) root.audioSink.audio.muted = false
                                        }
                                    }
                                    onPressed: mouse => updateVol(mouse.x)
                                    onPositionChanged: mouse => { if (pressed) updateVol(mouse.x) }
                                }
                                WheelHandler {
                                    target: volTrack
                                    onWheel: (event) => {
                                        var step = event.angleDelta.y > 0 ? 0.03 : -0.03
                                        if (root.audioSink && root.audioSink.audio) {
                                            root.audioSink.audio.volume = Math.max(0, Math.min(1.0, root.volRatio + step))
                                            if (root.audioSink.audio.muted && step > 0) root.audioSink.audio.muted = false
                                        }
                                    }
                                }
                            }

                            Text {
                                Layout.preferredWidth: 26
                                horizontalAlignment: Text.AlignRight
                                text: Math.round((root.isMuted ? 0 : root.volRatio) * 100) + "%"
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: Theme.fontPx(8)
                                font.weight: Font.Bold
                                color: Theme.fgDim
                            }

                            // Quick jump to Audio tab in Center Column
                            Rectangle {
                                width: 22; height: 22; radius: 11
                                color: audioJumpMH.containsMouse ? Theme.bgHover : (root.centerTab === 2 ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.20) : "transparent")
                                border.width: 1
                                border.color: root.centerTab === 2 ? Theme.accent : (audioJumpMH.containsMouse ? Theme.outline : "transparent")
                                Text {
                                    anchors.centerIn: parent
                                    text: "tune"
                                    font.family: Theme.fontIcon
                                    font.pixelSize: 13
                                    color: root.centerTab === 2 ? Theme.accent : Theme.fgDim
                                }
                                MouseArea {
                                    id: audioJumpMH
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.centerTab = 2
                                        root.refreshOutputPorts()
                                    }
                                }
                            }
                        }

                        // Brightness Row
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Rectangle {
                                width: 24; height: 24; radius: 12
                                color: "transparent"
                                Text {
                                    anchors.centerIn: parent
                                    text: "brightness_6"
                                    font.family: Theme.fontIcon
                                    font.pixelSize: 15
                                    color: Theme.accentLit
                                }
                            }

                            Item {
                                id: brightTrack
                                Layout.fillWidth: true
                                Layout.preferredHeight: 18

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 9
                                    color: Qt.rgba(1, 1, 1, 0.10)
                                }
                                Rectangle {
                                    height: parent.height
                                    width: Math.max(0, Math.min(parent.width, parent.width * root.brightRatio))
                                    radius: 9
                                    color: Theme.accentLit
                                    Behavior on width {
                                        enabled: !brightArea.pressed
                                        NumberAnimation { duration: 100 }
                                    }
                                }
                                MouseArea {
                                    id: brightArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    function updateBright(mx) {
                                        var r = Math.max(0.01, Math.min(1.0, mx / brightTrack.width))
                                        root.setBrightness(r)
                                    }
                                    onPressed: mouse => updateBright(mouse.x)
                                    onPositionChanged: mouse => { if (pressed) updateBright(mouse.x) }
                                }
                                WheelHandler {
                                    target: brightTrack
                                    onWheel: (event) => {
                                        var step = event.angleDelta.y > 0 ? 0.03 : -0.03
                                        root.setBrightness(root.brightRatio + step)
                                    }
                                }
                            }

                            Text {
                                Layout.preferredWidth: 26
                                horizontalAlignment: Text.AlignRight
                                text: Math.round(root.brightRatio * 100) + "%"
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: Theme.fontPx(8)
                                font.weight: Font.Bold
                                color: Theme.fgDim
                            }

                            Item { width: 22; height: 22 }
                        }
                    }
                }
            }

            /* ========================================================= */
            /* 2. CENTER COLUMN: HUB (NOTIFICATIONS & CALENDAR) (~286px)*/
            /* ========================================================= */
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 6

                // 2A. Header Tab Bar (Notifs & Calendar)
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 26
                    spacing: 6

                    // Notifications Tab Pill
                    Rectangle {
                        Layout.preferredHeight: 24
                        Layout.preferredWidth: notifTabRow.implicitWidth + 16
                        radius: 12
                        color: root.centerTab === 0 ? Theme.accent : (notifTabHov.containsMouse ? Theme.bgHover : Qt.rgba(1, 1, 1, 0.06))
                        border.width: 1
                        border.color: root.centerTab === 0 ? Theme.accentLit : Theme.outline

                        RowLayout {
                            id: notifTabRow
                            anchors.centerIn: parent
                            spacing: 4
                            Text {
                                text: "notifications"
                                font.family: Theme.fontIcon
                                font.pixelSize: 13
                                color: root.centerTab === 0 ? (Theme.isDark ? "#101116" : "#ffffff") : Theme.fgDim
                            }
                            Text {
                                text: "Notifs"
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: Theme.fontPx(8.5)
                                font.weight: Font.Bold
                                color: root.centerTab === 0 ? (Theme.isDark ? "#101116" : "#ffffff") : Theme.fg
                            }
                            Rectangle {
                                visible: root.notifCount > 0
                                Layout.preferredHeight: 14
                                Layout.preferredWidth: cntTxt.implicitWidth + 6
                                radius: 7
                                color: root.centerTab === 0 ? (Theme.isDark ? Qt.rgba(0,0,0,0.3) : Qt.rgba(1,1,1,0.4)) : Theme.accent
                                Text {
                                    id: cntTxt
                                    anchors.centerIn: parent
                                    text: String(root.notifCount)
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: Theme.fontPx(7)
                                    font.weight: Font.Bold
                                    color: root.centerTab === 0 ? (Theme.isDark ? "#ffffff" : "#101116") : (Theme.isDark ? "#101116" : "#ffffff")
                                }
                            }
                        }
                        MouseArea {
                            id: notifTabHov
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.centerTab = 0
                        }
                    }

                    // Calendar Tab Pill
                    Rectangle {
                        Layout.preferredHeight: 24
                        Layout.preferredWidth: calTabRow.implicitWidth + 16
                        radius: 12
                        color: root.centerTab === 1 ? Theme.accent : (calTabHov.containsMouse ? Theme.bgHover : Qt.rgba(1, 1, 1, 0.06))
                        border.width: 1
                        border.color: root.centerTab === 1 ? Theme.accentLit : Theme.outline

                        RowLayout {
                            id: calTabRow
                            anchors.centerIn: parent
                            spacing: 4
                            Text {
                                text: "calendar_month"
                                font.family: Theme.fontIcon
                                font.pixelSize: 13
                                color: root.centerTab === 1 ? (Theme.isDark ? "#101116" : "#ffffff") : Theme.fgDim
                            }
                            Text {
                                text: "Calendar"
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: Theme.fontPx(8.5)
                                font.weight: Font.Bold
                                color: root.centerTab === 1 ? (Theme.isDark ? "#101116" : "#ffffff") : Theme.fg
                            }
                        }
                        MouseArea {
                            id: calTabHov
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.centerTab = 1
                        }
                    }

                    // Audio Tab Pill
                    Rectangle {
                        Layout.preferredHeight: 24
                        Layout.preferredWidth: audioTabRow.implicitWidth + 16
                        radius: 12
                        color: root.centerTab === 2 ? Theme.accent : (audioTabHov.containsMouse ? Theme.bgHover : Qt.rgba(1, 1, 1, 0.06))
                        border.width: 1
                        border.color: root.centerTab === 2 ? Theme.accentLit : Theme.outline

                        RowLayout {
                            id: audioTabRow
                            anchors.centerIn: parent
                            spacing: 4
                            Text {
                                text: "tune"
                                font.family: Theme.fontIcon
                                font.pixelSize: 13
                                color: root.centerTab === 2 ? (Theme.isDark ? "#101116" : "#ffffff") : Theme.fgDim
                            }
                            Text {
                                text: "Audio"
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: Theme.fontPx(8.5)
                                font.weight: Font.Bold
                                color: root.centerTab === 2 ? (Theme.isDark ? "#101116" : "#ffffff") : Theme.fg
                            }
                            Rectangle {
                                visible: root.activeAppStreams.length > 0
                                Layout.preferredHeight: 14
                                Layout.preferredWidth: strmCntTxt.implicitWidth + 6
                                radius: 7
                                color: root.centerTab === 2 ? (Theme.isDark ? Qt.rgba(0,0,0,0.3) : Qt.rgba(1,1,1,0.4)) : Theme.accent
                                Text {
                                    id: strmCntTxt
                                    anchors.centerIn: parent
                                    text: String(root.activeAppStreams.length)
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: Theme.fontPx(7)
                                    font.weight: Font.Bold
                                    color: root.centerTab === 2 ? (Theme.isDark ? "#ffffff" : "#101116") : (Theme.isDark ? "#101116" : "#ffffff")
                                }
                            }
                        }
                        MouseArea {
                            id: audioTabHov
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.centerTab = 2
                                root.refreshOutputPorts()
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Clear All Notifications (Visible when in notifs tab and notifCount > 0)
                    Rectangle {
                        visible: root.centerTab === 0 && root.notifCount > 0
                        Layout.preferredHeight: 22
                        Layout.preferredWidth: clearRow.implicitWidth + 10
                        radius: 11
                        color: clearMH.containsMouse ? Theme.bgHover : "transparent"
                        border.width: 1
                        border.color: clearMH.containsMouse ? Theme.accent : Theme.outline

                        Row {
                            id: clearRow
                            anchors.centerIn: parent
                            spacing: 4
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "delete_sweep"
                                font.family: Theme.fontIcon
                                font.pixelSize: 13
                                color: clearMH.containsMouse ? Theme.accent : Theme.fgDim
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Clear"
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: Theme.fontPx(7.5)
                                font.weight: Font.Medium
                                color: clearMH.containsMouse ? Theme.accent : Theme.fgDim
                            }
                        }
                        MouseArea {
                            id: clearMH
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.dismissAllNotifs()
                        }
                    }
                }

                // 2B. Tab Content Container
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    // ── View A: Notifications List ──
                    Item {
                        anchors.fill: parent
                        visible: root.centerTab === 0

                        // Empty State
                        Item {
                            anchors.fill: parent
                            visible: root.notifCount === 0

                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 4
                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "notifications"
                                    font.family: Theme.fontIcon
                                    font.pixelSize: 26
                                    color: Theme.fgFaint
                                }
                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "No notifications"
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: Theme.fontPx(9)
                                    font.weight: Font.Bold
                                    color: Theme.fgDim
                                }
                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "You're all caught up"
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: Theme.fontPx(7.5)
                                    color: Theme.fgFaint
                                }
                            }
                        }

                        // Scrollable Notifications List
                        Flickable {
                            anchors.fill: parent
                            contentHeight: notifCol.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            visible: root.notifCount > 0

                            ColumnLayout {
                                id: notifCol
                                width: parent.width
                                spacing: 6

                                Repeater {
                                    model: root.notifItems
                                    delegate: Rectangle {
                                        id: notifCard
                                        required property var modelData
                                        required property int index

                                        Layout.fillWidth: true
                                        Layout.preferredHeight: Math.max(50, nCol.implicitHeight + 12)
                                        radius: 10
                                        color: nCardMH.containsMouse ? Theme.bgHover : Qt.rgba(Theme.bgAlt.r, Theme.bgAlt.g, Theme.bgAlt.b, 0.70)
                                        border.width: 1
                                        border.color: nCardMH.containsMouse ? Qt.rgba(Theme.accentLit.r, Theme.accentLit.g, Theme.accentLit.b, 0.35) : Theme.outline

                                        MouseArea {
                                            id: nCardMH
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (modelData.actions && modelData.actions.length > 0) {
                                                    NotificationService.invokeAction(modelData, modelData.actions[0])
                                                }
                                            }
                                        }

                                        ColumnLayout {
                                            id: nCol
                                            anchors.fill: parent
                                            anchors.margins: 6
                                            spacing: 2

                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 4

                                                Rectangle {
                                                    width: 14; height: 14; radius: 7
                                                    color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.2)
                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: "notifications"
                                                        font.family: Theme.fontIcon
                                                        font.pixelSize: 9
                                                        color: Theme.accent
                                                    }
                                                }

                                                Text {
                                                    Layout.fillWidth: true
                                                    text: modelData.appName || "System"
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: Theme.fontPx(7.5)
                                                    font.weight: Font.Bold
                                                    color: Theme.fgDim
                                                    elide: Text.ElideRight
                                                }

                                                Text {
                                                    text: modelData.timeStr || ""
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: Theme.fontPx(6.5)
                                                    color: Theme.fgFaint
                                                    visible: text.length > 0
                                                }

                                                // Dismiss Button
                                                Rectangle {
                                                    width: 16; height: 16; radius: 8
                                                    color: dismissMH.containsMouse ? Qt.rgba(1, 0.2, 0.2, 0.2) : "transparent"
                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: "close"
                                                        font.family: Theme.fontIcon
                                                        font.pixelSize: 10
                                                        color: dismissMH.containsMouse ? "#ff4444" : Theme.fgFaint
                                                    }
                                                    MouseArea {
                                                        id: dismissMH
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            if (modelData.id !== undefined) NotificationService.dismiss(modelData.id)
                                                        }
                                                    }
                                                }
                                            }

                                            Text {
                                                Layout.fillWidth: true
                                                text: modelData.summary || ""
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: Theme.fontPx(8)
                                                font.weight: Font.Bold
                                                color: Theme.fg
                                                elide: Text.ElideRight
                                                visible: text.length > 0
                                            }

                                            Text {
                                                Layout.fillWidth: true
                                                text: modelData.body || ""
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: Theme.fontPx(7)
                                                color: Theme.fgDim
                                                elide: Text.ElideRight
                                                maximumLineCount: 2
                                                wrapMode: Text.Wrap
                                                visible: text.length > 0
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── View B: Calendar Month Grid ──
                    Item {
                        anchors.fill: parent
                        visible: root.centerTab === 1

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 4

                            // Calendar Header: < Month Year >
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 4

                                Rectangle {
                                    width: 20; height: 20; radius: 10
                                    color: prevMH.containsMouse ? Theme.bgHover : "transparent"
                                    Text {
                                        anchors.centerIn: parent
                                        text: "‹"
                                        font.pixelSize: Theme.fontPx(13)
                                        font.weight: Font.Bold
                                        color: prevMH.containsMouse ? Theme.fg : Theme.fgDim
                                    }
                                    MouseArea {
                                        id: prevMH
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.prevMonth()
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: root.monthNames[root.calMonth] + " " + root.calYear
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: Theme.fontPx(9.5)
                                    font.weight: Font.Bold
                                    color: Theme.fg
                                    horizontalAlignment: Text.AlignHCenter
                                }

                                Rectangle {
                                    width: 20; height: 20; radius: 10
                                    color: nextMH.containsMouse ? Theme.bgHover : "transparent"
                                    Text {
                                        anchors.centerIn: parent
                                        text: "›"
                                        font.pixelSize: Theme.fontPx(13)
                                        font.weight: Font.Bold
                                        color: nextMH.containsMouse ? Theme.fg : Theme.fgDim
                                    }
                                    MouseArea {
                                        id: nextMH
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.nextMonth()
                                    }
                                }
                            }

                            // Weekday Abbreviations
                            Row {
                                Layout.fillWidth: true
                                spacing: (parent.width - 7 * 24) / 6
                                Repeater {
                                    model: root.weekdayShortNames
                                    delegate: Text {
                                        width: 24
                                        horizontalAlignment: Text.AlignHCenter
                                        text: modelData
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: Theme.fontPx(7)
                                        font.weight: Font.Bold
                                        color: Theme.fgFaint
                                    }
                                }
                            }

                            // 42-day (6x7) Calendar Grid
                            GridLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                columns: 7
                                rowSpacing: 2
                                columnSpacing: (parent.width - 7 * 24) / 6

                                Repeater {
                                    model: 42
                                    delegate: Item {
                                        required property int index
                                        width: 24; height: 20

                                        readonly property int firstDay: root.firstDayWeekday(root.calYear, root.calMonth)
                                        readonly property int totalDays: root.daysInMonth(root.calYear, root.calMonth)
                                        readonly property int dayNum: index - firstDay + 1
                                        readonly property bool isCurrentMonth: dayNum >= 1 && dayNum <= totalDays
                                        readonly property bool isToday: isCurrentMonth && (dayNum === root.currentDate.getDate()) && (root.calMonth === root.currentDate.getMonth()) && (root.calYear === root.currentDate.getFullYear())
                                        readonly property bool isSelected: isCurrentMonth && (dayNum === root.selectedDay)

                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: 20; height: 20
                                            radius: 10
                                            color: isToday ? Theme.accent : (isSelected ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.25) : (dayMH.containsMouse ? Theme.bgHover : "transparent"))
                                            border.width: isSelected && !isToday ? 1 : 0
                                            border.color: Theme.accentLit

                                            Text {
                                                anchors.centerIn: parent
                                                text: isCurrentMonth ? String(dayNum) : ""
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: Theme.fontPx(7.5)
                                                font.weight: isToday ? Font.Bold : Font.Normal
                                                color: isToday ? (Theme.isDark ? "#101116" : "#ffffff") : (isCurrentMonth ? Theme.fg : Theme.fgFaint)
                                            }
                                        }

                                        MouseArea {
                                            id: dayMH
                                            anchors.fill: parent
                                            hoverEnabled: isCurrentMonth
                                            cursorShape: isCurrentMonth ? Qt.PointingHandCursor : Qt.ArrowCursor
                                            onClicked: {
                                                if (isCurrentMonth) root.selectedDay = dayNum
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ── View C: Audio Devices, Apps Volume & Virtual Devices Toggle ──
                    Item {
                        anchors.fill: parent
                        visible: root.centerTab === 2

                        Flickable {
                            id: audioFlick
                            anchors.fill: parent
                            contentWidth: width
                            contentHeight: audioCol.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            ScrollBar.vertical: ScrollBar {
                                parent: audioFlick
                                anchors.right: audioFlick.right
                                anchors.top: audioFlick.top
                                anchors.bottom: audioFlick.bottom
                                width: 4
                                policy: ScrollBar.AsNeeded
                                contentItem: Rectangle {
                                    implicitWidth: 4
                                    radius: 2
                                    color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.45)
                                }
                            }

                            ColumnLayout {
                                id: audioCol
                                width: parent.width - 6
                                spacing: 8

                                // 1. Virtual Devices Toggle Card
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 34
                                    radius: 10
                                    color: root.showVirtualDevices ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.12) : Qt.rgba(Theme.bgAlt.r, Theme.bgAlt.g, Theme.bgAlt.b, 0.65)
                                    border.width: 1
                                    border.color: root.showVirtualDevices ? Qt.rgba(Theme.accentLit.r, Theme.accentLit.g, Theme.accentLit.b, 0.40) : Theme.outline

                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    Behavior on border.color { ColorAnimation { duration: 150 } }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        spacing: 8

                                        Text {
                                            text: "tune"
                                            font.family: Theme.fontIcon
                                            font.pixelSize: 14
                                            color: root.showVirtualDevices ? Theme.accent : Theme.fgDim
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 0
                                            Text {
                                                text: "Virtual Audio Devices"
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: Theme.fontPx(8)
                                                font.weight: Font.Bold
                                                color: root.showVirtualDevices ? Theme.fg : Theme.fgDim
                                            }
                                            Text {
                                                text: "EasyEffects & software sinks"
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: Theme.fontPx(6.8)
                                                color: Theme.fgFaint
                                            }
                                        }

                                        // Switch Pill
                                        Rectangle {
                                            Layout.preferredWidth: 32
                                            Layout.preferredHeight: 18
                                            radius: 9
                                            color: root.showVirtualDevices ? Theme.accent : Qt.rgba(1, 1, 1, 0.15)
                                            Behavior on color { ColorAnimation { duration: 150 } }

                                            Rectangle {
                                                width: 14
                                                height: 14
                                                radius: 7
                                                anchors.verticalCenter: parent.verticalCenter
                                                x: root.showVirtualDevices ? parent.width - width - 2 : 2
                                                color: root.showVirtualDevices ? (Theme.isDark ? "#101116" : "#ffffff") : (Theme.isDark ? "#bbbbbb" : "#888888")
                                                Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                            }
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.toggleVirtualDevices()
                                    }
                                }

                                // 2A. Output Ports (Speakers / Headphones)
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4
                                    visible: root.outputPorts.length > 0

                                    Text {
                                        text: "Output Port"
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: Theme.fontPx(7.5)
                                        font.weight: Font.Bold
                                        color: Theme.fgFaint
                                    }

                                    Repeater {
                                        model: root.outputPorts
                                        delegate: Rectangle {
                                            required property var modelData
                                            readonly property bool isActive: root.activeOutputPort === modelData.name
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 28
                                            radius: 8
                                            color: isActive ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16) : (portMH.containsMouse ? Theme.bgHover : Qt.rgba(Theme.bgAlt.r, Theme.bgAlt.g, Theme.bgAlt.b, 0.40))
                                            border.width: 1
                                            border.color: isActive ? Theme.accent : (portMH.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Theme.outline)

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 8
                                                anchors.rightMargin: 8
                                                spacing: 6

                                                Rectangle {
                                                    width: 12; height: 12; radius: 6
                                                    color: isActive ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.25) : "transparent"
                                                    border.width: 1.5
                                                    border.color: isActive ? Theme.accent : Theme.fgFaint
                                                    Rectangle {
                                                        anchors.centerIn: parent
                                                        width: 5; height: 5; radius: 2.5
                                                        color: Theme.accent
                                                        visible: isActive
                                                    }
                                                }

                                                Text {
                                                    text: /headphone|headset/i.test(modelData.desc || modelData.name) ? "headphones" : "volume_up"
                                                    font.family: Theme.fontIcon
                                                    font.pixelSize: 13
                                                    color: isActive ? Theme.accent : Theme.fgDim
                                                }

                                                Text {
                                                    Layout.fillWidth: true
                                                    text: modelData.desc || modelData.name
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: Theme.fontPx(7.8)
                                                    font.weight: isActive ? Font.Bold : Font.Normal
                                                    color: isActive ? Theme.fg : Theme.fgDim
                                                    elide: Text.ElideRight
                                                }

                                                Text {
                                                    visible: isActive
                                                    text: "check"
                                                    font.family: Theme.fontIcon
                                                    font.pixelSize: 12
                                                    color: Theme.accent
                                                }
                                            }

                                            MouseArea {
                                                id: portMH
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.selectOutputPort(modelData.name)
                                            }
                                        }
                                    }
                                }

                                // 2B. Audio Devices List (Sinks)
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4

                                    Text {
                                        text: "Output Devices"
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: Theme.fontPx(7.5)
                                        font.weight: Font.Bold
                                        color: Theme.fgFaint
                                    }

                                    Repeater {
                                        model: root.sinks
                                        delegate: Rectangle {
                                            id: sinkCard
                                            required property var modelData
                                            readonly property var node: modelData
                                            readonly property bool isDefault: root.defaultSink && root.defaultSink.id === node.id
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 30
                                            radius: 8
                                            color: isDefault ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16) : (sinkMH.containsMouse ? Theme.bgHover : Qt.rgba(Theme.bgAlt.r, Theme.bgAlt.g, Theme.bgAlt.b, 0.40))
                                            border.width: 1
                                            border.color: isDefault ? Theme.accent : (sinkMH.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Theme.outline)

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 8
                                                anchors.rightMargin: 8
                                                spacing: 6

                                                Rectangle {
                                                    width: 12; height: 12; radius: 6
                                                    color: isDefault ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.25) : "transparent"
                                                    border.width: 1.5
                                                    border.color: isDefault ? Theme.accent : Theme.fgFaint
                                                    Rectangle {
                                                        anchors.centerIn: parent
                                                        width: 5; height: 5; radius: 2.5
                                                        color: Theme.accent
                                                        visible: isDefault
                                                    }
                                                }

                                                Text {
                                                    text: {
                                                        const nm = (node.name || "") + " " + (node.description || "")
                                                        if (/easyeffects/i.test(nm)) return "graphic_eq"
                                                        if (/bluez|bluetooth/i.test(nm)) return "bluetooth_audio"
                                                        if (/hdmi/i.test(nm)) return "tv"
                                                        if (/headphone|headset/i.test(nm)) return "headphones"
                                                        if (/usb/i.test(nm)) return "speaker"
                                                        return "volume_up"
                                                    }
                                                    font.family: Theme.fontIcon
                                                    font.pixelSize: 13
                                                    color: isDefault ? Theme.accent : Theme.fgDim
                                                }

                                                Text {
                                                    Layout.fillWidth: true
                                                    text: root.nodeName(node)
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: Theme.fontPx(7.8)
                                                    font.weight: isDefault ? Font.Bold : Font.Normal
                                                    color: isDefault ? Theme.fg : Theme.fgDim
                                                    elide: Text.ElideRight
                                                }

                                                Text {
                                                    visible: isDefault
                                                    text: "check"
                                                    font.family: Theme.fontIcon
                                                    font.pixelSize: 12
                                                    color: Theme.accent
                                                }
                                            }

                                            MouseArea {
                                                id: sinkMH
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    Pipewire.preferredDefaultAudioSink = node
                                                    Quickshell.execDetached(["wpctl", "set-default", String(node.id)])
                                                    root.refreshOutputPorts()
                                                }
                                            }
                                        }
                                    }

                                    Text {
                                        visible: root.sinks.length === 0
                                        Layout.fillWidth: true
                                        text: "No audio output devices found"
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: Theme.fontPx(7.5)
                                        color: Theme.fgFaint
                                        horizontalAlignment: Text.AlignHCenter
                                    }
                                }

                                // 3. Application Volumes Section
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 4

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text {
                                            text: "Application Volumes"
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: Theme.fontPx(7.5)
                                            font.weight: Font.Bold
                                            color: Theme.fgFaint
                                        }
                                        Item { Layout.fillWidth: true }
                                        Text {
                                            visible: root.activeAppStreams.length > 0
                                            text: root.activeAppStreams.length + " active"
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: Theme.fontPx(6.8)
                                            color: Theme.accentLit
                                        }
                                    }

                                    Repeater {
                                        model: root.activeAppStreams
                                        delegate: Rectangle {
                                            id: appCard
                                            required property var modelData
                                            readonly property var node: modelData
                                            readonly property bool appMuted: (node && node.audio) ? node.audio.muted : false
                                            readonly property real appVol: (node && node.audio) ? Math.max(0, Math.min(1.0, node.audio.volume)) : 0.0

                                            PwObjectTracker { objects: node ? [node] : [] }

                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 46
                                            radius: 10
                                            color: Qt.rgba(Theme.bgAlt.r, Theme.bgAlt.g, Theme.bgAlt.b, 0.50)
                                            border.width: 1
                                            border.color: Theme.outline

                                            ColumnLayout {
                                                anchors.fill: parent
                                                anchors.margins: 6
                                                spacing: 4

                                                // Top row: App Icon, Name, Mute Icon, App %
                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 6

                                                    Rectangle {
                                                        width: 18; height: 18; radius: 9
                                                        color: appMuteMH.containsMouse ? Theme.bgHover : "transparent"
                                                        Text {
                                                            anchors.centerIn: parent
                                                            text: appCard.appMuted ? "volume_off" : "volume_down"
                                                            font.family: Theme.fontIcon
                                                            font.pixelSize: 12
                                                            color: appCard.appMuted ? Theme.err : Theme.accent
                                                        }
                                                        MouseArea {
                                                            id: appMuteMH
                                                            anchors.fill: parent
                                                            hoverEnabled: true
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: {
                                                                if (appCard.node && appCard.node.audio) {
                                                                    appCard.node.audio.muted = !appCard.node.audio.muted
                                                                }
                                                            }
                                                        }
                                                    }

                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: root.nodeName(appCard.node)
                                                        font.family: "JetBrainsMono Nerd Font"
                                                        font.pixelSize: Theme.fontPx(7.8)
                                                        font.weight: Font.Bold
                                                        color: appCard.appMuted ? Theme.fgFaint : Theme.fg
                                                        elide: Text.ElideRight
                                                    }

                                                    Text {
                                                        text: Math.round((appCard.appMuted ? 0 : appCard.appVol) * 100) + "%"
                                                        font.family: "JetBrainsMono Nerd Font"
                                                        font.pixelSize: Theme.fontPx(7.2)
                                                        font.weight: Font.Bold
                                                        color: Theme.fgDim
                                                    }
                                                }

                                                // Bottom row: Interactive Slider Track
                                                Item {
                                                    id: appVolTrack
                                                    Layout.fillWidth: true
                                                    Layout.preferredHeight: 12

                                                    Rectangle {
                                                        anchors.fill: parent
                                                        radius: 6
                                                        color: Qt.rgba(1, 1, 1, 0.08)
                                                    }

                                                    Rectangle {
                                                        height: parent.height
                                                        width: Math.max(0, Math.min(parent.width, parent.width * (appCard.appMuted ? 0 : appCard.appVol)))
                                                        radius: 6
                                                        color: appCard.appMuted ? Theme.fgFaint : Theme.accent
                                                        Behavior on width {
                                                            enabled: !appVolMA.pressed
                                                            NumberAnimation { duration: 80 }
                                                        }
                                                    }

                                                    MouseArea {
                                                        id: appVolMA
                                                        anchors.fill: parent
                                                        preventStealing: true
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        function setAppVol(mx) {
                                                            var r = Math.max(0, Math.min(1.0, mx / appVolTrack.width))
                                                            if (appCard.node && appCard.node.audio) {
                                                                appCard.node.audio.volume = r
                                                                if (appCard.node.audio.muted && r > 0) appCard.node.audio.muted = false
                                                            }
                                                        }
                                                        onPressed: mouse => setAppVol(mouse.x)
                                                        onPositionChanged: mouse => { if (pressed) setAppVol(mouse.x) }
                                                    }

                                                    WheelHandler {
                                                        target: appVolTrack
                                                        onWheel: (event) => {
                                                            var step = event.angleDelta.y > 0 ? 0.04 : -0.04
                                                            if (appCard.node && appCard.node.audio) {
                                                                var nv = Math.max(0, Math.min(1.0, appCard.appVol + step))
                                                                appCard.node.audio.volume = nv
                                                                if (appCard.node.audio.muted && step > 0) appCard.node.audio.muted = false
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // Empty state when no apps playing audio
                                    Rectangle {
                                        visible: root.activeAppStreams.length === 0
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 46
                                        radius: 10
                                        color: Qt.rgba(Theme.bgAlt.r, Theme.bgAlt.g, Theme.bgAlt.b, 0.30)
                                        border.width: 1
                                        border.color: Theme.outline

                                        RowLayout {
                                            anchors.centerIn: parent
                                            spacing: 6
                                            Text {
                                                text: "music_off"
                                                font.family: Theme.fontIcon
                                                font.pixelSize: 14
                                                color: Theme.fgFaint
                                            }
                                            Text {
                                                text: "No active audio streams playing"
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: Theme.fontPx(7.5)
                                                color: Theme.fgFaint
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            /* ========================================================= */
            /* 3. RIGHT COLUMN: MEDIA PLAYER & WEATHER (~268px)         */
            /* ========================================================= */
            ColumnLayout {
                Layout.preferredWidth: 268
                Layout.fillHeight: true
                spacing: 8

                // 3A. Live Header (Clock, Date & Weather Capsule)
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 26
                    spacing: 6

                    // Clock & Date
                    RowLayout {
                        spacing: 4
                        Text {
                            text: root.timeStr
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: Theme.fontPx(11)
                            font.weight: Font.Bold
                            color: Theme.fg
                        }
                        Text {
                            text: "· " + root.dateStr
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: Theme.fontPx(8)
                            font.weight: Font.Medium
                            color: Theme.fgDim
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Weather Capsule
                    Rectangle {
                        Layout.preferredHeight: 24
                        Layout.preferredWidth: weatherRow.implicitWidth + 12
                        radius: 12
                        color: Qt.rgba(1, 1, 1, 0.06)
                        border.width: 1
                        border.color: Theme.outline

                        RowLayout {
                            id: weatherRow
                            anchors.centerIn: parent
                            spacing: 4

                            Text {
                                text: WeatherService.icon.length > 0 ? WeatherService.icon : "cloud"
                                font.family: Theme.fontIcon
                                font.pixelSize: 13
                                color: Theme.accentLit
                            }
                            Text {
                                text: WeatherService.temp.length > 0 ? WeatherService.temp : "--°"
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: Theme.fontPx(8)
                                font.weight: Font.Bold
                                color: Theme.fg
                            }
                            Text {
                                visible: WeatherService.city.length > 0
                                text: "• " + WeatherService.city
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: Theme.fontPx(7.5)
                                color: Theme.fgDim
                                elide: Text.ElideRight
                                Layout.maximumWidth: 60
                            }
                        }
                    }
                }

                // 3B. Rich Media Player Card
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 14
                    color: Qt.rgba(Theme.bgAlt.r, Theme.bgAlt.g, Theme.bgAlt.b, 0.65)
                    border.width: 1
                    border.color: Theme.outline
                    clip: true

                    // Ambient blurred art background
                    Image {
                        anchors.fill: parent
                        source: root.musicArtUrl
                        sourceSize: Qt.size(200, 200)
                        fillMode: Image.PreserveAspectCrop
                        opacity: (status === Image.Ready && root.hasMusicTrack) ? 0.12 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 200 } }
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 8

                        // Track Art & Metadata Row
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            // Album Art / Vinyl Disc
                            Rectangle {
                                width: 50; height: 50
                                radius: 10
                                color: Theme.bg
                                border.width: 1
                                border.color: root.hasMusicTrack ? Theme.accent : Theme.outline
                                clip: true

                                Image {
                                    id: artImg
                                    anchors.fill: parent
                                    source: root.musicArtUrl
                                    sourceSize: Qt.size(100, 100)
                                    fillMode: Image.PreserveAspectCrop
                                    visible: root.hasMusicTrack && root.musicArtUrl.length > 0 && status === Image.Ready
                                }

                                Item {
                                    anchors.fill: parent
                                    visible: !root.hasMusicTrack || root.musicArtUrl.length === 0 || artImg.status !== Image.Ready

                                    Text {
                                        anchors.centerIn: parent
                                        text: "music_note"
                                        font.family: Theme.fontIcon
                                        font.pixelSize: 22
                                        color: Theme.accent
                                    }
                                }
                            }

                            // Track Title & Artist
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                Text {
                                    Layout.fillWidth: true
                                    text: root.musicTitle
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: Theme.fontPx(9.5)
                                    font.weight: Font.Bold
                                    color: Theme.fg
                                    elide: Text.ElideRight
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: root.musicArtist
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: Theme.fontPx(8)
                                    font.weight: Font.Medium
                                    color: Theme.fgDim
                                    elide: Text.ElideRight
                                }

                                Text {
                                    text: (root.mprisPlayer && root.mprisPlayer.identity) ? root.mprisPlayer.identity : "Media"
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: Theme.fontPx(7)
                                    color: Theme.fgFaint
                                }
                            }
                        }

                        // Seekable Progress Slider
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Item {
                                id: seekTrack
                                Layout.fillWidth: true
                                Layout.preferredHeight: 14

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: parent.width; height: 4
                                    radius: 2
                                    color: Qt.rgba(1, 1, 1, 0.12)
                                }

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: 0
                                    width: Math.max(0, Math.min(seekTrack.width, seekTrack.width * root.musicProgress))
                                    height: 4
                                    radius: 2
                                    color: Theme.accent
                                }

                                // Interactive Seek Area
                                MouseArea {
                                    id: seekMA
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: root.hasMusicTrack ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onClicked: mouse => {
                                        if (root.hasMusicTrack && seekTrack.width > 0) {
                                            root.seekRatio(mouse.x / seekTrack.width)
                                        }
                                    }
                                }
                            }

                            // Time Labels (Elapsed / Total)
                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: root.formatTime(root.musicPosition)
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: Theme.fontPx(7)
                                    color: Theme.fgDim
                                }
                                Item { Layout.fillWidth: true }
                                Text {
                                    text: root.formatTime(root.musicLength)
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: Theme.fontPx(7)
                                    color: Theme.fgDim
                                }
                            }
                        }

                        // Playback Controls Row (Prev, Play/Pause, Next)
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 16

                            Item { Layout.fillWidth: true }

                            // Previous
                            Rectangle {
                                width: 28; height: 28; radius: 14
                                color: prevBtnMH.containsMouse ? Theme.bgHover : "transparent"
                                Text {
                                    anchors.centerIn: parent
                                    text: "skip_previous"
                                    font.family: Theme.fontIcon
                                    font.pixelSize: 18
                                    color: prevBtnMH.containsMouse ? Theme.accent : Theme.fg
                                }
                                MouseArea {
                                    id: prevBtnMH
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (root.mprisPlayer) root.mprisPlayer.previous()
                                    }
                                }
                            }

                            // Play / Pause (Accent Circle)
                            Rectangle {
                                width: 36; height: 36; radius: 18
                                color: playBtnMH.containsMouse ? Qt.rgba(Theme.accentLit.r, Theme.accentLit.g, Theme.accentLit.b, 1.0) : Theme.accent
                                border.width: 1
                                border.color: Qt.rgba(1, 1, 1, 0.2)

                                Text {
                                    anchors.centerIn: parent
                                    text: root.isMusicPlaying ? "pause" : "play_arrow"
                                    font.family: Theme.fontIcon
                                    font.pixelSize: 20
                                    color: Theme.isDark ? "#101116" : "#ffffff"
                                }
                                MouseArea {
                                    id: playBtnMH
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (root.mprisPlayer) root.mprisPlayer.togglePlaying()
                                    }
                                }
                            }

                            // Next
                            Rectangle {
                                width: 28; height: 28; radius: 14
                                color: nextBtnMH.containsMouse ? Theme.bgHover : "transparent"
                                Text {
                                    anchors.centerIn: parent
                                    text: "skip_next"
                                    font.family: Theme.fontIcon
                                    font.pixelSize: 18
                                    color: nextBtnMH.containsMouse ? Theme.accent : Theme.fg
                                }
                                MouseArea {
                                    id: nextBtnMH
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (root.mprisPlayer) root.mprisPlayer.next()
                                    }
                                }
                            }

                            Item { Layout.fillWidth: true }
                        }
                    }
                }
            }
        }
    }
}
