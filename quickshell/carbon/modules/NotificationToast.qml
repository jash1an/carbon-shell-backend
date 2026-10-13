import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import "../Singletons"

/**
 * NotificationToast.qml
 *
 * New-notification toast:
 * - Appears when a new notification arrives.
 * - Suppressed when Do Not Disturb is active.
 * - Auto-dismisses after a timeout (default ~5s).
 * - Click marks read and opens the notification panel.
 * - Top-right position with margin.
 * - Swipe sideways to dismiss or hover X button.
 * - Glass styling consistent with Carbon shell design.
 */
Rectangle {
    id: root

    property var toastItem: null
    property bool active: false

    width: 320
    implicitHeight: toastContentCol.implicitHeight + 24
    radius: 20
    color: Qt.rgba(15/255, 20/255, 22/255, 0.78)
    border.width: 1
    border.color: Qt.rgba(255/255, 255/255, 255/255, 0.16)
    clip: true

    layer.enabled: true
    layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: "#000000"
        shadowOpacity: 0.50
        shadowBlur: 0.80
        shadowVerticalOffset: 16
    }

    // Theme-Sensitive Subtle Radial Accent Glow confined strictly inside toast
    Rectangle {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: -30
        anchors.rightMargin: -30
        width: 100
        height: 100
        radius: 50
        color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16)
    }

    // Top highlight
    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        height: 1
        color: Qt.rgba(255/255, 255/255, 255/255, 0.22)
    }

    // Swipe offset & animations
    property real swipeX: 0
    property real toastProgress: active ? 1.0 : 0.0

    Behavior on toastProgress {
        NumberAnimation {
            duration: 280
            easing.type: Easing.OutBack
            easing.overshoot: 1.15
        }
    }

    Behavior on swipeX {
        NumberAnimation {
            duration: 200
            easing.type: Easing.OutCubic
        }
    }

    opacity: Math.max(0.0, toastProgress * (1.0 - (Math.abs(swipeX) / 160.0)))
    scale: 0.90 + (0.10 * toastProgress)

    // Signals
    signal openPanelRequested()

    Timer {
        id: autoDismissTimer
        interval: {
            if (root.toastItem && root.toastItem.expireTimeout > 0) {
                return root.toastItem.expireTimeout
            }
            return 5000
        }
        repeat: false
        onTriggered: {
            root.dismissToast()
        }
    }

    Connections {
        target: NotificationService
        function onNotificationArrived(item) {
            // Suppress toast if DND is on
            if (NotificationService.dnd) return
            root.showToast(item)
        }
    }

    function showToast(item) {
        root.toastItem = item
        root.swipeX = 0
        root.active = true
        autoDismissTimer.restart()
    }

    function dismissToast() {
        autoDismissTimer.stop()
        root.active = false
    }

    // App tint
    function getAppColor(appName) {
        var str = appName || "app"
        var hash = 0
        for (var i = 0; i < str.length; i++) {
            hash = str.charCodeAt(i) + ((hash << 5) - hash)
        }
        var h = Math.abs(hash % 360) / 360.0
        return Qt.hsla(h, 0.65, 0.60, 1.0)
    }

    readonly property color appTint: getAppColor(root.toastItem ? root.toastItem.appName : "")

    MouseArea {
        id: toastMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        property real startX: 0
        property real startY: 0
        property bool isDragging: false

        onEntered: {
            autoDismissTimer.stop()
        }

        onExited: {
            if (root.active) {
                autoDismissTimer.restart()
            }
        }

        onPressed: (mouse) => {
            startX = mouse.x
            startY = mouse.y
            isDragging = false
            autoDismissTimer.stop()
        }

        onPositionChanged: (mouse) => {
            if (pressed) {
                var dx = mouse.x - startX
                var dy = mouse.y - startY
                if (!isDragging && Math.abs(dx) > 8 && Math.abs(dx) > Math.abs(dy)) {
                    isDragging = true
                }
                if (isDragging) {
                    root.swipeX = dx
                }
            }
        }

        onReleased: (mouse) => {
            if (isDragging) {
                if (Math.abs(root.swipeX) > 80) {
                    root.dismissToast()
                } else {
                    root.swipeX = 0
                    autoDismissTimer.restart()
                }
                isDragging = false
            }
        }

        onClicked: {
            if (!isDragging && Math.abs(root.swipeX) < 6) {
                if (root.toastItem && root.toastItem.unread) {
                    NotificationService.markRead(root.toastItem.id)
                }
                root.dismissToast()
                root.openPanelRequested()
            }
        }
    }

    // Top Right Close "X" Button
    Rectangle {
        id: closeToastBtn
        z: 10
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 10
        anchors.rightMargin: 10
        width: 22
        height: 22
        radius: 11
        color: closeToastMouse.containsMouse ? Qt.rgba(255/255, 255/255, 255/255, 0.25) : Qt.rgba(255/255, 255/255, 255/255, 0.12)
        visible: toastMouse.containsMouse || closeToastMouse.containsMouse

        Text {
            anchors.centerIn: parent
            text: "close"
            font.family: Theme.fontIcon
            font.pixelSize: 13
            color: "#f4f6f5"
        }

        MouseArea {
            id: closeToastMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                root.dismissToast()
            }
        }
    }

    // Toast Content Layout
    ColumnLayout {
        id: toastContentCol
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        // Header: Icon tile 32px, App name, Time
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Rectangle {
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                radius: 10
                color: Qt.rgba(root.appTint.r, root.appTint.g, root.appTint.b, 0.25)
                border.width: 1
                border.color: Qt.rgba(root.appTint.r, root.appTint.g, root.appTint.b, 0.50)

                Image {
                    id: toastIconImg
                    anchors.centerIn: parent
                    width: 18
                    height: 18
                    fillMode: Image.PreserveAspectFit
                    source: {
                        var icon = root.toastItem ? (root.toastItem.appIcon || "") : ""
                        if (!icon) return ""
                        if (icon.indexOf("/") !== -1 || icon.startsWith("file:")) return icon
                        return ""
                    }
                    visible: status === Image.Ready && source !== ""
                }

                Text {
                    anchors.centerIn: parent
                    visible: !toastIconImg.visible
                    text: {
                        var n = root.toastItem ? (root.toastItem.appName || "") : ""
                        return n.length > 0 ? n.charAt(0).toUpperCase() : "A"
                    }
                    font.family: "Manrope"
                    font.pixelSize: 14
                    font.weight: Font.ExtraBold
                    color: root.appTint
                }
            }

            Text {
                text: root.toastItem ? (root.toastItem.appName || "Notification") : ""
                font.family: "Manrope"
                font.pixelSize: 12
                font.weight: Font.Bold
                color: Qt.rgba(244/255, 246/255, 245/255, 0.75)
                elide: Text.ElideRight
                Layout.maximumWidth: 160
            }

            Item { Layout.fillWidth: true }

            Text {
                visible: !closeToastBtn.visible
                text: "Now"
                font.family: "Manrope"
                font.pixelSize: 10
                font.weight: Font.Medium
                color: Qt.rgba(244/255, 246/255, 245/255, 0.40)
            }
        }

        // Summary
        Text {
            Layout.fillWidth: true
            text: root.toastItem ? (root.toastItem.summary || "") : ""
            font.family: "Manrope"
            font.pixelSize: 13
            font.weight: Font.ExtraBold
            color: "#ffffff"
            elide: Text.ElideRight
            maximumLineCount: 1
            visible: text.length > 0
        }

        // Body
        Text {
            Layout.fillWidth: true
            text: root.toastItem ? (root.toastItem.body || "") : ""
            font.family: "Manrope"
            font.pixelSize: 12
            font.weight: Font.Medium
            color: Qt.rgba(244/255, 246/255, 245/255, 0.70)
            wrapMode: Text.Wrap
            elide: Text.ElideRight
            maximumLineCount: 2
            visible: text.length > 0
        }
    }
}
