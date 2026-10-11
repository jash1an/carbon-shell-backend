import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import "../../Singletons"

/**
 * LockSurface:
 * Fullscreen WlSessionLockSurface that seamlessly connects to LockTransition
 * (continuing from t = 780ms on lock, and driving the reverse timeline on unlock).
 */
WlSessionLockSurface {
    id: root

    signal requestUnlock()
    property var sessionLock: null
    property var notificationServer: null
    readonly property string home: Quickshell.env("HOME") || ""

    color: "#050508"

    readonly property string phase: LockTransition.phase
    readonly property real t: LockTransition.t
    readonly property real u: LockTransition.u
    readonly property real screenDiag: Math.sqrt(root.width * root.width + root.height * root.height)
    readonly property real centerX: root.width / 2
    readonly property real centerY: root.height / 2 - 20

    function easeInCubic(p) {
        return Math.pow(Math.max(0.0, Math.min(1.0, p)), 3.0)
    }

    function easeOutCubic(p) {
        var x = Math.max(0.0, Math.min(1.0, p))
        return 1.0 - Math.pow(1.0 - x, 3.0)
    }

    function easeInOutCubic(p) {
        var x = Math.max(0.0, Math.min(1.0, p))
        return x < 0.5 ? 4.0 * x * x * x : 1.0 - Math.pow(-2.0 * x + 2.0, 3.0) / 2.0
    }

    Component.onCompleted: {
        pwdCard.forceActiveFocus()
    }

    function startUnlock() {
        topVisualizer.active = false
        LockTransition.startUnlock()
    }

    function testNotif() {
        notifOverlay.showToast("Test Notification", "Lock Screen Preview", "Notifications pop smoothly above the music overlay.")
    }

    function testNotifCenter() {
        notifOverlay.toggleCenter()
    }

    function testNotifClear() {
        notifOverlay.clearAll()
    }

    // Capture clicks anywhere on the lock screen to restore password card focus
    MouseArea {
        anchors.fill: parent
        onClicked: {
            pwdCard.revealed = true
            pwdCard.restartIdleTimer(3000)
            pwdCard.forceActiveFocus()
        }
    }

    /* ── 1. Wallpaper Background (Blurred & Sharp Reveal Mask) ── */
    Item {
        id: bgContainer
        anchors.fill: parent

        // Base Sharp Desktop Screenshot
        Image {
            id: sharpBg
            anchors.fill: parent
            source: (LockTransition.screenshotPath.length > 0) ? ("file://" + LockTransition.screenshotPath) : ("file://" + root.home + "/.cache/carbon/wallpaper_scaled.jpg")
            fillMode: Image.PreserveAspectCrop
            cache: false
        }

        // Blurred + Dimmed Layer
        Item {
            id: blurredLayer
            anchors.fill: parent

            Image {
                id: bgWallpaper
                anchors.fill: parent
                source: sharpBg.source
                fillMode: Image.PreserveAspectCrop
                cache: false

                layer.enabled: true
                layer.effect: MultiEffect {
                    autoPaddingEnabled: false
                    blurEnabled: true
                    blur: 1.0
                    blurMax: 48
                    blurMultiplier: 1.0
                }
            }

            // Dark glass tint / dimming overlay
            Rectangle {
                id: bgDim
                anchors.fill: parent
                color: "#050508"
                opacity: 0.55
            }
        }

        // Sharp Reveal Layer expanding smoothly on top during unlock (u >= 500ms)
        Item {
            id: sharpRevealLayer
            anchors.fill: parent
            visible: root.phase === "unlocking" && root.u >= 500.0

            Image {
                anchors.fill: parent
                source: sharpBg.source
                fillMode: Image.PreserveAspectCrop
                cache: false
            }

            layer.enabled: true
            layer.effect: MultiEffect {
                maskEnabled: true
                maskSource: sharpMaskItem
                maskSpreadAtMin: 0.28
            }
        }
    }

    // Expanding Sharp Radial Mask (u = 500-1100ms)
    Item {
        id: sharpMaskItem
        anchors.fill: parent
        visible: false

        readonly property real p: Math.max(0.0, Math.min(1.0, (root.u - 500.0) / 600.0))
        readonly property real currentRadius: root.easeInOutCubic(p) * 0.58 * root.screenDiag

        Rectangle {
            x: root.centerX - sharpMaskItem.currentRadius
            y: root.centerY - sharpMaskItem.currentRadius
            width: sharpMaskItem.currentRadius * 2
            height: sharpMaskItem.currentRadius * 2
            radius: sharpMaskItem.currentRadius
            color: "#FFFFFF"
        }
    }

    // Shockwave Ring riding sharp front (u = 500-1100ms)
    Item {
        anchors.fill: parent
        visible: root.phase === "unlocking" && root.u >= 500.0 && root.u <= 1100.0

        readonly property real p: Math.max(0.0, Math.min(1.0, (root.u - 500.0) / 600.0))
        readonly property real currentRadius: root.easeInOutCubic(p) * 0.58 * root.screenDiag
        readonly property real shockAlpha: Math.max(0.0, 0.60 * (1.0 - p))

        // Soft halo (7px)
        Rectangle {
            x: root.centerX - parent.currentRadius - 3.5
            y: root.centerY - parent.currentRadius - 3.5
            width: (parent.currentRadius + 3.5) * 2
            height: (parent.currentRadius + 3.5) * 2
            radius: parent.currentRadius + 3.5
            color: "transparent"
            border.color: Qt.rgba(1, 1, 1, parent.shockAlpha * 0.35)
            border.width: 7.0
        }

        // Crisp white ring (1.6px)
        Rectangle {
            x: root.centerX - parent.currentRadius
            y: root.centerY - parent.currentRadius
            width: parent.currentRadius * 2
            height: parent.currentRadius * 2
            radius: parent.currentRadius
            color: "transparent"
            border.color: Qt.rgba(1, 1, 1, parent.shockAlpha)
            border.width: 1.6
        }
    }

    /* ── 2. Center Assembly: Unified Carbon Atom + Password Card ── */
    UnifiedCarbonAtom {
        id: carbonAtom
        x: root.centerX - width / 2
        y: root.centerY - height / 2
        width: 120
        height: 120
    }

    PasswordCard {
        id: pwdCard
        anchors.horizontalCenter: carbonAtom.horizontalCenter
        anchors.top: carbonAtom.bottom
        anchors.topMargin: 12
        onUnlocked: root.startUnlock()
    }

    /* ── 3. Quadratic Bezier Widget Flight Helpers ── */
    // Helper to calculate Bezier offset from resting destination to center (cx, cy)
    // Control point is at 20% in x, 85% in y
    function getBezierOffset(destX, destY, progress) {
        var deltaX = root.centerX - destX
        var deltaY = root.centerY - destY
        var s = Math.max(0.0, Math.min(1.0, progress))
        var p0X = deltaX, p0Y = deltaY
        var p1X = deltaX * 0.80, p1Y = deltaY * 0.15
        var curX = (1.0 - s) * (1.0 - s) * p0X + 2.0 * (1.0 - s) * s * p1X
        var curY = (1.0 - s) * (1.0 - s) * p0Y + 2.0 * (1.0 - s) * s * p1Y
        return Qt.point(curX, curY)
    }

    // ── Bottom-Right Clock (Widget 0: Lock 700-1300ms, Unlock 320-720ms) ──
    LockClock {
        id: lockClock
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 40
        anchors.bottomMargin: 36

        readonly property real lockP: Math.max(0.0, Math.min(1.0, (root.t - 700.0) / 600.0))
        readonly property real unlockP: Math.max(0.0, Math.min(1.0, (root.u - 320.0) / 400.0))
        readonly property real s: {
            if (root.phase === "locking") return root.easeOutCubic(lockP)
            if (root.phase === "unlocking") return 1.0 - root.easeInCubic(unlockP)
            return 1.0
        }

        readonly property point bOffset: root.getBezierOffset(root.width - 40 - width / 2, root.height - 36 - height / 2, lockClock.s)

        transform: Translate {
            x: lockClock.bOffset.x
            y: lockClock.bOffset.y
        }

        opacity: {
            if (root.phase === "locking") return lockClock.lockP
            if (root.phase === "unlocking") return Math.pow(lockClock.s, 0.70)
            return 1.0
        }
    }

    // ── Bottom-Left Media Overlay (Widget 2: Lock 850-1400ms, Unlock 240-640ms) ──
    LockMediaOverlay {
        id: mediaOverlay
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: 36
        anchors.bottomMargin: 36

        readonly property real lockP: Math.max(0.0, Math.min(1.0, (root.t - 850.0) / 550.0))
        readonly property real unlockP: Math.max(0.0, Math.min(1.0, (root.u - 240.0) / 400.0))
        readonly property real s: {
            if (root.phase === "locking") return root.easeOutCubic(lockP)
            if (root.phase === "unlocking") return 1.0 - root.easeInCubic(unlockP)
            return 1.0
        }

        readonly property point bOffset: root.getBezierOffset(36 + width / 2, root.height - 36 - height / 2, mediaOverlay.s)

        transform: Translate {
            x: mediaOverlay.bOffset.x
            y: mediaOverlay.bOffset.y
        }

        scale: 0.35 + 0.65 * mediaOverlay.s

        opacity: {
            if (root.phase === "locking") return mediaOverlay.lockP
            if (root.phase === "unlocking") return Math.pow(mediaOverlay.s, 0.70)
            return 1.0
        }
    }

    // ── Top Cava Visualizer (Lock unroll 900-1450ms, Unlock retract 240-600ms) ──
    LockCavaVisualizer {
        id: topVisualizer
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        height: 70

        readonly property real lockUnroll: Math.max(0.0, Math.min(1.0, (root.t - 900.0) / 550.0))
        readonly property real unlockRetract: Math.max(0.0, Math.min(1.0, (root.u - 240.0) / 360.0))

        width: {
            if (root.phase === "locking") return root.width * root.easeOutCubic(lockUnroll)
            if (root.phase === "unlocking") return root.width * (1.0 - root.easeInCubic(unlockRetract))
            return root.width
        }

        opacity: width > 10 ? 1.0 : 0.0
    }

    // ── Notifications Overlay (Widget 3: Unlock retract 200-550ms) ──
    LockNotificationOverlay {
        id: notifOverlay
        notificationServer: root.notificationServer
        anchors.left: parent.left
        anchors.leftMargin: 36
        anchors.bottomMargin: 14
        anchors.bottom: mediaOverlay.top

        readonly property real unlockP: Math.max(0.0, Math.min(1.0, (root.u - 200.0) / 350.0))
        readonly property real s: root.phase === "unlocking" ? (1.0 - root.easeInCubic(unlockP)) : 1.0

        opacity: Math.pow(notifOverlay.s, 0.70)
    }
}

