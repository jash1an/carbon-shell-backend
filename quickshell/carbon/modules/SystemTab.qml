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

    // Telemetry properties
    property string osName: "Arch Linux (x86_64)"
    property string kernelVer: ""
    property string uptimeStr: ""
    property string cpuModel: ""
    property string memStr: ""
    property string hyprVer: "Hyprland 0.57.0"

    // Startup apps
    property var startupApps: []
    property string newAppName: ""
    property string newAppCmd: ""

    readonly property string startupScript: (Quickshell.env("HOME") || "") + "/.config/carbon/scripts/carbon-startup-apply.py"

    FileView {
        id: startupJsonFile
        path: (Quickshell.env("HOME") || "") + "/.config/carbon/carbon-startup-apps.json"
        watchChanges: true
        blockLoading: true
        printErrors: false
        onLoaded: root.loadStartupApps()
        onFileChanged: {
            reload()
            root.loadStartupApps()
        }
    }

    function loadStartupApps() {
        try {
            var txt = startupJsonFile.text().trim()
            if (txt.length > 0) {
                var d = JSON.parse(txt)
                if (Array.isArray(d)) {
                    root.startupApps = d
                }
            }
        } catch (e) {}
    }

    Process {
        id: telemetryProc
        command: [
            "bash", "-c",
            "uname -r; uptime -p 2>/dev/null || uptime; grep -m 1 'model name' /proc/cpuinfo | cut -d: -f2; free -h | awk '/^Mem:/ {print $3 \" / \" $2}'; hyprctl version | head -n 1"
        ]
        stdout: StdioCollector {
            id: telemCollector
            waitForEnd: true
        }
        onExited: {
            var lines = telemCollector.text.trim().split("\n")
            if (lines.length > 0) root.kernelVer = lines[0].trim()
            if (lines.length > 1) root.uptimeStr = lines[1].replace(/^up\s+/, "").trim()
            if (lines.length > 2) root.cpuModel = lines[2].trim()
            if (lines.length > 3) root.memStr = lines[3].trim()
            if (lines.length > 4) root.hyprVer = lines[4].trim()
        }
    }

    function refreshTelemetry() {
        if (!telemetryProc.running) telemetryProc.running = true
    }

    function toggleApp(idx) {
        Quickshell.execDetached([root.startupScript, "toggle", String(idx)])
    }

    function removeApp(idx) {
        Quickshell.execDetached([root.startupScript, "remove", String(idx)])
    }

    function addApp() {
        if (root.newAppName.trim().length === 0 || root.newAppCmd.trim().length === 0) return
        Quickshell.execDetached([root.startupScript, "add", root.newAppName.trim(), root.newAppCmd.trim()])
        root.newAppName = ""
        root.newAppCmd = ""
    }

    Component.onCompleted: {
        root.loadStartupApps()
        root.refreshTelemetry()
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ===================================================================
        // LEFT COLUMN: SYSTEM TELEMETRY & HARDWARE
        // ===================================================================
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredWidth: 380

            Flickable {
                anchors.fill: parent
                contentWidth: width
                contentHeight: telemCol.implicitHeight + 40
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: telemCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 20
                    spacing: 14

                    // Header
                    RowLayout {
                        Layout.fillWidth: true

                        Text {
                            text: "SYSTEM TELEMETRY"
                            font.family: Theme.font
                            font.pixelSize: Theme.fontPx(11)
                            font.weight: Font.Bold
                            color: Qt.rgba(1, 1, 1, 0.45)
                            Layout.fillWidth: true
                        }

                        Rectangle {
                            Layout.preferredWidth: 24
                            Layout.preferredHeight: 24
                            radius: 6
                            color: refMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: "󰑐"
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fontPx(13)
                                color: Theme.primary
                            }

                            MouseArea {
                                id: refMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: root.describe("Refresh Telemetry", "Query live system uptime, CPU info, and memory utilization.")
                                onExited: root.clearDesc()
                                ToolTip.visible: containsMouse
                                ToolTip.text: "Refresh system telemetry"
                                ToolTip.delay: 300
                                onClicked: root.refreshTelemetry()
                            }
                        }
                    }

                    // Telemetry Spec Cards
                    Repeater {
                        model: [
                            { label: "OPERATING SYSTEM", val: root.osName, glyph: "󰣇", desc: "Active Linux distribution and CPU architecture." },
                            { label: "COMPOSITOR", val: root.hyprVer, glyph: "󱐋", desc: "Wayland compositor and build release version." },
                            { label: "LINUX KERNEL", val: root.kernelVer || "Linux x86_64", glyph: "󰌽", desc: "Active running Linux kernel release." },
                            { label: "SYSTEM UPTIME", val: root.uptimeStr || "Active", glyph: "󱑂", desc: "Elapsed operating time since host powered on." },
                            { label: "PROCESSOR", val: root.cpuModel || "x86_64 CPU", glyph: "󰘚", desc: "Host CPU processor model and thread architecture." },
                            { label: "MEMORY (RAM)", val: root.memStr || "Dynamic", glyph: "󰍛", desc: "Active utilized memory out of total physical RAM." }
                        ]

                        delegate: Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 48
                            radius: 8
                            color: telemCardMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.04) : Qt.rgba(0, 0, 0, 0.25)
                            border.color: Qt.rgba(1, 1, 1, 0.08)
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 12

                                Text {
                                    text: modelData.glyph
                                    font.family: Theme.fontMono
                                    font.pixelSize: Theme.fontPx(16)
                                    color: Theme.primary
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1

                                    Text {
                                        text: modelData.label
                                        font.family: Theme.fontMono
                                        font.pixelSize: Theme.fontPx(9)
                                        font.weight: Font.Bold
                                        color: Qt.rgba(1, 1, 1, 0.40)
                                    }

                                    Text {
                                        text: modelData.val
                                        font.family: Theme.font
                                        font.pixelSize: Theme.fontPx(11.5)
                                        color: Qt.rgba(1, 1, 1, 0.85)
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }
                            }

                            MouseArea {
                                id: telemCardMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.NoButton
                                onEntered: root.describe(modelData.label, modelData.desc)
                                onExited: root.clearDesc()
                                ToolTip.visible: containsMouse
                                ToolTip.text: modelData.desc
                                ToolTip.delay: 300
                            }
                        }
                    }

                    // Hairline Divider
                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Qt.rgba(1, 1, 1, 0.08)
                    }

                    // Header: Environment & Session Controls
                    Text {
                        text: "SESSION & PROCESS CONTROLS"
                        font.family: Theme.font
                        font.pixelSize: Theme.fontPx(11)
                        font.weight: Font.Bold
                        color: Qt.rgba(1, 1, 1, 0.45)
                    }

                    // Card 1: Hyprland Controls
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 84
                        radius: 8
                        color: Qt.rgba(0, 0, 0, 0.25)
                        border.color: Qt.rgba(1, 1, 1, 0.08)
                        border.width: 1

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 8

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                Text {
                                    text: "󱐋"
                                    font.family: Theme.fontMono
                                    font.pixelSize: Theme.fontPx(16)
                                    color: Theme.primary
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1

                                    Text {
                                        text: "Hyprland Compositor"
                                        font.family: Theme.font
                                        font.pixelSize: Theme.fontPx(12.5)
                                        font.weight: Font.DemiBold
                                        color: Qt.rgba(1, 1, 1, 0.90)
                                    }

                                    Text {
                                        text: "Wayland display server and window manager"
                                        font.family: Theme.font
                                        font.pixelSize: Theme.fontPx(10)
                                        color: Qt.rgba(1, 1, 1, 0.40)
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                // Reload Button
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 28
                                    radius: 6
                                    color: reloadHyprMouse.pressed ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.25) : (reloadHyprMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.04))
                                    border.color: reloadHyprMouse.containsMouse ? Theme.primary : Qt.rgba(1, 1, 1, 0.10)
                                    border.width: 1

                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 6
                                        Text { text: "󰑐"; font.family: Theme.fontMono; font.pixelSize: Theme.fontPx(11); color: Theme.primary }
                                        Text { text: "Reload Hyprland"; font.family: Theme.font; font.pixelSize: Theme.fontPx(11); font.weight: Font.Medium; color: Qt.rgba(1, 1, 1, 0.90) }
                                    }

                                    MouseArea {
                                        id: reloadHyprMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onEntered: root.describe("Reload Hyprland", "Live re-parse Hyprland config files, window rules, animations, and monitor profiles.")
                                        onExited: root.clearDesc()
                                        ToolTip.visible: containsMouse
                                        ToolTip.text: "Reload Hyprland configuration"
                                        ToolTip.delay: 300
                                        onClicked: {
                                            Quickshell.execDetached(["hyprctl", "reload"])
                                            root.describe("Hyprland", "hyprctl reload dispatched successfully.")
                                        }
                                    }
                                }

                                // Restart Button
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 28
                                    radius: 6
                                    color: restartHyprMouse.pressed ? Qt.rgba(1, 0.4, 0.4, 0.25) : (restartHyprMouse.containsMouse ? Qt.rgba(1, 0.4, 0.4, 0.12) : Qt.rgba(1, 1, 1, 0.04))
                                    border.color: restartHyprMouse.containsMouse ? "#ff6b6b" : Qt.rgba(1, 1, 1, 0.10)
                                    border.width: 1

                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 6
                                        Text { text: "󰑓"; font.family: Theme.fontMono; font.pixelSize: Theme.fontPx(11); color: "#ff6b6b" }
                                        Text { text: "Restart Hyprland"; font.family: Theme.font; font.pixelSize: Theme.fontPx(11); font.weight: Font.Medium; color: Qt.rgba(1, 1, 1, 0.90) }
                                    }

                                    MouseArea {
                                        id: restartHyprMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onEntered: root.describe("Restart Hyprland", "Exit current Hyprland compositor session and restart the display manager.")
                                        onExited: root.clearDesc()
                                        ToolTip.visible: containsMouse
                                        ToolTip.text: "Restart compositor session (dispatch exit)"
                                        ToolTip.delay: 300
                                        onClicked: {
                                            Quickshell.execDetached(["hyprctl", "dispatch", "exit"])
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Card 2: Carbon Shell Controls
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 84
                        radius: 8
                        color: Qt.rgba(0, 0, 0, 0.25)
                        border.color: Qt.rgba(1, 1, 1, 0.08)
                        border.width: 1

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 8

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                Text {
                                    text: "󱄄"
                                    font.family: Theme.fontMono
                                    font.pixelSize: Theme.fontPx(16)
                                    color: Theme.primary
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1

                                    Text {
                                        text: "Carbon Desktop Shell"
                                        font.family: Theme.font
                                        font.pixelSize: Theme.fontPx(12.5)
                                        font.weight: Font.DemiBold
                                        color: Qt.rgba(1, 1, 1, 0.90)
                                    }

                                    Text {
                                        text: "Quickshell desktop interface and dynamic widgets"
                                        font.family: Theme.font
                                        font.pixelSize: Theme.fontPx(10)
                                        color: Qt.rgba(1, 1, 1, 0.40)
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                // Reload Shell Button
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 28
                                    radius: 6
                                    color: reloadShellMouse.pressed ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.25) : (reloadShellMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.04))
                                    border.color: reloadShellMouse.containsMouse ? Theme.primary : Qt.rgba(1, 1, 1, 0.10)
                                    border.width: 1

                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 6
                                        Text { text: "󰑐"; font.family: Theme.fontMono; font.pixelSize: Theme.fontPx(11); color: Theme.primary }
                                        Text { text: "Reload Shell"; font.family: Theme.font; font.pixelSize: Theme.fontPx(11); font.weight: Font.Medium; color: Qt.rgba(1, 1, 1, 0.90) }
                                    }

                                    MouseArea {
                                        id: reloadShellMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onEntered: root.describe("Reload Shell", "Re-load Carbon Shell configs, themes, and dynamic QML components.")
                                        onExited: root.clearDesc()
                                        ToolTip.visible: containsMouse
                                        ToolTip.text: "Hot-reload Carbon Shell layout and configs"
                                        ToolTip.delay: 300
                                        onClicked: {
                                            Quickshell.execDetached(["sh", "-c", "/usr/bin/quickshell ipc --any-display -p " + ((Quickshell.env("HOME") || "") + "/.local/share/quickshell/carbon") + " call island reloadConfig 2>/dev/null || systemctl --user reload-or-restart carbon-quickshell.service"])
                                            root.describe("Carbon Shell", "Reload signal dispatched to desktop shell.")
                                        }
                                    }
                                }

                                // Restart Shell Button
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 28
                                    radius: 6
                                    color: restartShellMouse.pressed ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.25) : (restartShellMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.04))
                                    border.color: restartShellMouse.containsMouse ? Theme.primary : Qt.rgba(1, 1, 1, 0.10)
                                    border.width: 1

                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: 6
                                        Text { text: "󰑓"; font.family: Theme.fontMono; font.pixelSize: Theme.fontPx(11); color: Theme.primary }
                                        Text { text: "Restart Shell"; font.family: Theme.font; font.pixelSize: Theme.fontPx(11); font.weight: Font.Medium; color: Qt.rgba(1, 1, 1, 0.90) }
                                    }

                                    MouseArea {
                                        id: restartShellMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onEntered: root.describe("Restart Shell", "Full process restart of the Quickshell desktop environment service.")
                                        onExited: root.clearDesc()
                                        ToolTip.visible: containsMouse
                                        ToolTip.text: "Restart Quickshell desktop service"
                                        ToolTip.delay: 300
                                        onClicked: {
                                            Quickshell.execDetached(["sh", "-c", "systemctl --user restart carbon-quickshell.service 2>/dev/null || (pkill -9 quickshell; sleep 0.4; quickshell -p " + ((Quickshell.env("HOME") || "") + "/.local/share/quickshell/carbon") + " &)"])
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Section 3: Default Applications
                    Text {
                        text: "DEFAULT APPLICATIONS"
                        font.family: Theme.font
                        font.pixelSize: Theme.fontPx(11)
                        font.weight: Font.Bold
                        color: Qt.rgba(1, 1, 1, 0.45)
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 104
                        radius: 8
                        color: Qt.rgba(0, 0, 0, 0.25)
                        border.color: Qt.rgba(1, 1, 1, 0.08)
                        border.width: 1

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 8

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                Text {
                                    text: "󰀻"
                                    font.family: Theme.fontMono
                                    font.pixelSize: Theme.fontPx(16)
                                    color: Theme.primary
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1

                                    Text {
                                        text: "Default Application Handlers"
                                        font.family: Theme.font
                                        font.pixelSize: Theme.fontPx(12.5)
                                        font.weight: Font.DemiBold
                                        color: Qt.rgba(1, 1, 1, 0.90)
                                    }

                                    Text {
                                        text: "Browser: LibreWolf  •  Files: Files  •  Terminal: Kitty"
                                        font.family: Theme.font
                                        font.pixelSize: Theme.fontPx(10)
                                        color: Qt.rgba(1, 1, 1, 0.40)
                                    }
                                }
                            }

                            // Manage Defaults Button
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 28
                                radius: 6
                                color: defAppsMouse.pressed ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.25) : (defAppsMouse.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15) : Qt.rgba(1, 1, 1, 0.04))
                                border.color: defAppsMouse.containsMouse ? Theme.primary : Qt.rgba(1, 1, 1, 0.10)
                                border.width: 1

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 6
                                    Text { text: "󰀻"; font.family: Theme.fontMono; font.pixelSize: Theme.fontPx(11); color: Theme.primary }
                                    Text { text: "Configure Default Applications →"; font.family: Theme.font; font.pixelSize: Theme.fontPx(11); font.weight: Font.Medium; color: Qt.rgba(1, 1, 1, 0.90) }
                                }

                                MouseArea {
                                    id: defAppsMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onEntered: root.describe("Default Applications", "Configure default system applications for web browser, terminal, file manager, and editors.")
                                    onExited: root.clearDesc()
                                    ToolTip.visible: containsMouse
                                    ToolTip.text: "Open Default Applications tab"
                                    ToolTip.delay: 300
                                    onClicked: {
                                        if (root.hub) {
                                            root.hub.currentSection = "Default Apps"
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
        // RIGHT COLUMN: STARTUP APPLICATIONS
        // ===================================================================
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredWidth: 420

            Flickable {
                anchors.fill: parent
                contentWidth: width
                contentHeight: startupCol.implicitHeight + 40
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: startupCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 20
                    spacing: 14

                    // Header
                    Text {
                        text: "LOGIN STARTUP APPLICATIONS (AUTOSTART.CONF)"
                        font.family: Theme.font
                        font.pixelSize: Theme.fontPx(11)
                        font.weight: Font.Bold
                        color: Qt.rgba(1, 1, 1, 0.45)
                    }

                    // List of Apps
                    Repeater {
                        model: root.startupApps

                        delegate: Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 52
                            radius: 8
                            color: Qt.rgba(0, 0, 0, 0.25)
                            border.color: modelData.enabled ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.25) : Qt.rgba(1, 1, 1, 0.08)
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 10

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    Text {
                                        text: modelData.name || "Startup App"
                                        font.family: Theme.font
                                        font.pixelSize: Theme.fontPx(12.5)
                                        font.weight: Font.DemiBold
                                        color: modelData.enabled ? Qt.rgba(1, 1, 1, 0.90) : Qt.rgba(1, 1, 1, 0.50)
                                    }

                                    Text {
                                        text: modelData.command || ""
                                        font.family: Theme.fontMono
                                        font.pixelSize: Theme.fontPx(9.5)
                                        color: Qt.rgba(1, 1, 1, 0.40)
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }

                                // Status Badge Toggle
                                TerminalStatusBadge {
                                    checked: Boolean(modelData.enabled)
                                    interactive: false
                                    Layout.alignment: Qt.AlignRight
                                }

                                MouseArea {
                                    id: toggleMouse
                                    width: 50
                                    height: 30
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onEntered: root.describe("Startup: " + (modelData.name || "App"), "Toggle automatic launch on boot for " + (modelData.name || "this app") + ".")
                                    onExited: root.clearDesc()
                                    ToolTip.visible: containsMouse
                                    ToolTip.text: "Toggle autostart for " + (modelData.name || "app")
                                    ToolTip.delay: 300
                                    onClicked: root.toggleApp(index)
                                }

                                // Remove button
                                Rectangle {
                                    Layout.preferredWidth: 26
                                    Layout.preferredHeight: 26
                                    radius: 6
                                    color: delMouse.containsMouse ? Qt.rgba(1, 0.3, 0.3, 0.15) : "transparent"
                                    border.color: delMouse.containsMouse ? "#ff6b6b" : "transparent"
                                    border.width: 1

                                    Text {
                                        anchors.centerIn: parent
                                        text: "󰅖"
                                        font.family: Theme.fontMono
                                        font.pixelSize: Theme.fontPx(13)
                                        color: delMouse.containsMouse ? "#ff6b6b" : Qt.rgba(1, 1, 1, 0.40)
                                    }

                                    MouseArea {
                                        id: delMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onEntered: root.describe("Remove Startup App", "Remove " + (modelData.name || "app") + " from autostart configuration.")
                                        onExited: root.clearDesc()
                                        ToolTip.visible: containsMouse
                                        ToolTip.text: "Remove from autostart"
                                        ToolTip.delay: 300
                                        onClicked: root.removeApp(index)
                                    }
                                }
                            }
                        }
                    }

                    // Add new startup app card
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 110
                        radius: 10
                        color: Qt.rgba(0, 0, 0, 0.35)
                        border.color: Qt.rgba(1, 1, 1, 0.08)
                        border.width: 1

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 8

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                // Name input
                                Rectangle {
                                    Layout.preferredWidth: 120
                                    Layout.preferredHeight: 32
                                    radius: 6
                                    color: Qt.rgba(0, 0, 0, 0.30)
                                    border.color: nameInput.activeFocus ? Theme.primary : Qt.rgba(1, 1, 1, 0.12)
                                    border.width: 1

                                    TextInput {
                                        id: nameInput
                                        anchors.fill: parent
                                        anchors.margins: 6
                                        text: root.newAppName
                                        onTextChanged: root.newAppName = text
                                        font.family: Theme.font
                                        font.pixelSize: Theme.fontPx(11)
                                        color: Qt.rgba(1, 1, 1, 0.90)
                                        selectByMouse: true

                                        Text {
                                            visible: !nameInput.text && !nameInput.activeFocus
                                            text: "App Name"
                                            font: nameInput.font
                                            color: Qt.rgba(1, 1, 1, 0.30)
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }
                                }

                                // Command input
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 32
                                    radius: 6
                                    color: Qt.rgba(0, 0, 0, 0.30)
                                    border.color: cmdInput.activeFocus ? Theme.primary : Qt.rgba(1, 1, 1, 0.12)
                                    border.width: 1

                                    TextInput {
                                        id: cmdInput
                                        anchors.fill: parent
                                        anchors.margins: 6
                                        text: root.newAppCmd
                                        onTextChanged: root.newAppCmd = text
                                        font.family: Theme.fontMono
                                        font.pixelSize: Theme.fontPx(11)
                                        color: Qt.rgba(1, 1, 1, 0.90)
                                        selectByMouse: true

                                        Text {
                                            visible: !cmdInput.text && !cmdInput.activeFocus
                                            text: "Command (e.g. easyeffects)"
                                            font: cmdInput.font
                                            color: Qt.rgba(1, 1, 1, 0.30)
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 30
                                radius: 6
                                color: addMouse.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.20) : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.10)
                                border.color: Theme.primary
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: "+ Add Startup Application"
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontPx(11)
                                    font.weight: Font.DemiBold
                                    color: Theme.primary
                                }

                                MouseArea {
                                    id: addMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onEntered: root.describe("Add Startup App", "Register a new binary command or background script into ~/.config/carbon/autostart.conf.")
                                    onExited: root.clearDesc()
                                    ToolTip.visible: containsMouse
                                    ToolTip.text: "Register new binary or script to autostart on login"
                                    ToolTip.delay: 300
                                    onClicked: root.addApp()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
