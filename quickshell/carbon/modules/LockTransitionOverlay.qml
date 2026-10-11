import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import "../Singletons"

/**
 * LockTransitionOverlay.qml
 *
 * Fullscreen item inside overlay PanelWindow that provides the
 * smooth desktop-to-lock transition (0-780ms handoff, up to 1250ms).
 *
 * Timeline (t in ms from LockTransition.t):
 * - 0-300ms: Desktop snapshot dissolves, dark veil ramps up (opacity -> 0.60)
 * - 0-780ms: Single shared blur ramps from 0 to 48px
 * - 200-750ms: 6 atomic dots fly inward from screen edges toward carbon orbits
 * - 400-780ms: Center "C" nucleus scales up with elastic bounce
 * - 780ms: WlSessionLock engages and takes over input focus without hitch
 * - 780-1250ms: Overlay fades out cleanly once WlSessionLock surface is visible
 */
Item {
    id: root
    anchors.fill: parent

    visible: LockTransition.phase === "locking"
    opacity: {
        if (LockTransition.phase !== "locking") return 0.0
        if (LockTransition.t < 780.0) return 1.0
        // Clean fade out after handoff
        return Math.max(0.0, 1.0 - (LockTransition.t - 780.0) / 470.0)
    }

    readonly property real t: LockTransition.t
    readonly property real eCubic: {
        var progress = Math.max(0.0, Math.min(1.0, t / 780.0))
        // OutCubic easing
        return 1.0 - Math.pow(1.0 - progress, 3.0)
    }

    readonly property string homeDir: Quickshell.env("HOME") || "/home/shogun"

    // 1. Blurred snapshot of desktop
    Item {
        anchors.fill: parent

        Image {
            id: snapImg
            anchors.fill: parent
            source: (LockTransition.screenshotPath.length > 0 && root.visible) ? ("file://" + LockTransition.screenshotPath) : ("file://" + root.homeDir + "/.cache/carbon/wallpaper_scaled.jpg")
            fillMode: Image.PreserveAspectCrop
            cache: false
            onStatusChanged: {
                if (status === Image.Error && source.toString().indexOf("lock_screen_snap.jpg") !== -1) {
                    source = "file://" + root.homeDir + "/.cache/carbon/wallpaper_scaled.jpg"
                }
            }
        }

        layer.enabled: true
        layer.effect: MultiEffect {
            autoPaddingEnabled: false
            blurEnabled: true
            blur: Math.min(1.0, root.t / 780.0)
            blurMax: 48
            blurMultiplier: 1.0
        }
    }

    // 2. Dim veil (0 -> 0.60 opacity)
    Rectangle {
        anchors.fill: parent
        color: "#050508"
        opacity: Math.min(0.60, (root.t / 500.0) * 0.60)
    }

    // 3. Converging Carbon Lewis Dot Assembly
    Item {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -20
        width: 360
        height: 310

        // Central "C" glyph
        Text {
            anchors.centerIn: parent
            text: "C"
            font.family: "Valley Sans"
            font.pixelSize: 56
            font.bold: true
            color: "#FFFFFF"
            scale: {
                if (root.t < 400.0) return 0.0
                var p = Math.min(1.0, (root.t - 400.0) / 380.0)
                // OutBack overshoot
                var c1 = 1.70158
                var c3 = c1 + 1.0
                return 1.0 + c3 * Math.pow(p - 1.0, 3.0) + c1 * Math.pow(p - 1.0, 2.0)
            }
            opacity: Math.max(0.0, Math.min(1.0, (root.t - 400.0) / 250.0))
        }

        // Concentric Orbit Guide Rings
        Rectangle {
            anchors.centerIn: parent
            width: 104; height: 104; radius: 52
            color: "transparent"
            border.color: Theme.accent ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.32) : Qt.rgba(0, 0.94, 1, 0.32)
            border.width: 1.3
            opacity: Math.max(0.0, Math.min(0.35, (root.t - 300.0) / 350.0))
        }

        Rectangle {
            anchors.centerIn: parent
            width: 184; height: 184; radius: 92
            color: "transparent"
            border.color: Theme.accent ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.28) : Qt.rgba(0, 0.94, 1, 0.28)
            border.width: 1.5
            opacity: Math.max(0.0, Math.min(0.35, (root.t - 300.0) / 350.0))
        }

        // Converging 6 Valence Dots
        Repeater {
            model: [
                { startX: 0, startY: -root.height / 2 - 80, endX: 0, endY: -52, size: 24, halo: 32 },
                { startX: 0, startY: root.height / 2 + 80, endX: 0, endY: 52, size: 24, halo: 32 },
                { startX: 0, startY: -root.height / 2 - 80, endX: 0, endY: -92, size: 28, halo: 40 },
                { startX: 0, startY: root.height / 2 + 80, endX: 0, endY: 92, size: 28, halo: 40 },
                { startX: -root.width / 2 - 80, startY: 0, endX: -92, endY: 0, size: 28, halo: 40 },
                { startX: root.width / 2 + 80, startY: 0, endX: 92, endY: 0, size: 28, halo: 40 }
            ]

            delegate: Item {
                required property var modelData
                readonly property real p: Math.max(0.0, Math.min(1.0, (root.t - 200.0) / 550.0))
                readonly property real easeVal: 1.0 - Math.pow(1.0 - p, 3.0)

                x: parent.width / 2 + (modelData.startX * (1.0 - easeVal) + modelData.endX * easeVal) - width / 2
                y: parent.height / 2 + (modelData.startY * (1.0 - easeVal) + modelData.endY * easeVal) - height / 2
                width: modelData.halo + 4
                height: width
                opacity: Math.min(1.0, p * 1.5)

                Rectangle {
                    anchors.centerIn: parent
                    width: modelData.halo
                    height: width
                    radius: width / 2
                    color: Theme.accent ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.45) : Qt.rgba(0, 0.94, 1, 0.45)
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: modelData.size
                    height: width
                    radius: width / 2
                    color: "#FFFFFF"
                    border.width: 2.2
                    border.color: Theme.accent ? Theme.accent : "#00F0FF"

                    Rectangle {
                        anchors.centerIn: parent
                        width: modelData.size * 0.35
                        height: width
                        radius: width / 2
                        color: Theme.accent ? Theme.accent : "#00F0FF"
                    }
                }
            }
        }
    }
}
