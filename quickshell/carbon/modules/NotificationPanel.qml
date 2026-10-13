import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import "../Singletons"

/**
 * NotificationPanel.qml
 *
 * Requirements:
 * - Width 344px, height up to 480px.
 * - Glass panel styling:
 *   - Background rgba(15,20,22, 0.6)
 *   - Faint coral radial glow at top-right
 *   - Border 1px rgba(255,255,255, 0.11), radius 30px
 *   - Shadow 0 34px 90px rgba(0,0,0, 0.6), inner top highlight
 * - Header:
 *   - "Notifications" (19px, weight 800)
 *   - Subtitle: "N new", "All caught up", or "Do not disturb is on"
 *   - Two 34px round icon buttons:
 *     - DND (moon) - turns lavender (#c9d0ff, dark icon) when active
 *     - Clear all (trash)
 * - Tabs: All / Chat / System in a pill track with sliding indicator
 * - Scrollable list grouped under:
 *   - "New" (with "Mark all read" link in coral)
 *   - "Earlier"
 *   - Hide a group when it's empty. Fade top and bottom edges; hide scrollbar.
 * - Empty state:
 *   - Breathing round orb with a bell, "All quiet", and a one-line hint.
 * - Footer hint: "Click to expand, swipe sideways to dismiss"
 */
