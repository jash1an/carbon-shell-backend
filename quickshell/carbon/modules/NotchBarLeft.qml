import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import M3Shapes
import "../Singletons"
import "../components"

/**
 * NotchBarLeft: Top-attached curved notch for Left side
 *   - App launcher button
 *   - Workspace pills with active accent highlight and app icons
 *   - Desktop & Active Workspace label (Monitor icon + Desktop / Workspace N)
 */
NotchContainer {
    id: root

    implicitHeight: 34
    earWidth: 20
    contentSpacing: 7

    signal openLauncher()

    /* Hyprland workspace tracking */
    property int activeWs: 1
    property var activeWorkspaces: [1]

    function getShapeForWs(wsId) {
        switch (wsId) {
            case 1: return MaterialShape.Clover4Leaf
            case 2: return MaterialShape.Sunny
            case 3: return MaterialShape.Flower
            case 4: return MaterialShape.Cookie12Sided
            case 5: return MaterialShape.Gem
            case 6: return MaterialShape.Diamond
            case 7: return MaterialShape.Cookie4Sided
            case 8: return MaterialShape.SoftBurst
            case 9: return MaterialShape.Boom
            case 10: return MaterialShape.Ghostish
            default: {
                const extraShapes = [
                    MaterialShape.Slanted,
                    MaterialShape.Pentagon,
                    MaterialShape.ClamShell,
                    MaterialShape.PuffyDiamond,
                    MaterialShape.Arch
                ]
                return extraShapes[Math.abs(wsId - 11) % extraShapes.length]
            }
        }
    }

    function switchWorkspace(id) {
        root.activeWs = id
        Quickshell.execDetached(["hyprctl", "eval", "local fn = require('hyprland.functions'); fn.wsaction('focus', '', " + id + ")()"])
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            const n = event.name
            if (n === "workspace" || n === "workspacev2") {
                const id = parseInt(event.data, 10)
                if (!isNaN(id) && id > 0) root.activeWs = id
                listProbe.running = true
            } else if (n === "createworkspace" || n === "destroyworkspace"
                       || n === "focusedmon" || n === "focusedmonv2") {
                listProbe.running = true
            }
        }
    }

    Connections {
        target: Hyprland.focusedMonitor
        function onActiveWorkspaceChanged() {
            if (Hyprland.focusedMonitor && Hyprland.focusedMonitor.activeWorkspace) {
                root.activeWs = Hyprland.focusedMonitor.activeWorkspace.id
            }
        }
    }

    Process {
        id: listProbe
        command: ["sh", "-c", "hyprctl workspaces -j | jq -r '.[].id' 2>/dev/null || true"]
        running: false
        stdout: StdioCollector { id: listC; waitForEnd: true }
        onExited: {
            const lines = listC.text.trim().split("\n")
            const ids = []
            for (let i = 0; i < lines.length; i++) {
                const id = parseInt(lines[i].trim(), 10)
                if (!isNaN(id) && id > 0 && ids.indexOf(id) === -1) {
                    ids.push(id)
                }
            }
            ids.sort((a, b) => a - b)
            if (ids.length > 0) root.activeWorkspaces = ids
        }
    }

    Timer {
        interval: 15000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: listProbe.running = true
    }

    readonly property var displayWorkspaces: {
        const base = [1, 2, 3, 4]
        for (let i = 0; i < root.activeWorkspaces.length; i++) {
            const id = root.activeWorkspaces[i]
            if (id <= 10 && base.indexOf(id) === -1) base.push(id)
        }
        if (root.activeWs <= 10 && base.indexOf(root.activeWs) === -1) {
            base.push(root.activeWs)
        }
        base.sort((a, b) => a - b)
        return base
    }

    /* ── Content Row Inside Notch ───────────────────────────────────── */
    content: [
        /* 1. App Launcher Icon */
        Item {
            id: launcherBadge
            width: 22
            height: 22
            anchors.verticalCenter: parent.verticalCenter
            readonly property bool isHovered: lMouse.containsMouse

            scale: isHovered ? 1.18 : 1.0
            y: isHovered ? -2 : 0
            Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }
            Behavior on y { NumberAnimation { duration: 240; easing.type: Easing.OutBack; easing.overshoot: 1.4 } }

            // Ambient glowing halo morphing into unique Boom shape
            MaterialShape {
                anchors.centerIn: parent
                width: parent.width + 8
                height: parent.height + 8
                shape: launcherBadge.isHovered ? MaterialShape.Boom : MaterialShape.Circle
                animationDuration: 260
                animationEasing: Easing.OutBack
                color: launcherBadge.isHovered ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.25) : "transparent"
                scale: launcherBadge.isHovered ? 1.12 : 0.6
                opacity: launcherBadge.isHovered ? 1.0 : 0.0
                rotation: launcherBadge.isHovered ? -8 : 0
                Behavior on opacity { NumberAnimation { duration: 180 } }
                Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutBack } }
                Behavior on rotation { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
            }

            // Tactile highlight chip morphing into unique Boom shape
            MaterialShape {
                anchors.fill: parent
                shape: launcherBadge.isHovered ? MaterialShape.Boom : MaterialShape.Circle
                animationDuration: 260
                animationEasing: Easing.OutBack
                color: launcherBadge.isHovered ? Theme.bgHover : Qt.alpha(Theme.fg, 0.08)
                strokeColor: launcherBadge.isHovered ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.45) : "transparent"
                strokeWidth: 1.2
                rotation: launcherBadge.isHovered ? -8 : 0
                Behavior on color { ColorAnimation { duration: 120 } }
                Behavior on strokeColor { ColorAnimation { duration: 120 } }
                Behavior on rotation { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
            }

            StaticCarbonLogo {
                anchors.centerIn: parent
                width: 17
                height: 17
                hovered: launcherBadge.isHovered
            }

            MouseArea {
                id: lMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openLauncher()
            }
        },

        /* 2. Workspace Pills / Icons */
        Row {
            spacing: 5
            anchors.verticalCenter: parent.verticalCenter

            Repeater {
                model: root.displayWorkspaces

                delegate: Item {
                    id: wsBtn
                    required property var modelData
                    required property int index

                    readonly property int wsId: wsBtn.modelData
                    readonly property bool isActive: root.activeWs === wsId
                    readonly property bool isOccupied: root.activeWorkspaces.indexOf(wsId) !== -1

                    width: isActive ? 24 : 22
                    height: 22
                    scale: isActive ? 1.08 : (wsMouse.containsMouse ? 1.15 : 1.0)
                    Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
                    Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack; easing.overshoot: 1.3 } }

                    MaterialShape {
                        anchors.fill: parent
                        shape: wsBtn.isActive ? root.getShapeForWs(wsBtn.wsId) : (wsMouse.containsMouse ? root.getShapeForWs(wsBtn.wsId) : MaterialShape.Circle)
                        animationDuration: 280
                        animationEasing: Easing.OutBack
                        color: wsBtn.isActive ? Theme.accent : (wsMouse.containsMouse ? Theme.bgHover : (wsBtn.isOccupied ? (Theme.isDark ? Qt.alpha(Theme.fg, 0.16) : Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.10)) : (Theme.isDark ? Qt.alpha(Theme.fg, 0.05) : Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.06))))
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }

                    // Subtle outline for inactive occupied
                    Rectangle {
                        visible: !wsBtn.isActive && wsBtn.isOccupied
                        anchors.fill: parent
                        radius: width / 2
                        color: "transparent"
                        border.color: Theme.isDark ? Qt.alpha(Theme.fg, 0.18) : Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.15)
                        border.width: 1
                    }

                    Text {
                        anchors.centerIn: parent
                        text: String(wsBtn.wsId)
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: Theme.fontPx(10)
                        font.weight: wsBtn.isActive ? Font.Bold : Font.Medium
                        color: wsBtn.isActive ? (Theme.isDark ? "#111111" : "#ffffff") : (wsBtn.isOccupied ? Theme.fg : (Theme.isDark ? Theme.fgFaint : Theme.fgDim))
                    }

                    MouseArea {
                        id: wsMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.switchWorkspace(wsBtn.wsId)
                    }
                }
            }
        },

        /* Divider */
        Rectangle {
            width: 1
            height: 14
            color: Theme.isDark ? Qt.alpha(Theme.fg, 0.18) : Qt.alpha(Theme.fg, 0.25)
            anchors.verticalCenter: parent.verticalCenter
        },

        /* 3. Active Workspace / Desktop Badge */
        Row {
            spacing: 6
            anchors.verticalCenter: parent.verticalCenter

            MaterialShape {
                width: 15
                height: 15
                anchors.verticalCenter: parent.verticalCenter
                shape: root.getShapeForWs(root.activeWs)
                animationDuration: 280
                animationEasing: Easing.OutBack
                color: Theme.accent
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0

                Text {
                    text: "Desktop"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: Theme.fontPx(8)
                    font.weight: Font.Medium
                    color: Theme.isDark ? Theme.fgFaint : Theme.fgDim
                }

                Text {
                    text: "Workspace " + root.activeWs
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: Theme.fontPx(10)
                    font.weight: Font.Bold
                    color: Theme.fg
                }
            }
        }
    ]
}
