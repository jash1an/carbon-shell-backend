import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import "../Singletons"

/**
 * NotificationCard.qml
 *
 * Requirements:
 * - Radius 21px. Icon tile 38px, radius 13, tinted with the app's color.
 * - App name (muted), a coral unread dot, and the time label on the right.
 * - Title (14px, weight 800), body (12.5px, muted, clamped to 2 lines when collapsed).
 * - Unread cards have a slightly brighter gradient and border. Read cards are flatter.
 * - Click expands the card (body unclamps, action buttons slide open) and marks it read.
 * - Action buttons: the first is a white pill (primary, dismisses the card),
 *   the rest are ghost pills (mark read and collapse).
 * - Hover reveals a small round X (top-right) that dismisses the card.
 */
Rectangle {
    id: root

    required property var notifItem
    required property int cardIndex

    // Expanded state
    property bool expanded: false

    // Signals
    signal dismissRequested(var item)
    signal actionInvoked(var item, var actionObj)

    readonly property bool isUnread: root.notifItem ? root.notifItem.unread : false
    readonly property var actionsList: (root.notifItem && root.notifItem.actions) ? root.notifItem.actions : []
    readonly property bool hasActions: actionsList.length > 0

    width: parent ? parent.width : 344
    implicitHeight: mainCol.implicitHeight + 28
    radius: 21

    // Colors & Glass Styling per specs
    // Unread cards have slightly brighter gradient & border. Read cards are flatter.
    gradient: Gradient {
        GradientStop {
            position: 0.0
            color: root.isUnread ? Qt.rgba(255/255, 255/255, 255/255, 0.12) : Qt.rgba(255/255, 255/255, 255/255, 0.05)
        }
        GradientStop {
            position: 1.0
            color: root.isUnread ? Qt.rgba(255/255, 255/255, 255/255, 0.06) : Qt.rgba(255/255, 255/255, 255/255, 0.02)
        }
    }

    border.width: 1
    border.color: root.isUnread 
                  ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35) 
                  : Qt.rgba(255/255, 255/255, 255/255, 0.08)

    // Theme-Sensitive Subtle Radial Accent Glow confined strictly inside the notification card
    Rectangle {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: -30
        anchors.rightMargin: -30
        width: 110
        height: 110
        radius: 55
        visible: root.isUnread
        color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16)
    }

    // Generate dynamic color tint from appName
    function getAppColor(appName) {
        var str = appName || "app"
        var hash = 0
        for (var i = 0; i < str.length; i++) {
            hash = str.charCodeAt(i) + ((hash << 5) - hash)
        }
        var h = Math.abs(hash % 360) / 360.0
        return Qt.hsla(h, 0.65, 0.60, 1.0)
    }

    readonly property color appTint: getAppColor(root.notifItem ? root.notifItem.appName : "")

    // Drag swipe offset
    property real swipeX: 0
    property bool isDismissing: false

    x: swipeX
    opacity: isDismissing ? 0.0 : Math.max(0.0, 1.0 - (Math.abs(swipeX) / 180.0))

    Behavior on swipeX {
        NumberAnimation {
            duration: 220
            easing.type: Easing.OutCubic
        }
    }

    Behavior on opacity {
        NumberAnimation {
            duration: 180
            easing.type: Easing.OutCubic
        }
    }

    Behavior on implicitHeight {
        NumberAnimation {
            duration: 240
            easing.type: Easing.OutCubic
        }
    }

    SequentialAnimation {
        id: dismissAnim
        ParallelAnimation {
            NumberAnimation {
                target: root
                property: "swipeX"
                to: root.swipeX < 0 ? -380 : 380
                duration: 200
                easing.type: Easing.InCubic
            }
            NumberAnimation {
                target: root
                property: "opacity"
                to: 0.0
                duration: 200
                easing.type: Easing.InCubic
            }
        }
        ScriptAction {
            script: {
                root.dismissRequested(root.notifItem)
            }
        }
    }

    function dismissWithAnimation() {
        if (root.isDismissing) return
        root.isDismissing = true
        dismissAnim.restart()
    }

    MouseArea {
        id: cardMouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        property real startX: 0
        property real startY: 0
        property bool isDragging: false

        onPressed: (mouse) => {
            startX = mouse.x
            startY = mouse.y
            isDragging = false
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
                if (Math.abs(root.swipeX) > 90) {
                    root.dismissWithAnimation()
                } else {
                    root.swipeX = 0
                }
                isDragging = false
            }
        }

        onCanceled: {
            root.swipeX = 0
            isDragging = false
        }

        onClicked: (mouse) => {
            if (!isDragging && Math.abs(root.swipeX) < 6) {
                if (root.notifItem && root.notifItem.unread) {
                    NotificationService.markRead(root.notifItem.id)
                }
                root.expanded = !root.expanded
            }
        }
    }

    // Top Right Hover Close "X" Button
    Rectangle {
        id: closeBtn
        z: 10
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 10
        anchors.rightMargin: 10
        width: 22
        height: 22
        radius: 11
        color: closeMouse.containsMouse ? Qt.rgba(255/255, 255/255, 255/255, 0.25) : Qt.rgba(255/255, 255/255, 255/255, 0.12)
        visible: cardMouseArea.containsMouse || closeMouse.containsMouse

        Text {
            anchors.centerIn: parent
            text: "close"
            font.family: Theme.fontIcon
            font.pixelSize: 13
            color: "#f4f6f5"
        }

        MouseArea {
            id: closeMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                root.dismissWithAnimation()
            }
        }
    }

    // Main Layout Content
    ColumnLayout {
        id: mainCol
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        // Header Row: Icon tile 38px, App name, Coral unread dot, Time label
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            // Icon Tile 38px, radius 13, tinted with app's color
            Rectangle {
                Layout.preferredWidth: 38
                Layout.preferredHeight: 38
                radius: 13
                color: Qt.rgba(root.appTint.r, root.appTint.g, root.appTint.b, 0.22)
                border.width: 1
                border.color: Qt.rgba(root.appTint.r, root.appTint.g, root.appTint.b, 0.45)

                Image {
                    id: iconImg
                    anchors.centerIn: parent
                    width: 22
                    height: 22
                    fillMode: Image.PreserveAspectFit
                    source: {
                        var icon = root.notifItem ? (root.notifItem.appIcon || "") : ""
                        if (!icon) return ""
                        if (icon.indexOf("/") !== -1 || icon.startsWith("file:")) return icon
                        return ""
                    }
                    visible: status === Image.Ready && source !== ""
                }

                Text {
                    anchors.centerIn: parent
                    visible: !iconImg.visible
                    text: {
                        var n = root.notifItem ? (root.notifItem.appName || "") : ""
                        return n.length > 0 ? n.charAt(0).toUpperCase() : "A"
                    }
                    font.family: "Manrope"
                    font.pixelSize: 16
                    font.weight: Font.ExtraBold
                    color: root.appTint
                }
            }

            // App Name & Unread Dot
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    text: root.notifItem ? (root.notifItem.appName || "Application") : ""
                    font.family: "Manrope"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    color: Qt.rgba(244/255, 246/255, 245/255, 0.66) // Muted at 66%
                    elide: Text.ElideRight
                    Layout.maximumWidth: 160
                }

                // Theme-sensitive unread dot
                Rectangle {
                    visible: root.isUnread
                    Layout.preferredWidth: 6
                    Layout.preferredHeight: 6
                    radius: 3
                    color: Theme.accent || "#f2705f"
                }

                Item { Layout.fillWidth: true }
            }

            // Time Label (right)
            Text {
                visible: !closeBtn.visible
                text: root.notifItem ? (root.notifItem.timeStr || "") : ""
                font.family: "Manrope"
                font.pixelSize: 11
                font.weight: Font.Medium
                color: Qt.rgba(244/255, 246/255, 245/255, 0.40) // Muted at 40%
                Layout.alignment: Qt.AlignRight
            }
        }

        // Title: 14px, weight 800
        Text {
            Layout.fillWidth: true
            text: root.notifItem ? (root.notifItem.summary || "") : ""
            font.family: "Manrope"
            font.pixelSize: 14
            font.weight: Font.ExtraBold
            color: "#f4f6f5"
            wrapMode: Text.Wrap
            maximumLineCount: root.expanded ? 4 : 1
            elide: Text.ElideRight
            visible: text.length > 0
        }

        // Body: 12.5px, muted, clamped to 2 lines when collapsed
        Text {
            Layout.fillWidth: true
            text: root.notifItem ? (root.notifItem.body || "") : ""
            font.family: "Manrope"
            font.pixelSize: 13
            font.weight: Font.Medium
            color: Qt.rgba(244/255, 246/255, 245/255, 0.66) // Muted at 66%
            wrapMode: Text.Wrap
            maximumLineCount: root.expanded ? 12 : 2
            elide: Text.ElideRight
            visible: text.length > 0
        }

        // Action Buttons Row (visible when expanded and hasActions)
        Item {
            Layout.fillWidth: true
            implicitHeight: actionButtonsRow.implicitHeight
            visible: root.expanded && root.hasActions

            RowLayout {
                id: actionButtonsRow
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: 8

                Repeater {
                    model: root.actionsList

                    delegate: Rectangle {
                        id: actBtn
                        required property int index
                        required property var modelData

                        readonly property bool isPrimary: actBtn.index === 0

                        Layout.preferredHeight: 30
                        Layout.preferredWidth: actBtnText.implicitWidth + 24
                        radius: 15

                        // Primary is white pill; others are ghost pills
                        color: actBtn.isPrimary 
                               ? (actMouse.containsMouse ? "#ffffff" : Qt.rgba(255/255, 255/255, 255/255, 0.90))
                               : (actMouse.containsMouse ? Qt.rgba(255/255, 255/255, 255/255, 0.16) : Qt.rgba(255/255, 255/255, 255/255, 0.08))
                        border.width: actBtn.isPrimary ? 0 : 1
                        border.color: Qt.rgba(255/255, 255/255, 255/255, 0.18)

                        Text {
                            id: actBtnText
                            anchors.centerIn: parent
                            text: actBtn.modelData.text || "Action"
                            font.family: "Manrope"
                            font.pixelSize: 12
                            font.weight: actBtn.isPrimary ? Font.Bold : Font.DemiBold
                            color: actBtn.isPrimary ? "#0f1416" : "#f4f6f5"
                        }

                        MouseArea {
                            id: actMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (actBtn.isPrimary) {
                                    root.actionInvoked(root.notifItem, actBtn.modelData)
                                    root.dismissWithAnimation()
                                } else {
                                    root.actionInvoked(root.notifItem, actBtn.modelData)
                                    root.expanded = false
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
