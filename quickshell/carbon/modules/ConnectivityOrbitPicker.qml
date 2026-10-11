import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import "../Singletons"

/**
 * ConnectivityOrbitPicker.qml
 *
 * Generic Monochrome Orbit-Orb Connectivity Picker for Carbon Shell.
 * Supports:
 * - Wi-Fi (nmcli): signal-proportional orbits (118 - sig*52 px), 12-dot keyboard password ring,
 *   connecting spinner, 800ms rose flash on wrong password, electron curve & pulse on success.
 * - Bluetooth (BlueZ D-Bus via carbon-bluetooth.py):
 *   Two orbits: paired/known devices on inner orbit (~66px) and discovered devices on outer orbit (~112px, RSSI modulated).
 *   Stable MAC-hashed angles (never jump), live battery arcs (accent color), device type icons (headphones, speaker, phone, etc.),
 *   scanning spinner arc around nucleus, connecting spinner, success electron curve & pulse ring, 800ms rose failure flash,
 *   BlueZ 6-digit passkey confirmation agent (no dialogs), long-press to forget with 1s filling ring,
 *   adapter state handling (bluetooth off / power on via nucleus tap, no adapter),
 *   optional auto-switch audio output on headset connect.
 */
Item {
    id: root

    /* ── Configuration & Token Defaults ── */
    property int wifiOrbitBase: Theme.wifiOrbitBase || 118
    property int wifiOrbitFactor: Theme.wifiOrbitFactor || 52
    property int guideRingInner: Theme.guideRingInner || 70
    property int guideRingOuter: Theme.guideRingOuter || 105
    property int btInnerRadius: Theme.btInnerRadius || 66
    property int btOuterRadius: Theme.btOuterRadius || 112
    property int scanInterval: Theme.connectivityScanInterval || 8000
    property bool reducedMotion: Theme.reducedMotion || false
    property bool autoSwitchAudio: Theme.bluetoothHeadsetDefaultAudio || false

    /* ── Mode & State Machine ── */
    // pickerMode: "none" | "wifi" | "bluetooth"
    property string pickerMode: "none"
    // state: "idle" | "list" | "pass" | "connecting" | "confirm_passkey" | "done"
    property string state: "idle"

    /* ── Selection & Caption Communication ── */
    property var selectedItem: null
    property var hoveredItem: null
    property string statusMessage: ""
    property string pendingPasskey: ""
    property string pendingMac: ""
    property string failedMac: ""
    property real failureFlashOpacity: 0.0

    readonly property string captionText: {
        if (root.pickerMode === "bluetooth") {
            if (!root.btAdapterAvailable) return "no bluetooth adapter"
            if (!root.btPowered) return "bluetooth off / tap nucleus to power on"
            if (root.isLoading) return "searching for devices…"
            if (root.state === "confirm_passkey") {
                return "confirm passkey: " + root.pendingPasskey + " / tap orb to confirm, tap nucleus to cancel"
            }
            if (root.state === "connecting") {
                var targetB = root.selectedItem ? (root.selectedItem.name || root.selectedItem.mac) : ""
                return "connecting to " + targetB + "…"
            }
            if (root.statusMessage.length > 0) return root.statusMessage
            var activeB = root.hoveredItem || root.selectedItem
            if (activeB) {
                var bType = activeB.deviceType || "device"
                var bState = activeB.connected ? "connected" : (activeB.paired ? "paired" : "discovered")
                var batStr = (activeB.battery !== undefined && activeB.battery >= 0) ? (" / " + activeB.battery + "%") : ""
                var bTail = activeB.connected ? "tap again to disconnect" : (activeB.paired ? "tap again to connect" : "tap again to pair")
                return activeB.name + " / " + bType + " / " + bState + batStr + " / " + bTail
            }
            if (root.btList.length === 0) {
                return root.btScanning ? "discovering devices…" : "no bluetooth devices found"
            }
            return root.btScanning ? "select a device / discovering…" : "select a device / tap nucleus to exit"
        }

        // Wi-Fi
        if (root.isLoading) {
            return "searching for networks…"
        }
        if (root.state === "pass") {
            if (root.wrongPasswordActive) return "wrong password / try again"
            return "enter password / Enter to connect / Esc to cancel"
        }
        if (root.state === "connecting") {
            var targetW = root.selectedItem ? (root.selectedItem.ssid || root.selectedItem.name || "") : ""
            return "connecting to " + targetW + "…"
        }
        if (root.statusMessage.length > 0) return root.statusMessage

        var activeW = root.hoveredItem || root.selectedItem
        if (activeW) {
            var sec = activeW.isSecured ? "secured" : "open"
            var tailW = (root.selectedItem === activeW) ? "tap again to connect" : "tap to select"
            return activeW.ssid + " / " + sec + " / " + activeW.signal + "% / " + tailW
        }

        if (root.wifiList.length === 0 && !root.wifiScanning) return "no wi-fi networks found"
        return "select a network / tap nucleus to exit"
    }

    /* Signals to parent (NucleusHub) */
    signal backRequested()
    signal connectSuccess()

    /* ── Colors (Strict Monochrome + Halo Accent) ── */
    readonly property color colAccent: Theme.accent || "#00F0FF"
    readonly property color colErr: Theme.err || "#f87171"
    readonly property color colWhite: "#FFFFFF"
    readonly property color colFg: Theme.fg || "#e6e4f0"
    readonly property color colFgDim: Theme.fgDim || "#94a3b8"
    readonly property color colBgDark: Theme.bg || "#0e0e14"

    /* ── Internal Models ── */
    property var wifiList: []
    property var wifiStagedList: []
    property bool wifiScanning: false
    property var btList: []
    property var btRawList: []
    property bool btScanning: false
    property bool btAdapterAvailable: true
    property bool btPowered: true

    /* Password Input Buffer */
    property string passwordBuffer: ""
    property bool wrongPasswordActive: false

    /* Loading & Animation State */
    property bool isLoading: false
    property real animPhase: 0.0
    property var savedWifiConnections: []
    property double connectStartTime: 0.0

    FrameAnimation {
        running: !root.reducedMotion && (root.isLoading || root.wifiScanning || root.btScanning || root.state === "connecting")
        onTriggered: {
            root.animPhase = (root.animPhase + frameTime * 240.0) % 360.0
        }
    }

    Timer {
        id: wifiLoadTimer
        interval: 1800
        repeat: false
        onTriggered: {
            root.wifiList = root.wifiStagedList
            root.isLoading = false
        }
    }

    Timer {
        id: btLoadTimer
        interval: 2200
        repeat: false
        onTriggered: {
            root.btList = root.btRawList
            root.isLoading = false
        }
    }

    Timer {
        id: delayClearStatusTimer
        interval: 3200
        repeat: false
        onTriggered: {
            root.statusMessage = ""
        }
    }

    NumberAnimation {
        id: failureFlashAnim
        target: root
        property: "failureFlashOpacity"
        from: 1.0
        to: 0.0
        duration: 800
        easing.type: Easing.OutCubic
    }

    /* Success Animation Props */
    property real successStartX: 0.0
    property real successStartY: -96.0
    property real electronProgress: 0.0
    property real pulseProgress: 0.0
    property bool showSuccessEffects: false

    function triggerSuccessAnimation(sx, sy) {
        root.successStartX = (sx !== undefined && sx !== null) ? sx : 0.0
        root.successStartY = (sy !== undefined && sy !== null) ? sy : -96.0
        root.showSuccessEffects = true
        root.electronProgress = 0.0
        root.pulseProgress = 0.0
        successSeq.restart()
    }

    SequentialAnimation {
        id: successSeq
        ParallelAnimation {
            NumberAnimation {
                target: root
                property: "electronProgress"
                from: 0.0
                to: 1.0
                duration: 700
                easing.type: Easing.InOutCubic
            }
            SequentialAnimation {
                PauseAnimation { duration: 240 }
                NumberAnimation {
                    target: root
                    property: "pulseProgress"
                    from: 0.0
                    to: 1.0
                    duration: 600
                    easing.type: Easing.OutCubic
                }
            }
        }
        PauseAnimation { duration: 320 }
        ScriptAction {
            script: {
                root.showSuccessEffects = false
                root.electronProgress = 0.0
                root.pulseProgress = 0.0
                root.state = "list"
                root.connectSuccess()
            }
        }
    }

    /* ── Lifecycle Management ── */
    function openWifi() {
        root.stopBluetoothBackend()
        root.pickerMode = "wifi"
        root.state = "list"
        root.selectedItem = null
        root.hoveredItem = null
        root.statusMessage = ""
        root.passwordBuffer = ""
        root.wrongPasswordActive = false
        root.showSuccessEffects = false
        root.wifiList = []
        root.wifiStagedList = []
        root.isLoading = true
        btLoadTimer.stop()
        wifiLoadTimer.restart()
        if (!wifiSavedProc.running) {
            wifiSavedProc.running = true
        }
        root.rescanWifi()
    }

    function openBluetooth() {
        root.pickerMode = "bluetooth"
        root.state = "list"
        root.selectedItem = null
        root.hoveredItem = null
        root.statusMessage = ""
        root.pendingPasskey = ""
        root.pendingMac = ""
        root.failedMac = ""
        root.failureFlashOpacity = 0.0
        root.showSuccessEffects = false
        root.btList = []
        root.btRawList = []
        root.isLoading = true
        wifiLoadTimer.stop()
        btLoadTimer.restart()
        root.startBluetoothBackend()
    }

    function closePicker() {
        root.stopBluetoothBackend()
        root.isLoading = false
        wifiLoadTimer.stop()
        btLoadTimer.stop()
        delayClearStatusTimer.stop()
        connectGuardTimer.stop()
        failureFlashAnim.stop()
        root.pickerMode = "none"
        root.state = "idle"
        root.selectedItem = null
        root.hoveredItem = null
        root.statusMessage = ""
        root.passwordBuffer = ""
        root.wrongPasswordActive = false
        root.pendingPasskey = ""
        root.pendingMac = ""
        root.showSuccessEffects = false
        root.wifiList = []
        root.wifiStagedList = []
        root.btList = []
        root.btRawList = []
    }

    function goBack() {
        if (root.state === "confirm_passkey") {
            root.sendBtCmd({ "action": "cancel_passkey" })
            root.state = "list"
            root.pendingPasskey = ""
            root.pendingMac = ""
            return
        }
        if (root.pickerMode === "bluetooth" && !root.btPowered && root.btAdapterAvailable) {
            root.sendBtCmd({ "action": "power_on" })
            return
        }
        if (root.state === "pass") {
            root.state = "list"
            root.passwordBuffer = ""
            root.wrongPasswordActive = false
            keyScope.focus = false
            return
        }
        if (root.state === "list" || root.state === "connecting" || root.state === "done") {
            root.closePicker()
            root.backRequested()
        }
    }

    /* ══════════════════════════════════════════════════════════════════════
       WIFI BACKEND (nmcli)
       ══════════════════════════════════════════════════════════════════════ */
    function shellQuote(s) {
        return "'" + String(s).replace(/'/g, "'\\''") + "'"
    }

    Process {
        id: wifiSavedProc
        command: ["nmcli", "-t", "-f", "NAME,TYPE", "connection", "show"]
        stdout: StdioCollector {
            id: wifiSavedOut
            waitForEnd: true
        }
        onExited: {
            var lines = String(wifiSavedOut.text).split("\n")
            var saved = []
            for (var i = 0; i < lines.length; i++) {
                var l = lines[i].trim()
                if (!l) continue
                var p = l.split(":")
                if (p.length >= 2 && p[1] === "802-11-wireless") {
                    saved.push(p[0])
                }
            }
            root.savedWifiConnections = saved
        }
    }

    Process {
        id: wifiScanProc
        command: ["nmcli", "-t", "-f", "IN-USE,SIGNAL,SECURITY,SSID", "dev", "wifi", "list", "--rescan", "auto"]
        stdout: StdioCollector {
            id: wifiScanOut
            waitForEnd: true
        }
        onExited: {
            root.wifiScanning = false
            root.parseWifiOutput(String(wifiScanOut.text))
            if (!wifiLoadTimer.running) {
                root.wifiList = root.wifiStagedList
                root.isLoading = false
            }
        }
    }

    Timer {
        id: wifiRescanTimer
        interval: root.scanInterval
        repeat: true
        running: root.pickerMode === "wifi" && root.state === "list"
        onTriggered: {
            if (!wifiScanProc.running) {
                root.rescanWifi()
            }
        }
    }

    function rescanWifi() {
        if (wifiScanProc.running) return
        root.wifiScanning = true
        wifiScanProc.running = true
    }

    function parseWifiOutput(raw) {
        var lines = raw.split("\n")
        var seen = {}
        var list = []

        for (var i = 0; i < lines.length; i++) {
            var line = lines[i].trim()
            if (!line) continue
            var parts = line.split(":")
            if (parts.length < 4) continue

            var inUse = parts[0].trim() === "*"
            var sig = parseInt(parts[1].trim(), 10) || 20
            var secStr = parts[2].trim()
            var ssid = parts.slice(3).join(":").trim()

            if (!ssid) continue
            var isSec = (secStr.length > 0 && secStr !== "--")
            var isSaved = root.savedWifiConnections.indexOf(ssid) !== -1

            if (seen[ssid]) {
                if (sig > seen[ssid].signal) {
                    seen[ssid].signal = sig
                    seen[ssid].connected = seen[ssid].connected || inUse
                }
                continue
            }

            var item = {
                ssid: ssid,
                signal: sig,
                isSecured: isSec,
                isSaved: isSaved,
                connected: inUse,
                isWifi: true
            }
            seen[ssid] = item
            list.push(item)
        }

        list.sort(function(a, b) {
            if (a.connected !== b.connected) return a.connected ? -1 : 1
            return b.signal - a.signal
        })

        if (list.length > 14) list = list.slice(0, 14)

        var total = list.length
        for (var idx = 0; idx < total; idx++) {
            var it = list[idx]
            var normSig = Math.max(0.0, Math.min(1.0, it.signal / 100.0))
            it.orbitRadius = Math.round(root.wifiOrbitBase - (normSig * root.wifiOrbitFactor))
            it.orbRadius = Math.round(11 + (normSig * 8))
            it.angleDeg = idx * (360.0 / Math.max(1, total))
        }

        if (root.isLoading) {
            root.wifiStagedList = list
        } else {
            root.wifiList = list
        }
    }

    property bool pendingConnectSuccess: false

    Timer {
        id: connectGuardTimer
        repeat: false
        onTriggered: {
            if (root.pendingConnectSuccess) {
                root.state = "done"
                root.passwordBuffer = ""
                root.wrongPasswordActive = false
                root.triggerSuccessAnimation(0.0, -96.0)
            } else {
                root.state = "pass"
                root.passwordBuffer = ""
                root.wrongPasswordActive = true
                wrongPasswordTimer.restart()
                root.statusMessage = "connection failed / try again"
            }
        }
    }

    Process {
        id: wifiConnectProc
        stdout: StdioCollector { id: wifiConnOut; waitForEnd: true }
        stderr: StdioCollector { id: wifiConnErr; waitForEnd: true }
        onExited: {
            var isSuccess = (exitCode === 0)
            root.pendingConnectSuccess = isSuccess
            var elapsed = Date.now() - root.connectStartTime
            var remaining = Math.max(0, 1400 - elapsed)
            if (remaining > 0) {
                connectGuardTimer.interval = remaining
                connectGuardTimer.restart()
            } else {
                if (isSuccess) {
                    root.state = "done"
                    root.passwordBuffer = ""
                    root.wrongPasswordActive = false
                    root.triggerSuccessAnimation(0.0, -96.0)
                } else {
                    root.state = "pass"
                    root.passwordBuffer = ""
                    root.wrongPasswordActive = true
                    wrongPasswordTimer.restart()
                    root.statusMessage = "connection failed / try again"
                }
            }
        }
    }

    Timer {
        id: wrongPasswordTimer
        interval: 800
        repeat: false
        onTriggered: {
            root.wrongPasswordActive = false
        }
    }

    function connectWifi(item, password) {
        root.state = "connecting"
        root.connectStartTime = Date.now()
        var cmd = ""
        if (item.isSaved && (!password || password.length === 0)) {
            cmd = "nmcli connection up id " + root.shellQuote(item.ssid)
        } else if (item.isSecured && password && password.length > 0) {
            cmd = "nmcli dev wifi connect " + root.shellQuote(item.ssid) + " password " + root.shellQuote(password)
        } else {
            cmd = "nmcli dev wifi connect " + root.shellQuote(item.ssid)
        }
        wifiConnectProc.command = ["sh", "-c", cmd]
        wifiConnectProc.running = true
    }

    /* ══════════════════════════════════════════════════════════════════════
       BLUETOOTH BACKEND (BlueZ D-Bus via carbon-bluetooth.py)
       ══════════════════════════════════════════════════════════════════════ */
    Process {
        id: btDaemonProc
        command: ["python3", (Quickshell.env("CARBON_CONFIG_DIR") || ((Quickshell.env("HOME") || "") + "/.config/carbon")) + "/scripts/carbon-bluetooth.py"]
        stdinEnabled: true
        running: false

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) {
                root.handleBtDaemonLine(line.trim())
            }
        }

        onExited: {
            root.btScanning = false
        }
    }

    function startBluetoothBackend() {
        if (!btDaemonProc.running) {
            btDaemonProc.running = true
        }
        sendBtCmd({ "action": "set_auto_switch_audio", "enabled": root.autoSwitchAudio })
    }

    function stopBluetoothBackend() {
        if (btDaemonProc.running) {
            sendBtCmd({ "action": "stop" })
            btDaemonProc.running = false
        }
        root.btScanning = false
    }

    function sendBtCmd(obj) {
        if (btDaemonProc.running) {
            try {
                btDaemonProc.write(JSON.stringify(obj) + "\n")
            } catch (e) {
                console.log("[ConnectivityPicker] sendBtCmd error:", e)
            }
        }
    }

    function handleBtDaemonLine(line) {
        if (!line) return
        var data
        try {
            data = JSON.parse(line)
        } catch (e) {
            return
        }

        if (data.type === "adapter_state") {
            root.btAdapterAvailable = data.available
            root.btPowered = data.powered
            if (!data.available || !data.powered) {
                root.btScanning = false
            }
        } else if (data.type === "scan_state") {
            root.btScanning = data.scanning
        } else if (data.type === "devices") {
            var rawList = data.list || []
            for (var i = 0; i < rawList.length; i++) {
                rawList[i].isWifi = false
            }
            root.btRawList = rawList
            if (!root.isLoading) {
                root.btList = rawList
            }
        } else if (data.type === "passkey_request") {
            root.state = "confirm_passkey"
            root.pendingPasskey = String(data.passkey || "")
            root.pendingMac = String(data.mac || "")
        } else if (data.type === "passkey_cancelled") {
            if (root.state === "confirm_passkey") {
                root.state = "list"
                root.pendingPasskey = ""
                root.pendingMac = ""
            }
        } else if (data.type === "action_result") {
            if (data.success) {
                if (data.action === "connect" || data.action === "pair") {
                    root.state = "done"
                    var targetX = 0.0
                    var targetY = -66.0
                    if (root.selectedItem) {
                        var rad = (root.selectedItem.angleDeg || 0.0) * (Math.PI / 180.0)
                        targetX = root.selectedItem.orbitRadius * Math.cos(rad)
                        targetY = root.selectedItem.orbitRadius * Math.sin(rad)
                    }
                    root.triggerSuccessAnimation(targetX, targetY)
                } else if (data.action === "disconnect" || data.action === "forget") {
                    root.state = "list"
                    root.selectedItem = null
                }
            } else {
                root.state = "list"
                root.failedMac = String(data.mac || "")
                failureFlashAnim.restart()
                root.statusMessage = "connection failed: " + (data.error || "rejected")
                delayClearStatusTimer.restart()
            }
        }
    }

    /* ══════════════════════════════════════════════════════════════════════
       KEYBOARD LISTENER (Password Input in Wi-Fi 'pass' State)
       ══════════════════════════════════════════════════════════════════════ */
    Item {
        id: keyScope
        focus: root.pickerMode === "wifi" && root.state === "pass"

        Keys.onEscapePressed: {
            root.goBack()
        }
        Keys.onReturnPressed: {
            if (root.selectedItem && root.passwordBuffer.length > 0) {
                root.connectWifi(root.selectedItem, root.passwordBuffer)
            }
        }
        Keys.onEnterPressed: {
            if (root.selectedItem && root.passwordBuffer.length > 0) {
                root.connectWifi(root.selectedItem, root.passwordBuffer)
            }
        }
        Keys.onBackPressed: {
            if (root.passwordBuffer.length > 0) {
                root.passwordBuffer = root.passwordBuffer.slice(0, -1)
            }
        }
        Keys.onDeletePressed: {
            if (root.passwordBuffer.length > 0) {
                root.passwordBuffer = root.passwordBuffer.slice(0, -1)
            }
        }
        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Backspace) {
                if (root.passwordBuffer.length > 0) {
                    root.passwordBuffer = root.passwordBuffer.slice(0, -1)
                }
                event.accepted = true
                return
            }
            if (event.text && event.text.length > 0 && (!event.modifiers || event.modifiers === Qt.ShiftModifier)) {
                root.passwordBuffer += event.text
                event.accepted = true
            }
        }
    }

    onStateChanged: {
        if (root.state === "pass") {
            Qt.callLater(() => keyScope.forceActiveFocus())
        }
    }

    /* ══════════════════════════════════════════════════════════════════════
       VISUAL RENDERING: GUIDE RINGS, SCANNER SPINNER, ORBS, 12-DOT PASS RING
       ══════════════════════════════════════════════════════════════════════ */
    Item {
        id: visualContainer
        anchors.centerIn: parent
        visible: root.pickerMode !== "none"

        /* ── Faint Concentric Orbit Guide Rings (Celestial / Bohr Model Abstractness) ── */
        Item {
            id: guideRingsLayer
            anchors.centerIn: parent
            visible: !root.isLoading && !root.showSuccessEffects && (root.pickerMode === "wifi" || root.pickerMode === "bluetooth")
            opacity: visible ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }

            // Inner Orbit Guide Ring
            Rectangle {
                anchors.centerIn: parent
                width: ((root.pickerMode === "bluetooth") ? root.btInnerRadius : root.guideRingInner) * 2
                height: width
                radius: width / 2
                color: "transparent"
                border.color: Qt.rgba(1, 1, 1, 0.09)
                border.width: 1.0
                Behavior on width { NumberAnimation { duration: 340; easing.type: Easing.OutCubic } }
            }

            // Outer Orbit Guide Ring
            Rectangle {
                anchors.centerIn: parent
                width: ((root.pickerMode === "bluetooth") ? root.btOuterRadius : root.guideRingOuter) * 2
                height: width
                radius: width / 2
                color: "transparent"
                border.color: Qt.rgba(1, 1, 1, 0.06)
                border.width: 1.0
                Behavior on width { NumberAnimation { duration: 340; easing.type: Easing.OutCubic } }
            }
        }

        /* ── Thin Scanning Spinner Arc around Nucleus ── */
        Item {
            id: nucleusScanningSpinner
            anchors.centerIn: parent
            width: 58
            height: 58
            visible: (root.wifiScanning || root.btScanning) && !root.isLoading
            opacity: visible ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
            rotation: root.animPhase

            Canvas {
                anchors.fill: parent
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.reset()
                    ctx.lineWidth = 1.2
                    ctx.strokeStyle = root.colAccent
                    ctx.beginPath()
                    // r = 28 (width=58), sweep 60 degrees (Math.PI / 3)
                    ctx.arc(29, 29, 28, 0, Math.PI / 3, false)
                    ctx.stroke()
                }
            }
        }

        /* ── Bohr Valence Electron Loading Orbs (Only on Initial Loading Screen) ── */
        Item {
            id: scanningOrbitSystem
            anchors.centerIn: parent
            width: 1
            height: 1
            visible: (root.pickerMode === "bluetooth" || root.pickerMode === "wifi") && root.isLoading
            opacity: visible ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
            rotation: (root.animPhase * 0.15) % 360.0

            Item {
                x: -width / 2
                y: -root.guideRingInner - height / 2
                width: 22
                height: 22

                Rectangle {
                    anchors.centerIn: parent
                    width: 20; height: 20; radius: 10
                    color: Qt.rgba(root.colAccent.r, root.colAccent.g, root.colAccent.b, 0.38)
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: 12; height: 12; radius: 6
                    color: root.colWhite
                    border.width: 1.5
                    border.color: root.colAccent

                    Rectangle {
                        anchors.centerIn: parent
                        width: 4; height: 4; radius: 2
                        color: root.colAccent
                    }
                }
            }

            Item {
                x: -width / 2
                y: root.guideRingInner - height / 2
                width: 22
                height: 22

                Rectangle {
                    anchors.centerIn: parent
                    width: 20; height: 20; radius: 10
                    color: Qt.rgba(root.colAccent.r, root.colAccent.g, root.colAccent.b, 0.38)
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: 12; height: 12; radius: 6
                    color: root.colWhite
                    border.width: 1.5
                    border.color: root.colAccent

                    Rectangle {
                        anchors.centerIn: parent
                        width: 4; height: 4; radius: 2
                        color: root.colAccent
                    }
                }
            }
        }

        /* ── Thin Bond Line from Selected Orb to Nucleus upon Success ── */
        Shape {
            visible: root.showSuccessEffects
            anchors.fill: parent
            ShapePath {
                strokeColor: Qt.rgba(1, 1, 1, 0.40)
                strokeWidth: 1.6
                startX: root.successStartX
                startY: root.successStartY
                PathLine { x: 0; y: 0 }
            }
        }

        /* ── Pulse Ring Expanding from Nucleus on Success (600ms) ── */
        Rectangle {
            visible: root.showSuccessEffects && root.pulseProgress > 0.001
            anchors.centerIn: parent
            width: 38 + (root.pulseProgress * 110)
            height: 38 + (root.pulseProgress * 110)
            radius: width / 2
            color: "transparent"
            border.color: Qt.rgba(1, 1, 1, (1.0 - root.pulseProgress) * 0.85)
            border.width: 2.0
        }

        /* ── Success Electron Travelling along Curve into Nucleus (700ms) ── */
        Item {
            id: successElectron
            visible: root.showSuccessEffects && root.electronProgress < 0.999
            readonly property real ep: root.electronProgress
            readonly property real curX: root.successStartX * (1.0 - ep) + Math.sin(ep * Math.PI) * 16.0
            readonly property real curY: root.successStartY * (1.0 - ep)

            x: curX - 4
            y: curY - 4
            width: 8
            height: 8

            Rectangle {
                anchors.fill: parent
                radius: 4
                color: root.colWhite
            }

            Rectangle {
                x: -Math.sin(successElectron.ep * Math.PI) * 3
                y: -4
                width: 5
                height: 5
                radius: 2.5
                color: Qt.rgba(1, 1, 1, 0.5)
            }
        }

        /* ── 12-Dot Password Ring around Selected Orb in Wi-Fi 'pass' State ── */
        Item {
            id: dotRingSystem
            x: 0
            y: -96
            visible: root.pickerMode === "wifi" && (root.state === "pass" || root.state === "connecting" || root.state === "done")

            Item {
                anchors.centerIn: parent
                width: 88
                height: 88
                visible: root.state === "connecting"
                rotation: root.animPhase

                Canvas {
                    anchors.fill: parent
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.reset()
                        ctx.lineWidth = 2.0
                        ctx.strokeStyle = root.colAccent
                        ctx.beginPath()
                        ctx.arc(44, 44, 42, 0, Math.PI * 0.9, false)
                        ctx.stroke()
                    }
                }
            }

            Repeater {
                model: 12
                delegate: Item {
                    id: dotDelegate
                    required property int index
                    readonly property real angleDeg: index * 30.0
                    readonly property real rad: angleDeg * (Math.PI / 180.0)
                    readonly property real dotRadius: 38

                    readonly property bool isLit: {
                        if (root.showSuccessEffects) return true
                        var len = root.passwordBuffer.length
                        if (len === 0) return false
                        return index < len
                    }

                    x: (dotRadius * Math.cos(rad)) - width / 2
                    y: (dotRadius * Math.sin(rad)) - height / 2
                    width: isLit ? 6 : 4
                    height: isLit ? 6 : 4
                    Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                    Behavior on height { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: {
                            if (root.wrongPasswordActive) return root.colErr
                            if (dotDelegate.isLit) return root.colWhite
                            return Qt.rgba(1, 1, 1, 0.22)
                        }
                        Behavior on color { ColorAnimation { duration: 160 } }
                    }
                }
            }
        }

        /* ── Active Orbs (WiFi or Bluetooth) ── */
        Repeater {
            model: (!root.isLoading && root.pickerMode === "wifi") ? root.wifiList : ((!root.isLoading && root.pickerMode === "bluetooth") ? root.btList : [])
            delegate: Item {
                id: orbDelegate
                required property int index
                required property var modelData

                readonly property bool isThisSelected: root.selectedItem === modelData
                readonly property bool inPassMode: (root.pickerMode === "wifi") && (root.state === "pass" || root.state === "connecting" || root.state === "done")

                // Target Coordinates:
                readonly property real idleAngleOffset: 0.0
                readonly property real idleDistOffset: 0.0

                readonly property real finalAngleDeg: (modelData.angleDeg || 0.0) + (isThisSelected ? 0.0 : idleAngleOffset)
                readonly property real baseRad: finalAngleDeg * (Math.PI / 180.0)
                readonly property real finalRadius: (modelData.orbitRadius || 80) + (isThisSelected ? 0.0 : idleDistOffset)
                readonly property real targetX: (inPassMode && isThisSelected) ? 0.0 : (finalRadius * Math.cos(baseRad))
                readonly property real targetY: (inPassMode && isThisSelected) ? -96.0 : (finalRadius * Math.sin(baseRad))
                readonly property real targetD: (inPassMode && isThisSelected) ? 52.0 : ((modelData.orbRadius || 17) * 2)

                // Dynamic Scale & Opacity per specifications (hover expands to 1.15, others shrink to 0.88 and dim to 0.65):
                readonly property bool isThisHovered: orbMouse.containsMouse || (root.hoveredItem === modelData)
                readonly property bool isAnyHovered: root.hoveredItem !== null
                readonly property real targetScale: (inPassMode && !isThisSelected) 
                    ? 0.4 
                    : (isThisHovered ? 1.15 : (isAnyHovered && !isThisSelected ? 0.88 : 1.0))
                readonly property real targetAlpha: (inPassMode && !isThisSelected) 
                    ? 0.0 
                    : (isAnyHovered && !isThisHovered && !isThisSelected ? 0.65 : 1.0)

                // Staggered Spawning Animation (55ms stagger)
                property real spawnProgress: 0.0
                Component.onCompleted: {
                    if (root.reducedMotion) {
                        spawnProgress = 1.0
                    } else {
                        spawnTimer.restart()
                    }
                }

                Timer {
                    id: spawnTimer
                    interval: Math.max(10, index * 55)
                    repeat: false
                    onTriggered: spawnAnim.restart()
                }

                NumberAnimation {
                    id: spawnAnim
                    target: orbDelegate
                    property: "spawnProgress"
                    from: 0.0
                    to: 1.0
                    duration: 320
                    easing.type: Easing.OutCubic
                }

                // Long-press to forget state
                property bool forgetPending: false
                property real forgetFillProgress: 0.0

                NumberAnimation {
                    id: forgetFillAnim
                    target: orbDelegate
                    property: "forgetFillProgress"
                    from: 0.0
                    to: 1.0
                    duration: 1000
                    easing.type: Easing.Linear
                    onFinished: {
                        if (orbDelegate.forgetFillProgress >= 0.99) {
                            root.sendBtCmd({ "action": "forget", "mac": modelData.mac })
                            orbDelegate.forgetPending = false
                            orbDelegate.forgetFillProgress = 0.0
                            root.statusMessage = "forgot " + modelData.name
                            delayClearStatusTimer.restart()
                        }
                    }
                }

                Timer {
                    id: firstHoldTimer
                    interval: 700
                    repeat: false
                    onTriggered: {
                        orbDelegate.forgetPending = true
                        root.statusMessage = "forget " + modelData.name + "? / hold again to confirm"
                        delayClearStatusTimer.restart()
                    }
                }

                x: targetX - width / 2
                y: targetY - height / 2
                width: targetD
                height: targetD
                scale: targetScale * (0.3 + 0.7 * spawnProgress)
                opacity: targetAlpha * Math.min(1.0, spawnProgress * 1.5)

                Behavior on x { NumberAnimation { duration: 340; easing.type: Easing.OutCubic } }
                Behavior on y { NumberAnimation { duration: 340; easing.type: Easing.OutCubic } }
                Behavior on width { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                Behavior on height { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                Behavior on scale { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

                // Selection White Ring
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width + 8
                    height: parent.height + 8
                    radius: width / 2
                    color: "transparent"
                    border.color: root.colWhite
                    border.width: 1.6
                    visible: orbDelegate.isThisSelected && !orbDelegate.inPassMode
                    opacity: orbDelegate.isThisSelected ? 1.0 : 0.0
                    Behavior on opacity { NumberAnimation { duration: 160 } }
                }

                // Connecting Spinner Arc around target orb
                Item {
                    anchors.centerIn: parent
                    width: parent.width + 8
                    height: parent.height + 8
                    visible: root.state === "connecting" && orbDelegate.isThisSelected
                    rotation: root.animPhase

                    Canvas {
                        anchors.fill: parent
                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.reset()
                            ctx.lineWidth = 1.8
                            ctx.strokeStyle = root.colAccent
                            ctx.beginPath()
                            ctx.arc(width / 2, height / 2, width / 2 - 2, 0, Math.PI * 0.8, false)
                            ctx.stroke()
                        }
                    }
                }

                // Battery Arc Indicator (Thin arc 0-100% in accent color)
                Canvas {
                    id: batteryArc
                    anchors.centerIn: parent
                    width: parent.width + 6
                    height: parent.height + 6
                    visible: root.pickerMode === "bluetooth" && modelData.battery !== undefined && modelData.battery >= 0
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.reset()
                        if (modelData.battery === undefined || modelData.battery < 0) return
                        var pct = Math.max(0.0, Math.min(1.0, modelData.battery / 100.0))
                        ctx.lineWidth = 1.5
                        ctx.strokeStyle = root.colAccent
                        ctx.beginPath()
                        var startAngle = -Math.PI / 2
                        ctx.arc(width / 2, height / 2, width / 2 - 1.5, startAngle, startAngle + (pct * 2 * Math.PI), false)
                        ctx.stroke()
                    }
                }

                // Long-Press Forget Progress Arc
                Canvas {
                    id: forgetProgressArc
                    anchors.centerIn: parent
                    width: parent.width + 10
                    height: parent.height + 10
                    visible: orbDelegate.forgetFillProgress > 0.005
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.reset()
                        ctx.lineWidth = 2.0
                        ctx.strokeStyle = root.colErr
                        ctx.beginPath()
                        var startAngle = -Math.PI / 2
                        ctx.arc(width / 2, height / 2, width / 2 - 2, startAngle, startAngle + (orbDelegate.forgetFillProgress * 2 * Math.PI), false)
                        ctx.stroke()
                    }
                }

                Connections {
                    target: orbDelegate
                    function onForgetFillProgressChanged() {
                        forgetProgressArc.requestPaint()
                    }
                }

                // Main Orb Body
                Rectangle {
                    id: orbBody
                    anchors.fill: parent
                    radius: width / 2
                    color: modelData.connected 
                           ? root.colWhite 
                           : (orbMouse.containsMouse 
                              ? Qt.rgba(root.colAccent.r, root.colAccent.g, root.colAccent.b, 0.22) 
                              : Qt.rgba(root.colBgDark.r, root.colBgDark.g, root.colBgDark.b, 0.94))
                    border.color: modelData.connected 
                                  ? root.colWhite 
                                  : (orbMouse.containsMouse 
                                     ? root.colAccent 
                                     : (modelData.paired ? root.colWhite : Qt.rgba(1, 1, 1, 0.35)))
                    border.width: modelData.connected ? 1.0 : (modelData.paired ? 1.6 : 1.2)

                    // Failure Rose Flash
                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: root.colErr
                        visible: (root.failedMac === modelData.mac && root.failureFlashOpacity > 0.01)
                        opacity: root.failureFlashOpacity
                    }

                    // Glyph Text Icon
                    Text {
                        anchors.centerIn: parent
                        text: {
                            if (root.pickerMode === "wifi") {
                                return modelData.isSecured ? "lock" : "wifi"
                            }
                            var dt = modelData.deviceType || "generic"
                            if (dt === "headphones") return "headphones"
                            if (dt === "speaker") return "speaker"
                            if (dt === "phone") return "smartphone"
                            if (dt === "watch") return "watch"
                            if (dt === "keyboard") return "keyboard"
                            if (dt === "mouse") return "mouse"
                            if (dt === "gamepad") return "sports_esports"
                            return "bluetooth"
                        }
                        font.family: Theme.fontIcon
                        font.pixelSize: (orbDelegate.inPassMode && orbDelegate.isThisSelected) ? 22 : Math.max(12, Math.round(parent.width * 0.48))
                        color: modelData.connected ? "#0b0e14" : (modelData.paired ? root.colWhite : root.colFgDim)
                    }

                    MouseArea {
                        id: orbMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor

                        onEntered: {
                            root.hoveredItem = modelData
                        }
                        onExited: {
                            if (root.hoveredItem === modelData) root.hoveredItem = null
                        }

                        onPressed: {
                            if (root.pickerMode === "bluetooth" && modelData.paired) {
                                if (orbDelegate.forgetPending) {
                                    forgetFillAnim.restart()
                                } else {
                                    firstHoldTimer.restart()
                                }
                            }
                        }

                        onReleased: {
                            firstHoldTimer.stop()
                            if (forgetFillAnim.running) {
                                forgetFillAnim.stop()
                                orbDelegate.forgetFillProgress = 0.0
                            }
                        }

                        onClicked: {
                            if (root.state === "confirm_passkey") {
                                root.sendBtCmd({ "action": "confirm_passkey" })
                                root.state = "connecting"
                                return
                            }

                            if (root.pickerMode === "wifi") {
                                if (orbDelegate.isThisSelected) {
                                    if (modelData.isSaved || !modelData.isSecured || modelData.connected) {
                                        root.connectWifi(modelData, "")
                                    } else {
                                        root.state = "pass"
                                        root.passwordBuffer = ""
                                    }
                                } else {
                                    root.selectedItem = modelData
                                }
                            } else if (root.pickerMode === "bluetooth") {
                                if (orbDelegate.isThisSelected) {
                                    root.state = "connecting"
                                    if (modelData.connected) {
                                        root.sendBtCmd({ "action": "disconnect", "mac": modelData.mac })
                                    } else if (modelData.paired) {
                                        root.sendBtCmd({ "action": "connect", "mac": modelData.mac })
                                    } else {
                                        root.sendBtCmd({ "action": "pair", "mac": modelData.mac })
                                    }
                                } else {
                                    root.selectedItem = modelData
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Component.onDestruction: {
        root.closePicker()
    }
}
