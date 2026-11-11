import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import "../Singletons"
import "../components"

Item {
    id: root

    property bool open: false
    signal closeRequested()

    property string currentSection: "Modes"
    property string activeSettingName: ""
    property string activeDescription: ""

    function describe(name, desc) {
        root.activeSettingName = name || ""
        root.activeDescription = desc || ""
    }

    function clearDescription() {
        root.activeSettingName = ""
        root.activeDescription = ""
    }

    // Backdrop dismissal
    MouseArea {
        anchors.fill: parent
        onClicked: root.closeRequested()
    }

    // Main Hub Window (Full-screen flush edge-to-edge layout separated by strict 1px hairlines)
    Rectangle {
        id: hubWindow
        anchors.fill: parent
        color: Theme.surface
        border.width: 0
        radius: 0
        clip: true
        focus: true

        Keys.onEscapePressed: root.closeRequested()

        // Stop propagation so clicking inside window doesn't close
        MouseArea {
            anchors.fill: parent
            onClicked: {}
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // Header Bar
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.px(52)
                color: Qt.rgba(0, 0, 0, 0.20)
                border.color: Qt.rgba(1, 1, 1, 0.08)
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.px(20)
                    anchors.rightMargin: Theme.px(16)
                    spacing: Theme.px(12)

                    Text {
                        text: "CARBON // SETTINGS HUB"
                        font.family: Theme.font
                        font.pixelSize: Theme.fontPx(13)
                        font.weight: Font.Bold
                        color: Theme.primary
                    }

                    Item { Layout.fillWidth: true }

                    // Close Button
                    Rectangle {
                        Layout.preferredWidth: Theme.px(28)
                        Layout.preferredHeight: Theme.px(28)
                        radius: Theme.px(6)
                        color: closeMouse.pressed ? Qt.rgba(1, 1, 1, 0.15) : (closeMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent")
                        border.color: closeMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.20) : "transparent"
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: "✕"
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.fontPx(13)
                            color: Qt.rgba(1, 1, 1, 0.70)
                        }

                        MouseArea {
                            id: closeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.closeRequested()
                        }
                    }
                }
            }

            // Body: Sidebar + Vertical Hairline + Main Tab Content
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                // ==========================================
                // SIDEBAR with subtle tactile hardware pattern
                // ==========================================
                Item {
                    Layout.preferredWidth: Theme.px(210)
                    Layout.fillHeight: true

                    // Plain solid background
                    Rectangle {
                        anchors.fill: parent
                        color: "transparent"
                    }

                    // Sidebar Navigation Items
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.topMargin: Theme.px(16)
                        anchors.leftMargin: Theme.px(12)
                        anchors.rightMargin: Theme.px(12)
                        spacing: Theme.px(4)

                        Repeater {
                            model: [
                                { name: "Appearance", glyph: "󰏘", badge: "M3" },
                                { name: "Modes", glyph: "󱐋", badge: "STUDIO" },
                                { name: "Personalization", glyph: "󰥔", badge: "" },
                                { name: "Launcher", glyph: "󰌌", badge: "" },
                                { name: "Default Apps", glyph: "󰀻", badge: "" },
                                { name: "Notifications", glyph: "󰂚", badge: "" },
                                { name: "Lock Screen", glyph: "󰌾", badge: "" },
                                { name: "Display", glyph: "󰍹", badge: "" },
                                { name: "Audio", glyph: "󰓃", badge: "" },
                                { name: "Network", glyph: "󰤨", badge: "" },
                                { name: "Input", glyph: "󰍽", badge: "" },
                                { name: "Power", glyph: "󰁹", badge: "" },
                                { name: "System", glyph: "󰘚", badge: "" }
                            ]

                            delegate: Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Theme.px(38)
                                radius: Theme.px(6)
                                color: (root.currentSection.toLowerCase() === modelData.name.toLowerCase()) ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12) : (navMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : "transparent")
                                border.color: (root.currentSection.toLowerCase() === modelData.name.toLowerCase()) ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.40) : "transparent"
                                border.width: 1

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.px(12)
                                    anchors.rightMargin: Theme.px(12)
                                    spacing: Theme.px(10)

                                    Text {
                                        text: modelData.glyph
                                        font.family: Theme.fontMono
                                        font.pixelSize: Theme.fontPx(15)
                                        color: (root.currentSection.toLowerCase() === modelData.name.toLowerCase()) ? Theme.primary : Qt.rgba(1, 1, 1, 0.60)
                                    }

                                    Text {
                                        text: modelData.name
                                        font.family: Theme.font
                                        font.pixelSize: Theme.fontPx(13)
                                        font.weight: (root.currentSection.toLowerCase() === modelData.name.toLowerCase()) ? Font.DemiBold : Font.Normal
                                        color: (root.currentSection.toLowerCase() === modelData.name.toLowerCase()) ? Qt.rgba(1, 1, 1, 0.95) : Qt.rgba(1, 1, 1, 0.65)
                                        Layout.fillWidth: true
                                    }

                                    Text {
                                        visible: modelData.badge.length > 0
                                        text: modelData.badge
                                        font.family: Theme.fontMono
                                        font.pixelSize: Theme.fontPx(9)
                                        font.weight: Font.Bold
                                        color: Theme.primary
                                    }
                                }

                                MouseArea {
                                    id: navMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.currentSection = modelData.name
                                }
                            }
                        }

                        Item { Layout.fillHeight: true }

                        // Version info at bottom of sidebar
                        Text {
                            text: "CARBON // v2.6.4"
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.fontPx(10)
                            color: Qt.rgba(1, 1, 1, 0.25)
                            Layout.alignment: Qt.AlignHCenter
                            Layout.bottomMargin: 12
                        }
                    }
                }

                // 1px Vertical Hairline Separating Sidebar & Content
                Rectangle {
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1
                    color: Qt.rgba(1, 1, 1, 0.08)
                }

                // Main Content View
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    AppearanceTab {
                        hub: root
                        anchors.fill: parent
                        visible: root.currentSection.toLowerCase() === "appearance"
                    }

                    ModesTab {
                        hub: root
                        anchors.fill: parent
                        visible: root.currentSection.toLowerCase() === "modes"
                    }

                    PersonalizationTab {
                        hub: root
                        anchors.fill: parent
                        visible: root.currentSection.toLowerCase() === "personalization" || root.currentSection.toLowerCase() === "clock" || root.currentSection.toLowerCase() === "tile"
                    }

                    LauncherTab {
                        hub: root
                        anchors.fill: parent
                        visible: root.currentSection.toLowerCase() === "launcher" || root.currentSection.toLowerCase() === "spotlight"
                    }

                    DefaultAppsTab {
                        hub: root
                        anchors.fill: parent
                        visible: root.currentSection.toLowerCase() === "default apps" || root.currentSection.toLowerCase() === "defaultapps" || root.currentSection.toLowerCase() === "default_apps"
                    }

                    NotificationsTab {
                        hub: root
                        anchors.fill: parent
                        visible: root.currentSection.toLowerCase() === "notifications" || root.currentSection.toLowerCase() === "dnd"
                    }

                    LockScreenTab {
                        hub: root
                        anchors.fill: parent
                        visible: root.currentSection.toLowerCase() === "lock screen" || root.currentSection.toLowerCase() === "lockscreen" || root.currentSection.toLowerCase() === "lock"
                    }

                    DisplaysTab {
                        hub: root
                        anchors.fill: parent
                        visible: root.currentSection.toLowerCase() === "display" || root.currentSection.toLowerCase() === "displays"
                    }

                    AudioTab {
                        hub: root
                        anchors.fill: parent
                        visible: root.currentSection.toLowerCase() === "audio" || root.currentSection.toLowerCase() === "media"
                    }

                    NetworkTab {
                        hub: root
                        anchors.fill: parent
                        visible: root.currentSection.toLowerCase() === "network" || root.currentSection.toLowerCase() === "wifi"
                    }

                    InputTab {
                        hub: root
                        anchors.fill: parent
                        visible: root.currentSection.toLowerCase() === "input" || root.currentSection.toLowerCase() === "mouse" || root.currentSection.toLowerCase() === "keyboard"
                    }

                    PowerTab {
                        hub: root
                        anchors.fill: parent
                        visible: root.currentSection.toLowerCase() === "power" || root.currentSection.toLowerCase() === "battery"
                    }

                    SystemTab {
                        hub: root
                        anchors.fill: parent
                        visible: root.currentSection.toLowerCase() === "system" || root.currentSection.toLowerCase() === "startup"
                    }
                }
            }

            // ==========================================
            // STATUS & DESCRIPTION FOOTER BAR
            // ==========================================
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.px(34)
                color: Qt.rgba(0, 0, 0, 0.35)
                border.color: Qt.rgba(1, 1, 1, 0.08)
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.px(16)
                    anchors.rightMargin: Theme.px(16)
                    spacing: Theme.px(10)

                    Text {
                        text: root.activeSettingName.length > 0 ? "󰋼 " + root.activeSettingName.toUpperCase() : "󰘳 READY"
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fontPx(11)
                        font.weight: Font.Bold
                        color: root.activeSettingName.length > 0 ? Theme.primary : Qt.rgba(1, 1, 1, 0.40)
                    }

                    Rectangle {
                        visible: root.activeSettingName.length > 0
                        width: 1
                        height: Theme.px(14)
                        color: Qt.rgba(1, 1, 1, 0.15)
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.activeDescription.length > 0 ? root.activeDescription : "Hover over any setting or control to inspect its purpose and system impact."
                        font.family: Theme.font
                        font.pixelSize: Theme.fontPx(11)
                        color: root.activeDescription.length > 0 ? Qt.rgba(1, 1, 1, 0.85) : Qt.rgba(1, 1, 1, 0.35)
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
}
