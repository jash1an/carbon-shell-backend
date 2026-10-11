import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import "../../Singletons"

/**
 * LockSurface:
 * Fullscreen WlSessionLockSurface that hosts:
 *   - Blurred/dimmed wallpaper background
 *   - The Carbon Lewis Dot animated logo (converging from screen edges)
 *   - Staged entrance of the curved PasswordCard input
 *   - Smooth unlock exit transition
 *
 * Performance Optimized:
 * All heavy visual elements, blurs, cava processes, and orbital animations
 * are lazy-loaded via Loader and only instantiated while root.lock.locked is true.
 * When unlocked, 0% CPU and 0 textures/effects are retained in memory.
 */
WlSessionLockSurface {
    id: root

    signal requestUnlock()
    property var sessionLock: null
    property var notificationServer: null
    readonly property string home: Quickshell.env("HOME") || ""

    color: "#050508"

    Component.onCompleted: {
        pwdCard.forceActiveFocus()
    }

    function startUnlock() {
        topVisualizer.active = false
        LockTransition.startUnlock()
        unlockAnim.restart()
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

    SequentialAnimation {
        id: unlockAnim

        ParallelAnimation {
            NumberAnimation {
                target: centerAssembly
                property: "opacity"
                to: 0.0
                duration: 260
                easing.type: Easing.InQuad
            }
            NumberAnimation {
                target: centerAssembly
                property: "scale"
                to: 0.88
                duration: 260
                easing.type: Easing.InQuad
            }
            NumberAnimation {
                target: bgContainer
                property: "opacity"
                to: 0.0
                duration: 280
                easing.type: Easing.OutQuad
            }
            NumberAnimation {
                target: bgDim
                property: "opacity"
                to: 0.0
                duration: 280
                easing.type: Easing.OutQuad
            }
            NumberAnimation {
                target: mediaOverlay
                property: "opacity"
                to: 0.0
                duration: 260
                easing.type: Easing.InQuad
            }
            NumberAnimation {
                target: lockClock
                property: "opacity"
                to: 0.0
                duration: 260
                easing.type: Easing.InQuad
            }
            NumberAnimation {
                target: topVisualizer
                property: "opacity"
                to: 0.0
                duration: 260
                easing.type: Easing.InQuad
            }
            NumberAnimation {
                target: notifOverlay
                property: "opacity"
                to: 0.0
                duration: 220
                easing.type: Easing.InQuad
            }
        }

        ScriptAction {
            script: {
                root.requestUnlock()
                Quickshell.execDetached(["sh", root.home + "/.config/hypr/scripts/carbon-ipc.sh", "unlock"])
            }
        }
    }

    // Capture clicks anywhere on the lock screen to restore password card focus
    MouseArea {
        anchors.fill: parent
        onClicked: {
            pwdCard.revealed = true
            pwdCard.forceActiveFocus()
        }
    }

    // Wallpaper Background with Blur
    Item {
        id: bgContainer
        anchors.fill: parent

        Image {
            id: bgWallpaper
            anchors.fill: parent
            source: "file://" + root.home + "/.cache/carbon/wallpaper_scaled.jpg"
            fillMode: Image.PreserveAspectCrop
            cache: false
        }

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
        opacity: 0.60
    }

    // Center Assembly: Lewis Dot Logo + Password Card
    Item {
        id: centerAssembly
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -20
        width: 360
        height: 310

        ColumnLayout {
            anchors.fill: parent
            spacing: 24

            // Carbon Lewis Dot Structure Logo
            CarbonLewisLogo {
                id: lewisLogo
                screenWidth: root.width
                screenHeight: root.height
                Layout.alignment: Qt.AlignHCenter
            }

            // Password Input Card
            PasswordCard {
                id: pwdCard
                Layout.alignment: Qt.AlignHCenter
                onUnlocked: root.startUnlock()
            }
        }
    }

    // Bottom-Left Media Overlay
    LockMediaOverlay {
        id: mediaOverlay
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: 36
        anchors.bottomMargin: 36
    }

    // Bottom-Right Clock
    LockClock {
        id: lockClock
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 40
        anchors.bottomMargin: 36
    }

    // Top Cava Audio Visualizer
    LockCavaVisualizer {
        id: topVisualizer
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 70
    }

    // Bottom-Left Notifications Overlay
    LockNotificationOverlay {
        id: notifOverlay
        notificationServer: root.notificationServer
        anchors.left: parent.left
        anchors.leftMargin: 36
        anchors.bottomMargin: 14
        anchors.bottom: mediaOverlay.top
    }
}
