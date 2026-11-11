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

    property string layoutStyle: "modern"
    property int blurRadius: 4
    property bool mediaOverlay: true
    property bool cairoModeEnabled: false
    property bool cairoRomanizeLyrics: true
    property bool clockEnabled: true
    property bool heartbeat: true

    function loadConfig() {
        if (!configProc.running) configProc.running = true
    }

    function setCfg(key, val) {
        Quickshell.execDetached([root.scriptPath, "set", "lockscreen", key, String(val)])
    }

    Process {
        id: configProc
        command: [root.scriptPath, "get", "lockscreen"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) {
                var raw = line.trim()
                if (!raw) return
                try {
                    var d = JSON.parse(raw)
                    if (d.layout !== undefined) root.layoutStyle = d.layout
                    if (d.blurRadius !== undefined) root.blurRadius = parseInt(d.blurRadius) || 4
                    if (d.mediaOverlay !== undefined) root.mediaOverlay = Boolean(d.mediaOverlay)
                    if (d.showMedia !== undefined) root.mediaOverlay = Boolean(d.showMedia)
                    if (d.cairoModeEnabled !== undefined) root.cairoModeEnabled = Boolean(d.cairoModeEnabled)
                    if (d.cairoRomanizeLyrics !== undefined) root.cairoRomanizeLyrics = Boolean(d.cairoRomanizeLyrics)
                    if (d.clock !== undefined) root.clockEnabled = Boolean(d.clock)
                    if (d.heartbeat !== undefined) root.heartbeat = Boolean(d.heartbeat)
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

            // Section 1: Lock Screen Layout Style
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.px(10)

                Text {
                    text: "LOCK SCREEN ARCHITECTURE & LAYOUT"
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fontPx(11)
                    font.weight: Font.Bold
                    color: Qt.rgba(1, 1, 1, 0.40)
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(12)

                    Repeater {
                        model: [
                            { id: "modern", name: "Modern Minimal", desc: "Clean typography with subtle date line and essential status indicators." },
                            { id: "glass", name: "Glass Card", desc: "Frosted translucent acrylic credential tile with blurred backdrop." },
                            { id: "bold", name: "Bold Clock", desc: "Hero-sized stacked chronometer display with high-contrast numerals." }
                        ]

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Theme.px(80)
                            radius: Theme.px(8)
                            color: root.layoutStyle === modelData.id ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12) : (cardMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(0, 0, 0, 0.20))
                            border.color: root.layoutStyle === modelData.id ? Theme.primary : (cardMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(1, 1, 1, 0.08))
                            border.width: 1

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: Theme.px(12)
                                spacing: Theme.px(4)

                                Text {
                                    text: modelData.name
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontPx(13)
                                    font.weight: Font.DemiBold
                                    color: root.layoutStyle === modelData.id ? Theme.primary : Theme.fg
                                }

                                Text {
                                    text: modelData.desc
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontPx(11)
                                    color: Qt.rgba(1, 1, 1, 0.50)
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                }
                            }

                            MouseArea {
                                id: cardMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                ToolTip.visible: containsMouse
                                ToolTip.text: modelData.desc
                                ToolTip.delay: 300
                                onEntered: root.describe(modelData.name + " Layout", modelData.desc)
                                onExited: root.clearDesc()
                                onClicked: {
                                    root.layoutStyle = modelData.id
                                    root.setCfg("layout", modelData.id)
                                }
                            }
                        }
                    }
                }
            }

            // Section 2: Backdrop Blur
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.px(10)

                Text {
                    text: "BACKDROP BLUR"
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fontPx(11)
                    font.weight: Font.Bold
                    color: Qt.rgba(1, 1, 1, 0.40)
                }

                RazorWireSlider {
                    Layout.fillWidth: true
                    label: "Lock Screen Backdrop Blur"
                    description: "Amount of gaussian wallpaper blur passes applied when the system is locked."
                    from: 0
                    to: 10
                    stepSize: 1
                    unit: " passes"
                    value: root.blurRadius
                    onMoved: (val) => {
                        root.blurRadius = Math.round(val)
                        root.setCfg("blurRadius", root.blurRadius)
                    }
                }
            }

            // Section 3: Cairo Kinetic Lyrics Engine
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.px(10)

                Text {
                    text: "CAIRO KINETIC SYNCED LYRICS ENGINE"
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fontPx(11)
                    font.weight: Font.Bold
                    color: Qt.rgba(1, 1, 1, 0.40)
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.px(64)
                    radius: Theme.px(8)
                    color: Qt.rgba(0, 0, 0, 0.20)
                    border.color: root.cairoModeEnabled ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.35) : Qt.rgba(1, 1, 1, 0.08)
                    border.width: 1

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                        onEntered: root.describe("Cairo Kinetic Lyrics Mode", "Replace standard lock screen with Apple Music-style kinetic synced lyrics on deep black.")
                        onExited: root.clearDesc()
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.px(16)
                        anchors.rightMargin: Theme.px(16)

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.px(2)
                            Text { text: "Enable Cairo Kinetic Lyrics Mode"; font.family: Theme.font; font.pixelSize: Theme.fontPx(13); font.weight: Font.DemiBold; color: Theme.fg }
                            Text { text: "Replace standard lock screen with Apple Music-style kinetic synced lyrics on deep black"; font.family: Theme.font; font.pixelSize: Theme.fontPx(11); color: Qt.rgba(1, 1, 1, 0.50) }
                        }

                        TerminalStatusBadge {
                            settingName: "Cairo Kinetic Lyrics Mode"
                            description: "Replace standard lock screen with Apple Music-style kinetic synced lyrics on deep black."
                            checked: root.cairoModeEnabled
                            onClicked: {
                                root.cairoModeEnabled = !root.cairoModeEnabled
                                root.setCfg("cairoModeEnabled", root.cairoModeEnabled)
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.px(64)
                    radius: Theme.px(8)
                    color: Qt.rgba(0, 0, 0, 0.20)
                    border.color: Qt.rgba(1, 1, 1, 0.08)
                    border.width: 1

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                        onEntered: root.describe("Romanized Synced Lyrics", "Transliterate non-English lyrics (Japanese, Korean, Russian, etc.) into readable Latin script.")
                        onExited: root.clearDesc()
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.px(16)
                        anchors.rightMargin: Theme.px(16)

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.px(2)
                            Text { text: "English Converted Lyrics (Romanization)"; font.family: Theme.font; font.pixelSize: Theme.fontPx(13); color: Theme.fg }
                            Text { text: "Transliterate non-English lyrics (Japanese, Korean, Russian, etc.) into readable Latin script"; font.family: Theme.font; font.pixelSize: Theme.fontPx(11); color: Qt.rgba(1, 1, 1, 0.50) }
                        }

                        TerminalStatusBadge {
                            settingName: "Romanized Synced Lyrics"
                            description: "Transliterate non-English lyrics (Japanese, Korean, Russian, etc.) into readable Latin script."
                            checked: root.cairoRomanizeLyrics
                            onClicked: {
                                root.cairoRomanizeLyrics = !root.cairoRomanizeLyrics
                                root.setCfg("cairoRomanizeLyrics", root.cairoRomanizeLyrics)
                            }
                        }
                    }
                }
            }

            // Section 4: Lock Screen Ornaments
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.px(10)

                Text {
                    text: "LOCK SCREEN WIDGETS & ORNAMENTS"
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fontPx(11)
                    font.weight: Font.Bold
                    color: Qt.rgba(1, 1, 1, 0.40)
                }

                // Media Player Overlay
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
                        onEntered: root.describe("Lock Screen Media Player", "Show album art and playback controls on the lock screen.")
                        onExited: root.clearDesc()
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.px(16)
                        anchors.rightMargin: Theme.px(16)

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.px(2)
                            Text { text: "Media Player on Lock Screen"; font.family: Theme.font; font.pixelSize: Theme.fontPx(13); color: Theme.fg }
                            Text { text: "Show album art and playback controls on lock screen"; font.family: Theme.font; font.pixelSize: Theme.fontPx(11); color: Qt.rgba(1, 1, 1, 0.50) }
                        }

                        TerminalStatusBadge {
                            settingName: "Lock Screen Media Player"
                            description: "Show album art and playback controls on the lock screen."
                            checked: root.mediaOverlay
                            onClicked: {
                                root.mediaOverlay = !root.mediaOverlay
                                root.setCfg("mediaOverlay", root.mediaOverlay)
                            }
                        }
                    }
                }

                // Heartbeat Pulse Animation
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
                        onEntered: root.describe("Heartbeat Dot Pulse", "Subtle rhythmic shockwave dot pulse beneath the lock screen logo.")
                        onExited: root.clearDesc()
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.px(16)
                        anchors.rightMargin: Theme.px(16)

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.px(2)
                            Text { text: "Heartbeat Dot Pulse"; font.family: Theme.font; font.pixelSize: Theme.fontPx(13); color: Theme.fg }
                            Text { text: "Subtle rhythmic shockwave dot pulse beneath logo"; font.family: Theme.font; font.pixelSize: Theme.fontPx(11); color: Qt.rgba(1, 1, 1, 0.50) }
                        }

                        TerminalStatusBadge {
                            settingName: "Heartbeat Dot Pulse"
                            description: "Subtle rhythmic shockwave dot pulse beneath the lock screen logo."
                            checked: root.heartbeat
                            onClicked: {
                                root.heartbeat = !root.heartbeat
                                root.setCfg("heartbeat", root.heartbeat)
                            }
                        }
                    }
                }
            }
        }
    }
}
