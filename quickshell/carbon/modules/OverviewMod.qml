import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import M3Shapes
import "../Singletons"

/**
 * OverviewMod: macOS Mission Control & Windows Task View style animated
 * workspaces & windows overview.
 * Displays all workspaces horizontally with their open applications,
 * live status, window preview cards, and cascading spring emergence animations.
 */
Item {
    id: root

    property bool open: false
    signal requestClose()

    readonly property bool animatingOut: !root.open && root.opacity > 0.001

    /* Keyboard navigation */
    focus: root.open
    Keys.onEscapePressed: root.requestClose()

    /* ── Live Data Acquisition ────────────────────────────────────────── */
    property var workspacesList: []
    property int activeWsId: 1
    property int selectedIndex: 0

    Process {
        id: dataProbe
        command: [(Quickshell.env("HOME") || "") + "/.config/hypr/scripts/carbon-overview-data.py"]
        stdout: StdioCollector {
            id: dataCol
            waitForEnd: true
        }
        onExited: {
            try {
                const txt = String(dataCol.text).trim()
                if (txt.length > 0) {
                    const parsed = JSON.parse(txt)
                    root.activeWsId = parsed.activeWorkspace || 1
                    root.workspacesList = parsed.workspaces || []
                    for (let i = 0; i < root.workspacesList.length; i++) {
                        if (root.workspacesList[i].id === root.activeWsId) {
                            root.selectedIndex = i
                            break
                        }
                    }
                }
            } catch (e) {
                console.log("Overview data parse error:", e)
            }
        }
    }

    Timer {
        id: refreshTimer
        interval: 1000
        repeat: true
        running: root.open
        onTriggered: {
            if (!dataProbe.running) dataProbe.running = true
        }
    }

    Process {
        id: moveProc
        onExited: {
            refreshTimer.restart()
            if (!dataProbe.running) dataProbe.running = true
        }
    }

    onOpenChanged: {
        root.cancelDrag()
        if (root.open) {
            if (!dataProbe.running) dataProbe.running = true
            animProgress.restart()
            root.forceActiveFocus()
        }
    }

    /* ── Drag & Drop Window Between Workspaces ─────────────────────────── */
    property bool isDragging: false
    property var draggingWindow: null // { address, title, class, appName, icon, sourceWsId }
    property real dragX: 0
    property real dragY: 0
    property int hoveredTargetWsId: -1
    property bool hoveredNewWs: false

    function startDrag(winData, srcWsId, startX, startY) {
        root.draggingWindow = {
            address: winData.address,
            title: winData.title || "",
            class: winData.class || "",
            appName: winData.appName || winData.class || "App",
            icon: winData.icon || winData.class || "",
            sourceWsId: srcWsId
        }
        root.dragX = startX
        root.dragY = startY
        root.hoveredTargetWsId = -1
        root.hoveredNewWs = false
        root.isDragging = true
    }

    function updateDrag(gx, gy) {
        root.dragX = gx
        root.dragY = gy

        // Check if hovering over "+ New Workspace" button
        if (typeof addBtn !== "undefined" && addBtn) {
            let newBtnPt = addBtn.mapFromItem(root, gx, gy)
            if (newBtnPt.x >= 0 && newBtnPt.x <= addBtn.width && newBtnPt.y >= 0 && newBtnPt.y <= addBtn.height) {
                root.hoveredNewWs = true
                root.hoveredTargetWsId = -1
                return
            }
        }
        root.hoveredNewWs = false

        // Check cards
        let targetId = -1
        if (typeof cardsRepeater !== "undefined" && cardsRepeater) {
            for (let i = 0; i < cardsRepeater.count; i++) {
                let item = cardsRepeater.itemAt(i)
                if (item) {
                    let pt = item.mapFromItem(root, gx, gy)
                    if (pt.x >= 0 && pt.x <= item.width && pt.y >= 0 && pt.y <= item.height) {
                        if (root.workspacesList[i] && root.workspacesList[i].id !== root.draggingWindow.sourceWsId) {
                            targetId = root.workspacesList[i].id
                        }
                        break
                    }
                }
            }
        }
        root.hoveredTargetWsId = targetId
    }

    function endDrag(gx, gy) {
        if (!root.isDragging || !root.draggingWindow) {
            root.cancelDrag()
            return
        }

        let addr = root.draggingWindow.address
        let srcWs = root.draggingWindow.sourceWsId

        if (root.hoveredNewWs) {
            let maxId = 1
            for (let i = 0; i < root.workspacesList.length; i++) {
                if (root.workspacesList[i].id > maxId) maxId = root.workspacesList[i].id
            }
            root.moveWindowToWorkspace(addr, maxId + 1)
        } else if (root.hoveredTargetWsId !== -1 && root.hoveredTargetWsId !== srcWs) {
            root.moveWindowToWorkspace(addr, root.hoveredTargetWsId)
        }

        root.cancelDrag()
    }

    function cancelDrag() {
        root.isDragging = false
        root.draggingWindow = null
        root.hoveredTargetWsId = -1
        root.hoveredNewWs = false
    }

    function moveWindowToWorkspace(addr, targetWid) {
        let dispatchCmd = "hl.dsp.window.move({ workspace = " + targetWid + ", window = 'address:" + addr + "' })"
        Hyprland.dispatch(dispatchCmd)

        moveProc.command = ["hyprctl", "dispatch", dispatchCmd]
        moveProc.running = true

        // Optimistic UI update: move window between workspaces in root.workspacesList
        let foundWin = null
        let newWorkspaces = JSON.parse(JSON.stringify(root.workspacesList))
        for (let i = 0; i < newWorkspaces.length; i++) {
            let ws = newWorkspaces[i]
            let idx = ws.windows ? ws.windows.findIndex(w => w.address === addr) : -1
            if (idx !== -1) {
                foundWin = ws.windows.splice(idx, 1)[0]
                break
            }
        }
        if (foundWin) {
            let targetWs = newWorkspaces.find(w => w.id === targetWid)
            if (targetWs) {
                if (!targetWs.windows) targetWs.windows = []
                targetWs.windows.push(foundWin)
            } else {
                newWorkspaces.push({
                    id: targetWid,
                    name: "Workspace " + targetWid,
                    isActive: targetWid === root.activeWsId,
                    windows: [foundWin]
                })
                newWorkspaces.sort((a, b) => a.id - b.id)
            }
            root.workspacesList = newWorkspaces
        }
    }

    function getShapeForWs(wsId) {
        switch (wsId) {
            case 1: return MaterialShape.Clover4Leaf
            case 2: return MaterialShape.Sunny
            case 3: return MaterialShape.Flower
            case 4: return MaterialShape.Heart
            case 5: return MaterialShape.Gem
            case 6: return MaterialShape.Diamond
            case 7: return MaterialShape.Cookie4Sided
            case 8: return MaterialShape.SoftBurst
            case 9: return MaterialShape.Boom
            case 10: return MaterialShape.Ghostish
            default: return MaterialShape.Circle
        }
    }

    function jumpToWorkspace(wid) {
        Hyprland.dispatch("hl.dsp.focus({ workspace = \"" + wid + "\" })")
        root.requestClose()
    }

    function focusWindow(wid, addr) {
        Hyprland.dispatch("hl.dsp.focus({ workspace = \"" + wid + "\" })")
        Hyprland.dispatch("hl.dsp.focus({ window = \"address:" + addr + "\" })")
        root.requestClose()
    }

    function closeWindow(addr) {
        Hyprland.dispatch("hl.dsp.window.close({ window = \"address:" + addr + "\" })")
        refreshTimer.restart()
        if (!dataProbe.running) dataProbe.running = true
    }

    /* ── Entrance & Exit Animation Driver ─────────────────────────────── */
    property real enterProgress: 0.0
    NumberAnimation {
        id: animProgress
        target: root
        property: "enterProgress"
        from: 0.0
        to: 1.0
        duration: 480
        easing.type: Easing.OutBack
        easing.overshoot: 1.25
    }

    opacity: root.open ? 1.0 : 0.0
    Behavior on opacity {
        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
    }

    /* ── Backdrop Dimmer & Glass ──────────────────────────────────────── */
    Rectangle {
        id: backdrop
        anchors.fill: parent
        color: "#B208080A"

        MouseArea {
            anchors.fill: parent
            onClicked: root.requestClose()
        }
    }

    /* ── Top Header Bar ───────────────────────────────────────────────── */
    Item {
        id: header
        anchors.top: parent.top
        anchors.topMargin: 40
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(parent.width - 80, 1100)
        height: 60

        opacity: root.enterProgress
        transform: Translate {
            y: (1.0 - root.enterProgress) * -20
        }

        RowLayout {
            anchors.fill: parent
            spacing: 16

            /* Logo & Title */
            RowLayout {
                spacing: 12
                Rectangle {
                    width: 38
                    height: 38
                    radius: 19
                    color: Theme.accent

                    Text {
                        anchors.centerIn: parent
                        text: ""
                        font.family: Theme.font
                        font.pixelSize: Theme.fontPx(18)
                        color: Theme.isDark ? "#111111" : "#ffffff"
                    }
                }

                ColumnLayout {
                    spacing: 2
                    Text {
                        text: "Workspaces & Tasks"
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: Theme.fontPx(20)
                        font.weight: Font.Bold
                        color: Theme.fg
                    }
                    Text {
                        text: "Active Workspace " + root.activeWsId + " • Swipe down or ESC to dismiss"
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: Theme.fontPx(12)
                        color: Theme.fgDim
                    }
                }
            }

            Item { Layout.fillWidth: true }

            /* Action Buttons */
            RowLayout {
                spacing: 10

                /* Add Workspace Button */
                Rectangle {
                    id: addBtn
                    implicitWidth: addRow.implicitWidth + 24
                    implicitHeight: 36
                    radius: 18
                    color: (root.isDragging && root.hoveredNewWs) ? Theme.accent : (addMouse.containsMouse ? Theme.bgActive : Theme.bgAlt)
                    border.color: (root.isDragging && root.hoveredNewWs) ? Theme.accent : (addMouse.containsMouse ? Theme.accent : Theme.outline)
                    border.width: (root.isDragging && root.hoveredNewWs) ? 2 : 1
                    scale: (root.isDragging && root.hoveredNewWs) ? 1.08 : 1.0

                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                    Behavior on color { ColorAnimation { duration: 150 } }
                    Behavior on border.color { ColorAnimation { duration: 150 } }

                    RowLayout {
                        id: addRow
                        anchors.centerIn: parent
                        spacing: 8
                        Text {
                            text: "+"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: Theme.fontPx(18)
                            font.weight: Font.Bold
                            color: (root.isDragging && root.hoveredNewWs) ? (Theme.isDark ? "#111111" : "#ffffff") : Theme.accent
                        }
                        Text {
                            text: (root.isDragging && root.hoveredNewWs) ? "Drop to Move Here" : "New Workspace"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: Theme.fontPx(13)
                            font.weight: Font.DemiBold
                            color: (root.isDragging && root.hoveredNewWs) ? (Theme.isDark ? "#111111" : "#ffffff") : Theme.fg
                        }
                    }

                    MouseArea {
                        id: addMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            let maxId = 1
                            for (let i = 0; i < root.workspacesList.length; i++) {
                                if (root.workspacesList[i].id > maxId) maxId = root.workspacesList[i].id
                            }
                            root.jumpToWorkspace(maxId + 1)
                        }
                    }
                }

                /* Close Button */
                Rectangle {
                    width: 36
                    height: 36
                    radius: 18
                    color: closeMouse.containsMouse ? Theme.err : Theme.bgAlt
                    border.color: closeMouse.containsMouse ? Theme.err : Theme.outline
                    border.width: 1

                    Behavior on color { ColorAnimation { duration: 150 } }

                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        font.pixelSize: Theme.fontPx(13)
                        font.weight: Font.Bold
                        color: closeMouse.containsMouse ? "#ffffff" : Theme.fg
                    }

                    MouseArea {
                        id: closeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.requestClose()
                    }
                }
            }
        }
    }

    /* ── Workspaces Carousel List ─────────────────────────────────────── */
    Flickable {
        id: carousel
        anchors.top: header.bottom
        anchors.topMargin: 30
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 40
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(parent.width - 60, cardsRow.implicitWidth)
        contentWidth: cardsRow.implicitWidth
        contentHeight: height
        clip: false
        boundsBehavior: Flickable.StopAtBounds

        Row {
            id: cardsRow
            spacing: 24
            anchors.verticalCenter: parent.verticalCenter

            Repeater {
                id: cardsRepeater
                model: root.workspacesList

                delegate: Item {
                    id: cardDelegate
                    required property var modelData
                    required property int index

                    readonly property bool isCurrent: modelData.id === root.activeWsId
                    readonly property var winList: modelData.windows || []
                    readonly property bool isDropTarget: root.isDragging && root.hoveredTargetWsId === modelData.id

                    /* Card Dimensions */
                    width: 320
                    height: Math.min(carousel.height - 20, 460)

                    /* Cascading staggered animation */
                    readonly property real cardDelay: Math.min(index * 0.08, 0.4)
                    readonly property real cardProgress: Math.max(0.0, Math.min(1.0, (root.enterProgress - cardDelay) / (1.0 - cardDelay + 0.0001)))

                    opacity: cardProgress
                    scale: 0.88 + 0.12 * cardProgress
                    transform: Translate {
                        y: (1.0 - cardProgress) * 60 + (cardHover.hovered ? -8 : 0)
                        Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    }

                    /* Outer Card Body */
                    Rectangle {
                        id: cardBody
                        anchors.fill: parent
                        radius: 20
                        color: cardDelegate.isDropTarget ? Theme.bgActive : Theme.bg
                        border.color: cardDelegate.isDropTarget ? Theme.accent : (cardDelegate.isCurrent ? Theme.accent : (cardHover.hovered ? Theme.accentLit : Theme.outline))
                        border.width: cardDelegate.isDropTarget ? 2.5 : (cardDelegate.isCurrent ? 2 : 1)
                        scale: cardDelegate.isDropTarget ? 1.03 : 1.0

                        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
                        Behavior on border.color { ColorAnimation { duration: 180 } }
                        Behavior on color { ColorAnimation { duration: 160 } }

                        /* Shadow Layer */
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            shadowEnabled: true
                            shadowColor: cardDelegate.isCurrent ? Theme.accent : "#000000"
                            shadowOpacity: cardDelegate.isCurrent ? 0.35 : (cardHover.hovered ? 0.45 : 0.25)
                            shadowBlur: cardDelegate.isCurrent ? 0.7 : (cardHover.hovered ? 0.8 : 0.5)
                            shadowVerticalOffset: cardHover.hovered ? 12 : 6
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 18
                            spacing: 14

                            /* ── Card Header ────────────────────────── */
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                /* Geometric Shape for this workspace */
                                Item {
                                    width: 32
                                    height: 32

                                    MaterialShape {
                                        anchors.fill: parent
                                        shape: root.getShapeForWs(modelData.id)
                                        color: cardDelegate.isCurrent ? Theme.accent : Theme.bgHover
                                        strokeColor: Theme.accent
                                        strokeWidth: 1.2
                                        animationDuration: 250
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        text: String(modelData.id)
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: Theme.fontPx(13)
                                        font.weight: Font.Bold
                                        color: cardDelegate.isCurrent ? (Theme.isDark ? "#111111" : "#ffffff") : Theme.fg
                                    }
                                }

                                ColumnLayout {
                                    spacing: 1
                                    Layout.fillWidth: true
                                    Text {
                                        text: modelData.name || ("Workspace " + modelData.id)
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: Theme.fontPx(15)
                                        font.weight: Font.Bold
                                        color: Theme.fg
                                    }
                                    Text {
                                        text: cardDelegate.winList.length > 0 ? (cardDelegate.winList.length + (cardDelegate.winList.length === 1 ? " application" : " applications")) : "Empty"
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: Theme.fontPx(11)
                                        color: Theme.fgDim
                                    }
                                }

                                /* ACTIVE Tag */
                                Rectangle {
                                    visible: cardDelegate.isCurrent
                                    implicitWidth: activeTagRow.implicitWidth + 14
                                    implicitHeight: 22
                                    radius: 11
                                    color: Theme.accent

                                    RowLayout {
                                        id: activeTagRow
                                        anchors.centerIn: parent
                                        spacing: 4
                                        Rectangle {
                                            width: 5
                                            height: 5
                                            radius: 2.5
                                            color: Theme.isDark ? "#111111" : "#ffffff"
                                        }
                                        Text {
                                            text: "ACTIVE"
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: Theme.fontPx(9)
                                            font.weight: Font.Black
                                            color: Theme.isDark ? "#111111" : "#ffffff"
                                        }
                                    }
                                }
                            }

                            /* Divider */
                            Rectangle {
                                Layout.fillWidth: true
                                height: 1
                                color: Theme.outline
                                opacity: 0.6
                            }

                            /* ── Window Preview Cards List ──────────── */
                            Flickable {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                contentHeight: winColumn.implicitHeight
                                clip: true
                                boundsBehavior: Flickable.StopAtBounds

                                Column {
                                    id: winColumn
                                    width: parent.width
                                    spacing: 8

                                    Repeater {
                                        model: cardDelegate.winList

                                        delegate: Rectangle {
                                            id: winTile
                                            required property var modelData
                                            required property int index

                                            readonly property bool isBeingDragged: root.isDragging && root.draggingWindow && root.draggingWindow.address === modelData.address

                                            width: winColumn.width
                                            height: 64
                                            radius: 12
                                            MouseArea {
                                                id: winMouse
                                                anchors.fill: parent
                                                hoverEnabled: !root.isDragging
                                                cursorShape: root.isDragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor

                                                property bool dragActive: false
                                                property real pressX: 0
                                                property real pressY: 0

                                                onPressed: (mouse) => {
                                                    dragActive = false
                                                    pressX = mouse.x
                                                    pressY = mouse.y
                                                }

                                                onPositionChanged: (mouse) => {
                                                    if (pressed) {
                                                        let dx = mouse.x - pressX
                                                        let dy = mouse.y - pressY
                                                        let distSq = dx * dx + dy * dy
                                                        if (!dragActive && distSq > 64) {
                                                            dragActive = true
                                                            let pt = winMouse.mapToItem(root, mouse.x, mouse.y)
                                                            root.startDrag(modelData, cardDelegate.modelData.id, pt.x, pt.y)
                                                        }
                                                        if (dragActive) {
                                                            let pt = winMouse.mapToItem(root, mouse.x, mouse.y)
                                                            root.updateDrag(pt.x, pt.y)
                                                        }
                                                    }
                                                }

                                                onReleased: (mouse) => {
                                                    if (dragActive) {
                                                        dragActive = false
                                                        let pt = winMouse.mapToItem(root, mouse.x, mouse.y)
                                                        root.endDrag(pt.x, pt.y)
                                                    } else {
                                                        root.focusWindow(cardDelegate.modelData.id, modelData.address)
                                                    }
                                                }

                                                onCanceled: {
                                                    if (dragActive) {
                                                        dragActive = false
                                                        root.cancelDrag()
                                                    }
                                                }
                                            }

                                            color: isBeingDragged ? Theme.bgAlt : (winMouse.containsMouse ? Theme.bgHover : Theme.bgAlt)
                                            border.color: isBeingDragged ? Theme.accent : (winMouse.containsMouse ? Theme.accent : Theme.outline)
                                            border.width: isBeingDragged ? 1.5 : (winMouse.containsMouse ? 1.5 : 1)
                                            opacity: isBeingDragged ? 0.35 : 1.0

                                            scale: isBeingDragged ? 0.96 : (winMouse.containsMouse ? 1.025 : 1.0)
                                            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutQuad } }
                                            Behavior on opacity { NumberAnimation { duration: 140 } }
                                            Behavior on color { ColorAnimation { duration: 140 } }
                                            Behavior on border.color { ColorAnimation { duration: 140 } }

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.margins: 10
                                                spacing: 12

                                                /* App Icon */
                                                Image {
                                                    width: 32
                                                    height: 32
                                                    source: Quickshell.iconPath(modelData.icon || modelData.class, "application-x-executable")
                                                    sourceSize: Qt.size(32, 32)
                                                    fillMode: Image.PreserveAspectFit
                                                }

                                                /* Window Title & Class */
                                                ColumnLayout {
                                                    Layout.fillWidth: true
                                                    spacing: 2

                                                    Text {
                                                        text: modelData.appName || modelData.class
                                                        font.family: "JetBrainsMono Nerd Font"
                                                        font.pixelSize: Theme.fontPx(13)
                                                        font.weight: Font.Bold
                                                        color: Theme.fg
                                                        elide: Text.ElideRight
                                                        Layout.fillWidth: true
                                                    }

                                                    Text {
                                                        text: modelData.title || ""
                                                        font.family: "JetBrainsMono Nerd Font"
                                                        font.pixelSize: Theme.fontPx(11)
                                                        color: Theme.fgDim
                                                        elide: Text.ElideRight
                                                        Layout.fillWidth: true
                                                    }
                                                }

                                                /* Close Window Button */
                                                Rectangle {
                                                    width: 24
                                                    height: 24
                                                    radius: 12
                                                    color: winCloseMouse.containsMouse ? Theme.err : "transparent"
                                                    opacity: winMouse.containsMouse ? 1.0 : 0.0
                                                    Behavior on opacity { NumberAnimation { duration: 120 } }
                                                    Behavior on color { ColorAnimation { duration: 120 } }

                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: "✕"
                                                        font.pixelSize: Theme.fontPx(10)
                                                        font.weight: Font.Bold
                                                        color: winCloseMouse.containsMouse ? "#ffffff" : Theme.fgDim
                                                    }

                                                    MouseArea {
                                                        id: winCloseMouse
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: root.closeWindow(modelData.address)
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    /* Empty State */
                                    Item {
                                        visible: cardDelegate.winList.length === 0
                                        width: winColumn.width
                                        height: 160

                                        ColumnLayout {
                                            anchors.centerIn: parent
                                            spacing: 8

                                            Text {
                                                Layout.alignment: Qt.AlignHCenter
                                                text: ""
                                                font.family: Theme.font
                                                font.pixelSize: Theme.fontPx(32)
                                                color: Theme.fgFaint
                                            }

                                            Text {
                                                Layout.alignment: Qt.AlignHCenter
                                                text: "No open applications"
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: Theme.fontPx(13)
                                                font.weight: Font.DemiBold
                                                color: Theme.fgDim
                                            }

                                            Text {
                                                Layout.alignment: Qt.AlignHCenter
                                                text: "Click to switch here"
                                                font.family: "JetBrainsMono Nerd Font"
                                                font.pixelSize: Theme.fontPx(11)
                                                color: Theme.fgFaint
                                            }
                                        }
                                    }
                                }
                            }

                            /* ── Bottom Switch Button ───────────────── */
                            Rectangle {
                                Layout.fillWidth: true
                                height: 38
                                radius: 10
                                color: cardDelegate.isCurrent ? Theme.bgHover : (switchMouse.containsMouse ? Theme.accent : Theme.bgAlt)
                                border.color: switchMouse.containsMouse ? Theme.accent : Theme.outline
                                border.width: 1

                                Behavior on color { ColorAnimation { duration: 150 } }

                                Text {
                                    anchors.centerIn: parent
                                    text: cardDelegate.isCurrent ? "Current Workspace" : "Switch to Workspace " + cardDelegate.modelData.id
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: Theme.fontPx(12)
                                    font.weight: Font.Bold
                                    color: switchMouse.containsMouse && !cardDelegate.isCurrent ? (Theme.isDark ? "#111111" : "#ffffff") : Theme.fg
                                }

                                MouseArea {
                                    id: switchMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: cardDelegate.isCurrent ? Qt.ArrowCursor : Qt.PointingHandCursor
                                    onClicked: root.jumpToWorkspace(cardDelegate.modelData.id)
                                }
                            }
                        }

                        MouseArea {
                            id: cardBodyMouse
                            anchors.fill: parent
                            z: -1
                            hoverEnabled: true
                            cursorShape: cardDelegate.isCurrent ? Qt.ArrowCursor : Qt.PointingHandCursor
                            onClicked: root.jumpToWorkspace(cardDelegate.modelData.id)
                        }

                        /* Drop Target Overlay */
                        Rectangle {
                            anchors.fill: parent
                            radius: 20
                            color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14)
                            border.color: Theme.accent
                            border.width: 2.5
                            visible: cardDelegate.isDropTarget
                            z: 200

                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 10

                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: "Move " + (root.draggingWindow ? root.draggingWindow.appName : "Window")
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: Theme.fontPx(16)
                                    font.weight: Font.Bold
                                    color: Theme.fg
                                }

                                Rectangle {
                                    Layout.alignment: Qt.AlignHCenter
                                    implicitWidth: dropBadgeText.implicitWidth + 24
                                    implicitHeight: 28
                                    radius: 14
                                    color: Theme.accent

                                    Text {
                                        id: dropBadgeText
                                        anchors.centerIn: parent
                                        text: "Workspace " + cardDelegate.modelData.id
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: Theme.fontPx(12)
                                        font.weight: Font.Black
                                        color: Theme.isDark ? "#111111" : "#ffffff"
                                    }
                                }
                            }
                        }
                    }

                    HoverHandler { id: cardHover }
                }
            }
        }
    }

    /* ── Floating Drag Ghost (Top Layer) ─────────────────────────────── */
    Item {
        id: dragGhost
        visible: root.isDragging
        z: 9999
        x: root.dragX - width / 2
        y: root.dragY - height / 2
        width: 300
        height: 68

        Rectangle {
            anchors.fill: parent
            radius: 14
            color: Theme.bgActive
            border.color: (root.hoveredTargetWsId !== -1 || root.hoveredNewWs) ? Theme.accent : Theme.outline
            border.width: 2
            scale: 1.05
            rotation: 2.5
            opacity: 0.96

            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: (root.hoveredTargetWsId !== -1 || root.hoveredNewWs) ? Theme.accent : "#000000"
                shadowOpacity: 0.65
                shadowBlur: 0.8
                shadowVerticalOffset: 12
            }

            RowLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 12

                Image {
                    width: 34
                    height: 34
                    source: root.draggingWindow ? Quickshell.iconPath(root.draggingWindow.icon || root.draggingWindow.class, "application-x-executable") : ""
                    sourceSize: Qt.size(34, 34)
                    fillMode: Image.PreserveAspectFit
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    Text {
                        text: root.draggingWindow ? (root.draggingWindow.appName || root.draggingWindow.class) : ""
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: Theme.fontPx(13)
                        font.weight: Font.Bold
                        color: Theme.fg
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    Text {
                        text: root.hoveredNewWs ? "Release to move to New Workspace" :
                              (root.hoveredTargetWsId !== -1 ? ("Drop into Workspace " + root.hoveredTargetWsId) :
                              ("Moving from Workspace " + (root.draggingWindow ? root.draggingWindow.sourceWsId : "")))
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: Theme.fontPx(11)
                        font.weight: (root.hoveredTargetWsId !== -1 || root.hoveredNewWs) ? Font.Bold : Font.Normal
                        color: (root.hoveredTargetWsId !== -1 || root.hoveredNewWs) ? Theme.accent : Theme.fgDim
                    }
                }
            }
        }
    }
}
