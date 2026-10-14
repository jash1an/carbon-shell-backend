import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import "../components"
import "../Singletons"

/**
 * Carbon Control Center (Quick Settings)
 *
 * Streamlined, clean, and intuitive control panel:
 *   - Header: Live clock/date, Screen recorder, Screenshot, Settings, Lock, and Power shortcuts
 *   - Tab Bar: Controls, Tasks, Timer, Weather
 *   - Quick Toggles: Wi-Fi (power + network picker), Bluetooth (power + device picker), Night Light, DND
 *   - Sliders: Volume (mute icon, draggable track, live percentage) & Brightness (draggable track, live percentage)
 *   - Media Player: Compact now-playing card with album art, title, artist, seekable progress, and playback controls
 *   - Notifications: Scrollable notifications center with individual dismiss and clear-all actions
 *   - Detail Sheets: WifiPopup & BtPopup overlays
 */
Item {
    id: root

    property bool open: false
    property bool hovered: false
    property int mode: 0            // 0: controls, 1: todo, 2: timer
    property string corner: "bottom_right"
    property real shellOpacity: Theme.shellOpacity
    readonly property string home: Quickshell.env("HOME") || ""

    /* ── Notifications Support & Navigation ── */
    property var server: null
    readonly property var notifs: root.server && root.server.trackedNotifications ? root.server.trackedNotifications : null
    readonly property int notifCount: root.notifs && root.notifs.values ? root.notifs.values.length : 0
    property bool showingNotifs: false
    property int selectedNotifIndex: -1
    property int expandedNotifId: -1

    onShowingNotifsChanged: {
        if (root.showingNotifs) {
            root.scrollToNotifs()
        }
    }
    onModeChanged: {
        root.selectedNotifIndex = -1
        root.expandedNotifId = -1
    }

    function scrollToNotifs() {
        if (typeof pane0Flick !== 'undefined' && pane0Flick) {
            pane0Flick.contentY = Math.min(pane0Flick.contentHeight - pane0Flick.height, 220)
        }
    }

    function selectNextNotif() {
        if (root.notifCount > 0) {
            root.selectedNotifIndex = Math.min(root.notifCount - 1, root.selectedNotifIndex + 1)
            if (typeof pane0Flick !== 'undefined' && pane0Flick) {
                pane0Flick.contentY = Math.min(pane0Flick.contentHeight - pane0Flick.height, Math.max(pane0Flick.contentY, 200 + root.selectedNotifIndex * 54))
            }
        }
    }

    function selectPrevNotif() {
        if (root.selectedNotifIndex > 0) {
            root.selectedNotifIndex = root.selectedNotifIndex - 1
            if (typeof pane0Flick !== 'undefined' && pane0Flick) {
                pane0Flick.contentY = Math.max(0, 200 + (root.selectedNotifIndex - 1) * 54)
            }
        } else {
            root.selectedNotifIndex = -1
            if (typeof pane0Flick !== 'undefined' && pane0Flick) {
                pane0Flick.contentY = 0
            }
        }
    }

    function dismissAllNotifs() {
        if (!root.notifs) return
        const list = root.notifs.values ? [...root.notifs.values] : []
        for (let i = 0; i < list.length; i++) {
            if (list[i] && typeof list[i].dismiss === "function") {
                list[i].dismiss()
            }
        }
        root.selectedNotifIndex = -1
        root.expandedNotifId = -1
    }

    function activateSelectedNotif() {
        if (!root.notifs || root.notifCount <= 0) return
        const list = root.notifs.values ? [...root.notifs.values] : []
        if (root.selectedNotifIndex < 0 || root.selectedNotifIndex >= list.length) return
        const n = list[root.selectedNotifIndex]
        if (!n) return

        if (root.expandedNotifId === n.id) {
            root.expandedNotifId = -1
        } else {
            root.expandedNotifId = n.id
        }

        if (n.actions && n.actions.length > 0) {
            let def = null
            for (let i = 0; i < n.actions.length; i++) {
                if (n.actions[i].id === "default" || n.actions[i].identifier === "default") {
                    def = n.actions[i]
                    break
                }
            }
            if (!def && n.actions.length === 1) def = n.actions[0]
            if (def && typeof def.invoke === "function") {
                def.invoke()
            }
        } else if (typeof n.invoke === "function") {
            n.invoke()
        }
    }

    /* ── Panel Dimensions ── */
    readonly property int paneW: 336
    readonly property int paneH: 446
    readonly property int cardW: root.paneW + 24
    readonly property int cardH: 92 + root.paneH
    implicitWidth: root.cardW
    implicitHeight: root.cardH
    width: root.implicitWidth
    height: root.implicitHeight

    readonly property var cardItem: card
    readonly property bool animatingOut: !root.open && card.opacity > 0.001

    function paneX(idx) { return (idx - root.mode) * root.paneW }

    /* ============================ MPRIS Media ============================ */
    readonly property var players: Mpris.players.values !== undefined
        ? Mpris.players.values : Mpris.players
    property var activePlayer: null
    property string trackTitle: ""
    property string trackArtist: ""
    property string artUrl: ""
    property bool playing: false
    property bool canPrev: false
    property bool canNext: false
    property bool posSupported: false
    property double posUs: 0
    property double lenUs: 0
    property real progRatio: root.lenUs > 0
        ? Math.max(0, Math.min(1, root.posUs / root.lenUs)) : 0

    function resolveActivePlayer() {
        if (!root.players || root.players.length === 0)
            return null
        for (let i = 0; i < root.players.length; i++)
            if (root.players[i].playbackState === MprisPlaybackState.Playing)
                return root.players[i]
        for (let i = 0; i < root.players.length; i++)
            if (root.players[i].playbackState === MprisPlaybackState.Paused
                && (root.players[i].trackTitle || "").length > 0)
                return root.players[i]
        return root.players[0]
    }

    function syncPlayer() {
        const p = root.resolveActivePlayer()
        root.activePlayer = p
        root.trackTitle = p ? String(p.trackTitle || "") : ""
        root.trackArtist = (p && p.metadata && p.metadata["xesam:artist"]) ? String(p.metadata["xesam:artist"]) : ""
        root.artUrl = p && p.metadata ? String(p.metadata["mpris:artUrl"] || "") : ""
        root.playing = !!p && p.playbackState === MprisPlaybackState.Playing
        root.canPrev = !!p && p.canGoPrevious
        root.canNext = !!p && p.canGoNext
        root.posSupported = !!p && p.positionSupported
        root.posUs = p ? p.position : 0
        root.lenUs = p ? p.length : 0
    }

    Timer {
        id: progTick
        interval: 200
        repeat: true
        running: root.open && root.playing && root.lenUs > 0
        onTriggered: {
            if (root.posUs + 200000 <= root.lenUs) root.posUs += 200000
        }
    }

    Timer {
        id: playerProbe
        interval: 800
        repeat: true
        running: root.open
        onTriggered: root.syncPlayer()
    }

    function togglePlayPause() {
        if (root.activePlayer) root.activePlayer.togglePlaying()
    }

    function seekToRatio(r) {
        if (root.lenUs <= 0) return
        const clamped = Math.max(0, Math.min(1, r))
        root.posUs = clamped * root.lenUs
        const targetSec = root.posUs / 1000000.0
        try {
            if (root.activePlayer) root.activePlayer.position = root.posUs
        } catch (e) {}
        Quickshell.execDetached(["playerctl", "position", targetSec.toFixed(2)])
        if (root.activePlayer && root.activePlayer.positionSupported) {
            root.activePlayer.positionChanged()
        }
    }

    /* ============================ Audio (Pipewire) ============================ */
    readonly property var audioSink: Pipewire.defaultAudioSink
    readonly property real volRatio: (audioSink && audioSink.audio) ? Math.max(0, Math.min(1.0, audioSink.audio.volume)) : 0.0
    readonly property bool isMuted: (audioSink && audioSink.audio) ? audioSink.audio.muted : false

    /* ============================ Display Brightness ============================ */
    property real brightRatio: 0.5
    property real brightMax: 1
    property real lastBrightWrite: 0

    Process {
        id: brightProbe
        command: ["sh", "-c", 'echo "a b c $(brightnessctl --class backlight get) $(brightnessctl --class backlight max)"']
        stdout: SplitParser {
            onRead: data => {
                const tokens = data.trim().split(/\s+/)
                if (tokens.length < 2) return
                const cur = parseFloat(tokens[tokens.length - 2])
                const mx = parseFloat(tokens[tokens.length - 1])
                if (isNaN(cur) || isNaN(mx) || mx <= 0) return
                root.brightMax = mx
                root.brightRatio = Math.max(0.05, Math.min(1.0, cur / mx))
            }
        }
    }

    function refreshBrightness() {
        if (!brightProbe.running) brightProbe.running = true
    }

    function setBrightness(v) {
        root.brightRatio = Math.max(0.05, Math.min(1.0, v))
        root.lastBrightWrite = Date.now()
        Quickshell.execDetached(["brightnessctl", "--class", "backlight", "s",
            String(Math.round(root.brightRatio * root.brightMax)), "--quiet"])
    }

    Timer {
        interval: 3000
        repeat: true
        running: root.open
        onTriggered: {
            if (Date.now() - root.lastBrightWrite > 1500)
                root.refreshBrightness()
        }
    }

    /* ============================ Quick Toggles ============================ */
    property bool btOn: false
    property bool wifiOn: true
    property bool nightAvailable: true
    property bool nightOn: false
    property bool dndOn: false
    property string wifiName: ""
    property string btName: ""
    property bool wifiPopupOpen: false
    property bool btPopupOpen: false

    Timer {
        id: settleTimer
        interval: 900
        onTriggered: root.refreshStates()
    }

    function refreshStates() {
        if (!root.open) return
        if (!btProbe.running) btProbe.running = true
        if (!wifiProbe.running) wifiProbe.running = true
        if (!nightProbe.running) nightProbe.running = true
        if (!dndProbe.running) dndProbe.running = true
        if (!btNameProbe.running) btNameProbe.running = true
        if (!wifiNameProbe.running) wifiNameProbe.running = true
        if (!recProbe.running) recProbe.running = true
        root.refreshBrightness()
    }

    /* Bluetooth */
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
        Quickshell.execDetached(["sh", "-c",
            "bluetoothctl power " + (root.btOn ? "on" : "off") + " >/dev/null 2>&1"])
        settleTimer.restart()
    }

    /* Wi-Fi */
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
        Quickshell.execDetached(["sh", "-c",
            "nmcli radio wifi " + (root.wifiOn ? "on" : "off") + " >/dev/null 2>&1"])
        settleTimer.restart()
    }

    /* Night light */
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

    /* Do Not Disturb */
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
        Quickshell.execDetached(["sh", "-c",
            root.dndOn ? "touch /tmp/carbon-dnd.on" : "rm -f /tmp/carbon-dnd.on"])
        settleTimer.restart()
    }

    /* Screen Recorder */
    property bool recWorking: false
    property int recElapsed: 0
    property string recDone: ""
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
        id: recClock
        interval: 1000
        repeat: true
        running: root.recWorking
        onTriggered: root.recElapsed++
    }

    Timer {
        interval: 2000
        repeat: true
        running: root.open
        onTriggered: {
            if (!recProbe.running) recProbe.running = true
        }
    }

    /* Clock & Date Header */
    property string timeStr: Qt.formatTime(new Date(), "hh:mm")
    property string dateStr: Qt.formatDate(new Date(), "ddd, MMM d")

    Timer {
        interval: 1000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            const now = new Date()
            root.timeStr = Qt.formatTime(now, "hh:mm")
            root.dateStr = Qt.formatDate(now, "ddd, MMM d")
        }
    }

    onOpenChanged: {
        if (root.open) {
            root.syncPlayer()
            root.refreshStates()
            if (typeof pane0Flick !== 'undefined' && pane0Flick) pane0Flick.contentY = 0
            root.selectedNotifIndex = -1
        } else {
            root.wifiPopupOpen = false
            root.btPopupOpen = false
            root.showingNotifs = false
            root.expandedNotifId = -1
        }
    }

    Component.onCompleted: {
        root.refreshStates()
    }

    /* ============================ Visual Card Container ============================ */
    Item {
        id: card
        width: root.cardW
        height: root.cardH
        clip: true

        property color fillColor: Qt.rgba(Theme.m3surfaceContainer.r, Theme.m3surfaceContainer.g, Theme.m3surfaceContainer.b, root.shellOpacity)
        property color strokeColor: root.open
            ? Qt.rgba(Theme.accentLit.r, Theme.accentLit.g, Theme.accentLit.b, 0.40)
            : Theme.outline
        Behavior on fillColor { ColorAnimation { duration: 250 } }
        Behavior on strokeColor { ColorAnimation { duration: 250 } }

        Shape {
            id: cardShape
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            asynchronous: false
            layer.enabled: true
            layer.smooth: true

            ShapePath {
                strokeWidth: 0
                strokeColor: "transparent"
                fillColor: card.fillColor
                PathSvg {
                    path: {
                        const w = card.width
                        const h = card.height
                        const r = 24
                        if (root.corner === "bottom_right") {
                            let p = `M 0 ${r} `
                            p += `A ${r} ${r} 0 0 1 ${r} 0 `
                            p += `L ${w} 0 `
                            p += `L ${w} ${h} `
                            p += `L 0 ${h} `
                            p += `Z`
                            return p
                        } else if (root.corner === "top_left") {
                            let p = `M 0 0 `
                            p += `L ${w} 0 `
                            p += `L ${w} ${h - r} `
                            p += `A ${r} ${r} 0 0 1 ${w - r} ${h} `
                            p += `L 0 ${h} `
                            p += `Z`
                            return p
                        } else {
                            let p = `M 0 ${r} `
                            p += `A ${r} ${r} 0 0 1 ${r} 0 `
                            p += `L ${w - r} 0 `
                            p += `A ${r} ${r} 0 0 1 ${w} ${r} `
                            p += `L ${w} ${h - r} `
                            p += `A ${r} ${r} 0 0 1 ${w - r} ${h} `
                            p += `L ${r} ${h} `
                            p += `A ${r} ${r} 0 0 1 0 ${h - r} `
                            p += `Z`
                            return p
                        }
                    }
                }
            }

            ShapePath {
                strokeWidth: 1.0
                strokeColor: card.strokeColor
                fillColor: "transparent"
                capStyle: ShapePath.FlatCap
                joinStyle: ShapePath.MiterJoin
                PathSvg {
                    path: {
                        const w = card.width
                        const h = card.height
                        const r = 24
                        if (root.corner === "bottom_right") {
                            let p = `M 0 ${h} `
                            p += `L 0 ${r} `
                            p += `A ${r} ${r} 0 0 1 ${r} 0 `
                            p += `L ${w} 0`
                            return p
                        } else if (root.corner === "top_left") {
                            let p = `M 0 ${h} `
                            p += `L ${w - r} ${h} `
                            p += `A ${r} ${r} 0 0 0 ${w} ${h - r} `
                            p += `L ${w} 0`
                            return p
                        } else {
                            let p = `M 0 ${r} `
                            p += `A ${r} ${r} 0 0 1 ${r} 0 `
                            p += `L ${w - r} 0 `
                            p += `A ${r} ${r} 0 0 1 ${w} ${r} `
                            p += `L ${w} ${h - r} `
                            p += `A ${r} ${r} 0 0 1 ${w - r} ${h} `
                            p += `L ${r} ${h} `
                            p += `A ${r} ${r} 0 0 1 0 ${h - r} `
                            p += `L 0 ${r}`
                            return p
                        }
                    }
                }
            }
        }

        transformOrigin: (root.corner === "top_center" || root.corner === "center") ? Item.Top :
                         (root.corner === "bottom_center" ? Item.Bottom :
                         (root.corner === "top_left" ? Item.TopLeft :
                         (root.corner === "bottom_left" ? Item.BottomLeft : Item.BottomRight)))

        x: (root.corner === "top_center" || root.corner === "center" || root.corner === "bottom_center") ? 0 :
           ((root.corner === "top_left" || root.corner === "bottom_left") ? (root.open ? 0 : -14) : (root.open ? 0 : 14))
        y: (root.corner === "top_center" || root.corner === "center") ? (root.open ? 0 : -12) :
           (root.corner === "bottom_center" ? (root.open ? 0 : 12) :
           (root.corner === "top_left" ? (root.open ? 0 : -14) : (root.open ? 0 : 14)))
        scale: root.open ? 1.0 : 0.97
        opacity: root.open ? 1.0 : 0.0

        Behavior on opacity {
            NumberAnimation {
                duration: root.open ? 140 : 85
                easing.type: root.open ? Easing.OutCubic : Easing.InQuad
            }
        }
        Behavior on x {
            NumberAnimation {
                duration: root.open ? 140 : 85
                easing.type: root.open ? Easing.OutCubic : Easing.InQuad
            }
        }
        Behavior on y {
            NumberAnimation {
                duration: root.open ? 140 : 85
                easing.type: root.open ? Easing.OutCubic : Easing.InQuad
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: root.open ? 140 : 85
                easing.type: root.open ? Easing.OutCubic : Easing.InQuad
            }
        }

        HoverHandler {
            onHoveredChanged: root.hovered = hovered
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 6

            /* ── Header: Clock, Recorder & Action Shortcuts ── */
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 30
                spacing: 5

                // Clock & Date
                RowLayout {
                    spacing: 5
                    Text {
                        text: root.timeStr
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: Theme.fontPx(12)
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

                // Screen Recorder Button
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

                // Screenshot Button
                Rectangle {
                    width: 26
                    height: 26
                    radius: 13
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
                        onClicked: {
                            Quickshell.execDetached([root.home + "/.config/hypr/scripts/carbon-screenshot-region.sh"])
                        }
                    }
                }

                // Settings Button
                Rectangle {
                    width: 26
                    height: 26
                    radius: 13
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
                        onClicked: {
                            Quickshell.execDetached(["sh", "-c", "command -v carbon-config-editor >/dev/null && carbon-config-editor || systemsettings || true"])
                        }
                    }
                }

                // Lock Button
                Rectangle {
                    width: 26
                    height: 26
                    radius: 13
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
                        onClicked: {
                            Quickshell.execDetached([root.home + "/.config/hypr/scripts/hyprlock.sh"])
                        }
                    }
                }

                // Power Button
                Rectangle {
                    width: 26
                    height: 26
                    radius: 13
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
                        onClicked: {
                            Quickshell.execDetached(["sh", root.home + "/.config/carbon/scripts/carbon-ipc.sh", "power"])
                        }
                    }
                }
            }

            /* ── Header: Modern Slim Pill Tabs ── */
            Rectangle {
                Layout.fillWidth: true
                height: 30
                radius: 15
                color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.06)

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 3
                    spacing: 3

                    Repeater {
                        model: [
                            { glyph: "tune", label: "Controls" },
                            { glyph: "checklist", label: "Tasks" },
                            { glyph: "timer", label: "Timer" }
                        ]
                        delegate: Rectangle {
                            required property int index
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: 12
                            color: root.mode === index ? Theme.accent : (tabHov.hovered ? Theme.bgHover : "transparent")
                            Behavior on color { ColorAnimation { duration: 150 } }

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: 4
                                Text {
                                    text: modelData.glyph
                                    font.family: Theme.fontIcon
                                    font.pixelSize: 13
                                    color: root.mode === index ? (Theme.isDark ? "#101116" : "#ffffff") : Theme.fgDim
                                }
                                Text {
                                    text: modelData.label
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: Theme.fontPx(8)
                                    font.weight: root.mode === index ? Font.Bold : Font.Normal
                                    color: root.mode === index ? (Theme.isDark ? "#101116" : "#ffffff") : Theme.fgDim
                                }
                            }

                            MouseArea {
                                id: tabHov
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.mode = index
                            }
                        }
                    }
                }
            }

            /* ── Content Panes ── */
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: root.paneH
                clip: true

                /* ==== Mode 0: Controls & Notifications ==== */
                Item {
                    id: pane0
                    width: parent.width
                    height: parent.height
                    x: root.paneX(0)
                    opacity: root.mode === 0 ? 1 : 0
                    enabled: root.mode === 0
                    clip: true
                    Behavior on x {
                        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                    }
                    Behavior on opacity {
                        NumberAnimation { duration: 150; easing.type: Easing.InOutCubic }
                    }

                    Flickable {
                        id: pane0Flick
                        anchors.fill: parent
                        contentWidth: width
                        contentHeight: unifiedCol.implicitHeight + 12
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        focus: root.mode === 0

                        ScrollBar.vertical: ScrollBar {
                            policy: ScrollBar.AsNeeded
                            width: 3
                            anchors.right: pane0Flick.right
                            anchors.rightMargin: 1
                        }

                        WheelHandler {
                            target: pane0Flick
                            onWheel: (event) => {
                                var delta = event.angleDelta.y
                                var targetY = pane0Flick.contentY - (delta * 0.5)
                                var maxY = Math.max(0, pane0Flick.contentHeight - pane0Flick.height)
                                pane0Flick.contentY = Math.max(0, Math.min(maxY, targetY))
                            }
                        }

                        Keys.onDownPressed: (event) => {
                            event.accepted = true
                            root.selectNextNotif()
                        }
                        Keys.onUpPressed: (event) => {
                            event.accepted = true
                            root.selectPrevNotif()
                        }
                        Keys.onReturnPressed: (event) => {
                            event.accepted = true
                            root.activateSelectedNotif()
                        }
                        Keys.onEnterPressed: (event) => {
                            event.accepted = true
                            root.activateSelectedNotif()
                        }

                        ColumnLayout {
                            id: unifiedCol
                            width: pane0Flick.width - 4
                            spacing: 8

                            /* ── Part 1: Quick Toggles (2x2 Grid) ── */
                            GridLayout {
                                Layout.fillWidth: true
                                columns: 2
                                columnSpacing: 6
                                rowSpacing: 6

                                // Wi-Fi Toggle Pill
                                Rectangle {

                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 46
                                    radius: 14
                                    color: root.wifiOn ? Theme.accent : (wifiTileHov.containsMouse ? Theme.bgHover : Qt.rgba(Theme.bgAlt.r, Theme.bgAlt.g, Theme.bgAlt.b, 0.65))
                                    border.width: 1
                                    border.color: root.wifiOn ? Qt.rgba(Theme.accentLit.r, Theme.accentLit.g, Theme.accentLit.b, 0.60) : Theme.outline
                                    Behavior on color { ColorAnimation { duration: 150 } }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 6
                                        spacing: 6

                                        Rectangle {
                                            width: 30
                                            height: 30
                                            radius: 15
                                            color: root.wifiOn ? (Theme.isDark ? Qt.rgba(0,0,0,0.2) : Qt.rgba(1,1,1,0.3)) : Qt.rgba(1, 1, 1, 0.08)
                                            Text {
                                                anchors.centerIn: parent
                                                text: root.wifiOn ? "wifi" : "wifi_off"
                                                font.family: Theme.fontIcon
                                                font.pixelSize: 16
                                                color: root.wifiOn ? (Theme.isDark ? "#101116" : "#ffffff") : Theme.fgDim
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 1
                                            Text {
                                                Layout.fillWidth: true
                                                text: "Wi-Fi"
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: Theme.fontPx(9)
                                                font.weight: Font.Bold
                                                color: root.wifiOn ? (Theme.isDark ? "#101116" : "#ffffff") : Theme.fg
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                text: root.wifiOn ? (root.wifiName.length > 0 ? root.wifiName : "Connected") : "Off"
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: Theme.fontPx(7)
                                                color: root.wifiOn ? (Theme.isDark ? Qt.rgba(0.06, 0.07, 0.09, 0.75) : Qt.rgba(1, 1, 1, 0.85)) : Theme.fgDim
                                                elide: Text.ElideRight
                                            }
                                        }

                                        Rectangle {
                                            width: 22
                                            height: 22
                                            radius: 11
                                            color: wifiChevHov.containsMouse ? (root.wifiOn ? Qt.rgba(0,0,0,0.15) : Theme.bgHover) : "transparent"
                                            Text {
                                                anchors.centerIn: parent
                                                text: "chevron_right"
                                                font.family: Theme.fontIcon
                                                font.pixelSize: 14
                                                color: root.wifiOn ? (Theme.isDark ? "#101116" : "#ffffff") : Theme.fgDim
                                            }
                                            MouseArea {
                                                id: wifiChevHov
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    root.wifiPopupOpen = !root.wifiPopupOpen
                                                    if (root.wifiPopupOpen) root.btPopupOpen = false
                                                }
                                            }
                                        }
                                    }

                                    MouseArea {
                                        id: wifiTileHov
                                        anchors.fill: parent
                                        anchors.rightMargin: 26
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.toggleWifi()
                                    }
                                }

                                // Bluetooth Toggle Pill
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 46
                                    radius: 14
                                    color: root.btOn ? Theme.accent : (btTileHov.containsMouse ? Theme.bgHover : Qt.rgba(Theme.bgAlt.r, Theme.bgAlt.g, Theme.bgAlt.b, 0.65))
                                    border.width: 1
                                    border.color: root.btOn ? Qt.rgba(Theme.accentLit.r, Theme.accentLit.g, Theme.accentLit.b, 0.60) : Theme.outline
                                    Behavior on color { ColorAnimation { duration: 150 } }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 6
                                        spacing: 6

                                        Rectangle {
                                            width: 30
                                            height: 30
                                            radius: 15
                                            color: root.btOn ? (Theme.isDark ? Qt.rgba(0,0,0,0.2) : Qt.rgba(1,1,1,0.3)) : Qt.rgba(1, 1, 1, 0.08)
                                            Text {
                                                anchors.centerIn: parent
                                                text: root.btOn ? "bluetooth" : "bluetooth_disabled"
                                                font.family: Theme.fontIcon
                                                font.pixelSize: 16
                                                color: root.btOn ? (Theme.isDark ? "#101116" : "#ffffff") : Theme.fgDim
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 1
                                            Text {
                                                Layout.fillWidth: true
                                                text: "Bluetooth"
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: Theme.fontPx(9)
                                                font.weight: Font.Bold
                                                color: root.btOn ? (Theme.isDark ? "#101116" : "#ffffff") : Theme.fg
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                text: root.btOn ? (root.btName.length > 0 ? root.btName : "On") : "Off"
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: Theme.fontPx(7)
                                                color: root.btOn ? (Theme.isDark ? Qt.rgba(0.06, 0.07, 0.09, 0.75) : Qt.rgba(1, 1, 1, 0.85)) : Theme.fgDim
                                                elide: Text.ElideRight
                                            }
                                        }

                                        Rectangle {
                                            width: 22
                                            height: 22
                                            radius: 11
                                            color: btChevHov.containsMouse ? (root.btOn ? Qt.rgba(0,0,0,0.15) : Theme.bgHover) : "transparent"
                                            Text {
                                                anchors.centerIn: parent
                                                text: "chevron_right"
                                                font.family: Theme.fontIcon
                                                font.pixelSize: 14
                                                color: root.btOn ? (Theme.isDark ? "#101116" : "#ffffff") : Theme.fgDim
                                            }
                                            MouseArea {
                                                id: btChevHov
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    root.btPopupOpen = !root.btPopupOpen
                                                    if (root.btPopupOpen) root.wifiPopupOpen = false
                                                }
                                            }
                                        }
                                    }

                                    MouseArea {
                                        id: btTileHov
                                        anchors.fill: parent
                                        anchors.rightMargin: 26
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.toggleBt()
                                    }
                                }

                                // Night Light Toggle Pill
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 46
                                    radius: 14
                                    color: root.nightOn ? Theme.accent : (nightTileHov.containsMouse ? Theme.bgHover : Qt.rgba(Theme.bgAlt.r, Theme.bgAlt.g, Theme.bgAlt.b, 0.65))
                                    border.width: 1
                                    border.color: root.nightOn ? Qt.rgba(Theme.accentLit.r, Theme.accentLit.g, Theme.accentLit.b, 0.60) : Theme.outline
                                    Behavior on color { ColorAnimation { duration: 150 } }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        spacing: 6

                                        Rectangle {
                                            width: 30
                                            height: 30
                                            radius: 15
                                            color: root.nightOn ? (Theme.isDark ? Qt.rgba(0,0,0,0.2) : Qt.rgba(1,1,1,0.3)) : Qt.rgba(1, 1, 1, 0.08)
                                            Text {
                                                anchors.centerIn: parent
                                                text: "dark_mode"
                                                font.family: Theme.fontIcon
                                                font.pixelSize: 16
                                                color: root.nightOn ? (Theme.isDark ? "#101116" : "#ffffff") : Theme.fgDim
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 1
                                            Text {
                                                Layout.fillWidth: true
                                                text: "Night Light"
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: Theme.fontPx(9)
                                                font.weight: Font.Bold
                                                color: root.nightOn ? (Theme.isDark ? "#101116" : "#ffffff") : Theme.fg
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                text: root.nightOn ? "On" : "Off"
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: Theme.fontPx(7)
                                                color: root.nightOn ? (Theme.isDark ? Qt.rgba(0.06, 0.07, 0.09, 0.75) : Qt.rgba(1, 1, 1, 0.85)) : Theme.fgDim
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

                                // Do Not Disturb Toggle Pill
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 46
                                    radius: 14
                                    color: root.dndOn ? Theme.accent : (dndTileHov.containsMouse ? Theme.bgHover : Qt.rgba(Theme.bgAlt.r, Theme.bgAlt.g, Theme.bgAlt.b, 0.65))
                                    border.width: 1
                                    border.color: root.dndOn ? Qt.rgba(Theme.accentLit.r, Theme.accentLit.g, Theme.accentLit.b, 0.60) : Theme.outline
                                    Behavior on color { ColorAnimation { duration: 150 } }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        spacing: 6

                                        Rectangle {
                                            width: 30
                                            height: 30
                                            radius: 15
                                            color: root.dndOn ? (Theme.isDark ? Qt.rgba(0,0,0,0.2) : Qt.rgba(1,1,1,0.3)) : Qt.rgba(1, 1, 1, 0.08)
                                            Text {
                                                anchors.centerIn: parent
                                                text: root.dndOn ? "notifications_off" : "notifications"
                                                font.family: Theme.fontIcon
                                                font.pixelSize: 16
                                                color: root.dndOn ? (Theme.isDark ? "#101116" : "#ffffff") : Theme.fgDim
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 1
                                            Text {
                                                Layout.fillWidth: true
                                                text: "DND"
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: Theme.fontPx(9)
                                                font.weight: Font.Bold
                                                color: root.dndOn ? (Theme.isDark ? "#101116" : "#ffffff") : Theme.fg
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                text: root.dndOn ? "On" : "Off"
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: Theme.fontPx(7)
                                                color: root.dndOn ? (Theme.isDark ? Qt.rgba(0.06, 0.07, 0.09, 0.75) : Qt.rgba(1, 1, 1, 0.85)) : Theme.fgDim
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

                            /* ── Part 2: Hardware Sliders (Volume & Brightness) ── */
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 78
                                radius: 16
                                color: Qt.rgba(Theme.bgAlt.r, Theme.bgAlt.g, Theme.bgAlt.b, 0.65)
                                border.width: 1
                                border.color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.06)

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 6

                                    // Volume Slider Row
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8

                                        // Mute Toggle Icon Button
                                        Rectangle {
                                            width: 24
                                            height: 24
                                            radius: 12
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

                                        // Volume Interactive Track
                                        Item {
                                            id: volTrack
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 18

                                            Rectangle {
                                                anchors.fill: parent
                                                radius: 9
                                                color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.10)
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

                                        // Volume Percent Label
                                        Text {
                                            Layout.preferredWidth: 28
                                            horizontalAlignment: Text.AlignRight
                                            text: Math.round((root.isMuted ? 0 : root.volRatio) * 100) + "%"
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: Theme.fontPx(8)
                                            font.weight: Font.Bold
                                            color: Theme.fgDim
                                        }
                                    }

                                    // Brightness Slider Row
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8

                                        // Sun Icon
                                        Rectangle {
                                            width: 24
                                            height: 24
                                            radius: 12
                                            color: "transparent"
                                            Text {
                                                anchors.centerIn: parent
                                                text: "brightness_6"
                                                font.family: Theme.fontIcon
                                                font.pixelSize: 15
                                                color: Theme.accentLit
                                            }
                                        }

                                        // Brightness Interactive Track
                                        Item {
                                            id: brightTrack
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 18

                                            Rectangle {
                                                anchors.fill: parent
                                                radius: 9
                                                color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(0, 0, 0, 0.10)
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
                                                    var r = Math.max(0.05, Math.min(1.0, mx / brightTrack.width))
                                                    root.setBrightness(r)
                                                }

                                                onPressed: mouse => updateBright(mouse.x)
                                                onPositionChanged: mouse => { if (pressed) updateBright(mouse.x) }
                                            }

                                            WheelHandler {
                                                target: brightTrack
                                                onWheel: (event) => {
                                                    var step = event.angleDelta.y > 0 ? 0.05 : -0.05
                                                    root.setBrightness(Math.max(0.05, Math.min(1.0, root.brightRatio + step)))
                                                }
                                            }
                                        }

                                        // Brightness Percent Label
                                        Text {
                                            Layout.preferredWidth: 28
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

                            /* ── Part 3: Media Player Capsule ── */
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 74
                                radius: 16
                                color: Qt.rgba(Theme.bgAlt.r, Theme.bgAlt.g, Theme.bgAlt.b, 0.65)
                                border.width: 1
                                border.color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.06)

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 8

                                    // Album Art / Fallback
                                    Rectangle {
                                        width: 44
                                        height: 44
                                        radius: 10
                                        clip: true
                                        color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.15)
                                        border.width: 1
                                        border.color: Theme.outline

                                        Image {
                                            id: artImg
                                            anchors.fill: parent
                                            sourceSize: Qt.size(80, 80)
                                            fillMode: Image.PreserveAspectCrop
                                            source: root.artUrl
                                            visible: root.artUrl.length > 0 && status === Image.Ready
                                        }

                                        Text {
                                            anchors.centerIn: parent
                                            visible: !artImg.visible
                                            text: "music_note"
                                            font.family: Theme.fontIcon
                                            font.pixelSize: 22
                                            color: Theme.accent
                                        }
                                    }

                                    // Track Info & Progress
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2

                                        Text {
                                            Layout.fillWidth: true
                                            text: root.trackTitle.length > 0 ? root.trackTitle : "No Media Playing"
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: Theme.fontPx(9)
                                            font.weight: Font.Bold
                                            color: Theme.fg
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: root.trackArtist.length > 0 ? root.trackArtist : (root.activePlayer ? "Standby" : "Idle")
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: Theme.fontPx(7.5)
                                            color: Theme.fgDim
                                            elide: Text.ElideRight
                                        }

                                        // Progress Track
                                        Item {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 4
                                            visible: root.lenUs > 0

                                            Rectangle {
                                                anchors.fill: parent
                                                radius: 2
                                                color: Qt.rgba(1, 1, 1, 0.10)
                                            }

                                            Rectangle {
                                                height: parent.height
                                                width: Math.max(0, Math.min(parent.width, parent.width * root.progRatio))
                                                radius: 2
                                                color: Theme.accent
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: mouse => root.seekToRatio(mouse.x / width)
                                            }
                                        }
                                    }

                                    // Controls
                                    RowLayout {
                                        spacing: 2

                                        Rectangle {
                                            width: 26
                                            height: 26
                                            radius: 13
                                            color: prevBtnHov.containsMouse ? Theme.bgHover : "transparent"
                                            Text {
                                                anchors.centerIn: parent
                                                text: "skip_previous"
                                                font.family: Theme.fontIcon
                                                font.pixelSize: 16
                                                color: root.canPrev ? Theme.fg : Theme.fgDim
                                            }
                                            MouseArea {
                                                id: prevBtnHov
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: if (root.activePlayer) root.activePlayer.previous()
                                            }
                                        }

                                        Rectangle {
                                            width: 30
                                            height: 30
                                            radius: 15
                                            color: Theme.accent
                                            scale: playBtnHov.pressed ? 0.92 : 1.0
                                            Behavior on scale { NumberAnimation { duration: 80 } }

                                            Text {
                                                anchors.centerIn: parent
                                                text: root.playing ? "pause" : "play_arrow"
                                                font.family: Theme.fontIcon
                                                font.pixelSize: 18
                                                color: Theme.isDark ? "#101116" : "#ffffff"
                                            }
                                            MouseArea {
                                                id: playBtnHov
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.togglePlayPause()
                                            }
                                        }

                                        Rectangle {
                                            width: 26
                                            height: 26
                                            radius: 13
                                            color: nextBtnHov.containsMouse ? Theme.bgHover : "transparent"
                                            Text {
                                                anchors.centerIn: parent
                                                text: "skip_next"
                                                font.family: Theme.fontIcon
                                                font.pixelSize: 16
                                                color: root.canNext ? Theme.fg : Theme.fgDim
                                            }
                                            MouseArea {
                                                id: nextBtnHov
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: if (root.activePlayer) root.activePlayer.next()
                                            }
                                        }
                                    }
                                }
                            }

                            /* ── Part 4: Notifications Section ── */
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 22
                                Layout.leftMargin: 4
                                Layout.rightMargin: 4
                                spacing: 6

                                Text {
                                    text: "NOTIFICATIONS"
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: Theme.fontPx(8)
                                    font.weight: Font.Bold
                                    font.letterSpacing: 1.2
                                    color: Theme.fgDim
                                }

                                Rectangle {
                                    visible: root.notifCount > 0
                                    Layout.preferredHeight: 15
                                    Layout.preferredWidth: countTxt.implicitWidth + 8
                                    radius: 7.5
                                    color: Theme.accent
                                    Text {
                                        id: countTxt
                                        anchors.centerIn: parent
                                        text: String(root.notifCount)
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: Theme.fontPx(8)
                                        font.weight: Font.Bold
                                        color: Theme.isDark ? "#101116" : "#ffffff"
                                    }
                                }

                                Item { Layout.fillWidth: true }

                                Rectangle {
                                    visible: root.notifCount > 0
                                    Layout.preferredHeight: 20
                                    Layout.preferredWidth: clearRow.implicitWidth + 10
                                    radius: 10
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
                                            text: "Clear all"
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: Theme.fontPx(8)
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

                            Rectangle {
                                Layout.fillWidth: true
                                height: 1
                                color: Theme.outline
                            }

                            // Empty State
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 46
                                radius: 12
                                color: Qt.rgba(Theme.bgAlt.r, Theme.bgAlt.g, Theme.bgAlt.b, 0.45)
                                border.width: 1
                                border.color: Qt.rgba(1, 1, 1, 0.05)
                                visible: root.notifCount === 0

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 8
                                    Text {
                                        text: "notifications"
                                        font.family: Theme.fontIcon
                                        font.pixelSize: 16
                                        color: Qt.rgba(Theme.fgDim.r, Theme.fgDim.g, Theme.fgDim.b, 0.4)
                                    }
                                    Text {
                                        text: "No new notifications"
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: Theme.fontPx(8.5)
                                        font.weight: Font.Medium
                                        color: Theme.fgDim
                                    }
                                }
                            }

                            // Notification Cards Repeater
                            Repeater {
                                model: root.notifs
                                delegate: Rectangle {
                                    id: notifCardItem
                                    required property int index
                                    required property var modelData

                                    readonly property bool isSelected: root.selectedNotifIndex === index
                                    readonly property bool isExpanded: root.expandedNotifId === (modelData ? modelData.id : -999)

                                    Layout.fillWidth: true
                                    Layout.preferredHeight: isExpanded ? (notifContentCol.implicitHeight + notifActionRow.implicitHeight + 22) : (notifContentCol.implicitHeight + 14)
                                    radius: 12
                                    color: isSelected
                                        ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.22)
                                        : (notifCardMH.containsMouse ? Theme.bgHover : Qt.rgba(Theme.bgAlt.r, Theme.bgAlt.g, Theme.bgAlt.b, 0.70))
                                    border.width: isSelected ? 1.5 : 1
                                    border.color: isSelected
                                        ? Qt.rgba(Theme.accentLit.r, Theme.accentLit.g, Theme.accentLit.b, 0.85)
                                        : (notifCardMH.containsMouse ? Qt.rgba(Theme.accentLit.r, Theme.accentLit.g, Theme.accentLit.b, 0.35) : Qt.rgba(1, 1, 1, 0.10))

                                    MouseArea {
                                        id: notifCardMH
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.selectedNotifIndex = index
                                            root.activateSelectedNotif()
                                        }
                                    }

                                    ColumnLayout {
                                        id: notifContentCol
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.margins: 8
                                        spacing: 4

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 6

                                            Rectangle {
                                                width: 18
                                                height: 18
                                                radius: 9
                                                color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.2)
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "notifications"
                                                    font.family: Theme.fontIcon
                                                    font.pixelSize: 11
                                                    color: Theme.accent
                                                }
                                            }

                                            Text {
                                                Layout.fillWidth: true
                                                text: (modelData && modelData.appName) ? modelData.appName : "System"
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: Theme.fontPx(7.5)
                                                font.weight: Font.Bold
                                                color: Theme.fgDim
                                                elide: Text.ElideRight
                                            }

                                            Rectangle {
                                                width: 18
                                                height: 18
                                                radius: 9
                                                color: closeMH.containsMouse ? Qt.rgba(1, 0.2, 0.2, 0.2) : "transparent"

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "close"
                                                    font.family: Theme.fontIcon
                                                    font.pixelSize: 11
                                                    color: closeMH.containsMouse ? "#ff5555" : Theme.fgDim
                                                }

                                                MouseArea {
                                                    id: closeMH
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        if (modelData && typeof modelData.dismiss === "function") {
                                                            modelData.dismiss()
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: (modelData && modelData.summary) ? modelData.summary : ""
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: Theme.fontPx(8.5)
                                            font.weight: Font.Bold
                                            color: Theme.fg
                                            elide: Text.ElideRight
                                            visible: text.length > 0
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: (modelData && modelData.body) ? modelData.body : ""
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: Theme.fontPx(7.5)
                                            color: Theme.fgDim
                                            wrapMode: Text.Wrap
                                            maximumLineCount: notifCardItem.isExpanded ? 10 : 2
                                            elide: Text.ElideRight
                                            visible: text.length > 0
                                        }

                                        RowLayout {
                                            id: notifActionRow
                                            Layout.fillWidth: true
                                            visible: notifCardItem.isExpanded && modelData && modelData.actions && modelData.actions.length > 0
                                            spacing: 6

                                            Repeater {
                                                model: (modelData && modelData.actions) ? modelData.actions : []
                                                delegate: Rectangle {
                                                    required property var modelData
                                                    Layout.fillWidth: true
                                                    Layout.preferredHeight: 20
                                                    radius: 6
                                                    color: actMH.containsMouse ? Theme.accent : Qt.rgba(1, 1, 1, 0.08)
                                                    border.width: 1
                                                    border.color: actMH.containsMouse ? Theme.accentLit : Qt.rgba(1, 1, 1, 0.12)

                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: modelData.text || modelData.label || "Action"
                                                        font.family: "JetBrainsMono Nerd Font"
                                                        font.pixelSize: Theme.fontPx(7.5)
                                                        font.weight: Font.Medium
                                                        color: actMH.containsMouse ? (Theme.isDark ? "#101116" : "#ffffff") : Theme.fg
                                                    }

                                                    MouseArea {
                                                        id: actMH
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            if (typeof modelData.invoke === "function") {
                                                                modelData.invoke()
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
                }

                /* ==== Mode 1: Tasks ==== */
                TodoPane {
                    width: parent.width
                    height: parent.height
                    x: root.paneX(1)
                    opacity: root.mode === 1 ? 1 : 0
                    enabled: root.mode === 1
                    Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.InOutCubic } }
                }

                /* ==== Mode 2: Timer ==== */
                TimerPane {
                    width: parent.width
                    height: parent.height
                    x: root.paneX(2)
                    opacity: root.mode === 2 ? 1 : 0
                    enabled: root.mode === 2
                    Behavior on x { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.InOutCubic } }
                }
            }
        }

        /* Detail popups for Wi-Fi & Bluetooth (only active & visible when open) */
        WifiPopup {
            id: wifiPopup
            anchors.horizontalCenter: card.horizontalCenter
            anchors.top: card.top
            anchors.topMargin: 40
            width: card.width - 20
            height: card.height - 48
            z: 100
            visible: root.wifiPopupOpen || wifiPopup.animatingOut
            enabled: root.wifiPopupOpen
            open: root.wifiPopupOpen
            powerOn: root.wifiOn
            wifiName: root.wifiName
            onPowerToggled: root.toggleWifi()
            onRequestedClose: root.wifiPopupOpen = false
        }

        BtPopup {
            id: btPopup
            anchors.horizontalCenter: card.horizontalCenter
            anchors.top: card.top
            anchors.topMargin: 40
            width: card.width - 20
            height: card.height - 48
            z: 100
            visible: root.btPopupOpen || btPopup.animatingOut
            enabled: root.btPopupOpen
            open: root.btPopupOpen
            powerOn: root.btOn
            btName: root.btName
            onPowerToggled: root.toggleBt()
            onRequestedClose: root.btPopupOpen = false
        }
    }
}