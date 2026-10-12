import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import M3Shapes
import "../components"
import "../Singletons"

/**
 * Carbon quick-settings panel. Hovers open from the top-right hot corner.
 * Three modes behind a small tab bar:
 *   0. Quick  — now-playing strip + Bluetooth / Wi-Fi / night light / gaming
 *               toggles + a screen recorder (full screen or slurp region, with
 *               separate microphone / app-audio switches mixed via a null sink).
 *   1. Calendar — compact month widget.
 *   2. Timer  — pomodoro / stopwatch.
 * States are probed live from the CLIs on open and after any toggle fires.
 */
Item {
    id: root

    property bool open: false
    property bool hovered: false
    property int mode: 0            // 0: controls, 1: todo, 2: timer, 3: weather
    property string corner: "bottom_right"
    property real shellOpacity: Theme.shellOpacity
    readonly property string home: Quickshell.env("HOME") || ""

    /* ── Notifications Support & Keyboard Navigation ── */
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
        if (typeof pane0Flick !== 'undefined') {
            pane0Flick.contentY = Math.min(pane0Flick.contentHeight - pane0Flick.height, 264)
        }
    }

    function selectNextNotif() {
        if (root.notifCount > 0) {
            root.selectedNotifIndex = Math.min(root.notifCount - 1, root.selectedNotifIndex + 1)
            if (typeof pane0Flick !== 'undefined') {
                pane0Flick.contentY = Math.min(pane0Flick.contentHeight - pane0Flick.height, Math.max(pane0Flick.contentY, 260 + root.selectedNotifIndex * 54))
            }
        }
    }

    function selectPrevNotif() {
        if (root.selectedNotifIndex > 0) {
            root.selectedNotifIndex = root.selectedNotifIndex - 1
            if (typeof pane0Flick !== 'undefined') {
                pane0Flick.contentY = Math.max(0, 260 + (root.selectedNotifIndex - 1) * 54)
            }
        } else {
            root.selectedNotifIndex = -1
            if (typeof pane0Flick !== 'undefined') {
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

    /* Fixed size: modern Concept 7 dynamic capsule hybrid dimensions */
    readonly property int paneW: 296
    readonly property int paneH: 268
    readonly property int cardW: root.paneW + 24
    readonly property int cardH: 52 + root.paneH
    implicitWidth: root.cardW
    implicitHeight: root.cardH
    width: root.implicitWidth
    height: root.implicitHeight

    readonly property var cardItem: card
    readonly property bool animatingOut: !root.open && card.opacity > 0.001

    /* Pager position for a pane: current sits at 0, neighbours sit one page
     * off either side and animate in/out when the mode changes. */
    function paneX(idx) { return (idx - root.mode) * root.paneW }


    /* ============================ Now playing ============================ */
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

    /* Smooth the progress knob between Mpris position poll refreshes. */
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

    /* ============================ Quick toggles ============================ */
    property bool btOn: false
    property bool wifiOn: true
    property bool nightAvailable: true
    property bool nightOn: false
    property bool gameOn: false
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
        if (!gameProbe.running) gameProbe.running = true
        if (!dndProbe.running) dndProbe.running = true
        if (!btNameProbe.running) btNameProbe.running = true
        if (!wifiNameProbe.running) wifiNameProbe.running = true
        if (!recProbe.running) recProbe.running = true
    }

    /* Screen Recorder */
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
                if (el > 0 && Math.abs(el - root.recElapsed) > 2) {
                    root.recElapsed = el
                }
            }
        }
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

    /* Night light (hyprsunset) */
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

    /* Gaming mode: drop Hyprland animations for lower latency */
    Process {
        id: gameProbe
        command: ["sh", "-c",
            "hyprctl getoption animations:enabled -j 2>/dev/null | sed -n 's/.*\\\"bool\\\":[[:space:]]*\\(true\\|false\\).*/\\1/p'"]
        stdout: StdioCollector { id: gameC; waitForEnd: true }
        onExited: root.gameOn = String(gameC.text).trim() === "false"
    }
    function toggleGame() {
        root.gameOn = !root.gameOn
        Quickshell.execDetached(["hyprctl", "eval",
            root.gameOn
                ? "hl.config({ animations = { enabled = false } })"
                : "hl.config({ animations = { enabled = true } })"])
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

    /* ============================ Recorder (Full Screen Only) ============================ */
    property bool recWorking: false
    property bool recFail: false
    property bool recMic: true
    property bool recApp: true
    property int recElapsed: 0
    property string recDone: ""

    readonly property string recScriptDir: root.home + "/.config/hypr/scripts"

    function recStatus() {
        if (root.recFail) return "Failed to start recording"
        if (root.recWorking) return "● REC  " + root.fmtRec(root.recElapsed)
        if (root.recDone.length > 0) return "Saved · " + root.recDone
        return "Ready"
    }
    function fmtRec(s) {
        const m = Math.floor(s / 60)
        return String(m).padStart(2, "0") + ":" + String(s % 60).padStart(2, "0")
    }
    function recStart() {
        if (root.recWorking) return
        root.recDone = ""
        root.recFail = false
        root.recElapsed = 0
        recStartProc.command = ["/bin/sh", root.recScriptDir + "/carbon-rec-start.sh",
            "full",
            root.recMic ? "1" : "0", root.recApp ? "1" : "0"]
        recStartProc.running = true
    }
    function recStop() {
        recStopProc.command = ["/bin/sh", root.recScriptDir + "/carbon-rec-stop.sh"]
        recStopProc.running = true
    }

    Timer {
        id: recClock
        interval: 1000
        repeat: true
        running: root.recWorking
        onTriggered: root.recElapsed++
    }

    Timer {
        id: recMsgTimer
        interval: 5000
        onTriggered: root.recDone = ""
    }

    /* Periodic recorder health & status check */
    Timer {
        id: recHeartbeatTimer
        interval: 1500
        repeat: true
        running: root.open || root.recWorking
        triggeredOnStart: true
        onTriggered: {
            if (!recProbe.running) recProbe.running = true
        }
    }

    Process {
        id: recStartProc
        command: ["/bin/sh", "/bin/true"]
        stdout: StdioCollector { id: recStartC; waitForEnd: true }
        onExited: {
            if (exitCode === 0) {
                /* the start script detaches wf-recorder; confirm it is still
                 * alive before flipping the UI to "recording" */
                recVerifyProc.running = true
            } else {
                root.recFail = true
                recFailTimer.restart()
            }
        }
    }

    Process {
        id: recVerifyProc
        command: ["sh", "-c", "[ -f /tmp/rec.pid ] && kill -0 $(cat /tmp/rec.pid) 2>/dev/null && echo alive || echo dead"]
        stdout: StdioCollector { id: recVerifyC; waitForEnd: true }
        onExited: {
            if (String(recVerifyC.text).trim() === "alive") {
                root.recWorking = true
            } else {
                root.recFail = true
                recFailTimer.restart()
            }
        }
    }

    Timer {
        id: recFailTimer
        interval: 4000
        onTriggered: root.recFail = false
    }

    Process {
        id: recStopProc
        command: ["/bin/sh", "/bin/true"]
        stdout: StdioCollector { id: recStopC; waitForEnd: true }
        onExited: {
            root.recWorking = false
            const v = String(recStopC.text).trim().replace(/^saved:\s*/, "")
            if (v.length > 0) {
                root.recDone = v.substring(v.lastIndexOf("/") + 1)
                recMsgTimer.restart()
            }
        }
    }

    onOpenChanged: {
        if (root.open) {
            root.syncPlayer()
            root.refreshStates()
            if (!layoutLoader.running) layoutLoader.running = true
            if (typeof pane0Flick !== 'undefined') pane0Flick.contentY = 0
            root.selectedNotifIndex = -1
        } else {
            root.wifiPopupOpen = false
            root.btPopupOpen = false
            root.showingNotifs = false
            root.expandedNotifId = -1
        }
    }

    /* ==================== Reorderable Layout ==================== */
    property var cardOrder: ["media", "toggles", "recorder"]
    property string activeCardDrag: ""

    function getCardHeight(name) {
        if (name === "media") return 104;
        if (name === "recorder") return 76;
        if (name === "toggles") return 70;
        return 70;
    }

    function getSlotY(slotIdx) {
        if (slotIdx <= 0) return 0;
        var h0 = getCardHeight(root.cardOrder[0]);
        var y1 = h0 + 6;
        if (slotIdx === 1) return y1;
        var h1 = getCardHeight(root.cardOrder[1]);
        return y1 + h1 + 6;
    }

    function getTargetCardY(name) {
        var idx = root.cardOrder.indexOf(name);
        return idx >= 0 ? getSlotY(idx) : 0;
    }

    function checkCardSwap(draggedName, centerY) {
        var curSlot = root.cardOrder.indexOf(draggedName);
        if (curSlot === -1) return;

        var bestSlot = 0;
        var minDist = 999999;
        for (var s = 0; s < 3; s++) {
            var sCenter = getSlotY(s) + getCardHeight(root.cardOrder[s]) / 2;
            var d = Math.abs(centerY - sCenter);
            if (d < minDist) {
                minDist = d;
                bestSlot = s;
            }
        }

        if (bestSlot !== curSlot) {
            var arr = root.cardOrder.slice();
            arr.splice(curSlot, 1);
            arr.splice(bestSlot, 0, draggedName);
            root.cardOrder = arr;
        }
    }

    /* 5 Toggle tiles ordering */
    property var tileOrder: ["wifi", "bt", "night", "game", "dnd"]
    property string activeTileDrag: ""

    readonly property var tileSlotCoords: [
        { x: 37,  y: 2 },
        { x: 101, y: 2 },
        { x: 165, y: 2 },
        { x: 69,  y: 52 },
        { x: 133, y: 52 }
    ]

    function getTileSlotX(name) {
        var idx = root.tileOrder.indexOf(name);
        return idx >= 0 && idx < tileSlotCoords.length ? tileSlotCoords[idx].x : 37;
    }

    function getTileSlotY(name) {
        var idx = root.tileOrder.indexOf(name);
        return idx >= 0 && idx < tileSlotCoords.length ? tileSlotCoords[idx].y : 2;
    }

    function checkTileSwap(draggedName, centerX, centerY) {
        var curSlot = root.tileOrder.indexOf(draggedName);
        if (curSlot === -1) return;

        var bestSlot = curSlot;
        var minDist = 999999;
        for (var s = 0; s < tileSlotCoords.length; s++) {
            var sx = tileSlotCoords[s].x + 23;
            var sy = tileSlotCoords[s].y + 23;
            var dist = Math.hypot(centerX - sx, centerY - sy);
            if (dist < minDist) {
                minDist = dist;
                bestSlot = s;
            }
        }

        if (bestSlot !== curSlot && minDist < 34) {
            var arr = root.tileOrder.slice();
            arr.splice(curSlot, 1);
            arr.splice(bestSlot, 0, draggedName);
            root.tileOrder = arr;
        }
    }

    Component.onCompleted: {
        layoutLoader.running = true
        recProbe.running = true
        root.refreshStates()
    }

    function saveLayout() {
        var d = {
            cardOrder: root.cardOrder,
            tileOrder: root.tileOrder
        };
        Quickshell.execDetached(["sh", "-c",
            "echo '" + JSON.stringify(d) + "' > " + root.home + "/.config/hypr/carbon-qs-layout.json"]);
    }

    function resetLayout() {
        root.cardOrder = ["media", "toggles", "recorder"];
        root.tileOrder = ["wifi", "bt", "night", "game", "dnd"];
        if (typeof cardMedia !== 'undefined') cardMedia.y = Qt.binding(() => root.getTargetCardY("media"));
        if (typeof cardToggles !== 'undefined') cardToggles.y = Qt.binding(() => root.getTargetCardY("toggles"));
        if (typeof cardRecorder !== 'undefined') cardRecorder.y = Qt.binding(() => root.getTargetCardY("recorder"));
        if (typeof tileWifi !== 'undefined') {
            tileWifi.x = Qt.binding(() => root.getTileSlotX("wifi"));
            tileWifi.y = Qt.binding(() => root.getTileSlotY("wifi"));
        }
        if (typeof tileBt !== 'undefined') {
            tileBt.x = Qt.binding(() => root.getTileSlotX("bt"));
            tileBt.y = Qt.binding(() => root.getTileSlotY("bt"));
        }
        if (typeof tileNight !== 'undefined') {
            tileNight.x = Qt.binding(() => root.getTileSlotX("night"));
            tileNight.y = Qt.binding(() => root.getTileSlotY("night"));
        }
        if (typeof tileGame !== 'undefined') {
            tileGame.x = Qt.binding(() => root.getTileSlotX("game"));
            tileGame.y = Qt.binding(() => root.getTileSlotY("game"));
        }
        if (typeof tileDnd !== 'undefined') {
            tileDnd.x = Qt.binding(() => root.getTileSlotX("dnd"));
            tileDnd.y = Qt.binding(() => root.getTileSlotY("dnd"));
        }
        Quickshell.execDetached(["rm", "-f", root.home + "/.config/hypr/carbon-qs-layout.json"]);
    }

    Process {
        id: layoutLoader
        command: ["sh", "-c", "cat " + root.home + "/.config/hypr/carbon-qs-layout.json 2>/dev/null || true"]
        stdout: StdioCollector { id: layoutC; waitForEnd: true }
        onExited: {
            try {
                var txt = String(layoutC.text).trim();
                if (txt.length > 5) {
                    var d = JSON.parse(txt);
                    if (Array.isArray(d.cardOrder) && d.cardOrder.length === 3) {
                        root.cardOrder = d.cardOrder;
                    }
                    if (Array.isArray(d.tileOrder) && d.tileOrder.length === 5) {
                        root.tileOrder = d.tileOrder;
                    }
                }
            } catch (e) {}
        }
    }

    /* ============================ Visual ============================ */
    Item {
        id: card
        width: root.cardW
        height: root.cardH
        clip: true

        readonly property color fillColor: Theme.isDark ? Qt.rgba(0.08, 0.09, 0.12, root.shellOpacity) : Qt.rgba(Theme.m3surfaceContainerLowest.r, Theme.m3surfaceContainerLowest.g, Theme.m3surfaceContainerLowest.b, root.shellOpacity)
        readonly property color strokeColor: root.open ? Qt.rgba(Theme.accentLit.r, Theme.accentLit.g, Theme.accentLit.b, 0.35) : (Theme.isDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.12))

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
                            // Only top-left is rounded; completely flush and square at bottom and right screen edges
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
                            // Stroke ONLY on left edge and top edge — zero stroke on bottom or right screen edges!
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

        transformOrigin: root.corner === "top_left" ? Item.TopLeft :
                         (root.corner === "bottom_left" ? Item.BottomLeft : Item.BottomRight)

        x: (root.corner === "top_left" || root.corner === "bottom_left") ? (root.open ? 0 : -14) : (root.open ? 0 : 14)
        y: root.corner === "top_left" ? (root.open ? 0 : -14) : (root.open ? 0 : 14)
        scale: root.open ? 1.0 : 0.97
        opacity: root.open ? 1.0 : 0.0

        Behavior on opacity {
            NumberAnimation {
                duration: root.open ? 130 : 80
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
                            { glyph: "timer", label: "Timer" },
                            { glyph: "partly_cloudy_day", label: "Weather" }
                        ]
                        delegate: Rectangle {
                            required property int index
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: 12
                            color: root.mode === index ? Theme.accent : (tabHov.hovered ? Theme.bgHover : "transparent")
                            Behavior on color { ColorAnimation { duration: Theme.motionDurationShort3; easing.type: Theme.easingStandard } }

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
                                    font.family: "Inter"
                                    font.pixelSize: 8
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

            /* --- Content (modes swipe horizontally, size stays fixed) --- */
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: root.paneH
                clip: true

                /* ==== Mode 0: quick settings + recorder (draggable modules) & notifications ==== */
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

                    /* ── Unified Controls & Notifications (Android-style scrollable) ── */
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
                            spacing: 6

                            /* ── Part 1: Controls Section ── */
                            Item {
                                id: controlsContainer
                                Layout.fillWidth: true
                                Layout.preferredHeight: 262

/* 1. Media Player Capsule with Wavy Visualizer */
                        Rectangle {
                            id: cardMedia
                        width: parent.width
                        height: 104
                        x: 0
                        y: root.activeCardDrag === "media" ? y : root.getTargetCardY("media")
                        radius: 18
                        color: mediaDrag.drag.active ? Theme.bgAlt : Qt.rgba(Theme.bgAlt.r, Theme.bgAlt.g, Theme.bgAlt.b, 0.70)
                        border.color: mediaDrag.drag.active ? Theme.accent : (Theme.isDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.08))
                        border.width: 1
                        z: mediaDrag.drag.active ? 50 : 1
                        scale: mediaDrag.drag.active ? 1.02 : 1.0
                        Behavior on scale { NumberAnimation { duration: 100 } }
                        Behavior on y {
                            enabled: root.activeCardDrag !== "media"
                            NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                        }

                        opacity: root.open ? 1 : 0
                        transform: Translate {
                            y: root.open ? 0 : 4
                            Behavior on y { NumberAnimation { duration: root.open ? 120 : 70; easing.type: Easing.OutCubic } }
                        }
                        Behavior on opacity { NumberAnimation { duration: root.open ? 120 : 70; easing.type: Easing.OutCubic } }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 3

                            /* Top track row */
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                Rectangle {
                                    width: 32
                                    height: 32
                                    radius: 10
                                    color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.22)
                                    border.color: Qt.rgba(Theme.accentLit.r, Theme.accentLit.g, Theme.accentLit.b, 0.35)
                                    border.width: 1
                                    clip: true

                                    Image {
                                        anchors.fill: parent
                                        source: root.artUrl
                                        sourceSize: Qt.size(80, 80)
                                        visible: root.artUrl.length > 0
                                        fillMode: Image.PreserveAspectCrop
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        text: "music_note"
                                        font.family: Theme.fontIcon
                                        font.pixelSize: 16
                                        color: Theme.accentLit
                                        visible: root.artUrl.length === 0
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1

                                    Text {
                                        Layout.fillWidth: true
                                        text: root.trackTitle.length > 0 ? root.trackTitle : "No Media Playing"
                                        font.family: "Inter"
                                        font.pixelSize: 10
                                        font.weight: Font.Bold
                                        color: Theme.fg
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: root.trackArtist.length > 0 ? root.trackArtist : "Waiting for playback…"
                                        font.family: "Inter"
                                        font.pixelSize: 8
                                        color: Theme.accentLit
                                        elide: Text.ElideRight
                                    }
                                }

                                RowLayout {
                                    spacing: 4

                                    Rectangle {
                                        width: 22
                                        height: 22
                                        radius: 11
                                        color: prevMH.containsMouse ? Theme.bgHover : "transparent"
                                        scale: prevMH.pressed ? 0.92 : (prevMH.containsMouse ? 1.08 : 1.0)
                                        Behavior on scale { NumberAnimation { duration: Theme.motionDurationShort2; easing.type: Theme.easingEmphasized } }
                                        Text {
                                            anchors.centerIn: parent
                                            text: "skip_previous"
                                            font.family: Theme.fontIcon
                                            font.pixelSize: 13
                                            color: root.canPrev ? Theme.fg : Theme.fgDim
                                        }
                                        MouseArea {
                                            id: prevMH
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: root.canPrev ? Qt.PointingHandCursor : Qt.ArrowCursor
                                            onClicked: if (root.activePlayer && root.canPrev) root.activePlayer.previous()
                                        }
                                    }

                                    Rectangle {
                                        width: 28
                                        height: 28
                                        radius: 14
                                        color: Theme.accent
                                        scale: playMH.pressed ? 0.92 : (playMH.containsMouse ? 1.06 : 1.0)
                                        Behavior on scale { NumberAnimation { duration: Theme.motionDurationShort2; easing.type: Theme.easingEmphasized } }
                                        Text {
                                            anchors.centerIn: parent
                                            text: root.playing ? "pause" : "play_arrow"
                                            font.family: Theme.fontIcon
                                            font.pixelSize: 16
                                            color: Theme.isDark ? "#101116" : "#ffffff"
                                        }
                                        MouseArea {
                                            id: playMH
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: if (root.activePlayer) root.activePlayer.togglePlaying()
                                        }
                                    }

                                    Rectangle {
                                        width: 22
                                        height: 22
                                        radius: 11
                                        color: nextMH.containsMouse ? Theme.bgHover : "transparent"
                                        scale: nextMH.pressed ? 0.92 : (nextMH.containsMouse ? 1.08 : 1.0)
                                        Behavior on scale { NumberAnimation { duration: Theme.motionDurationShort2; easing.type: Theme.easingEmphasized } }
                                        Text {
                                            anchors.centerIn: parent
                                            text: "skip_next"
                                            font.family: Theme.fontIcon
                                            font.pixelSize: 13
                                            color: root.canNext ? Theme.fg : Theme.fgDim
                                        }
                                        MouseArea {
                                            id: nextMH
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: root.canNext ? Qt.PointingHandCursor : Qt.ArrowCursor
                                            onClicked: if (root.activePlayer && root.canNext) root.activePlayer.next()
                                        }
                                    }
                                }
                            }

                            /* Wavy Visualizer Seek Bar */
                            WavySeekBar {
                                Layout.fillWidth: true
                                waveHeight: 10
                                barHeight: 6
                                timeLabelSize: 7
                                accentColor: Theme.accent
                                accentLitColor: Theme.accentLit
                                isPlaying: root.playing
                                currentPosition: root.posUs / 1000000
                                totalLength: root.lenUs / 1000000
                                onSeekRequested: (frac) => root.seekToRatio(frac)
                            }
                        }

                        MouseArea {
                            id: mediaDrag
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: 20
                            hoverEnabled: true
                            cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.SizeAllCursor
                            drag.target: cardMedia
                            drag.axis: Drag.YAxis
                            drag.minimumY: 0
                            drag.maximumY: Math.max(0, controlsContainer.height - cardMedia.height)
                            onPressed: root.activeCardDrag = "media"
                            onPositionChanged: {
                                if (drag.active) {
                                    root.checkCardSwap("media", cardMedia.y + cardMedia.height / 2)
                                }
                            }
                            onReleased: {
                                root.activeCardDrag = ""
                                cardMedia.y = Qt.binding(() => root.getTargetCardY("media"))
                                root.saveLayout()
                            }
                        }
                    }

                    /* 2. Circular Quick Toggles Capsule (NO sound/brightness bars) */
                    Rectangle {
                        id: cardToggles
                        width: parent.width
                        height: 70
                        x: 0
                        y: root.activeCardDrag === "toggles" ? y : root.getTargetCardY("toggles")
                        radius: 18
                        color: togglesDrag.drag.active ? Theme.bgAlt : Qt.rgba(Theme.bgAlt.r, Theme.bgAlt.g, Theme.bgAlt.b, 0.70)
                        border.color: togglesDrag.drag.active ? Theme.accent : (Theme.isDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.08))
                        border.width: 1
                        z: togglesDrag.drag.active ? 50 : 1
                        scale: togglesDrag.drag.active ? 1.02 : 1.0
                        Behavior on scale { NumberAnimation { duration: 100 } }
                        Behavior on y {
                            enabled: root.activeCardDrag !== "toggles"
                            NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                        }

                        opacity: root.open ? 1 : 0
                        transform: Translate {
                            y: root.open ? 0 : 4
                            Behavior on y { NumberAnimation { duration: root.open ? 125 : 75; easing.type: Easing.OutCubic } }
                        }
                        Behavior on opacity { NumberAnimation { duration: root.open ? 125 : 75; easing.type: Easing.OutCubic } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 6
                            spacing: 0

                            // 1. Wi-Fi Toggle with M3 Abstract Shape Highlight
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignHCenter
                                spacing: 2

                                Item {
                                    Layout.alignment: Qt.AlignHCenter
                                    width: 38
                                    height: 38
                                    scale: wifiM.pressed ? 0.94 : (wifiM.containsMouse ? 1.08 : 1.0)
                                    Behavior on scale { NumberAnimation { duration: Theme.motionDurationShort2; easing.type: Theme.easingEmphasized } }

                                    MaterialShape {
                                        anchors.centerIn: parent
                                        width: 38
                                        height: 38
                                        shape: wifiM.containsMouse ? MaterialShape.Flower : (root.wifiOn ? MaterialShape.Cookie12Sided : MaterialShape.Circle)
                                        animationDuration: 280
                                        animationEasing: Easing.OutBack
                                        color: root.wifiOn ? Theme.accent : (wifiM.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.20) : Qt.rgba(1, 1, 1, 0.07))
                                        strokeWidth: 1
                                        strokeColor: root.wifiOn ? Qt.rgba(Theme.accentLit.r, Theme.accentLit.g, Theme.accentLit.b, 0.60) : (wifiM.containsMouse ? Theme.accent : Qt.rgba(1, 1, 1, 0.10))
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        text: "wifi"
                                        font.family: Theme.fontIcon
                                        font.pixelSize: 18
                                        color: root.wifiOn ? (Theme.isDark ? "#101116" : "#ffffff") : Theme.fgDim
                                    }

                                    MouseArea {
                                        id: wifiM
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.wifiPopupOpen = !root.wifiPopupOpen
                                            if (root.wifiPopupOpen) root.btPopupOpen = false
                                        }
                                    }
                                }

                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "Wi-Fi"
                                    font.family: "Inter"
                                    font.pixelSize: 8
                                    font.weight: Font.DemiBold
                                    color: root.wifiOn ? Theme.accentLit : Theme.fgDim
                                }
                            }

                            // 2. Bluetooth Toggle with M3 Abstract Shape Highlight
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignHCenter
                                spacing: 2

                                Item {
                                    Layout.alignment: Qt.AlignHCenter
                                    width: 38
                                    height: 38
                                    scale: btM.pressed ? 0.94 : (btM.containsMouse ? 1.08 : 1.0)
                                    Behavior on scale { NumberAnimation { duration: Theme.motionDurationShort2; easing.type: Theme.easingEmphasized } }

                                    MaterialShape {
                                        anchors.centerIn: parent
                                        width: 38
                                        height: 38
                                        shape: btM.containsMouse ? MaterialShape.Diamond : (root.btOn ? MaterialShape.PuffyDiamond : MaterialShape.Circle)
                                        animationDuration: 280
                                        animationEasing: Easing.OutBack
                                        color: root.btOn ? Theme.accent : (btM.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.20) : Qt.rgba(1, 1, 1, 0.07))
                                        strokeWidth: 1
                                        strokeColor: root.btOn ? Qt.rgba(Theme.accentLit.r, Theme.accentLit.g, Theme.accentLit.b, 0.60) : (btM.containsMouse ? Theme.accent : Qt.rgba(1, 1, 1, 0.10))
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        text: "bluetooth"
                                        font.family: Theme.fontIcon
                                        font.pixelSize: 18
                                        color: root.btOn ? (Theme.isDark ? "#101116" : "#ffffff") : Theme.fgDim
                                    }

                                    MouseArea {
                                        id: btM
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.btPopupOpen = !root.btPopupOpen
                                            if (root.btPopupOpen) root.wifiPopupOpen = false
                                        }
                                    }
                                }

                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "Bluetooth"
                                    font.family: "Inter"
                                    font.pixelSize: 8
                                    font.weight: Font.DemiBold
                                    color: root.btOn ? Theme.accentLit : Theme.fgDim
                                }
                            }

                            // 3. Night Light Toggle with M3 Abstract Shape Highlight
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignHCenter
                                spacing: 2

                                Item {
                                    Layout.alignment: Qt.AlignHCenter
                                    width: 38
                                    height: 38
                                    scale: nightM.pressed ? 0.94 : (nightM.containsMouse ? 1.08 : 1.0)
                                    Behavior on scale { NumberAnimation { duration: Theme.motionDurationShort2; easing.type: Theme.easingEmphasized } }

                                    MaterialShape {
                                        anchors.centerIn: parent
                                        width: 38
                                        height: 38
                                        shape: nightM.containsMouse ? MaterialShape.Sunny : (root.nightOn ? MaterialShape.SoftBurst : MaterialShape.Circle)
                                        animationDuration: 280
                                        animationEasing: Easing.OutBack
                                        color: root.nightOn ? Theme.accent : (nightM.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.20) : Qt.rgba(1, 1, 1, 0.07))
                                        strokeWidth: 1
                                        strokeColor: root.nightOn ? Qt.rgba(Theme.accentLit.r, Theme.accentLit.g, Theme.accentLit.b, 0.60) : (nightM.containsMouse ? Theme.accent : Qt.rgba(1, 1, 1, 0.10))
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        text: "nightlight"
                                        font.family: Theme.fontIcon
                                        font.pixelSize: 18
                                        color: root.nightOn ? (Theme.isDark ? "#101116" : "#ffffff") : Theme.fgDim
                                    }

                                    MouseArea {
                                        id: nightM
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.toggleNight()
                                    }
                                }

                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "Night"
                                    font.family: "Inter"
                                    font.pixelSize: 8
                                    font.weight: Font.DemiBold
                                    color: root.nightOn ? Theme.accentLit : Theme.fgDim
                                }
                            }

                            // 4. DND Toggle with M3 Abstract Shape Highlight
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignHCenter
                                spacing: 2

                                Item {
                                    Layout.alignment: Qt.AlignHCenter
                                    width: 38
                                    height: 38
                                    scale: dndM.pressed ? 0.94 : (dndM.containsMouse ? 1.08 : 1.0)
                                    Behavior on scale { NumberAnimation { duration: Theme.motionDurationShort2; easing.type: Theme.easingEmphasized } }

                                    MaterialShape {
                                        anchors.centerIn: parent
                                        width: 38
                                        height: 38
                                        shape: dndM.containsMouse ? MaterialShape.Clover4Leaf : (root.dndOn ? MaterialShape.Clover4Leaf : MaterialShape.Circle)
                                        animationDuration: 280
                                        animationEasing: Easing.OutBack
                                        color: root.dndOn ? Theme.accent : (dndM.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.20) : Qt.rgba(1, 1, 1, 0.07))
                                        strokeWidth: 1
                                        strokeColor: root.dndOn ? Qt.rgba(Theme.accentLit.r, Theme.accentLit.g, Theme.accentLit.b, 0.60) : (dndM.containsMouse ? Theme.accent : Qt.rgba(1, 1, 1, 0.10))
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        text: root.dndOn ? "do_not_disturb_on" : "notifications"
                                        font.family: Theme.fontIcon
                                        font.pixelSize: 18
                                        color: root.dndOn ? (Theme.isDark ? "#101116" : "#ffffff") : Theme.fgDim
                                    }

                                    MouseArea {
                                        id: dndM
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.toggleDnd()
                                    }
                                }

                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "DND"
                                    font.family: "Inter"
                                    font.pixelSize: 8
                                    font.weight: Font.DemiBold
                                    color: root.dndOn ? Theme.accentLit : Theme.fgDim
                                }
                            }

                            // 5. Game Toggle with M3 Abstract Shape Highlight
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignHCenter
                                spacing: 2

                                Item {
                                    Layout.alignment: Qt.AlignHCenter
                                    width: 38
                                    height: 38
                                    scale: gameM.pressed ? 0.94 : (gameM.containsMouse ? 1.08 : 1.0)
                                    Behavior on scale { NumberAnimation { duration: Theme.motionDurationShort2; easing.type: Theme.easingEmphasized } }

                                    MaterialShape {
                                        anchors.centerIn: parent
                                        width: 38
                                        height: 38
                                        shape: gameM.containsMouse ? MaterialShape.Gem : (root.gameOn ? MaterialShape.Boom : MaterialShape.Circle)
                                        animationDuration: 280
                                        animationEasing: Easing.OutBack
                                        color: root.gameOn ? Theme.accent : (gameM.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.20) : Qt.rgba(1, 1, 1, 0.07))
                                        strokeWidth: 1
                                        strokeColor: root.gameOn ? Qt.rgba(Theme.accentLit.r, Theme.accentLit.g, Theme.accentLit.b, 0.60) : (gameM.containsMouse ? Theme.accent : Qt.rgba(1, 1, 1, 0.10))
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        text: "sports_esports"
                                        font.family: Theme.fontIcon
                                        font.pixelSize: 18
                                        color: root.gameOn ? (Theme.isDark ? "#101116" : "#ffffff") : Theme.fgDim
                                    }

                                    MouseArea {
                                        id: gameM
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.toggleGame()
                                    }
                                }

                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "Game"
                                    font.family: "Inter"
                                    font.pixelSize: 8
                                    font.weight: Font.DemiBold
                                    color: root.gameOn ? Theme.accentLit : Theme.fgDim
                                }
                            }
                        }

                        MouseArea {
                            id: togglesDrag
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: 16
                            hoverEnabled: true
                            cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.SizeAllCursor
                            drag.target: cardToggles
                            drag.axis: Drag.YAxis
                            drag.minimumY: 0
                            drag.maximumY: Math.max(0, controlsContainer.height - cardToggles.height)
                            onPressed: root.activeCardDrag = "toggles"
                            onPositionChanged: {
                                if (drag.active) {
                                    root.checkCardSwap("toggles", cardToggles.y + cardToggles.height / 2)
                                }
                            }
                            onReleased: {
                                root.activeCardDrag = ""
                                cardToggles.y = Qt.binding(() => root.getTargetCardY("toggles"))
                                root.saveLayout()
                            }
                        }
                    }

                    /* 3. Modern Single-Row Studio Recorder Toolbar */
                    Rectangle {
                        id: cardRecorder
                        width: parent.width
                        height: 76
                        x: 0
                        y: root.activeCardDrag === "recorder" ? y : root.getTargetCardY("recorder")
                        radius: 18
                        color: recDrag.drag.active ? Theme.bgAlt : Qt.rgba(Theme.bgAlt.r, Theme.bgAlt.g, Theme.bgAlt.b, 0.70)
                        border.color: recDrag.drag.active ? Theme.accent : (Theme.isDark ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.08))
                        border.width: 1
                        z: recDrag.drag.active ? 50 : 1
                        scale: recDrag.drag.active ? 1.02 : 1.0
                        Behavior on scale { NumberAnimation { duration: 100 } }
                        Behavior on y {
                            enabled: root.activeCardDrag !== "recorder"
                            NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
                        }

                        opacity: root.open ? 1 : 0
                        transform: Translate {
                            y: root.open ? 0 : 4
                            Behavior on y { NumberAnimation { duration: root.open ? 130 : 80; easing.type: Easing.OutCubic } }
                        }
                        Behavior on opacity { NumberAnimation { duration: root.open ? 130 : 80; easing.type: Easing.OutCubic } }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 5

                            /* Header Row */
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 4

                                Text {
                                    text: "STUDIO TOOLBAR"
                                    font.family: "Inter"
                                    font.pixelSize: 8
                                    font.weight: Font.Bold
                                    font.letterSpacing: 1.2
                                    color: Theme.fgDim
                                }

                                Item { Layout.fillWidth: true }

                                Text {
                                    text: root.recStatus()
                                    font.family: "Inter"
                                    font.pixelSize: 8
                                    font.weight: Font.DemiBold
                                    color: (root.recWorking || root.recFail) ? "#ff7b6b" : Theme.accentLit
                                    elide: Text.ElideRight
                                }
                            }

                            /* Single-Row Action Studio Toolbar (Full-screen only) */
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 5

                                // Mic Chip
                                Rectangle {
                                    width: 26
                                    height: 26
                                    radius: 13
                                    color: root.recMic ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.25) : Qt.rgba(1, 1, 1, 0.07)
                                    border.width: 1
                                    border.color: root.recMic ? Qt.rgba(Theme.accentLit.r, Theme.accentLit.g, Theme.accentLit.b, 0.50) : Qt.rgba(1, 1, 1, 0.10)
                                    Text {
                                        anchors.centerIn: parent
                                        text: root.recMic ? "mic" : "mic_off"
                                        font.family: Theme.fontIcon
                                        font.pixelSize: 14
                                        color: root.recMic ? Theme.accentLit : Theme.fgDim
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: if (!root.recWorking) root.recMic = !root.recMic
                                    }
                                }

                                // App Audio Chip
                                Rectangle {
                                    width: 26
                                    height: 26
                                    radius: 13
                                    color: root.recApp ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.25) : Qt.rgba(1, 1, 1, 0.07)
                                    border.width: 1
                                    border.color: root.recApp ? Qt.rgba(Theme.accentLit.r, Theme.accentLit.g, Theme.accentLit.b, 0.50) : Qt.rgba(1, 1, 1, 0.10)
                                    Text {
                                        anchors.centerIn: parent
                                        text: root.recApp ? "volume_up" : "volume_off"
                                        font.family: Theme.fontIcon
                                        font.pixelSize: 14
                                        color: root.recApp ? Theme.accentLit : Theme.fgDim
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: if (!root.recWorking) root.recApp = !root.recApp
                                    }
                                }

                                // Quick Snap Chip
                                Rectangle {
                                    width: 26
                                    height: 26
                                    radius: 13
                                    color: snapH.containsMouse ? Theme.bgHover : Qt.rgba(1, 1, 1, 0.07)
                                    border.width: 1
                                    border.color: Qt.rgba(1, 1, 1, 0.10)
                                    Text {
                                        anchors.centerIn: parent
                                        text: "photo_camera"
                                        font.family: Theme.fontIcon
                                        font.pixelSize: 15
                                        color: snapH.containsMouse ? Theme.accentLit : Theme.fg
                                    }
                                    MouseArea {
                                        id: snapH
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Quickshell.execDetached(["sh", root.home + "/.config/hypr/scripts/carbon-screenshot-full.sh"])
                                    }
                                }

                                // Start / Stop Record Pill
                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 26
                                    radius: 13
                                    color: root.recWorking ? "#8f2d24" : Theme.accent
                                    scale: recBtnH.pressed ? 0.94 : (recBtnH.containsMouse ? 1.02 : 1.0)
                                    Behavior on scale { NumberAnimation { duration: Theme.motionDurationShort2; easing.type: Theme.easingEmphasized } }

                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 4
                                        Text {
                                            text: root.recWorking ? "stop_circle" : "fiber_manual_record"
                                            font.family: Theme.fontIcon
                                            font.pixelSize: 13
                                            color: root.recWorking ? "#ffffff" : "#ff3b30"
                                        }
                                        Text {
                                            text: root.recWorking ? "Stop" : "Record"
                                            font.family: "Inter"
                                            font.pixelSize: 9
                                            font.weight: Font.Bold
                                            color: root.recWorking ? "#ffffff" : (Theme.isDark ? "#101116" : "#ffffff")
                                        }
                                    }
                                    MouseArea {
                                        id: recBtnH
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.recWorking ? root.recStop() : root.recStart()
                                    }
                                }
                            }
                        }

                        MouseArea {
                            id: recDrag
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: 16
                            hoverEnabled: true
                            cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.SizeAllCursor
                            drag.target: cardRecorder
                            drag.axis: Drag.YAxis
                            drag.minimumY: 0
                            drag.maximumY: Math.max(0, controlsContainer.height - cardRecorder.height)
                            onPressed: root.activeCardDrag = "recorder"
                            onPositionChanged: {
                                if (drag.active) {
                                    root.checkCardSwap("recorder", cardRecorder.y + cardRecorder.height / 2)
                                }
                            }
                            onReleased: {
                                root.activeCardDrag = ""
                                cardRecorder.y = Qt.binding(() => root.getTargetCardY("recorder"))
                                root.saveLayout()
                            }
                        }
                    }
                            }

                            /* ── Part 2: Notifications Section Header ── */
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 22
                                Layout.leftMargin: 4
                                Layout.rightMargin: 4
                                spacing: 6

                                Text {
                                    text: "NOTIFICATIONS"
                                    font.family: "Inter"
                                    font.pixelSize: 8
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
                                        font.family: "Inter"
                                        font.pixelSize: 8
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
                                            font.family: "Inter"
                                            font.pixelSize: 8
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

                            /* ── Part 3: Empty State (if no notifications) ── */
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 52
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
                                        font.pixelSize: 18
                                        color: Qt.rgba(Theme.fgDim.r, Theme.fgDim.g, Theme.fgDim.b, 0.4)
                                    }
                                    Text {
                                        text: "No new notifications"
                                        font.family: "Inter"
                                        font.pixelSize: 9
                                        font.weight: Font.Medium
                                        color: Theme.fgDim
                                    }
                                }
                            }

                            /* ── Part 4: Notification Cards ── */
                            Repeater {
                                model: root.notifs
                                delegate: Rectangle {
                                    id: cardItem
                                    required property int index
                                    required property var modelData

                                    readonly property bool isSelected: root.selectedNotifIndex === index
                                    readonly property bool isExpanded: root.expandedNotifId === (modelData ? modelData.id : -999)

                                    Layout.fillWidth: true
                                    Layout.preferredHeight: isExpanded ? (contentCol.implicitHeight + actionRow.implicitHeight + 24) : (contentCol.implicitHeight + 14)
                                    radius: 12
                                    color: isSelected
                                        ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.22)
                                        : (cardMH.containsMouse ? Theme.bgHover : Qt.rgba(Theme.bgAlt.r, Theme.bgAlt.g, Theme.bgAlt.b, 0.70))
                                    border.width: isSelected ? 1.5 : 1
                                    border.color: isSelected
                                        ? Qt.rgba(Theme.accentLit.r, Theme.accentLit.g, Theme.accentLit.b, 0.85)
                                        : (cardMH.containsMouse ? Qt.rgba(Theme.accentLit.r, Theme.accentLit.g, Theme.accentLit.b, 0.35) : Qt.rgba(1, 1, 1, 0.10))

                                    scale: isSelected ? 1.01 : (cardMH.containsMouse ? 1.005 : 1.0)
                                    Behavior on scale { NumberAnimation { duration: Theme.motionDurationShort2; easing.type: Theme.easingEmphasized } }
                                    Behavior on Layout.preferredHeight { NumberAnimation { duration: Theme.motionDurationShort3; easing.type: Theme.easingEmphasizedDecelerate } }
                                    Behavior on color { ColorAnimation { duration: Theme.motionDurationShort2 } }
                                    Behavior on border.color { ColorAnimation { duration: Theme.motionDurationShort2 } }

                                    MouseArea {
                                        id: cardMH
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.selectedNotifIndex = index
                                            root.activateSelectedNotif()
                                        }
                                    }

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 7
                                        spacing: 4

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 8

                                            Rectangle {
                                                Layout.preferredWidth: 26
                                                Layout.preferredHeight: 26
                                                Layout.alignment: Qt.AlignTop
                                                radius: 6
                                                color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18)
                                                border.color: Qt.rgba(Theme.accentLit.r, Theme.accentLit.g, Theme.accentLit.b, 0.30)
                                                border.width: 1
                                                clip: true

                                                Image {
                                                    anchors.fill: parent
                                                    anchors.margins: 2
                                                    source: {
                                                        const icon = String(cardItem.modelData ? (cardItem.modelData.appIcon || "") : "")
                                                        return (icon.startsWith("/") || icon.startsWith("file:")) ? icon : ""
                                                    }
                                                    sourceSize: Qt.size(52, 52)
                                                    fillMode: Image.PreserveAspectFit
                                                    visible: status === Image.Ready
                                                }

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "notifications"
                                                    font.family: Theme.fontIcon
                                                    font.pixelSize: 14
                                                    color: Theme.accentLit
                                                    visible: parent.children[0].status !== Image.Ready
                                                }
                                            }

                                            ColumnLayout {
                                                id: contentCol
                                                Layout.fillWidth: true
                                                Layout.alignment: Qt.AlignVCenter
                                                spacing: 1

                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 4

                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: {
                                                            if (!cardItem.modelData) return ""
                                                            return cardItem.modelData.summary && cardItem.modelData.summary.length > 0
                                                                ? cardItem.modelData.summary
                                                                : (cardItem.modelData.appName || "Notification")
                                                        }
                                                        font.family: "Inter"
                                                        font.pixelSize: 10
                                                        font.weight: Font.Bold
                                                        color: cardItem.isSelected ? Theme.accentLit : Theme.fg
                                                        elide: Text.ElideRight
                                                    }

                                                    Text {
                                                        text: "close"
                                                        font.family: Theme.fontIcon
                                                        font.pixelSize: 13
                                                        color: dismissMH.containsMouse ? "#ff6b6b" : Theme.fgFaint
                                                        MouseArea {
                                                            id: dismissMH
                                                            anchors.fill: parent
                                                            anchors.margins: -4
                                                            hoverEnabled: true
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: {
                                                                if (cardItem.modelData && typeof cardItem.modelData.dismiss === "function") {
                                                                    cardItem.modelData.dismiss()
                                                                }
                                                            }
                                                        }
                                                    }
                                                }

                                                Text {
                                                    Layout.fillWidth: true
                                                    text: cardItem.modelData ? String(cardItem.modelData.body || "") : ""
                                                    font.family: "Inter"
                                                    font.pixelSize: 9
                                                    color: Theme.fgDim
                                                    wrapMode: Text.Wrap
                                                    maximumLineCount: cardItem.isExpanded ? 10 : 2
                                                    elide: cardItem.isExpanded ? Text.ElideNone : Text.ElideRight
                                                    visible: text.length > 0
                                                }
                                            }
                                        }

                                        RowLayout {
                                            id: actionRow
                                            Layout.fillWidth: true
                                            visible: cardItem.isExpanded
                                            spacing: 4

                                            Item { Layout.fillWidth: true }

                                            Repeater {
                                                model: (cardItem.modelData && cardItem.modelData.actions) ? cardItem.modelData.actions : []
                                                delegate: Rectangle {
                                                    required property var modelData
                                                    Layout.preferredHeight: 20
                                                    Layout.preferredWidth: actTxt.implicitWidth + 10
                                                    radius: 10
                                                    color: actMH.containsMouse ? Theme.accentLit : Theme.accent
                                                    Text {
                                                        id: actTxt
                                                        anchors.centerIn: parent
                                                        text: modelData.text || "Action"
                                                        font.family: "Inter"
                                                        font.pixelSize: 8
                                                        font.weight: Font.Bold
                                                        color: Theme.isDark ? "#101116" : "#ffffff"
                                                    }
                                                    MouseArea {
                                                        id: actMH
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: {
                                                            if (modelData && typeof modelData.invoke === "function") {
                                                                modelData.invoke()
                                                            }
                                                        }
                                                    }
                                                }
                                            }

                                            Rectangle {
                                                Layout.preferredHeight: 20
                                                Layout.preferredWidth: 50
                                                radius: 10
                                                color: disMH.containsMouse ? Theme.bgHover : Qt.rgba(1, 1, 1, 0.08)
                                                border.width: 1
                                                border.color: Theme.outline
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "Dismiss"
                                                    font.family: "Inter"
                                                    font.pixelSize: 8
                                                    font.weight: Font.Medium
                                                    color: Theme.fgDim
                                                }
                                                MouseArea {
                                                    id: disMH
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        if (cardItem.modelData && typeof cardItem.modelData.dismiss === "function") {
                                                            cardItem.modelData.dismiss()
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

                /* ==== Mode 1: to-do list ==== */
                TodoPane {
                    width: parent.width
                    height: parent.height
                    x: root.paneX(1)
                    opacity: root.mode === 1 ? 1 : 0
                    enabled: root.mode === 1
                    transform: Translate {
                        y: root.open ? 0 : 4
                        Behavior on y { NumberAnimation { duration: root.open ? 130 : 80; easing.type: Easing.OutCubic } }
                    }
                    Behavior on x {
                        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                    }
                    Behavior on opacity {
                        NumberAnimation { duration: 150; easing.type: Easing.InOutCubic }
                    }
                }

                /* ==== Mode 2: timer ==== */
                TimerPane {
                    width: parent.width
                    height: parent.height
                    x: root.paneX(2)
                    opacity: root.mode === 2 ? 1 : 0
                    enabled: root.mode === 2
                    transform: Translate {
                        y: root.open ? 0 : 4
                        Behavior on y { NumberAnimation { duration: root.open ? 130 : 80; easing.type: Easing.OutCubic } }
                    }
                    Behavior on x {
                        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                    }
                    Behavior on opacity {
                        NumberAnimation { duration: 150; easing.type: Easing.InOutCubic }
                    }
                }

                /* ==== Mode 3: weather ==== */
                WeatherPane {
                    width: parent.width
                    height: parent.height
                    x: root.paneX(3)
                    opacity: root.mode === 3 ? 1 : 0
                    enabled: root.mode === 3
                    transform: Translate {
                        y: root.open ? 0 : 4
                        Behavior on y { NumberAnimation { duration: root.open ? 130 : 80; easing.type: Easing.OutCubic } }
                    }
                    Behavior on x {
                        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                    }
                    Behavior on opacity {
                        NumberAnimation { duration: 150; easing.type: Easing.InOutCubic }
                    }
                }
            }
        }

        /* Detail popups for the Wi-Fi / Bluetooth tiles, layered over the
         * mode content (kept out of the pane's clip so they can extend it). */
        WifiPopup {
            id: wifiPopup
            anchors.horizontalCenter: card.horizontalCenter
            anchors.top: card.top
            anchors.topMargin: 40
            width: card.width - 20
            height: card.height - 48
            z: 100
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
            open: root.btPopupOpen
            powerOn: root.btOn
            btName: root.btName
            onPowerToggled: root.toggleBt()
            onRequestedClose: root.btPopupOpen = false
        }
    }
}