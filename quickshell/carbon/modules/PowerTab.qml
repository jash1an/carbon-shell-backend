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

    implicitWidth: 800
    implicitHeight: 600

    property string profile: "balanced"
    property string powerButtonAction: "poweroff"
    property string lidActionBattery: "suspend"
    property bool dimEnabled: true
    property int dimTimeout: 180
    property int dimBrightnessPercent: 20
    property int screenOffTimeout: 300
    property int autoSuspendTimeout: 1800

    readonly property string scriptPath: (Quickshell.env("HOME") || "") + "/.config/carbon/scripts/carbon-power-apply.py"

    FileView {
        id: powerJsonFile
        path: (Quickshell.env("HOME") || "") + "/.config/carbon/carbon-power.json"
        watchChanges: true
        blockLoading: true
        printErrors: false
        onLoaded: root.loadPowerConfig()
        onFileChanged: {
            reload()
            root.loadPowerConfig()
        }
    }

    function loadPowerConfig() {
        try {
            var txt = powerJsonFile.text().trim()
            if (txt.length > 0) {
                var d = JSON.parse(txt)
                if (d.profile !== undefined) root.profile = String(d.profile)
                if (d.powerButtonAction !== undefined) root.powerButtonAction = String(d.powerButtonAction)
                if (d.lidActionBattery !== undefined) root.lidActionBattery = String(d.lidActionBattery)
                if (d.dimEnabled !== undefined) root.dimEnabled = Boolean(d.dimEnabled)
                if (d.dimTimeout !== undefined) root.dimTimeout = parseInt(d.dimTimeout) || 180
                if (d.dimBrightnessPercent !== undefined) root.dimBrightnessPercent = parseInt(d.dimBrightnessPercent) || 20
                if (d.screenOffTimeout !== undefined) root.screenOffTimeout = parseInt(d.screenOffTimeout) || 300
                if (d.autoSuspendTimeout !== undefined) root.autoSuspendTimeout = parseInt(d.autoSuspendTimeout) || 1800
            }
        } catch (e) {}
    }

    function setPower(key, val) {
        Quickshell.execDetached([root.scriptPath, "set", key, String(val)])
    }

    Component.onCompleted: root.loadPowerConfig()

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ===================================================================
        // LEFT COLUMN: POWER PROFILES & HARDWARE ACTIONS
        // ===================================================================
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredWidth: 420

            Flickable {
                anchors.fill: parent
                contentWidth: width
                contentHeight: leftContent.implicitHeight + 40
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: leftContent
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 20
                    spacing: 16

                    // Header
                    Text {
                        text: "ACTIVE POWER PROFILE"
                        font.family: Theme.font
                        font.pixelSize: Theme.fontPx(11)
                        font.weight: Font.Bold
                        color: Qt.rgba(1, 1, 1, 0.45)
                    }

                    // Profiles Selector (Power Saver, Balanced, Performance)
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Repeater {
                            model: [
                                { id: "power-saver", name: "Power Saver", desc: "Minimize energy consumption, cooler temperatures & extended battery", glyph: "󰾆" },
                                { id: "balanced", name: "Balanced", desc: "Intelligent dynamic scaling between efficiency and peak responsiveness", glyph: "󰓅" },
                                { id: "performance", name: "Performance", desc: "Uncapped CPU clock frequencies, zero governor throttling & raw speed", glyph: "󱐋" }
                            ]

                            delegate: Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 60
                                radius: 10
                                readonly property bool isSelected: root.profile === modelData.id
                                color: isSelected ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.14) : (profMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(0, 0, 0, 0.25))
                                border.color: isSelected ? Theme.primary : Qt.rgba(1, 1, 1, 0.08)
                                border.width: 1

                                scale: profMouse.pressed ? 0.98 : (profMouse.containsMouse ? 1.01 : 1.0)
                                Behavior on color { ColorAnimation { duration: 150 } }
                                Behavior on border.color { ColorAnimation { duration: 150 } }
                                Behavior on scale { NumberAnimation { duration: 150 } }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 14
                                    anchors.rightMargin: 14
                                    spacing: 12

                                    Rectangle {
                                        Layout.preferredWidth: 34
                                        Layout.preferredHeight: 34
                                        radius: 8
                                        color: parent.parent.isSelected ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.20) : Qt.rgba(1, 1, 1, 0.04)

                                        Text {
                                            anchors.centerIn: parent
                                            text: modelData.glyph
                                            font.family: Theme.fontMono
                                            font.pixelSize: Theme.fontPx(16)
                                            color: parent.parent.parent.isSelected ? Theme.primary : Qt.rgba(1, 1, 1, 0.50)
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2

                                        Text {
                                            text: modelData.name
                                            font.family: Theme.font
                                            font.pixelSize: Theme.fontPx(13)
                                            font.weight: parent.parent.isSelected ? Font.Bold : Font.Medium
                                            color: parent.parent.isSelected ? Theme.primary : Qt.rgba(1, 1, 1, 0.90)
                                        }

                                        Text {
                                            text: modelData.desc
                                            font.family: Theme.font
                                            font.pixelSize: Theme.fontPx(10.5)
                                            color: Qt.rgba(1, 1, 1, 0.45)
                                            Layout.fillWidth: true
                                            elide: Text.ElideRight
                                        }
                                    }

                                    Text {
                                        visible: parent.parent.isSelected
                                        text: "ACTIVE"
                                        font.family: Theme.fontMono
                                        font.pixelSize: Theme.fontPx(9.5)
                                        font.weight: Font.Bold
                                        color: Theme.primary
                                    }
                                }

                                MouseArea {
                                    id: profMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onEntered: root.describe(modelData.name + " Profile", modelData.desc)
                                    onExited: root.clearDesc()
                                    ToolTip.visible: containsMouse
                                    ToolTip.text: modelData.desc
                                    ToolTip.delay: 300
                                    onClicked: {
                                        root.profile = modelData.id
                                        root.setPower("profile", modelData.id)
                                    }
                                }
                            }
                        }
                    }

                    // Hairline
                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Qt.rgba(1, 1, 1, 0.08)
                    }

                    // Hardware Event Triggers Header
                    Text {
                        text: "HARDWARE BUTTONS & LID ACTIONS"
                        font.family: Theme.font
                        font.pixelSize: Theme.fontPx(11)
                        font.weight: Font.Bold
                        color: Qt.rgba(1, 1, 1, 0.45)
                    }

                    // Laptop Lid Closed Action
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            text: "When Laptop Lid is Closed"
                            font.family: Theme.font
                            font.pixelSize: Theme.fontPx(12)
                            font.weight: Font.Medium
                            color: Qt.rgba(1, 1, 1, 0.85)
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Repeater {
                                model: [
                                    { id: "suspend", label: "Suspend" },
                                    { id: "lock", label: "Lock Screen" },
                                    { id: "ignore", label: "Do Nothing" }
                                ]

                                delegate: Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 32
                                    radius: 8
                                    readonly property bool isSelected: root.lidActionBattery === modelData.id
                                    color: isSelected ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.18) : (lidMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(1, 1, 1, 0.02))
                                    border.color: isSelected ? Theme.primary : Qt.rgba(1, 1, 1, 0.08)
                                    border.width: 1

                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.label
                                        font.family: Theme.font
                                        font.pixelSize: Theme.fontPx(11)
                                        font.weight: parent.isSelected ? Font.DemiBold : Font.Normal
                                        color: parent.isSelected ? Theme.primary : Qt.rgba(1, 1, 1, 0.65)
                                    }

                                    MouseArea {
                                        id: lidMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onEntered: root.describe("Lid Action: " + modelData.label, "When laptop lid is closed: " + modelData.label + ".")
                                        onExited: root.clearDesc()
                                        ToolTip.visible: containsMouse
                                        ToolTip.text: "When laptop lid is closed: " + modelData.label
                                        ToolTip.delay: 300
                                        onClicked: {
                                            root.lidActionBattery = modelData.id
                                            root.setPower("lidActionBattery", modelData.id)
                                            root.setPower("lidActionAC", modelData.id)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Physical Power Button Action
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            text: "When Physical Power Button Pressed"
                            font.family: Theme.font
                            font.pixelSize: Theme.fontPx(12)
                            font.weight: Font.Medium
                            color: Qt.rgba(1, 1, 1, 0.85)
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Repeater {
                                model: [
                                    { id: "poweroff", label: "Power Off Menu" },
                                    { id: "suspend", label: "Suspend" },
                                    { id: "ignore", label: "Ignore" }
                                ]

                                delegate: Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 32
                                    radius: 8
                                    readonly property bool isSelected: root.powerButtonAction === modelData.id
                                    color: isSelected ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.18) : (pwrBtnMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(1, 1, 1, 0.02))
                                    border.color: isSelected ? Theme.primary : Qt.rgba(1, 1, 1, 0.08)
                                    border.width: 1

                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.label
                                        font.family: Theme.font
                                        font.pixelSize: Theme.fontPx(11)
                                        font.weight: parent.isSelected ? Font.DemiBold : Font.Normal
                                        color: parent.isSelected ? Theme.primary : Qt.rgba(1, 1, 1, 0.65)
                                    }

                                    MouseArea {
                                        id: pwrBtnMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onEntered: root.describe("Power Button: " + modelData.label, "Action triggered when hardware power button is tapped: " + modelData.label + ".")
                                        onExited: root.clearDesc()
                                        ToolTip.visible: containsMouse
                                        ToolTip.text: "Action triggered when power button tapped: " + modelData.label
                                        ToolTip.delay: 300
                                        onClicked: {
                                            root.powerButtonAction = modelData.id
                                            root.setPower("powerButtonAction", modelData.id)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // 1px Vertical Hairline Separator
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 1
            color: Qt.rgba(1, 1, 1, 0.08)
        }

        // ===================================================================
        // RIGHT COLUMN: AUTOMATED SLEEP & HYPRIDLE TIMEOUTS
        // ===================================================================
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredWidth: 380

            Flickable {
                anchors.fill: parent
                contentWidth: width
                contentHeight: rightContent.implicitHeight + 40
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: rightContent
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 20
                    spacing: 16

                    // Section Header
                    Text {
                        text: "AUTOMATED SLEEP & HYPRIDLE"
                        font.family: Theme.font
                        font.pixelSize: Theme.fontPx(11)
                        font.weight: Font.Bold
                        color: Qt.rgba(1, 1, 1, 0.45)
                    }

                    // Display Backlight Dimming Toggle
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 36
                        radius: 8
                        color: dimArea.containsMouse ? Qt.rgba(1, 1, 1, 0.04) : "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8

                            Text {
                                text: "Idle Screen Dimming"
                                font.family: Theme.font
                                font.pixelSize: Theme.fontPx(12)
                                font.weight: Font.Medium
                                color: Qt.rgba(1, 1, 1, 0.85)
                                Layout.fillWidth: true
                            }

                            TerminalStatusBadge {
                                checked: root.dimEnabled
                                interactive: false
                                Layout.alignment: Qt.AlignRight
                            }
                        }

                        MouseArea {
                            id: dimArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: root.describe("Idle Screen Dimming", "Dim screen backlight to low brightness when inactive before sleeping.")
                            onExited: root.clearDesc()
                            ToolTip.visible: containsMouse
                            ToolTip.text: "Dim screen backlight to low brightness when inactive before sleeping."
                            ToolTip.delay: 300
                            onClicked: {
                                root.dimEnabled = !root.dimEnabled
                                root.setPower("dimEnabled", root.dimEnabled)
                            }
                        }
                    }

                    // Dim Timeout Slider
                    RazorWireSlider {
                        Layout.fillWidth: true
                        label: "Dimming Delay"
                        description: "Time (seconds) of inactivity before display begins dimming."
                        from: 30
                        to: 600
                        stepSize: 15
                        decimals: 0
                        unit: "s"
                        value: root.dimTimeout
                        onMoved: (val) => {
                            root.dimTimeout = Math.round(val)
                            root.setPower("dimTimeout", root.dimTimeout)
                        }
                    }

                    // Dim Level Percentage
                    RazorWireSlider {
                        Layout.fillWidth: true
                        label: "Dimmed Backlight Level"
                        description: "Target backlight brightness percentage while in dimmed idle state."
                        from: 5
                        to: 50
                        stepSize: 1
                        decimals: 0
                        unit: "%"
                        value: root.dimBrightnessPercent
                        onMoved: (val) => {
                            root.dimBrightnessPercent = Math.round(val)
                            root.setPower("dimBrightnessPercent", root.dimBrightnessPercent)
                        }
                    }

                    // Hairline
                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Qt.rgba(1, 1, 1, 0.08)
                    }

                    // Screen Off Timeout
                    RazorWireSlider {
                        Layout.fillWidth: true
                        label: "Turn Off Screen Timeout"
                        description: "Time (seconds) of inactivity before monitors turn off into standby."
                        from: 60
                        to: 3600
                        stepSize: 60
                        decimals: 0
                        unit: "s"
                        value: root.screenOffTimeout
                        onMoved: (val) => {
                            root.screenOffTimeout = Math.round(val)
                            root.setPower("screenOffTimeout", root.screenOffTimeout)
                        }
                    }

                    // Auto Suspend Timeout (0 = disabled)
                    RazorWireSlider {
                        Layout.fillWidth: true
                        label: "Auto Suspend Timeout (0=Off)"
                        description: "Time (seconds) of inactivity before system enters deep ACPI sleep (0 to disable)."
                        from: 0
                        to: 7200
                        stepSize: 300
                        decimals: 0
                        unit: "s"
                        value: root.autoSuspendTimeout
                        onMoved: (val) => {
                            root.autoSuspendTimeout = Math.round(val)
                            root.setPower("autoSuspendTimeout", root.autoSuspendTimeout)
                        }
                    }
                }
            }
        }
    }
}
