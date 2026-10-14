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
 * and system tray applets (Discord, Antigravity, Zen, GPU Screen Recorder, EasyEffects, etc.).
 * Pops up when the user clicks the small up-arrow chevron in the bar.
 * Left-click activates / switches to the app window.
 * Right-click opens a tailored contextual options menu with app-specific features
 * and a compulsory Quit / Close button.
 */
Item {
    id: root

    property bool open: false
    property string barEdge: "top"
    property bool hovered: hoverHandler.hovered
    property var selectedApp: null
    signal requestedClose()

    clip: true

    focus: root.open
    Keys.enabled: root.open
    Keys.onEscapePressed: (event) => {
        if (root.selectedApp !== null) {
            root.selectedApp = null
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
            root.selectedApp = null
            if (!bgAppsProbe.running) bgAppsProbe.running = true
            root.animatingOut = false
            animatingOutTimer.stop()
        } else {
            root.selectedApp = null
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

        // Add Background applications (GPU Screen Recorder, EasyEffects, Discord, etc.)
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

                list.push({
                    isSni: false,
                    rawItem: app,
                    name: app.name || app.title || "App",
                    sub: app.hasWindow ? ("Workspace " + app.workspace) : (app.category ? (app.category.charAt(0).toUpperCase() + app.category.slice(1)) : "Background Process"),
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

    readonly property int columns: 4
    readonly property int rows: Math.max(1, Math.ceil(allItems.length / columns))

    implicitWidth: 216
    implicitHeight: {
        if (root.selectedApp) {
            var acts = root.selectedApp.actions || []
            var count = Math.max(1, acts.length)
            return Math.min(320, Math.max(160, count * 32 + 66))
        }
        return (allItems.length === 0) ? 74 : (rows * 38 + 58)
    }

    Behavior on implicitHeight {
        NumberAnimation { duration: 180; easing.bezierCurve: Theme.animCurves.expressiveDefaultSpatial }
    }
    Behavior on implicitWidth {
        NumberAnimation { duration: 180; easing.bezierCurve: Theme.animCurves.expressiveDefaultSpatial }
    }

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

        // 1. If action specifies a direct shell command (cmd):
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
            root.selectedApp = null
            root.requestedClose()
            return
        }
        else if (act.action === "movetoworkspace") {
            if (app.hasWindow && app.address) {
                Quickshell.execDetached(["hyprctl", "dispatch", "movetoworkspace", "+0,address:" + app.address])
                Quickshell.execDetached(["hyprctl", "dispatch", "focuswindow", "address:" + app.address])
            }
            root.selectedApp = null
            root.requestedClose()
            return
        }
        else if (act.action === "togglefloating") {
            if (app.hasWindow && app.address) {
                Quickshell.execDetached(["hyprctl", "dispatch", "togglefloating", "address:" + app.address])
            }
            root.selectedApp = null
            root.requestedClose()
            return
        }
        // 3. Compulsory close / quit:
        else if (act.action === "close") {
            if (app.hasWindow && app.address) {
                Quickshell.execDetached(["hyprctl", "dispatch", "closewindow", "address:" + app.address])
            }
            if (app.pid) {
                Quickshell.execDetached(["kill", String(app.pid)])
            }
            if (app.class && (app.class.includes("gpu_screen_recorder") || app.class.includes("gpu-screen-recorder"))) {
                Quickshell.execDetached(["sh", "-c", "pkill -f gpu-screen-recorder; flatpak kill com.dec05eba.gpu_screen_recorder 2>/dev/null"])
            }
            root.selectedApp = null
            root.requestedClose()
            bgRefreshTimer.restart()
            if (!bgAppsProbe.running) bgAppsProbe.running = true
            return
        }
        // 4. Native SNI actions:
        else if (act.action === "sniActivate") {
            if (app.rawItem) app.rawItem.activate()
            root.selectedApp = null
            root.requestedClose()
            return
        }
        else if (act.action === "sniMenu") {
            if (app.rawItem && app.rawItem.hasMenu) {
                app.rawItem.openMenu(0, 0)
            } else if (app.rawItem) {
                app.rawItem.secondaryActivate()
            }
            root.selectedApp = null
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
            root.selectedApp = null
            root.requestedClose()
            bgRefreshTimer.restart()
            return
        }

        // Close after executing danger / quit actions
        if (act.danger) {
            root.selectedApp = null
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

        /* ── VIEW A: Apps Grid (when selectedApp === null) ── */
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            anchors.leftMargin: root.barMode === "notch" ? 22 : 10
            spacing: 6
            visible: root.selectedApp === null

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
                        font.pixelSize: Theme.fontPx(9.5)
                        font.weight: Font.Bold
                        color: Theme.fg
                        elide: Text.ElideRight
                        width: parent.width
                    }

                    Text {
                        text: root.hoveredAppSub ? root.hoveredAppSub : (root.allItems.length + " running")
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: Theme.fontPx(7.5)
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
                    spacing: 8
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
                                id: appImg
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

                            Text {
                                anchors.centerIn: parent
                                visible: appImg.status !== Image.Ready
                                text: "widgets"
                                font.family: Theme.fontIcon
                                font.pixelSize: 16
                                color: Theme.accent
                            }

                            MouseArea {
                                id: slotMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                cursorShape: Qt.PointingHandCursor
                                onClicked: (mouse) => {
                                    if (mouse.button === Qt.RightButton) {
                                        // Right Click: Open contextual options menu
                                        root.selectedApp = slot.modelData
                                    } else {
                                        // Left Click: Default quick activate action
                                        if (slot.modelData.isSni) {
                                            slot.modelData.rawItem.activate()
                                            root.requestedClose()
                                        } else {
                                            var app = slot.modelData
                                            if (app.hasWindow && app.address) {
                                                if (app.workspace > 0) {
                                                    Quickshell.execDetached(["hyprctl", "dispatch", "workspace", String(app.workspace)])
                                                }
                                                Quickshell.execDetached(["hyprctl", "dispatch", "focuswindow", "address:" + app.address])
                                                root.requestedClose()
                                            } else {
                                                if (app.exec) {
                                                    Quickshell.execDetached(["sh", "-c", app.exec])
                                                    root.requestedClose()
                                                } else {
                                                    // Open options menu if no direct window/exec
                                                    root.selectedApp = app
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

        /* ── VIEW B: App Context Options Menu (when selectedApp !== null) ── */
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            anchors.leftMargin: root.barMode === "notch" ? 22 : 10
            spacing: 6
            visible: root.selectedApp !== null

            // Header: Back button, App Icon, App Name & Subtitle, Close
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Rectangle {
                    width: 22
                    height: 22
                    radius: 11
                    color: backMA.containsMouse ? Theme.bgHover : Qt.rgba(1, 1, 1, 0.06)
                    border.width: 1
                    border.color: backMA.containsMouse ? Theme.accent : Theme.outline

                    Text {
                        anchors.centerIn: parent
                        text: "arrow_back"
                        font.family: Theme.fontIcon
                        font.pixelSize: 12
                        color: backMA.containsMouse ? Theme.accent : Theme.fgDim
                    }

                    MouseArea {
                        id: backMA
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.selectedApp = null
                    }
                }

                Image {
                    id: selAppImg
                    width: 20
                    height: 20
                    source: {
                        if (!root.selectedApp) return ""
                        if (root.selectedApp.isSni) {
                            return root.selectedApp.rawItem.icon || ""
                        } else {
                            return root.selectedApp.iconPath || Quickshell.iconPath(root.selectedApp.icon, "application-x-executable")
                        }
                    }
                    sourceSize: Qt.size(20, 20)
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                }

                Column {
                    Layout.fillWidth: true
                    spacing: 0

                    Text {
                        text: root.selectedApp ? root.selectedApp.name : ""
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: Theme.fontPx(9)
                        font.weight: Font.Bold
                        color: Theme.fg
                        elide: Text.ElideRight
                        width: parent.width
                    }

                    Text {
                        text: root.selectedApp ? (root.selectedApp.sub || "Options") : ""
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: Theme.fontPx(7)
                        color: Theme.accentLit
                        elide: Text.ElideRight
                        width: parent.width
                    }
                }

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
                        onClicked: root.selectedApp = null
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.08)
            }

            // Context Actions List
            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: width
                contentHeight: actCol.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: actCol
                    width: parent.width
                    spacing: 4

                    Repeater {
                        model: (root.selectedApp && root.selectedApp.actions) ? root.selectedApp.actions : []
                        delegate: Rectangle {
                            id: actBtn
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredHeight: 28
                            radius: 8
                            color: modelData.danger ? (actBtnMA.containsMouse ? Qt.rgba(Theme.err.r, Theme.err.g, Theme.err.b, 0.22) : Qt.rgba(Theme.err.r, Theme.err.g, Theme.err.b, 0.08)) : (actBtnMA.containsMouse ? Theme.bgHover : Qt.rgba(1, 1, 1, 0.04))
                            border.width: 1
                            border.color: modelData.danger ? Qt.rgba(Theme.err.r, Theme.err.g, Theme.err.b, 0.40) : (actBtnMA.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.35) : Theme.outline)

                            Behavior on color { ColorAnimation { duration: 100 } }
                            Behavior on border.color { ColorAnimation { duration: 100 } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 8

                                Text {
                                    text: modelData.icon || (modelData.danger ? "close" : "play_arrow")
                                    font.family: Theme.fontIcon
                                    font.pixelSize: 13
                                    color: modelData.danger ? Theme.err : (actBtnMA.containsMouse ? Theme.accent : Theme.fgDim)
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.label || ""
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: Theme.fontPx(8)
                                    font.weight: modelData.danger ? Font.Bold : Font.Normal
                                    color: modelData.danger ? Theme.err : (actBtnMA.containsMouse ? Theme.fg : Theme.fgDim)
                                    elide: Text.ElideRight
                                }
                            }

                            MouseArea {
                                id: actBtnMA
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.executeAction(modelData, root.selectedApp)
                            }
                        }
                    }
                }
            }
        }
    }
}
