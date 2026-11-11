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

    readonly property string scriptPath: (Quickshell.env("CARBON_CONFIG_DIR") || ((Quickshell.env("HOME") || "") + "/.config/carbon")) + "/scripts/carbon-default-apps.py"

    property var defaultApps: []
    property var allApps: []
    property bool isLoaded: false

    // App Browser Modal state
    property string browseCategory: ""
    property string browseCategoryTitle: ""
    property string appSearchQuery: ""

    function refresh() {
        if (!loadProc.running) {
            loadProc.running = true
        }
    }

    function loadAllApps() {
        if (!allAppsProc.running) {
            allAppsProc.running = true
        }
    }

    function openAppBrowser(cat, title) {
        root.browseCategory = cat
        root.browseCategoryTitle = title
        root.appSearchQuery = ""
        if (root.allApps.length === 0) {
            root.loadAllApps()
        }
    }

    function closeAppBrowser() {
        root.browseCategory = ""
        root.browseCategoryTitle = ""
        root.appSearchQuery = ""
    }

    function setDefault(cat, appId) {
        // Optimistic UI update
        var updated = []
        var chosenName = appId
        for (var i = 0; i < root.defaultApps.length; i++) {
            var item = Object.assign({}, root.defaultApps[i])
            if (item.category === cat) {
                item.current = appId
                var found = false
                for (var j = 0; j < item.options.length; j++) {
                    if (item.options[j].id === appId) {
                        item.currentName = item.options[j].name
                        chosenName = item.options[j].name
                        found = true
                        break
                    }
                }
                // If chosen from all-apps browse and not in options, append it
                if (!found) {
                    for (var k = 0; k < root.allApps.length; k++) {
                        if (root.allApps[k].id === appId) {
                            chosenName = root.allApps[k].name
                            item.currentName = chosenName
                            item.options.push(root.allApps[k])
                            break
                        }
                    }
                }
            }
            updated.push(item)
        }
        root.defaultApps = updated

        root.describe("Default Application Changed", "Set " + chosenName + " as system default handler for " + cat + ".")

        // Dispatch backend script
        Quickshell.execDetached([root.scriptPath, "set", cat, appId])

        // Schedule delayed refresh to ensure all MIME associations sync
        refreshTimer.restart()
    }

    Timer {
        id: refreshTimer
        interval: 600
        repeat: false
        onTriggered: root.refresh()
    }

    Process {
        id: loadProc
        command: [root.scriptPath, "get"]
        stdout: StdioCollector {
            id: loadCollector
            waitForEnd: true
        }
        onExited: {
            try {
                var raw = loadCollector.text.trim()
                if (raw.length > 0) {
                    var data = JSON.parse(raw)
                    if (Array.isArray(data)) {
                        root.defaultApps = data
                        root.isLoaded = true
                    }
                }
            } catch(e) {}
        }
    }

    Process {
        id: allAppsProc
        command: [root.scriptPath, "all-apps"]
        stdout: StdioCollector {
            id: allAppsCollector
            waitForEnd: true
        }
        onExited: {
            try {
                var raw = allAppsCollector.text.trim()
                if (raw.length > 0) {
                    var data = JSON.parse(raw)
                    if (Array.isArray(data)) {
                        root.allApps = data
                    }
                }
            } catch(e) {}
        }
    }

    Process {
        id: pickFileProc
        command: [root.scriptPath, "pick-file", root.browseCategory]
        stdout: StdioCollector {
            id: pickCollector
            waitForEnd: true
        }
        onExited: {
            try {
                var raw = pickCollector.text.trim()
                if (raw.length > 0) {
                    var data = JSON.parse(raw)
                    if (data.status === "ok") {
                        root.closeAppBrowser()
                        root.refresh()
                    }
                }
            } catch(e) {}
        }
    }

    Component.onCompleted: {
        root.refresh()
        root.loadAllApps()
    }

    // Main Flickable Content
    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentCol.implicitHeight + Theme.px(64)
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        ColumnLayout {
            id: contentCol
            width: parent.width - Theme.px(48)
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: Theme.px(24)
            spacing: Theme.px(20)

            // Header Section
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.px(12)

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(2)

                    Text {
                        text: "DEFAULT APPLICATIONS // SYSTEM HANDLERS"
                        font.family: Theme.font
                        font.pixelSize: Theme.fontPx(11)
                        font.weight: Font.Bold
                        color: Qt.rgba(1, 1, 1, 0.45)
                    }

                    Text {
                        text: "Configure preferred applications for web browsing, file management, terminal, editing, and multimedia."
                        font.family: Theme.font
                        font.pixelSize: Theme.fontPx(11.5)
                        color: Qt.rgba(1, 1, 1, 0.55)
                    }
                }

                // Refresh Button
                Rectangle {
                    Layout.preferredWidth: Theme.px(32)
                    Layout.preferredHeight: Theme.px(32)
                    radius: Theme.px(6)
                    color: refMouse.pressed ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.25) : (refMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent")
                    border.color: refMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(1, 1, 1, 0.08)
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "󰑐"
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fontPx(13)
                        color: loadProc.running ? Theme.primary : Qt.rgba(1, 1, 1, 0.70)
                        RotationAnimator on rotation {
                            running: loadProc.running
                            from: 0
                            to: 360
                            loops: Animation.Infinite
                            duration: 800
                        }
                    }

                    MouseArea {
                        id: refMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: root.describe("Refresh Defaults", "Query system XDG MIME database and installed desktop entries.")
                        onExited: root.clearDesc()
                        ToolTip.visible: containsMouse
                        ToolTip.text: "Reload default applications"
                        ToolTip.delay: 300
                        onClicked: {
                            root.refresh()
                            root.loadAllApps()
                        }
                    }
                }
            }

            // Categories List
            Repeater {
                model: root.defaultApps

                delegate: Rectangle {
                    id: catCard
                    property var catItem: modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: colInner.implicitHeight + Theme.px(28)
                    radius: Theme.px(10)
                    color: Qt.rgba(0, 0, 0, 0.25)
                    border.color: Qt.rgba(1, 1, 1, 0.08)
                    border.width: 1

                    ColumnLayout {
                        id: colInner
                        anchors.fill: parent
                        anchors.margins: Theme.px(14)
                        spacing: Theme.px(12)

                        // Card Header
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.px(12)

                            // Icon circle
                            Rectangle {
                                Layout.preferredWidth: Theme.px(36)
                                Layout.preferredHeight: Theme.px(36)
                                radius: Theme.px(8)
                                color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12)
                                border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.25)
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: catItem.glyph || "󰀻"
                                    font.family: Theme.fontMono
                                    font.pixelSize: Theme.fontPx(17)
                                    color: Theme.primary
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Theme.px(1)

                                RowLayout {
                                    spacing: Theme.px(8)

                                    Text {
                                        text: catItem.title
                                        font.family: Theme.font
                                        font.pixelSize: Theme.fontPx(13.5)
                                        font.weight: Font.DemiBold
                                        color: Qt.rgba(1, 1, 1, 0.95)
                                    }

                                    // Category badge
                                    Rectangle {
                                        radius: Theme.px(4)
                                        Layout.preferredHeight: Theme.px(18)
                                        Layout.preferredWidth: catBadgeText.implicitWidth + Theme.px(10)
                                        color: Qt.rgba(1, 1, 1, 0.06)

                                        Text {
                                            id: catBadgeText
                                            anchors.centerIn: parent
                                            text: (catItem.category || "").toUpperCase()
                                            font.family: Theme.fontMono
                                            font.pixelSize: Theme.fontPx(8.5)
                                            font.weight: Font.Bold
                                            color: Qt.rgba(1, 1, 1, 0.50)
                                        }
                                    }
                                }

                                Text {
                                    text: catItem.desc || ""
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontPx(10.5)
                                    color: Qt.rgba(1, 1, 1, 0.40)
                                }
                            }

                            // Active Default Indicator Badge
                            Rectangle {
                                Layout.preferredHeight: Theme.px(26)
                                Layout.preferredWidth: activeDefText.implicitWidth + Theme.px(18)
                                radius: Theme.px(6)
                                color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12)
                                border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.35)
                                border.width: 1

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: Theme.px(5)

                                    Text {
                                        text: "󰄬"
                                        font.family: Theme.fontMono
                                        font.pixelSize: Theme.fontPx(10)
                                        color: Theme.primary
                                    }

                                    Text {
                                        id: activeDefText
                                        text: catItem.currentName || "None"
                                        font.family: Theme.font
                                        font.pixelSize: Theme.fontPx(11)
                                        font.weight: Font.DemiBold
                                        color: Theme.primary
                                    }
                                }
                            }
                        }

                        // 1px Hairline
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 1
                            color: Qt.rgba(1, 1, 1, 0.06)
                        }

                        // Options List (Pre-categorized chips + Browse apps button)
                        Flow {
                            Layout.fillWidth: true
                            spacing: Theme.px(8)

                            Repeater {
                                model: catItem.options

                                delegate: Rectangle {
                                    readonly property bool isSelected: modelData.id === catItem.current
                                    width: optRow.implicitWidth + Theme.px(24)
                                    height: Theme.px(34)
                                    radius: Theme.px(6)
                                    color: isSelected ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.18) : (optMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.20))
                                    border.color: isSelected ? Theme.primary : (optMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(1, 1, 1, 0.10))
                                    border.width: 1

                                    RowLayout {
                                        id: optRow
                                        anchors.centerIn: parent
                                        spacing: Theme.px(8)

                                        Text {
                                            visible: isSelected
                                            text: "󰄬"
                                            font.family: Theme.fontMono
                                            font.pixelSize: Theme.fontPx(11)
                                            color: Theme.primary
                                        }

                                        Text {
                                            text: modelData.name
                                            font.family: Theme.font
                                            font.pixelSize: Theme.fontPx(11.5)
                                            font.weight: isSelected ? Font.DemiBold : Font.Normal
                                            color: isSelected ? Qt.rgba(1, 1, 1, 0.98) : Qt.rgba(1, 1, 1, 0.70)
                                        }

                                        Text {
                                            text: "(" + modelData.id.replace(".desktop", "") + ")"
                                            font.family: Theme.fontMono
                                            font.pixelSize: Theme.fontPx(9)
                                            color: isSelected ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.80) : Qt.rgba(1, 1, 1, 0.30)
                                        }
                                    }

                                    MouseArea {
                                        id: optMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onEntered: root.describe(catItem.title + ": " + modelData.name, "Set " + modelData.name + " (" + modelData.id + ") as default handler.")
                                        onExited: root.clearDesc()
                                        ToolTip.visible: containsMouse
                                        ToolTip.text: "Select " + modelData.name + " as default"
                                        ToolTip.delay: 300
                                        onClicked: {
                                            root.setDefault(catItem.category, modelData.id)
                                        }
                                    }
                                }
                            }

                            // Browse apps button alongside the options
                            Rectangle {
                                width: browseRow.implicitWidth + Theme.px(22)
                                height: Theme.px(34)
                                radius: Theme.px(6)
                                color: browseMouse.pressed ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.25) : (browseMouse.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.14) : Qt.rgba(1, 1, 1, 0.05))
                                border.color: browseMouse.containsMouse ? Theme.primary : Qt.rgba(1, 1, 1, 0.14)
                                border.width: 1

                                RowLayout {
                                    id: browseRow
                                    anchors.centerIn: parent
                                    spacing: Theme.px(6)

                                    Text {
                                        text: "󰍉"
                                        font.family: Theme.fontMono
                                        font.pixelSize: Theme.fontPx(11)
                                        color: browseMouse.containsMouse ? Theme.primary : Qt.rgba(1, 1, 1, 0.65)
                                    }

                                    Text {
                                        text: "Browse apps"
                                        font.family: Theme.font
                                        font.pixelSize: Theme.fontPx(11.5)
                                        font.weight: Font.Medium
                                        color: browseMouse.containsMouse ? Theme.primary : Qt.rgba(1, 1, 1, 0.75)
                                    }
                                }

                                MouseArea {
                                    id: browseMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onEntered: root.describe("Browse Apps: " + catItem.title, "Browse all installed desktop applications or pick a custom launcher from disk.")
                                    onExited: root.clearDesc()
                                    ToolTip.visible: containsMouse
                                    ToolTip.text: "Browse all installed apps for " + catItem.title
                                    ToolTip.delay: 300
                                    onClicked: root.openAppBrowser(catItem.category, catItem.title)
                                }
                            }
                        }
                    }
                }
            }

            // Bottom Spacing
            Item {
                Layout.preferredHeight: Theme.px(16)
            }
        }
    }

    // ===================================================================
    // BROWSE APPS MODAL OVERLAY
    // ===================================================================
    Rectangle {
        id: appBrowserOverlay
        anchors.fill: parent
        visible: root.browseCategory !== ""
        color: Qt.rgba(0, 0, 0, 0.70)
        z: 99

        // Stop dismissal propagation
        MouseArea {
            anchors.fill: parent
            onClicked: root.closeAppBrowser()
        }

        // Center Dialog Box
        Rectangle {
            id: dialogBox
            anchors.centerIn: parent
            width: Math.min(parent.width - Theme.px(48), Theme.px(680))
            height: Math.min(parent.height - Theme.px(48), Theme.px(540))
            radius: Theme.px(12)
            color: Theme.surface
            border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.35)
            border.width: 1
            clip: true

            // Stop click propagation inside dialog
            MouseArea {
                anchors.fill: parent
                onClicked: {}
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.px(18)
                spacing: Theme.px(14)

                // Dialog Header
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(12)

                    Rectangle {
                        Layout.preferredWidth: Theme.px(34)
                        Layout.preferredHeight: Theme.px(34)
                        radius: Theme.px(8)
                        color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                        border.color: Theme.primary
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: "󰍉"
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.fontPx(16)
                            color: Theme.primary
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.px(1)

                        Text {
                            text: "BROWSE ALL APPLICATIONS // " + root.browseCategoryTitle.toUpperCase()
                            font.family: Theme.font
                            font.pixelSize: Theme.fontPx(13)
                            font.weight: Font.Bold
                            color: Qt.rgba(1, 1, 1, 0.95)
                        }

                        Text {
                            text: "Select any installed system application to set as default handler for " + root.browseCategoryTitle
                            font.family: Theme.font
                            font.pixelSize: Theme.fontPx(10.5)
                            color: Qt.rgba(1, 1, 1, 0.45)
                        }
                    }

                    // Close Button
                    Rectangle {
                        Layout.preferredWidth: Theme.px(28)
                        Layout.preferredHeight: Theme.px(28)
                        radius: Theme.px(6)
                        color: closeDialogMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : "transparent"
                        border.color: closeDialogMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.20) : "transparent"
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: "✕"
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.fontPx(13)
                            color: Qt.rgba(1, 1, 1, 0.70)
                        }

                        MouseArea {
                            id: closeDialogMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.closeAppBrowser()
                        }
                    }
                }

                // 1px Hairline
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: Qt.rgba(1, 1, 1, 0.08)
                }

                // Search Bar
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.px(38)
                    radius: Theme.px(8)
                    color: Qt.rgba(0, 0, 0, 0.35)
                    border.color: searchInput.activeFocus ? Theme.primary : Qt.rgba(1, 1, 1, 0.12)
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.px(12)
                        anchors.rightMargin: Theme.px(12)
                        spacing: Theme.px(10)

                        Text {
                            text: "󰍉"
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.fontPx(14)
                            color: searchInput.activeFocus ? Theme.primary : Qt.rgba(1, 1, 1, 0.40)
                        }

                        TextInput {
                            id: searchInput
                            Layout.fillWidth: true
                            font.family: Theme.font
                            font.pixelSize: Theme.fontPx(12)
                            color: Qt.rgba(1, 1, 1, 0.95)
                            selectByMouse: true
                            text: root.appSearchQuery
                            onTextChanged: root.appSearchQuery = text

                            Text {
                                visible: !searchInput.text && !searchInput.activeFocus
                                text: "Search all installed applications..."
                                font: searchInput.font
                                color: Qt.rgba(1, 1, 1, 0.30)
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        // Clear search query button
                        Rectangle {
                            visible: root.appSearchQuery.length > 0
                            Layout.preferredWidth: Theme.px(20)
                            Layout.preferredHeight: Theme.px(20)
                            radius: Theme.px(10)
                            color: Qt.rgba(1, 1, 1, 0.10)

                            Text {
                                anchors.centerIn: parent
                                text: "✕"
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fontPx(9)
                                color: Qt.rgba(1, 1, 1, 0.60)
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.appSearchQuery = ""
                            }
                        }
                    }
                }

                // Apps Scrollable List
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Theme.px(8)
                    color: Qt.rgba(0, 0, 0, 0.20)
                    border.color: Qt.rgba(1, 1, 1, 0.06)
                    border.width: 1
                    clip: true

                    ListView {
                        id: appsListView
                        anchors.fill: parent
                        anchors.margins: Theme.px(6)
                        spacing: Theme.px(4)
                        boundsBehavior: Flickable.StopAtBounds

                        model: {
                            var q = root.appSearchQuery.toLowerCase().trim()
                            if (!q) return root.allApps
                            return root.allApps.filter(function(a) {
                                return (a.name && a.name.toLowerCase().indexOf(q) !== -1) ||
                                       (a.id && a.id.toLowerCase().indexOf(q) !== -1) ||
                                       (a.exec && a.exec.toLowerCase().indexOf(q) !== -1) ||
                                       (a.categories && a.categories.toLowerCase().indexOf(q) !== -1)
                            })
                        }

                        delegate: Rectangle {
                            id: appItemDelegate
                            width: appsListView.width
                            height: Theme.px(46)
                            radius: Theme.px(6)

                            readonly property bool isCurrent: {
                                for (var i = 0; i < root.defaultApps.length; i++) {
                                    if (root.defaultApps[i].category === root.browseCategory) {
                                        return root.defaultApps[i].current === modelData.id
                                    }
                                }
                                return false
                            }

                            color: isCurrent ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.16) : (appItemMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent")
                            border.color: isCurrent ? Theme.primary : (appItemMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : "transparent")
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.px(12)
                                anchors.rightMargin: Theme.px(12)
                                spacing: Theme.px(12)

                                // Mini app icon placeholder/box
                                Rectangle {
                                    Layout.preferredWidth: Theme.px(28)
                                    Layout.preferredHeight: Theme.px(28)
                                    radius: Theme.px(6)
                                    color: Qt.rgba(1, 1, 1, 0.06)
                                    border.color: Qt.rgba(1, 1, 1, 0.10)
                                    border.width: 1

                                    Text {
                                        anchors.centerIn: parent
                                        text: "󰀻"
                                        font.family: Theme.fontMono
                                        font.pixelSize: Theme.fontPx(13)
                                        color: isCurrent ? Theme.primary : Qt.rgba(1, 1, 1, 0.70)
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: Theme.px(1)

                                    Text {
                                        text: modelData.name || modelData.id
                                        font.family: Theme.font
                                        font.pixelSize: Theme.fontPx(12)
                                        font.weight: isCurrent ? Font.DemiBold : Font.Normal
                                        color: isCurrent ? Qt.rgba(1, 1, 1, 0.98) : Qt.rgba(1, 1, 1, 0.85)
                                    }

                                    Text {
                                        text: modelData.id + (modelData.exec ? "  •  " + modelData.exec : "")
                                        font.family: Theme.fontMono
                                        font.pixelSize: Theme.fontPx(9.5)
                                        color: Qt.rgba(1, 1, 1, 0.35)
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }

                                // Status indicator
                                Rectangle {
                                    visible: isCurrent
                                    Layout.preferredHeight: Theme.px(22)
                                    Layout.preferredWidth: currBadgeTxt.implicitWidth + Theme.px(14)
                                    radius: Theme.px(4)
                                    color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.18)
                                    border.color: Theme.primary
                                    border.width: 1

                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: Theme.px(4)
                                        Text { text: "󰄬"; font.family: Theme.fontMono; font.pixelSize: Theme.fontPx(9); color: Theme.primary }
                                        Text { id: currBadgeTxt; text: "CURRENT"; font.family: Theme.font; font.pixelSize: Theme.fontPx(9); font.weight: Font.Bold; color: Theme.primary }
                                    }
                                }

                                Rectangle {
                                    visible: !isCurrent && appItemMouse.containsMouse
                                    Layout.preferredHeight: Theme.px(24)
                                    Layout.preferredWidth: selectTxt.implicitWidth + Theme.px(16)
                                    radius: Theme.px(4)
                                    color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15)
                                    border.color: Theme.primary
                                    border.width: 1

                                    Text {
                                        id: selectTxt
                                        anchors.centerIn: parent
                                        text: "Set Default"
                                        font.family: Theme.font
                                        font.pixelSize: Theme.fontPx(10)
                                        font.weight: Font.DemiBold
                                        color: Theme.primary
                                    }
                                }
                            }

                            MouseArea {
                                id: appItemMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.setDefault(root.browseCategory, modelData.id)
                                    root.closeAppBrowser()
                                }
                            }
                        }
                    }
                }

                // Modal Footer
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(10)

                    Text {
                        text: (appsListView.count || 0) + " applications found"
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fontPx(10)
                        color: Qt.rgba(1, 1, 1, 0.35)
                    }

                    Item { Layout.fillWidth: true }

                    // Custom File Picker Button
                    Rectangle {
                        Layout.preferredHeight: Theme.px(32)
                        Layout.preferredWidth: customFileRow.implicitWidth + Theme.px(24)
                        radius: Theme.px(6)
                        color: customFileMouse.pressed ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.25) : (customFileMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.05))
                        border.color: customFileMouse.containsMouse ? Theme.primary : Qt.rgba(1, 1, 1, 0.14)
                        border.width: 1

                        RowLayout {
                            id: customFileRow
                            anchors.centerIn: parent
                            spacing: Theme.px(6)

                            Text {
                                text: "󰉋"
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fontPx(11)
                                color: customFileMouse.containsMouse ? Theme.primary : Qt.rgba(1, 1, 1, 0.70)
                            }

                            Text {
                                text: "Browse Files On Disk (.desktop)..."
                                font.family: Theme.font
                                font.pixelSize: Theme.fontPx(11)
                                font.weight: Font.Medium
                                color: customFileMouse.containsMouse ? Theme.primary : Qt.rgba(1, 1, 1, 0.85)
                            }
                        }

                        MouseArea {
                            id: customFileMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (!pickFileProc.running) {
                                    pickFileProc.running = true
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
