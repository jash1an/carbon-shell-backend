import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Services.SystemTray
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import M3Shapes
import "../Singletons"
import "../components"

/**
 * Nebula-style Top-Right Island (Proportionally Scaled 38px):
 *   - Horizontal System Tray
 *   - Battery badge (Icon + %, hover/click opens BatteryPopup)
 *   - Sound icon (hover/click opens audio & mic device popup)
 *   - Sun icon (hover/click opens brightness control popup)
 *   - Bell icon (hover/click opens animated NotificationPopup)
 *   - Power button (opens native animated PowerMenu)
 */
Item {
    id: root

    implicitHeight: root.vertical ? (verticalCol.implicitHeight + (root.attachedEdge !== "" ? 24 : (root.showBackground ? 16 : 8))) : 38
    implicitWidth: root.vertical ? (root.attachedEdge !== "" ? 34 : 38) : pill.width

    property var anchorWindow: null
    property int notifCount: 0

    signal openMixer()
    signal closeMixer()
    signal toggleMixer()
    signal openBrightness()
    signal closeBrightness()
    signal toggleBrightness()
    signal openBattery()
    signal closeBattery()
    signal toggleBattery()
    signal openTray()
    signal closeTray()
    signal toggleTray()
    signal toggleControls()
    signal openPower()

    /* Audio Sink State */
    readonly property var audioSink: Pipewire.defaultAudioSink
    readonly property real volume: audioSink && audioSink.audio ? audioSink.audio.volume : 0.0
    readonly property bool muted: audioSink && audioSink.audio ? audioSink.audio.muted : false

    readonly property string volumeGlyph: {
        if (root.muted) return "volume_off"
        if (root.volume > 0.5) return "volume_up"
        if (root.volume > 0.0) return "volume_down"
        return "volume_mute"
    }

    /* Battery State */
    readonly property var battery: UPower.displayDevice
    readonly property bool hasBattery: battery ? battery.isPresent : false
    readonly property real batteryPct: battery ? battery.percentage : 1.0
    readonly property bool isCharging: battery ? battery.state === UPowerDeviceState.Charging : false

    readonly property string batteryGlyph: {
        if (root.isCharging) return "battery_charging_full"
        if (root.batteryPct > 0.8) return "battery_full"
        if (root.batteryPct > 0.5) return "battery_5_bar"
        if (root.batteryPct > 0.2) return "battery_3_bar"
        return "battery_alert"
    }

    /* System Tray Items */
    readonly property var trayItems: SystemTray.items.values.filter(function (it) {
        var key = ((it.id || "") + " " + (it.title || "") + " " + (it.tooltipTitle || "")).toLowerCase()
        return !/(nm[ _-]?applet|blueman)/.test(key)
    })

    property bool showBackground: true
    property bool vertical: false
    property string attachedEdge: ""

    readonly property string notchFillPath: {
        const w = pill.width
        const h = pill.height
        const rf = 12
        const rc = 12
        if (root.attachedEdge === "left") {
            return `M 0 0 A ${rf} ${rf} 0 0 0 ${rf} ${rf} L ${w - rc} ${rf} A ${rc} ${rc} 0 0 1 ${w} ${rf + rc} L ${w} ${h - (rf + rc)} A ${rc} ${rc} 0 0 1 ${w - rc} ${h - rf} L ${rf} ${h - rf} A ${rf} ${rf} 0 0 0 0 ${h} L 0 0 Z`
        } else if (root.attachedEdge === "right") {
            return `M ${w} 0 A ${rf} ${rf} 0 0 1 ${w - rf} ${rf} L ${rc} ${rf} A ${rc} ${rc} 0 0 0 0 ${rf + rc} L 0 ${h - (rf + rc)} A ${rc} ${rc} 0 0 0 ${rc} ${h - rf} L ${w - rf} ${h - rf} A ${rf} ${rf} 0 0 1 ${w} ${h} L ${w} 0 Z`
        }
        return ""
    }

    readonly property string notchStrokePath: {
        const w = pill.width
        const h = pill.height
        const rf = 12
        const rc = 12
        if (root.attachedEdge === "left") {
            return `M 0 0 A ${rf} ${rf} 0 0 0 ${rf} ${rf} L ${w - rc} ${rf} A ${rc} ${rc} 0 0 1 ${w} ${rf + rc} L ${w} ${h - (rf + rc)} A ${rc} ${rc} 0 0 1 ${w - rc} ${h - rf} L ${rf} ${h - rf} A ${rf} ${rf} 0 0 0 0 ${h}`
        } else if (root.attachedEdge === "right") {
            return `M ${w} 0 A ${rf} ${rf} 0 0 1 ${w - rf} ${rf} L ${rc} ${rf} A ${rc} ${rc} 0 0 0 0 ${rf + rc} L 0 ${h - (rf + rc)} A ${rc} ${rc} 0 0 0 ${rc} ${h - rf} L ${w - rf} ${h - rf} A ${rf} ${rf} 0 0 1 ${w} ${h}`
        }
        return ""
    }

    Rectangle {
        id: pill
        anchors.top: parent.top
        anchors.right: parent.right
        height: root.vertical ? (verticalCol.implicitHeight + (root.attachedEdge !== "" ? 28 : (root.showBackground ? 16 : 8))) : 38
        width: root.vertical ? (root.attachedEdge !== "" ? 34 : 38) : (contentRow.implicitWidth + (root.showBackground ? 20 : 8))
        radius: root.attachedEdge !== "" ? 0 : 19
        color: (root.attachedEdge === "" && root.showBackground) ? Theme.bg : "transparent"
        border.color: (root.attachedEdge === "" && root.showBackground) ? Theme.outline : "transparent"
        border.width: (root.attachedEdge === "" && root.showBackground) ? 1 : 0

        Shape {
            id: notchShape
            visible: root.attachedEdge !== ""
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            asynchronous: false
            layer.enabled: true
            layer.smooth: true

            ShapePath {
                strokeWidth: 0
                strokeColor: "transparent"
                fillColor: root.showBackground ? Theme.bg : "transparent"

                PathSvg {
                    path: root.notchFillPath
                }
            }

            ShapePath {
                strokeWidth: root.showBackground ? 1 : 0
                strokeColor: root.showBackground ? Theme.outline : "transparent"
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin

                PathSvg {
                    path: root.notchStrokePath
                }
            }
        }

        RowLayout {
            id: contentRow
            visible: !root.vertical
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 8
            spacing: 7

            /* ── System Tray (Windows-style Up Arrow) ─────────────────── */
            Item {
                id: trayBadge
                Layout.preferredWidth: 22
                Layout.preferredHeight: 22
                Layout.alignment: Qt.AlignVCenter
                visible: true
                readonly property bool isHovered: trayMouse.containsMouse

                scale: isHovered ? 1.15 : 1.0
                Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }

                Rectangle {
                    anchors.fill: parent
                    radius: 6
                    color: trayBadge.isHovered ? Theme.bgHover : "transparent"
                    border.color: trayBadge.isHovered ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.4) : "transparent"
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                }

                Text {
                    anchors.centerIn: parent
                    text: "keyboard_arrow_up"
                    font.family: Theme.fontIcon
                    font.pixelSize: 18
                    color: trayBadge.isHovered ? Theme.accent : Theme.fg
                }

                MouseArea {
                    id: trayMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: root.openTray()
                    onExited: root.closeTray()
                    onClicked: root.toggleTray()
                }
            }

            /* Divider after tray */
            Rectangle {
                Layout.preferredWidth: 1
                Layout.preferredHeight: 14
                Layout.alignment: Qt.AlignVCenter
                color: "#25FFFFFF"
                visible: true
            }

            /* ── Battery Button (Hover/Click to open battery popup) ────── */
            Item {
                id: batBadge
                Layout.preferredWidth: 26
                Layout.preferredHeight: 26
                Layout.alignment: Qt.AlignVCenter
                visible: root.hasBattery

                readonly property bool isHovered: batMouse.containsMouse

                scale: isHovered ? 1.18 : 1.0
                y: isHovered ? -2 : 0
                Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }
                Behavior on y { NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }

                // Ambient glowing halo morphing into unique Gem shape
                MaterialShape {
                    anchors.centerIn: parent
                    width: parent.width + 8
                    height: parent.height + 8
                    shape: batBadge.isHovered ? MaterialShape.Gem : MaterialShape.Circle
                    animationDuration: 260
                    animationEasing: Easing.OutBack
                    color: batBadge.isHovered ? (root.isCharging ? Qt.rgba(Theme.accentLit.r, Theme.accentLit.g, Theme.accentLit.b, 0.25) : Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.25)) : "transparent"
                    scale: batBadge.isHovered ? 1.12 : 0.6
                    opacity: batBadge.isHovered ? 1.0 : 0.0
                    rotation: batBadge.isHovered ? 8 : 0
                    Behavior on opacity { NumberAnimation { duration: 180 } }
                    Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutBack } }
                    Behavior on rotation { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
                }

                // Tactile highlight chip morphing into unique Gem shape
                MaterialShape {
                    anchors.fill: parent
                    shape: batBadge.isHovered ? MaterialShape.Gem : MaterialShape.Circle
                    animationDuration: 260
                    animationEasing: Easing.OutBack
                    color: batBadge.isHovered ? Theme.bgHover : "transparent"
                    strokeColor: batBadge.isHovered ? (root.isCharging ? Qt.rgba(Theme.accentLit.r, Theme.accentLit.g, Theme.accentLit.b, 0.45) : Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.40)) : "transparent"
                    strokeWidth: 1.2
                    rotation: batBadge.isHovered ? 8 : 0
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Behavior on strokeColor { ColorAnimation { duration: 120 } }
                    Behavior on rotation { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
                }

                Text {
                    anchors.centerIn: parent
                    text: root.batteryGlyph
                    font.family: Theme.fontIcon
                    font.pixelSize: 15
                    color: root.isCharging ? Theme.accentLit : (root.batteryPct < 0.2 ? Theme.err : (batBadge.isHovered ? Theme.accent : Theme.fg))
                    scale: batBadge.isHovered ? 1.12 : 1.0
                    Behavior on scale { NumberAnimation { duration: Theme.motionDurationShort3; easing.type: Theme.easingEmphasized } }
                }

                MouseArea {
                    id: batMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleBattery()
                }
            }

            /* ── Sound Icon (Hover/Click to open volume & mic popup) ───── */
            Item {
                id: volBadge
                Layout.preferredWidth: 26
                Layout.preferredHeight: 26
                Layout.alignment: Qt.AlignVCenter

                readonly property bool isHovered: volMouse.containsMouse

                scale: isHovered ? 1.18 : 1.0
                y: isHovered ? -2 : 0
                Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }
                Behavior on y { NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }

                // Ambient glowing halo morphing into unique Flower shape
                MaterialShape {
                    anchors.centerIn: parent
                    width: parent.width + 8
                    height: parent.height + 8
                    shape: volBadge.isHovered ? MaterialShape.Flower : MaterialShape.Circle
                    animationDuration: 260
                    animationEasing: Easing.OutBack
                    color: volBadge.isHovered ? (root.muted ? Qt.rgba(Theme.err.r, Theme.err.g, Theme.err.b, 0.25) : Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.25)) : "transparent"
                    scale: volBadge.isHovered ? 1.12 : 0.6
                    opacity: volBadge.isHovered ? 1.0 : 0.0
                    rotation: volBadge.isHovered ? -4 : 0
                    Behavior on opacity { NumberAnimation { duration: 180 } }
                    Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutBack } }
                    Behavior on rotation { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
                }

                // Tactile highlight chip morphing into unique Flower shape
                MaterialShape {
                    anchors.fill: parent
                    shape: volBadge.isHovered ? MaterialShape.Flower : MaterialShape.Circle
                    animationDuration: 260
                    animationEasing: Easing.OutBack
                    color: volBadge.isHovered ? Theme.bgHover : "transparent"
                    strokeColor: volBadge.isHovered ? (root.muted ? Qt.rgba(Theme.err.r, Theme.err.g, Theme.err.b, 0.45) : Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35)) : "transparent"
                    strokeWidth: 1.2
                    rotation: volBadge.isHovered ? -4 : 0
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Behavior on strokeColor { ColorAnimation { duration: 120 } }
                    Behavior on rotation { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
                }

                Text {
                    anchors.centerIn: parent
                    text: root.volumeGlyph
                    font.family: Theme.fontIcon
                    font.pixelSize: 15
                    color: root.muted ? Theme.err : (volBadge.isHovered ? Theme.accent : Theme.fg)
                    scale: volBadge.isHovered ? 1.12 : 1.0
                    Behavior on scale { NumberAnimation { duration: Theme.motionDurationShort3; easing.type: Theme.easingEmphasized } }
                }

                MouseArea {
                    id: volMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleMixer()
                }
            }

            /* ── Display Brightness Icon (Hover/Click to open brightness) ─ */
            Item {
                id: brightBadge
                Layout.preferredWidth: 26
                Layout.preferredHeight: 26
                Layout.alignment: Qt.AlignVCenter

                readonly property bool isHovered: brightMouse.containsMouse

                scale: isHovered ? 1.18 : 1.0
                y: isHovered ? -2 : 0
                Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }
                Behavior on y { NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }

                // Ambient glowing halo morphing into unique Sunny shape
                MaterialShape {
                    anchors.centerIn: parent
                    width: parent.width + 8
                    height: parent.height + 8
                    shape: brightBadge.isHovered ? MaterialShape.Sunny : MaterialShape.Circle
                    animationDuration: 260
                    animationEasing: Easing.OutBack
                    color: brightBadge.isHovered ? Qt.rgba(Theme.accentLit.r, Theme.accentLit.g, Theme.accentLit.b, 0.25) : "transparent"
                    scale: brightBadge.isHovered ? 1.12 : 0.6
                    opacity: brightBadge.isHovered ? 1.0 : 0.0
                    rotation: brightBadge.isHovered ? 15 : 0
                    Behavior on opacity { NumberAnimation { duration: 180 } }
                    Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutBack } }
                    Behavior on rotation { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
                }

                // Tactile highlight chip morphing into unique Sunny shape
                MaterialShape {
                    anchors.fill: parent
                    shape: brightBadge.isHovered ? MaterialShape.Sunny : MaterialShape.Circle
                    animationDuration: 260
                    animationEasing: Easing.OutBack
                    color: brightBadge.isHovered ? Theme.bgHover : "transparent"
                    strokeColor: brightBadge.isHovered ? Qt.rgba(Theme.accentLit.r, Theme.accentLit.g, Theme.accentLit.b, 0.45) : "transparent"
                    strokeWidth: 1.2
                    rotation: brightBadge.isHovered ? 15 : 0
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Behavior on strokeColor { ColorAnimation { duration: 120 } }
                    Behavior on rotation { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
                }

                Text {
                    anchors.centerIn: parent
                    text: "light_mode"
                    font.family: Theme.fontIcon
                    font.pixelSize: 15
                    color: brightBadge.isHovered ? Theme.accentLit : Theme.fg
                    scale: brightBadge.isHovered ? 1.12 : 1.0
                    rotation: brightBadge.isHovered ? 25 : 0
                    Behavior on scale { NumberAnimation { duration: Theme.motionDurationShort3; easing.type: Theme.easingEmphasized } }
                    Behavior on rotation { NumberAnimation { duration: Theme.motionDurationMedium2; easing.type: Theme.easingEmphasized } }
                }

                MouseArea {
                    id: brightMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleBrightness()
                }
            }

            /* Divider */
            Rectangle {
                Layout.preferredWidth: 1
                Layout.preferredHeight: 14
                Layout.alignment: Qt.AlignVCenter
                color: "#25FFFFFF"
            }

            /* ── Power Button (Opens native animated PowerMenu) ────────── */
            Item {
                id: pwrBadge
                Layout.preferredWidth: 26
                Layout.preferredHeight: 26
                Layout.alignment: Qt.AlignVCenter

                readonly property bool isHovered: pwrMouse.containsMouse

                scale: isHovered ? 1.18 : 1.0
                y: isHovered ? -2 : 0
                Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }
                Behavior on y { NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }

                // Ambient glowing halo morphing into unique SoftBurst energy shape
                MaterialShape {
                    anchors.centerIn: parent
                    width: parent.width + 8
                    height: parent.height + 8
                    shape: pwrBadge.isHovered ? MaterialShape.SoftBurst : MaterialShape.Circle
                    animationDuration: 260
                    animationEasing: Easing.OutBack
                    color: pwrBadge.isHovered ? Qt.rgba(Theme.err.r, Theme.err.g, Theme.err.b, 0.28) : "transparent"
                    scale: pwrBadge.isHovered ? 1.12 : 0.6
                    opacity: pwrBadge.isHovered ? 1.0 : 0.0
                    rotation: pwrBadge.isHovered ? 45 : 0
                    Behavior on opacity { NumberAnimation { duration: 180 } }
                    Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutBack } }
                    Behavior on rotation { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
                }

                // Tactile highlight chip morphing into unique SoftBurst energy shape
                MaterialShape {
                    anchors.fill: parent
                    shape: pwrBadge.isHovered ? MaterialShape.SoftBurst : MaterialShape.Circle
                    animationDuration: 260
                    animationEasing: Easing.OutBack
                    color: pwrBadge.isHovered ? Qt.alpha(Theme.err, 0.22) : "transparent"
                    strokeColor: pwrBadge.isHovered ? Qt.rgba(Theme.err.r, Theme.err.g, Theme.err.b, 0.45) : "transparent"
                    strokeWidth: 1.2
                    rotation: pwrBadge.isHovered ? 45 : 0
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Behavior on strokeColor { ColorAnimation { duration: 120 } }
                    Behavior on rotation { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
                }

                Text {
                    anchors.centerIn: parent
                    text: "power_settings_new"
                    font.family: Theme.fontIcon
                    font.pixelSize: 15
                    color: pwrBadge.isHovered ? Theme.err : Theme.fgDim
                    scale: pwrBadge.isHovered ? 1.12 : 1.0
                    Behavior on scale { NumberAnimation { duration: Theme.motionDurationShort3; easing.type: Theme.easingEmphasized } }
                }

                MouseArea {
                    id: pwrMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openPower()
                }
            }
        }

        /* ── Vertical Column for Dock / Edge Mode ─────────────── */
        ColumnLayout {
            id: verticalCol
            visible: root.vertical
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: root.attachedEdge !== "" ? 12 : (root.showBackground ? 8 : 4)
            spacing: 6

            /* System Tray (Vertical) */
            Item {
                Layout.preferredWidth: 26
                Layout.preferredHeight: 26
                Layout.alignment: Qt.AlignHCenter
                visible: true
                readonly property bool isHovered: trayMouseV.containsMouse

                Rectangle {
                    anchors.fill: parent
                    radius: 6
                    color: parent.isHovered ? Theme.bgHover : "transparent"
                    Behavior on color { ColorAnimation { duration: Motion.fast } }
                }

                Text {
                    anchors.centerIn: parent
                    text: "keyboard_arrow_up"
                    font.family: Theme.fontIcon
                    font.pixelSize: 18
                    color: parent.isHovered ? Theme.accent : Theme.fgDim
                }

                MouseArea {
                    id: trayMouseV
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: root.openTray()
                    onExited: root.closeTray()
                    onClicked: root.toggleTray()
                }
            }

            /* Battery */
            Item {
                Layout.preferredWidth: 26
                Layout.preferredHeight: 26
                Layout.alignment: Qt.AlignHCenter
                visible: root.hasBattery

                readonly property bool isHovered: batMouseV.containsMouse
                scale: isHovered ? 1.18 : 1.0
                x: isHovered ? -2 : 0
                Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }
                Behavior on x { NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }

                // Ambient glowing halo morphing into unique Gem shape
                MaterialShape {
                    anchors.centerIn: parent
                    width: parent.width + 8
                    height: parent.height + 8
                    shape: parent.isHovered ? MaterialShape.Gem : MaterialShape.Circle
                    animationDuration: 260
                    animationEasing: Easing.OutBack
                    color: parent.isHovered ? (root.isCharging ? Qt.rgba(Theme.accentLit.r, Theme.accentLit.g, Theme.accentLit.b, 0.25) : Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.25)) : "transparent"
                    scale: parent.isHovered ? 1.12 : 0.6
                    opacity: parent.isHovered ? 1.0 : 0.0
                    rotation: parent.isHovered ? 8 : 0
                    Behavior on opacity { NumberAnimation { duration: 180 } }
                    Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutBack } }
                    Behavior on rotation { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
                }

                // Tactile highlight chip morphing into unique Gem shape
                MaterialShape {
                    anchors.fill: parent
                    shape: parent.isHovered ? MaterialShape.Gem : MaterialShape.Circle
                    animationDuration: 260
                    animationEasing: Easing.OutBack
                    color: parent.isHovered ? Theme.bgHover : "transparent"
                    strokeColor: parent.isHovered ? (root.isCharging ? Qt.rgba(Theme.accentLit.r, Theme.accentLit.g, Theme.accentLit.b, 0.45) : Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.40)) : "transparent"
                    strokeWidth: 1.2
                    rotation: parent.isHovered ? 8 : 0
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Behavior on strokeColor { ColorAnimation { duration: 120 } }
                    Behavior on rotation { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
                }

                Text {
                    anchors.centerIn: parent
                    text: root.batteryGlyph
                    font.family: Theme.fontIcon
                    font.pixelSize: 15
                    color: root.isCharging ? Theme.accentLit : (root.batteryPct < 0.2 ? Theme.err : (parent.isHovered ? Theme.accent : Theme.fg))
                    scale: parent.isHovered ? 1.12 : 1.0
                    Behavior on scale { NumberAnimation { duration: Theme.motionDurationShort3; easing.type: Theme.easingEmphasized } }
                }

                MouseArea {
                    id: batMouseV
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleBattery()
                }
            }

            /* Sound */
            Item {
                Layout.preferredWidth: 26
                Layout.preferredHeight: 26
                Layout.alignment: Qt.AlignHCenter

                readonly property bool isHovered: volMouseV.containsMouse
                scale: isHovered ? 1.18 : 1.0
                x: isHovered ? -2 : 0
                Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }
                Behavior on x { NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }

                // Ambient glowing halo morphing into unique Flower shape
                MaterialShape {
                    anchors.centerIn: parent
                    width: parent.width + 8
                    height: parent.height + 8
                    shape: parent.isHovered ? MaterialShape.Flower : MaterialShape.Circle
                    animationDuration: 260
                    animationEasing: Easing.OutBack
                    color: parent.isHovered ? (root.muted ? Qt.rgba(Theme.err.r, Theme.err.g, Theme.err.b, 0.25) : Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.25)) : "transparent"
                    scale: parent.isHovered ? 1.12 : 0.6
                    opacity: parent.isHovered ? 1.0 : 0.0
                    rotation: parent.isHovered ? -8 : 0
                    Behavior on opacity { NumberAnimation { duration: 180 } }
                    Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutBack } }
                    Behavior on rotation { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
                }

                // Tactile highlight chip morphing into unique Flower shape
                MaterialShape {
                    anchors.fill: parent
                    shape: parent.isHovered ? MaterialShape.Flower : MaterialShape.Circle
                    animationDuration: 260
                    animationEasing: Easing.OutBack
                    color: parent.isHovered ? Theme.bgHover : "transparent"
                    strokeColor: parent.isHovered ? (root.muted ? Qt.rgba(Theme.err.r, Theme.err.g, Theme.err.b, 0.45) : Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.40)) : "transparent"
                    strokeWidth: 1.2
                    rotation: parent.isHovered ? -8 : 0
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Behavior on strokeColor { ColorAnimation { duration: 120 } }
                    Behavior on rotation { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
                }

                Text {
                    anchors.centerIn: parent
                    text: root.volumeGlyph
                    font.family: Theme.fontIcon
                    font.pixelSize: 15
                    color: root.muted ? Theme.err : (parent.isHovered ? Theme.accent : Theme.fg)
                    scale: parent.isHovered ? 1.12 : 1.0
                    Behavior on scale { NumberAnimation { duration: Theme.motionDurationShort3; easing.type: Theme.easingEmphasized } }
                }

                MouseArea {
                    id: volMouseV
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleMixer()
                }
            }

            /* Brightness */
            Item {
                Layout.preferredWidth: 26
                Layout.preferredHeight: 26
                Layout.alignment: Qt.AlignHCenter

                readonly property bool isHovered: brightMouseV.containsMouse
                scale: isHovered ? 1.18 : 1.0
                x: isHovered ? -2 : 0
                Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }
                Behavior on x { NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }

                // Ambient glowing halo morphing into unique Sunny shape
                MaterialShape {
                    anchors.centerIn: parent
                    width: parent.width + 8
                    height: parent.height + 8
                    shape: parent.isHovered ? MaterialShape.Sunny : MaterialShape.Circle
                    animationDuration: 260
                    animationEasing: Easing.OutBack
                    color: parent.isHovered ? Qt.rgba(Theme.accentLit.r, Theme.accentLit.g, Theme.accentLit.b, 0.25) : "transparent"
                    scale: parent.isHovered ? 1.12 : 0.6
                    opacity: parent.isHovered ? 1.0 : 0.0
                    rotation: parent.isHovered ? 15 : 0
                    Behavior on opacity { NumberAnimation { duration: 180 } }
                    Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutBack } }
                    Behavior on rotation { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
                }

                // Tactile highlight chip morphing into unique Sunny shape
                MaterialShape {
                    anchors.fill: parent
                    shape: parent.isHovered ? MaterialShape.Sunny : MaterialShape.Circle
                    animationDuration: 260
                    animationEasing: Easing.OutBack
                    color: parent.isHovered ? Theme.bgHover : "transparent"
                    strokeColor: parent.isHovered ? Qt.rgba(Theme.accentLit.r, Theme.accentLit.g, Theme.accentLit.b, 0.45) : "transparent"
                    strokeWidth: 1.2
                    rotation: parent.isHovered ? 15 : 0
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Behavior on strokeColor { ColorAnimation { duration: 120 } }
                    Behavior on rotation { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
                }

                Text {
                    anchors.centerIn: parent
                    text: "light_mode"
                    font.family: Theme.fontIcon
                    font.pixelSize: 15
                    color: parent.isHovered ? Theme.accentLit : Theme.fg
                    scale: parent.isHovered ? 1.12 : 1.0
                    rotation: parent.isHovered ? 25 : 0
                    Behavior on scale { NumberAnimation { duration: Theme.motionDurationShort3; easing.type: Theme.easingEmphasized } }
                    Behavior on rotation { NumberAnimation { duration: Theme.motionDurationMedium2; easing.type: Theme.easingEmphasized } }
                }

                MouseArea {
                    id: brightMouseV
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleBrightness()
                }
            }

            /* Divider */
            Rectangle {
                Layout.preferredWidth: 16
                Layout.preferredHeight: 1
                Layout.alignment: Qt.AlignHCenter
                color: "#25FFFFFF"
            }

            /* Power */
            Item {
                Layout.preferredWidth: 26
                Layout.preferredHeight: 26
                Layout.alignment: Qt.AlignHCenter

                readonly property bool isHovered: pwrMouseV.containsMouse
                scale: isHovered ? 1.18 : 1.0
                x: isHovered ? -2 : 0
                Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }
                Behavior on x { NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }

                // Ambient glowing halo morphing into unique SoftBurst energy shape
                MaterialShape {
                    anchors.centerIn: parent
                    width: parent.width + 8
                    height: parent.height + 8
                    shape: parent.isHovered ? MaterialShape.SoftBurst : MaterialShape.Circle
                    animationDuration: 260
                    animationEasing: Easing.OutBack
                    color: parent.isHovered ? Qt.rgba(Theme.err.r, Theme.err.g, Theme.err.b, 0.28) : "transparent"
                    scale: parent.isHovered ? 1.12 : 0.6
                    opacity: parent.isHovered ? 1.0 : 0.0
                    rotation: parent.isHovered ? 45 : 0
                    Behavior on opacity { NumberAnimation { duration: 180 } }
                    Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutBack } }
                    Behavior on rotation { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
                }

                // Tactile highlight chip morphing into unique SoftBurst energy shape
                MaterialShape {
                    anchors.fill: parent
                    shape: parent.isHovered ? MaterialShape.SoftBurst : MaterialShape.Circle
                    animationDuration: 260
                    animationEasing: Easing.OutBack
                    color: parent.isHovered ? Qt.alpha(Theme.err, 0.22) : "transparent"
                    strokeColor: parent.isHovered ? Qt.rgba(Theme.err.r, Theme.err.g, Theme.err.b, 0.45) : "transparent"
                    strokeWidth: 1.2
                    rotation: parent.isHovered ? 45 : 0
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Behavior on strokeColor { ColorAnimation { duration: 120 } }
                    Behavior on rotation { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
                }

                Text {
                    anchors.centerIn: parent
                    text: "power_settings_new"
                    font.family: Theme.fontIcon
                    font.pixelSize: 15
                    color: parent.isHovered ? Theme.err : Theme.fgDim
                    scale: parent.isHovered ? 1.12 : 1.0
                    Behavior on scale { NumberAnimation { duration: Theme.motionDurationShort3; easing.type: Theme.easingEmphasized } }
                }

                MouseArea {
                    id: pwrMouseV
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openPower()
                }
            }
        }
    }
}
