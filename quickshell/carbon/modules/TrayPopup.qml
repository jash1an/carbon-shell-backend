import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Services.SystemTray
import "../Singletons"

/**
 * TrayPopup:
 * Modern desktop-class system tray and background applications manager.
 * Displays running background applications and SNI applets in a clean desktop list.
 * Left-click activates or focuses the application window.
 * Right-click (or clicking the options button) smoothly expands an inline action
 * drawer right beneath the app without hiding the other background applications.
 */
Item {
    id: root

    property bool open: false
    property string barEdge: "top"
    property bool hovered: hoverHandler.hovered
    property string selectedAppId: ""
    signal requestedClose()

    clip: true

    focus: root.open
    Keys.enabled: root.open
    Keys.onEscapePressed: (event) => {
        if (root.selectedAppId !== "") {
            root.selectedAppId = ""
            event.accepted = true
        } else {
            root.requestedClose()
            event.accepted = true
        }
    }

    // 1. Native StatusNotifierItem (SNI) tray items
    readonly property var sniItems: SystemTray.items.values.filter(function (it) {
        var key = ((it.id || "") + " " + (it.title || "") + " " + (it.tooltipTitle || "")).toLowerCase()
        return !/(nm[ _-]?applet|blueman)/.test(key)
    })

    // 2. Active Background & Desktop Applications (scanned from Hyprland & user processes)
    property var bgApps: []

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
            root.selectedAppId = ""
            if (!bgAppsProbe.running) bgAppsProbe.running = true
            root.animatingOut = false
            animatingOutTimer.stop()
        } else {
            root.selectedAppId = ""
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
                id: "sni-" + (it.id || i),
                isSni: true,
                rawItem: it,
                name: it.title || it.tooltipTitle || it.id || "Tray App",
                sub: "System Tray Applet",
                icon: it.icon,
                iconPath: "",
                hasWindow: false,
                category: "general",
                actions: [
                    { id: "activate", label: "Open / Activate", icon: "touch_app", action: "sniActivate" },
                    (it.hasMenu ? { id: "native_menu", label: "App Menu", icon: "menu", action: "sniMenu" } : null),
                    { id: "quit", label: "Quit Application", icon: "close", danger: true, action: "sniQuit" }
                ].filter(function (a) { return a !== null })
            })
        }

        // Add Background applications (GPU Screen Recorder, Serein, Kitty, etc.)
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
                var defaultActs = (app.actions && app.actions.length > 0) ? app.actions : [
                    (app.hasWindow ? { id: "focus", label: "Focus Window", icon: "visibility", action: "focus" } : null),
                    { id: "quit", label: "Close Application", icon: "close", danger: true, action: "close" }
                ].filter(function (a) { return a !== null })

                var subText = "Background Process"
                if (app.hasWindow) {
                    subText = "Workspace " + app.workspace + " • Active"
                } else if (app.category) {
                    subText = app.category.charAt(0).toUpperCase() + app.category.slice(1) + " Daemon"
                }

                list.push({
                    id: app.id || ("bg-" + j),
                    isSni: false,
                    rawItem: app,
                    name: app.name || app.title || "App",
                    sub: subText,
                    icon: app.icon || "application-x-executable",
                    iconPath: app.iconPath || "",
                    address: app.address || "",
                    workspace: app.workspace || 1,
                    hasWindow: Boolean(app.hasWindow),
                    exec: app.exec || "",
                    appClass: app.class || "",
                    pid: app.pid || 0,
                    category: app.category || "general",
                    actions: defaultActs
                })
            }
        }

        return list
    }

    implicitWidth: 330
    implicitHeight: Math.min(460, Math.max(140, mainListCol.implicitHeight + 48))

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

    function executeAction(act, app) {
        if (!act || !app) return

        // 1. Direct shell command
        if (act.cmd) {
            Quickshell.execDetached(["sh", "-c", act.cmd])
        }

        // 2. Hyprland window actions
        if (act.action === "focus") {
            if (app.hasWindow && app.address) {
                if (app.workspace > 0) {
                    Quickshell.execDetached(["hyprctl", "dispatch", "workspace", String(app.workspace)])
                }
                Quickshell.execDetached(["hyprctl", "dispatch", "focuswindow", "address:" + app.address])
            }
            root.selectedAppId = ""
            root.requestedClose()
            return
        }
        else if (act.action === "movetoworkspace") {
            if (app.hasWindow && app.address) {
                Quickshell.execDetached(["hyprctl", "dispatch", "movetoworkspace", "+0,address:" + app.address])
                Quickshell.execDetached(["hyprctl", "dispatch", "focuswindow", "address:" + app.address])
            }
            root.selectedAppId = ""
            root.requestedClose()
            return
        }
        else if (act.action === "togglefloating") {
            if (app.hasWindow && app.address) {
                Quickshell.execDetached(["hyprctl", "dispatch", "togglefloating", "address:" + app.address])
            }
            root.selectedAppId = ""
            root.requestedClose()
            return
        }
        // 3. Compulsory close / quit
        else if (act.action === "close") {
            if (app.hasWindow && app.address) {
                Quickshell.execDetached(["hyprctl", "dispatch", "closewindow", "address:" + app.address])
            }
            if (app.pid) {
                Quickshell.execDetached(["kill", String(app.pid)])
            }
            if (app.appClass && (app.appClass.includes("gpu_screen_recorder") || app.appClass.includes("gpu-screen-recorder"))) {
                Quickshell.execDetached(["sh", "-c", "pkill -f gpu-screen-recorder; flatpak kill com.dec05eba.gpu_screen_recorder 2>/dev/null"])
            }
            root.selectedAppId = ""
            root.requestedClose()
            bgRefreshTimer.restart()
            if (!bgAppsProbe.running) bgAppsProbe.running = true
            return
        }
        // 4. Native SNI actions
        else if (act.action === "sniActivate") {
            if (app.rawItem) app.rawItem.activate()
            root.selectedAppId = ""
            root.requestedClose()
            return
        }
        else if (act.action === "sniMenu") {
            if (app.rawItem && app.rawItem.hasMenu) {
                app.rawItem.openMenu(0, 0)
            } else if (app.rawItem) {
                app.rawItem.secondaryActivate()
            }
            root.selectedAppId = ""
            root.requestedClose()
            return
        }
        else if (act.action === "sniQuit") {
            if (app.rawItem) {
                app.rawItem.secondaryActivate()
            }
            var procName = (app.name || "").toLowerCase().replace(/\s+/g, "")
            if (procName) {
                Quickshell.execDetached(["sh", "-c", "pkill -f " + procName + " 2>/dev/null || true"])
            }
            root.selectedAppId = ""
            root.requestedClose()
            bgRefreshTimer.restart()
            return
        }

        // Close after danger actions
        if (act.danger) {
            root.selectedAppId = ""
            root.requestedClose()
            bgRefreshTimer.restart()
            if (!bgAppsProbe.running) bgAppsProbe.running = true
        }
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
        scale: root.open ? 1.0 : 0.96
        y: root.open ? 0 : (root.barEdge === "bottom" ? -6 : 6)

        Behavior on opacity {
            NumberAnimation {
                duration: root.open ? 180 : 130
                easing.bezierCurve: Theme.animCurves.expressiveDefaultEffects
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: root.open ? 240 : 150
                easing.bezierCurve: root.open ? Theme.animCurves.expressiveDefaultSpatial : Theme.animCurves.standardAccel
            }
        }
        Behavior on y {
            NumberAnimation {
                duration: root.open ? 240 : 150
                easing.bezierCurve: root.open ? Theme.animCurves.expressiveDefaultSpatial : Theme.animCurves.standardAccel
            }
        }

        ColumnLayout {
            id: mainLayout
            anchors.fill: parent
            anchors.margins: 12
            anchors.leftMargin: root.barMode === "notch" ? 22 : 12
            spacing: 8

            // Desktop Header: App Icon, Title, Active Count Badge, Close
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Rectangle {
                    width: 24
                    height: 24
                    radius: 7
                    color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.15)
                    border.width: 1
                    border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35)

                    Text {
                        anchors.centerIn: parent
                        text: "widgets"
                        font.family: Theme.fontIcon
                        font.pixelSize: 14
                        color: Theme.accent
                    }
                }

                Text {
                    text: "Background Apps"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: Theme.fontPx(9.5)
                    font.weight: Font.Bold
                    color: Theme.fg
                }

                Rectangle {
                    Layout.preferredHeight: 18
                    Layout.preferredWidth: countTxt.implicitWidth + 10
                    radius: 9
                    color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18)
                    border.width: 1
                    border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.30)

                    Text {
                        id: countTxt
                        anchors.centerIn: parent
                        text: root.allItems.length + " active"
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: Theme.fontPx(7)
                        font.weight: Font.Bold
                        color: Theme.accentLit
                    }
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    width: 20
                    height: 20
                    radius: 10
                    color: closeMA.containsMouse ? Theme.bgHover : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "close"
                        font.family: Theme.fontIcon
                        font.pixelSize: 12
                        color: closeMA.containsMouse ? Theme.fg : Theme.fgFaint
                    }

                    MouseArea {
                        id: closeMA
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.requestedClose()
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.08)
            }

            // Desktop App List View with Inline Expandable Drawers
            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: width
                contentHeight: mainListCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: mainListCol
                    width: parent.width
                    spacing: 6

                    // Empty State
                    Rectangle {
                        visible: root.allItems.length === 0
                        Layout.fillWidth: true
                        Layout.preferredHeight: 64
                        radius: 8
                        color: Qt.rgba(Theme.bgAlt.r, Theme.bgAlt.g, Theme.bgAlt.b, 0.30)
                        border.width: 1
                        border.color: Theme.outline

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 8
                            Text {
                                text: "layers_clear"
                                font.family: Theme.fontIcon
                                font.pixelSize: 18
                                color: Theme.fgFaint
                            }
                            Text {
                                text: "No background apps running"
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: Theme.fontPx(8.5)
                                color: Theme.fgFaint
                            }
                        }
                    }

                    // App Items Repeater
                    Repeater {
                        model: root.allItems
                        delegate: ColumnLayout {
                            id: appItemDelegate
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            spacing: 3

                            readonly property bool isSelected: root.selectedAppId === modelData.id
                            readonly property bool isRowHovered: rowMA.containsMouse

                            // Main App Tile Row
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 38
                                radius: 8
                                color: appItemDelegate.isSelected
                                       ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16)
                                       : (appItemDelegate.isRowHovered ? Theme.bgHover : Qt.rgba(1, 1, 1, 0.04))
                                border.width: 1
                                border.color: appItemDelegate.isSelected
                                              ? Theme.accent
                                              : (appItemDelegate.isRowHovered ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35) : Theme.outline)

                                Behavior on color { ColorAnimation { duration: 120 } }
                                Behavior on border.color { ColorAnimation { duration: 120 } }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    spacing: 8

                                    // App Icon Tile
                                    Rectangle {
                                        width: 24
                                        height: 24
                                        radius: 6
                                        color: Qt.rgba(1, 1, 1, 0.05)
                                        border.width: 1
                                        border.color: Qt.rgba(1, 1, 1, 0.08)

                                        Image {
                                            id: appIconImg
                                            anchors.centerIn: parent
                                            width: 18
                                            height: 18
                                            fillMode: Image.PreserveAspectFit
                                            source: {
                                                if (modelData.isSni) {
                                                    return modelData.rawItem.icon || ""
                                                }
                                                return modelData.iconPath || Quickshell.iconPath(modelData.icon, "application-x-executable")
                                            }
                                            smooth: true
                                            mipmap: true
                                        }

                                        Text {
                                            anchors.centerIn: parent
                                            visible: appIconImg.status !== Image.Ready
                                            text: "widgets"
                                            font.family: Theme.fontIcon
                                            font.pixelSize: 13
                                            color: Theme.accent
                                        }
                                    }

                                    // Name & Subtitle
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0

                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.name || ""
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: Theme.fontPx(8.5)
                                            font.weight: Font.Bold
                                            color: appItemDelegate.isSelected ? Theme.accent : Theme.fg
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.sub || ""
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: Theme.fontPx(7)
                                            color: appItemDelegate.isSelected ? Theme.accentLit : Theme.fgDim
                                            elide: Text.ElideRight
                                        }
                                    }
                                }

                                MouseArea {
                                    id: rowMA
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: (mouse) => {
                                        if (mouse.button === Qt.RightButton) {
                                            // Right click: toggle inline options drawer
                                            root.selectedAppId = appItemDelegate.isSelected ? "" : modelData.id
                                        } else {
                                            // Left click: default activation
                                            if (modelData.isSni) {
                                                modelData.rawItem.activate()
                                                root.requestedClose()
                                            } else {
                                                if (modelData.hasWindow && modelData.address) {
                                                    if (modelData.workspace > 0) {
                                                        Quickshell.execDetached(["hyprctl", "dispatch", "workspace", String(modelData.workspace)])
                                                    }
                                                    Quickshell.execDetached(["hyprctl", "dispatch", "focuswindow", "address:" + modelData.address])
                                                    root.requestedClose()
                                                } else if (modelData.exec) {
                                                    Quickshell.execDetached(["sh", "-c", modelData.exec])
                                                    root.requestedClose()
                                                } else {
                                                    // Toggle drawer if no direct window
                                                    root.selectedAppId = appItemDelegate.isSelected ? "" : modelData.id
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // Inline Expandable Action Drawer (Appears right beneath the app without hiding other apps)
                            Rectangle {
                                id: drawerCard
                                Layout.fillWidth: true
                                Layout.leftMargin: 8
                                Layout.rightMargin: 8
                                implicitHeight: appItemDelegate.isSelected ? (drawerContentCol.implicitHeight + 8) : 0
                                opacity: appItemDelegate.isSelected ? 1.0 : 0.0
                                visible: implicitHeight > 0
                                clip: true
                                radius: 8
                                color: Qt.rgba(Theme.bgAlt.r, Theme.bgAlt.g, Theme.bgAlt.b, 0.45)
                                border.width: 1
                                border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.25)

                                Behavior on implicitHeight {
                                    NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
                                }
                                Behavior on opacity {
                                    NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
                                }

                                ColumnLayout {
                                    id: drawerContentCol
                                    anchors.top: parent.top
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.margins: 4
                                    spacing: 3

                                    Repeater {
                                        model: modelData.actions || []
                                        delegate: Rectangle {
                                            id: actBtn
                                            required property var modelData
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 25
                                            radius: 6
                                            color: modelData.danger
                                                   ? (actMA.containsMouse ? Qt.rgba(Theme.err.r, Theme.err.g, Theme.err.b, 0.22) : Qt.rgba(Theme.err.r, Theme.err.g, Theme.err.b, 0.08))
                                                   : (actMA.containsMouse ? Theme.bgHover : "transparent")
                                            border.width: 1
                                            border.color: modelData.danger
                                                          ? Qt.rgba(Theme.err.r, Theme.err.g, Theme.err.b, 0.40)
                                                          : (actMA.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35) : "transparent")

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 8
                                                anchors.rightMargin: 8
                                                spacing: 6

                                                Text {
                                                    text: modelData.icon || (modelData.danger ? "close" : "play_arrow")
                                                    font.family: Theme.fontIcon
                                                    font.pixelSize: 12
                                                    color: modelData.danger ? Theme.err : (actMA.containsMouse ? Theme.accent : Theme.fgDim)
                                                }

                                                Text {
                                                    Layout.fillWidth: true
                                                    text: modelData.label || ""
                                                    font.family: "JetBrainsMono Nerd Font"
                                                    font.pixelSize: Theme.fontPx(7.5)
                                                    font.weight: modelData.danger ? Font.Bold : Font.Normal
                                                    color: modelData.danger ? Theme.err : (actMA.containsMouse ? Theme.fg : Theme.fgDim)
                                                    elide: Text.ElideRight
                                                }
                                            }

                                            MouseArea {
                                                id: actMA
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.executeAction(modelData, appItemDelegate.modelData)
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
}
