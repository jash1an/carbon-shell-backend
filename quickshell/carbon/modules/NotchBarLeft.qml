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

    signal openSpotlight()
    signal toggleSpotlight()

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
        Quickshell.execDetached(["hyprctl", "dispatch", "workspace", String(id)])
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

    /* ── Content Row Inside Notch (Workspaces & Spotlight removed per prompt) ── */
    content: []
}
