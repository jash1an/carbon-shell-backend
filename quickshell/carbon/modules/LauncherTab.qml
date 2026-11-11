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

    property string launcherStyle: "spotlight"
    property int animationSpeed: 160
    property bool showRecents: true
    property bool clipboardHistory: true
    property int maxResults: 8

    function loadConfig() {
        if (!configProc.running) configProc.running = true
    }

    function setCfg(key, val) {
        Quickshell.execDetached([root.scriptPath, "set", "launcher", key, String(val)])
    }

    Process {
        id: configProc
        command: [root.scriptPath, "get", "launcher"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) {
                var raw = line.trim()
                if (!raw) return
                try {
                    var d = JSON.parse(raw)
                    if (d.launcherStyle !== undefined) root.launcherStyle = d.launcherStyle
                    if (d.animationSpeed !== undefined) root.animationSpeed = parseInt(d.animationSpeed) || 160
                    if (d.showRecents !== undefined) root.showRecents = Boolean(d.showRecents)
                    if (d.clipboardHistory !== undefined) root.clipboardHistory = Boolean(d.clipboardHistory)
                    if (d.maxResults !== undefined) root.maxResults = parseInt(d.maxResults) || 8
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

            // Section 1: Launcher Experience Mode
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.px(10)

                Text {
                    text: "LAUNCHER EXPERIENCE & INTERFACE"
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fontPx(11)
                    font.weight: Font.Bold
                    color: Qt.rgba(1, 1, 1, 0.40)
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(12)

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Theme.px(90)
                        radius: Theme.px(8)
                        color: root.launcherStyle === "spotlight" ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12) : (spotlightMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(0, 0, 0, 0.20))
                        border.color: root.launcherStyle === "spotlight" ? Theme.primary : (spotlightMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(1, 1, 1, 0.08))
                        border.width: 1

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: Theme.px(14)
                            spacing: Theme.px(4)

                            RowLayout {
                                spacing: Theme.px(8)
                                Text { text: "󰌌"; font.family: Theme.fontMono; font.pixelSize: Theme.fontPx(16); color: root.launcherStyle === "spotlight" ? Theme.primary : Qt.rgba(1, 1, 1, 0.60) }
                                Text { text: "Spotlight Palette"; font.family: Theme.font; font.pixelSize: Theme.fontPx(13); font.weight: Font.DemiBold; color: root.launcherStyle === "spotlight" ? Theme.primary : Theme.fg }
                            }
                            Text {
                                text: "Centered command palette with live calculations, file actions & web search"
                                font.family: Theme.font
                                font.pixelSize: Theme.fontPx(11)
                                color: Qt.rgba(1, 1, 1, 0.50)
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                            }
                        }

                        MouseArea {
                            id: spotlightMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            ToolTip.visible: containsMouse
                            ToolTip.text: "Enable centered Spotlight command palette"
                            ToolTip.delay: 300
                            onEntered: root.describe("Spotlight Palette", "Centered command palette with live calculations, file actions & web search.")
                            onExited: root.clearDesc()
                            onClicked: {
                                root.launcherStyle = "spotlight"
                                root.setCfg("launcherStyle", "spotlight")
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Theme.px(90)
                        radius: Theme.px(8)
                        color: root.launcherStyle === "launcher" ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12) : (drawerMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(0, 0, 0, 0.20))
                        border.color: root.launcherStyle === "launcher" ? Theme.primary : (drawerMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(1, 1, 1, 0.08))
                        border.width: 1

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: Theme.px(14)
                            spacing: Theme.px(4)

                            RowLayout {
                                spacing: Theme.px(8)
                                Text { text: "󰀻"; font.family: Theme.fontMono; font.pixelSize: Theme.fontPx(16); color: root.launcherStyle === "launcher" ? Theme.primary : Qt.rgba(1, 1, 1, 0.60) }
                                Text { text: "App Drawer"; font.family: Theme.font; font.pixelSize: Theme.fontPx(13); font.weight: Font.DemiBold; color: root.launcherStyle === "launcher" ? Theme.primary : Theme.fg }
                            }
                            Text {
                                text: "Full categorized application grid with quick launchers and pinning"
                                font.family: Theme.font
                                font.pixelSize: Theme.fontPx(11)
                                color: Qt.rgba(1, 1, 1, 0.50)
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                            }
                        }

                        MouseArea {
                            id: drawerMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            ToolTip.visible: containsMouse
                            ToolTip.text: "Enable full categorized application grid"
                            ToolTip.delay: 300
                            onEntered: root.describe("App Drawer", "Full categorized application grid with quick launchers and pinning.")
                            onExited: root.clearDesc()
                            onClicked: {
                                root.launcherStyle = "launcher"
                                root.setCfg("launcherStyle", "launcher")
                            }
                        }
                    }
                }
            }

            // Section 2: Motion & Result Limits
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.px(10)

                Text {
                    text: "ANIMATION & SEARCH LIMITS"
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fontPx(11)
                    font.weight: Font.Bold
                    color: Qt.rgba(1, 1, 1, 0.40)
                }

                // Animation Speed
                RazorWireSlider {
                    Layout.fillWidth: true
                    label: "Opening Animation Speed"
                    description: "Spring acceleration duration when summoning Spotlight or App Drawer in milliseconds."
                    from: 100
                    to: 400
                    stepSize: 10
                    unit: "ms"
                    value: root.animationSpeed
                    onMoved: (val) => {
                        root.animationSpeed = Math.round(val)
                        root.setCfg("animationSpeed", root.animationSpeed)
                    }
                }

                // Maximum Results
                RazorWireSlider {
                    Layout.fillWidth: true
                    label: "Maximum Search Results"
                    description: "Maximum application and command items rendered before requiring scrolling."
                    from: 4
                    to: 16
                    stepSize: 1
                    unit: " items"
                    value: root.maxResults
                    onMoved: (val) => {
                        root.maxResults = Math.round(val)
                        root.setCfg("maxResults", root.maxResults)
                    }
                }
            }

            // Section 3: Smart Features Matrix
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.px(10)

                Text {
                    text: "INTELLIGENT INTEGRATIONS"
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fontPx(11)
                    font.weight: Font.Bold
                    color: Qt.rgba(1, 1, 1, 0.40)
                }

                // Recent Apps
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
                        onEntered: root.describe("Recent Applications", "Show frequently launched apps when the search box is empty.")
                        onExited: root.clearDesc()
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.px(16)
                        anchors.rightMargin: Theme.px(16)

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.px(2)
                            Text { text: "Recent Applications"; font.family: Theme.font; font.pixelSize: Theme.fontPx(13); color: Theme.fg }
                            Text { text: "Show frequently launched apps when search box is empty"; font.family: Theme.font; font.pixelSize: Theme.fontPx(11); color: Qt.rgba(1, 1, 1, 0.50) }
                        }

                        TerminalStatusBadge {
                            settingName: "Recent Applications"
                            description: "Show frequently launched apps when search box is empty."
                            checked: root.showRecents
                            onClicked: {
                                root.showRecents = !root.showRecents
                                root.setCfg("showRecents", root.showRecents)
                            }
                        }
                    }
                }

                // Clipboard History
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
                        onEntered: root.describe("Clipboard History Tab", "Allow searching and pasting recent clipboard clips.")
                        onExited: root.clearDesc()
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.px(16)
                        anchors.rightMargin: Theme.px(16)

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.px(2)
                            Text { text: "Clipboard History Tab"; font.family: Theme.font; font.pixelSize: Theme.fontPx(13); color: Theme.fg }
                            Text { text: "Allow searching and pasting recent clipboard clips"; font.family: Theme.font; font.pixelSize: Theme.fontPx(11); color: Qt.rgba(1, 1, 1, 0.50) }
                        }

                        TerminalStatusBadge {
                            settingName: "Clipboard History Tab"
                            description: "Allow searching and pasting recent clipboard clips."
                            checked: root.clipboardHistory
                            onClicked: {
                                root.clipboardHistory = !root.clipboardHistory
                                root.setCfg("clipboardHistory", root.clipboardHistory)
                            }
                        }
                    }
                }
            }
        }
    }
}
