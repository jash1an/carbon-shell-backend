import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Services.Notifications
import "../Singletons"

/**
 * Animated Notification Panel Popup:
 *   - Clean glassmorphic card with smooth opacity, slide, and scale transitions
 *   - Displays active notifications tracked by NotificationServer
 *   - Includes header with unread badge, "Clear all" button, and close action
 *   - Individual card dismiss on click with slide-out animation
 *   - Polished empty state when all notifications are cleared
 */
Item {
    id: root

    required property var server
    property bool open: false
    property string barEdge: "top"
    property bool hovered: false

    readonly property var notifs: server && server.trackedNotifications ? server.trackedNotifications : null
    readonly property int total: listView ? listView.count : 0

    signal requestClose()

    implicitWidth: 320
    implicitHeight: 360

    HoverHandler {
        onHoveredChanged: root.hovered = hovered
    }

    function dismissAll() {
        if (!root.notifs) return
        const list = root.notifs.values ? [...root.notifs.values] : []
        for (let i = 0; i < list.length; i++) {
            if (list[i] && typeof list[i].dismiss === "function") {
                list[i].dismiss()
            }
        }
    }

    /* Auto-track any notification arriving at the server */
    Connections {
        target: root.server
        function onNotification(notification) {
            notification.tracked = true
        }
    }

    Rectangle {
        id: card
        width: parent.width
        height: parent.height
        radius: 16
        color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.90)
        border.color: root.open ? Qt.rgba(Theme.accentLit.r, Theme.accentLit.g, Theme.accentLit.b, 0.45) : Qt.rgba(1, 1, 1, 0.12)
        border.width: 1

        /* VisionOS Specular Rim highlight */
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: card.radius - 1
            color: "transparent"
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, root.open ? 0.20 : 0.06)
            z: 99
        }

        opacity: root.open ? 1 : 0
        x: root.open ? 0 : (root.barEdge === "left" ? -28 : (root.barEdge === "right" ? 28 : 0))
        y: root.open ? 0 : (root.barEdge === "top" ? -20 : (root.barEdge === "bottom" ? 20 : 0))
        scale: root.open ? 1.0 : 0.88
        transformOrigin: root.barEdge === "left" ? Item.BottomLeft :
                         (root.barEdge === "right" ? Item.BottomRight :
                         (root.barEdge === "bottom" ? Item.BottomRight : Item.TopRight))

        Behavior on border.color { ColorAnimation { duration: 200 } }
        Behavior on opacity {
            NumberAnimation { duration: root.open ? 220 : 140; easing.type: Easing.OutCubic }
        }
        Behavior on x {
            NumberAnimation {
                duration: root.open ? 320 : 160
                easing.type: root.open ? Easing.OutBack : Easing.OutCubic
                easing.overshoot: 1.35
            }
        }
        Behavior on y {
            NumberAnimation {
                duration: root.open ? 320 : 160
                easing.type: root.open ? Easing.OutBack : Easing.OutCubic
                easing.overshoot: 1.35
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: root.open ? 300 : 150
                easing.type: root.open ? Easing.OutBack : Easing.OutCubic
                easing.overshoot: 1.38
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8
            opacity: root.open ? 1.0 : 0.0
            y: root.open ? 0 : 8
            Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            Behavior on y { NumberAnimation { duration: 300; easing.type: Easing.OutBack; easing.overshoot: 1.2 } }

            /* ── Header ─────────────────────────────────────────────── */
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 24
                spacing: 6

                Text {
                    text: "notifications"
                    font.family: Theme.fontIcon
                    font.pixelSize: 15
                    color: Theme.accent
                }

                Text {
                    text: "Notifications"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: Theme.fontPx(13)
                    font.weight: Font.Bold
                    color: Theme.fg
                }

                /* Unread counter badge */
                Rectangle {
                    visible: root.total > 0
                    Layout.preferredHeight: 18
                    Layout.preferredWidth: countText.implicitWidth + 10
                    radius: 9
                    color: Theme.accent

                    Text {
                        id: countText
                        anchors.centerIn: parent
                        text: String(root.total)
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: Theme.fontPx(10)
                        font.weight: Font.Bold
                        color: "#0e0e12"
                    }
                }

                Item { Layout.fillWidth: true }

                /* Clear all button */
                Rectangle {
                    visible: root.total > 0
                    Layout.preferredHeight: 22
                    Layout.preferredWidth: clearRow.implicitWidth + 12
                    radius: 11
                    color: clearHov.containsMouse ? Theme.bgHover : "transparent"
                    border.color: clearHov.containsMouse ? Theme.accent : Theme.outline
                    border.width: 1

                    Behavior on color { ColorAnimation { duration: Theme.motionDurationShort3 } }

                    Row {
                        id: clearRow
                        anchors.centerIn: parent
                        spacing: 4

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "delete_sweep"
                            font.family: Theme.fontIcon
                            font.pixelSize: 13
                            color: clearHov.containsMouse ? Theme.accent : Theme.fgDim
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Clear all"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: Theme.fontPx(10)
                            font.weight: Font.Medium
                            color: clearHov.containsMouse ? Theme.accent : Theme.fgDim
                        }
                    }

                    MouseArea {
                        id: clearHov
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.dismissAll()
                    }
                }

                /* Close Button */
                Rectangle {
                    Layout.preferredWidth: 22
                    Layout.preferredHeight: 22
                    radius: 11
                    color: closeHov.containsMouse ? Theme.bgHover : "transparent"

                    Behavior on color { ColorAnimation { duration: Theme.motionDurationShort3 } }

                    Text {
                        anchors.centerIn: parent
                        text: "close"
                        font.family: Theme.fontIcon
                        font.pixelSize: 13
                        color: closeHov.containsMouse ? Theme.fg : Theme.fgFaint
                    }

                    MouseArea {
                        id: closeHov
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.requestClose()
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Theme.outline
            }

            /* ── Content Area ───────────────────────────────────────── */
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                /* Empty state */
                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 6
                    visible: root.total === 0

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "notifications"
                        font.family: Theme.fontIcon
                        font.pixelSize: 36
                        color: Qt.alpha(Theme.fg, 0.15)
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "No Notifications"
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: Theme.fontPx(13)
                        font.weight: Font.DemiBold
                        color: Theme.fgDim
                    }

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "You are all caught up!"
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: Theme.fontPx(10)
                        color: Theme.fgFaint
                    }
                }

                /* Notification Cards List */
                ListView {
                    id: listView
                    anchors.fill: parent
                    clip: true
                    spacing: 6
                    model: root.notifs
                    boundsBehavior: Flickable.StopAtBounds
                    visible: root.total > 0

                    delegate: Rectangle {
                        id: cardItem
                        required property int index
                        required property var modelData

                        width: listView.width
                        height: contentCol.implicitHeight + 16
                        radius: 10
                        color: itemMouse.containsMouse
                            ? Qt.rgba(Theme.bgHover.r, Theme.bgHover.g, Theme.bgHover.b, 0.88)
                            : Qt.rgba(Theme.bgAlt.r, Theme.bgAlt.g, Theme.bgAlt.b, 0.72)
                        border.color: itemMouse.containsMouse ? Theme.accent : Qt.rgba(1, 1, 1, 0.12)
                        border.width: 1

                        /* Specular rim inside card */
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 1
                            radius: cardItem.radius - 1
                            color: "transparent"
                            border.width: 1
                            border.color: Qt.rgba(1, 1, 1, itemMouse.containsMouse ? 0.22 : 0.06)
                            z: 10
                        }

                        Behavior on color { ColorAnimation { duration: 120 } }
                        Behavior on border.color { ColorAnimation { duration: 120 } }

                        property bool dying: false
                        x: dying ? width + 50 : 0
                        opacity: dying ? 0 : 1
                        scale: dying ? 0.85 : (itemMouse.pressed ? 0.96 : (itemMouse.containsMouse ? 1.02 : Math.max(0.96, 1.0 - cardItem.index * 0.015)))

                        Behavior on x {
                            NumberAnimation {
                                duration: 200
                                easing.type: Easing.InBack
                                easing.overshoot: 1.15
                            }
                        }
                        Behavior on opacity { NumberAnimation { duration: 180 } }
                        Behavior on scale {
                            NumberAnimation {
                                duration: 180
                                easing.type: Easing.OutBack
                                easing.overshoot: 1.25
                            }
                        }

                        Timer {
                            id: exitTimer
                            interval: 200
                            onTriggered: {
                                if (cardItem.modelData) cardItem.modelData.dismiss()
                            }
                        }

                        function dismissCard() {
                            if (cardItem.dying) return
                            cardItem.dying = true
                            exitTimer.start()
                        }

                        MouseArea {
                            id: itemMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: cardItem.dismissCard()
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 8

                            /* App / Sender Icon */
                            Rectangle {
                                Layout.preferredWidth: 26
                                Layout.preferredHeight: 26
                                Layout.alignment: Qt.AlignTop
                                radius: 6
                                color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.15)
                                border.color: Theme.outline
                                border.width: 1
                                clip: true

                                Image {
                                    anchors.fill: parent
                                    anchors.margins: 3
                                    source: {
                                        const icon = String(cardItem.modelData ? (cardItem.modelData.appIcon || "") : "")
                                        return (icon.startsWith("/") || icon.startsWith("file:")) ? icon : ""
                                    }
                                    fillMode: Image.PreserveAspectFit
                                    visible: status === Image.Ready
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: "notifications"
                                    font.family: Theme.fontIcon
                                    font.pixelSize: 14
                                    color: Theme.accent
                                    visible: parent.children[0].status !== Image.Ready
                                }
                            }

                            /* Text Details */
                            ColumnLayout {
                                id: contentCol
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 2

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 4

                                    Text {
                                        Layout.fillWidth: true
                                        text: {
                                            if (!cardItem.modelData) return ""
                                            return cardItem.modelData.summary.length > 0
                                                ? cardItem.modelData.summary
                                                : cardItem.modelData.appName
                                        }
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: Theme.fontPx(11)
                                        font.weight: Font.Bold
                                        color: Theme.fg
                                        elide: Text.ElideRight
                                    }

                                    /* Dismiss cross on hover */
                                    Text {
                                        text: "close"
                                        font.family: Theme.fontIcon
                                        font.pixelSize: 11
                                        color: itemMouse.containsMouse ? Theme.err : "transparent"
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: cardItem.modelData ? String(cardItem.modelData.body || "") : ""
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: Theme.fontPx(10)
                                    color: Theme.fgDim
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                    visible: text.length > 0
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
