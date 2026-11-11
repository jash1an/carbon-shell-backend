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

    // Clock
    property string clockStyle: "split_pill"
    property string clockFormat: "12"
    property bool clockShowDate: true

    // Blank Tile
    property bool blankTileEnabled: true
    property real blankTileOpacity: 1.0
    property string blankTileImagePath: ""

    // Motion
    property bool reduceMotion: false
    property int movementDuration: 105
    property int fadeDuration: 157
    property int hoverResponse: 206
    property int bounceAmount: 42

    function loadConfig() {
        if (!configProc.running) configProc.running = true
    }

    function setCfg(sec, key, val) {
        Quickshell.execDetached([root.scriptPath, "set", sec, key, String(val)])
    }

    Process {
        id: configProc
        command: [root.scriptPath, "dump-all"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) {
                var raw = line.trim()
                if (!raw) return
                try {
                    var d = JSON.parse(raw)
                    if (d.clock) {
                        if (d.clock.style !== undefined) root.clockStyle = d.clock.style
                        if (d.clock.format !== undefined) root.clockFormat = d.clock.format
                        if (d.clock.showDate !== undefined) root.clockShowDate = Boolean(d.clock.showDate)
                    }
                    if (d.blank_tile) {
                        if (d.blank_tile.enabled !== undefined) root.blankTileEnabled = Boolean(d.blank_tile.enabled)
                        if (d.blank_tile.opacity !== undefined) root.blankTileOpacity = parseFloat(d.blank_tile.opacity) || 1.0
                        if (d.blank_tile.imagePath !== undefined) root.blankTileImagePath = d.blank_tile.imagePath
                    }
                    if (d.motion) {
                        if (d.motion.reduceMotion !== undefined) root.reduceMotion = Boolean(d.motion.reduceMotion)
                        if (d.motion.movementDuration !== undefined) root.movementDuration = parseInt(d.motion.movementDuration) || 105
                        if (d.motion.fadeDuration !== undefined) root.fadeDuration = parseInt(d.motion.fadeDuration) || 157
                        if (d.motion.hoverResponse !== undefined) root.hoverResponse = parseInt(d.motion.hoverResponse) || 206
                        if (d.motion.bounce !== undefined) root.bounceAmount = parseInt(d.motion.bounce) || 42
                    }
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

            // Section 1: Clock & Typography
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.px(10)

                Text {
                    text: "CLOCK TYPOGRAPHY & TIME FORMATS"
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fontPx(11)
                    font.weight: Font.Bold
                    color: Qt.rgba(1, 1, 1, 0.40)
                }

                // Typography Style Picker
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.px(110)
                    radius: Theme.px(8)
                    color: Qt.rgba(0, 0, 0, 0.20)
                    border.color: Qt.rgba(1, 1, 1, 0.08)
                    border.width: 1

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.px(14)
                        spacing: Theme.px(10)

                        Text { text: "Typography Style Design"; font.family: Theme.font; font.pixelSize: Theme.fontPx(13); font.weight: Font.DemiBold; color: Theme.fg }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.px(8)

                            Repeater {
                                model: [
                                    { id: "split_pill", name: "Split Pill", desc: "Two-tone segmented pill showing hours and minutes in high-contrast capsules." },
                                    { id: "minimal_pill", name: "Aero Minimal", desc: "Clean, ultra-lightweight floating typography with translucent background." },
                                    { id: "titan", name: "Titan 3D", desc: "Bold architectural typography with dimensional depth shading." },
                                    { id: "stacked", name: "Stacked", desc: "Vertical hour-over-minute stack optimized for compact or square status areas." },
                                    { id: "mono_glow", name: "Nordic Mono", desc: "Monospaced clean Scandinavian clock typography with soft cyan glow." },
                                    { id: "orbitron", name: "Cyber HUD", desc: "Futuristic sci-fi angular digital display styling." }
                                ]

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: Theme.px(34)
                                    radius: Theme.px(6)
                                    color: root.clockStyle === modelData.id ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.18) : (clockMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.30))
                                    border.color: root.clockStyle === modelData.id ? Theme.primary : Qt.rgba(1, 1, 1, 0.08)
                                    border.width: 1

                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.name
                                        font.family: Theme.font
                                        font.pixelSize: Theme.fontPx(11)
                                        font.weight: root.clockStyle === modelData.id ? Font.Bold : Font.Normal
                                        color: root.clockStyle === modelData.id ? Theme.primary : Theme.fgDim
                                    }

                                    MouseArea {
                                        id: clockMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        ToolTip.visible: containsMouse
                                        ToolTip.text: modelData.desc
                                        ToolTip.delay: 300
                                        onEntered: root.describe(modelData.name + " Clock", modelData.desc)
                                        onExited: root.clearDesc()
                                        onClicked: {
                                            root.clockStyle = modelData.id
                                            root.setCfg("clock", "style", modelData.id)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // 12h vs 24h & Date Toggle
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(12)

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Theme.px(54)
                        radius: Theme.px(8)
                        color: Qt.rgba(0, 0, 0, 0.20)
                        border.color: Qt.rgba(1, 1, 1, 0.08)
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.px(16)
                            anchors.rightMargin: Theme.px(16)

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Theme.px(2)
                                Text { text: "Time Notation"; font.family: Theme.font; font.pixelSize: Theme.fontPx(13); color: Theme.fg }
                                Text { text: "12-hour AM/PM vs 24-hour military digital clock"; font.family: Theme.font; font.pixelSize: Theme.fontPx(11); color: Qt.rgba(1, 1, 1, 0.50) }
                            }

                            RowLayout {
                                spacing: Theme.px(6)
                                Rectangle {
                                    width: Theme.px(50); height: Theme.px(28); radius: Theme.px(5)
                                    color: root.clockFormat === "12" ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.20) : (mouse12.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.30))
                                    border.color: root.clockFormat === "12" ? Theme.primary : Qt.rgba(1, 1, 1, 0.10)
                                    Text { anchors.centerIn: parent; text: "12h"; font.family: Theme.fontMono; font.pixelSize: Theme.fontPx(11); color: root.clockFormat === "12" ? Theme.primary : Theme.fgDim }
                                    MouseArea {
                                        id: mouse12
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        ToolTip.visible: containsMouse
                                        ToolTip.text: "12-hour AM/PM standard clock format"
                                        ToolTip.delay: 300
                                        onEntered: root.describe("Time Notation (12h)", "12-hour AM/PM standard clock format.")
                                        onExited: root.clearDesc()
                                        onClicked: {
                                            root.clockFormat = "12"
                                            root.setCfg("clock", "format", "12")
                                        }
                                    }
                                }
                                Rectangle {
                                    width: Theme.px(50); height: Theme.px(28); radius: Theme.px(5)
                                    color: root.clockFormat === "24" ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.20) : (mouse24.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(0, 0, 0, 0.30))
                                    border.color: root.clockFormat === "24" ? Theme.primary : Qt.rgba(1, 1, 1, 0.10)
                                    Text { anchors.centerIn: parent; text: "24h"; font.family: Theme.fontMono; font.pixelSize: Theme.fontPx(11); color: root.clockFormat === "24" ? Theme.primary : Theme.fgDim }
                                    MouseArea {
                                        id: mouse24
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        ToolTip.visible: containsMouse
                                        ToolTip.text: "24-hour military digital clock format"
                                        ToolTip.delay: 300
                                        onEntered: root.describe("Time Notation (24h)", "24-hour military digital clock format.")
                                        onExited: root.clearDesc()
                                        onClicked: {
                                            root.clockFormat = "24"
                                            root.setCfg("clock", "format", "24")
                                        }
                                    }
                                }
                            }
                        }
                    }

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
                            onEntered: root.describe("Show Calendar Date", "Display weekday and calendar date beside chronometer.")
                            onExited: root.clearDesc()
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.px(16)
                            anchors.rightMargin: Theme.px(16)

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Theme.px(2)
                                Text { text: "Show Calendar Date"; font.family: Theme.font; font.pixelSize: Theme.fontPx(13); color: Theme.fg }
                                Text { text: "Display weekday and calendar date beside chronometer"; font.family: Theme.font; font.pixelSize: Theme.fontPx(11); color: Qt.rgba(1, 1, 1, 0.50) }
                            }

                            TerminalStatusBadge {
                                settingName: "Show Calendar Date"
                                description: "Display weekday and calendar date beside chronometer."
                                checked: root.clockShowDate
                                onClicked: {
                                    root.clockShowDate = !root.clockShowDate
                                    root.setCfg("clock", "showDate", root.clockShowDate)
                                }
                            }
                        }
                    }
                }
            }

            // Section 2: Blank Tile Customization
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.px(10)

                Text {
                    text: "BLANK TILE HERO CUSTOMIZATION"
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
                    border.color: Qt.rgba(1, 1, 1, 0.08)
                    border.width: 1

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                        onEntered: root.describe("Blank Tile Hero Image", "Render custom cropped image wallpaper in Spotlight hero header.")
                        onExited: root.clearDesc()
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.px(16)
                        anchors.rightMargin: Theme.px(16)

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.px(2)
                            Text { text: "Use Image Background"; font.family: Theme.font; font.pixelSize: Theme.fontPx(13); color: Theme.fg }
                            Text { text: "Render custom cropped image wallpaper in Spotlight hero header"; font.family: Theme.font; font.pixelSize: Theme.fontPx(11); color: Qt.rgba(1, 1, 1, 0.50) }
                        }

                        TerminalStatusBadge {
                            settingName: "Blank Tile Hero Image"
                            description: "Render custom cropped image wallpaper in Spotlight hero header."
                            checked: root.blankTileEnabled
                            onClicked: {
                                root.blankTileEnabled = !root.blankTileEnabled
                                root.setCfg("blank_tile", "enabled", root.blankTileEnabled)
                            }
                        }
                    }
                }

                // Opacity & Reset
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.px(68)
                    radius: Theme.px(8)
                    color: Qt.rgba(0, 0, 0, 0.20)
                    border.color: Qt.rgba(1, 1, 1, 0.08)
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.px(16)
                        spacing: Theme.px(16)

                        RazorWireSlider {
                            Layout.fillWidth: true
                            label: "Tile Image Opacity"
                            description: "Transparency level of the cropped image wallpaper inside the blank tile surface."
                            from: 0.20
                            to: 1.00
                            stepSize: 0.05
                            decimals: 2
                            value: root.blankTileOpacity
                            onMoved: (val) => {
                                root.blankTileOpacity = val
                                root.setCfg("blank_tile", "opacity", root.blankTileOpacity)
                            }
                        }

                        Rectangle {
                            Layout.preferredWidth: Theme.px(70)
                            Layout.preferredHeight: Theme.px(28)
                            radius: Theme.px(5)
                            color: resetMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06)
                            border.color: resetMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.25) : Qt.rgba(1, 1, 1, 0.12)
                            border.width: 1
                            Text { anchors.centerIn: parent; text: "Reset"; font.family: Theme.font; font.pixelSize: Theme.fontPx(11); color: Theme.fg }
                            MouseArea {
                                id: resetMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                ToolTip.visible: containsMouse
                                ToolTip.text: "Restore blank tile hero settings to default"
                                ToolTip.delay: 300
                                onEntered: root.describe("Reset Blank Tile", "Restore blank tile hero settings to default values.")
                                onExited: root.clearDesc()
                                onClicked: {
                                    root.blankTileEnabled = false
                                    root.blankTileOpacity = 1.0
                                    root.setCfg("blank_tile", "enabled", false)
                                    root.setCfg("blank_tile", "opacity", 1.0)
                                }
                            }
                        }
                    }
                }
            }

            // Section 3: Motion & Animation Kinetics
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.px(10)

                Text {
                    text: "MOTION & ANIMATION KINETICS"
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fontPx(11)
                    font.weight: Font.Bold
                    color: Qt.rgba(1, 1, 1, 0.40)
                }

                // Reduce Motion
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
                        onEntered: root.describe("Reduce Motion", "Minimize animations across the shell for maximum battery and performance.")
                        onExited: root.clearDesc()
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.px(16)
                        anchors.rightMargin: Theme.px(16)

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.px(2)
                            Text { text: "Reduce Motion"; font.family: Theme.font; font.pixelSize: Theme.fontPx(13); color: Theme.fg }
                            Text { text: "Minimize animations across the shell for maximum battery & performance"; font.family: Theme.font; font.pixelSize: Theme.fontPx(11); color: Qt.rgba(1, 1, 1, 0.50) }
                        }

                        TerminalStatusBadge {
                            settingName: "Reduce Motion"
                            description: "Minimize animations across the shell for maximum battery & performance."
                            checked: root.reduceMotion
                            onClicked: {
                                root.reduceMotion = !root.reduceMotion
                                root.setCfg("motion", "reduceMotion", root.reduceMotion)
                            }
                        }
                    }
                }

                // Movement Duration Slider
                RazorWireSlider {
                    Layout.fillWidth: true
                    label: "Movement Duration"
                    description: "Duration for geometry translations (sizing and position shifts) in milliseconds."
                    from: 50
                    to: 350
                    stepSize: 5
                    unit: "ms"
                    value: root.movementDuration
                    onMoved: (val) => {
                        root.movementDuration = Math.round(val)
                        root.setCfg("motion", "movementDuration", root.movementDuration)
                    }
                }

                // Fade Duration Slider
                RazorWireSlider {
                    Layout.fillWidth: true
                    label: "Fades & Color Shifts"
                    description: "Duration for opacity cross-fades and color transitions in milliseconds."
                    from: 50
                    to: 350
                    stepSize: 5
                    unit: "ms"
                    value: root.fadeDuration
                    onMoved: (val) => {
                        root.fadeDuration = Math.round(val)
                        root.setCfg("motion", "fadeDuration", root.fadeDuration)
                    }
                }

                // Hover Response Time
                RazorWireSlider {
                    Layout.fillWidth: true
                    label: "Hover Response Time"
                    description: "Micro-interaction delay for tooltip and focus glow in milliseconds."
                    from: 50
                    to: 400
                    stepSize: 10
                    unit: "ms"
                    value: root.hoverResponse
                    onMoved: (val) => {
                        root.hoverResponse = Math.round(val)
                        root.setCfg("motion", "hoverResponse", root.hoverResponse)
                    }
                }
            }
        }
    }
}
