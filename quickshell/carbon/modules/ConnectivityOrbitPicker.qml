import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import "../Singletons"

/**
 * ConnectivityOrbitPicker.qml
 *
 * Nucleus Hub Attached Wi-Fi & Bluetooth Picker.
 * - Sits directly below the nucleus on a horizontal layout
 * - Two tabs at (-84px, 0) and (+84px, 0) on the nucleus line
 * - Live captured satellite start/end positions preserving full randomness
 * - Horizontal carousel row at y = +104px (selected radius 36, neighbors shrinking & fading)
 * - Details & action rows with primary pill, 2-step Forget ("Sure?"), and status
 * - Password pill with masked/plain text, blinking caret, eye toggle, submit arrow, stdin piping
 * - Bluetooth BlueZ passkey agent confirmation
 * - Dual-orb scanning indicator around nucleus or selected item
 * - Hub slide-up when near screen bottom
 * - Smooth cubic easing, zero wobble, nothing animates at rest, nothing runs while closed
 */
Item {
    id: root

    /* ── Mode & State Machine ── */
    // pickerMode: "none" | "wifi" | "bluetooth"
    property string pickerMode: "none"
    // state: "list" | "pass" | "busy" | "passkey"
    property string state: "list"

    readonly property bool isOpen: root.pickerMode === "wifi" || root.pickerMode === "bluetooth"
    readonly property bool reducedMotion: Boolean(Theme.reducedMotion)

    signal backRequested()

    /* ── Captured Satellite Positions (From Lobe Connect) ── */
    property real capturedWifiX: -84
    property real capturedWifiY: -84
    property real capturedBtX: 84
    property real capturedBtY: -84

    /* ── Open / Close Transition Progress (0.0 .. 1.0) ── */
    property real transitionProgress: 0.0

    NumberAnimation {
        id: openAnim
        target: root
        property: "transitionProgress"
        from: 0.0
        to: 1.0
        duration: root.reducedMotion ? 0 : 450
        easing.type: Easing.OutCubic
    }

    NumberAnimation {
        id: closeAnim
        target: root
        property: "transitionProgress"
        from: 1.0
        to: 0.0
        duration: root.reducedMotion ? 0 : 400
        easing.type: Easing.OutCubic
        onFinished: {
            root.pickerMode = "none"
            root.state = "list"
            root.backRequested()
        }
    }

    /* ── Selection & Scrolling ── */
    property int selectedIndex: 0
    property real scrollOffset: 0.0
    property bool isDragging: false
    property real dragStartX: 0.0
    property real dragStartOffset: 0.0

    Behavior on scrollOffset {
        enabled: !root.isDragging && !root.reducedMotion
        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
    }

    Timer {
        id: snapTimer
        interval: 160
        repeat: false
        onTriggered: {
            const listLen = root.pickerMode === "bluetooth" ? root.btList.length : root.wifiList.length
            if (listLen > 0) {
                root.selectedIndex = Math.max(0, Math.min(listLen - 1, Math.round(root.scrollOffset)))
                root.scrollOffset = root.selectedIndex
            }
        }
    }

    /* ── Two-Step Forget State ── */
    property bool forgetPending: false
    Timer {
        id: forgetResetTimer
        interval: 2500
        onTriggered: root.forgetPending = false
    }

    /* ── Status Messages ── */
    property string statusText: ""
    property bool isStatusError: false
    property real wrongPasswordFlash: 0.0

    Behavior on wrongPasswordFlash {
        NumberAnimation { duration: 800; easing.type: Easing.OutCubic }
    }

    /* ── Success Pulse Ring ── */
    property real successPulseScale: 1.0
    property real successPulseAlpha: 0.0

    ParallelAnimation {
        id: successPulseAnim
        NumberAnimation {
            target: root
            property: "successPulseScale"
            from: 1.0
            to: 2.11 // 36px * 2.11 ~ 76px
            duration: root.reducedMotion ? 0 : 700
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: root
            property: "successPulseAlpha"
            from: 0.85
            to: 0.0
            duration: root.reducedMotion ? 0 : 700
            easing.type: Easing.OutCubic
        }
    }

    /* ── Dual-Orb Rotation Scanning Animation ── */
    property bool scanAnimRunning: false
    property real scanOrbAngle: 0.0

    Timer {
        id: scanOrbTimer
        interval: 16
        running: root.isOpen && (root.scanAnimRunning || root.state === "busy")
        repeat: true
        onTriggered: {
            root.scanOrbAngle = (root.scanOrbAngle + 0.005 * 16.0) % (2.0 * Math.PI)
        }
    }

    Timer {
        id: initialScanTimer
        interval: 3000
        onTriggered: {
            if (!root.wifiScanning && !root.btScanning) root.scanAnimRunning = false
        }
    }

    Timer {
        id: manualScanTimer
        interval: 2500
        onTriggered: {
            if (!root.wifiScanning && !root.btScanning) root.scanAnimRunning = false
        }
    }

    /* ── Password Entry State ── */
    property string passwordInput: ""
    property bool showPassword: false
    property bool caretVisible: true

    Timer {
        id: caretBlinkTimer
        interval: 500
        running: root.state === "pass"
        repeat: true
        onTriggered: root.caretVisible = !root.caretVisible
    }

    /* ── Bluetooth Passkey Confirmation State ── */
    property string pendingPasskey: ""
    property string pendingMac: ""
    property string pendingDevName: ""

    /* ── Data Models ── */
    property var wifiList: []
    property var btList: []
    property bool wifiScanning: false
    property bool btScanning: false
    property bool btAdapterAvailable: true
    property bool btPowered: true

    readonly property var currentItem: {
        if (root.pickerMode === "bluetooth") {
            if (root.selectedIndex >= 0 && root.selectedIndex < root.btList.length) {
                return root.btList[root.selectedIndex]
            }
        } else {
            if (root.selectedIndex >= 0 && root.selectedIndex < root.wifiList.length) {
                return root.wifiList[root.selectedIndex]
            }
        }
        return null
    }

    /* ── Public Control API ── */
    function openWifi() {
        root.pickerMode = "wifi"
        root.state = "list"
        root.selectedIndex = 0
        root.scrollOffset = 0.0
        root.statusText = ""
        root.isStatusError = false
        root.forgetPending = false
        root.scanAnimRunning = true
        initialScanTimer.restart()
        openAnim.restart()
        root.fetchSavedNetworks()
        root.rescanWifi()
    }

    function openBluetooth() {
        root.pickerMode = "bluetooth"
        root.state = "list"
        root.selectedIndex = 0
        root.scrollOffset = 0.0
        root.statusText = ""
        root.isStatusError = false
        root.forgetPending = false
        root.scanAnimRunning = true
        initialScanTimer.restart()
        openAnim.restart()
        startBtBackend()
    }

    function goBack() {
        if (root.state === "pass" || root.state === "passkey") {
            root.state = "list"
            root.passwordInput = ""
            root.statusText = ""
            return
        }
        closePicker()
    }

    function resetPicker() {
        openAnim.stop()
        closeAnim.stop()
        stopBtBackend()
        transitionProgress = 0.0
        pickerMode = "none"
        state = "list"
        scanAnimRunning = false
    }

    function closePicker() {
        stopBtBackend()
        closeAnim.restart()
    }

    function switchTab(mode) {
        if (root.pickerMode === mode) return
        root.pickerMode = mode
        root.state = "list"
        root.selectedIndex = 0
        root.scrollOffset = 0.0
        root.statusText = ""
        root.isStatusError = false
        root.forgetPending = false
        if (mode === "bluetooth") {
            startBtBackend()
        } else {
            stopBtBackend()
            root.rescanWifi()
        }
    }

    /* ── Wi-Fi Backend via nmcli & carbon-wifi.py ── */
    property var savedConnections: []

    Process {
        id: savedWifiProc
        command: ["nmcli", "-t", "-f", "NAME", "connection", "show"]
        running: false
        stdout: StdioCollector {
            id: savedWifiCol
            waitForEnd: true
        }
        onExited: {
            const raw = String(savedWifiCol.text || "").trim()
            if (!raw) {
                root.savedConnections = []
                return
            }
            const lines = raw.split("\n")
            const saved = []
            for (let i = 0; i < lines.length; i++) {
                const s = lines[i].trim()
                if (s.length > 0 && s !== "lo" && s !== "Wired connection 1") {
                    saved.push(s)
                }
            }
            root.savedConnections = saved
            root.rescanWifi()
        }
    }

    function fetchSavedNetworks() {
        savedWifiProc.running = false
        savedWifiProc.running = true
    }

    Process {
        id: wifiScanProc
        command: ["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "dev", "wifi", "list"]
        running: false
        stdout: StdioCollector {
            id: wifiScanCol
            waitForEnd: true
        }
        onExited: {
            root.wifiScanning = false
            root.scanAnimRunning = false
            const raw = String(wifiScanCol.text || "").trim()
            if (!raw) return
            const lines = raw.split("\n")
            const seen = {}
            const list = []

            for (let i = 0; i < lines.length; i++) {
                const parts = lines[i].split(":")
                if (parts.length >= 3) {
                    const inUse = (parts[0].trim() === "*")
                    const ssid = parts[1].trim()
                    const signal = parseInt(parts[2].trim(), 10) || 0
                    const security = parts.length >= 4 ? parts.slice(3).join(":").trim() : ""

                    if (ssid.length > 0 && !seen[ssid]) {
                        seen[ssid] = true
                        const isSaved = root.savedConnections.indexOf(ssid) !== -1
                        list.push({
                            ssid: ssid,
                            name: ssid,
                            signal: signal,
                            security: security,
                            connected: inUse,
                            saved: isSaved,
                            deviceType: "wifi"
                        })
                    }
                }
            }

            // Sort: connected first, then saved, then by signal descending
            list.sort((a, b) => {
                if (a.connected && !b.connected) return -1
                if (!a.connected && b.connected) return 1
                if (a.saved && !b.saved) return -1
                if (!a.saved && b.saved) return 1
                return b.signal - a.signal
            })

            root.wifiList = list
            if (root.selectedIndex >= list.length) {
                root.selectedIndex = Math.max(0, list.length - 1)
                root.scrollOffset = root.selectedIndex
            }
        }
    }

    function rescanWifi() {
        if (wifiScanProc.running) return
        root.wifiScanning = true
        wifiScanProc.running = false
        wifiScanProc.running = true
    }

    /* Python Helper Process for Stdin Password & BlueZ Backend */
    Process {
        id: wifiActionProc
        command: ["python3", Quickshell.env("HOME") + "/carbon-shell/quickshell/carbon/scripts/carbon-wifi.py"]
        running: false
        stdout: SplitParser {
            onRead: (line) => {
                const s = line.trim()
                if (!s) return
                try {
                    const data = JSON.parse(s)
                    if (data.event === "result") {
                        root.handleWifiResult(data)
                    }
                } catch (e) {}
            }
        }
    }

    function ensureWifiActionProc() {
        if (!wifiActionProc.running) wifiActionProc.running = true
    }

    function handleWifiResult(data) {
        if (data.action === "connect") {
            if (data.status === "success") {
                root.state = "list"
                root.statusText = "connected - " + data.ssid
                root.isStatusError = false
                successPulseAnim.restart()
                root.fetchSavedNetworks()
            } else {
                if (data.error === "wrong_password") {
                    root.wrongPasswordFlash = 1.0
                    root.statusText = "wrong password, try again"
                    root.isStatusError = true
                    root.passwordInput = ""
                    flashTimer.restart()
                } else if (data.error === "network_not_found") {
                    root.state = "list"
                    root.statusText = "network not found"
                    root.isStatusError = true
                } else if (data.error === "no_response") {
                    root.state = "list"
                    root.statusText = "no response"
                    root.isStatusError = true
                } else {
                    root.state = "list"
                    root.statusText = "connection failed"
                    root.isStatusError = true
                }
            }
        } else if (data.action === "disconnect" || data.action === "forget") {
            root.state = "list"
            root.statusText = ""
            root.fetchSavedNetworks()
        }
    }

    Timer {
        id: flashTimer
        interval: 800
        onTriggered: root.wrongPasswordFlash = 0.0
    }

    /* ── Bluetooth Backend via carbon-bluetooth.py ── */
    Process {
        id: btBackendProc
        command: ["python3", Quickshell.env("HOME") + "/carbon-shell/quickshell/carbon/scripts/carbon-bluetooth.py"]
        running: false
        stdout: SplitParser {
            onRead: (line) => {
                const s = line.trim()
                if (!s) return
                try {
                    const data = JSON.parse(s)
                    root.handleBtEvent(data)
                } catch (e) {}
            }
        }
    }

    function startBtBackend() {
        if (!btBackendProc.running) btBackendProc.running = true
    }

    function stopBtBackend() {
        if (btBackendProc.running) {
            try {
                btBackendProc.write(JSON.stringify({ action: "stop" }) + "\n")
            } catch (e) {}
            btBackendProc.running = false
        }
    }

    function handleBtEvent(data) {
        if (data.type === "devices") {
            const rawList = data.list || []
            // Order: connected, then paired, then nearby by RSSI
            rawList.sort((a, b) => {
                if (a.connected && !b.connected) return -1
                if (!a.connected && b.connected) return 1
                if (a.paired && !b.paired) return -1
                if (!a.paired && b.paired) return 1
                return (b.rssi || -999) - (a.rssi || -999)
            })
            root.btList = rawList
            if (root.selectedIndex >= rawList.length) {
                root.selectedIndex = Math.max(0, rawList.length - 1)
                root.scrollOffset = root.selectedIndex
            }
        } else if (data.type === "adapter_state") {
            root.btAdapterAvailable = Boolean(data.available)
            root.btPowered = Boolean(data.powered)
            if (!root.btPowered) {
                root.statusText = "bluetooth off"
            }
        } else if (data.type === "scan_state") {
            root.btScanning = Boolean(data.scanning)
            if (!root.btScanning) root.scanAnimRunning = false
        } else if (data.type === "passkey_request") {
            root.pendingMac = data.mac || ""
            root.pendingDevName = data.name || ""
            root.pendingPasskey = String(data.passkey || "")
            root.state = "passkey"
            root.statusText = "does this code match the device?"
            root.isStatusError = false
        } else if (data.type === "action_result") {
            if (data.success) {
                root.state = "list"
                root.statusText = ""
                root.isStatusError = false
                if (data.action === "connect" || data.action === "pair") {
                    successPulseAnim.restart()
                }
            } else {
                root.state = "list"
                root.statusText = (data.error && data.error.includes("reject"))
                    ? ("pairing rejected by " + (root.pendingDevName || "device"))
                    : (data.error || "action failed")
                root.isStatusError = true
            }
        }
    }

    /* ── Action Executors ── */
    function runPrimaryAction() {
        if (!root.currentItem) return

        if (root.pickerMode === "wifi") {
            const item = root.currentItem
            if (item.connected) {
                // Disconnect
                root.state = "busy"
                root.statusText = "disconnecting…"
                ensureWifiActionProc()
                wifiActionProc.write(JSON.stringify({ action: "disconnect", ssid: item.ssid }) + "\n")
            } else if (item.saved) {
                // Saved connect
                root.state = "busy"
                root.statusText = "connecting to " + item.ssid + "…"
                ensureWifiActionProc()
                wifiActionProc.write(JSON.stringify({ action: "connect", ssid: item.ssid, is_saved: true }) + "\n")
            } else if (!item.security || item.security.length === 0) {
                // Open network connect
                root.state = "busy"
                root.statusText = "connecting to " + item.ssid + "…"
                ensureWifiActionProc()
                wifiActionProc.write(JSON.stringify({ action: "connect", ssid: item.ssid, is_saved: false }) + "\n")
            } else if (item.security.includes("802.1X") || item.security.includes("Enterprise")) {
                root.statusText = "needs a system dialog"
                ensureWifiActionProc()
                wifiActionProc.write(JSON.stringify({ action: "launch_editor" }) + "\n")
            } else {
                // Secured new network -> open password pill
                root.state = "pass"
                root.passwordInput = ""
                root.statusText = ""
                root.isStatusError = false
            }
        } else {
            // Bluetooth
            if (!root.btPowered) {
                if (btBackendProc.running) {
                    btBackendProc.write(JSON.stringify({ action: "power_on" }) + "\n")
                }
                return
            }
            const item = root.currentItem
            root.state = "busy"
            if (item.connected) {
                root.statusText = "disconnecting…"
                btBackendProc.write(JSON.stringify({ action: "disconnect", mac: item.mac }) + "\n")
            } else if (item.paired) {
                root.statusText = "connecting to " + item.name + "…"
                btBackendProc.write(JSON.stringify({ action: "connect", mac: item.mac }) + "\n")
            } else {
                root.statusText = "pairing with " + item.name + "…"
                btBackendProc.write(JSON.stringify({ action: "pair", mac: item.mac }) + "\n")
            }
        }
    }

    function runForgetAction() {
        if (!root.currentItem) return
        if (root.pickerMode === "wifi") {
            const item = root.currentItem
            ensureWifiActionProc()
            wifiActionProc.write(JSON.stringify({ action: "forget", ssid: item.ssid }) + "\n")
        } else {
            const item = root.currentItem
            if (btBackendProc.running) {
                btBackendProc.write(JSON.stringify({ action: "forget", mac: item.mac }) + "\n")
            }
        }
    }

    function submitPassword() {
        if (!root.currentItem || root.passwordInput.length === 0) return
        root.state = "busy"
        root.statusText = "connecting to " + root.currentItem.ssid + "…"
        ensureWifiActionProc()
        wifiActionProc.write(JSON.stringify({
            action: "connect",
            ssid: root.currentItem.ssid,
            password: root.passwordInput,
            is_saved: false
        }) + "\n")
    }

    /* ══════════════════════════════════════════════════════════════════════
       KEYBOARD FOCUS & EVENT ROUTING
       ══════════════════════════════════════════════════════════════════════ */
    Item {
        id: keyboardHandler
        anchors.fill: parent
        focus: root.isOpen

        Keys.onPressed: (event) => {
            if (!root.isOpen) return

            // 1. Password state keyboard handler
            if (root.state === "pass") {
                if (event.key === Qt.Key_Escape) {
                    root.state = "list"
                    root.passwordInput = ""
                    event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    root.submitPassword()
                    event.accepted = true
                } else if (event.key === Qt.Key_Backspace) {
                    if (root.passwordInput.length > 0) {
                        root.passwordInput = root.passwordInput.substring(0, root.passwordInput.length - 1)
                    }
                    event.accepted = true
                } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V) {
                    Quickshell.execDetached(["sh", "-c", "wl-paste -n > /tmp/carbon_paste_tmp.txt && python3 -c 'import sys; v=open(\"/tmp/carbon_paste_tmp.txt\").read().strip(); print(v)'"])
                    event.accepted = true
                } else if (event.text && event.text.length > 0 && event.text.charCodeAt(0) >= 32) {
                    root.passwordInput += event.text
                    event.accepted = true
                }
                return
            }

            // 2. Bluetooth Passkey state
            if (root.state === "passkey") {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    if (btBackendProc.running) btBackendProc.write(JSON.stringify({ action: "confirm_passkey" }) + "\n")
                    event.accepted = true
                } else if (event.key === Qt.Key_Escape) {
                    if (btBackendProc.running) btBackendProc.write(JSON.stringify({ action: "cancel_passkey" }) + "\n")
                    root.state = "list"
                    event.accepted = true
                }
                return
            }

            // 3. Normal List state
            if (event.key === Qt.Key_Escape) {
                root.goBack()
                event.accepted = true
            } else if (event.key === Qt.Key_Tab) {
                root.switchTab(root.pickerMode === "wifi" ? "bluetooth" : "wifi")
                event.accepted = true
            } else if (event.key === Qt.Key_Left) {
                const listLen = root.pickerMode === "bluetooth" ? root.btList.length : root.wifiList.length
                if (listLen > 0) {
                    root.selectedIndex = Math.max(0, root.selectedIndex - 1)
                    root.scrollOffset = root.selectedIndex
                }
                event.accepted = true
            } else if (event.key === Qt.Key_Right) {
                const listLen = root.pickerMode === "bluetooth" ? root.btList.length : root.wifiList.length
                if (listLen > 0) {
                    root.selectedIndex = Math.min(listLen - 1, root.selectedIndex + 1)
                    root.scrollOffset = root.selectedIndex
                }
                event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.runPrimaryAction()
                event.accepted = true
            }
        }
    }

    /* ══════════════════════════════════════════════════════════════════════
       VISUAL LAYOUT (Centered at Nucleus (0, 0))
       ══════════════════════════════════════════════════════════════════════ */
    visible: root.transitionProgress > 0.001

    // ── 1. TWO TAB SLOTS ON NUCLEUS HORIZONTAL LINE (y = 0) ──
    Item {
        id: tabsContainer
        anchors.centerIn: parent
        width: 1
        height: 1

        // Interpolate live from captured positions to (-84, 0) and (+84, 0)
        readonly property real p: root.transitionProgress

        // WiFi Tab (Only shown when Wi-Fi is active)
        Rectangle {
            visible: root.pickerMode === "wifi"
            x: root.capturedWifiX + (-84.0 - root.capturedWifiX) * tabsContainer.p - (width / 2)
            y: root.capturedWifiY + (0.0 - root.capturedWifiY) * tabsContainer.p - (height / 2)
            width: 40
            height: 40
            radius: 20
            readonly property bool isActive: root.pickerMode === "wifi"
            color: isActive ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0.04, 0.05, 0.08, 0.92)
            border.color: isActive ? "#FFFFFF" : Qt.rgba(1, 1, 1, 0.40)
            border.width: isActive ? 2.0 : 1.2

            Behavior on color { ColorAnimation { duration: 140 } }
            Behavior on border.color { ColorAnimation { duration: 140 } }

            Text {
                anchors.centerIn: parent
                text: "wifi"
                font.family: Theme.fontIcon
                font.pixelSize: 18
                color: "#FFFFFF"
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.switchTab("wifi")
            }
        }

        // Bluetooth Tab (Only shown when Bluetooth is active)
        Rectangle {
            visible: root.pickerMode === "bluetooth"
            x: root.capturedBtX + (84.0 - root.capturedBtX) * tabsContainer.p - (width / 2)
            y: root.capturedBtY + (0.0 - root.capturedBtY) * tabsContainer.p - (height / 2)
            width: 40
            height: 40
            radius: 20
            readonly property bool isActive: root.pickerMode === "bluetooth"
            color: isActive ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(0.04, 0.05, 0.08, 0.92)
            border.color: isActive ? "#FFFFFF" : Qt.rgba(1, 1, 1, 0.40)
            border.width: isActive ? 2.0 : 1.2

            Behavior on color { ColorAnimation { duration: 140 } }
            Behavior on border.color { ColorAnimation { duration: 140 } }

            Text {
                anchors.centerIn: parent
                text: "bluetooth"
                font.family: Theme.fontIcon
                font.pixelSize: 18
                color: "#FFFFFF"
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.switchTab("bluetooth")
            }
        }
    }

    // ── 2. DUAL-ORB SCANNING / BUSY ROTATION ANIMATION ──
    Item {
        id: rotatingOrbsLayer
        anchors.horizontalCenter: parent.horizontalCenter
        width: 1
        height: 1
        visible: root.scanAnimRunning || root.state === "busy"
        opacity: visible ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

        // When busy (connecting/pairing): center at (0, 104) around selected item
        // When scanning: center at (0, 0) around nucleus
        readonly property real targetCenterY: (root.state === "busy") ? 104.0 : 0.0
        readonly property real targetRadius: (root.state === "busy") ? 44.0 : 40.0

        y: targetCenterY

        // Orb 1 (Radius 4.0, diameter 8.0, white)
        Rectangle {
            x: (rotatingOrbsLayer.targetRadius * Math.cos(root.scanOrbAngle)) - (width / 2)
            y: (rotatingOrbsLayer.targetRadius * Math.sin(root.scanOrbAngle)) - (height / 2)
            width: 8.0
            height: 8.0
            radius: 4.0
            color: "#FFFFFF"
        }

        // Orb 2 (Radius 4.0, diameter 8.0, white, opposite side +PI)
        Rectangle {
            x: (rotatingOrbsLayer.targetRadius * Math.cos(root.scanOrbAngle + Math.PI)) - (width / 2)
            y: (rotatingOrbsLayer.targetRadius * Math.sin(root.scanOrbAngle + Math.PI)) - (height / 2)
            width: 8.0
            height: 8.0
            radius: 4.0
            color: "#FFFFFF"
        }
    }

    // ── 3. HORIZONTAL ROUND ITEM ROW (y = +104px) ──
    Item {
        id: listRowLayer
        anchors.horizontalCenter: parent.horizontalCenter
        width: 1
        height: 1

        // Transition: fly from nucleus center (0, 0) to (0, 104) starting at 25% of transition
        readonly property real listProgress: Math.max(0.0, Math.min(1.0, (root.transitionProgress - 0.25) / 0.75))
        y: 104.0 * listProgress
        opacity: listProgress

        // Input Capture Area for Wheel & Drag Scroll
        MouseArea {
            anchors.centerIn: parent
            width: 440
            height: 90
            hoverEnabled: true

            onWheel: (wheel) => {
                const listLen = root.pickerMode === "bluetooth" ? root.btList.length : root.wifiList.length
                if (listLen <= 0) return
                const delta = (wheel.angleDelta.y > 0) ? -0.6 : 0.6
                root.scrollOffset = Math.max(0, Math.min(listLen - 1, root.scrollOffset + delta))
                snapTimer.restart()
            }

            onPressed: (mouse) => {
                root.isDragging = true
                root.dragStartX = mouse.x
                root.dragStartOffset = root.scrollOffset
                snapTimer.stop()
            }

            onPositionChanged: (mouse) => {
                if (!root.isDragging) return
                const dx = mouse.x - root.dragStartX
                const listLen = root.pickerMode === "bluetooth" ? root.btList.length : root.wifiList.length
                root.scrollOffset = Math.max(0, Math.min(listLen - 1, root.dragStartOffset - (dx / 50.0)))
            }

            onReleased: {
                root.isDragging = false
                snapTimer.restart()
            }
        }

        // Visible Items Repeater
        Repeater {
            model: root.pickerMode === "bluetooth" ? root.btList : root.wifiList

            delegate: Item {
                id: itemDelegate
                required property int index
                required property var modelData

                // Distance from current scroll position
                readonly property real dist: Math.abs(index - root.scrollOffset)
                visible: dist <= 4.2

                // Layout formula: spacing 66px, max radius 36, shrinks by 13px per slot, min radius 11px
                readonly property real itemRadius: Math.max(11.0, 36.0 - 13.0 * dist)
                readonly property real itemAlpha: Math.max(0.0, Math.min(1.0, 1.3 - 0.32 * dist))
                readonly property bool isSelected: Math.abs(index - root.selectedIndex) < 0.5
                readonly property bool isSavedOrPaired: Boolean(modelData.saved || modelData.paired)
                readonly property bool isConnected: Boolean(modelData.connected)

                // Fly from nucleus center (0, 0) with stagger
                readonly property real slotTargetX: (index - root.scrollOffset) * 66.0
                readonly property real itemAnimP: Math.max(0.0, Math.min(1.0, (listRowLayer.listProgress - (dist * 0.08)) / Math.max(0.01, 1.0 - (dist * 0.08))))
                readonly property real curX: slotTargetX * itemAnimP
                readonly property real curY: (-104.0 * (1.0 - itemAnimP))

                x: curX - itemRadius
                y: curY - itemRadius
                width: itemRadius * 2
                height: itemRadius * 2
                opacity: itemAlpha * itemAnimP

                // Success Pulse Ring on connected item
                Rectangle {
                    anchors.centerIn: parent
                    visible: isSelected && root.successPulseAlpha > 0.001
                    width: (itemDelegate.itemRadius * 2) * root.successPulseScale
                    height: width
                    radius: width / 2
                    color: "transparent"
                    border.color: "#FFFFFF"
                    border.width: 2.0
                    opacity: root.successPulseAlpha
                }

                // Main Circle Item
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: isConnected ? "#FFFFFF" : Qt.rgba(0.04, 0.05, 0.08, 0.95)
                    border.color: isSelected ? "#FFFFFF" : (isSavedOrPaired ? Qt.rgba(1, 1, 1, 0.70) : Qt.rgba(1, 1, 1, 0.30))
                    border.width: isSelected ? 2.4 : 1.2

                    // Icon inside circle
                    Text {
                        anchors.centerIn: parent
                        text: {
                            if (root.pickerMode === "wifi") {
                                const sig = modelData.signal || 0
                                if (sig >= 75) return "wifi"
                                if (sig >= 45) return "network_wifi_2_bar"
                                return "network_wifi_1_bar"
                            } else {
                                const dt = modelData.deviceType || ""
                                if (dt === "headphones") return "headphones"
                                if (dt === "speaker") return "speaker"
                                if (dt === "phone") return "smartphone"
                                if (dt === "watch") return "watch"
                                if (dt === "keyboard") return "keyboard"
                                if (dt === "mouse") return "mouse"
                                if (dt === "gamepad") return "sports_esports"
                                return "bluetooth"
                            }
                        }
                        font.family: Theme.fontIcon
                        font.pixelSize: Math.max(9, Math.round(itemDelegate.itemRadius * 0.52))
                        color: isConnected ? "#0b0e14" : "#FFFFFF"
                    }

                    // Small Lock Badge for secured Wi-Fi
                    Text {
                        anchors.bottom: parent.bottom
                        anchors.right: parent.right
                        anchors.margins: Math.max(2, itemDelegate.itemRadius * 0.12)
                        visible: (root.pickerMode === "wifi") && Boolean(modelData.security && modelData.security.length > 0) && !isConnected && itemDelegate.itemRadius >= 20
                        text: "lock"
                        font.family: Theme.fontIcon
                        font.pixelSize: Math.max(8, Math.round(itemDelegate.itemRadius * 0.32))
                        color: Qt.rgba(1, 1, 1, 0.75)
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (itemDelegate.isSelected) {
                            root.runPrimaryAction()
                        } else {
                            root.selectedIndex = itemDelegate.index
                            root.scrollOffset = itemDelegate.index
                        }
                    }
                }
            }
        }
    }

    // ── 4. LABELS UNDER THE ROW (Line 1 Name & Line 2 Details) ──
    Item {
        id: labelsLayer
        anchors.horizontalCenter: parent.horizontalCenter
        width: 380
        height: 50
        y: 160
        opacity: listRowLayer.listProgress

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 3

            // Line 1: Name (16px bold)
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: root.currentItem ? (root.currentItem.name || root.currentItem.ssid || "") : (root.pickerMode === "wifi" ? (root.wifiScanning ? "Scanning for networks…" : "No networks found") : (root.btScanning ? "Discovering devices…" : "No devices found"))
                font.family: "Valley Sans, Rubik, sans-serif"
                font.pixelSize: 16
                font.bold: true
                color: "#FFFFFF"
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            // Line 2: Details line
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: {
                    if (!root.currentItem) return ""
                    if (root.pickerMode === "wifi") {
                        const secStr = (root.currentItem.security && root.currentItem.security.length > 0) ? "secured" : "open"
                        const savedStr = root.currentItem.saved ? "saved" : ""
                        const sigStr = "signal " + (root.currentItem.signal || 0) + "%"
                        const posStr = (root.selectedIndex + 1) + "/" + root.wifiList.length
                        return secStr + (savedStr ? " - " + savedStr : "") + " - " + sigStr + " - " + posStr
                    } else {
                        const typeStr = root.currentItem.deviceType || "device"
                        const stateStr = root.currentItem.connected ? "connected" : (root.currentItem.paired ? "paired" : "nearby")
                        const batStr = (root.currentItem.battery !== undefined && root.currentItem.battery >= 0) ? ("battery " + root.currentItem.battery + "%") : ""
                        const posStr = (root.selectedIndex + 1) + "/" + root.btList.length
                        return typeStr + " - " + stateStr + (batStr ? " - " + batStr : "") + " - " + posStr
                    }
                }
                font.family: "Valley Sans, Rubik, sans-serif"
                font.pixelSize: 12
                color: Qt.rgba(1, 1, 1, 0.60)
            }
        }
    }

    // ── 5. ACTION ROW (y = +236px from nucleus center) ──
    Item {
        id: actionRowLayer
        anchors.horizontalCenter: parent.horizontalCenter
        width: 380
        height: 60
        y: 236
        opacity: listRowLayer.listProgress

        // A. Normal List / Busy State
        RowLayout {
            anchors.centerIn: parent
            spacing: 8
            visible: root.state === "list" || root.state === "busy"

            readonly property bool hasForget: Boolean(root.currentItem && (root.currentItem.saved || root.currentItem.paired))

            // Primary Pill Button
            Rectangle {
                Layout.preferredWidth: parent.hasForget ? 130 : 170
                Layout.preferredHeight: 38
                radius: 19
                color: "#FFFFFF"

                Text {
                    anchors.centerIn: parent
                    text: {
                        if (root.state === "busy") return "…"
                        if (root.pickerMode === "wifi") {
                            if (!root.currentItem) return "Connect"
                            return root.currentItem.connected ? "Disconnect" : "Connect"
                        } else {
                            if (!root.btPowered) return "Turn on"
                            if (!root.currentItem) return "Pair"
                            if (root.currentItem.connected) return "Disconnect"
                            if (root.currentItem.paired) return "Connect"
                            return "Pair"
                        }
                    }
                    font.family: "Valley Sans, Rubik, sans-serif"
                    font.pixelSize: 13
                    font.bold: true
                    color: "#0b0e14"
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.runPrimaryAction()
                }
            }

            // Ghost Forget Pill (84px)
            Rectangle {
                visible: parent.hasForget
                Layout.preferredWidth: 84
                Layout.preferredHeight: 38
                radius: 19
                color: Qt.rgba(1, 1, 1, 0.08)
                border.color: root.forgetPending ? "#F87171" : Qt.rgba(1, 1, 1, 0.35)
                border.width: 1.2

                Text {
                    anchors.centerIn: parent
                    text: root.forgetPending ? "Sure?" : "Forget"
                    font.family: "Valley Sans, Rubik, sans-serif"
                    font.pixelSize: 12
                    font.bold: root.forgetPending
                    color: root.forgetPending ? "#F87171" : "#FFFFFF"
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (!root.forgetPending) {
                            root.forgetPending = true
                            forgetResetTimer.restart()
                        } else {
                            root.forgetPending = false
                            forgetResetTimer.stop()
                            root.runForgetAction()
                        }
                    }
                }
            }
        }

        // B. Password Entry State (Wi-Fi)
        ColumnLayout {
            anchors.centerIn: parent
            spacing: 6
            visible: root.state === "pass"

            RowLayout {
                spacing: 8
                Layout.alignment: Qt.AlignHCenter

                // 214px Password Pill
                Rectangle {
                    Layout.preferredWidth: 214
                    Layout.preferredHeight: 38
                    radius: 19
                    color: Qt.rgba(0.04, 0.05, 0.08, 0.95)
                    border.color: root.wrongPasswordFlash > 0.01 ? "#F87171" : Qt.rgba(1, 1, 1, 0.40)
                    border.width: 1.2

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 10
                        spacing: 6

                        Text {
                            text: "lock"
                            font.family: Theme.fontIcon
                            font.pixelSize: 15
                            color: Qt.rgba(1, 1, 1, 0.60)
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            // Placeholder
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: root.passwordInput.length === 0
                                text: "password"
                                font.family: "Valley Sans, Rubik, sans-serif"
                                font.pixelSize: 13
                                color: Qt.rgba(1, 1, 1, 0.35)
                            }

                            // Password Text / Masked Dots with Caret
                            Row {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2

                                Text {
                                    text: root.showPassword ? root.passwordInput : "●".repeat(root.passwordInput.length)
                                    font.family: "Valley Sans, Rubik, sans-serif"
                                    font.pixelSize: root.showPassword ? 13 : 10
                                    color: "#FFFFFF"
                                }

                                Text {
                                    visible: root.caretVisible
                                    text: "|"
                                    font.family: "Valley Sans, Rubik, sans-serif"
                                    font.pixelSize: 14
                                    color: "#FFFFFF"
                                }
                            }
                        }

                        // Eye toggle button
                        Text {
                            text: root.showPassword ? "visibility" : "visibility_off"
                            font.family: Theme.fontIcon
                            font.pixelSize: 16
                            color: Qt.rgba(1, 1, 1, 0.65)
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.showPassword = !root.showPassword
                            }
                        }
                    }
                }

                // Submit Arrow Button (radius 17px, diameter 34px)
                Rectangle {
                    Layout.preferredWidth: 34
                    Layout.preferredHeight: 34
                    radius: 17
                    color: "#FFFFFF"

                    Text {
                        anchors.centerIn: parent
                        text: "arrow_forward"
                        font.family: Theme.fontIcon
                        font.pixelSize: 18
                        color: "#0b0e14"
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.submitPassword()
                    }
                }
            }

            // Cancel ghost pill
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 84
                Layout.preferredHeight: 28
                radius: 14
                color: Qt.rgba(1, 1, 1, 0.08)
                border.color: Qt.rgba(1, 1, 1, 0.25)
                border.width: 1.0

                Text {
                    anchors.centerIn: parent
                    text: "Cancel"
                    font.family: "Valley Sans, Rubik, sans-serif"
                    font.pixelSize: 11
                    color: Qt.rgba(1, 1, 1, 0.80)
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.state = "list"
                        root.passwordInput = ""
                    }
                }
            }
        }

        // C. Bluetooth Passkey Confirmation State
        ColumnLayout {
            anchors.centerIn: parent
            spacing: 6
            visible: root.state === "passkey"

            // 190px Passkey Pill (18px mono)
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 190
                Layout.preferredHeight: 38
                radius: 19
                color: Qt.rgba(0.04, 0.05, 0.08, 0.95)
                border.color: Qt.rgba(1, 1, 1, 0.40)
                border.width: 1.2

                Text {
                    anchors.centerIn: parent
                    text: root.pendingPasskey
                    font.family: "JetBrains Mono, monospace"
                    font.pixelSize: 18
                    font.bold: true
                    color: "#FFFFFF"
                }
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 8

                Rectangle {
                    Layout.preferredWidth: 90
                    Layout.preferredHeight: 32
                    radius: 16
                    color: "#FFFFFF"
                    Text {
                        anchors.centerIn: parent
                        text: "Confirm"
                        font.family: "Valley Sans, Rubik, sans-serif"
                        font.pixelSize: 12
                        font.bold: true
                        color: "#0b0e14"
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (btBackendProc.running) btBackendProc.write(JSON.stringify({ action: "confirm_passkey" }) + "\n")
                        }
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 80
                    Layout.preferredHeight: 32
                    radius: 16
                    color: Qt.rgba(1, 1, 1, 0.08)
                    border.color: Qt.rgba(1, 1, 1, 0.30)
                    border.width: 1.0
                    Text {
                        anchors.centerIn: parent
                        text: "Cancel"
                        font.family: "Valley Sans, Rubik, sans-serif"
                        font.pixelSize: 12
                        color: "#FFFFFF"
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (btBackendProc.running) btBackendProc.write(JSON.stringify({ action: "cancel_passkey" }) + "\n")
                            root.state = "list"
                        }
                    }
                }
            }
        }
    }

    // ── 6. STATUS LINE BELOW ACTION ROW ──
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: actionRowLayer.bottom
        anchors.topMargin: 8
        opacity: listRowLayer.listProgress
        text: root.statusText
        font.family: "Valley Sans, Rubik, sans-serif"
        font.pixelSize: 12
        color: root.isStatusError ? "#F87171" : Qt.rgba(1, 1, 1, 0.55)
    }

    // ── 7. SCAN BUTTON (Bottom-Right of Picker) ──
    RowLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.horizontalCenterOffset: 154
        y: 240
        spacing: 5
        opacity: listRowLayer.listProgress

        Rectangle {
            Layout.preferredWidth: 30
            Layout.preferredHeight: 30
            radius: 15
            color: Qt.rgba(1, 1, 1, 0.08)
            border.color: Qt.rgba(1, 1, 1, 0.30)
            border.width: 1.0

            Text {
                anchors.centerIn: parent
                text: "refresh"
                font.family: Theme.fontIcon
                font.pixelSize: 15
                color: "#FFFFFF"
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.scanAnimRunning = true
                    manualScanTimer.restart()
                    if (root.pickerMode === "bluetooth") {
                        if (btBackendProc.running) btBackendProc.write(JSON.stringify({ action: "power_on" }) + "\n")
                    } else {
                        root.rescanWifi()
                    }
                }
            }
        }

        Text {
            text: "scan"
            font.family: "Valley Sans, Rubik, sans-serif"
            font.pixelSize: 11
            color: Qt.rgba(1, 1, 1, 0.60)
        }
    }
}
