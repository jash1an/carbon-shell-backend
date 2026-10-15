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
 *   - System shortcuts: Screen recorder, Screenshot, Settings, Lock, Power
 *   - 2x2 Quick toggles: Wi-Fi, Bluetooth, Night Light (Working), DND (Synced)
 *   - Wi-Fi & Bluetooth include dedicated arrow buttons to browse options in a linked sub-menu!
 *   - Hardware sliders: Volume & Brightness
 *
 * Middle Column (Media Player & Live Info):
 *   - Live Clock & Weather capsule
 *   - Rich Media Player: Vinyl album art, title, artist, progress slider, controls
 *
 * Right Column (Audio & Calendar Tabs):
 *   - Audio Tab:
 *       * Output Devices & Ports (Speakers / Headphones)
 *       * Input Devices / Microphones (Source switcher, Mic volume slider & mute toggle)
 *       * App Volume Streams (Kitty, Zen, Spotify, Serein, etc.)
 *       * Virtual Audio Devices persistent toggle
 *   - Calendar Tab: Dynamic month grid & agenda
 *   - System Tab: CPU, RAM, Battery & Storage gauges
 */
Item {
    id: root

    property bool open: false
    property bool animatingOut: false
    property alias cardItem: mainCard
    property bool minimalCalendarOnly: false
    property bool attachedBottom: false
    property bool showBackground: true
    readonly property bool hovered: (rootHover && rootHover.hovered) || (mainCardHover && mainCardHover.hovered)
    signal closeRequested()

    implicitWidth: root.minimalCalendarOnly ? 310 : 940
    implicitHeight: root.minimalCalendarOnly ? 276 : 330
    width: implicitWidth
    height: implicitHeight
    clip: true

    readonly property string home: Quickshell.env("HOME") || ""

    focus: root.open
    Keys.enabled: root.open
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Escape) {
            if (root.activeSubMenu !== "") {
                root.activeSubMenu = ""
                event.accepted = true
            } else {
                root.closeRequested()
                event.accepted = true
            }
        }
    }
    Keys.onEscapePressed: (event) => {
        if (root.activeSubMenu !== "") {
            root.activeSubMenu = ""
            event.accepted = true
        } else {
            root.closeRequested()
            event.accepted = true
        }
    }

    HoverHandler {
        id: rootHover
    }

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
        onTriggered: {
            root.currentDate = new Date()
            root.timeStr = Qt.formatTime(root.currentDate, "hh:mm")
            root.dateStr = Qt.formatDate(root.currentDate, "ddd, MMM d")
        }
    }

    /* ── Sub-Menu State for Wi-Fi and Bluetooth ──────────────────────── */
    property string activeSubMenu: "" // "" | "wifi" | "bluetooth"

    /* ── Quick Toggles State ─────────────────────────────────────────── */
    property bool wifiOn: false
    property string wifiName: ""
    property bool btOn: false
    property string btName: ""
    property bool nightOn: false
    property bool nightAvailable: true
    property bool dndOn: false

    Timer {
        id: settleTimer
        interval: 400
        repeat: false
        onTriggered: root.refreshStates()
    }

    function refreshStates() {
        if (!wifiProbe.running) wifiProbe.running = true
        if (!btProbe.running) btProbe.running = true
        if (!nightProbe.running) nightProbe.running = true
        if (!dndProbe.running) dndProbe.running = true
        if (!brightProbe.running) brightProbe.running = true
        if (!recProbe.running) recProbe.running = true
    }

    onOpenChanged: {
        if (root.open) {
            root.animatingOut = false
            animatingOutTimer.stop()
            root.activeSubMenu = ""
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

    function shellQuote(s) {
        return "'" + String(s).replace(/'/g, "'\\''") + "'"
    }

    // Wi-Fi Backend
    Process {
        id: wifiProbe
        command: ["sh", "-c", "echo \"$(nmcli -t -f WIFI g 2>/dev/null):$(nmcli -t -f ACTIVE,SSID dev wifi 2>/dev/null | grep '^yes:' | cut -d: -f2-)\""]
        stdout: StdioCollector { id: wifiC; waitForEnd: true }
        onExited: {
            const raw = String(wifiC.text).trim().split(":")
            root.wifiOn = (raw[0] === "enabled")
            root.wifiName = (raw.length > 1 && raw[1]) ? raw[1] : ""
        }
    }
    function toggleWifi() {
        root.wifiOn = !root.wifiOn
        Quickshell.execDetached(["nmcli", "radio", "wifi", root.wifiOn ? "on" : "off"])
        settleTimer.restart()
    }

    // Wi-Fi Scanner for Sub-menu
    property var wifiNetworks: []
    property bool wifiScanning: false
    property string wifiConnectSsid: ""
    property string wifiPassword: ""
    property string wifiStatus: ""
    property bool showWifiPasswordPrompt: false

    Process {
        id: wifiScanListProc
        command: ["sh", "-c", "nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY dev wifi list 2>/dev/null"]
        stdout: StdioCollector { id: wifiScanCol; waitForEnd: true }
        onExited: {
            root.wifiScanning = false
            var raw = String(wifiScanCol.text).trim().split("\n")
            var list = []
            var seen = {}
            for (var i = 0; i < raw.length; i++) {
                var line = raw[i].trim()
                if (!line) continue
                var parts = line.split(":")
                if (parts.length >= 3) {
                    var inUse = parts[0] === "*"
                    var ssid = parts[1]
                    var signal = parseInt(parts[2]) || 50
                    var sec = parts.length > 3 ? parts[3] : ""
                    if (ssid && !seen[ssid]) {
                        seen[ssid] = true
                        list.push({ inUse: inUse, ssid: ssid, signal: signal, security: sec, isSecure: sec.length > 0 && sec !== "--" })
                    }
                }
            }
            root.wifiNetworks = list
        }
    }

    function scanWifi() {
        root.wifiScanning = true
        root.wifiStatus = "Scanning for networks..."
        Quickshell.execDetached(["sh", "-c", "nmcli dev wifi rescan >/dev/null 2>&1"])
        wifiScanTimer.restart()
    }

    Timer {
        id: wifiScanTimer
        interval: 1000
        onTriggered: {
            if (!wifiScanListProc.running) wifiScanListProc.running = true
            root.wifiStatus = ""
        }
    }

    function connectWifi(ssid, pw) {
        root.wifiStatus = "Connecting to " + ssid + "..."
        var cmd = pw ? ("nmcli dev wifi connect " + shellQuote(ssid) + " password " + shellQuote(pw)) : ("nmcli dev wifi connect " + shellQuote(ssid))
        Quickshell.execDetached(["sh", "-c", cmd + " && sleep 1 && nmcli dev wifi list >/dev/null 2>&1"])
        root.showWifiPasswordPrompt = false
        root.wifiConnectSsid = ""
        root.wifiPassword = ""
        wifiScanTimer.restart()
    }

    // Bluetooth Backend
    Process {
        id: btProbe
        command: ["sh", "-c", "echo \"$(rfkill list bluetooth | grep -qi 'Soft blocked: no' && echo on || echo off):$(bluetoothctl info 2>/dev/null | grep 'Name:' | head -n1 | cut -d: -f2-)\""]
        stdout: StdioCollector { id: btC; waitForEnd: true }
        onExited: {
            const raw = String(btC.text).trim().split(":")
            root.btOn = (raw[0] === "on")
            root.btName = (raw.length > 1 && raw[1]) ? raw[1].trim() : ""
        }
    }
    function toggleBt() {
        root.btOn = !root.btOn
        if (!root.btOn) root.btName = ""
        Quickshell.execDetached(["sh", "-c", "rfkill " + (root.btOn ? "unblock" : "block") + " bluetooth 2>/dev/null; bluetoothctl power " + (root.btOn ? "on" : "off") + " >/dev/null 2>&1"])
        settleTimer.restart()
    }

    property var btDevices: []
    property bool btScanning: false
    property string btStatus: ""

    Process {
        id: btListProc
        command: ["sh", "-c", "if command -v bluetoothctl >/dev/null 2>&1; then bluetoothctl devices 2>/dev/null | head -n 12; else echo 'NO_BT_UTIL'; fi"]
        stdout: StdioCollector { id: btListCol; waitForEnd: true }
        onExited: {
            root.btScanning = false
            var txt = String(btListCol.text).trim()
            if (txt === "NO_BT_UTIL") {
                root.btDevices = []
                root.btStatus = "bluez-utils not installed"
                return
            }
            if (txt.length === 0) {
                root.btDevices = []
                root.btStatus = "No Bluetooth devices discovered"
                return
            }
            var lines = txt.split("\n")
            var list = []
            for (var i = 0; i < lines.length; i++) {
                var l = lines[i].trim()
                if (l.startsWith("Device")) {
                    var p = l.split(" ")
                    var mac = p[1]
                    var name = p.slice(2).join(" ")
                    list.push({ mac: mac, name: name || mac })
                }
            }
            root.btDevices = list
            root.btStatus = list.length === 0 ? "No devices paired" : ""
        }
    }

    function scanBt() {
        root.btScanning = true
        root.btStatus = "Scanning..."
        if (!btListProc.running) btListProc.running = true
    }

    // Night Light (Works seamlessly with Hyprland shader & carbon-night.sh)
    Process {
        id: nightProbe
        command: [root.home + "/.config/carbon/scripts/carbon-night.sh", "status"]
        stdout: StdioCollector { id: nightC; waitForEnd: true }
        onExited: {
            const v = String(nightC.text).trim()
            root.nightAvailable = true
            root.nightOn = v === "on"
        }
    }
    function toggleNight() {
        root.nightOn = !root.nightOn
        Quickshell.execDetached([root.home + "/.config/carbon/scripts/carbon-night.sh", root.nightOn ? "on" : "off"])
        settleTimer.restart()
    }

    // Do Not Disturb (DND sync with NotificationService & /tmp/carbon-dnd.on)
    Process {
        id: dndProbe
        command: ["sh", "-c", "if [ -f /tmp/carbon-dnd.on ]; then echo true; else echo false; fi"]
        stdout: StdioCollector { id: dndC; waitForEnd: true }
        onExited: {
            root.dndOn = String(dndC.text).trim() === "true"
            Theme.dnd = root.dndOn
            NotificationService.dnd = root.dndOn
        }
    }
    function toggleDnd() {
        root.dndOn = !root.dndOn
        Theme.dnd = root.dndOn
        NotificationService.dnd = root.dndOn
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

    /* ── Audio Output State ───────────────────────────────────────────── */
    readonly property var audioSink: Pipewire.defaultAudioSink
    readonly property var defaultSink: audioSink
    readonly property real volRatio: (audioSink && audioSink.audio) ? Math.max(0, Math.min(1.0, audioSink.audio.volume)) : 0.0
    readonly property bool isMuted: (audioSink && audioSink.audio) ? audioSink.audio.muted : false

    /* ── Audio Input / Microphone State ───────────────────────────────── */
    readonly property var audioSource: Pipewire.defaultAudioSource
    readonly property var defaultSource: audioSource
    readonly property real micVolRatio: (audioSource && audioSource.audio) ? Math.max(0, Math.min(1.0, audioSource.audio.volume)) : 1.0
    readonly property bool isMicMuted: (audioSource && audioSource.audio) ? audioSource.audio.muted : false

    function setMicVolume(r) {
        r = Math.max(0, Math.min(1.0, r))
        if (root.audioSource && root.audioSource.audio) {
            root.audioSource.audio.volume = r
            if (root.audioSource.audio.muted && r > 0) root.audioSource.audio.muted = false
        }
        Quickshell.execDetached(["wpctl", "set-volume", "@DEFAULT_AUDIO_SOURCE@", r.toFixed(2)])
    }

    function toggleMicMute() {
        if (root.audioSource && root.audioSource.audio) {
            root.audioSource.audio.muted = !root.audioSource.audio.muted
        }
        Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE@", "toggle"])
    }

    function selectAudioSource(sourceNode) {
        if (!sourceNode) return
        Quickshell.execDetached(["wpctl", "set-default", String(sourceNode.id)])
        if (sourceNode.name) {
            Quickshell.execDetached(["pactl", "set-default-source", sourceNode.name])
        }
    }

    function selectAudioSink(sinkNode) {
        if (!sinkNode) return
        Quickshell.execDetached(["wpctl", "set-default", String(sinkNode.id)])
        if (sinkNode.name) {
            Quickshell.execDetached(["pactl", "set-default-sink", sinkNode.name])
        }
        root.refreshOutputPorts()
    }

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

    readonly property var sources: allNodes.filter(n => {
        if (!n || !n.audio || n.isStream) return false;
        var isSource = (n.properties && n.properties["media.class"] === "Audio/Source") || (n.isSource && (!n.properties || !n.properties["media.class"]));
        if (!isSource) return false;
        if (root.showVirtualDevices) return true;
        var idStr = String((n.properties && (n.properties["media.class"] || n.properties["node.name"])) || n.name || "");
        return !/virtual|null|stream|easyeffects|monitor/i.test(idStr);
    })

    /* Apps currently routed towards default sink */
    PwNodeLinkTracker {
        id: linkTracker
        node: root.defaultSink
    }

    readonly property var streams: linkTracker.linkGroups

    PwObjectTracker {
        objects: [ root.defaultSink, root.defaultSource ].filter(n => n !== null)
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
        if (!n) return "Default Audio Device";
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

    /* Output ports */
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

    /* ── Brightness Slider ────────────────────────────────────────────── */
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

    function setBrightness(r) {
        r = Math.max(0.01, Math.min(1.0, r))
        root.brightRatio = r
        root.lastBrightWrite = Date.now()
        Quickshell.execDetached(["brightnessctl", "--class", "backlight", "s", Math.max(1, Math.round(r * 100)) + "%"])
    }

    /* ── Right Column Tabs: 0: Audio, 1: Calendar, 2: System ─────────── */
    property int centerTab: 0

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
    readonly property var mprisPlayer: Mpris.players.values.length > 0 ? Mpris.players.values[0] : null
    readonly property bool hasMusicTrack: LyricsService.hasActiveTrack || (mprisPlayer && mprisPlayer.trackTitle.length > 0)
    readonly property bool isMusicPlaying: LyricsService.isPlaying || (mprisPlayer && mprisPlayer.playbackState === MprisPlaybackState.Playing)
    readonly property string musicArtUrl: LyricsService.artUrl.length > 0 ? LyricsService.artUrl : (mprisPlayer ? mprisPlayer.trackArtUrl : "")
    readonly property string musicTitle: hasMusicTrack ? (LyricsService.trackTitle || "No title") : "No media playing"
    readonly property string musicArtist: hasMusicTrack ? (LyricsService.trackArtist || "Unknown artist") : "Silence"
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

            // 1. Background fill
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

            // 2. Stroke outline
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
            /* 1. LEFT COLUMN: QUICK CONTROLS & SLIDERS (~268px)        */
            /* ========================================================= */
            ColumnLayout {
                Layout.preferredWidth: 268
                Layout.fillHeight: true
                spacing: 8

                // VIEW 1A: NORMAL QUICK CONTROLS VIEW (when activeSubMenu === "")
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 8
                    visible: root.activeSubMenu === ""

                    // Shortcuts Header Row (Recorder, Screenshot, Settings, Lock, Power)
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
                                onClicked: Quickshell.execDetached(["sh", "-c", "hyprlock || true"])
                            }
                        }

                        Item { Layout.fillWidth: true }

                        // Power
                        Rectangle {
                            width: 26; height: 26; radius: 13
                            color: pwrMH.containsMouse ? Qt.rgba(Theme.err.r, Theme.err.g, Theme.err.b, 0.25) : Qt.rgba(1, 1, 1, 0.05)
                            border.width: 1
                            border.color: pwrMH.containsMouse ? Theme.err : Theme.outline
                            Text {
                                anchors.centerIn: parent
                                text: "power_settings_new"
                                font.family: Theme.fontIcon
                                font.pixelSize: 13
                                color: pwrMH.containsMouse ? Theme.err : Theme.fgDim
                            }
                            MouseArea {
                                id: pwrMH
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Quickshell.execDetached([root.home + "/.config/hypr/scripts/carbon-power.sh"])
                            }
                        }
                    }

                    // 2x2 Quick Toggles Grid (Wi-Fi, Bluetooth, Night Light, DND)
                    // 2x2 Quick Toggles Grid (Wi-Fi, Bluetooth, Night Light, DND)
                    GridLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 96
                        columns: 2
                        rowSpacing: 6
                        columnSpacing: 6

                        // Tile 1: Wi-Fi with dedicated menu arrow
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 45
                            radius: 10
                            color: root.wifiOn ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16)
                                               : (wifiTileHov.containsMouse ? Theme.bgHover : Qt.rgba(Theme.bgAlt.r, Theme.bgAlt.g, Theme.bgAlt.b, 0.65))
                            border.width: 1
                            border.color: root.wifiOn ? Theme.accent : (wifiTileHov.containsMouse ? Theme.accentLit : Theme.outline)

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 4
                                spacing: 4

                                // Main toggle area (power on/off)
                                Item {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true

                                    RowLayout {
                                        anchors.fill: parent
                                        spacing: 6

                                        Rectangle {
                                            width: 26; height: 26; radius: 8
                                            color: root.wifiOn ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.28) : Qt.rgba(1, 1, 1, 0.08)
                                            Text {
                                                anchors.centerIn: parent
                                                text: "wifi"
                                                font.family: Theme.fontIcon
                                                font.pixelSize: 14
                                                color: root.wifiOn ? Theme.accentLit : Theme.fgDim
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
                                                color: root.wifiOn ? Theme.accentLit : Theme.fg
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                text: root.wifiOn ? (root.wifiName.length > 0 ? root.wifiName : "Connected") : "Off"
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: Theme.fontPx(7)
                                                color: root.wifiOn ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.75) : Theme.fgDim
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

                                // Arrow button to open Wi-Fi menu
                                Rectangle {
                                    width: 22
                                    height: 22
                                    radius: 6
                                    color: wifiArrowMA.containsMouse ? (root.wifiOn ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.25) : Theme.bgHover) : "transparent"

                                    Text {
                                        anchors.centerIn: parent
                                        text: "keyboard_arrow_right"
                                        font.family: Theme.fontIcon
                                        font.pixelSize: 15
                                        color: root.wifiOn ? Theme.accentLit : Theme.fgDim
                                    }

                                    MouseArea {
                                        id: wifiArrowMA
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.activeSubMenu = "wifi"
                                            root.scanWifi()
                                        }
                                    }
                                }
                            }
                        }

                        // Tile 2: Bluetooth with dedicated menu arrow
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 45
                            radius: 10
                            color: root.btOn ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16)
                                             : (btTileHov.containsMouse ? Theme.bgHover : Qt.rgba(Theme.bgAlt.r, Theme.bgAlt.g, Theme.bgAlt.b, 0.65))
                            border.width: 1
                            border.color: root.btOn ? Theme.accent : (btTileHov.containsMouse ? Theme.accentLit : Theme.outline)

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 4
                                spacing: 4

                                Item {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true

                                    RowLayout {
                                        anchors.fill: parent
                                        spacing: 6

                                        Rectangle {
                                            width: 26; height: 26; radius: 8
                                            color: root.btOn ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.28) : Qt.rgba(1, 1, 1, 0.08)
                                            Text {
                                                anchors.centerIn: parent
                                                text: "bluetooth"
                                                font.family: Theme.fontIcon
                                                font.pixelSize: 14
                                                color: root.btOn ? Theme.accentLit : Theme.fgDim
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
                                                color: root.btOn ? Theme.accentLit : Theme.fg
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                text: root.btOn ? (root.btName.length > 0 ? root.btName : "On") : "Off"
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: Theme.fontPx(7)
                                                color: root.btOn ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.75) : Theme.fgDim
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

                                // Arrow button to open Bluetooth menu
                                Rectangle {
                                    width: 22
                                    height: 22
                                    radius: 6
                                    color: btArrowMA.containsMouse ? (root.btOn ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.25) : Theme.bgHover) : "transparent"

                                    Text {
                                        anchors.centerIn: parent
                                        text: "keyboard_arrow_right"
                                        font.family: Theme.fontIcon
                                        font.pixelSize: 15
                                        color: root.btOn ? Theme.accentLit : Theme.fgDim
                                    }

                                    MouseArea {
                                        id: btArrowMA
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.activeSubMenu = "bluetooth"
                                            root.scanBt()
                                        }
                                    }
                                }
                            }
                        }

                        // Tile 3: Night Light
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 45
                            radius: 10
                            color: root.nightOn ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16)
                                                : (nightTileHov.containsMouse ? Theme.bgHover : Qt.rgba(Theme.bgAlt.r, Theme.bgAlt.g, Theme.bgAlt.b, 0.65))
                            border.width: 1
                            border.color: root.nightOn ? Theme.accent : (nightTileHov.containsMouse ? Theme.accentLit : Theme.outline)

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 6
                                spacing: 6

                                Rectangle {
                                    width: 26; height: 26; radius: 8
                                    color: root.nightOn ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.28) : Qt.rgba(1, 1, 1, 0.08)
                                    Text {
                                        anchors.centerIn: parent
                                        text: "nightlight"
                                        font.family: Theme.fontIcon
                                        font.pixelSize: 14
                                        color: root.nightOn ? Theme.accentLit : Theme.fgDim
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
                                        color: root.nightOn ? Theme.accentLit : Theme.fg
                                    }
                                    Text {
                                        text: root.nightOn ? "On" : "Off"
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: Theme.fontPx(7)
                                        color: root.nightOn ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.75) : Theme.fgDim
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

                        // Tile 4: Do Not Disturb (DND)
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 45
                            radius: 10
                            color: root.dndOn ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16)
                                              : (dndTileHov.containsMouse ? Theme.bgHover : Qt.rgba(Theme.bgAlt.r, Theme.bgAlt.g, Theme.bgAlt.b, 0.65))
                            border.width: 1
                            border.color: root.dndOn ? Theme.accent : (dndTileHov.containsMouse ? Theme.accentLit : Theme.outline)

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 6
                                spacing: 6

                                Rectangle {
                                    width: 26; height: 26; radius: 8
                                    color: root.dndOn ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.28) : Qt.rgba(1, 1, 1, 0.08)
                                    Text {
                                        anchors.centerIn: parent
                                        text: root.dndOn ? "notifications_off" : "notifications"
                                        font.family: Theme.fontIcon
                                        font.pixelSize: 14
                                        color: root.dndOn ? Theme.accentLit : Theme.fgDim
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
                                        color: root.dndOn ? Theme.accentLit : Theme.fg
                                    }
                                    Text {
                                        text: root.dndOn ? "On" : "Off"
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: Theme.fontPx(7)
                                        color: root.dndOn ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.75) : Theme.fgDim
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

                    // Hardware Sliders Box (Volume & Brightness)
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 10
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
                                        text: root.isMuted ? "volume_off" : (root.volRatio > 0.5 ? "volume_up" : (root.volRatio > 0.0 ? "volume_down" : "volume_mute"))
                                        font.family: Theme.fontIcon
                                        font.pixelSize: 14
                                        color: root.isMuted ? Theme.err : Theme.accentLit
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

                                    // Track background
                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        height: 6
                                        radius: 3
                                        color: Qt.rgba(1, 1, 1, 0.10)
                                    }
                                    // Progress bar
                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.verticalCenter: parent.verticalCenter
                                        height: 6
                                        width: Math.max(0, Math.min(parent.width, parent.width * (root.isMuted ? 0 : root.volRatio)))
                                        radius: 3
                                        color: root.isMuted ? Theme.fgFaint : Theme.accentLit
                                        Behavior on width {
                                            enabled: !volArea.pressed
                                            NumberAnimation { duration: 100 }
                                        }
                                    }
                                    // Circular Thumb
                                    Rectangle {
                                        width: 12; height: 12; radius: 6
                                        anchors.verticalCenter: parent.verticalCenter
                                        x: Math.max(0, Math.min(parent.width - width, (parent.width * (root.isMuted ? 0 : root.volRatio)) - (width / 2)))
                                        color: root.isMuted ? Theme.fgFaint : Theme.accentLit
                                        border.width: 1.5
                                        border.color: Theme.bg
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
                                        font.pixelSize: 14
                                        color: Theme.accentLit
                                    }
                                }

                                Item {
                                    id: brightTrack
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 18

                                    // Track background
                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        height: 6
                                        radius: 3
                                        color: Qt.rgba(1, 1, 1, 0.10)
                                    }
                                    // Progress bar
                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.verticalCenter: parent.verticalCenter
                                        height: 6
                                        width: Math.max(0, Math.min(parent.width, parent.width * root.brightRatio))
                                        radius: 3
                                        color: Theme.accentLit
                                        Behavior on width {
                                            enabled: !brightArea.pressed
                                            NumberAnimation { duration: 100 }
                                        }
                                    }
                                    // Circular Thumb
                                    Rectangle {
                                        width: 12; height: 12; radius: 6
                                        anchors.verticalCenter: parent.verticalCenter
                                        x: Math.max(0, Math.min(parent.width - width, (parent.width * root.brightRatio) - (width / 2)))
                                        color: Theme.accentLit
                                        border.width: 1.5
                                        border.color: Theme.bg
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
                            }
                        }
                    }
                }

                // VIEW 1B: LINKED SUB-MENU (Wi-Fi Networks Picker)
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 6
                    visible: root.activeSubMenu === "wifi"

                    // Sub-menu Header
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 26
                        spacing: 6

                        Rectangle {
                            width: 24; height: 24; radius: 12
                            color: wifiBackMA.containsMouse ? Theme.bgHover : Qt.rgba(1, 1, 1, 0.06)
                            border.width: 1
                            border.color: wifiBackMA.containsMouse ? Theme.accent : Theme.outline

                            Text {
                                anchors.centerIn: parent
                                text: "arrow_back"
                                font.family: Theme.fontIcon
                                font.pixelSize: 13
                                color: wifiBackMA.containsMouse ? Theme.accent : Theme.fgDim
                            }
                            MouseArea {
                                id: wifiBackMA
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.activeSubMenu = ""
                            }
                        }

                        Text {
                            text: "Wi-Fi Networks"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: Theme.fontPx(9)
                            font.weight: Font.Bold
                            color: Theme.fg
                        }

                        Item { Layout.fillWidth: true }

                        // Rescan Button
                        Rectangle {
                            width: 24; height: 24; radius: 12
                            color: wifiRescanMA.containsMouse ? Theme.bgHover : "transparent"
                            Text {
                                anchors.centerIn: parent
                                text: "refresh"
                                font.family: Theme.fontIcon
                                font.pixelSize: 14
                                color: root.wifiScanning ? Theme.accent : (wifiRescanMA.containsMouse ? Theme.fg : Theme.fgDim)
                                rotation: root.wifiScanning ? 360 : 0
                                Behavior on rotation { NumberAnimation { duration: 800; loops: Animation.Infinite } }
                            }
                            MouseArea {
                                id: wifiRescanMA
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.scanWifi()
                            }
                        }

                        // Close Button
                        Rectangle {
                            width: 20; height: 20; radius: 10
                            color: wifiSubCloseMA.containsMouse ? Theme.bgHover : "transparent"
                            Text {
                                anchors.centerIn: parent
                                text: "close"
                                font.family: Theme.fontIcon
                                font.pixelSize: 12
                                color: wifiSubCloseMA.containsMouse ? Theme.fg : Theme.fgFaint
                            }
                            MouseArea {
                                id: wifiSubCloseMA
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.activeSubMenu = ""
                            }
                        }
                    }

                    // Password prompt card
                    Rectangle {
                        visible: root.showWifiPasswordPrompt
                        Layout.fillWidth: true
                        Layout.preferredHeight: 38
                        radius: 8
                        color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.12)
                        border.width: 1
                        border.color: Theme.accent

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 4
                            spacing: 4

                            TextInput {
                                id: wifiPwField
                                Layout.fillWidth: true
                                echoMode: TextInput.Password
                                text: root.wifiPassword
                                onTextChanged: root.wifiPassword = text
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: Theme.fontPx(8)
                                color: Theme.fg
                                clip: true
                                Text {
                                    visible: !parent.text
                                    text: "Enter password..."
                                    color: Theme.fgFaint
                                    font: parent.font
                                }
                            }

                            Rectangle {
                                width: 48; height: 24; radius: 6
                                color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.22)
                                border.width: 1
                                border.color: Theme.accentLit
                                Text {
                                    anchors.centerIn: parent
                                    text: "Connect"
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: Theme.fontPx(7.5)
                                    font.weight: Font.Bold
                                    color: Theme.accentLit
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.connectWifi(root.wifiConnectSsid, root.wifiPassword)
                                }
                            }
                        }
                    }

                    // Networks List
                    Flickable {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentWidth: width
                        contentHeight: wifiNetCol.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        ColumnLayout {
                            id: wifiNetCol
                            width: parent.width
                            spacing: 4

                            Repeater {
                                model: root.wifiNetworks
                                delegate: Rectangle {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 32
                                    radius: 7
                                    color: modelData.inUse
                                           ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18)
                                           : (netRowMA.containsMouse ? Theme.bgHover : Qt.rgba(1, 1, 1, 0.04))
                                    border.width: 1
                                    border.color: modelData.inUse ? Theme.accent : Theme.outline

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 6
                                        spacing: 6

                                        Text {
                                            text: modelData.signal > 70 ? "wifi" : (modelData.signal > 40 ? "network_wifi_3_bar" : "network_wifi_2_bar")
                                            font.family: Theme.fontIcon
                                            font.pixelSize: 13
                                            color: modelData.inUse ? Theme.accentLit : Theme.fgDim
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.ssid || ""
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: Theme.fontPx(8)
                                            font.weight: modelData.inUse ? Font.Bold : Font.Normal
                                            color: modelData.inUse ? Theme.accentLit : Theme.fg
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            visible: modelData.isSecure
                                            text: "lock"
                                            font.family: Theme.fontIcon
                                            font.pixelSize: 11
                                            color: Theme.fgFaint
                                        }

                                        Rectangle {
                                            width: modelData.inUse ? 54 : 46
                                            height: 20
                                            radius: 5
                                            color: modelData.inUse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.25)
                                                                   : (netRowMA.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.20) : "transparent")
                                            border.width: 1
                                            border.color: (modelData.inUse || netRowMA.containsMouse) ? Theme.accentLit : Theme.outline

                                            Text {
                                                anchors.centerIn: parent
                                                text: modelData.inUse ? "Active" : "Connect"
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: Theme.fontPx(6.8)
                                                font.weight: Font.Bold
                                                color: (modelData.inUse || netRowMA.containsMouse) ? Theme.accentLit : Theme.fgDim
                                            }
                                        }
                                    }

                                    MouseArea {
                                        id: netRowMA
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (modelData.inUse) return
                                            if (modelData.isSecure) {
                                                root.wifiConnectSsid = modelData.ssid
                                                root.showWifiPasswordPrompt = true
                                            } else {
                                                root.connectWifi(modelData.ssid, "")
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // VIEW 1C: LINKED SUB-MENU (Bluetooth Devices Picker)
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 6
                    visible: root.activeSubMenu === "bluetooth"

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 26
                        spacing: 6

                        Rectangle {
                            width: 24; height: 24; radius: 12
                            color: btBackMA.containsMouse ? Theme.bgHover : Qt.rgba(1, 1, 1, 0.06)
                            border.width: 1
                            border.color: btBackMA.containsMouse ? Theme.accent : Theme.outline

                            Text {
                                anchors.centerIn: parent
                                text: "arrow_back"
                                font.family: Theme.fontIcon
                                font.pixelSize: 13
                                color: btBackMA.containsMouse ? Theme.accent : Theme.fgDim
                            }
                            MouseArea {
                                id: btBackMA
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.activeSubMenu = ""
                            }
                        }

                        Text {
                            text: "Bluetooth Devices"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: Theme.fontPx(9)
                            font.weight: Font.Bold
                            color: Theme.fg
                        }

                        Item { Layout.fillWidth: true }

                        Rectangle {
                            width: 20; height: 20; radius: 10
                            color: btSubCloseMA.containsMouse ? Theme.bgHover : "transparent"
                            Text {
                                anchors.centerIn: parent
                                text: "close"
                                font.family: Theme.fontIcon
                                font.pixelSize: 12
                                color: btSubCloseMA.containsMouse ? Theme.fg : Theme.fgFaint
                            }
                            MouseArea {
                                id: btSubCloseMA
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.activeSubMenu = ""
                            }
                        }
                    }

                    Flickable {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        contentWidth: width
                        contentHeight: btDevCol.implicitHeight
                        clip: true

                        ColumnLayout {
                            id: btDevCol
                            width: parent.width
                            spacing: 4

                            Text {
                                visible: root.btDevices.length === 0
                                text: root.btStatus || "No Bluetooth devices available"
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: Theme.fontPx(8)
                                color: Theme.fgFaint
                                Layout.alignment: Qt.AlignHCenter
                            }

                            Repeater {
                                model: root.btDevices
                                delegate: Rectangle {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 32
                                    radius: 7
                                    color: Qt.rgba(1, 1, 1, 0.04)
                                    border.width: 1
                                    border.color: Theme.outline

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 6
                                        spacing: 6

                                        Text {
                                            text: "bluetooth"
                                            font.family: Theme.fontIcon
                                            font.pixelSize: 13
                                            color: Theme.accentLit
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.name || modelData.mac
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: Theme.fontPx(8)
                                            color: Theme.fg
                                            elide: Text.ElideRight
                                        }

                                        Rectangle {
                                            width: 48; height: 20; radius: 5
                                            color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.22)
                                            border.width: 1
                                            border.color: Theme.accentLit
                                            Text {
                                                anchors.centerIn: parent
                                                text: "Pair"
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: Theme.fontPx(7)
                                                font.weight: Font.Bold
                                                color: Theme.accentLit
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: Quickshell.execDetached(["sh", "-c", "bluetoothctl connect " + modelData.mac])
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
            /* 2. MIDDLE COLUMN: MEDIA PLAYER & WEATHER (~276px)        */
            /* ========================================================= */
            ColumnLayout {
                Layout.preferredWidth: 276
                Layout.fillHeight: true
                spacing: 8

                // 2A. Live Header (Clock, Date & Weather Capsule)
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

                // 2B. Rich Media Player Card
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
                                    smooth: true
                                    visible: status === Image.Ready && root.hasMusicTrack
                                }

                                Text {
                                    anchors.centerIn: parent
                                    visible: !artImg.visible
                                    text: "album"
                                    font.family: Theme.fontIcon
                                    font.pixelSize: 28
                                    color: root.hasMusicTrack ? Theme.accentLit : Theme.fgFaint
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
                                    color: root.hasMusicTrack ? Theme.accentLit : Theme.fgDim
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        // Progress Slider Row
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Text {
                                text: root.formatTime(root.musicPosition)
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: Theme.fontPx(7)
                                color: Theme.fgFaint
                            }

                            Item {
                                id: pTrack
                                Layout.fillWidth: true
                                Layout.preferredHeight: 12

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: parent.width
                                    height: 4
                                    radius: 2
                                    color: Qt.rgba(1, 1, 1, 0.12)
                                }

                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Math.max(0, Math.min(parent.width, parent.width * root.musicProgress))
                                    height: 4
                                    radius: 2
                                    color: Theme.accentLit
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: mouse => {
                                        if (width > 0) root.seekRatio(mouse.x / width)
                                    }
                                }
                            }

                            Text {
                                text: root.formatTime(root.musicLength)
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: Theme.fontPx(7)
                                color: Theme.fgFaint
                            }
                        }

                        // Player Transport Controls
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 12

                            // Shuffle
                            Rectangle {
                                width: 22; height: 22; radius: 11
                                color: shufMH.containsMouse ? Theme.bgHover : "transparent"
                                Text {
                                    anchors.centerIn: parent
                                    text: "shuffle"
                                    font.family: Theme.fontIcon
                                    font.pixelSize: 13
                                    color: LyricsService.shuffle ? Theme.accent : Theme.fgFaint
                                }
                                MouseArea {
                                    id: shufMH
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: LyricsService.toggleShuffle()
                                }
                            }

                            // Previous Track
                            Rectangle {
                                width: 26; height: 26; radius: 13
                                color: prevMH.containsMouse ? Theme.bgHover : Qt.rgba(1, 1, 1, 0.05)
                                Text {
                                    anchors.centerIn: parent
                                    text: "skip_previous"
                                    font.family: Theme.fontIcon
                                    font.pixelSize: 16
                                    color: prevMH.containsMouse ? Theme.accent : Theme.fg
                                }
                                MouseArea {
                                    id: prevMH
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: LyricsService.previousTrack()
                                }
                            }

                            // Play / Pause
                            Rectangle {
                                width: 34; height: 34; radius: 17
                                color: ppMH.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.28) : Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16)
                                border.width: 1
                                border.color: Theme.accentLit
                                Text {
                                    anchors.centerIn: parent
                                    text: root.isMusicPlaying ? "pause" : "play_arrow"
                                    font.family: Theme.fontIcon
                                    font.pixelSize: 18
                                    color: Theme.accentLit
                                }
                                MouseArea {
                                    id: ppMH
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: LyricsService.togglePlay()
                                }
                            }

                            // Next Track
                            Rectangle {
                                width: 26; height: 26; radius: 13
                                color: nextMH.containsMouse ? Theme.bgHover : Qt.rgba(1, 1, 1, 0.05)
                                Text {
                                    anchors.centerIn: parent
                                    text: "skip_next"
                                    font.family: Theme.fontIcon
                                    font.pixelSize: 16
                                    color: nextMH.containsMouse ? Theme.accent : Theme.fg
                                }
                                MouseArea {
                                    id: nextMH
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: LyricsService.nextTrack()
                                }
                            }

                            // Loop
                            Rectangle {
                                width: 22; height: 22; radius: 11
                                color: loopMH.containsMouse ? Theme.bgHover : "transparent"
                                Text {
                                    anchors.centerIn: parent
                                    text: LyricsService.loopStatus === "Track" ? "repeat_one" : "repeat"
                                    font.family: Theme.fontIcon
                                    font.pixelSize: 13
                                    color: LyricsService.loopStatus !== "None" ? Theme.accent : Theme.fgFaint
                                }
                                MouseArea {
                                    id: loopMH
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: LyricsService.cycleLoop()
                                }
                            }
                        }
                    }
                }
            }

            /* ========================================================= */
            /* 3. RIGHT COLUMN: TABS (AUDIO & CALENDAR) (~348px)         */
            /* ========================================================= */
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 6

                // 3A. Header Tab Bar (Audio & Calendar)
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 26
                    spacing: 6

                    // Audio Tab Pill
                    Rectangle {
                        Layout.preferredHeight: 24
                        Layout.preferredWidth: audioTabRow.implicitWidth + 18
                        radius: 12
                        color: root.centerTab === 0 ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.20)
                                                    : (audioTabHov.containsMouse ? Theme.bgHover : Qt.rgba(1, 1, 1, 0.05))
                        border.width: 1
                        border.color: root.centerTab === 0 ? Theme.accentLit : Qt.rgba(1, 1, 1, 0.08)

                        RowLayout {
                            id: audioTabRow
                            anchors.centerIn: parent
                            spacing: 5
                            Text {
                                text: "tune"
                                font.family: Theme.fontIcon
                                font.pixelSize: 13
                                color: root.centerTab === 0 ? Theme.accentLit : Theme.fgDim
                            }
                            Text {
                                text: "Audio"
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: Theme.fontPx(8.5)
                                font.weight: Font.Bold
                                color: root.centerTab === 0 ? Theme.accentLit : Theme.fg
                            }
                            Rectangle {
                                visible: root.activeAppStreams.length > 0
                                Layout.preferredHeight: 14
                                Layout.preferredWidth: strmCntTxt.implicitWidth + 6
                                radius: 7
                                color: root.centerTab === 0 ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35) : Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.20)
                                border.width: 1
                                border.color: root.centerTab === 0 ? Theme.accentLit : "transparent"
                                Text {
                                    id: strmCntTxt
                                    anchors.centerIn: parent
                                    text: String(root.activeAppStreams.length)
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: Theme.fontPx(7)
                                    font.weight: Font.Bold
                                    color: Theme.accentLit
                                }
                            }
                        }
                        MouseArea {
                            id: audioTabHov
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.centerTab = 0
                                root.refreshOutputPorts()
                            }
                        }
                    }

                    // Calendar Tab Pill
                    Rectangle {
                        Layout.preferredHeight: 24
                        Layout.preferredWidth: calTabRow.implicitWidth + 18
                        radius: 12
                        color: root.centerTab === 1 ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.20)
                                                    : (calTabHov.containsMouse ? Theme.bgHover : Qt.rgba(1, 1, 1, 0.05))
                        border.width: 1
                        border.color: root.centerTab === 1 ? Theme.accentLit : Qt.rgba(1, 1, 1, 0.08)

                        RowLayout {
                            id: calTabRow
                            anchors.centerIn: parent
                            spacing: 5
                            Text {
                                text: "calendar_month"
                                font.family: Theme.fontIcon
                                font.pixelSize: 13
                                color: root.centerTab === 1 ? Theme.accentLit : Theme.fgDim
                            }
                            Text {
                                text: "Calendar"
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: Theme.fontPx(8.5)
                                font.weight: Font.Bold
                                color: root.centerTab === 1 ? Theme.accentLit : Theme.fg
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

                    Item { Layout.fillWidth: true }
                }

                // 3B. Tab Content Card
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    // ── TAB 0 VIEW: AUDIO MIXER, INPUT & OUTPUT DEVICES ──
                    Item {
                        anchors.fill: parent
                        visible: root.centerTab === 0

                        Flickable {
                            anchors.fill: parent
                            anchors.rightMargin: 2
                            contentWidth: width
                            contentHeight: audioCol.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            ScrollBar.vertical: ScrollBar {
                                id: audioScroll
                                policy: ScrollBar.AsNeeded
                                width: 5
                                anchors.right: parent.right
                                anchors.rightMargin: 1
                                contentItem: Rectangle {
                                    implicitWidth: 4
                                    radius: 2
                                    color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.45)
                                }
                            }

                            ColumnLayout {
                                id: audioCol
                                width: parent.width - (audioScroll.visible ? 14 : 2)
                                spacing: 8

                                // SECTION 1: OUTPUT DEVICES
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: outSectionCol.implicitHeight + 14
                                    radius: 10
                                    color: Qt.rgba(Theme.bgAlt.r, Theme.bgAlt.g, Theme.bgAlt.b, 0.65)
                                    border.width: 1
                                    border.color: Theme.outline

                                    ColumnLayout {
                                        id: outSectionCol
                                        anchors.fill: parent
                                        anchors.margins: 8
                                        spacing: 6

                                        // Section Header
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 6
                                            Text {
                                                text: root.isMuted ? "volume_off" : (root.volRatio > 0.5 ? "volume_up" : (root.volRatio > 0.0 ? "volume_down" : "volume_mute"))
                                                font.family: Theme.fontIcon
                                                font.pixelSize: 14
                                                color: root.isMuted ? Theme.err : Theme.accentLit
                                            }
                                            Text {
                                                text: "Output Devices"
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: Theme.fontPx(8.5)
                                                font.weight: Font.Bold
                                                color: Theme.fg
                                            }
                                            Item { Layout.fillWidth: true }
                                            Text {
                                                text: root.isMuted ? "MUTED" : (Math.round(root.volRatio * 100) + "%")
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: Theme.fontPx(7.5)
                                                font.weight: Font.Bold
                                                color: root.isMuted ? Theme.err : Theme.accentLit
                                            }
                                        }

                                        // Master Output Slider & Mute Row
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 8

                                            Rectangle {
                                                width: 22; height: 22; radius: 11
                                                color: outMuteHov.containsMouse ? Theme.bgHover : (root.isMuted ? Qt.rgba(Theme.err.r, Theme.err.g, Theme.err.b, 0.20) : "transparent")
                                                border.width: 1
                                                border.color: root.isMuted ? Theme.err : (outMuteHov.containsMouse ? Theme.outline : "transparent")

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: root.isMuted ? "volume_off" : "volume_up"
                                                    font.family: Theme.fontIcon
                                                    font.pixelSize: 13
                                                    color: root.isMuted ? Theme.err : Theme.accentLit
                                                }
                                                MouseArea {
                                                    id: outMuteHov
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
                                                id: outVolTrack
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 16

                                                // Track background
                                                Rectangle {
                                                    anchors.left: parent.left
                                                    anchors.right: parent.right
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    height: 6
                                                    radius: 3
                                                    color: Qt.rgba(1, 1, 1, 0.10)
                                                }
                                                // Progress fill
                                                Rectangle {
                                                    anchors.left: parent.left
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    height: 6
                                                    width: Math.max(0, Math.min(parent.width, parent.width * (root.isMuted ? 0 : root.volRatio)))
                                                    radius: 3
                                                    color: root.isMuted ? Theme.fgFaint : Theme.accentLit
                                                    Behavior on width {
                                                        enabled: !outVolArea.pressed
                                                        NumberAnimation { duration: 100 }
                                                    }
                                                }
                                                // Circular Thumb
                                                Rectangle {
                                                    width: 12; height: 12; radius: 6
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    x: Math.max(0, Math.min(parent.width - width, (parent.width * (root.isMuted ? 0 : root.volRatio)) - (width / 2)))
                                                    color: root.isMuted ? Theme.fgFaint : Theme.accentLit
                                                    border.width: 1.5
                                                    border.color: Theme.bg
                                                }

                                                MouseArea {
                                                    id: outVolArea
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    function upd(mx) {
                                                        var r = Math.max(0, Math.min(1.0, mx / outVolTrack.width))
                                                        if (root.audioSink && root.audioSink.audio) {
                                                            root.audioSink.audio.volume = r
                                                            if (root.audioSink.audio.muted && r > 0) root.audioSink.audio.muted = false
                                                        }
                                                    }
                                                    onPressed: mouse => upd(mouse.x)
                                                    onPositionChanged: mouse => { if (pressed) upd(mouse.x) }
                                                }
                                                WheelHandler {
                                                    target: outVolTrack
                                                    onWheel: (event) => {
                                                        var step = event.angleDelta.y > 0 ? 0.03 : -0.03
                                                        if (root.audioSink && root.audioSink.audio) {
                                                            root.audioSink.audio.volume = Math.max(0, Math.min(1.0, root.volRatio + step))
                                                            if (root.audioSink.audio.muted && step > 0) root.audioSink.audio.muted = false
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        // Available Output Sinks
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 4
                                            visible: root.sinks.length > 0

                                            Repeater {
                                                model: root.sinks
                                                delegate: Rectangle {
                                                    required property var modelData
                                                    readonly property bool isDefault: root.defaultSink && (root.defaultSink.id === modelData.id)
                                                    Layout.fillWidth: true
                                                    Layout.preferredHeight: 24
                                                    radius: 6
                                                    color: isDefault ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16)
                                                                     : (snkMH.containsMouse ? Theme.bgHover : Qt.rgba(1, 1, 1, 0.04))
                                                    border.width: 1
                                                    border.color: isDefault ? Theme.accentLit : Qt.rgba(1, 1, 1, 0.08)

                                                    RowLayout {
                                                        anchors.fill: parent
                                                        anchors.leftMargin: 8
                                                        anchors.rightMargin: 8
                                                        spacing: 6

                                                        Text {
                                                            text: {
                                                                var n = (root.nodeName(modelData) || "").toLowerCase()
                                                                if (n.includes("headphone") || n.includes("headset") || n.includes("buds")) return "headphones"
                                                                if (n.includes("hdmi") || n.includes("displayport")) return "tv"
                                                                return "speaker"
                                                            }
                                                            font.family: Theme.fontIcon
                                                            font.pixelSize: 12
                                                            color: isDefault ? Theme.accentLit : Theme.fgDim
                                                        }

                                                        Text {
                                                            Layout.fillWidth: true
                                                            text: root.nodeName(modelData)
                                                            font.family: "JetBrainsMono Nerd Font"
                                                            font.pixelSize: Theme.fontPx(7.5)
                                                            font.weight: isDefault ? Font.Bold : Font.Normal
                                                            color: isDefault ? Theme.accentLit : Theme.fg
                                                            elide: Text.ElideRight
                                                        }

                                                        Text {
                                                            visible: isDefault
                                                            text: "check"
                                                            font.family: Theme.fontIcon
                                                            font.pixelSize: 12
                                                            color: Theme.accentLit
                                                        }
                                                    }

                                                    MouseArea {
                                                        id: snkMH
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: root.selectAudioSink(modelData)
                                                    }
                                                }
                                            }
                                        }

                                        // Ports switcher (Speakers / Headphones)
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 4
                                            visible: root.outputPorts.length > 1

                                            Repeater {
                                                model: root.outputPorts
                                                delegate: Rectangle {
                                                    required property var modelData
                                                    readonly property bool isSelected: root.activeOutputPort === modelData.name
                                                    Layout.fillWidth: true
                                                    Layout.preferredHeight: 22
                                                    radius: 6
                                                    color: isSelected ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16)
                                                                      : (pMH.containsMouse ? Theme.bgHover : Qt.rgba(1, 1, 1, 0.04))
                                                    border.width: 1
                                                    border.color: isSelected ? Theme.accentLit : Qt.rgba(1, 1, 1, 0.08)

                                                    RowLayout {
                                                        anchors.centerIn: parent
                                                        spacing: 4
                                                        Text {
                                                            text: modelData.name.includes("headphone") ? "headphones" : "speaker"
                                                            font.family: Theme.fontIcon
                                                            font.pixelSize: 11
                                                            color: isSelected ? Theme.accentLit : Theme.fgDim
                                                        }
                                                        Text {
                                                            text: modelData.desc || modelData.name
                                                            font.family: "JetBrainsMono Nerd Font"
                                                            font.pixelSize: Theme.fontPx(7.2)
                                                            font.weight: isSelected ? Font.Bold : Font.Normal
                                                            color: isSelected ? Theme.accentLit : Theme.fg
                                                        }
                                                    }
                                                    MouseArea {
                                                        id: pMH
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: root.selectOutputPort(modelData.name)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                // SECTION 2: INPUT DEVICES (MICROPHONES)
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: micSectionCol.implicitHeight + 14
                                    radius: 10
                                    color: Qt.rgba(Theme.bgAlt.r, Theme.bgAlt.g, Theme.bgAlt.b, 0.65)
                                    border.width: 1
                                    border.color: Theme.outline

                                    ColumnLayout {
                                        id: micSectionCol
                                        anchors.fill: parent
                                        anchors.margins: 8
                                        spacing: 6

                                        // Section Header
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 6
                                            Text {
                                                text: root.isMicMuted ? "mic_off" : "mic"
                                                font.family: Theme.fontIcon
                                                font.pixelSize: 14
                                                color: root.isMicMuted ? Theme.err : Theme.accentLit
                                            }
                                            Text {
                                                text: "Input Devices (Microphone)"
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: Theme.fontPx(8.5)
                                                font.weight: Font.Bold
                                                color: Theme.fg
                                            }
                                            Item { Layout.fillWidth: true }
                                            Text {
                                                text: root.isMicMuted ? "MUTED" : (Math.round(root.micVolRatio * 100) + "%")
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: Theme.fontPx(7.5)
                                                font.weight: Font.Bold
                                                color: root.isMicMuted ? Theme.err : Theme.accentLit
                                            }
                                        }

                                        // Microphone Slider & Mute Row
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 8

                                            Rectangle {
                                                width: 22; height: 22; radius: 11
                                                color: micMuteMH.containsMouse ? Theme.bgHover : (root.isMicMuted ? Qt.rgba(Theme.err.r, Theme.err.g, Theme.err.b, 0.20) : "transparent")
                                                border.width: 1
                                                border.color: root.isMicMuted ? Theme.err : (micMuteMH.containsMouse ? Theme.outline : "transparent")

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: root.isMicMuted ? "mic_off" : "mic"
                                                    font.family: Theme.fontIcon
                                                    font.pixelSize: 13
                                                    color: root.isMicMuted ? Theme.err : Theme.accentLit
                                                }
                                                MouseArea {
                                                    id: micMuteMH
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.toggleMicMute()
                                                }
                                            }

                                            Item {
                                                id: micTrack
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 16

                                                // Track background
                                                Rectangle {
                                                    anchors.left: parent.left
                                                    anchors.right: parent.right
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    height: 6
                                                    radius: 3
                                                    color: Qt.rgba(1, 1, 1, 0.10)
                                                }
                                                // Progress fill
                                                Rectangle {
                                                    anchors.left: parent.left
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    height: 6
                                                    width: Math.max(0, Math.min(parent.width, parent.width * (root.isMicMuted ? 0 : root.micVolRatio)))
                                                    radius: 3
                                                    color: root.isMicMuted ? Theme.fgFaint : Theme.accentLit
                                                    Behavior on width {
                                                        enabled: !micArea.pressed
                                                        NumberAnimation { duration: 100 }
                                                    }
                                                }
                                                // Circular Thumb
                                                Rectangle {
                                                    width: 12; height: 12; radius: 6
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    x: Math.max(0, Math.min(parent.width - width, (parent.width * (root.isMicMuted ? 0 : root.micVolRatio)) - (width / 2)))
                                                    color: root.isMicMuted ? Theme.fgFaint : Theme.accentLit
                                                    border.width: 1.5
                                                    border.color: Theme.bg
                                                }

                                                MouseArea {
                                                    id: micArea
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    function upd(mx) {
                                                        var r = Math.max(0, Math.min(1.0, mx / micTrack.width))
                                                        root.setMicVolume(r)
                                                    }
                                                    onPressed: mouse => upd(mouse.x)
                                                    onPositionChanged: mouse => { if (pressed) upd(mouse.x) }
                                                }
                                                WheelHandler {
                                                    target: micTrack
                                                    onWheel: (event) => {
                                                        var step = event.angleDelta.y > 0 ? 0.03 : -0.03
                                                        root.setMicVolume(root.micVolRatio + step)
                                                    }
                                                }
                                            }
                                        }

                                        // Available Microphones (Sources)
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 4
                                            visible: root.sources.length > 0

                                            Repeater {
                                                model: root.sources
                                                delegate: Rectangle {
                                                    required property var modelData
                                                    readonly property bool isDefault: root.defaultSource && (root.defaultSource.id === modelData.id)
                                                    Layout.fillWidth: true
                                                    Layout.preferredHeight: 24
                                                    radius: 6
                                                    color: isDefault ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16)
                                                                     : (srcMH.containsMouse ? Theme.bgHover : Qt.rgba(1, 1, 1, 0.04))
                                                    border.width: 1
                                                    border.color: isDefault ? Theme.accentLit : Qt.rgba(1, 1, 1, 0.08)

                                                    RowLayout {
                                                        anchors.fill: parent
                                                        anchors.leftMargin: 8
                                                        anchors.rightMargin: 8
                                                        spacing: 6

                                                        Text {
                                                            text: "mic"
                                                            font.family: Theme.fontIcon
                                                            font.pixelSize: 12
                                                            color: isDefault ? Theme.accentLit : Theme.fgDim
                                                        }

                                                        Text {
                                                            Layout.fillWidth: true
                                                            text: root.nodeName(modelData)
                                                            font.family: "JetBrainsMono Nerd Font"
                                                            font.pixelSize: Theme.fontPx(7.5)
                                                            font.weight: isDefault ? Font.Bold : Font.Normal
                                                            color: isDefault ? Theme.accentLit : Theme.fg
                                                            elide: Text.ElideRight
                                                        }

                                                        Text {
                                                            visible: isDefault
                                                            text: "check"
                                                            font.family: Theme.fontIcon
                                                            font.pixelSize: 12
                                                            color: Theme.accentLit
                                                        }
                                                    }

                                                    MouseArea {
                                                        id: srcMH
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: root.selectAudioSource(modelData)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                // SECTION 3: APPLICATION AUDIO STREAMS
                                Rectangle {
                                    visible: root.activeAppStreams.length > 0
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: appStreamsCol.implicitHeight + 12
                                    radius: 10
                                    color: Qt.rgba(Theme.bgAlt.r, Theme.bgAlt.g, Theme.bgAlt.b, 0.65)
                                    border.width: 1
                                    border.color: Theme.outline

                                    ColumnLayout {
                                        id: appStreamsCol
                                        anchors.fill: parent
                                        anchors.margins: 8
                                        spacing: 6

                                        Text {
                                            text: "Application Volumes"
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: Theme.fontPx(8)
                                            font.weight: Font.Bold
                                            color: Theme.fg
                                        }

                                        Repeater {
                                            model: root.activeAppStreams
                                            delegate: RowLayout {
                                                required property var modelData
                                                Layout.fillWidth: true
                                                spacing: 6

                                                readonly property real streamVol: (modelData && modelData.audio) ? Math.max(0, Math.min(1.0, modelData.audio.volume)) : 1.0
                                                readonly property bool streamMuted: (modelData && modelData.audio) ? modelData.audio.muted : false

                                                Text {
                                                    Layout.preferredWidth: 80
                                                    text: root.nodeName(modelData)
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: Theme.fontPx(7.5)
                                                    color: streamMuted ? Theme.fgDim : Theme.fg
                                                    elide: Text.ElideRight
                                                }

                                                Item {
                                                    id: strmTrack
                                                    Layout.fillWidth: true
                                                    Layout.preferredHeight: 14

                                                    // Track background
                                                    Rectangle {
                                                        anchors.left: parent.left
                                                        anchors.right: parent.right
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        height: 5
                                                        radius: 2.5
                                                        color: Qt.rgba(1, 1, 1, 0.10)
                                                    }
                                                    // Progress fill
                                                    Rectangle {
                                                        anchors.left: parent.left
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        height: 5
                                                        width: Math.max(0, Math.min(parent.width, parent.width * (streamMuted ? 0 : streamVol)))
                                                        radius: 2.5
                                                        color: streamMuted ? Theme.fgFaint : Theme.accentLit
                                                    }
                                                    // Mini Thumb
                                                    Rectangle {
                                                        width: 10; height: 10; radius: 5
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        x: Math.max(0, Math.min(parent.width - width, (parent.width * (streamMuted ? 0 : streamVol)) - (width / 2)))
                                                        color: streamMuted ? Theme.fgFaint : Theme.accentLit
                                                        border.width: 1
                                                        border.color: Theme.bg
                                                    }

                                                    MouseArea {
                                                        anchors.fill: parent
                                                        cursorShape: Qt.PointingHandCursor
                                                        function upd(mx) {
                                                            var r = Math.max(0, Math.min(1.0, mx / strmTrack.width))
                                                            if (modelData && modelData.audio) {
                                                                modelData.audio.volume = r
                                                                if (modelData.audio.muted && r > 0) modelData.audio.muted = false
                                                            }
                                                        }
                                                        onPressed: mouse => upd(mouse.x)
                                                        onPositionChanged: mouse => { if (pressed) upd(mouse.x) }
                                                    }
                                                }

                                                Text {
                                                    Layout.preferredWidth: 26
                                                    text: Math.round((streamMuted ? 0 : streamVol) * 100) + "%"
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: Theme.fontPx(7)
                                                    color: Theme.fgDim
                                                    horizontalAlignment: Text.AlignRight
                                                }
                                            }
                                        }
                                    }
                                }

                                // SECTION 4: VIRTUAL AUDIO DEVICES PERSISTENT TOGGLE
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 32
                                    radius: 10
                                    color: root.showVirtualDevices ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14) : Qt.rgba(Theme.bgAlt.r, Theme.bgAlt.g, Theme.bgAlt.b, 0.65)
                                    border.width: 1
                                    border.color: root.showVirtualDevices ? Theme.accentLit : Theme.outline

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: 8
                                        spacing: 8

                                        Text {
                                            text: "graphic_eq"
                                            font.family: Theme.fontIcon
                                            font.pixelSize: 14
                                            color: root.showVirtualDevices ? Theme.accentLit : Theme.fgDim
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 0
                                            Text {
                                                text: "Virtual Audio Devices"
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: Theme.fontPx(8)
                                                font.weight: Font.Bold
                                                color: root.showVirtualDevices ? Theme.accentLit : Theme.fgDim
                                            }
                                            Text {
                                                text: "EasyEffects & software sinks (persisted)"
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: Theme.fontPx(6.8)
                                                color: Theme.fgFaint
                                            }
                                        }

                                        Rectangle {
                                            Layout.preferredWidth: 32
                                            Layout.preferredHeight: 18
                                            radius: 9
                                            color: root.showVirtualDevices ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35) : Qt.rgba(1, 1, 1, 0.15)
                                            border.width: 1
                                            border.color: root.showVirtualDevices ? Theme.accentLit : Qt.rgba(1, 1, 1, 0.10)

                                            Rectangle {
                                                width: 12; height: 12; radius: 6
                                                anchors.verticalCenter: parent.verticalCenter
                                                x: root.showVirtualDevices ? parent.width - width - 3 : 3
                                                color: root.showVirtualDevices ? Theme.accentLit : (Theme.isDark ? "#888888" : "#aaaaaa")
                                                Behavior on x { NumberAnimation { duration: 150 } }
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
                            }
                        }
                    }

                    // ── TAB 1 VIEW: CALENDAR ──
                    Item {
                        anchors.fill: parent
                        visible: root.centerTab === 1

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 4

                            // Month Navigation Header
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 22

                                Rectangle {
                                    width: 22; height: 22; radius: 11
                                    color: calPrevHov.containsMouse ? Theme.bgHover : "transparent"
                                    Text {
                                        anchors.centerIn: parent
                                        text: "chevron_left"
                                        font.family: Theme.fontIcon
                                        font.pixelSize: 14
                                        color: Theme.fg
                                    }
                                    MouseArea {
                                        id: calPrevHov
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.prevMonth()
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: root.monthNames[root.calMonth] + " " + root.calYear
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: Theme.fontPx(9)
                                    font.weight: Font.Bold
                                    color: Theme.fg
                                    horizontalAlignment: Text.AlignHCenter
                                }

                                Rectangle {
                                    width: 22; height: 22; radius: 11
                                    color: calNextHov.containsMouse ? Theme.bgHover : "transparent"
                                    Text {
                                        anchors.centerIn: parent
                                        text: "chevron_right"
                                        font.family: Theme.fontIcon
                                        font.pixelSize: 14
                                        color: Theme.fg
                                    }
                                    MouseArea {
                                        id: calNextHov
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.nextMonth()
                                    }
                                }
                            }

                            // Day of Week Headers
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                Repeater {
                                    model: root.weekdayShortNames
                                    delegate: Text {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        text: modelData
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: Theme.fontPx(7)
                                        font.weight: Font.Bold
                                        color: Theme.accentLit
                                        horizontalAlignment: Text.AlignHCenter
                                    }
                                }
                            }

                            // 7x6 Days Grid
                            Grid {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                columns: 7
                                rowSpacing: 2
                                columnSpacing: 2

                                Repeater {
                                    model: 42
                                    delegate: Item {
                                        required property int index
                                        width: (parent.width - 12) / 7
                                        height: 20

                                        readonly property int firstDay: root.firstDayWeekday(root.calYear, root.calMonth)
                                        readonly property int totalDays: root.daysInMonth(root.calYear, root.calMonth)
                                        readonly property int dayNum: index - firstDay + 1
                                        readonly property bool isCurrentMonth: dayNum >= 1 && dayNum <= totalDays
                                        readonly property bool isToday: isCurrentMonth && (dayNum === root.currentDate.getDate()) && (root.calMonth === root.currentDate.getMonth()) && (root.calYear === root.currentDate.getFullYear())
                                        readonly property bool isSelected: isCurrentMonth && (dayNum === root.selectedDay)

                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: 18; height: 18
                                            radius: 9
                                            color: isToday ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.28) : (isSelected ? Theme.bgHover : "transparent")
                                            border.width: (isToday || isSelected) ? 1 : 0
                                            border.color: isToday ? Theme.accentLit : (isSelected ? Theme.outline : "transparent")

                                            Text {
                                                anchors.centerIn: parent
                                                text: isCurrentMonth ? String(dayNum) : ""
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: Theme.fontPx(7)
                                                font.weight: isToday ? Font.Bold : Font.Normal
                                                color: isToday ? Theme.accentLit : (isCurrentMonth ? Theme.fg : "transparent")
                                            }
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            enabled: isCurrentMonth
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.selectedDay = dayNum
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
