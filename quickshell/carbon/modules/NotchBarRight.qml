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
    signal openNotif()
    signal closeNotif()
    signal toggleNotif()
    signal toggleControls()
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
        /* 0. System Telemetry Badge (CPU & RAM) - Simple outline on hover */
        Item {
            id: telemetryBadge
            implicitWidth: telemRow.implicitWidth + 8
            implicitHeight: 24
            anchors.verticalCenter: parent.verticalCenter
            readonly property bool isHovered: telemMouse.containsMouse

            Rectangle {
                anchors.fill: parent
                radius: 6
                color: "transparent"
                border.color: telemetryBadge.isHovered ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.45) : "transparent"
                border.width: 1
                Behavior on border.color { ColorAnimation { duration: 120 } }
            }

            Row {
                id: telemRow
                spacing: 6
                anchors.centerIn: parent

                Rectangle {
                    width: 7
                    height: 7
                    radius: 3.5
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.cpuUsage > 75 || root.ramPct > 85 ? Theme.warn : Theme.accent
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
        /* 0. System Tray Overflow: Windows-style Up Arrow (Chevron) - Simple outline on hover */
        Item {
            id: trayBadge
            width: 22
            height: 22
            anchors.verticalCenter: parent.verticalCenter
            visible: true
            readonly property bool isHovered: trayMouse.containsMouse

            Rectangle {
                anchors.fill: parent
                radius: 6
                color: "transparent"
                border.color: trayBadge.isHovered ? Theme.accent : "transparent"
                border.width: 1
                Behavior on border.color { ColorAnimation { duration: 120 } }
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

        /* 7. Notification Bell Badge */
        Item {
            id: notifBadge
            width: root.notifCount > 0 ? (notifRow.implicitWidth + 12) : 22
            height: 22
            anchors.verticalCenter: parent.verticalCenter
            readonly property bool isHovered: notifMouse.containsMouse

            Rectangle {
                anchors.fill: parent
                radius: 6
                color: "transparent"
                border.color: notifBadge.isHovered ? Theme.accent : (root.notifCount > 0 ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35) : "transparent")
                border.width: 1
                Behavior on border.color { ColorAnimation { duration: 120 } }
            }

            RowLayout {
                id: notifRow
                anchors.centerIn: parent
                spacing: 3

                Text {
                    text: root.notifCount > 0 ? "notifications_active" : "notifications"
                    font.family: Theme.fontIcon
                    font.pixelSize: 15
                    color: root.notifCount > 0 ? Theme.accentLit : (notifBadge.isHovered ? Theme.accent : Theme.fg)
                }

                Text {
                    visible: root.notifCount > 0
                    text: String(root.notifCount)
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: Theme.fontPx(7.5)
                    font.weight: Font.Bold
                    color: Theme.accentLit
                }
            }

            MouseArea {
                id: notifMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleNotif()
            }
        },

        /* Divider after notifications */
        Rectangle {
            width: 1
            height: 14
            anchors.verticalCenter: parent.verticalCenter
            color: Qt.alpha(Theme.fg, 0.15)
            visible: true
        },

        /* 8. Control Center Button (Simple clean outline on hover) */
        Item {
            id: controlsBadge
            width: 24
            height: 24
            anchors.verticalCenter: parent.verticalCenter
            readonly property bool isHovered: controlsMouse.containsMouse

            Rectangle {
                anchors.fill: parent
                radius: 6
                color: "transparent"
                border.color: controlsBadge.isHovered ? Theme.accent : "transparent"
                border.width: 1
                Behavior on border.color { ColorAnimation { duration: 120 } }
            }

            Text {
                anchors.centerIn: parent
                text: "tune"
                font.family: Theme.fontIcon
                font.pixelSize: 15
                color: controlsBadge.isHovered ? Theme.accentLit : Theme.fg
            }

            MouseArea {
                id: controlsMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleControls()
            }
        },

        /* Divider after controls */
        Rectangle {
            width: 1
            height: 14
            anchors.verticalCenter: parent.verticalCenter
            color: Qt.alpha(Theme.fg, 0.15)
            visible: true
        },

        /* 9. Power Menu Button (Simple clean outline on hover) */
        Item {
            id: pwrBadge
            width: 24
            height: 24
            anchors.verticalCenter: parent.verticalCenter
            readonly property bool isHovered: pwrMouse.containsMouse

            Rectangle {
                anchors.fill: parent
                radius: 6
                color: "transparent"
                border.color: pwrBadge.isHovered ? Theme.err : "transparent"
                border.width: 1
                Behavior on border.color { ColorAnimation { duration: 120 } }
            }

            Text {
                anchors.centerIn: parent
                text: "power_settings_new"
                font.family: Theme.fontIcon
                font.pixelSize: 15
                color: pwrBadge.isHovered ? Theme.err : Theme.fgDim
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