Rectangle {
    id: root

    property bool open: false
    signal closeRequested()

    width: 344
    implicitHeight: 480
    radius: 30
    color: Qt.rgba(15/255, 20/255, 22/255, 0.60)
    border.width: 1
    border.color: Qt.rgba(255/255, 255/255, 255/255, 0.11)
    clip: true

    // MultiEffect Shadow & Blur container
    layer.enabled: true
    layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: "#000000"
        shadowOpacity: 0.60
        shadowBlur: 0.90
        shadowVerticalOffset: 34
    }

    // Top-Right Faint Coral Radial Glow
    Rectangle {
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: -60
        anchors.rightMargin: -60
        width: 180
        height: 180
        radius: 90
        color: "transparent"
        border.width: 0

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: Qt.rgba(242/255, 112/255, 95/255, 0.14) // Coral #f2705f glow
        }
    }

    // Inner Top Highlight
    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 20
        anchors.rightMargin: 20
        height: 1
        color: Qt.rgba(255/255, 255/255, 255/255, 0.20)
    }

    // Active Tab State: 0 = "All", 1 = "Chat", 2 = "System"
    property int currentTab: 0

    // Filtered lists
    readonly property var allItems: NotificationService.list || []
    readonly property var tabItems: {
        var res = []
        for (var i = 0; i < allItems.length; i++) {
            var item = allItems[i]
            if (currentTab === 0) {
                res.push(item)
            } else if (currentTab === 1 && item.category === "chat") {
                res.push(item)
            } else if (currentTab === 2 && item.category === "system") {
                res.push(item)
            }
        }
        return res
    }

    // Subdivided into "New" (unread) and "Earlier" (read)
    readonly property var newGroupItems: {
        var g = []
        for (var i = 0; i < tabItems.length; i++) {
            if (tabItems[i].unread) g.push(tabItems[i])
        }
        return g
    }

    readonly property var earlierGroupItems: {
        var g = []
        for (var i = 0; i < tabItems.length; i++) {
            if (!tabItems[i].unread) g.push(tabItems[i])
        }
        return g
    }

    readonly property int totalCount: tabItems.length
    readonly property int unreadCount: NotificationService.unreadCount

    // Subtitle text computation
    readonly property string subtitleText: {
        if (NotificationService.dnd) return "Do not disturb is on"
        if (root.unreadCount > 0) return root.unreadCount + " new"
        return "All caught up"
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 18
        spacing: 12

        // ── 1. Header ────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    text: "Notifications"
                    font.family: "Manrope"
                    font.pixelSize: 19
                    font.weight: Font.ExtraBold // 800
                    color: "#f4f6f5"
                }

                Text {
                    text: root.subtitleText
                    font.family: "Manrope"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                    color: NotificationService.dnd ? "#c9d0ff" : Qt.rgba(244/255, 246/255, 245/255, 0.66)
                }
            }

            // Top-Right Action Buttons: DND & Clear All (34px round buttons)
            RowLayout {
                spacing: 8

                // DND Button (Moon)
                Rectangle {
                    width: 34
                    height: 34
                    radius: 17
                    color: NotificationService.dnd 
                           ? "#c9d0ff" 
                           : (dndMouse.containsMouse ? Qt.rgba(255/255, 255/255, 255/255, 0.15) : Qt.rgba(255/255, 255/255, 255/255, 0.08))
                    border.width: 1
                    border.color: NotificationService.dnd ? "#c9d0ff" : Qt.rgba(255/255, 255/255, 255/255, 0.12)

                    Text {
                        anchors.centerIn: parent
                        text: "nightlight"
                        font.family: Theme.fontIcon
                        font.pixelSize: 16
                        color: NotificationService.dnd ? "#0f1416" : "#f4f6f5"
                    }

                    MouseArea {
                        id: dndMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            NotificationService.toggleDnd()
                        }
                    }
                }

                // Clear All Button (Trash)
                Rectangle {
                    width: 34
                    height: 34
                    radius: 17
                    color: clearMouse.containsMouse ? Qt.rgba(255/255, 255/255, 255/255, 0.15) : Qt.rgba(255/255, 255/255, 255/255, 0.08)
                    border.width: 1
                    border.color: Qt.rgba(255/255, 255/255, 255/255, 0.12)
                    visible: root.totalCount > 0

                    Text {
                        anchors.centerIn: parent
                        text: "delete"
                        font.family: Theme.fontIcon
                        font.pixelSize: 16
                        color: "#f4f6f5"
                    }

                    MouseArea {
                        id: clearMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            NotificationService.clearAll()
                        }
                    }
                }
            }
        }

        // ── 2. Tabs Track: All / Chat / System ──────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            radius: 18
            color: Qt.rgba(0, 0, 0, 0.25)
            border.width: 1
            border.color: Qt.rgba(255/255, 255/255, 255/255, 0.08)

            // Sliding Indicator
            Rectangle {
                x: root.currentTab * ((parent.width - 6) / 3) + 3
                y: 3
                width: (parent.width - 6) / 3
                height: 30
                radius: 15
                color: Qt.rgba(255/255, 255/255, 255/255, 0.18)
            }

            RowLayout {
                anchors.fill: parent
                anchors.margins: 3
                spacing: 0

                Repeater {
                    model: ["All", "Chat", "System"]

                    delegate: Item {
                        required property int index
                        required property string modelData

                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        Text {
                            anchors.centerIn: parent
                            text: modelData
                            font.family: "Manrope"
                            font.pixelSize: 12
                            font.weight: root.currentTab === index ? Font.Bold : Font.Medium
                            color: root.currentTab === index ? "#ffffff" : Qt.rgba(244/255, 246/255, 245/255, 0.66)
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.currentTab = index
                            }
                        }
                    }
                }
            }
        }

        // ── 3. Scrollable List / Empty State ────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            // Empty State View
            ColumnLayout {
                anchors.centerIn: parent
                spacing: 12
                visible: root.totalCount === 0

                // Breathing round orb with a bell
                Rectangle {
                    Layout.alignment: Qt.AlignHCenter
                    width: 68
                    height: 68
                    radius: 34
                    color: Qt.rgba(255/255, 255/255, 255/255, 0.06)
                    border.width: 1
                    border.color: Qt.rgba(255/255, 255/255, 255/255, 0.12)

                    Text {
                        anchors.centerIn: parent
                        text: "notifications"
                        font.family: Theme.fontIcon
                        font.pixelSize: 28
                        color: Qt.rgba(244/255, 246/255, 245/255, 0.50)
                    }
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "All quiet"
                    font.family: "Manrope"
                    font.pixelSize: 15
                    font.weight: Font.Bold
                    color: "#f4f6f5"
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "No new notifications right now"
                    font.family: "Manrope"
                    font.pixelSize: 12
                    font.weight: Font.Medium
                    color: Qt.rgba(244/255, 246/255, 245/255, 0.40)
                }
            }

            // Scrollable Content
            Flickable {
                id: notifFlickable
                anchors.fill: parent
                contentHeight: listCol.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                visible: root.totalCount > 0
                clip: true

                ColumnLayout {
                    id: listCol
                    width: parent.width
                    spacing: 12

                    // ── Group "New" (Unread) ──
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        visible: root.newGroupItems.length > 0

                        RowLayout {
                            Layout.fillWidth: true

                            Text {
                                text: "New"
                                font.family: "Manrope"
                                font.pixelSize: 12
                                font.weight: Font.Bold
                                color: Qt.rgba(244/255, 246/255, 245/255, 0.66)
                            }

                            Item { Layout.fillWidth: true }

                            Text {
                                text: "Mark all read"
                                font.family: "Manrope"
                                font.pixelSize: 11
                                font.weight: Font.Bold
                                color: "#f2705f" // Coral

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        NotificationService.markAllRead()
                                    }
                                }
                            }
                        }

                        Repeater {
                            model: root.newGroupItems

                            delegate: NotificationCard {
                                notifItem: modelData
                                cardIndex: index
                                onDismissRequested: (item) => {
                                    NotificationService.dismiss(item.id)
                                }
                                onActionInvoked: (item, actionObj) => {
                                    NotificationService.invokeAction(item, actionObj)
                                }
                            }
                        }
                    }

                    // ── Group "Earlier" (Read) ──
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        visible: root.earlierGroupItems.length > 0

                        RowLayout {
                            Layout.fillWidth: true

                            Text {
                                text: "Earlier"
                                font.family: "Manrope"
                                font.pixelSize: 12
                                font.weight: Font.Bold
                                color: Qt.rgba(244/255, 246/255, 245/255, 0.40)
                            }

                            Item { Layout.fillWidth: true }
                        }

                        Repeater {
                            model: root.earlierGroupItems

                            delegate: NotificationCard {
                                notifItem: modelData
                                cardIndex: index
                                onDismissRequested: (item) => {
                                    NotificationService.dismiss(item.id)
                                }
                                onActionInvoked: (item, actionObj) => {
                                    NotificationService.invokeAction(item, actionObj)
                                }
                            }
                        }
                    }
                }
            }

            // Top fade gradient
            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 14
                gradient: Gradient {
                    GradientStop { position: 0.0; color: Qt.rgba(15/255, 20/255, 22/255, 0.90) }
                    GradientStop { position: 1.0; color: "transparent" }
                }
                visible: notifFlickable.visible && notifFlickable.contentY > 2
            }

            // Bottom fade gradient
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: 14
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 1.0; color: Qt.rgba(15/255, 20/255, 22/255, 0.90) }
                }
                visible: notifFlickable.visible
            }
        }

        // ── 4. Footer Hint ──────────────────────────────────────────────────
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: "Click to expand, swipe sideways to dismiss"
            font.family: "Manrope"
            font.pixelSize: 11
            font.weight: Font.Medium
            color: Qt.rgba(244/255, 246/255, 245/255, 0.35)
        }
    }
}
