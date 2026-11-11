import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../Singletons"
import "../components"

Item {
    id: root

    property var hub: null
    function describe(name, desc) { if (hub && hub.describe) hub.describe(name, desc) }
    function clearDesc() { if (hub && hub.clearDescription) hub.clearDescription() }

    readonly property string scriptPath: (Quickshell.env("CARBON_CONFIG_DIR") || ((Quickshell.env("HOME") || "") + "/.config/carbon")) + "/scripts/carbon-settings-apply.py"

    property bool notifEnabled: true
    property bool dndEnabled: false
    property int bannerTimeout: 5
    property bool compactIsland: true

    function loadConfig() {
        if (!configProc.running) configProc.running = true
    }

    function setCfg(key, val) {
        Quickshell.execDetached([root.scriptPath, "set", "notifications", key, String(val)])
    }

    Process {
        id: configProc
        command: [root.scriptPath, "get", "notifications"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) {
                var raw = line.trim()
                if (!raw) return
                try {
                    var d = JSON.parse(raw)
                    if (d.enabled !== undefined) root.notifEnabled = Boolean(d.enabled)
                    if (d.dnd !== undefined) root.dndEnabled = Boolean(d.dnd)
                    if (d.timeout !== undefined) root.bannerTimeout = parseInt(d.timeout) || 5
                    if (d.compactIsland !== undefined) root.compactIsland = Boolean(d.compactIsland)
                } catch(e) {}
            }
        }
    }

    Component.onCompleted: root.loadConfig()

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentCol.implicitHeight + Theme.px(64)
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        ColumnLayout {
            id: contentCol
            width: parent.width - Theme.px(64)
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: Theme.px(28)
            spacing: Theme.px(24)

            // Section 1: Notifications Status
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.px(10)

                Text {
                    text: "NOTIFICATION SYSTEM STATUS"
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fontPx(11)
                    font.weight: Font.Bold
                    color: Qt.rgba(1, 1, 1, 0.40)
                }

                // Global Enable
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.px(64)
                    radius: Theme.px(8)
                    color: Qt.rgba(0, 0, 0, 0.20)
                    border.color: root.notifEnabled ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.35) : Qt.rgba(1, 1, 1, 0.08)
                    border.width: 1

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                        onEntered: root.describe("Desktop Notifications", "Render banner popups and route messages through the Notification Center.")
                        onExited: root.clearDesc()
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.px(16)
                        anchors.rightMargin: Theme.px(16)

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.px(2)
                            Text { text: "Enable Desktop Notifications"; font.family: Theme.font; font.pixelSize: Theme.fontPx(13); font.weight: Font.DemiBold; color: Theme.fg }
                            Text { text: "Render banner popups and route messages through the Notification Center"; font.family: Theme.font; font.pixelSize: Theme.fontPx(11); color: Qt.rgba(1, 1, 1, 0.50) }
                        }

                        TerminalStatusBadge {
                            settingName: "Desktop Notifications"
                            description: "Render banner popups and route messages through the Notification Center."
                            checked: root.notifEnabled
                            onClicked: {
                                root.notifEnabled = !root.notifEnabled
                                root.setCfg("enabled", root.notifEnabled)
                            }
                        }
                    }
                }

                // Do Not Disturb (DND)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.px(64)
                    radius: Theme.px(8)
                    color: Qt.rgba(0, 0, 0, 0.20)
                    border.color: root.dndEnabled ? Qt.rgba(1, 0.4, 0.4, 0.45) : Qt.rgba(1, 1, 1, 0.08)
                    border.width: 1

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                        onEntered: root.describe("Do Not Disturb (DND)", "Silence all popups and banners while keeping notifications stored in tray.")
                        onExited: root.clearDesc()
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.px(16)
                        anchors.rightMargin: Theme.px(16)

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.px(2)
                            RowLayout {
                                spacing: Theme.px(8)
                                Text { text: "󰂛"; font.family: Theme.fontMono; font.pixelSize: Theme.fontPx(15); color: root.dndEnabled ? "#F87171" : Qt.rgba(1, 1, 1, 0.60) }
                                Text { text: "Do Not Disturb (DND)"; font.family: Theme.font; font.pixelSize: Theme.fontPx(13); font.weight: Font.DemiBold; color: root.dndEnabled ? "#F87171" : Theme.fg }
                            }
                            Text { text: "Silence all popups and banners while keeping notifications stored in tray"; font.family: Theme.font; font.pixelSize: Theme.fontPx(11); color: Qt.rgba(1, 1, 1, 0.50) }
                        }

                        TerminalStatusBadge {
                            settingName: "Do Not Disturb (DND)"
                            description: "Silence all popups and banners while keeping notifications stored in tray."
                            checked: root.dndEnabled
                            onClicked: {
                                root.dndEnabled = !root.dndEnabled
                                root.setCfg("dnd", root.dndEnabled)
                            }
                        }
                    }
                }
            }

            // Section 2: Banner Behavior
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.px(10)

                Text {
                    text: "BANNER TIMEOUT & VISUALS"
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fontPx(11)
                    font.weight: Font.Bold
                    color: Qt.rgba(1, 1, 1, 0.40)
                }

                // Banner Timeout Slider
                RazorWireSlider {
                    Layout.fillWidth: true
                    label: "Banner Dismissal Timeout"
                    description: "Seconds before notification toast automatically tucks away."
                    from: 2
                    to: 10
                    stepSize: 1
                    unit: " s"
                    value: root.bannerTimeout
                    onMoved: (val) => {
                        root.bannerTimeout = Math.round(val)
                        root.setCfg("timeout", root.bannerTimeout)
                    }
                }

                // Dynamic Island Banner Integration
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.px(54)
                    radius: Theme.px(8)
                    color: Qt.rgba(0, 0, 0, 0.20)
                    border.color: Qt.rgba(1, 1, 1, 0.08)
                    border.width: 1

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                        onEntered: root.describe("Island Morph Banners", "Expand the screen notch or floating island into an animated toast when alert arrives.")
                        onExited: root.clearDesc()
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.px(16)
                        anchors.rightMargin: Theme.px(16)

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.px(2)
                            Text { text: "Island Morph Banners"; font.family: Theme.font; font.pixelSize: Theme.fontPx(13); color: Theme.fg }
                            Text { text: "Expand the screen notch or floating island into an animated toast when alert arrives"; font.family: Theme.font; font.pixelSize: Theme.fontPx(11); color: Qt.rgba(1, 1, 1, 0.50) }
                        }

                        TerminalStatusBadge {
                            settingName: "Island Morph Banners"
                            description: "Expand the screen notch or floating island into an animated toast when alert arrives."
                            checked: root.compactIsland
                            onClicked: {
                                root.compactIsland = !root.compactIsland
                                root.setCfg("compactIsland", root.compactIsland)
                            }
                        }
                    }
                }
            }
        }
    }
}
