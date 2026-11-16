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

    readonly property string scriptPath: (Quickshell.env("HOME") || "") + "/.config/carbon/scripts/carbon-shortcuts-apply.py"
    readonly property string shortcutsJsonPath: (Quickshell.env("HOME") || "") + "/.config/carbon/carbon-shortcuts.json"
    readonly property string customJsonPath: (Quickshell.env("HOME") || "") + "/.config/carbon/carbon-custom-shortcuts.json"
    readonly property string barModeJsonPath: (Quickshell.env("HOME") || "") + "/.config/carbon/carbon-bar-mode.json"

    // State
    property var allShortcuts: []
    property var presetsAvailable: []
    property string activePreset: "carbon_default"
    property string activeBarMode: "nucleus"
    property bool tapSuperEnabled: false
    property string tapSuperAction: "spotlight"
    property string searchQuery: ""
    property string selectedCategory: "All"

    // Key Recording State
    property bool isRecording: false
    property string recordingId: ""
    property string recordingTitle: ""
    property bool isRecordingCustomModal: false

    // Conflict Resolution State
    property bool showConflictModal: false
    property var conflictItem: null
    property string pendingCombo: ""
    property string pendingTargetId: ""

    // Add Custom Shortcut Modal State
    property bool showAddCustomModal: false
    property string newCustomTitle: ""
    property string newCustomCommand: ""
    property string newCustomCombo: ""

    // Toast Notification State
    property string toastMessage: ""
    property bool toastVisible: false

    function showToast(msg) {
        root.toastMessage = msg
        root.toastVisible = true
        toastTimer.restart()
    }

    Timer {
        id: toastTimer
        interval: 3200
        repeat: false
        onTriggered: root.toastVisible = false
    }

    // FileView watchers for live changes
    FileView {
        id: shortcutsWatcher
        path: root.shortcutsJsonPath
        watchChanges: true
        blockLoading: true
        printErrors: false
        onLoaded: root.loadShortcuts()
        onFileChanged: {
            reload()
            root.loadShortcuts()
        }
    }

    FileView {
        id: customWatcher
        path: root.customJsonPath
        watchChanges: true
        blockLoading: true
        printErrors: false
        onLoaded: root.loadShortcuts()
        onFileChanged: {
            reload()
            root.loadShortcuts()
        }
    }

    FileView {
        id: barModeWatcher
        path: root.barModeJsonPath
        watchChanges: true
        blockLoading: true
        printErrors: false
        onFileChanged: {
            reload()
            root.loadShortcuts()
        }
    }

    // Process to fetch shortcuts JSON
    Process {
        id: fetchShortcutsProcess
        command: ["python3", root.scriptPath, "get"]
        stdout: StdioCollector {
            id: fetchCollector
            waitForEnd: true
        }
        onExited: {
            try {
                var txt = String(fetchCollector.text).trim()
                if (txt.length > 2) {
                    var data = JSON.parse(txt)
                    root.tapSuperEnabled = Boolean(data.tap_super)
                    root.tapSuperAction = String(data.tap_super_action || "spotlight")
                    root.activePreset = String(data.preset || "carbon_default")
                    root.activeBarMode = String(data.active_mode || "nucleus")
                    root.presetsAvailable = data.presets_available || []
                    root.allShortcuts = data.shortcuts || []
                }
            } catch (e) {
                console.log("[ShortcutsTab] Load error:", e)
            }
        }
    }

    function loadShortcuts() {
        if (!fetchShortcutsProcess.running) {
            fetchShortcutsProcess.running = true
        }
    }

    function applyPreset(presetId) {
        Quickshell.execDetached(["python3", root.scriptPath, "apply-preset", presetId])
        root.showToast("Applied Preset: " + presetId.replace("_", " ").toUpperCase())
        refreshTimer.restart()
    }

    function setTapSuper(enabled, action) {
        root.tapSuperEnabled = enabled
        root.tapSuperAction = action
        Quickshell.execDetached(["python3", root.scriptPath, "set-tap-super", enabled ? "true" : "false", action])
        root.showToast(enabled ? "Tap Super enabled (" + action + ")" : "Tap Super disabled")
        refreshTimer.restart()
    }

    function resetAllShortcuts() {
        Quickshell.execDetached(["python3", root.scriptPath, "reset-all"])
        root.showToast("All shortcuts reset to defaults")
        refreshTimer.restart()
    }

    function restoreSingleShortcut(id) {
        Quickshell.execDetached(["python3", root.scriptPath, "restore", id])
        root.showToast("Shortcut restored to default")
        refreshTimer.restart()
    }

    function deleteOrUnsetShortcut(item) {
        if (!item) return
        if (item.is_custom) {
            Quickshell.execDetached(["python3", root.scriptPath, "remove-custom", item.id])
            root.showToast("Custom shortcut removed: " + item.title)
        } else {
            Quickshell.execDetached(["python3", root.scriptPath, "unset", item.id])
            root.showToast("Shortcut disabled: " + item.title)
        }
        refreshTimer.restart()
    }

    function exportShortcuts() {
        Quickshell.execDetached(["python3", root.scriptPath, "export"])
        root.showToast("Exported shortcuts to user home folder")
    }

    function assignShortcut(id, combo) {
        Quickshell.execDetached(["python3", root.scriptPath, "set", id, combo])
        root.showToast("Shortcut updated: " + combo)
        refreshTimer.restart()
    }

    Timer {
        id: refreshTimer
        interval: 350
        repeat: false
        onTriggered: root.loadShortcuts()
    }

    // Normalizes combo string for comparison
    function normalizeCombo(comboStr) {
        if (!comboStr) return ""
        var parts = comboStr.split("+")
        var mods = []
        var key = ""
        for (var i = 0; i < parts.length; i++) {
            var p = parts[i].trim().toUpperCase()
            if (!p) continue
            if (p === "SUPER" || p === "MOD4" || p === "WIN") mods.push("SUPER")
            else if (p === "CTRL" || p === "CONTROL") mods.push("CTRL")
            else if (p === "ALT" || p === "MOD1") mods.push("ALT")
            else if (p === "SHIFT") mods.push("SHIFT")
            else key = p
        }
        mods.sort()
        return mods.concat(key ? [key] : []).join(" + ")
    }

    function findConflict(combo, ignoreId) {
        var norm = normalizeCombo(combo)
        if (!norm || norm === "UNSET") return null
        for (var i = 0; i < root.allShortcuts.length; i++) {
            var s = root.allShortcuts[i]
            if (ignoreId && s.id === ignoreId) continue
            if (!s.combo || s.combo === "Unset") continue
            if (normalizeCombo(s.combo) === norm) {
                return s
            }
        }
        return null
    }

    // Convert Qt key event to standard string format
    function keyEventToString(event) {
        var parts = []
        if (event.modifiers & Qt.MetaModifier) parts.push("SUPER")
        if (event.modifiers & Qt.ControlModifier) parts.push("CTRL")
        if (event.modifiers & Qt.AltModifier) parts.push("ALT")
        if (event.modifiers & Qt.ShiftModifier) parts.push("SHIFT")

        var k = event.key
        var keyName = ""

        if (k >= Qt.Key_A && k <= Qt.Key_Z) {
            keyName = String.fromCharCode(k)
        } else if (k >= Qt.Key_0 && k <= Qt.Key_9) {
            keyName = String.fromCharCode(k)
        } else if (k >= Qt.Key_F1 && k <= Qt.Key_F12) {
            keyName = "F" + (k - Qt.Key_F1 + 1)
        } else {
            switch (k) {
                case Qt.Key_Return:
                case Qt.Key_Enter: keyName = "Return"; break;
                case Qt.Key_Space: keyName = "Space"; break;
                case Qt.Key_Tab:
                case Qt.Key_Backtab: keyName = "Tab"; break;
                case Qt.Key_Backspace: keyName = "BackSpace"; break;
                case Qt.Key_Delete: keyName = "Delete"; break;
                case Qt.Key_Escape: keyName = "Escape"; break;
                case Qt.Key_Left: keyName = "left"; break;
                case Qt.Key_Right: keyName = "right"; break;
                case Qt.Key_Up: keyName = "up"; break;
                case Qt.Key_Down: keyName = "down"; break;
                case Qt.Key_Print: keyName = "Print"; break;
                case Qt.Key_Minus: keyName = "minus"; break;
                case Qt.Key_Equal: keyName = "equal"; break;
                case Qt.Key_BracketLeft: keyName = "bracketleft"; break;
                case Qt.Key_BracketRight: keyName = "bracketright"; break;
                case Qt.Key_Semicolon: keyName = "semicolon"; break;
                case Qt.Key_Apostrophe: keyName = "apostrophe"; break;
                case Qt.Key_Comma: keyName = "comma"; break;
                case Qt.Key_Period: keyName = "period"; break;
                case Qt.Key_Slash: keyName = "slash"; break;
                case Qt.Key_Backslash: keyName = "backslash"; break;
                case Qt.Key_Grave: keyName = "grave"; break;
                default:
                    if (k === Qt.Key_Super_L || k === Qt.Key_Super_R ||
                        k === Qt.Key_Control || k === Qt.Key_Alt || k === Qt.Key_Shift) {
                        return ""
                    }
                    keyName = event.text ? event.text.toUpperCase() : ""
                    break;
            }
        }

        if (!keyName) return ""
        parts.push(keyName)
        return parts.join(" + ")
    }

    // Handles keypress commit from recorder
    function handleRecordedCombo(combo) {
        if (!combo) return

        if (root.isRecordingCustomModal) {
            var conflictCustom = findConflict(combo, "")
            if (conflictCustom) {
                root.conflictItem = conflictCustom
                root.pendingCombo = combo
                root.pendingTargetId = "__custom__"
                root.showConflictModal = true
            } else {
                root.newCustomCombo = combo
            }
            root.isRecordingCustomModal = false
            root.isRecording = false
            return
        }

        var targetId = root.recordingId
        var conflict = findConflict(combo, targetId)
        if (conflict) {
            root.conflictItem = conflict
            root.pendingCombo = combo
            root.pendingTargetId = targetId
            root.showConflictModal = true
        } else {
            root.assignShortcut(targetId, combo)
        }

        root.isRecording = false
        root.recordingId = ""
        root.recordingTitle = ""
    }

    // Advanced search normalization helper
    function normalizeSearchKey(str) {
        if (!str) return ""
        return String(str).toLowerCase()
            .replace(/[\s\+\-_]+/g, "")
            .replace(/win|meta|mod4/g, "super")
            .replace(/control/g, "ctrl")
            .replace(/enter/g, "return")
    }

    // Filtered shortcuts model
    readonly property var filteredShortcuts: {
        var res = []
        var rawQ = root.searchQuery.trim().toLowerCase()
        var qNorm = root.normalizeSearchKey(rawQ)
        var cat = root.selectedCategory

        for (var i = 0; i < root.allShortcuts.length; i++) {
            var s = root.allShortcuts[i]
            // Category check
            if (cat !== "All") {
                if (cat === "Custom" && !s.is_custom) continue
                if (cat === "Shell & Mode" && !(s.category === "Shell & Controls" || s.category.indexOf("Active Mode") !== -1)) continue
                if (cat !== "Custom" && cat !== "Shell & Mode" && s.category !== cat) continue
            }

            // Query check (supports searching by action name, desc, or shortcut combo like SUPER+L)
            if (rawQ.length > 0) {
                var titleMatch = (s.title || "").toLowerCase().indexOf(rawQ) !== -1
                var descMatch = (s.desc || "").toLowerCase().indexOf(rawQ) !== -1
                var catMatch = (s.category || "").toLowerCase().indexOf(rawQ) !== -1

                // Search through shortcut key combination (e.g. "super+l", "super l", "super+return")
                var comboNorm = root.normalizeSearchKey(s.combo)
                var defaultComboNorm = root.normalizeSearchKey(s.default_combo)
                var comboMatch = (comboNorm.indexOf(qNorm) !== -1) || (defaultComboNorm.indexOf(qNorm) !== -1)

                if (!titleMatch && !descMatch && !comboMatch && !catMatch) {
                    continue
                }
            }

            res.push(s)
        }
        return res
    }

    Component.onCompleted: {
        root.loadShortcuts()
    }

    // =========================================================================
    // GLOBAL KEY INTERCEPTOR FOR RECORDING
    // =========================================================================
    Item {
        id: keyRecorderScope
        anchors.fill: parent
        focus: root.isRecording
        Keys.enabled: root.isRecording
        Keys.priority: Keys.BeforeItem

        Keys.onEscapePressed: (event) => {
            event.accepted = true
            root.isRecording = false
            root.isRecordingCustomModal = false
            root.recordingId = ""
            root.recordingTitle = ""
        }

        Keys.onPressed: (event) => {
            if (!root.isRecording) return
            event.accepted = true
            var combo = root.keyEventToString(event)
            if (combo.length > 0) {
                root.handleRecordedCombo(combo)
            }
        }
    }

    // =========================================================================
    // MAIN TAB LAYOUT
    // =========================================================================
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.px(20)
        spacing: Theme.px(14)

        // ---------------------------------------------------------------------
        // TOP CONTROL BAR: Title, Presets, Add Custom, Reset, Export
        // ---------------------------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.px(10)

            ColumnLayout {
                spacing: Theme.px(2)
                Text {
                    text: "KEYBOARD SHORTCUTS"
                    font.family: Theme.font
                    font.pixelSize: Theme.fontPx(13)
                    font.weight: Font.Bold
                    color: Qt.rgba(1, 1, 1, 0.90)
                }
                Text {
                    text: "Manage desktop hotkeys, active mode triggers, presets, and custom scripts."
                    font.family: Theme.font
                    font.pixelSize: Theme.fontPx(11)
                    color: Qt.rgba(1, 1, 1, 0.45)
                }
            }

            Item { Layout.fillWidth: true }

            // Preset Pills
            RowLayout {
                spacing: Theme.px(6)
                Text {
                    text: "PRESET:"
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fontPx(10)
                    font.weight: Font.Bold
                    color: Qt.rgba(1, 1, 1, 0.40)
                    Layout.alignment: Qt.AlignVCenter
                }

                Repeater {
                    model: [
                        { id: "carbon_default", label: "Carbon" },
                        { id: "tiling_i3", label: "Tiling (i3)" },
                        { id: "macos_gnome", label: "macOS" }
                    ]
                    delegate: Rectangle {
                        readonly property bool isSelected: root.activePreset === modelData.id
                        Layout.preferredHeight: Theme.px(28)
                        Layout.preferredWidth: presetLabel.implicitWidth + Theme.px(18)
                        radius: Theme.px(6)
                        color: isSelected ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.18) : (presetMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.03))
                        border.color: isSelected ? Theme.primary : Qt.rgba(1, 1, 1, 0.12)
                        border.width: 1

                        Text {
                            id: presetLabel
                            anchors.centerIn: parent
                            text: modelData.label
                            font.family: Theme.font
                            font.pixelSize: Theme.fontPx(11)
                            font.weight: parent.isSelected ? Font.Bold : Font.Normal
                            color: parent.isSelected ? Theme.primary : Qt.rgba(1, 1, 1, 0.70)
                        }

                        MouseArea {
                            id: presetMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: root.describe("Preset: " + modelData.label, "Switch entire system keybinding scheme to " + modelData.label + " defaults.")
                            onExited: root.clearDesc()
                            onClicked: root.applyPreset(modelData.id)
                        }
                    }
                }
            }

            // Add Custom Shortcut Button
            Rectangle {
                Layout.preferredHeight: Theme.px(28)
                Layout.preferredWidth: addLabel.implicitWidth + Theme.px(20)
                radius: Theme.px(6)
                color: addMouse.pressed ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.28) : (addMouse.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.20) : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12))
                border.color: Theme.primary
                border.width: 1

                RowLayout {
                    id: addLabel
                    anchors.centerIn: parent
                    spacing: Theme.px(6)
                    Text {
                        text: "＋"
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fontPx(12)
                        font.weight: Font.Bold
                        color: Theme.primary
                    }
                    Text {
                        text: "Add Shortcut"
                        font.family: Theme.font
                        font.pixelSize: Theme.fontPx(11)
                        font.weight: Font.DemiBold
                        color: Theme.primary
                    }
                }

                MouseArea {
                    id: addMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: root.describe("Add Custom Shortcut", "Create and bind a new custom terminal command, shell script, or app hotkey.")
                    onExited: root.clearDesc()
                    onClicked: {
                        root.newCustomTitle = ""
                        root.newCustomCommand = ""
                        root.newCustomCombo = ""
                        root.showAddCustomModal = true
                    }
                }
            }

            // Export Button
            Rectangle {
                Layout.preferredHeight: Theme.px(28)
                Layout.preferredWidth: Theme.px(32)
                radius: Theme.px(6)
                color: exportMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.04)
                border.color: Qt.rgba(1, 1, 1, 0.15)
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: "󰩹"
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fontPx(13)
                    color: Qt.rgba(1, 1, 1, 0.70)
                }

                MouseArea {
                    id: exportMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: root.describe("Export Shortcuts", "Export all system and custom shortcuts to a backup JSON file in your home directory.")
                    onExited: root.clearDesc()
                    onClicked: root.exportShortcuts()
                }
            }

            // Reset Defaults Button
            Rectangle {
                Layout.preferredHeight: Theme.px(28)
                Layout.preferredWidth: Theme.px(32)
                radius: Theme.px(6)
                color: resetAllMouse.containsMouse ? Qt.rgba(249/255, 115/255, 134/255, 0.20) : Qt.rgba(1, 1, 1, 0.04)
                border.color: resetAllMouse.containsMouse ? Theme.error : Qt.rgba(1, 1, 1, 0.15)
                border.width: 1

                Text {
                    anchors.centerIn: parent
                    text: "󰁯"
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fontPx(13)
                    color: resetAllMouse.containsMouse ? Theme.error : Qt.rgba(1, 1, 1, 0.70)
                }

                MouseArea {
                    id: resetAllMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: root.describe("Reset All Shortcuts", "Revert all keybindings back to factory Carbon Shell defaults.")
                    onExited: root.clearDesc()
                    onClicked: root.resetAllShortcuts()
                }
            }
        }

        // ---------------------------------------------------------------------
        // SUPER KEY "TAP" TRIGGER CARD
        // ---------------------------------------------------------------------
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.px(58)
            radius: Theme.px(8)
            color: root.tapSuperEnabled ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.08) : Qt.rgba(0, 0, 0, 0.25)
            border.color: root.tapSuperEnabled ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.35) : Qt.rgba(1, 1, 1, 0.08)
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.px(16)
                anchors.rightMargin: Theme.px(16)
                spacing: Theme.px(14)

                // Keycap graphic
                Rectangle {
                    width: Theme.px(32)
                    height: Theme.px(28)
                    radius: Theme.px(4)
                    color: Qt.rgba(1, 1, 1, 0.08)
                    border.color: root.tapSuperEnabled ? Theme.primary : Qt.rgba(1, 1, 1, 0.20)
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "󰘳"
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fontPx(14)
                        color: root.tapSuperEnabled ? Theme.primary : Qt.rgba(1, 1, 1, 0.70)
                    }
                }

                ColumnLayout {
                    spacing: Theme.px(2)
                    RowLayout {
                        spacing: Theme.px(6)
                        Text {
                            text: "Standalone Super Key Tap Trigger"
                            font.family: Theme.font
                            font.pixelSize: Theme.fontPx(12)
                            font.weight: Font.DemiBold
                            color: Qt.rgba(1, 1, 1, 0.90)
                        }
                        Rectangle {
                            visible: root.activeBarMode === "vanish" || root.activeBarMode === "nucleus"
                            Layout.preferredHeight: Theme.px(16)
                            Layout.preferredWidth: modeNote.implicitWidth + Theme.px(10)
                            radius: Theme.px(3)
                            color: Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.16)
                            border.color: Theme.secondary
                            border.width: 1

                            Text {
                                id: modeNote
                                anchors.centerIn: parent
                                text: "ACTIVE IN VANISH MODE"
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fontPx(9)
                                font.weight: Font.Bold
                                color: Theme.secondary
                            }
                        }
                    }

                    Text {
                        text: (root.activeBarMode === "vanish" || root.activeBarMode === "nucleus") ? "In Vanish mode, tapping Super opens the Central Clock Orb & Orbital Satellites." : "Quickly tap and release the Super key alone without disturbing modifier chords."
                        font.family: Theme.font
                        font.pixelSize: Theme.fontPx(10)
                        color: Qt.rgba(1, 1, 1, 0.45)
                    }
                }

                Item { Layout.fillWidth: true }

                // Action Selector
                RowLayout {
                    spacing: Theme.px(6)
                    visible: root.tapSuperEnabled

                    Repeater {
                        model: [
                            { id: "spotlight", label: "Spotlight" },
                            { id: "overview", label: "Overview" },
                            { id: "command-center", label: "Command Center" },
                            { id: "carbon-drop", label: "Carbon Drop" }
                        ]
                        delegate: Rectangle {
                            readonly property bool isSelected: root.tapSuperAction === modelData.id
                            Layout.preferredHeight: Theme.px(26)
                            Layout.preferredWidth: tapActionText.implicitWidth + Theme.px(14)
                            radius: Theme.px(4)
                            color: isSelected ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.22) : Qt.rgba(1, 1, 1, 0.04)
                            border.color: isSelected ? Theme.primary : Qt.rgba(1, 1, 1, 0.10)
                            border.width: 1

                            Text {
                                id: tapActionText
                                anchors.centerIn: parent
                                text: modelData.label
                                font.family: Theme.font
                                font.pixelSize: Theme.fontPx(10)
                                font.weight: parent.isSelected ? Font.Bold : Font.Normal
                                color: parent.isSelected ? Theme.primary : Qt.rgba(1, 1, 1, 0.65)
                            }

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.setTapSuper(true, modelData.id)
                            }
                        }
                    }
                }

                // Toggle Switch
                TerminalStatusBadge {
                    checked: root.tapSuperEnabled
                    interactive: true
                    onClicked: root.setTapSuper(checked, root.tapSuperAction)
                }
            }
        }

        // ---------------------------------------------------------------------
        // SEARCH BAR & CATEGORY FILTER TABS
        // ---------------------------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.px(10)

            // Search Bar
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.px(36)
                radius: Theme.px(6)
                color: Qt.rgba(0, 0, 0, 0.30)
                border.color: searchInput.activeFocus ? Theme.primary : Qt.rgba(1, 1, 1, 0.12)
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.px(10)
                    anchors.rightMargin: Theme.px(10)
                    spacing: Theme.px(8)

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
                        color: Qt.rgba(1, 1, 1, 0.90)
                        clip: true
                        selectByMouse: true
                        text: root.searchQuery
                        onTextChanged: root.searchQuery = text

                        Text {
                            anchors.fill: parent
                            visible: parent.text.length === 0 && !parent.activeFocus
                            text: "Search shortcuts by name, action, or press combo (e.g. SUPER+L, Return, F11)..."
                            font.family: Theme.font
                            font.pixelSize: Theme.fontPx(11)
                            color: Qt.rgba(1, 1, 1, 0.30)
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    Text {
                        visible: root.searchQuery.length > 0
                        text: "✕"
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fontPx(12)
                        color: Qt.rgba(1, 1, 1, 0.50)

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                searchInput.text = ""
                                root.searchQuery = ""
                            }
                        }
                    }
                }
            }

            // Category Filter Pills
            RowLayout {
                spacing: Theme.px(4)
                Repeater {
                    model: [
                        { name: "All", label: "ALL" },
                        { name: "Shell & Mode", label: "SHELL" },
                        { name: "Window Management", label: "WINDOWS" },
                        { name: "Applications", label: "APPS" },
                        { name: "Hardware & Media", label: "HARDWARE" },
                        { name: "Workspaces", label: "SPACES" },
                        { name: "Custom", label: "CUSTOM" }
                    ]

                    delegate: Rectangle {
                        readonly property bool isSelected: root.selectedCategory === modelData.name
                        Layout.preferredHeight: Theme.px(36)
                        Layout.preferredWidth: catText.implicitWidth + Theme.px(18)
                        radius: Theme.px(6)
                        color: isSelected ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.16) : (catMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(0, 0, 0, 0.20))
                        border.color: isSelected ? Theme.primary : Qt.rgba(1, 1, 1, 0.08)
                        border.width: 1

                        Text {
                            id: catText
                            anchors.centerIn: parent
                            text: modelData.label
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.fontPx(10)
                            font.weight: parent.isSelected ? Font.Bold : Font.Normal
                            color: parent.isSelected ? Theme.primary : Qt.rgba(1, 1, 1, 0.60)
                        }

                        MouseArea {
                            id: catMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.selectedCategory = modelData.name
                        }
                    }
                }
            }
        }

        // ---------------------------------------------------------------------
        // SHORTCUTS LIST VIEW
        // ---------------------------------------------------------------------
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            ListView {
                id: shortcutsList
                anchors.fill: parent
                clip: true
                spacing: Theme.px(6)
                model: root.filteredShortcuts
                boundsBehavior: Flickable.StopAtBounds

                delegate: Rectangle {
                    id: delegateCard
                    width: shortcutsList.width
                    height: Theme.px(56)
                    radius: Theme.px(6)
                    readonly property bool isRowRecording: root.isRecording && root.recordingId === modelData.id
                    color: isRowRecording ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12) : (itemMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : Qt.rgba(0, 0, 0, 0.22))
                    border.color: isRowRecording ? Theme.primary : (itemMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.07))
                    border.width: isRowRecording ? 2 : 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.px(14)
                        anchors.rightMargin: Theme.px(14)
                        spacing: Theme.px(12)

                        // Category Badge
                        Rectangle {
                            Layout.preferredWidth: catBadgeText.implicitWidth + Theme.px(12)
                            Layout.preferredHeight: Theme.px(22)
                            radius: Theme.px(4)
                            color: modelData.is_custom ? Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.16) : ((modelData.category && modelData.category.indexOf("Active Mode") !== -1) ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.16) : Qt.rgba(1, 1, 1, 0.05))
                            border.color: modelData.is_custom ? Theme.secondary : ((modelData.category && modelData.category.indexOf("Active Mode") !== -1) ? Theme.primary : Qt.rgba(1, 1, 1, 0.12))
                            border.width: 1

                            Text {
                                id: catBadgeText
                                anchors.centerIn: parent
                                text: modelData.is_custom ? "CUSTOM" : ((modelData.category && modelData.category.indexOf("Active Mode") !== -1) ? "MODE" : (modelData.category || "GENERAL").toUpperCase())
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fontPx(9)
                                font.weight: Font.Bold
                                color: modelData.is_custom ? Theme.secondary : ((modelData.category && modelData.category.indexOf("Active Mode") !== -1) ? Theme.primary : Qt.rgba(1, 1, 1, 0.50))
                            }
                        }

                        // Title & Description
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Theme.px(2)

                            Text {
                                text: modelData.title
                                font.family: Theme.font
                                font.pixelSize: Theme.fontPx(12)
                                font.weight: Font.DemiBold
                                color: (modelData.combo === "Unset") ? Qt.rgba(1, 1, 1, 0.50) : Qt.rgba(1, 1, 1, 0.92)
                                elide: Text.ElideRight
                            }

                            Text {
                                text: (modelData.combo === "Unset") ? "Disabled / Unbound" : (modelData.desc || modelData.target || "")
                                font.family: Theme.font
                                font.pixelSize: Theme.fontPx(10)
                                color: (modelData.combo === "Unset") ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.70) : Qt.rgba(1, 1, 1, 0.45)
                                elide: Text.ElideRight
                            }
                        }

                        // =====================================================
                        // RIGHT SIDE: DEDICATED FIXED-WIDTH KEYCAP / RECORDER CONTAINER
                        // Fixes off-place text bug with a stable, beautifully aligned box!
                        // =====================================================
                        Item {
                            id: keyContainer
                            Layout.preferredWidth: delegateCard.isRowRecording ? Theme.px(230) : Math.max(Theme.px(150), keyPillRow.implicitWidth + Theme.px(16))
                            Layout.preferredHeight: Theme.px(34)
                            Layout.alignment: Qt.AlignVCenter

                            // RECORDING ACTIVE STATE: Glowing, centered, with Cancel pill
                            Rectangle {
                                anchors.fill: parent
                                visible: delegateCard.isRowRecording
                                radius: Theme.px(6)
                                color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.22)
                                border.color: Theme.primary
                                border.width: 1

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Theme.px(10)
                                    anchors.rightMargin: Theme.px(8)
                                    spacing: Theme.px(8)

                                    Text {
                                        text: "⌨"
                                        font.pixelSize: Theme.fontPx(13)
                                        color: Theme.primary
                                    }

                                    Text {
                                        text: "Press Keys..."
                                        font.family: Theme.fontMono
                                        font.pixelSize: Theme.fontPx(11)
                                        font.weight: Font.Bold
                                        color: Theme.primary
                                        Layout.fillWidth: true
                                    }

                                    // Small Cancel Button
                                    Rectangle {
                                        Layout.preferredWidth: Theme.px(54)
                                        Layout.preferredHeight: Theme.px(22)
                                        radius: Theme.px(4)
                                        color: cancelRecMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(1, 1, 1, 0.10)
                                        border.color: Qt.rgba(1, 1, 1, 0.25)
                                        border.width: 1

                                        Text {
                                            anchors.centerIn: parent
                                            text: "Cancel"
                                            font.family: Theme.fontMono
                                            font.pixelSize: Theme.fontPx(9)
                                            font.weight: Font.DemiBold
                                            color: Qt.rgba(1, 1, 1, 0.85)
                                        }

                                        MouseArea {
                                            id: cancelRecMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.isRecording = false
                                                root.recordingId = ""
                                                root.recordingTitle = ""
                                            }
                                        }
                                    }
                                }
                            }

                            // NORMAL STATE: Tactile Keycaps (Clickable to Rebind)
                            Rectangle {
                                anchors.fill: parent
                                visible: !delegateCard.isRowRecording
                                radius: Theme.px(6)
                                color: keyCapArea.containsMouse && modelData.can_edit ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.08) : Qt.rgba(1, 1, 1, 0.03)
                                border.color: keyCapArea.containsMouse && modelData.can_edit ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.35) : "transparent"
                                border.width: 1

                                RowLayout {
                                    id: keyPillRow
                                    anchors.centerIn: parent
                                    spacing: Theme.px(4)

                                    Repeater {
                                        model: (modelData.combo && modelData.combo !== "Unset") ? modelData.combo.split("+") : ["Unset"]

                                        delegate: Rectangle {
                                            readonly property bool isUnset: modelData.trim() === "Unset"
                                            Layout.preferredHeight: Theme.px(24)
                                            Layout.preferredWidth: Math.max(Theme.px(26), keyCapText.implicitWidth + Theme.px(10))
                                            radius: Theme.px(4)
                                            color: isUnset ? Qt.rgba(249/255, 115/255, 134/255, 0.12) : Qt.rgba(1, 1, 1, 0.08)
                                            border.color: isUnset ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.40) : Qt.rgba(1, 1, 1, 0.20)
                                            border.width: 1

                                            Text {
                                                id: keyCapText
                                                anchors.centerIn: parent
                                                text: modelData.trim()
                                                font.family: Theme.fontMono
                                                font.pixelSize: Theme.fontPx(10)
                                                font.weight: Font.Bold
                                                color: isUnset ? Theme.error : Qt.rgba(1, 1, 1, 0.85)
                                            }
                                        }
                                    }
                                }

                                MouseArea {
                                    id: keyCapArea
                                    anchors.fill: parent
                                    enabled: Boolean(modelData.can_edit)
                                    hoverEnabled: Boolean(modelData.can_edit)
                                    cursorShape: modelData.can_edit ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    onEntered: if (modelData.can_edit) root.describe("Rebind Shortcut", "Click to press new keys and reassign " + modelData.title + ".")
                                    onExited: root.clearDesc()
                                    onClicked: {
                                        if (modelData.can_edit) {
                                            root.recordingId = modelData.id
                                            root.recordingTitle = modelData.title
                                            root.isRecordingCustomModal = false
                                            root.isRecording = true
                                            keyRecorderScope.forceActiveFocus()
                                        }
                                    }
                                }
                            }
                        }

                        // =====================================================
                        // ACTION BUTTONS: Edit, Restore Default, Delete / Unbind
                        // =====================================================
                        RowLayout {
                            spacing: Theme.px(4)

                            // Edit / Rebind Key Button
                            Rectangle {
                                visible: Boolean(modelData.can_edit)
                                Layout.preferredWidth: Theme.px(28)
                                Layout.preferredHeight: Theme.px(28)
                                radius: Theme.px(4)
                                color: editKeyMouse.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.18) : Qt.rgba(1, 1, 1, 0.04)
                                border.color: editKeyMouse.containsMouse ? Theme.primary : Qt.rgba(1, 1, 1, 0.10)
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰏫"
                                    font.family: Theme.fontMono
                                    font.pixelSize: Theme.fontPx(12)
                                    color: editKeyMouse.containsMouse ? Theme.primary : Qt.rgba(1, 1, 1, 0.65)
                                }

                                MouseArea {
                                    id: editKeyMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onEntered: root.describe("Rebind Shortcut", "Click then press desired keys on keyboard to reassign " + modelData.title + ".")
                                    onExited: root.clearDesc()
                                    onClicked: {
                                        root.recordingId = modelData.id
                                        root.recordingTitle = modelData.title
                                        root.isRecordingCustomModal = false
                                        root.isRecording = true
                                        keyRecorderScope.forceActiveFocus()
                                    }
                                }
                            }

                            // Restore / Reset Single Button (visible if altered or disabled)
                            Rectangle {
                                visible: !modelData.is_custom && (modelData.combo !== modelData.default_combo || modelData.combo === "Unset")
                                Layout.preferredWidth: Theme.px(28)
                                Layout.preferredHeight: Theme.px(28)
                                radius: Theme.px(4)
                                color: resetSingleMouse.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15) : Qt.rgba(1, 1, 1, 0.04)
                                border.color: resetSingleMouse.containsMouse ? Theme.primary : Qt.rgba(1, 1, 1, 0.10)
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰁯"
                                    font.family: Theme.fontMono
                                    font.pixelSize: Theme.fontPx(12)
                                    color: resetSingleMouse.containsMouse ? Theme.primary : Qt.rgba(1, 1, 1, 0.60)
                                }

                                MouseArea {
                                    id: resetSingleMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onEntered: root.describe("Restore to Default", "Restore " + modelData.title + " back to factory combo: " + modelData.default_combo)
                                    onExited: root.clearDesc()
                                    onClicked: root.restoreSingleShortcut(modelData.id)
                                }
                            }

                            // Delete / Unbind Button (for ALL editable shortcuts)
                            Rectangle {
                                visible: Boolean(modelData.can_edit) && modelData.combo !== "Unset"
                                Layout.preferredWidth: Theme.px(28)
                                Layout.preferredHeight: Theme.px(28)
                                radius: Theme.px(4)
                                color: deleteMouse.containsMouse ? Qt.rgba(249/255, 115/255, 134/255, 0.20) : Qt.rgba(1, 1, 1, 0.04)
                                border.color: deleteMouse.containsMouse ? Theme.error : Qt.rgba(1, 1, 1, 0.10)
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: "󰆴"
                                    font.family: Theme.fontMono
                                    font.pixelSize: Theme.fontPx(12)
                                    color: deleteMouse.containsMouse ? Theme.error : Qt.rgba(1, 1, 1, 0.60)
                                }

                                MouseArea {
                                    id: deleteMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onEntered: root.describe("Delete / Unbind Shortcut", modelData.is_custom ? ("Delete custom shortcut: " + modelData.title) : ("Disable and unbind shortcut for " + modelData.title + "."))
                                    onExited: root.clearDesc()
                                    onClicked: root.deleteOrUnsetShortcut(modelData)
                                }
                            }
                        }
                    }

                    // Hover feedback for the entire card
                    MouseArea {
                        id: itemMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: modelData.can_edit ? Qt.PointingHandCursor : Qt.ArrowCursor
                        acceptedButtons: Qt.LeftButton
                        onEntered: root.describe(modelData.title, (modelData.combo === "Unset") ? "Currently disabled. Click edit or restore to re-enable." : (modelData.desc || modelData.target || ""))
                        onExited: root.clearDesc()
                        onClicked: {
                            if (modelData.can_edit && !delegateCard.isRowRecording) {
                                root.recordingId = modelData.id
                                root.recordingTitle = modelData.title
                                root.isRecordingCustomModal = false
                                root.isRecording = true
                                keyRecorderScope.forceActiveFocus()
                            }
                        }
                    }
                }
            }

            // Empty state placeholder
            ColumnLayout {
                anchors.centerIn: parent
                visible: root.filteredShortcuts.length === 0
                spacing: Theme.px(8)

                Text {
                    text: "󰌌"
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fontPx(32)
                    color: Qt.rgba(1, 1, 1, 0.20)
                    Layout.alignment: Qt.AlignHCenter
                }
                Text {
                    text: "No shortcuts match \"" + root.searchQuery + "\""
                    font.family: Theme.font
                    font.pixelSize: Theme.fontPx(13)
                    color: Qt.rgba(1, 1, 1, 0.40)
                    Layout.alignment: Qt.AlignHCenter
                }
            }
        }
    }

    // =========================================================================
    // MODAL DIALOG: CONFLICT DETECTION
    // =========================================================================
    Rectangle {
        id: conflictModalOverlay
        anchors.fill: parent
        visible: root.showConflictModal
        color: Qt.rgba(0, 0, 0, 0.70)
        z: 999

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.ArrowCursor
            onClicked: {}
        }

        Rectangle {
            anchors.centerIn: parent
            width: Theme.px(440)
            height: Theme.px(210)
            radius: Theme.px(10)
            color: Theme.surface
            border.color: Theme.error
            border.width: 1

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.px(20)
                spacing: Theme.px(12)

                RowLayout {
                    spacing: Theme.px(10)
                    Text {
                        text: "⚠️"
                        font.pixelSize: Theme.fontPx(20)
                    }
                    Text {
                        text: "Keybinding Conflict Detected"
                        font.family: Theme.font
                        font.pixelSize: Theme.fontPx(14)
                        font.weight: Font.Bold
                        color: Theme.error
                    }
                }

                Text {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: "The combination <b>" + root.pendingCombo + "</b> is already assigned to <b>" + (root.conflictItem ? root.conflictItem.title : "another action") + "</b>.<br><br>Would you like to reassign this shortcut? The previous assignment will be unset."
                    font.family: Theme.font
                    font.pixelSize: Theme.fontPx(11)
                    color: Qt.rgba(1, 1, 1, 0.85)
                }

                Item { Layout.fillHeight: true }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(10)

                    Item { Layout.fillWidth: true }

                    // Cancel Button
                    Rectangle {
                        Layout.preferredWidth: Theme.px(80)
                        Layout.preferredHeight: Theme.px(30)
                        radius: Theme.px(6)
                        color: Qt.rgba(1, 1, 1, 0.08)
                        border.color: Qt.rgba(1, 1, 1, 0.15)
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: "Cancel"
                            font.family: Theme.font
                            font.pixelSize: Theme.fontPx(11)
                            color: Qt.rgba(1, 1, 1, 0.80)
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.showConflictModal = false
                                root.conflictItem = null
                                root.pendingCombo = ""
                                root.pendingTargetId = ""
                            }
                        }
                    }

                    // Reassign Button
                    Rectangle {
                        Layout.preferredWidth: Theme.px(130)
                        Layout.preferredHeight: Theme.px(30)
                        radius: Theme.px(6)
                        color: Theme.error
                        border.color: "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: "Reassign Shortcut"
                            font.family: Theme.font
                            font.pixelSize: Theme.fontPx(11)
                            font.weight: Font.Bold
                            color: "#ffffff"
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (root.conflictItem && root.conflictItem.id) {
                                    root.deleteOrUnsetShortcut(root.conflictItem)
                                }
                                if (root.pendingTargetId === "__custom__") {
                                    root.newCustomCombo = root.pendingCombo
                                } else if (root.pendingTargetId) {
                                    root.assignShortcut(root.pendingTargetId, root.pendingCombo)
                                }
                                root.showConflictModal = false
                                root.conflictItem = null
                                root.pendingCombo = ""
                                root.pendingTargetId = ""
                            }
                        }
                    }
                }
            }
        }
    }

    // =========================================================================
    // MODAL DIALOG: ADD CUSTOM SHORTCUT
    // =========================================================================
    Rectangle {
        id: addCustomModalOverlay
        anchors.fill: parent
        visible: root.showAddCustomModal
        color: Qt.rgba(0, 0, 0, 0.70)
        z: 998

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.ArrowCursor
            onClicked: {}
        }

        Rectangle {
            anchors.centerIn: parent
            width: Theme.px(480)
            height: Theme.px(330)
            radius: Theme.px(10)
            color: Theme.surface
            border.color: Qt.rgba(1, 1, 1, 0.15)
            border.width: 1

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.px(22)
                spacing: Theme.px(14)

                // Header
                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: "ADD CUSTOM SHORTCUT"
                        font.family: Theme.font
                        font.pixelSize: Theme.fontPx(13)
                        font.weight: Font.Bold
                        color: Theme.primary
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: "✕"
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fontPx(13)
                        color: Qt.rgba(1, 1, 1, 0.60)
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.showAddCustomModal = false
                        }
                    }
                }

                Text {
                    text: "Bind any arbitrary shell script, binary command, or application to a hotkey."
                    font.family: Theme.font
                    font.pixelSize: Theme.fontPx(11)
                    color: Qt.rgba(1, 1, 1, 0.45)
                }

                // Field 1: Action Name
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(4)
                    Text {
                        text: "SHORTCUT TITLE"
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fontPx(10)
                        font.weight: Font.Bold
                        color: Qt.rgba(1, 1, 1, 0.50)
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Theme.px(32)
                        radius: Theme.px(5)
                        color: Qt.rgba(0, 0, 0, 0.35)
                        border.color: nameInput.activeFocus ? Theme.primary : Qt.rgba(1, 1, 1, 0.12)
                        border.width: 1

                        TextInput {
                            id: nameInput
                            anchors.fill: parent
                            anchors.leftMargin: Theme.px(10)
                            anchors.rightMargin: Theme.px(10)
                            font.family: Theme.font
                            font.pixelSize: Theme.fontPx(11)
                            color: Qt.rgba(1, 1, 1, 0.90)
                            verticalAlignment: Text.AlignVCenter
                            clip: true
                            text: root.newCustomTitle
                            onTextChanged: root.newCustomTitle = text

                            Text {
                                anchors.fill: parent
                                visible: parent.text.length === 0 && !parent.activeFocus
                                text: "e.g. Open Obsidian or Toggle Discord Mute"
                                font.family: Theme.font
                                font.pixelSize: Theme.fontPx(11)
                                color: Qt.rgba(1, 1, 1, 0.30)
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                    }
                }

                // Field 2: Command / Script
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(4)
                    Text {
                        text: "TERMINAL COMMAND / EXECUTABLE"
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fontPx(10)
                        font.weight: Font.Bold
                        color: Qt.rgba(1, 1, 1, 0.50)
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Theme.px(32)
                        radius: Theme.px(5)
                        color: Qt.rgba(0, 0, 0, 0.35)
                        border.color: cmdInput.activeFocus ? Theme.primary : Qt.rgba(1, 1, 1, 0.12)
                        border.width: 1

                        TextInput {
                            id: cmdInput
                            anchors.fill: parent
                            anchors.leftMargin: Theme.px(10)
                            anchors.rightMargin: Theme.px(10)
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.fontPx(11)
                            color: Qt.rgba(1, 1, 1, 0.90)
                            verticalAlignment: Text.AlignVCenter
                            clip: true
                            text: root.newCustomCommand
                            onTextChanged: root.newCustomCommand = text

                            Text {
                                anchors.fill: parent
                                visible: parent.text.length === 0 && !parent.activeFocus
                                text: "e.g. flatpak run md.obsidian.Obsidian or ~/.config/carbon/scripts/myscript.sh"
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fontPx(10)
                                color: Qt.rgba(1, 1, 1, 0.30)
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                    }
                }

                // Field 3: Key Combination Recorder
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(4)
                    Text {
                        text: "KEY COMBINATION"
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fontPx(10)
                        font.weight: Font.Bold
                        color: Qt.rgba(1, 1, 1, 0.50)
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Theme.px(34)
                        radius: Theme.px(5)
                        color: (root.isRecording && root.isRecordingCustomModal) ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.20) : Qt.rgba(0, 0, 0, 0.35)
                        border.color: (root.isRecording && root.isRecordingCustomModal) ? Theme.primary : Qt.rgba(1, 1, 1, 0.12)
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.px(10)
                            anchors.rightMargin: Theme.px(10)
                            spacing: Theme.px(8)

                            Text {
                                text: (root.isRecording && root.isRecordingCustomModal) ? "⌨ Press Keys..." : (root.newCustomCombo ? root.newCustomCombo : "Click to record shortcut...")
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fontPx(11)
                                font.weight: (root.newCustomCombo || (root.isRecording && root.isRecordingCustomModal)) ? Font.Bold : Font.Normal
                                color: (root.isRecording && root.isRecordingCustomModal) ? Theme.primary : (root.newCustomCombo ? Qt.rgba(1, 1, 1, 0.90) : Qt.rgba(1, 1, 1, 0.35))
                                Layout.fillWidth: true
                            }

                            Rectangle {
                                Layout.preferredWidth: Theme.px(68)
                                Layout.preferredHeight: Theme.px(24)
                                radius: Theme.px(4)
                                color: Qt.rgba(1, 1, 1, 0.08)
                                border.color: Qt.rgba(1, 1, 1, 0.15)
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: (root.isRecording && root.isRecordingCustomModal) ? "Cancel" : "Record"
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontPx(10)
                                    color: Qt.rgba(1, 1, 1, 0.80)
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (root.isRecording && root.isRecordingCustomModal) {
                                            root.isRecording = false
                                            root.isRecordingCustomModal = false
                                        } else {
                                            root.isRecording = true
                                            root.isRecordingCustomModal = true
                                            root.recordingId = "__custom__"
                                            keyRecorderScope.forceActiveFocus()
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Item { Layout.fillHeight: true }

                // Actions: Cancel / Save
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(10)

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        Layout.preferredWidth: Theme.px(80)
                        Layout.preferredHeight: Theme.px(30)
                        radius: Theme.px(6)
                        color: Qt.rgba(1, 1, 1, 0.08)
                        border.color: Qt.rgba(1, 1, 1, 0.15)
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: "Cancel"
                            font.family: Theme.font
                            font.pixelSize: Theme.fontPx(11)
                            color: Qt.rgba(1, 1, 1, 0.80)
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.showAddCustomModal = false
                        }
                    }

                    Rectangle {
                        readonly property bool canSave: root.newCustomTitle.trim().length > 0 && root.newCustomCommand.trim().length > 0 && root.newCustomCombo.trim().length > 0
                        Layout.preferredWidth: Theme.px(120)
                        Layout.preferredHeight: Theme.px(30)
                        radius: Theme.px(6)
                        color: canSave ? Theme.primary : Qt.rgba(1, 1, 1, 0.10)
                        border.color: "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: "Save Shortcut"
                            font.family: Theme.font
                            font.pixelSize: Theme.fontPx(11)
                            font.weight: Font.Bold
                            color: parent.canSave ? Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 1.0) : Qt.rgba(1, 1, 1, 0.40)
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: parent.canSave
                            hoverEnabled: parent.canSave
                            cursorShape: parent.canSave ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                                Quickshell.execDetached([
                                    "python3", root.scriptPath, "add-custom",
                                    root.newCustomTitle.trim(),
                                    root.newCustomCommand.trim(),
                                    root.newCustomCombo.trim()
                                ])
                                root.showToast("Added custom shortcut: " + root.newCustomTitle)
                                root.showAddCustomModal = false
                                refreshTimer.restart()
                            }
                        }
                    }
                }
            }
        }
    }

    // =========================================================================
    // FLOATING TOAST NOTIFICATION
    // =========================================================================
    Rectangle {
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: Theme.px(16)
        width: toastText.implicitWidth + Theme.px(28)
        height: Theme.px(32)
        radius: Theme.px(16)
        color: Qt.rgba(0, 0, 0, 0.85)
        border.color: Theme.primary
        border.width: 1
        visible: root.toastVisible
        z: 1000

        Text {
            id: toastText
            anchors.centerIn: parent
            text: root.toastMessage
            font.family: Theme.font
            font.pixelSize: Theme.fontPx(11)
            font.weight: Font.DemiBold
            color: Theme.primary
        }
    }
}
