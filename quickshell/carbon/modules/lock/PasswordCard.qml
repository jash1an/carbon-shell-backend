import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pam
import M3Shapes
import "../../Singletons"

/**
 * PasswordCard:
 * A highly animative rectangular card with curved corners (radius 26px):
 *   - Each password character gets a unique geometric shape (MaterialShape)
 *   - Bouncy spring-scale & rotation entrance on each keystroke
 *   - Continuous fluid sine-wave floating motion across the shapes
 *   - Reactive lock glyph tilt on every keystroke
 *   - Border energy pulse on keypress
 *   - Glowing pulsing submit arrow button
 *   - Elastic shake on incorrect password & smooth unlock dissolve
 */
Item {
    id: cardRoot

    signal unlocked()

    property real xOffset: 0
    property string buffer: ""
    property bool isAuthenticating: false
    property bool isError: false
    property bool isSuccess: false

    // Unique geometric shapes assigned to each character
    readonly property var shapePalette: [
        MaterialShape.Gem,
        MaterialShape.Diamond,
        MaterialShape.Sunny,
        MaterialShape.Cookie4Sided,
        MaterialShape.SoftBurst,
        MaterialShape.Clover4Leaf,
        MaterialShape.Heart,
        MaterialShape.Slanted,
        MaterialShape.Flower,
        MaterialShape.ClamShell,
        MaterialShape.Pentagon,
        MaterialShape.Triangle,
        MaterialShape.Arch,
        MaterialShape.Boom,
        MaterialShape.PuffyDiamond,
        MaterialShape.Ghostish
    ]

    implicitWidth: 310
    implicitHeight: 52

    property bool revealed: false
    opacity: revealed ? 1.0 : 0.0
    scale: revealed ? 1.0 : 0.82
    transform: Translate {
        y: cardRoot.revealed ? 0 : 28
        Behavior on y {
            NumberAnimation {
                duration: cardRoot.revealed ? 420 : 240
                easing.type: cardRoot.revealed ? Easing.OutBack : Easing.InCubic
                easing.overshoot: 1.35
            }
        }
    }

    Behavior on opacity {
        NumberAnimation {
            duration: cardRoot.revealed ? 220 : 180
            easing.type: Easing.OutQuad
        }
    }

    Behavior on scale {
        NumberAnimation {
            duration: cardRoot.revealed ? 420 : 220
            easing.type: cardRoot.revealed ? Easing.OutBack : Easing.InCubic
            easing.overshoot: 1.4
        }
    }

    onRevealedChanged: {
        if (revealed) {
            keyPressPulse.restart()
        }
    }

    focus: true
    onActiveFocusChanged: {
        if (!activeFocus) forceActiveFocus()
    }

    Component.onCompleted: {
        forceActiveFocus()
    }

    function submitPassword() {
        if (buffer.length > 0 && !isAuthenticating) {
            isAuthenticating = true
            isError = false
            submitKickAnim.restart()
            passwd.start()
        }
    }

    /* ── Auto-Hide Idle Timer (5 seconds idle after typing) ────────── */
    Timer {
        id: idleHideTimer
        interval: 5000
        repeat: false
        onTriggered: {
            cardRoot.revealed = false
            cardRoot.buffer = ""
        }
    }

    Keys.onPressed: (event) => {
        if (isAuthenticating || isSuccess) return

        if (event.key === Qt.Key_Enter || event.key === Qt.Key_Return) {
            idleHideTimer.stop()
            submitPassword()
            event.accepted = true
        } else if (event.key === Qt.Key_Backspace) {
            cardRoot.revealed = true
            idleHideTimer.restart()
            if (event.modifiers & Qt.ControlModifier) {
                buffer = ""
            } else {
                buffer = buffer.slice(0, -1)
            }
            isError = false
            lockTiltAnim.restart()
            keyPressPulse.restart()
            event.accepted = true
        } else if (event.key === Qt.Key_Escape) {
            idleHideTimer.stop()
            buffer = ""
            cardRoot.revealed = false
            isError = false
            event.accepted = true
        } else if (event.text && event.text.length > 0) {
            const code = event.text.charCodeAt(0)
            if (code >= 32 && code !== 127) {
                cardRoot.revealed = true
                idleHideTimer.restart()
                buffer += event.text
                isError = false
                lockTiltAnim.restart()
                keyPressPulse.restart()
            }
            event.accepted = true
        } else {
            // Reveal on any other keypress as well so user sees the password card immediately
            cardRoot.revealed = true
            idleHideTimer.restart()
        }
    }

    /* ── Continuous Fluid Wave Rhythm for Password Shapes ────────────────── */
    FrameAnimation {
        id: waveTimer
        running: cardRoot.buffer.length > 0 && cardRoot.visible
        property real phase: 0
        onTriggered: phase += frameTime * 5.0
    }

    /* ── Keypress Border Glow Flash ──────────────────────────────────────── */
    SequentialAnimation {
        id: keyPressPulse
        NumberAnimation { target: borderGlow; property: "opacity"; to: 0.85; duration: 60; easing.type: Easing.OutQuad }
        NumberAnimation { target: borderGlow; property: "opacity"; to: 0.0; duration: 250; easing.type: Easing.OutQuad }
    }

    /* ── Lock Glyph Reactive Tilt ────────────────────────────────────────── */
    SequentialAnimation {
        id: lockTiltAnim
        NumberAnimation { target: lockIcon; property: "rotation"; to: -14; duration: 50; easing.type: Easing.OutQuad }
        NumberAnimation { target: lockIcon; property: "rotation"; to: 10; duration: 60; easing.type: Easing.InOutQuad }
        NumberAnimation { target: lockIcon; property: "rotation"; to: 0; duration: 65; easing.type: Easing.OutBack }
    }

    /* ── Submit Arrow Kick Animation ─────────────────────────────────────── */
    SequentialAnimation {
        id: submitKickAnim
        NumberAnimation { target: arrowText; property: "x"; from: 0; to: 7; duration: 80; easing.type: Easing.OutQuad }
        NumberAnimation { target: arrowText; property: "x"; to: 0; duration: 140; easing.type: Easing.OutBack }
    }

    /* ── Shake Animation on Authentication Error ─────────────────────────── */
    SequentialAnimation {
        id: shakeAnim

        PropertyAnimation { target: cardRoot; property: "xOffset"; from: 0; to: -16; duration: 45; easing.type: Easing.OutQuad }
        PropertyAnimation { target: cardRoot; property: "xOffset"; to: 16; duration: 55; easing.type: Easing.InOutQuad }
        PropertyAnimation { target: cardRoot; property: "xOffset"; to: -12; duration: 55; easing.type: Easing.InOutQuad }
        PropertyAnimation { target: cardRoot; property: "xOffset"; to: 12; duration: 55; easing.type: Easing.InOutQuad }
        PropertyAnimation { target: cardRoot; property: "xOffset"; to: -5; duration: 45; easing.type: Easing.InOutQuad }
        PropertyAnimation { target: cardRoot; property: "xOffset"; to: 0; duration: 45; easing.type: Easing.InOutQuad }
    }

    Timer {
        id: errorTimer
        interval: 1800
        onTriggered: cardRoot.isError = false
    }

    /* ── PAM Authentication Context ──────────────────────────────────────── */
    PamContext {
        id: passwd
        config: "hyprlock"
        user: Quickshell.env("USER")

        onResponseRequiredChanged: {
            if (responseRequired) {
                respond(cardRoot.buffer)
                cardRoot.buffer = ""
            }
        }

        onCompleted: (res) => {
            cardRoot.isAuthenticating = false
            if (res === PamResult.Success) {
                cardRoot.isSuccess = true
                cardRoot.unlocked()
            } else {
                cardRoot.isError = true
                cardRoot.buffer = ""
                shakeAnim.restart()
                errorTimer.restart()
            }
        }
    }

    /* ── Card Body ───────────────────────────────────────────────────────── */
    Rectangle {
        id: cardBg
        anchors.fill: parent
        anchors.horizontalCenterOffset: cardRoot.xOffset
        radius: 26

        color: Qt.rgba(0.08, 0.08, 0.12, 0.88)

        border.width: 1.5
        border.color: {
            if (cardRoot.isSuccess) return Theme.ok ? Theme.ok : "#a6e3a1"
            if (cardRoot.isError) return Theme.err ? Theme.err : "#f38ba8"
            if (cardRoot.buffer.length > 0) return Theme.accent ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.75) : Qt.rgba(0, 0.94, 1, 0.75)
            return Qt.rgba(1, 1, 1, 0.15)
        }

        Behavior on border.color {
            ColorAnimation { duration: 150 }
        }

        // Animated border glow ring on keystrokes
        Rectangle {
            id: borderGlow
            anchors.fill: parent
            radius: 26
            color: "transparent"
            border.width: 2.0
            border.color: Theme.accent ? Theme.accent : "#00F0FF"
            opacity: 0.0
        }

        // Inner row layout: Lock Icon + Animated Shapes + Submit Arrow
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 10
            spacing: 12

            // Lock Icon with reactive rotation
            Item {
                width: 20
                height: 20
                Layout.alignment: Qt.AlignVCenter

                Text {
                    id: lockIcon
                    anchors.centerIn: parent
                    text: cardRoot.isSuccess ? "check" : (cardRoot.isError ? "error" : "lock")
                    font.family: Theme.fontIcon
                    font.pixelSize: 18
                    color: {
                        if (cardRoot.isSuccess) return Theme.ok ? Theme.ok : "#a6e3a1"
                        if (cardRoot.isError) return Theme.err ? Theme.err : "#f38ba8"
                        return Theme.accent ? Theme.accent : "#00F0FF"
                    }
                }
            }

            // Input / Placeholder / Unique Geometric Shapes Area
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                // Placeholder / Status Text
                Text {
                    id: placeholderText
                    anchors.centerIn: parent
                    visible: cardRoot.buffer.length === 0
                    text: {
                        if (cardRoot.isSuccess) return "Unlocked"
                        if (cardRoot.isError) return "Incorrect password"
                        if (cardRoot.isAuthenticating) return "Authenticating..."
                        return "Enter your password"
                    }
                    font.family: Theme.font
                    font.pixelSize: 13
                    font.italic: !cardRoot.isError && !cardRoot.isSuccess
                    color: {
                        if (cardRoot.isSuccess) return Theme.ok ? Theme.ok : "#a6e3a1"
                        if (cardRoot.isError) return Theme.err ? Theme.err : "#f38ba8"
                        return Qt.rgba(1, 1, 1, 0.40)
                    }
                }

                // Fluid Animated Unique Geometric Shapes
                Row {
                    anchors.centerIn: parent
                    spacing: 7
                    visible: cardRoot.buffer.length > 0 && !cardRoot.isError

                    Repeater {
                        model: Math.min(cardRoot.buffer.length, 16)

                        Item {
                            id: shapeWrapper
                            required property int index
                            width: 15
                            height: 15
                            y: Math.sin(waveTimer.phase + index * 0.70) * 2.4

                            MaterialShape {
                                id: m3Shape
                                anchors.centerIn: parent
                                implicitSize: 13
                                shape: cardRoot.shapePalette[shapeWrapper.index % cardRoot.shapePalette.length]
                                color: Theme.accent ? Theme.accent : "#00F0FF"

                                Component.onCompleted: {
                                    entryAnim.restart()
                                }

                                ParallelAnimation {
                                    id: entryAnim
                                    NumberAnimation {
                                        target: m3Shape
                                        property: "scale"
                                        from: 0.1
                                        to: 1.0
                                        duration: 200
                                        easing.type: Easing.OutBack
                                        easing.overshoot: 1.5
                                    }
                                    NumberAnimation {
                                        target: m3Shape
                                        property: "rotation"
                                        from: -30
                                        to: 0
                                        duration: 220
                                        easing.type: Easing.OutBack
                                    }
                                    ColorAnimation {
                                        target: m3Shape
                                        property: "color"
                                        from: "#FFFFFF"
                                        to: Theme.accent ? Theme.accent : "#00F0FF"
                                        duration: 240
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Right Submit Arrow Button with interactive glow pulse
            Rectangle {
                id: submitBtn
                width: 34
                height: 34
                radius: 17
                color: (cardRoot.buffer.length > 0 && !cardRoot.isAuthenticating) ? (Theme.accent ? Theme.accent : "#00F0FF") : Qt.rgba(1, 1, 1, 0.08)
                Layout.alignment: Qt.AlignVCenter

                scale: (cardRoot.buffer.length > 0 && !cardRoot.isAuthenticating) ? (submitMouse.containsMouse ? 1.12 : 1.04) : 1.0

                Behavior on scale {
                    NumberAnimation { duration: 150; easing.type: Easing.OutBack }
                }

                Behavior on color {
                    ColorAnimation { duration: 150 }
                }

                // Glowing pulse halo behind active submit button
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width + 6
                    height: parent.height + 6
                    radius: width / 2
                    color: Theme.accent ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35) : Qt.rgba(0, 0.94, 1, 0.35)
                    visible: cardRoot.buffer.length > 0 && !cardRoot.isAuthenticating
                }

                Item {
                    id: arrowContainer
                    anchors.centerIn: parent
                    width: arrowText.implicitWidth
                    height: arrowText.implicitHeight

                    Text {
                        id: arrowText
                        anchors.centerIn: parent
                        text: cardRoot.isAuthenticating ? "progress_activity" : "arrow_forward"
                        font.family: Theme.fontIcon
                        font.pixelSize: 16
                        font.bold: true
                        color: (cardRoot.buffer.length > 0 && !cardRoot.isAuthenticating) ? "#121216" : Qt.rgba(1, 1, 1, 0.4)
                    }
                }

                MouseArea {
                    id: submitMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        cardRoot.submitPassword()
                        cardRoot.forceActiveFocus()
                    }
                }
            }
        }
    }
}
