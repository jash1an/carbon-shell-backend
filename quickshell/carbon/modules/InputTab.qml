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

    // Mouse states
    property real sensitivity: 0.0
    property string accelProfile: "flat"
    property bool leftHanded: false
    property bool naturalScrollMouse: false
    property bool touchpadEnabled: true
    property bool tapToClick: true
    property bool tapAndDrag: true
    property bool naturalScrollTouchpad: true
    property bool disableWhileTyping: true
    property real scrollFactor: 1.0

    // Keyboard states
    property string kbLayout: "us"
    property int repeatDelay: 600
    property int repeatRate: 25
    property bool numlockByDefault: false

    readonly property string scriptPath: (Quickshell.env("HOME") || "") + "/.config/carbon/scripts/carbon-input-apply.py"

    FileView {
        id: mouseJsonFile
        path: (Quickshell.env("HOME") || "") + "/.config/carbon/carbon-mouse-touchpad.json"
        watchChanges: true
        blockLoading: true
        printErrors: false
        onLoaded: root.loadMouseConfig()
        onFileChanged: {
            reload()
            root.loadMouseConfig()
        }
    }

    FileView {
        id: kbJsonFile
        path: (Quickshell.env("HOME") || "") + "/.config/carbon/carbon-keyboard.json"
        watchChanges: true
        blockLoading: true
        printErrors: false
        onLoaded: root.loadKbConfig()
        onFileChanged: {
            reload()
            root.loadKbConfig()
        }
    }

    function loadMouseConfig() {
        try {
            var txt = mouseJsonFile.text().trim()
            if (txt.length > 0) {
                var d = JSON.parse(txt)
                if (d.sensitivity !== undefined) root.sensitivity = parseFloat(d.sensitivity) || 0.0
                if (d.accel_profile !== undefined) root.accelProfile = String(d.accel_profile)
                if (d.left_handed !== undefined) root.leftHanded = Boolean(d.left_handed)
                if (d.natural_scroll_mouse !== undefined) root.naturalScrollMouse = Boolean(d.natural_scroll_mouse)
                if (d.touchpad_enabled !== undefined) root.touchpadEnabled = Boolean(d.touchpad_enabled)
                if (d.tap_to_click !== undefined) root.tapToClick = Boolean(d.tap_to_click)
                if (d.tap_and_drag !== undefined) root.tapAndDrag = Boolean(d.tap_and_drag)
                if (d.natural_scroll_touchpad !== undefined) root.naturalScrollTouchpad = Boolean(d.natural_scroll_touchpad)
                if (d.disable_while_typing !== undefined) root.disableWhileTyping = Boolean(d.disable_while_typing)
                if (d.scroll_factor !== undefined) root.scrollFactor = parseFloat(d.scroll_factor) || 1.0
            }
        } catch (e) {}
    }

    function loadKbConfig() {
        try {
            var txt = kbJsonFile.text().trim()
            if (txt.length > 0) {
                var d = JSON.parse(txt)
                if (d.kb_layout !== undefined) root.kbLayout = String(d.kb_layout)
                if (d.repeat_delay !== undefined) root.repeatDelay = parseInt(d.repeat_delay) || 600
                if (d.repeat_rate !== undefined) root.repeatRate = parseInt(d.repeat_rate) || 25
                if (d.numlock_by_default !== undefined) root.numlockByDefault = Boolean(d.numlock_by_default)
            }
        } catch (e) {}
    }

    function setMouse(key, val) {
        Quickshell.execDetached([root.scriptPath, "set-mouse", key, String(val)])
    }

    function setKb(key, val) {
        Quickshell.execDetached([root.scriptPath, "set-kb", key, String(val)])
    }

    Component.onCompleted: {
        root.loadMouseConfig()
        root.loadKbConfig()
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ===================================================================
        // LEFT COLUMN: MOUSE & TOUCHPAD
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

                    // Section Header
                    Text {
                        text: "MOUSE & POINTER"
                        font.family: Theme.font
                        font.pixelSize: Theme.fontPx(11)
                        font.weight: Font.Bold
                        color: Qt.rgba(1, 1, 1, 0.45)
                    }

                    // Pointer Sensitivity Slider
                    RazorWireSlider {
                        Layout.fillWidth: true
                        label: "Pointer Sensitivity"
                        description: "Hardware mouse pointer sensitivity multiplier (-1.0 to 1.0)."
                        from: -1.00
                        to: 1.00
                        stepSize: 0.05
                        decimals: 2
                        value: root.sensitivity
                        onMoved: (val) => {
                            root.sensitivity = val
                            root.setMouse("sensitivity", val)
                        }
                    }

                    // Acceleration Profile
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            text: "Acceleration Profile"
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
                                    { id: "flat", label: "Flat (Gaming/Precision)", desc: "1:1 linear mouse response with zero software acceleration." },
                                    { id: "adaptive", label: "Adaptive (Natural/Desktop)", desc: "Speed-dependent curve for fluid cursor travel across high-res displays." }
                                ]

                                delegate: Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 32
                                    radius: 8
                                    readonly property bool isSelected: root.accelProfile === modelData.id
                                    color: isSelected ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.18) : (accelMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(1, 1, 1, 0.02))
                                    border.color: isSelected ? Theme.primary : Qt.rgba(1, 1, 1, 0.08)
                                    border.width: 1

                                    scale: accelMouse.pressed ? 0.96 : (accelMouse.containsMouse ? 1.02 : 1.0)
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    Behavior on border.color { ColorAnimation { duration: 150 } }
                                    Behavior on scale { NumberAnimation { duration: 150 } }

                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.label
                                        font.family: Theme.font
                                        font.pixelSize: Theme.fontPx(11)
                                        font.weight: parent.isSelected ? Font.DemiBold : Font.Normal
                                        color: parent.isSelected ? Theme.primary : Qt.rgba(1, 1, 1, 0.65)
                                    }

                                    MouseArea {
                                        id: accelMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onEntered: root.describe(modelData.label, modelData.desc)
                                        onExited: root.clearDesc()
                                        ToolTip.visible: containsMouse
                                        ToolTip.text: modelData.desc
                                        ToolTip.delay: 300
                                        onClicked: {
                                            root.accelProfile = modelData.id
                                            root.setMouse("accel_profile", modelData.id)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Natural Scroll Mouse
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 36
                        radius: 8
                        color: mouseScrollArea.containsMouse ? Qt.rgba(1, 1, 1, 0.04) : "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8

                            Text {
                                text: "Natural Scrolling (Mouse Wheel)"
                                font.family: Theme.font
                                font.pixelSize: Theme.fontPx(12)
                                font.weight: Font.Medium
                                color: Qt.rgba(1, 1, 1, 0.85)
                                Layout.fillWidth: true
                            }

                            TerminalStatusBadge {
                                checked: root.naturalScrollMouse
                                interactive: false
                                Layout.alignment: Qt.AlignRight
                            }
                        }

                        MouseArea {
                            id: mouseScrollArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: root.describe("Natural Scrolling (Mouse)", "Invert mouse wheel scrolling direction to match touch swipe behavior.")
                            onExited: root.clearDesc()
                            ToolTip.visible: containsMouse
                            ToolTip.text: "Invert mouse wheel scrolling direction to match touch swipe behavior."
                            ToolTip.delay: 300
                            onClicked: {
                                root.naturalScrollMouse = !root.naturalScrollMouse
                                root.setMouse("natural_scroll_mouse", root.naturalScrollMouse)
                            }
                        }
                    }

                    // Left Handed Mouse
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 36
                        radius: 8
                        color: lhArea.containsMouse ? Qt.rgba(1, 1, 1, 0.04) : "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8

                            Text {
                                text: "Left-Handed Mouse Buttons"
                                font.family: Theme.font
                                font.pixelSize: Theme.fontPx(12)
                                font.weight: Font.Medium
                                color: Qt.rgba(1, 1, 1, 0.85)
                                Layout.fillWidth: true
                            }

                            TerminalStatusBadge {
                                checked: root.leftHanded
                                interactive: false
                                Layout.alignment: Qt.AlignRight
                            }
                        }

                        MouseArea {
                            id: lhArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: root.describe("Left-Handed Mouse", "Swap primary left and right mouse buttons for left-handed ergonomics.")
                            onExited: root.clearDesc()
                            ToolTip.visible: containsMouse
                            ToolTip.text: "Swap primary left and right mouse buttons for left-handed ergonomics."
                            ToolTip.delay: 300
                            onClicked: {
                                root.leftHanded = !root.leftHanded
                                root.setMouse("left_handed", root.leftHanded)
                            }
                        }
                    }

                    // Hairline
                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Qt.rgba(1, 1, 1, 0.08)
                    }

                    // Section Header: Touchpad
                    Text {
                        text: "TOUCHPAD & GESTURES"
                        font.family: Theme.font
                        font.pixelSize: Theme.fontPx(11)
                        font.weight: Font.Bold
                        color: Qt.rgba(1, 1, 1, 0.45)
                    }

                    // Touchpad Enabled
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 36
                        radius: 8
                        color: tpArea.containsMouse ? Qt.rgba(1, 1, 1, 0.04) : "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8

                            Text {
                                text: "Touchpad Enabled"
                                font.family: Theme.font
                                font.pixelSize: Theme.fontPx(12)
                                font.weight: Font.Medium
                                color: Qt.rgba(1, 1, 1, 0.85)
                                Layout.fillWidth: true
                            }

                            TerminalStatusBadge {
                                checked: root.touchpadEnabled
                                interactive: false
                                Layout.alignment: Qt.AlignRight
                            }
                        }

                        MouseArea {
                            id: tpArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: root.describe("Touchpad Enabled", "Master toggle to enable or disable the built-in laptop touchpad.")
                            onExited: root.clearDesc()
                            ToolTip.visible: containsMouse
                            ToolTip.text: "Master toggle to enable or disable the built-in laptop touchpad."
                            ToolTip.delay: 300
                            onClicked: {
                                root.touchpadEnabled = !root.touchpadEnabled
                                root.setMouse("touchpad_enabled", root.touchpadEnabled)
                            }
                        }
                    }

                    // Tap to Click
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 36
                        radius: 8
                        color: tapArea.containsMouse ? Qt.rgba(1, 1, 1, 0.04) : "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8

                            Text {
                                text: "Tap to Click"
                                font.family: Theme.font
                                font.pixelSize: Theme.fontPx(12)
                                font.weight: Font.Medium
                                color: Qt.rgba(1, 1, 1, 0.85)
                                Layout.fillWidth: true
                            }

                            TerminalStatusBadge {
                                checked: root.tapToClick
                                interactive: false
                                Layout.alignment: Qt.AlignRight
                            }
                        }

                        MouseArea {
                            id: tapArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: root.describe("Tap to Click", "Tap touchpad surface with 1 finger for left-click, 2 fingers for right-click.")
                            onExited: root.clearDesc()
                            ToolTip.visible: containsMouse
                            ToolTip.text: "Tap touchpad surface with 1 finger for left-click, 2 fingers for right-click."
                            ToolTip.delay: 300
                            onClicked: {
                                root.tapToClick = !root.tapToClick
                                root.setMouse("tap_to_click", root.tapToClick)
                            }
                        }
                    }

                    // Tap and Drag
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 36
                        radius: 8
                        color: dragArea.containsMouse ? Qt.rgba(1, 1, 1, 0.04) : "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8

                            Text {
                                text: "Tap and Drag"
                                font.family: Theme.font
                                font.pixelSize: Theme.fontPx(12)
                                font.weight: Font.Medium
                                color: Qt.rgba(1, 1, 1, 0.85)
                                Layout.fillWidth: true
                            }

                            TerminalStatusBadge {
                                checked: root.tapAndDrag
                                interactive: false
                                Layout.alignment: Qt.AlignRight
                            }
                        }

                        MouseArea {
                            id: dragArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: root.describe("Tap and Drag", "Double-tap and slide finger to drag windows or select text without physical click.")
                            onExited: root.clearDesc()
                            ToolTip.visible: containsMouse
                            ToolTip.text: "Double-tap and slide finger to drag windows or select text without physical click."
                            ToolTip.delay: 300
                            onClicked: {
                                root.tapAndDrag = !root.tapAndDrag
                                root.setMouse("tap_and_drag", root.tapAndDrag)
                            }
                        }
                    }

                    // Natural Scroll Touchpad
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 36
                        radius: 8
                        color: tpNatArea.containsMouse ? Qt.rgba(1, 1, 1, 0.04) : "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8

                            Text {
                                text: "Natural Scrolling (Two-Finger)"
                                font.family: Theme.font
                                font.pixelSize: Theme.fontPx(12)
                                font.weight: Font.Medium
                                color: Qt.rgba(1, 1, 1, 0.85)
                                Layout.fillWidth: true
                            }

                            TerminalStatusBadge {
                                checked: root.naturalScrollTouchpad
                                interactive: false
                                Layout.alignment: Qt.AlignRight
                            }
                        }

                        MouseArea {
                            id: tpNatArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: root.describe("Natural Scrolling (Touchpad)", "Two-finger swipe direction matches content movement on screen.")
                            onExited: root.clearDesc()
                            ToolTip.visible: containsMouse
                            ToolTip.text: "Two-finger swipe direction matches content movement on screen."
                            ToolTip.delay: 300
                            onClicked: {
                                root.naturalScrollTouchpad = !root.naturalScrollTouchpad
                                root.setMouse("natural_scroll_touchpad", root.naturalScrollTouchpad)
                            }
                        }
                    }

                    // Disable while typing
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 36
                        radius: 8
                        color: dwtArea.containsMouse ? Qt.rgba(1, 1, 1, 0.04) : "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8

                            Text {
                                text: "Disable Touchpad While Typing"
                                font.family: Theme.font
                                font.pixelSize: Theme.fontPx(12)
                                font.weight: Font.Medium
                                color: Qt.rgba(1, 1, 1, 0.85)
                                Layout.fillWidth: true
                            }

                            TerminalStatusBadge {
                                checked: root.disableWhileTyping
                                interactive: false
                                Layout.alignment: Qt.AlignRight
                            }
                        }

                        MouseArea {
                            id: dwtArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: root.describe("Disable While Typing", "Temporarily ignore touchpad input while typing to avoid accidental palm cursor jumps.")
                            onExited: root.clearDesc()
                            ToolTip.visible: containsMouse
                            ToolTip.text: "Temporarily ignore touchpad input while typing to avoid accidental palm cursor jumps."
                            ToolTip.delay: 300
                            onClicked: {
                                root.disableWhileTyping = !root.disableWhileTyping
                                root.setMouse("disable_while_typing", root.disableWhileTyping)
                            }
                        }
                    }

                    // Touchpad Scroll Speed Slider
                    RazorWireSlider {
                        Layout.fillWidth: true
                        label: "Touchpad Scroll Speed"
                        description: "Scroll speed acceleration multiplier for two-finger touchpad scrolling."
                        from: 0.20
                        to: 2.00
                        stepSize: 0.05
                        decimals: 2
                        unit: "x"
                        value: root.scrollFactor
                        onMoved: (val) => {
                            root.scrollFactor = val
                            root.setMouse("scroll_factor", val)
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
        // RIGHT COLUMN: KEYBOARD
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
                        text: "KEYBOARD HARDWARE & REPEAT"
                        font.family: Theme.font
                        font.pixelSize: Theme.fontPx(11)
                        font.weight: Font.Bold
                        color: Qt.rgba(1, 1, 1, 0.45)
                    }

                    // Layout Selection
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        Text {
                            text: "Active Keyboard Layout"
                            font.family: Theme.font
                            font.pixelSize: Theme.fontPx(12)
                            font.weight: Font.Medium
                            color: Qt.rgba(1, 1, 1, 0.85)
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8

                            Repeater {
                                model: ["us", "gb", "de", "fr"]

                                delegate: Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 32
                                    radius: 8
                                    readonly property bool isSelected: root.kbLayout === modelData
                                    color: isSelected ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.18) : (kbLayoutMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(1, 1, 1, 0.02))
                                    border.color: isSelected ? Theme.primary : Qt.rgba(1, 1, 1, 0.08)
                                    border.width: 1

                                    scale: kbLayoutMouse.pressed ? 0.96 : (kbLayoutMouse.containsMouse ? 1.02 : 1.0)
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    Behavior on border.color { ColorAnimation { duration: 150 } }
                                    Behavior on scale { NumberAnimation { duration: 150 } }

                                    Text {
                                        anchors.centerIn: parent
                                        text: modelData.toUpperCase()
                                        font.family: Theme.fontMono
                                        font.pixelSize: Theme.fontPx(11)
                                        font.weight: parent.isSelected ? Font.Bold : Font.Normal
                                        color: parent.isSelected ? Theme.primary : Qt.rgba(1, 1, 1, 0.65)
                                    }

                                    MouseArea {
                                        id: kbLayoutMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onEntered: root.describe("Keyboard Layout: " + modelData.toUpperCase(), "Switch active system XKB keyboard mapping to " + modelData.toUpperCase() + ".")
                                        onExited: root.clearDesc()
                                        ToolTip.visible: containsMouse
                                        ToolTip.text: "Switch active keyboard layout to " + modelData.toUpperCase()
                                        ToolTip.delay: 300
                                        onClicked: {
                                            root.kbLayout = modelData
                                            root.setKb("kb_layout", modelData)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Key Repeat Delay Slider
                    RazorWireSlider {
                        Layout.fillWidth: true
                        label: "Key Repeat Delay"
                        description: "Time (ms) a key must be held down before it starts repeating."
                        from: 150
                        to: 1000
                        stepSize: 25
                        decimals: 0
                        unit: "ms"
                        value: root.repeatDelay
                        onMoved: (val) => {
                            root.repeatDelay = Math.round(val)
                            root.setKb("repeat_delay", root.repeatDelay)
                        }
                    }

                    // Key Repeat Rate Slider
                    RazorWireSlider {
                        Layout.fillWidth: true
                        label: "Key Repeat Rate"
                        description: "Number of character repetitions per second while a key is held."
                        from: 10
                        to: 100
                        stepSize: 5
                        decimals: 0
                        unit: "Hz"
                        value: root.repeatRate
                        onMoved: (val) => {
                            root.repeatRate = Math.round(val)
                            root.setKb("repeat_rate", root.repeatRate)
                        }
                    }

                    // NumLock by Default
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 36
                        radius: 8
                        color: numlockArea.containsMouse ? Qt.rgba(1, 1, 1, 0.04) : "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 8

                            Text {
                                text: "NumLock Enabled by Default"
                                font.family: Theme.font
                                font.pixelSize: Theme.fontPx(12)
                                font.weight: Font.Medium
                                color: Qt.rgba(1, 1, 1, 0.85)
                                Layout.fillWidth: true
                            }

                            TerminalStatusBadge {
                                checked: root.numlockByDefault
                                interactive: false
                                Layout.alignment: Qt.AlignRight
                            }
                        }

                        MouseArea {
                            id: numlockArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: root.describe("NumLock by Default", "Automatically activate numeric keypad NumLock on desktop login.")
                            onExited: root.clearDesc()
                            ToolTip.visible: containsMouse
                            ToolTip.text: "Automatically activate numeric keypad NumLock on desktop login."
                            ToolTip.delay: 300
                            onClicked: {
                                root.numlockByDefault = !root.numlockByDefault
                                root.setKb("numlock_by_default", root.numlockByDefault)
                            }
                        }
                    }
                }
            }
        }
    }
}
