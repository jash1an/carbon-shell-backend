import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import M3Shapes
import "../Singletons"
import "../components"

/**
 * Nebula-style Top-Left Island (Proportionally Scaled 38px):
 *   - App launcher button (Caelestia logo)
 *   - Instant-reacting horizontal workspaces (1..4 base, 5+ conditional)
 *   - Clean active workspace label (e.g. "Workspace 1")
 */
Item {
    id: root

    implicitHeight: root.vertical ? (verticalCol.implicitHeight + (root.attachedEdge !== "" ? 24 : (root.showBackground ? 16 : 8))) : 38
    implicitWidth: root.vertical ? (root.attachedEdge !== "" ? 34 : 38) : pill.width

    signal openLauncher()

    /* Workspaces state */
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
        Quickshell.execDetached(["hyprctl", "dispatch", "workspace", String(id)])
    }

    /* Track active workspace instantly via Hyprland Raw IPC Events */
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

    /* Workspace occupancy probe */
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

    /* Dynamic workspace models (base 1..4, 5+ strictly conditional) */
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
        anchors.left: parent.left
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
            anchors.leftMargin: 6
            spacing: 6

            /* ── App Launcher Button ──────────────────────────────────── */
            Item {
                id: launcherBadge
                Layout.preferredWidth: 26
                Layout.preferredHeight: 26
                Layout.alignment: Qt.AlignVCenter

                readonly property bool isHovered: launcherMouse.containsMouse

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
                    color: launcherBadge.isHovered ? Theme.bgHover : "transparent"
                    strokeColor: launcherBadge.isHovered ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.40) : "transparent"
                    strokeWidth: 1.2
                    rotation: launcherBadge.isHovered ? -8 : 0
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Behavior on strokeColor { ColorAnimation { duration: 120 } }
                    Behavior on rotation { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
                }

                StaticCarbonLogo {
                    anchors.centerIn: parent
                    width: 18
                    height: 18
                    hovered: launcherBadge.isHovered
                }

                MouseArea {
                    id: launcherMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.openLauncher()
                        Quickshell.execDetached(["rofi", "-show", "drun"])
                    }
                }
            }

            /* Divider */
            Rectangle {
                Layout.preferredWidth: 1
                Layout.preferredHeight: 14
                Layout.alignment: Qt.AlignVCenter
                color: "#25FFFFFF"
            }

            /* ── Workspaces Row ───────────────────────────────────────── */
            Row {
                Layout.alignment: Qt.AlignVCenter
                spacing: 5

                Repeater {
                    model: root.displayWorkspaces
                    delegate: Item {
                        id: wsChip
                        required property int modelData
                        required property int index

                        readonly property bool isActive: modelData === root.activeWs
                        readonly property bool isOccupied: root.activeWorkspaces.indexOf(modelData) !== -1

                        width: isActive ? 24 : 20
                        height: 22
                        scale: isActive ? 1.08 : (wsMouse.containsMouse ? 1.15 : 1.0)
                        Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
                        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack; easing.overshoot: 1.3 } }

                        MaterialShape {
                            id: wsM3Shape
                            anchors.fill: parent
                            shape: wsChip.isActive ? root.getShapeForWs(wsChip.modelData) : (wsMouse.containsMouse ? root.getShapeForWs(wsChip.modelData) : MaterialShape.Circle)
                            animationDuration: 280
                            animationEasing: Easing.OutBack
                            color: wsChip.isActive ? Theme.accent : (wsMouse.containsMouse ? Theme.bgHover : (wsChip.isOccupied ? "#28FFFFFF" : "transparent"))
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }

                        // Outline ring for occupied inactive workspaces
                        Rectangle {
                            visible: !wsChip.isActive && wsChip.isOccupied
                            anchors.fill: parent
                            radius: width / 2
                            color: "transparent"
                            border.color: Qt.alpha(Theme.fg, 0.18)
                            border.width: 1
                        }

                        Text {
                            anchors.centerIn: parent
                            text: String(wsChip.modelData)
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: Theme.fontPx(10)
                            font.weight: wsChip.isActive ? Font.Bold : Font.Medium
                            color: wsChip.isActive ? (Theme.isDark ? "#111111" : "#ffffff") : (wsChip.isOccupied ? Theme.fg : Theme.fgDim)
                        }

                        MouseArea {
                            id: wsMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.switchWorkspace(wsChip.modelData)
                        }
                    }
                }
            }

            /* Divider */
            Rectangle {
                Layout.preferredWidth: 1
                Layout.preferredHeight: 14
                Layout.alignment: Qt.AlignVCenter
                color: "#25FFFFFF"
            }

            /* ── Clean Workspace Label & Morphing Shape ────────────────── */
            Row {
                Layout.alignment: Qt.AlignVCenter
                spacing: 6

                MaterialShape {
                    width: 14
                    height: 14
                    anchors.verticalCenter: parent.verticalCenter
                    shape: root.getShapeForWs(root.activeWs)
                    animationDuration: 280
                    animationEasing: Easing.OutBack
                    color: Theme.accent
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Workspace " + root.activeWs
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: Theme.fontPx(11)
                    font.weight: Font.Medium
                    color: Theme.fgDim
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

            /* App Launcher Button */
            Item {
                id: vLauncherBadge
                Layout.preferredWidth: 26
                Layout.preferredHeight: 26
                Layout.alignment: Qt.AlignHCenter
                readonly property bool isHovered: vLauncherMouse.containsMouse

                // Ambient blooming shape halo
                MaterialShape {
                    anchors.centerIn: parent
                    width: parent.width + 6
                    height: parent.height + 6
                    shape: MaterialShape.Boom
                    color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.25)
                    scale: vLauncherBadge.isHovered ? 1.12 : 0.6
                    opacity: vLauncherBadge.isHovered ? 1.0 : 0.0
                    rotation: vLauncherBadge.isHovered ? -8 : 0
                    Behavior on opacity { NumberAnimation { duration: 180 } }
                    Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutBack } }
                    Behavior on rotation { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
                }

                // Tactile highlight chip morphing into unique Boom shape
                MaterialShape {
                    anchors.fill: parent
                    shape: vLauncherBadge.isHovered ? MaterialShape.Boom : MaterialShape.Circle
                    animationDuration: 260
                    animationEasing: Easing.OutBack
                    color: vLauncherBadge.isHovered ? Theme.bgHover : "transparent"
                    strokeColor: vLauncherBadge.isHovered ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.40) : "transparent"
                    strokeWidth: 1.2
                    rotation: vLauncherBadge.isHovered ? -8 : 0
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Behavior on strokeColor { ColorAnimation { duration: 120 } }
                    Behavior on rotation { NumberAnimation { duration: 260; easing.type: Easing.OutBack } }
                }

                StaticCarbonLogo {
                    anchors.centerIn: parent
                    width: 18
                    height: 18
                    hovered: vLauncherBadge.isHovered
                }

                MouseArea {
                    id: vLauncherMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.openLauncher()
                        Quickshell.execDetached(["rofi", "-show", "drun"])
                    }
                }
            }

            /* Divider */
            Rectangle {
                Layout.preferredWidth: 16
                Layout.preferredHeight: 1
                Layout.alignment: Qt.AlignHCenter
                color: "#25FFFFFF"
            }

            /* Workspaces Column */
            Column {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 22
                Layout.preferredHeight: childrenRect.height
                spacing: 4

                Repeater {
                    model: root.displayWorkspaces
                    delegate: Item {
                        id: vWsChip
                        required property int modelData
                        required property int index

                        readonly property bool isActive: modelData === root.activeWs
                        readonly property bool isOccupied: root.activeWorkspaces.indexOf(modelData) !== -1

                        width: 22
                        height: isActive ? 24 : 20
                        scale: isActive ? 1.08 : (vWsMouse.containsMouse ? 1.15 : 1.0)
                        Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
                        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack; easing.overshoot: 1.3 } }

                        MaterialShape {
                            anchors.fill: parent
                            shape: vWsChip.isActive ? root.getShapeForWs(vWsChip.modelData) : (vWsMouse.containsMouse ? root.getShapeForWs(vWsChip.modelData) : MaterialShape.Circle)
                            animationDuration: 280
                            animationEasing: Easing.OutBack
                            color: vWsChip.isActive ? Theme.accent : (vWsMouse.containsMouse ? Theme.bgHover : (vWsChip.isOccupied ? "#28FFFFFF" : "transparent"))
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }

                        // Outline ring for occupied inactive workspaces
                        Rectangle {
                            visible: !vWsChip.isActive && vWsChip.isOccupied
                            anchors.fill: parent
                            radius: width / 2
                            color: "transparent"
                            border.color: Qt.alpha(Theme.fg, 0.18)
                            border.width: 1
                        }

                        Text {
                            anchors.centerIn: parent
                            text: String(vWsChip.modelData)
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: Theme.fontPx(10)
                            font.weight: vWsChip.isActive ? Font.Bold : Font.Medium
                            color: vWsChip.isActive ? (Theme.isDark ? "#111111" : "#ffffff") : (vWsChip.isOccupied ? Theme.fg : Theme.fgDim)
                        }

                        MouseArea {
                            id: vWsMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.switchWorkspace(vWsChip.modelData)
                        }
                    }
                }
            }

            /* Divider */
            Rectangle {
                Layout.preferredWidth: 16
                Layout.preferredHeight: 1
                Layout.alignment: Qt.AlignHCenter
                color: "#25FFFFFF"
            }

            /* Active Workspace Label Badge */
            Column {
                Layout.alignment: Qt.AlignHCenter
                spacing: 1

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "desktop_windows"
                    font.family: Theme.fontIcon
                    font.pixelSize: 13
                    color: Theme.accent
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "WS " + root.activeWs
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: Theme.fontPx(9)
                    font.weight: Font.Bold
                    color: Theme.fg
                }
            }
        }
    }
}
