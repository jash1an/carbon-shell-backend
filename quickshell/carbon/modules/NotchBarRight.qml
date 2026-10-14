import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Quickshell.Services.SystemTray
import M3Shapes
import "../Singletons"
import "../components"

/**
 * NotchBarRight: Top-attached curved notch for Right side
 *   - Control/Mixer button
 *   - Distro/VC status badge
 *   - Weather badge (cloud icon + temp)
 *   - Volume badge (speaker icon + %)
 *   - Wi-Fi and Bluetooth status indicators
 *   - Notification Bell with unread badge counter
 *   - Battery icon with hover trigger for Caelestia wavy popup
 *   - Power menu button
 */
NotchContainer {
    id: root

    implicitHeight: 34
    earWidth: 20
    contentSpacing: 7

    property int notifCount: 0
    implicitWidth: contentImplicitWidth + (leftFillet ? filletRadius : 0) + (horizontalPadding * 2)

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
    signal openPower()

    /* ── Audio Sink State ────────────────────────────────────────────── */
    readonly property var audioSink: Pipewire.defaultAudioSink
    readonly property real volume: audioSink && audioSink.audio ? audioSink.audio.volume : 0.0
    readonly property bool muted: audioSink && audioSink.audio ? audioSink.audio.muted : false
    readonly property int volumePct: Math.round(root.volume * 100)

    readonly property string volumeGlyph: {
        if (root.muted) return "volume_off"
        if (root.volume > 0.5) return "volume_up"
        if (root.volume > 0.0) return "volume_down"
        return "volume_mute"
    }

    /* ── Battery State ───────────────────────────────────────────────── */
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
    /* ── System Telemetry (CPU & RAM) ────────────────────────────────── */
    property int cpuUsage: 0
    property string ramUsageGB: "0.0"
    property int ramPct: 0
    property real lastCpuTotal: 0
    property real lastCpuIdle: 0

    Process {
        id: sysProbe
        command: ["awk", "/^cpu / {print $2+$3+$4+$5+$6+$7+$8, $5+$6} /^MemTotal:/ {tot=$2} /^MemAvailable:/ {avail=$2} END {print tot, avail}", "/proc/stat", "/proc/meminfo"]
        running: false
        stdout: StdioCollector {
            id: sysOut
            waitForEnd: true
        }
        onExited: {
            var raw = sysOut.text.trim().split("\n")
            if (raw.length >= 2) {
                var cpuParts = raw[0].trim().split(/\s+/)
                if (cpuParts.length >= 2) {
                    var total = parseFloat(cpuParts[0])
                    var idle = parseFloat(cpuParts[1])
                    if (root.lastCpuTotal > 0 && total > root.lastCpuTotal) {
                        var dTotal = total - root.lastCpuTotal
                        var dIdle = idle - root.lastCpuIdle
                        root.cpuUsage = Math.max(0, Math.min(100, Math.round((1.0 - (dIdle / dTotal)) * 100)))
                    }
                    root.lastCpuTotal = total
                    root.lastCpuIdle = idle
                }

                var memParts = raw[1].trim().split(/\s+/)
                if (memParts.length >= 2) {
                    var totKb = parseFloat(memParts[0])
                    var availKb = parseFloat(memParts[1])
                    if (totKb > 0) {
                        var usedKb = Math.max(0, totKb - availKb)
                        root.ramUsageGB = (usedKb / (1024 * 1024)).toFixed(1)
                        root.ramPct = Math.round((usedKb / totKb) * 100)
                    }
                }
            }
        }
    }

    Timer {
        id: sysTimer
        interval: 2000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: sysProbe.running = true
    }

    /* ── System Tray for Background App Mini Icons ──────────────────── */
    readonly property var trayItems: SystemTray.items.values.filter(function (it) {
        var key = ((it.id || "") + " " + (it.title || "") + " " + (it.tooltipTitle || "")).toLowerCase()
        return !/(nm[ _-]?applet|blueman)/.test(key)
    })

    /* ── Content Inside Notch ────────────────────────────────────────── */
    content: [
        /* 0. System Telemetry Badge (CPU & RAM) - Mirrors Left Bar Desktop Badge */
        Item {
            id: telemetryBadge
            implicitWidth: telemRow.implicitWidth
            implicitHeight: 24
            anchors.verticalCenter: parent.verticalCenter
            readonly property bool isHovered: telemMouse.containsMouse

            scale: isHovered ? 1.05 : 1.0
            Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }

            Row {
                id: telemRow
                spacing: 6
                anchors.verticalCenter: parent.verticalCenter

                MaterialShape {
                    width: 15
                    height: 15
                    anchors.verticalCenter: parent.verticalCenter
                    shape: telemetryBadge.isHovered ? MaterialShape.Diamond : MaterialShape.Gem
                    animationDuration: 280
                    animationEasing: Easing.OutBack
                    color: root.cpuUsage > 75 || root.ramPct > 85 ? Theme.warn : Theme.accent
                    rotation: telemetryBadge.isHovered ? 45 : 0
                    Behavior on rotation { NumberAnimation { duration: 280; easing.type: Easing.OutBack } }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0

                    Row {
                        spacing: 3
                        Text {
                            text: "CPU"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: Theme.fontPx(8)
                            font.weight: Font.Medium
                            color: Theme.fgFaint
                        }
                        Text {
                            text: root.cpuUsage + "%"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: Theme.fontPx(8)
                            font.weight: Font.Bold
                            color: root.cpuUsage > 80 ? Theme.err : (root.cpuUsage > 50 ? Theme.warn : Theme.fgDim)
                        }
                    }

                    Row {
                        spacing: 3
                        Text {
                            text: "RAM"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: Theme.fontPx(10)
                            font.weight: Font.Bold
                            color: Theme.fg
                        }
                        Text {
                            text: root.ramUsageGB + "G"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: Theme.fontPx(10)
                            font.weight: Font.Bold
                            color: root.ramPct > 85 ? Theme.warn : Theme.accent
                        }
                    }
                }
            }

            MouseArea {
                id: telemMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    Quickshell.execDetached(["sh", "-c", "kitty -e btop || foot -e btop || btop"])
                }
            }
        },

        /* Divider after Telemetry */
        Rectangle {
            width: 1
            height: 14
            anchors.verticalCenter: parent.verticalCenter
            color: Qt.alpha(Theme.fg, 0.18)
        },
        /* 0. System Tray Overflow: Windows-style Up Arrow (Chevron) */
        Item {
            id: trayBadge
            width: 22
            height: 22
            anchors.verticalCenter: parent.verticalCenter
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
                onClicked: root.toggleTray()
            }
        },

        /* Divider after tray */
        Rectangle {
            width: 1
            height: 14
            anchors.verticalCenter: parent.verticalCenter
            color: Qt.alpha(Theme.fg, 0.15)
            visible: true
        },




        /* 8. Battery Pill Icon */
        Item {
            id: batBadge
            width: 24
            height: 20
            anchors.verticalCenter: parent.verticalCenter
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
        },

        /* 9. Power Menu Button */
        Item {
            id: pwrBadge
            width: 24
            height: 24
            anchors.verticalCenter: parent.verticalCenter
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
    ]
}
