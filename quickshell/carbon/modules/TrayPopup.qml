import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Services.SystemTray
import "../Singletons"

/**
 * TrayPopup:
 * Windows-style system tray overflow menu displaying running background applications
 * and system tray applets (Discord, Antigravity, Zen, etc.).
 * Pops up when the user hovers over or clicks the small up-arrow chevron in the bar.
 */
Item {
    id: root

    property bool open: false
    property string barEdge: "top"
    property bool hovered: hoverHandler.hovered
    signal requestedClose()

    clip: true

    // 1. Native StatusNotifierItem (SNI) tray items
    readonly property var sniItems: SystemTray.items.values.filter(function (it) {
        var key = ((it.id || "") + " " + (it.title || "") + " " + (it.tooltipTitle || "")).toLowerCase()
        return !/(nm[ _-]?applet|blueman)/.test(key)
    })

    // 2. Active Background & Desktop Applications (scanned from Hyprland & user processes)
    property var bgApps: []
    property string hoveredAppName: ""
    property string hoveredAppSub: ""

    Process {
        id: bgAppsProbe
        command: ["python3", (Quickshell.env("HOME") || "") + "/.config/hypr/scripts/carbon-tray-apps.py"]
        stdout: StdioCollector {
            id: bgAppsCol
            waitForEnd: true
        }
        onExited: {
            try {
                const txt = String(bgAppsCol.text).trim()
                if (txt.length > 0) {
                    root.bgApps = JSON.parse(txt)
                }
            } catch (e) {
                console.log("[TrayPopup] Error parsing background apps:", e)
            }
        }
    }

    Timer {
        id: bgRefreshTimer
        interval: 3000
        repeat: true
        running: root.open
        onTriggered: {
            if (!bgAppsProbe.running) bgAppsProbe.running = true
        }
    }

    property bool animatingOut: false
    onOpenChanged: {
        if (root.open) {
            if (!bgAppsProbe.running) bgAppsProbe.running = true
            root.animatingOut = false
            animatingOutTimer.stop()
        } else {
            root.hoveredAppName = ""
            root.hoveredAppSub = ""
            root.animatingOut = true
            animatingOutTimer.restart()
        }
    }
    Timer {
        id: animatingOutTimer
        interval: 200
        onTriggered: root.animatingOut = false
    }

    Component.onCompleted: {
        if (!bgAppsProbe.running) bgAppsProbe.running = true
    }

    // Unified List of All Tray & Background Apps
    readonly property var allItems: {
        var list = []
        var seenKeys = {}

        // Add native SNI items first
        for (var i = 0; i < sniItems.length; i++) {
            var it = sniItems[i]
            var key = ((it.id || "") + " " + (it.title || "")).toLowerCase()
            seenKeys[key] = true
            list.push({
                isSni: true,
                rawItem: it,
                name: it.title || it.tooltipTitle || it.id || "Tray App",
                sub: "System Tray",
                icon: it.icon,
                iconPath: ""
            })
        }

        // Add Background applications (Discord, Antigravity, etc.)
        for (var j = 0; j < bgApps.length; j++) {
            var app = bgApps[j]
            var appKey = (app.class || app.name || "").toLowerCase()
            var matched = false
            for (var k in seenKeys) {
                if (k.indexOf(appKey) !== -1 || appKey.indexOf(k) !== -1) {
                    matched = true
                    break
                }
            }
            if (!matched) {
                list.push({
                    isSni: false,
                    rawItem: app,
                    name: app.name || app.title || "App",
                    sub: app.hasWindow ? ("Workspace " + app.workspace) : "Background Process",
                    icon: app.icon || "application-x-executable",
                    iconPath: app.iconPath || "",
                    address: app.address || "",
                    workspace: app.workspace || 1,
                    hasWindow: Boolean(app.hasWindow),
                    exec: app.exec || "",
                    appClass: app.class || ""
                })
            }
        }

        return list
    }

    readonly property int columns: 4
    readonly property int rows: Math.max(1, Math.ceil(allItems.length / columns))

    implicitWidth: 190
    implicitHeight: (allItems.length === 0) ? 74 : (rows * 38 + 58)

    HoverHandler {
        id: hoverHandler
    }

    property string barMode: "notch"
    property real notchOpacity: 0.96

    readonly property string fillPath: {
        const w = bgCard.width
        const h = bgCard.height
        if (root.barMode === "notch") {
            const r = 16
            if (root.barEdge === "bottom") {
                return `M 0 ${r} A ${r} ${r} 0 0 1 ${r} 0 L ${w} 0 L ${w} ${h} L 0 ${h} Z`
            }
            return `M 0 ${r} A ${r} ${r} 0 0 1 ${r} 0 L ${w} 0 L ${w} ${h} L ${r} ${h} A ${r} ${r} 0 0 1 0 ${h - r} Z`
        }
        const r = 16
        return `M ${r} 0 L ${w - r} 0 A ${r} ${r} 0 0 1 ${w} ${r} L ${w} ${h - r} A ${r} ${r} 0 0 1 ${w - r} ${h} L ${r} ${h} A ${r} ${r} 0 0 1 0 ${h - r} L 0 ${r} A ${r} ${r} 0 0 1 ${r} 0 Z`
    }

    readonly property string strokePath: {
        const w = bgCard.width
        const h = bgCard.height
        if (root.barMode === "notch") {
            const r = 16
            if (root.barEdge === "bottom") {
                return `M 0 ${h - r} L 0 ${r} A ${r} ${r} 0 0 1 ${r} 0 L ${w} 0`
            }
            return `M 0 ${r} L 0 ${h - r} A ${r} ${r} 0 0 0 ${r} ${h} L ${w} ${h}`
        }
        const r = 16
        return `M ${r} 0 L ${w - r} 0 A ${r} ${r} 0 0 1 ${w} ${r} L ${w} ${h - r} A ${r} ${r} 0 0 1 ${w - r} ${h} L ${r} ${h} A ${r} ${r} 0 0 1 0 ${h - r} L 0 ${r} A ${r} ${r} 0 0 1 ${r} 0 Z`
    }

    Item {
        id: bgCard
        anchors.fill: parent

        Shape {
            id: cardBgShape
            anchors.fill: parent
            preferredRendererType: Shape.GeometryRenderer
            antialiasing: true
            asynchronous: false

            ShapePath {
                fillColor: root.barMode === "notch" ? (Theme.isDark ? Qt.rgba(0.04, 0.04, 0.06, root.notchOpacity) : Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, root.notchOpacity)) : Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, Theme.shellOpacity)
                strokeColor: "transparent"
                strokeWidth: 0
                PathSvg { path: root.fillPath }
            }

            ShapePath {
                fillColor: "transparent"
                strokeColor: root.open ? Qt.rgba(Theme.accentLit.r, Theme.accentLit.g, Theme.accentLit.b, 0.45) : Theme.outline
                strokeWidth: 1
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathSvg { path: root.strokePath }
            }
        }

        opacity: root.open ? 1.0 : 0.0
        scale: root.open ? 1.0 : 0.95
        y: root.open ? 0 : (root.barEdge === "bottom" ? -6 : 6)

        Behavior on opacity {
            NumberAnimation {
                duration: root.open ? 200 : 140
                easing.bezierCurve: Theme.animCurves.expressiveDefaultEffects
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: root.open ? 280 : 160
                easing.bezierCurve: root.open ? Theme.animCurves.expressiveDefaultSpatial : Theme.animCurves.standardAccel
            }
        }
        Behavior on y {
            NumberAnimation {
                duration: root.open ? 280 : 160
                easing.bezierCurve: root.open ? Theme.animCurves.expressiveDefaultSpatial : Theme.animCurves.standardAccel
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            anchors.leftMargin: root.barMode === "notch" ? 22 : 10
            spacing: 6

            // Header: "Background Apps"
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Text {
                    text: "apps"
                    font.family: Theme.fontIcon
                    font.pixelSize: 13
                    color: Theme.accent
                }

                Column {
                    Layout.fillWidth: true
                    spacing: 0

                    Text {
                        text: root.hoveredAppName ? root.hoveredAppName : "Background Apps"
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: Theme.fontPx(10)
                        font.weight: Font.Bold
                        color: Theme.fg
                        elide: Text.ElideRight
                        width: parent.width
                    }

                    Text {
                        text: root.hoveredAppSub ? root.hoveredAppSub : (root.allItems.length + " running")
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: Theme.fontPx(8)
                        color: Theme.fgDim
                        elide: Text.ElideRight
                        width: parent.width
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.08)
            }

            // Grid of Background App Icons
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                Text {
                    anchors.centerIn: parent
                    visible: root.allItems.length === 0
                    text: "No background apps"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: Theme.fontPx(10)
                    color: Theme.fgDim
                }

                Grid {
                    anchors.centerIn: parent
                    columns: root.columns
                    spacing: 6
                    visible: root.allItems.length > 0

                    Repeater {
                        model: root.allItems
                        delegate: Item {
                            id: slot
                            required property var modelData
                            required property int index

                            width: 32
                            height: 32

                            readonly property bool isHovered: slotMouse.containsMouse

                            onIsHoveredChanged: {
                                if (isHovered) {
                                    root.hoveredAppName = slot.modelData.name
                                    root.hoveredAppSub = slot.modelData.sub
                                } else if (root.hoveredAppName === slot.modelData.name) {
                                    root.hoveredAppName = ""
                                    root.hoveredAppSub = ""
                                }
                            }

                            Rectangle {
                                anchors.fill: parent
                                radius: 8
                                color: slot.isHovered ? Theme.bgHover : "transparent"
                                border.color: slot.isHovered ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.45) : "transparent"
                                border.width: 1
                                scale: slot.isHovered ? 1.08 : 1.0
                                Behavior on color { ColorAnimation { duration: 120 } }
                                Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
                            }

                            Image {
                                anchors.centerIn: parent
                                source: {
                                    if (slot.modelData.isSni) {
                                        return slot.modelData.rawItem.icon || ""
                                    } else {
                                        return slot.modelData.iconPath || Quickshell.iconPath(slot.modelData.icon, "application-x-executable")
                                    }
                                }
                                sourceSize: Qt.size(22, 22)
                                width: 22
                                height: 22
                                fillMode: Image.PreserveAspectFit
                                smooth: true
                                mipmap: true
                            }

                            MouseArea {
                                id: slotMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                cursorShape: Qt.PointingHandCursor
                                onClicked: (mouse) => {
                                    if (slot.modelData.isSni) {
                                        var sni = slot.modelData.rawItem
                                        if (mouse.button === Qt.RightButton) {
                                            if (sni.hasMenu) sni.openMenu(mouse.x, mouse.y)
                                            else sni.secondaryActivate()
                                        } else {
                                            sni.activate()
                                        }
                                    } else {
                                        var app = slot.modelData
                                        if (mouse.button === Qt.RightButton) {
                                            // Secondary action: focus or activate
                                            if (app.hasWindow && app.address) {
                                                Quickshell.execDetached(["hyprctl", "dispatch", "focuswindow", "address:" + app.address])
                                            } else {
                                                Quickshell.execDetached(["sh", "-c", app.exec || (app.appClass + " &")])
                                            }
                                        } else {
                                            // Left Click: Switch workspace and focus window or bring to front
                                            if (app.hasWindow && app.address) {
                                                if (app.workspace > 0) {
                                                    Quickshell.execDetached(["hyprctl", "dispatch", "workspace", String(app.workspace)])
                                                }
                                                Quickshell.execDetached(["hyprctl", "dispatch", "focuswindow", "address:" + app.address])
                                            } else {
                                                Quickshell.execDetached(["sh", "-c", app.exec || (app.appClass + " &")])
                                            }
                                            root.requestedClose()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

