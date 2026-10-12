import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../../Singletons"

/**
 * LockSurface:
 * Fullscreen WlSessionLockSurface that serves as the single stage for
 * both lock and unlock transitions (lock-first architecture).
 *
 * Implements:
 * 1. Sharp wallpaper + pre-blurred cached texture via ShaderEffect radial wipe.
 * 2. Identical first frame: desktop resting nucleus dot & rings rendered at t=0.
 * 3. Single timeline: all visuals are pure deterministic functions of LockTransition.t / u.
 * 4. First-Frame Safety: waits for first frameSwapped before advancing t.
 * 5. Unlock: reverse timeline plays inside the lock surface; locked dropped only on final frameSwapped.
 */
WlSessionLockSurface {
    id: root

    signal requestUnlock()
    signal requestUnlockFinish()
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
        var x = Math.max(0.0, Math.min(1.0, p))
        return x * x * x
    }

    function easeOutCubic(p) {
        var x = Math.max(0.0, Math.min(1.0, p))
        return 1.0 - Math.pow(1.0 - x, 3.0)
    }

    function easeInOutCubic(p) {
        var x = Math.max(0.0, Math.min(1.0, p))
        return x < 0.5 ? 4.0 * x * x * x : 1.0 - Math.pow(-2.0 * x + 2.0, 3.0) / 2.0
    }

    /* ── First-Frame Safety & Unlock Finalization ────────────────────────── */
    property bool firstFrameSeen: false
    property bool waitingUnlockFinalFrame: false

    FrameAnimation {
        id: surfaceFrameDriver
        running: true
        onTriggered: {
            if (!root.firstFrameSeen) {
                root.firstFrameSeen = true
                console.log("[LockSurface] First rendered frame detected -> starting lock transition")
                LockTransition.notifyLockSurfaceReady()
            }
            if (root.waitingUnlockFinalFrame) {
                root.waitingUnlockFinalFrame = false
                console.log("[LockSurface] Final unlock frame reached -> requesting session lock release")
                root.requestUnlockFinish()
            }
        }
    }

    Connections {
        target: LockTransition
        function onUnlockAnimationFinished() {
            root.waitingUnlockFinalFrame = true
        }
    }

    Component.onCompleted: {
        pwdCard.revealed = true
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

    /* ── 1. Wallpaper Background (Sharp base + Pre-Blurred ShaderEffect) ─── */
    // Sharp Base Wallpaper (drawn sharp, identical to desktop)
    Image {
        id: bgSharp
        anchors.fill: parent
        source: "file://" + root.home + "/.cache/carbon/wallpaper_scaled.jpg"
        fillMode: Image.PreserveAspectCrop
        asynchronous: false
        cache: true
    }

    // Pre-blurred and Pre-dimmed texture loaded once from disk cache
    Image {
        id: bgBlurredTexture
        source: "file://" + root.home + "/.cache/carbon/wallpaper_blurred.jpg"
        fillMode: Image.PreserveAspectCrop
        asynchronous: false
        cache: true
        visible: false
    }

    // Radial Blur Wipe ShaderEffect (Single-pass hardware texture blend)
    // On Lock: reveals blurred texture outward from center
    // On Unlock: erases blurred texture outward from center (invert = 1.0)
    readonly property real maxBlurRadius: root.screenDiag * 0.58 + 80.0
    readonly property real blurRadius: {
        if (root.phase === "locking") {
            if (root.t < 280.0) return 0.0
            var p = Math.max(0.0, Math.min(1.0, (root.t - 280.0) / 500.0))
            return root.easeInOutCubic(p) * root.maxBlurRadius
        }
        if (root.phase === "locked") return root.maxBlurRadius
        if (root.phase === "unlocking") {
            if (root.u < 300.0) return 0.0
            var up = Math.max(0.0, Math.min(1.0, (root.u - 300.0) / 800.0))
            return root.easeInOutCubic(up) * root.maxBlurRadius
        }
        return 0.0
    }

    ShaderEffect {
        id: blurShader
        anchors.fill: parent
        visible: (root.blurRadius > 0.1) || (root.phase === "locked") || (root.phase === "unlocking")

        property vector2d center: Qt.vector2d(root.centerX, root.centerY)
        property vector2d screenSize: Qt.vector2d(root.width, root.height)
        property real radius: root.blurRadius
        property real softness: 70.0
        property real invert: (root.phase === "unlocking") ? 1.0 : 0.0
        property var source: bgBlurredTexture

        fragmentShader: Qt.resolvedUrl("../../shaders/blur_front.frag.qsb")
    }

    // Shockwave Ring riding the blur front
    readonly property real shockAlpha: {
        if (root.phase === "locking") {
            if (root.t < 280.0 || root.t > 850.0) return 0.0
            var p = Math.max(0.0, Math.min(1.0, (root.t - 280.0) / 500.0))
            return Math.max(0.0, 0.60 * (1.0 - p))
        }
        if (root.phase === "unlocking") {
            if (root.u < 300.0 || root.u > 1150.0) return 0.0
            var up = Math.max(0.0, Math.min(1.0, (root.u - 300.0) / 800.0))
            return Math.max(0.0, 0.55 * (1.0 - up))
        }
        return 0.0
    }

    Item {
        anchors.fill: parent
        visible: root.shockAlpha > 0.01 && root.blurRadius > 5.0 && root.blurRadius < root.maxBlurRadius

        Rectangle {
            x: root.centerX - root.blurRadius - 3.5
            y: root.centerY - root.blurRadius - 3.5
            width: (root.blurRadius + 3.5) * 2
            height: width
            radius: width / 2
            color: "transparent"
            border.color: Qt.rgba(1, 1, 1, root.shockAlpha * 0.35)
            border.width: 7.0
        }

        Rectangle {
            x: root.centerX - root.blurRadius
            y: root.centerY - root.blurRadius
            width: root.blurRadius * 2
            height: width
            radius: width / 2
            color: "transparent"
            border.color: Qt.rgba(1, 1, 1, root.shockAlpha)
            border.width: 1.6
        }
    }

    /* ── 2. Center Assembly: Desktop Resting Nucleus & Bohr Atom ─────────── */
    // Hub implosion progress (0 -> 1 during lock 0-250ms; reverse during unlock 800-1400ms)
    readonly property real hubProgress: Math.max(0.0, Math.min(1.0, root.t / 250.0))
    readonly property real hubRestoreProgress: Math.max(0.0, Math.min(1.0, (root.u - 800.0) / 600.0))

    // Desktop resting nucleus (identical to desktop resting dot & rings for seamless t=0)
    Item {
        id: desktopRestingNucleus
        x: root.centerX - width / 2
        y: root.centerY - height / 2
        width: 80
        height: 80
        visible: opacity > 0.001

        scale: {
            if (root.phase === "locking") return Math.max(0.0, 1.0 - root.easeInCubic(root.hubProgress))
            if (root.phase === "unlocking") return root.easeOutCubic(root.hubRestoreProgress)
            if (root.phase === "locked") return 0.0
            return 1.0
        }
        opacity: scale

        // Ring 1 (Inner, 2 electrons)
        Rectangle {
            anchors.centerIn: parent
            width: 40; height: 40; radius: 20
            color: "transparent"
            border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.22)
            border.width: 1

            Item {
                anchors.centerIn: parent
                width: parent.width; height: parent.height
                Rectangle { anchors.horizontalCenter: parent.horizontalCenter; y: -3.5; width: 6; height: 6; radius: 3; color: Theme.accent }
                Rectangle { anchors.horizontalCenter: parent.horizontalCenter; y: parent.height - 2.5; width: 6; height: 6; radius: 3; color: Theme.accent }
            }
        }

        // Ring 2 (Outer, 4 electrons)
        Rectangle {
            anchors.centerIn: parent
            width: 72; height: 72; radius: 36
            color: "transparent"
            border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16)
            border.width: 1

            Item {
                anchors.centerIn: parent
                width: parent.width; height: parent.height
                rotation: 45
                Repeater {
                    model: 4
                    delegate: Item {
                        anchors.fill: parent
                        rotation: index * 90
                        Rectangle { anchors.horizontalCenter: parent.horizontalCenter; y: -3.5; width: 6; height: 6; radius: 3; color: Theme.accent }
                    }
                }
            }
        }

        // 16px center dot
        Rectangle {
            anchors.centerIn: parent
            width: 16; height: 16; radius: 8
            color: Theme.accent
            border.color: "#FFFFFF"
            border.width: 1.0
        }
    }

    // Unified Bohr Atom (Carbon)
    UnifiedCarbonAtom {
        id: carbonAtom
        x: root.centerX - width / 2
        y: root.centerY - height / 2
        width: 120
        height: 120
        visible: opacity > 0.001

        scale: {
            if (root.phase === "locking") return root.easeOutCubic(root.hubProgress)
            if (root.phase === "unlocking") return Math.max(0.0, 1.0 - root.easeInCubic(root.hubRestoreProgress))
            if (root.phase === "locked") return 1.0
            return 0.0
        }
        opacity: scale
    }

    // Password Card (Fades in smoothly underneath the Bohr atom)
    readonly property real pwdLockP: Math.max(0.0, Math.min(1.0, (root.t - 700.0) / 500.0))
    readonly property real pwdUnlockP: Math.max(0.0, 1.0 - root.u / 250.0)

    PasswordCard {
        id: pwdCard
        anchors.horizontalCenter: carbonAtom.horizontalCenter
        anchors.top: carbonAtom.bottom
        anchors.topMargin: 12
        revealed: root.phase === "locked" || (root.phase === "locking" && root.t >= 700.0)
        opacity: {
            if (root.phase === "locking") return root.easeOutCubic(root.pwdLockP)
            if (root.phase === "unlocking") return root.pwdUnlockP
            if (root.phase === "locked") return (revealed ? 1.0 : 0.0)
            return 0.0
        }
        transform: Translate {
            y: {
                if (root.phase === "locking") return 24.0 * (1.0 - root.easeOutCubic(root.pwdLockP))
                if (root.phase === "unlocking") return 24.0 * (1.0 - root.pwdUnlockP)
                return 0.0
            }
        }
        onUnlocked: root.startUnlock()
    }

    /* ── 3. Smooth Bezier Glide for Widgets ──────────────────────────────── */
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

    // Bottom-Right Clock
    readonly property real clockLockP: Math.max(0.0, Math.min(1.0, (root.t - 500.0) / 600.0))
    readonly property real clockUnlockP: Math.max(0.0, Math.min(1.0, (root.u - 200.0) / 450.0))
    readonly property real clockS: {
        if (root.phase === "locking") return root.easeOutCubic(clockLockP)
        if (root.phase === "unlocking") return 1.0 - root.easeInCubic(clockUnlockP)
        if (root.phase === "locked") return 1.0
        return 0.0
    }
    readonly property point clockOffset: root.getBezierOffset(root.width - 40 - lockClock.width / 2, root.height - 36 - lockClock.height / 2, clockS)

    LockClock {
        id: lockClock
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 40
        anchors.bottomMargin: 36
        stageDriven: true
        opacity: root.clockS
        transform: Translate {
            x: root.clockOffset.x
            y: root.clockOffset.y
        }
    }

    // Bottom-Left Media Card
    readonly property real mediaLockP: Math.max(0.0, Math.min(1.0, (root.t - 650.0) / 550.0))
    readonly property real mediaUnlockP: Math.max(0.0, Math.min(1.0, (root.u - 240.0) / 400.0))
    readonly property real mediaS: {
        if (root.phase === "locking") return root.easeOutCubic(mediaLockP)
        if (root.phase === "unlocking") return 1.0 - root.easeInCubic(mediaUnlockP)
        if (root.phase === "locked") return 1.0
        return 0.0
    }
    readonly property point mediaOffset: root.getBezierOffset(36 + mediaOverlay.width / 2, root.height - 36 - mediaOverlay.height / 2, mediaS)

    LockMediaOverlay {
        id: mediaOverlay
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: 36
        anchors.bottomMargin: 36
        stageDriven: true
        opacity: root.mediaS
        scale: 0.35 + 0.65 * root.mediaS
        transform: Translate {
            x: root.mediaOffset.x
            y: root.mediaOffset.y
        }
    }

    // Top Cava Visualizer
    readonly property real cavaLockP: Math.max(0.0, Math.min(1.0, (root.t - 750.0) / 450.0))
    readonly property real cavaUnlockP: Math.max(0.0, Math.min(1.0, (root.u - 240.0) / 360.0))
    readonly property real cavaWidth: {
        if (root.phase === "locking") return root.width * root.easeOutCubic(cavaLockP)
        if (root.phase === "unlocking") return root.width * (1.0 - root.easeInCubic(cavaUnlockP))
        if (root.phase === "locked") return root.width
        return 0.0
    }

    LockCavaVisualizer {
        id: topVisualizer
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        height: 70
        stageDriven: true
        width: root.cavaWidth
        opacity: width > 10 ? 1.0 : 0.0
    }

    // Notifications Overlay
    LockNotificationOverlay {
        id: notifOverlay
        notificationServer: root.notificationServer
        anchors.left: parent.left
        anchors.leftMargin: 36
        anchors.bottomMargin: 14
        anchors.bottom: mediaOverlay.top
        opacity: root.phase === "unlocking" ? Math.max(0.0, 1.0 - root.u / 250.0) : 1.0
    }

    /* ── 4. Debug HUD ────────────────────────────────────────────────────── */
    Rectangle {
        visible: LockTransition.debugTimeline
        z: 9999
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: 14
        width: debugCol.width + 16
        height: debugCol.height + 12
        radius: 6
        color: "#CC050508"
        border.color: "#00F0FF"
        border.width: 1

        Column {
            id: debugCol
            anchors.centerIn: parent
            spacing: 3
            Text {
                text: "Phase: " + LockTransition.phase + " | t: " + Math.round(LockTransition.t) + "ms | u: " + Math.round(LockTransition.u) + "ms"
                color: "#00F0FF"
                font.family: "monospace"
                font.pixelSize: 12
                font.bold: true
            }
            Text {
                text: "Frame: " + LockTransition.lastFrameTimeMs.toFixed(1) + "ms (" + (LockTransition.lastFrameTimeMs > 0 ? (1000.0 / LockTransition.lastFrameTimeMs).toFixed(0) : 60) + " fps) | min=" + LockTransition.minFrameTimeMs.toFixed(1) + " avg=" + LockTransition.avgFrameTimeMs.toFixed(1) + " max=" + LockTransition.maxFrameTimeMs.toFixed(1)
                color: "#A6E3A1"
                font.family: "monospace"
                font.pixelSize: 11
            }
        }
    }
}
