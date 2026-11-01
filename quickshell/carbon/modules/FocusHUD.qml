import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../Singletons"
import "../components"

/**
 * FocusHUD:
 * High-performance Hyper-Tunnel Focus HUD for Carbon Shell.
 * Directly communicates with carbon-focus-engine (master Pomodoro timer & PID freezer)
 * over asynchronous JSON IPC via stdin/stdout.
 *
 * 100% Theme token bindings (zero hardcoded sizes or colors).
 */
Item {
    id: root

    property bool open: false
    signal closeRequested()

    implicitWidth: Theme.px(420)
    implicitHeight: Theme.px(540)
    width: implicitWidth
    height: implicitHeight

    // ── Focus Engine State ──
    property string focusState: "idle"     // "idle" | "focus" | "break"
    property int remainingSec: 1500
    property int focusTargetMin: 25
    property int breakTargetMin: 5
    property bool noiseActive: false
    property string noiseType: "none"

    readonly property string formattedTime: {
        var mins = Math.floor(root.remainingSec / 60)
        var secs = root.remainingSec % 60
        var mm = mins < 10 ? "0" + mins : mins
        var ss = secs < 10 ? "0" + secs : secs
        return mm + ":" + ss
    }

    readonly property color clockColor: {
        if (root.focusState === "focus") return Theme.warn
        if (root.focusState === "break") return Theme.ok
        return Theme.fgDim
    }

    readonly property string stateLabel: {
        if (root.focusState === "focus") return "TUNNEL ACTIVE • DISTRACTIONS FROZEN"
        if (root.focusState === "break") return "REST & RECHARGE • SYSTEM RESTORED"
        return "READY TO ENTER HYPER-TUNNEL"
    }

    readonly property string focusEngineBin: {
        var envPath = Quickshell.env("CARBON_FOCUS_ENGINE")
        if (envPath && envPath.length > 0) return envPath
        var home = Quickshell.env("HOME") || ""
        if (home.length > 0) {
            return home + "/.local/bin/carbon-focus-engine"
        }
        return "carbon-focus-engine"
    }

    focus: root.open
    Keys.enabled: root.open
    Keys.onEscapePressed: (event) => {
        root.closeRequested()
        event.accepted = true
    }

    // ── Engine Subprocess Pipe ──
    Process {
        id: focusEngineProc
        command: [
            "sh", "-c",
            "if command -v carbon-focus-engine >/dev/null 2>&1; then exec carbon-focus-engine; elif [ -x \"$HOME/.local/bin/carbon-focus-engine\" ]; then exec \"$HOME/.local/bin/carbon-focus-engine\"; else exec carbon-focus-engine; fi"
        ]
        running: true
        stdinEnabled: true

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) {
                var raw = (line || "").trim()
                if (!raw) return
                try {
                    var msg = JSON.parse(raw)
                    if (!msg) return
                    if (msg.state !== undefined) root.focusState = msg.state
                    if (msg.remaining !== undefined) root.remainingSec = msg.remaining
                    if (msg.focus_target !== undefined) root.focusTargetMin = msg.focus_target
                    if (msg.break_target !== undefined) root.breakTargetMin = msg.break_target
                    if (msg.noise_active !== undefined) root.noiseActive = Boolean(msg.noise_active)
                    if (msg.noise_type !== undefined) root.noiseType = msg.noise_type
                } catch(e) {}
            }
        }
    }

    function sendCmd(cmd) {
        if (focusEngineProc.running) {
            focusEngineProc.write(cmd + "\n")
        }
    }

    function startFocus() {
        sendCmd("start")
    }

    function startBreak() {
        sendCmd("start_break")
    }

    Process {
        id: rainProcess
        command: ["mpv", "--loop=inf", "--no-video", "/home/shogun/.config/carbon/assets/rain.mp3"]
        running: false
    }

    function stopSession() {
        if (rainProcess.running) rainProcess.running = false
        sendCmd("stop")
    }

    function setFocusMins(m) {
        var val = parseInt(m, 10)
        if (!isNaN(val) && val > 0) {
            sendCmd("set_focus " + val)
        }
    }

    function setBreakMins(m) {
        var val = parseInt(m, 10)
        if (!isNaN(val) && val > 0) {
            sendCmd("set_break " + val)
        }
    }

    function toggleNoise(type) {
        if (type === "rain") {
            if (rainProcess.running) {
                rainProcess.running = false
                root.noiseActive = false
                root.noiseType = "none"
                sendCmd("noise_stop")
            } else {
                sendCmd("noise_stop")
                rainProcess.running = true
                root.noiseActive = true
                root.noiseType = "rain"
            }
            return
        }
        if (rainProcess.running) {
            rainProcess.running = false
        }
        if (root.noiseActive && root.noiseType === type) {
            sendCmd("noise_stop")
        } else {
            sendCmd("noise_" + type)
        }
    }

    // ── Main Glass Card ──
    Rectangle {
        id: card
        anchors.fill: parent
        radius: Theme.tokens.rounding.extraLarge
        color: Qt.rgba(Theme.m3surfaceContainer.r, Theme.m3surfaceContainer.g, Theme.m3surfaceContainer.b, Theme.shellOpacity)
        border.width: Theme.px(1)
        border.color: root.focusState === "focus"
            ? Qt.rgba(Theme.warn.r, Theme.warn.g, Theme.warn.b, 0.45)
            : (root.focusState === "break"
                ? Qt.rgba(Theme.ok.r, Theme.ok.g, Theme.ok.b, 0.45)
                : Theme.outline)

        Behavior on border.color {
            ColorAnimation {
                duration: Theme.tokens.anim.normal
                easing.type: Easing.OutCubic
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.px(24)
            spacing: Theme.px(18)

            // Header Row: Title, State Badge, Close Button
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(10)

                Rectangle {
                    width: Theme.px(8)
                    height: Theme.px(8)
                    radius: Theme.tokens.rounding.full
                    color: root.clockColor

                    Behavior on color {
                        ColorAnimation { duration: Theme.tokens.anim.normal }
                    }
                }

                Text {
                    text: "HYPER-TUNNEL"
                    color: Theme.fg
                    font.family: Theme.font
                    font.pixelSize: Theme.fontPx(13)
                    font.bold: true
                    font.letterSpacing: 1.5
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    width: Theme.px(28)
                    height: Theme.px(28)
                    radius: Theme.tokens.rounding.full
                    color: closeHover.hovered ? Theme.bgHover : Theme.bgAlt
                    border.width: Theme.px(1)
                    border.color: Theme.outline

                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        color: Theme.fgDim
                        font.pixelSize: Theme.fontPx(11)
                    }

                    HoverHandler { id: closeHover }
                    TapHandler {
                        onTapped: root.closeRequested()
                    }
                }
            }

            // Big Clock Display Card
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.px(140)
                radius: Theme.tokens.rounding.large
                color: Theme.bgAlt
                border.width: Theme.px(1)
                border.color: Theme.outline

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: Theme.px(6)

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.formattedTime
                        color: root.clockColor
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fontPx(54)
                        font.bold: true
                        font.letterSpacing: 2.0

                        Behavior on color {
                            ColorAnimation {
                                duration: Theme.tokens.anim.normal
                                easing.type: Easing.OutCubic
                            }
                        }
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.stateLabel
                        color: root.clockColor
                        font.family: Theme.font
                        font.pixelSize: Theme.fontPx(10)
                        font.bold: true
                        font.letterSpacing: 1.2
                        opacity: 0.85

                        Behavior on color {
                            ColorAnimation { duration: Theme.tokens.anim.normal }
                        }
                    }
                }
            }

            // Control Buttons Row (Start Focus, Break, Stop)
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(10)

                // Start Focus Button
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.px(38)
                    radius: Theme.tokens.rounding.medium
                    color: root.focusState === "focus" ? Theme.warn : (startHover.hovered ? Theme.bgHover : Theme.bgAlt)
                    border.width: Theme.px(1)
                    border.color: root.focusState === "focus" ? Theme.warn : Theme.outline

                    Behavior on color { ColorAnimation { duration: Theme.tokens.anim.fast } }

                    Text {
                        anchors.centerIn: parent
                        text: root.focusState === "focus" ? "FOCUSING" : "START FOCUS"
                        color: root.focusState === "focus" ? Theme.m3background : Theme.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.fontPx(11)
                        font.bold: true
                        font.letterSpacing: 1.0
                    }

                    HoverHandler { id: startHover }
                    TapHandler {
                        onTapped: root.startFocus()
                    }
                }

                // Break Button
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.px(38)
                    radius: Theme.tokens.rounding.medium
                    color: root.focusState === "break" ? Theme.ok : (breakHover.hovered ? Theme.bgHover : Theme.bgAlt)
                    border.width: Theme.px(1)
                    border.color: root.focusState === "break" ? Theme.ok : Theme.outline

                    Behavior on color { ColorAnimation { duration: Theme.tokens.anim.fast } }

                    Text {
                        anchors.centerIn: parent
                        text: root.focusState === "break" ? "ON BREAK" : "TAKE BREAK"
                        color: root.focusState === "break" ? Theme.m3background : Theme.fg
                        font.family: Theme.font
                        font.pixelSize: Theme.fontPx(11)
                        font.bold: true
                        font.letterSpacing: 1.0
                    }

                    HoverHandler { id: breakHover }
                    TapHandler {
                        onTapped: root.startBreak()
                    }
                }

                // Stop / Reset Button
                Rectangle {
                    Layout.preferredWidth: Theme.px(64)
                    Layout.preferredHeight: Theme.px(38)
                    radius: Theme.tokens.rounding.medium
                    color: stopHover.hovered ? Theme.bgHover : Theme.bgAlt
                    border.width: Theme.px(1)
                    border.color: Theme.outline

                    Behavior on color { ColorAnimation { duration: Theme.tokens.anim.fast } }

                    Text {
                        anchors.centerIn: parent
                        text: "RESET"
                        color: Theme.fgDim
                        font.family: Theme.font
                        font.pixelSize: Theme.fontPx(10)
                        font.bold: true
                        font.letterSpacing: 1.0
                    }

                    HoverHandler { id: stopHover }
                    TapHandler {
                        onTapped: root.stopSession()
                    }
                }
            }

            // Editable Durations Row: Focus & Break TextInput elements
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(12)

                // Focus Duration Box
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.px(62)
                    radius: Theme.tokens.rounding.medium
                    color: Theme.bgAlt
                    border.width: Theme.px(1)
                    border.color: focusInput.activeFocus ? Theme.warn : Theme.outline

                    Behavior on border.color { ColorAnimation { duration: Theme.tokens.anim.fast } }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.px(8)
                        spacing: Theme.px(2)

                        Text {
                            text: "FOCUS TIME (MIN)"
                            color: Theme.fgDim
                            font.family: Theme.font
                            font.pixelSize: Theme.fontPx(9)
                            font.bold: true
                            font.letterSpacing: 1.0
                        }

                        TextInput {
                            id: focusInput
                            Layout.fillWidth: true
                            text: root.focusTargetMin.toString()
                            color: Theme.fg
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.fontPx(16)
                            font.bold: true
                            selectByMouse: true
                            validator: IntValidator { bottom: 1; top: 180 }
                            onEditingFinished: root.setFocusMins(text)
                            onAccepted: root.setFocusMins(text)
                        }
                    }
                }

                // Break Duration Box
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.px(62)
                    radius: Theme.tokens.rounding.medium
                    color: Theme.bgAlt
                    border.width: Theme.px(1)
                    border.color: breakInput.activeFocus ? Theme.ok : Theme.outline

                    Behavior on border.color { ColorAnimation { duration: Theme.tokens.anim.fast } }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.px(8)
                        spacing: Theme.px(2)

                        Text {
                            text: "BREAK TIME (MIN)"
                            color: Theme.fgDim
                            font.family: Theme.font
                            font.pixelSize: Theme.fontPx(9)
                            font.bold: true
                            font.letterSpacing: 1.0
                        }

                        TextInput {
                            id: breakInput
                            Layout.fillWidth: true
                            text: root.breakTargetMin.toString()
                            color: Theme.fg
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.fontPx(16)
                            font.bold: true
                            selectByMouse: true
                            validator: IntValidator { bottom: 1; top: 60 }
                            onEditingFinished: root.setBreakMins(text)
                            onAccepted: root.setBreakMins(text)
                        }
                    }
                }
            }

            // Acoustic Isolation Section
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.px(90)
                radius: Theme.tokens.rounding.large
                color: Theme.bgAlt
                border.width: Theme.px(1)
                border.color: Theme.outline

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.px(12)
                    spacing: Theme.px(8)

                    Text {
                        text: "ACOUSTIC ISOLATION"
                        color: Theme.fgDim
                        font.family: Theme.font
                        font.pixelSize: Theme.fontPx(9)
                        font.bold: true
                        font.letterSpacing: 1.0
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.px(10)

                        // Brown Noise Button
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Theme.px(36)
                            radius: Theme.tokens.rounding.medium
                            readonly property bool isSelected: root.noiseActive && root.noiseType === "brown"
                            color: isSelected ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.25) : (brownHover.hovered ? Theme.bgHover : Theme.bg)
                            border.width: Theme.px(1)
                            border.color: isSelected ? Theme.primary : Theme.outline

                            Behavior on color { ColorAnimation { duration: Theme.tokens.anim.fast } }

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: Theme.px(6)

                                Text {
                                    text: "󰝚"
                                    color: parent.parent.isSelected ? Theme.primary : Theme.fgDim
                                    font.family: Theme.fontMono
                                    font.pixelSize: Theme.fontPx(13)
                                }

                                Text {
                                    text: "Brown Noise"
                                    color: parent.parent.isSelected ? Theme.primary : Theme.fg
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontPx(11)
                                    font.bold: true
                                }
                            }

                            HoverHandler { id: brownHover }
                            TapHandler {
                                onTapped: root.toggleNoise("brown")
                            }
                        }

                        // Rain Noise Button
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Theme.px(36)
                            radius: Theme.tokens.rounding.medium
                            readonly property bool isSelected: rainProcess.running || (root.noiseActive && root.noiseType === "rain")
                            color: isSelected ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.25) : (rainHover.hovered ? Theme.bgHover : Theme.bg)
                            border.width: Theme.px(1)
                            border.color: isSelected ? Theme.primary : Theme.outline

                            Behavior on color { ColorAnimation { duration: Theme.tokens.anim.fast } }

                            RowLayout {
                                anchors.centerIn: parent
                                spacing: Theme.px(6)

                                Text {
                                    text: "󰖗"
                                    color: parent.parent.isSelected ? Theme.primary : Theme.fgDim
                                    font.family: Theme.fontMono
                                    font.pixelSize: Theme.fontPx(13)
                                }

                                Text {
                                    text: "Rain"
                                    color: parent.parent.isSelected ? Theme.primary : Theme.fg
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontPx(11)
                                    font.bold: true
                                }
                            }

                            HoverHandler { id: rainHover }
                            TapHandler {
                                onTapped: root.toggleNoise("rain")
                            }
                        }
                    }
                }
            }
        }
    }
}
