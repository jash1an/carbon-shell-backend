import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../Singletons"

/**
 * SpotlightModal: Modern Raycast / Spotlight command palette (Super + K).
 * Features:
 * - Real-time math & unit/currency evaluation via qalc
 * - Clipboard history search & paste via cliphist
 * - Instant system commands (screenshot, wallpaper, lock, settings, power)
 * - Desktop application search & launch
 * - Caelestia Material 3 surfaceContainer glass design
 */
Item {
    id: root

    property bool open: false
    property real shellOpacity: Theme.shellOpacity
    signal closeRequested()
    readonly property string home: Quickshell.env("HOME") || ""

    /* Caelestia Shell bottom slide-up & fluid pop-in animation */
    readonly property bool animatingOut: !root.open && (root.opacity > 0.005 || opacityAnim.running || slideAnim.running)

    property real yOffset: root.open ? 0 : 20
    transform: Translate { y: root.yOffset }
    transformOrigin: Item.Center
    scale: root.open ? 1.0 : 0.97
    opacity: root.open ? 1.0 : 0.0

    Behavior on yOffset {
        NumberAnimation {
            id: slideAnim
            duration: root.open ? 130 : 95
            easing.type: root.open ? Easing.OutCubic : Easing.InCubic
        }
    }

    Behavior on scale {
        NumberAnimation {
            duration: root.open ? 130 : 95
            easing.type: root.open ? Easing.OutCubic : Easing.InCubic
        }
    }

    Behavior on opacity {
        NumberAnimation {
            id: opacityAnim
            duration: root.open ? 120 : 85
            easing.type: Easing.OutCubic
        }
    }

    width: 620
    implicitWidth: 620

    // Dynamic height calculation: guarantees proper breathing room so 1-item lists are never clipped
    readonly property int calculatedHeight: {
        let h = 155 // base: margins (28) + search header (42) + divider (1) + tabs (24) + footer (20) + 4 spacings (40)
        if (calcCard.visible) {
            h += 66
        }
        if (resultsModel.count > 0) {
            h += 10 + Math.min(240, resultsModel.count * 48)
        } else if (!calcCard.visible) {
            h += 58 // empty placeholder
        }
        return Math.max(160, Math.min(460, h))
    }
    height: calculatedHeight
    implicitHeight: height

    Behavior on height {
        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
    }

    property string currentTab: "apps" // "apps", "clipboard", "commands"
    property real tabContentOpacity: 1.0
    property real tabContentY: 0

    onCurrentTabChanged: {
        tabSwitchAnim.restart()
    }

    SequentialAnimation {
        id: tabSwitchAnim
        ParallelAnimation {
            NumberAnimation { target: root; property: "tabContentOpacity"; to: 0.20; duration: 40; easing.type: Easing.OutQuad }
            NumberAnimation { target: root; property: "tabContentY"; to: 6; duration: 40; easing.type: Easing.OutQuad }
        }
        ParallelAnimation {
            NumberAnimation { target: root; property: "tabContentOpacity"; to: 1.0; duration: 120; easing.type: Easing.OutCubic }
            NumberAnimation { target: root; property: "tabContentY"; to: 0; duration: 120; easing.type: Easing.OutCubic }
        }
    }

    property string calcResult: ""
    property bool hasCalcResult: false

    // App & Action lists
    property var allApps: []
    property var clipboardItems: []
    property int selectedIndex: 0

    /* ── System Actions ───────────────────────────────────────────────── */
    readonly property var systemActions: [
        {
            id: "screenshot-region",
            title: "Screenshot Region",
            desc: "Select a region on screen and copy to clipboard",
            glyph: "crop",
            category: "System",
            run: () => {
                root.closeRequested()
                Quickshell.execDetached(["sh", root.home + "/.config/hypr/scripts/carbon-screenshot-region.sh"])
            }
        },
        {
            id: "screenshot-full",
            title: "Screenshot Full Screen",
            desc: "Capture all monitors and save to Pictures",
            glyph: "photo_camera",
            category: "System",
            run: () => {
                root.closeRequested()
                Quickshell.execDetached(["sh", root.home + "/.config/hypr/scripts/carbon-screenshot-full.sh"])
            }
        },
        {
            id: "wallpaper",
            title: "Change Wallpaper",
            desc: "Open Carbon dynamic wallpaper picker",
            glyph: "wallpaper",
            category: "Personalization",
            run: () => {
                root.closeRequested()
                Quickshell.execDetached(["sh", root.home + "/.config/hypr/scripts/carbon-ipc.sh", "wallpaper"])
            }
        },
        {
            id: "config",
            title: "Carbon Config & Theme Editor",
            desc: "Configure shell layout, notch mode, and keybinds",
            glyph: "settings",
            category: "Preferences",
            run: () => {
                root.closeRequested()
                Quickshell.execDetached(["python3", root.home + "/.config/hypr/scripts/carbon-config-editor.py"])
            }
        },
        {
            id: "terminal",
            title: "Open Terminal",
            desc: "Launch kitty terminal emulator",
            glyph: "terminal",
            category: "Developer",
            run: () => {
                root.closeRequested()
                Quickshell.execDetached(["kitty"])
            }
        },
        {
            id: "lock",
            title: "Lock Screen",
            desc: "Lock the desktop session with Carbon Lock",
            glyph: "lock",
            category: "Security",
            run: () => {
                root.closeRequested()
                Quickshell.execDetached(["sh", root.home + "/.config/hypr/scripts/carbon-ipc.sh", "lock"])
            }
        },
        {
            id: "suspend",
            title: "Sleep / Suspend",
            desc: "Put the system into low power sleep mode",
            glyph: "bedtime",
            category: "Power",
            run: () => {
                root.closeRequested()
                Quickshell.execDetached(["systemctl", "suspend"])
            }
        },
        {
            id: "restart-shell",
            title: "Restart Carbon Shell",
            desc: "Reload Quickshell process and UI",
            glyph: "refresh",
            category: "Developer",
            run: () => {
                root.closeRequested()
                Quickshell.execDetached(["sh", "-c", "systemctl --user restart carbon-quickshell.service 2>/dev/null || (pkill -9 quickshell; sleep 0.4; quickshell --config " + root.home + "/.local/share/quickshell/carbon &)"])
            }
        }
    ]

    ListModel {
        id: resultsModel
    }

    /* ── Desktop Applications Loader ──────────────────────────────────── */
    function loadApps() {
        const values = DesktopEntries.applications.values || []
        const list = []
        for (let i = 0; i < values.length; i++) {
            const e = values[i]
            if (e.noDisplay || !e.name || !e.command || e.command.length === 0) continue
            list.push(e)
        }
        list.sort((a, b) => a.name.localeCompare(b.name))
        root.allApps = list
    }

    Component.onCompleted: {
        root.loadApps()
    }

    Connections {
        target: DesktopEntries
        function onApplicationsChanged() {
            root.loadApps()
            root.rebuildResults()
        }
    }

    /* ── Clipboard Fetcher via cliphist ───────────────────────────────── */
    Process {
        id: cliphistProcess
        command: ["sh", "-c", "cliphist list | head -n 40"]
        running: false
        stdout: StdioCollector {
            id: clipCol
            waitForEnd: true
        }
        onExited: {
            const raw = String(clipCol.text || "").trim()
            if (!raw) return
            const lines = raw.split("\n")
            const items = []
            for (let i = 0; i < lines.length; i++) {
                const l = lines[i]
                if (!l) continue
                const tabIdx = l.indexOf("\t")
                if (tabIdx > 0) {
                    const id = l.substring(0, tabIdx).trim()
                    const preview = l.substring(tabIdx + 1).trim()
                    items.push({ id: id, raw: l, preview: preview })
                }
            }
            root.clipboardItems = items
            root.rebuildResults()
        }
    }

    function refreshClipboard() {
        cliphistProcess.running = false
        cliphistProcess.running = true
    }

    /* ── Math & Conversion Evaluator via qalc ─────────────────────────── */
    Timer {
        id: qalcDebounceTimer
        interval: 60
        onTriggered: {
            const q = searchInput.text.trim()
            if (q.length === 0) {
                root.calcResult = ""
                root.hasCalcResult = false
                return
            }
            // Check if input might be an expression
            const hasMath = /^[=]/.test(q) || (/[0-9]/.test(q) && /[+\-*/^%=()]/.test(q)) || /(sqrt|sin|cos|tan|log|ln|pi|to\s+[a-z]+)/i.test(q)
            if (hasMath) {
                const expr = q.replace(/^=\s*/, "")
                qalcProcess.running = false
                qalcProcess.command = ["qalc", "-t", "-m", "500", expr]
                qalcProcess.running = true
            } else {
                root.calcResult = ""
                root.hasCalcResult = false
            }
        }
    }

    Process {
        id: qalcProcess
        running: false
        stdout: StdioCollector {
            id: qalcCol
            waitForEnd: true
        }
        onExited: {
            const res = String(qalcCol.text || "").trim()
            if (res.length > 0 && !res.toLowerCase().startsWith("error") && !res.toLowerCase().includes("syntax error") && !res.toLowerCase().includes("parse error")) {
                root.calcResult = res
                root.hasCalcResult = true
            } else {
                root.calcResult = ""
                root.hasCalcResult = false
            }
            root.rebuildResults()
        }
    }

    /* ── Rebuild Results Model ────────────────────────────────────────── */
    function rebuildResults() {
        resultsModel.clear()
        const q = searchInput.text.trim().toLowerCase()

        // 1. If in clipboard mode
        if (root.currentTab === "clipboard" || q.startsWith("c ") || q.startsWith("clip ")) {
            const subQ = q.startsWith("clip ") ? q.substring(5).trim() : (q.startsWith("c ") ? q.substring(2).trim() : q)
            for (let i = 0; i < root.clipboardItems.length; i++) {
                const item = root.clipboardItems[i]
                if (subQ.length === 0 || (item.preview && item.preview.toLowerCase().includes(subQ))) {
                    resultsModel.append({
                        itemType: "clipboard",
                        itemId: item.id,
                        title: item.preview || "",
                        subTitle: "Press Enter to copy to clipboard",
                        glyph: "content_paste",
                        iconSource: "",
                        rawRef: item.raw || ""
                    })
                }
            }
            resultsList.currentIndex = resultsModel.count > 0 ? 0 : -1
            return
        }

        // 2. If in commands mode
        if (root.currentTab === "commands" || q.startsWith(">")) {
            const subQ = q.startsWith(">") ? q.substring(1).trim() : q
            for (let i = 0; i < root.systemActions.length; i++) {
                const act = root.systemActions[i]
                if (subQ.length === 0 || act.title.toLowerCase().includes(subQ) || act.desc.toLowerCase().includes(subQ)) {
                    resultsModel.append({
                        itemType: "action",
                        itemId: act.id,
                        title: act.title,
                        subTitle: act.desc,
                        glyph: act.glyph,
                        iconSource: "",
                        rawRef: ""
                    })
                }
            }
            resultsList.currentIndex = resultsModel.count > 0 ? 0 : -1
            return
        }

        // 3. Applications mode (default)
        let count = 0
        for (let i = 0; i < root.allApps.length; i++) {
            const app = root.allApps[i]
            const name = (app.name || "").toLowerCase()
            const generic = (app.genericName || "").toLowerCase()
            const comment = (app.comment || "").toLowerCase()
            if (q.length === 0 || name.includes(q) || generic.includes(q) || comment.includes(q)) {
                resultsModel.append({
                    itemType: "app",
                    itemId: app.id || app.name,
                    title: app.name,
                    subTitle: app.genericName || app.comment || "Application",
                    glyph: "apps",
                    iconSource: app.icon ? ("image://icon/" + app.icon) : "",
                    rawRef: ""
                })
                count++
                if (count > 30) break
            }
        }

        resultsList.currentIndex = resultsModel.count > 0 ? 0 : -1
    }

    function executeCurrentItem() {
        const q = searchInput.text.trim()
        const isMathQuery = root.hasCalcResult && (/^[=]/.test(q) || /[+\-*/^%]/.test(q) || /(sqrt|sin|cos|tan|log|ln)/i.test(q))

        if (root.hasCalcResult && (resultsList.currentIndex <= 0 || isMathQuery)) {
            copyCalcResult()
            return
        }

        if (resultsList.currentIndex < 0 || resultsList.currentIndex >= resultsModel.count) {
            if (root.hasCalcResult) {
                copyCalcResult()
            }
            return
        }

        const item = resultsModel.get(resultsList.currentIndex)
        if (!item) return

        if (item.itemType === "action") {
            for (let i = 0; i < root.systemActions.length; i++) {
                if (root.systemActions[i].id === item.itemId) {
                    root.systemActions[i].run()
                    return
                }
            }
        } else if (item.itemType === "app") {
            for (let i = 0; i < root.allApps.length; i++) {
                if (root.allApps[i].id === item.itemId || root.allApps[i].name === item.title) {
                    root.closeRequested()
                    root.allApps[i].execute()
                    return
                }
            }
        } else if (item.itemType === "clipboard") {
            root.closeRequested()
            Quickshell.execDetached(["sh", "-c", "cliphist decode " + item.itemId + " | wl-copy"])
        }
    }

    function copyCalcResult() {
        if (!root.calcResult) return
        Quickshell.execDetached(["sh", "-c", "printf '%s' " + JSON.stringify(root.calcResult) + " | wl-copy"])
        root.closeRequested()
    }

    /* ── Activation & Reset ───────────────────────────────────────────── */
    onOpenChanged: {
        if (root.open) {
            searchInput.text = ""
            root.calcResult = ""
            root.hasCalcResult = false
            root.currentTab = "apps"
            root.refreshClipboard()
            root.rebuildResults()
            searchInput.forceActiveFocus()
        }
    }

    /* ── Main Background Container ────────────────────────────────────── */
    Rectangle {
        id: bgCard
        anchors.fill: parent
        radius: 20
        color: Qt.rgba(Theme.m3surfaceContainer.r, Theme.m3surfaceContainer.g, Theme.m3surfaceContainer.b, root.shellOpacity)
        border.color: Qt.alpha(Theme.outline, 0.35)
        border.width: 1

        // Bottom flattener to cleanly merge flush with bottom of the screen
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 20
            color: bgCard.color
            z: 0
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 10

            /* 1. Top Search Header */
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 42
                spacing: 10

                Text {
                    font.family: Theme.fontIcon
                    font.pixelSize: 20
                    color: Theme.accent
                    text: "search"
                    Layout.alignment: Qt.AlignVCenter
                }

                TextInput {
                    id: searchInput
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    font.family: "Valley Sans"
                    font.pixelSize: 15
                    font.weight: Font.Medium
                    color: Theme.fg
                    selectionColor: Theme.accent
                    selectedTextColor: Theme.bg
                    clip: true

                    Text {
                        anchors.fill: parent
                        text: root.currentTab === "clipboard" ? "Search clipboard history..." : (root.currentTab === "commands" ? "Search commands..." : "Search applications or calculate...")
                        font.family: "Valley Sans"
                        font.pixelSize: 15
                        color: Theme.fgFaint
                        visible: !searchInput.text && !searchInput.inputMethodComposing
                    }

                    onTextChanged: {
                        qalcDebounceTimer.restart()
                        root.rebuildResults()
                    }

                    Keys.onEscapePressed: root.closeRequested()
                    Keys.onReturnPressed: root.executeCurrentItem()
                    Keys.onDownPressed: {
                        if (resultsList.count > 0) {
                            resultsList.currentIndex = (resultsList.currentIndex + 1) % resultsList.count
                            resultsList.positionViewAtIndex(resultsList.currentIndex, ListView.Contain)
                        }
                    }
                    Keys.onUpPressed: {
                        if (resultsList.count > 0) {
                            resultsList.currentIndex = (resultsList.currentIndex - 1 + resultsList.count) % resultsList.count
                            resultsList.positionViewAtIndex(resultsList.currentIndex, ListView.Contain)
                        }
                    }
                    Keys.onTabPressed: {
                        const tabs = ["apps", "clipboard", "commands"]
                        const nextIdx = (tabs.indexOf(root.currentTab) + 1) % tabs.length
                        root.currentTab = tabs[nextIdx]
                        root.rebuildResults()
                    }
                }

                /* Esc Badge */
                Rectangle {
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 20
                    radius: 4
                    color: Qt.alpha(Theme.fg, 0.08)
                    border.color: Qt.alpha(Theme.outlineVariant, 0.3)
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "ESC"
                        font.family: "Valley Sans"
                        font.pixelSize: 9
                        font.weight: Font.Bold
                        color: Theme.fgDim
                    }
                }
            }

            /* Divider */
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Qt.alpha(Theme.outlineVariant, 0.25)
            }

            /* 2. Category Filter Tabs */
            Item {
                id: modeTabs
                Layout.fillWidth: true
                Layout.preferredHeight: 26

                // Animated sliding background indicator pill
                Rectangle {
                    id: tabIndicator
                    y: 1
                    height: 24
                    radius: 12
                    color: Qt.alpha(Theme.accent, 0.22)
                    border.color: Qt.alpha(Theme.accent, 0.7)
                    border.width: 1
                    x: {
                        if (root.currentTab === "clipboard") return tabClip.x
                        if (root.currentTab === "commands") return tabCmd.x
                        return tabApps.x
                    }
                    width: {
                        if (root.currentTab === "clipboard") return tabClip.width
                        if (root.currentTab === "commands") return tabCmd.width
                        return tabApps.width
                    }

                    Behavior on x {
                        NumberAnimation {
                            duration: 180
                            easing.type: Easing.OutCubic
                        }
                    }
                    Behavior on width {
                        NumberAnimation {
                            duration: 180
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                Row {
                    anchors.fill: parent
                    spacing: 6

                    Item {
                        id: tabApps
                        width: tabAppsText.implicitWidth + 20
                        height: 26

                        Text {
                            id: tabAppsText
                            anchors.centerIn: parent
                            text: "Applications"
                            font.family: "Valley Sans"
                            font.pixelSize: 10
                            font.weight: root.currentTab === "apps" ? Font.Bold : Font.Normal
                            color: root.currentTab === "apps" ? Theme.accent : Theme.fgDim
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.currentTab = "apps"
                                root.rebuildResults()
                            }
                        }
                    }

                    Item {
                        id: tabClip
                        width: tabClipText.implicitWidth + 20
                        height: 26

                        Text {
                            id: tabClipText
                            anchors.centerIn: parent
                            text: "Clipboard"
                            font.family: "Valley Sans"
                            font.pixelSize: 10
                            font.weight: root.currentTab === "clipboard" ? Font.Bold : Font.Normal
                            color: root.currentTab === "clipboard" ? Theme.accent : Theme.fgDim
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.currentTab = "clipboard"
                                root.rebuildResults()
                            }
                        }
                    }

                    Item {
                        id: tabCmd
                        width: tabCmdText.implicitWidth + 20
                        height: 26

                        Text {
                            id: tabCmdText
                            anchors.centerIn: parent
                            text: "Commands"
                            font.family: "Valley Sans"
                            font.pixelSize: 10
                            font.weight: root.currentTab === "commands" ? Font.Bold : Font.Normal
                            color: root.currentTab === "commands" ? Theme.accent : Theme.fgDim
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.currentTab = "commands"
                                root.rebuildResults()
                            }
                        }
                    }
                }
            }

            /* 3. Live Calculation Card (When Expression Detected) */
            Rectangle {
                id: calcCard
                Layout.fillWidth: true
                Layout.preferredHeight: 56
                radius: 10
                color: Qt.alpha(Theme.accent, 0.12)
                border.color: Qt.alpha(Theme.accent, 0.4)
                border.width: 1
                visible: root.hasCalcResult && root.calcResult.length > 0

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 12

                    Rectangle {
                        width: 34
                        height: 34
                        radius: 8
                        color: Theme.accent
                        Layout.alignment: Qt.AlignVCenter

                        Text {
                            anchors.centerIn: parent
                            text: "calculate"
                            font.family: Theme.fontIcon
                            font.pixelSize: 20
                            color: Theme.bg
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Text {
                            text: root.calcResult
                            font.family: "Valley Sans"
                            font.pixelSize: 16
                            font.weight: Font.Bold
                            color: Theme.fg
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        Text {
                            text: "Press Enter to copy result to clipboard"
                            font.family: "Valley Sans"
                            font.pixelSize: 9
                            color: Theme.fgDim
                        }
                    }

                    Rectangle {
                        width: 65
                        height: 24
                        radius: 6
                        color: Qt.alpha(Theme.accent, 0.25)
                        Layout.alignment: Qt.AlignVCenter

                        Text {
                            anchors.centerIn: parent
                            text: "↵ Copy"
                            font.family: "Valley Sans"
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            color: Theme.accent
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.copyCalcResult()
                }
            }

            /* 4. Results List View */
            ListView {
                id: resultsList
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: Math.min(240, resultsModel.count * 48)
                Layout.minimumHeight: resultsModel.count > 0 ? Math.min(240, resultsModel.count * 48) : 0
                clip: true
                spacing: 4
                boundsBehavior: Flickable.StopAtBounds
                model: resultsModel
                visible: resultsModel.count > 0
                opacity: root.tabContentOpacity
                transform: Translate { y: root.tabContentY }

                delegate: Rectangle {
                    id: rowDelegate
                    required property int index
                    required property string itemType
                    required property string itemId
                    required property string title
                    required property string subTitle
                    required property string glyph
                    required property string iconSource

                    width: resultsList.width
                    height: 44
                    radius: 8
                    color: resultsList.currentIndex === index ? Qt.alpha(Theme.accent, 0.15) : (rowHover.hovered ? Qt.alpha(Theme.fg, 0.05) : "transparent")
                    border.color: resultsList.currentIndex === index ? Qt.alpha(Theme.accent, 0.4) : "transparent"
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 10

                        /* Icon */
                        Rectangle {
                            width: 28
                            height: 28
                            radius: 6
                            color: Qt.alpha(Theme.fg, 0.06)
                            Layout.alignment: Qt.AlignVCenter

                            Image {
                                anchors.centerIn: parent
                                width: 20
                                height: 20
                                source: rowDelegate.iconSource
                                sourceSize: Qt.size(40, 40)
                                visible: rowDelegate.iconSource.length > 0
                            }

                            Text {
                                anchors.centerIn: parent
                                text: rowDelegate.glyph
                                font.family: Theme.fontIcon
                                font.pixelSize: 16
                                color: resultsList.currentIndex === rowDelegate.index ? Theme.accent : Theme.fgDim
                                visible: rowDelegate.iconSource.length === 0
                            }
                        }

                        /* Texts */
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            Text {
                                text: rowDelegate.title
                                font.family: "Valley Sans"
                                font.pixelSize: 12
                                font.weight: resultsList.currentIndex === rowDelegate.index ? Font.Bold : Font.Medium
                                color: resultsList.currentIndex === rowDelegate.index ? Theme.accent : Theme.fg
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            Text {
                                text: rowDelegate.subTitle
                                font.family: "Valley Sans"
                                font.pixelSize: 9
                                color: Theme.fgDim
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }

                        /* Enter hint on selected item */
                        Text {
                            text: "↵"
                            font.family: "Valley Sans"
                            font.pixelSize: 13
                            color: Theme.accent
                            visible: resultsList.currentIndex === rowDelegate.index
                        }
                    }

                    MouseArea {
                        id: rowHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            resultsList.currentIndex = rowDelegate.index
                            root.executeCurrentItem()
                        }
                    }
                }
            }

            /* Empty State Placeholder */
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 48
                visible: resultsModel.count === 0 && !root.hasCalcResult
                opacity: root.tabContentOpacity
                transform: Translate { y: root.tabContentY }

                Text {
                    anchors.centerIn: parent
                    text: root.currentTab === "clipboard" ? "Clipboard is empty" : (root.currentTab === "commands" ? "No commands found" : "No applications found")
                    font.family: "Valley Sans"
                    font.pixelSize: 12
                    color: Theme.fgDim
                }
            }

            /* 5. Footer Shortcuts */
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 20
                spacing: 12

                Text {
                    text: resultsModel.count === 1 ? "1 result" : (resultsModel.count + " results")
                    font.family: "Valley Sans"
                    font.pixelSize: 9
                    color: Theme.fgFaint
                }

                Item { Layout.fillWidth: true }

                Row {
                    spacing: 10

                    Row {
                        spacing: 4
                        Text { text: "↑↓"; font.pixelSize: 9; color: Theme.fgDim; font.weight: Font.Bold }
                        Text { text: "Navigate"; font.pixelSize: 9; color: Theme.fgFaint }
                    }

                    Row {
                        spacing: 4
                        Text { text: "Tab"; font.pixelSize: 9; color: Theme.fgDim; font.weight: Font.Bold }
                        Text { text: "Filter"; font.pixelSize: 9; color: Theme.fgFaint }
                    }

                    Row {
                        spacing: 4
                        Text { text: "↵"; font.pixelSize: 9; color: Theme.fgDim; font.weight: Font.Bold }
                        Text { text: "Open"; font.pixelSize: 9; color: Theme.fgFaint }
                    }
                }
            }
        }
    }
}
