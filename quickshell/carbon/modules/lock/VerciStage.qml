import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import "../../Singletons"
import "VerciGlyphMap.js" as GlyphMap

/**
 * VerciStage.qml:
 * Carbon // Verci Synced-Lyric Standby & Lock Screen Replacement
 *
 * Zero on-screen chrome:
 *   - Zero clocks, zero album art covers, zero progress bars, zero buttons.
 *   - Pure #000000 pitch-black background.
 *   - Top ReactBits Aurora Shader.
 *   - Center 3-Slot Convex Lens Stack (Fisheye Visual + Split-Text Rise).
 *   - Max 3 words per line, balanced typography, visible full-color emojis.
 *   - Single-Enter Instant Unlock (500ms radial iris reveal centered at 683, 383).
 */
Item {
    id: root
    anchors.fill: parent

    focus: true

    // Center coordinates on 1366x768 screen
    readonly property real cx: root.width / 2
    readonly property real cy: root.height / 2

    // ── 1. Top Aurora Background Shader ──────────────────────────────────
    AuroraBackground {
        id: auroraBg
        anchors.fill: parent
        z: 0
    }

    // ── 2. Synced Lyric Engine ───────────────────────────────────────────
    VerciLyricEngine {
        id: lyricEngine
    }

    // ── 3. Radial Iris Reveal Unlock Controller ──────────────────────────
    property real irisRadius: 0.0
    property bool unlocking: false

    signal unlocked()

    function triggerUnlock() {
        if (root.unlocking) return
        root.unlocking = true
        irisAnim.restart()
    }

    NumberAnimation {
        id: irisAnim
        target: root
        property: "irisRadius"
        from: 0.0
        to: 950.0
        duration: 500
        easing.type: Easing.InOutCubic
        onFinished: {
            root.unlocked()
            LockState.finishUnlock()
        }
    }

    // Capture Return / Enter / Space key for instant unlock
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            event.accepted = true
            root.triggerUnlock()
        }
    }

    // Mouse click also triggers unlock if clicked
    MouseArea {
        anchors.fill: parent
        z: 10
        onClicked: {
            root.forceActiveFocus()
        }
    }

    Component.onCompleted: {
        root.forceActiveFocus()
    }

    // ── 4. The 3-Slot Convex Lens Stack ("Fisheye Visual") ───────────────
    // Center stage Item centered in parent
    Item {
        id: stageContainer
        anchors.centerIn: parent
        width: Math.min(1180, root.width * 0.88)
        height: 440
        z: 1
        visible: lyricEngine.hasLyrics && root.irisRadius < 900
        opacity: root.unlocking ? Math.max(0.0, 1.0 - root.irisRadius / 400.0) : 1.0

        // Slot C — Exiting Top (yOffset: -132px)
        Item {
            id: slotCContainer
            anchors.centerIn: parent
            y: parent.height / 2 - 132
            width: parent.width
            height: 60
            visible: lyricEngine.slotCBeat !== null
            opacity: 0.0 // fading out completely as it rolls off

            scale: 0.60
            transform: [
                Scale {
                    origin.x: slotCContainer.width / 2
                    origin.y: slotCContainer.height / 2
                    xScale: 0.60
                    yScale: 0.14
                },
                Rotation {
                    origin.x: slotCContainer.width / 2
                    origin.y: slotCContainer.height / 2
                    axis { x: 1; y: 0; z: 0 }
                    angle: 50
                }
            ]

            Text {
                anchors.centerIn: parent
                text: lyricEngine.slotCBeat ? lyricEngine.slotCBeat.text : ""
                font.family: "Google Sans Flex, Plus Jakarta Sans, Manrope, sans-serif"
                font.weight: Font.ExtraBold
                font.letterSpacing: -2.5
                font.pixelSize: 36
                color: Theme.m3secondary
            }
        }

        // Slot B — Just Passed / Shortening (yOffset: -64px)
        Item {
            id: slotBContainer
            anchors.centerIn: parent
            y: parent.height / 2 - 64
            width: parent.width
            height: 80
            visible: lyricEngine.slotBBeat !== null
            opacity: lyricEngine.slotBBeat ? 0.70 : 0.0

            Behavior on y {
                NumberAnimation { duration: 190; easing.type: Easing.OutCubic }
            }
            Behavior on opacity {
                NumberAnimation { duration: 190; easing.type: Easing.OutCubic }
            }

            transform: [
                Scale {
                    origin.x: slotBContainer.width / 2
                    origin.y: slotBContainer.height / 2
                    xScale: 0.85
                    yScale: 0.68
                },
                Rotation {
                    origin.x: slotBContainer.width / 2
                    origin.y: slotBContainer.height / 2
                    axis { x: 1; y: 0; z: 0 }
                    angle: 24
                }
            ]

            Row {
                anchors.centerIn: parent
                spacing: 14

                // Companion emoji icon with visible full color (zero border/card)
                Text {
                    text: (lyricEngine.slotBBeat && lyricEngine.slotBBeat.glyph) ? lyricEngine.slotBBeat.glyph : ""
                    visible: text.length > 0
                    font.family: "Noto Color Emoji, sans-serif"
                    font.pixelSize: 42
                    anchors.verticalCenter: parent.verticalCenter
                }

                Item {
                    width: slotBText.width + 30
                    height: slotBText.height + 16
                    anchors.verticalCenter: parent.verticalCenter

                    // Drained tape block for Slot B
                    VerciTapeBlock {
                        anchors.fill: parent
                        opened: lyricEngine.slotBBeat && lyricEngine.slotBBeat.isTape
                        fillColor: Qt.rgba(Theme.m3primary.r, Theme.m3primary.g, Theme.m3primary.b, 0.22)
                        visible: opened
                    }

                    Text {
                        id: slotBText
                        anchors.centerIn: parent
                        text: lyricEngine.slotBBeat ? lyricEngine.slotBBeat.text : ""
                        font.family: "Google Sans Flex, Plus Jakarta Sans, Manrope, sans-serif"
                        font.weight: Font.ExtraBold
                        font.letterSpacing: -2.5
                        font.pixelSize: {
                            var len = (text || "").length
                            if (len > 18) return 38
                            if (len > 12) return 44
                            return 52
                        }
                        color: (lyricEngine.slotBBeat && lyricEngine.slotBBeat.isTape)
                            ? Qt.rgba(Theme.m3onPrimary.r, Theme.m3onPrimary.g, Theme.m3onPrimary.b, 0.85)
                            : Theme.m3secondary
                    }
                }
            }
        }

        // Slot A — Active Present (front-and-center at yOffset: +20px)
        Item {
            id: slotAContainer
            anchors.centerIn: parent
            y: parent.height / 2 + 20
            width: parent.width
            height: 140
            visible: lyricEngine.slotABeat !== null

            // Split-Text Horizon Rise Entry Animation
            property real riseY: 0.0
            property real riseScale: 1.0

            function triggerHorizonRise() {
                slotARiseAnim.restart()
            }

            Connections {
                target: lyricEngine
                function onSlotABeatChanged() {
                    if (lyricEngine.slotABeat) {
                        slotAContainer.triggerHorizonRise()
                    }
                }
            }

            ParallelAnimation {
                id: slotARiseAnim
                NumberAnimation {
                    target: slotAContainer
                    property: "riseY"
                    from: 70.0
                    to: 0.0
                    duration: 180
                    easing.type: Easing.OutExpo
                }
                NumberAnimation {
                    target: slotAContainer
                    property: "riseScale"
                    from: 0.92
                    to: 1.0
                    duration: 180
                    easing.type: Easing.OutExpo
                }
            }

            transform: [
                Translate { y: slotAContainer.riseY },
                Scale {
                    origin.x: slotAContainer.width / 2
                    origin.y: slotAContainer.height / 2
                    xScale: slotAContainer.riseScale
                    yScale: slotAContainer.riseScale
                }
            ]

            // Italic safety container padding so slanted/bold glyphs are never clipped
            Item {
                anchors.centerIn: parent
                width: slotARow.width + 48
                height: slotARow.height + 20

                Row {
                    id: slotARow
                    anchors.centerIn: parent
                    spacing: 16

                    // Inline companion icon (60px) in full color with strictly zero background, zero border
                    Text {
                        text: (lyricEngine.slotABeat && lyricEngine.slotABeat.glyph) ? lyricEngine.slotABeat.glyph : ""
                        visible: text.length > 0
                        font.family: "Noto Color Emoji, sans-serif"
                        font.pixelSize: 60
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Item {
                        width: slotAText.width + 38
                        height: slotAText.height + 18
                        anchors.verticalCenter: parent.verticalCenter

                        // Angled Cutout Tape Block behind punch words
                        VerciTapeBlock {
                            id: tapeBlockA
                            anchors.fill: parent
                            opened: lyricEngine.slotABeat ? lyricEngine.slotABeat.isTape : false
                            fillColor: Theme.m3primary
                            visible: opened
                        }

                        // Front-and-center kinetic text (max 3 words)
                        Text {
                            id: slotAText
                            anchors.centerIn: parent
                            text: lyricEngine.slotABeat ? lyricEngine.slotABeat.text : ""
                            font.family: "Google Sans Flex, Plus Jakarta Sans, Manrope, sans-serif"
                            font.weight: Font.ExtraBold
                            font.letterSpacing: -3.0
                            font.italic: lyricEngine.slotABeat ? lyricEngine.slotABeat.isTape : false
                            font.pixelSize: {
                                var len = (text || "").length
                                if (len > 18) return 56
                                if (len > 12) return 66
                                if (len > 6) return 78
                                return 88
                            }
                            fontSizeMode: Text.HorizontalFit
                            color: (lyricEngine.slotABeat && lyricEngine.slotABeat.isTape)
                                ? (Theme.m3onPrimary || "#f7e8ea")
                                : "#FFFFFF"
                        }
                    }
                }
            }
        }
    }

    // ── 5. Radial Iris Reveal Cutout Surface (Canvas Cutout) ─────────────
    // During iris reveal, draws a fullscreen black mask with expanding circular hole centered at (683, 383)
    Canvas {
        id: irisCanvas
        anchors.fill: parent
        z: 20
        visible: root.irisRadius > 0.1

        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            if (root.irisRadius <= 0.1) return

            ctx.save()
            ctx.fillStyle = "#000000"
            ctx.beginPath()
            ctx.rect(0, 0, width, height)
            // Cutout iris circle at (683, 383)
            ctx.arc(683, 383, root.irisRadius, 0, Math.PI * 2, true)
            ctx.fill()
            ctx.restore()
        }
    }

    onIrisRadiusChanged: {
        if (irisCanvas.visible) {
            irisCanvas.requestPaint()
        }
    }
}
