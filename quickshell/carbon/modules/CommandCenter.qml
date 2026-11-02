import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../Singletons"

/**
 * CommandCenter:
 * Sleek, modern bottom-up Notch Command Center for Carbon Shell.
 *
 * Sits anchored to the bottom with organic Material Design 3 / Caelestia styling:
 *   - Row 1: Obsidian Notes Tile (Left) + Events / Schedule Tile (Right)
 *   - Row 2: Recent Apps Tile (Compact Dock with icons only, dynamic length) + Clipboard History Tile (Right)
 *
 * Uses Theme.font ("Plus Jakarta Sans") and Theme.fontIcon ("Material Symbols Rounded")
 * to match Carbon Shell perfectly.
 */
PanelWindow {
    id: commandCenterWindow

    property bool isOpen: false
    property bool animatingOut: false
    signal closeRequested()

    WlrLayershell.namespace: "carbon-command-center"
    WlrLayershell.layer: WlrLayer.Top
    aboveWindows: true
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    anchors {
        bottom: true
        left: true
        right: true
    }
    implicitHeight: Theme.px(390)

    // Only visible when open or during slide-out animation to completely prevent blocking clicks/scrolls
    visible: isOpen || animatingOut
    WlrLayershell.keyboardFocus: (isOpen && !animatingOut) ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    onIsOpenChanged: {
        if (!isOpen) {
            animatingOut = true
            closeAnimTimer.restart()
        } else {
            animatingOut = false
            closeAnimTimer.stop()
        }
    }

    Timer {
        id: closeAnimTimer
        interval: 340
        onTriggered: {
            commandCenterWindow.animatingOut = false
        }
    }

    // Data models populated by carbon-radar-engine
    property var vaultItems: []
    property var clipboardItems: []
    property var appsItems: []
    property var agendaItems: []
    property bool engineConnected: false
    property string feedbackMessage: ""

    Timer {
        id: feedbackClearTimer
        interval: 2000
        onTriggered: commandCenterWindow.feedbackMessage = ""
    }

    function showFeedback(msg) {
        commandCenterWindow.feedbackMessage = msg
        feedbackClearTimer.restart()
    }

    // ── Engine Subprocess Pipe ──
    Process {
        id: radarEngineProc
        command: [
            "sh", "-c",
            "if command -v carbon-radar-engine >/dev/null 2>&1; then exec carbon-radar-engine; elif [ -x \"$HOME/.local/bin/carbon-radar-engine\" ]; then exec \"$HOME/.local/bin/carbon-radar-engine\"; elif [ -x \"/home/shogun/carbon-shell/apps/carbon-radar/target/release/carbon-radar-engine\" ]; then exec \"/home/shogun/carbon-shell/apps/carbon-radar/target/release/carbon-radar-engine\"; else exec carbon-radar-engine; fi"
        ]
        running: true
        stdinEnabled: true

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) {
                var raw = (line || "").trim()
                if (!raw) return
                try {
                    var payload = JSON.parse(raw)
                    if (!payload) return
                    if (payload.vault !== undefined) commandCenterWindow.vaultItems = payload.vault
                    if (payload.clipboard !== undefined) commandCenterWindow.clipboardItems = payload.clipboard
                    if (payload.apps !== undefined) commandCenterWindow.appsItems = payload.apps
                    if (payload.agenda !== undefined) commandCenterWindow.agendaItems = payload.agenda
                    commandCenterWindow.engineConnected = true
                } catch(e) {}
            }
        }
    }

    // Shell runner process for one-off actions
    Process {
        id: actionRunner
    }

    function execCommand(cmd) {
        actionRunner.command = ["sh", "-c", cmd]
        actionRunner.running = true
    }

    function openNote(notePath) {
        if (!notePath) return
        execCommand("xdg-open " + JSON.stringify(notePath) + " 2>/dev/null || true")
        showFeedback("Opening note")
    }

    function copyClipboard(clipId) {
        if (!clipId) return
        execCommand("echo -n " + JSON.stringify(clipId) + " | cliphist decode | wl-copy 2>/dev/null || true")
        showFeedback("Copied to clipboard")
    }

    function focusApp(appClass) {
        if (!appClass) return
        execCommand("hyprctl dispatch focuswindow " + JSON.stringify("class:" + appClass) + " 2>/dev/null || true")
        showFeedback("Focused: " + appClass)
    }

    function triggerManualRefresh() {
        if (radarEngineProc.running) {
            radarEngineProc.write("refresh\n")
        }
    }

    function resolveAppIcon(cls) {
        if (!cls) return ""
        var p = Quickshell.iconPath(cls, "")
        if (p) return p
        var c = cls.toLowerCase().trim()
        p = Quickshell.iconPath(c, "")
        if (p) return p
        var parts = cls.split(".")
        var last = parts[parts.length - 1]
        p = Quickshell.iconPath(last, "")
        if (p) return p
        p = Quickshell.iconPath(last.toLowerCase(), "")
        if (p) return p
        return Quickshell.iconPath("application-x-executable", "")
    }

    // Scrim overlay to dismiss on outside click (only active when open)
    MouseArea {
        anchors.fill: parent
        enabled: commandCenterWindow.isOpen
        onClicked: commandCenterWindow.closeRequested()
    }

    // ── Main Compact Floating Card ──
    Rectangle {
        id: mainPanel
        width: Math.min(Theme.px(640), parent.width - Theme.px(32))
        height: Theme.px(360)
        anchors.horizontalCenter: parent.horizontalCenter

        // Slide-up animation
        y: (commandCenterWindow.isOpen && !commandCenterWindow.animatingOut) ? Theme.px(16) : commandCenterWindow.implicitHeight

        Behavior on y {
            NumberAnimation {
                duration: 320
                easing.type: Easing.OutExpo
            }
        }

        // Carbon Shell Modern Frosted Glass Aesthetic
        color: Theme.isDark ? Qt.rgba(0.06, 0.07, 0.09, 0.90) : Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.90)
        border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.16)
        border.width: 1
        radius: Theme.px(16)
        clip: true

        // Absorb clicks inside card so they don't dismiss
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            preventStealing: true
            onClicked: {}
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.px(12)
            spacing: Theme.px(8)

            // ── Minimal Sleek Header ──
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.px(24)
                Layout.maximumHeight: Theme.px(24)
                spacing: Theme.px(8)

                // Drag pill / status indicator
                Rectangle {
                    width: Theme.px(8)
                    height: Theme.px(8)
                    radius: Theme.px(4)
                    color: commandCenterWindow.engineConnected ? Theme.accent : Theme.outline

                    SequentialAnimation on opacity {
                        loops: Animation.Infinite
                        running: true
                        NumberAnimation { from: 0.5; to: 1.0; duration: 900; easing.type: Easing.InOutQuad }
                        NumberAnimation { from: 1.0; to: 0.5; duration: 900; easing.type: Easing.InOutQuad }
                    }
                }

                Text {
                    text: "Command Center"
                    font.family: Theme.font
                    font.pixelSize: Theme.fontPx(12)
                    font.weight: Font.DemiBold
                    color: Theme.fg
                }

                Item { Layout.fillWidth: true }

                // Action Feedback Badge
                Rectangle {
                    visible: commandCenterWindow.feedbackMessage !== ""
                    Layout.preferredHeight: Theme.px(20)
                    Layout.preferredWidth: fbText.implicitWidth + Theme.px(14)
                    radius: Theme.px(10)
                    color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.15)
                    border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.3)
                    border.width: 1

                    Text {
                        id: fbText
                        anchors.centerIn: parent
                        text: commandCenterWindow.feedbackMessage
                        font.family: Theme.font
                        font.pixelSize: Theme.fontPx(10)
                        font.weight: Font.Medium
                        color: Theme.accentLit
                    }
                }

                // Refresh Button
                Rectangle {
                    width: Theme.px(24)
                    height: Theme.px(24)
                    radius: Theme.px(12)
                    color: rHover.hovered ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.08) : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "refresh"
                        font.family: Theme.fontIcon
                        font.pixelSize: Theme.fontPx(14)
                        color: rHover.hovered ? Theme.accent : Theme.fgDim
                    }

                    HoverHandler { id: rHover }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: commandCenterWindow.triggerManualRefresh()
                    }
                }

                // Close Button
                Rectangle {
                    width: Theme.px(24)
                    height: Theme.px(24)
                    radius: Theme.px(12)
                    color: cBtnHover.hovered ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.15) : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "close"
                        font.family: Theme.fontIcon
                        font.pixelSize: Theme.fontPx(14)
                        color: cBtnHover.hovered ? Theme.error : Theme.fgDim
                    }

                    HoverHandler { id: cBtnHover }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: commandCenterWindow.closeRequested()
                    }
                }
            }

            // ── ROW 1: Obsidian Notes (Left) + Events / Schedule (Right) ──
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.px(144)
                Layout.maximumHeight: Theme.px(144)
                spacing: Theme.px(8)

                // ══════════════════════════════════════════════════
                // TILE 1: OBSIDIAN NOTES
                // ══════════════════════════════════════════════════
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.035) : Qt.rgba(0, 0, 0, 0.03)
                    border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.12)
                    border.width: 1
                    radius: Theme.px(12)
                    clip: true

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.px(10)
                        spacing: Theme.px(6)

                        // Tile Header
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.px(6)

                            Text {
                                text: "description"
                                font.family: Theme.fontIcon
                                font.pixelSize: Theme.fontPx(14)
                                color: Theme.accent
                            }

                            Text {
                                text: "Obsidian Notes"
                                font.family: Theme.font
                                font.pixelSize: Theme.fontPx(11)
                                font.weight: Font.DemiBold
                                color: Theme.fg
                            }

                            Item { Layout.fillWidth: true }

                            Rectangle {
                                Layout.preferredHeight: Theme.px(16)
                                Layout.preferredWidth: vCountText.implicitWidth + Theme.px(10)
                                radius: Theme.px(8)
                                color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.06)

                                Text {
                                    id: vCountText
                                    anchors.centerIn: parent
                                    text: commandCenterWindow.vaultItems.length
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontPx(9)
                                    font.weight: Font.Bold
                                    color: Theme.fgDim
                                }
                            }
                        }

                        // Notes ListView
                        ListView {
                            id: vaultListView
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            model: commandCenterWindow.vaultItems
                            spacing: Theme.px(2)

                            ScrollBar.vertical: ScrollBar {
                                policy: ScrollBar.AsNeeded
                                contentItem: Rectangle {
                                    implicitWidth: Theme.px(3)
                                    radius: Theme.px(2)
                                    color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.3)
                                }
                            }

                            delegate: Item {
                                width: vaultListView.width
                                height: Theme.px(28)

                                HoverHandler { id: noteHover }

                                Rectangle {
                                    anchors.fill: parent
                                    radius: Theme.px(6)
                                    color: noteHover.hovered ? (Theme.isDark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(0, 0, 0, 0.06)) : "transparent"

                                    Behavior on color { ColorAnimation { duration: 120 } }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: Theme.px(6)
                                        anchors.rightMargin: Theme.px(6)
                                        spacing: Theme.px(8)

                                        Text {
                                            text: "draft"
                                            font.family: Theme.fontIcon
                                            font.pixelSize: Theme.fontPx(13)
                                            color: noteHover.hovered ? Theme.accent : Theme.fgDim
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.name
                                            elide: Text.ElideRight
                                            font.family: Theme.font
                                            font.pixelSize: Theme.fontPx(11)
                                            font.weight: noteHover.hovered ? Font.Medium : Font.Normal
                                            color: noteHover.hovered ? Theme.accentLit : Theme.fg
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: commandCenterWindow.openNote(modelData.path)
                                    }
                                }
                            }
                        }
                    }
                }

                // ══════════════════════════════════════════════════
                // TILE 2: EVENTS / SCHEDULE (Beside Obsidian Notes)
                // ══════════════════════════════════════════════════
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.035) : Qt.rgba(0, 0, 0, 0.03)
                    border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.12)
                    border.width: 1
                    radius: Theme.px(12)
                    clip: true

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.px(10)
                        spacing: Theme.px(6)

                        // Tile Header
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.px(6)

                            Text {
                                text: "calendar_today"
                                font.family: Theme.fontIcon
                                font.pixelSize: Theme.fontPx(14)
                                color: Theme.accent
                            }

                            Text {
                                text: "Events & Agenda"
                                font.family: Theme.font
                                font.pixelSize: Theme.fontPx(11)
                                font.weight: Font.DemiBold
                                color: Theme.fg
                            }

                            Item { Layout.fillWidth: true }

                            Rectangle {
                                Layout.preferredHeight: Theme.px(16)
                                Layout.preferredWidth: aCountText.implicitWidth + Theme.px(10)
                                radius: Theme.px(8)
                                color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.06)

                                Text {
                                    id: aCountText
                                    anchors.centerIn: parent
                                    text: commandCenterWindow.agendaItems.length
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontPx(9)
                                    font.weight: Font.Bold
                                    color: Theme.fgDim
                                }
                            }
                        }

                        // Agenda ListView
                        ListView {
                            id: agendaListView
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            model: commandCenterWindow.agendaItems
                            spacing: Theme.px(2)

                            ScrollBar.vertical: ScrollBar {
                                policy: ScrollBar.AsNeeded
                                contentItem: Rectangle {
                                    implicitWidth: Theme.px(3)
                                    radius: Theme.px(2)
                                    color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.3)
                                }
                            }

                            delegate: Item {
                                width: agendaListView.width
                                height: Theme.px(28)

                                HoverHandler { id: aHover }

                                Rectangle {
                                    anchors.fill: parent
                                    radius: Theme.px(6)
                                    color: aHover.hovered ? (Theme.isDark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(0, 0, 0, 0.06)) : "transparent"

                                    Behavior on color { ColorAnimation { duration: 120 } }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: Theme.px(6)
                                        anchors.rightMargin: Theme.px(6)
                                        spacing: Theme.px(8)

                                        // Date Pill
                                        Rectangle {
                                            Layout.preferredHeight: Theme.px(18)
                                            Layout.preferredWidth: dText.implicitWidth + Theme.px(10)
                                            radius: Theme.px(4)
                                            color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14)
                                            border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.28)
                                            border.width: 1

                                            Text {
                                                id: dText
                                                anchors.centerIn: parent
                                                text: modelData.date
                                                font.family: Theme.font
                                                font.pixelSize: Theme.fontPx(9)
                                                font.weight: Font.Bold
                                                color: Theme.accentLit
                                            }
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.title
                                            elide: Text.ElideRight
                                            font.family: Theme.font
                                            font.pixelSize: Theme.fontPx(11)
                                            color: aHover.hovered ? Theme.fg : Theme.fgDim
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── ROW 2: Recent Apps Tile (Left, Compact Dock) + Clipboard Tile (Right) ──
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: Theme.px(154)
                spacing: Theme.px(8)

                // ══════════════════════════════════════════════════
                // TILE 3: RECENT APPS (Compact Dock, Icons Only, Dynamic Length)
                // ══════════════════════════════════════════════════
                Item {
                    Layout.preferredWidth: Theme.px(48)
                    Layout.fillHeight: true

                    // Dynamic length card fitting only the active apps (max 5)
                    Rectangle {
                        anchors.top: parent.top
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Theme.px(44)
                        // Height dynamically hugs only the active apps (up to 5 max)
                        height: Math.max(Theme.px(36), commandCenterWindow.appsItems.length * Theme.px(36) + Theme.px(8))

                        color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.035) : Qt.rgba(0, 0, 0, 0.03)
                        border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.12)
                        border.width: 1
                        radius: Theme.px(10)
                        clip: true

                        Column {
                            anchors.fill: parent
                            anchors.margins: Theme.px(4)
                            spacing: Theme.px(4)

                            Repeater {
                                model: commandCenterWindow.appsItems

                                delegate: Item {
                                    width: parent.width
                                    height: Theme.px(32)

                                    HoverHandler { id: appHover }

                                    Rectangle {
                                        id: iconBg
                                        anchors.centerIn: parent
                                        width: Theme.px(28)
                                        height: Theme.px(28)
                                        radius: Theme.px(6)
                                        color: appHover.hovered ? (Theme.isDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08)) : "transparent"
                                        scale: appHover.hovered ? 1.15 : 1.0

                                        Behavior on scale {
                                            NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
                                        }
                                        Behavior on color {
                                            ColorAnimation { duration: 120 }
                                        }

                                        Image {
                                            id: appImg
                                            anchors.centerIn: parent
                                            width: Theme.px(20)
                                            height: Theme.px(20)
                                            source: commandCenterWindow.resolveAppIcon(modelData)
                                            sourceSize: Qt.size(40, 40)
                                            fillMode: Image.PreserveAspectFit
                                            visible: status === Image.Ready
                                        }

                                        Text {
                                            anchors.centerIn: parent
                                            visible: appImg.status !== Image.Ready
                                            text: "apps"
                                            font.family: Theme.fontIcon
                                            font.pixelSize: Theme.fontPx(16)
                                            color: appHover.hovered ? Theme.accent : Theme.fgDim
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: commandCenterWindow.focusApp(modelData)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ══════════════════════════════════════════════════
                // TILE 4: CLIPBOARD HISTORY (Beside Recent Apps)
                // ══════════════════════════════════════════════════
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.035) : Qt.rgba(0, 0, 0, 0.03)
                    border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.12)
                    border.width: 1
                    radius: Theme.px(12)
                    clip: true

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.px(10)
                        spacing: Theme.px(6)

                        // Tile Header
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.px(6)

                            Text {
                                text: "content_paste"
                                font.family: Theme.fontIcon
                                font.pixelSize: Theme.fontPx(14)
                                color: Theme.accent
                            }

                            Text {
                                text: "Clipboard Buffer"
                                font.family: Theme.font
                                font.pixelSize: Theme.fontPx(11)
                                font.weight: Font.DemiBold
                                color: Theme.fg
                            }

                            Item { Layout.fillWidth: true }

                            Rectangle {
                                Layout.preferredHeight: Theme.px(16)
                                Layout.preferredWidth: cCountText.implicitWidth + Theme.px(10)
                                radius: Theme.px(8)
                                color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.06)

                                Text {
                                    id: cCountText
                                    anchors.centerIn: parent
                                    text: commandCenterWindow.clipboardItems.length
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontPx(9)
                                    font.weight: Font.Bold
                                    color: Theme.fgDim
                                }
                            }
                        }

                        // Clipboard ListView
                        ListView {
                            id: clipListView
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            model: commandCenterWindow.clipboardItems
                            spacing: Theme.px(2)

                            ScrollBar.vertical: ScrollBar {
                                policy: ScrollBar.AsNeeded
                                contentItem: Rectangle {
                                    implicitWidth: Theme.px(3)
                                    radius: Theme.px(2)
                                    color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.3)
                                }
                            }

                            delegate: Item {
                                width: clipListView.width
                                height: Theme.px(28)

                                HoverHandler { id: clipHover }

                                Rectangle {
                                    anchors.fill: parent
                                    radius: Theme.px(6)
                                    color: clipHover.hovered ? (Theme.isDark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(0, 0, 0, 0.06)) : "transparent"

                                    Behavior on color { ColorAnimation { duration: 120 } }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: Theme.px(6)
                                        anchors.rightMargin: Theme.px(6)
                                        spacing: Theme.px(8)

                                        Text {
                                            text: "content_copy"
                                            font.family: Theme.fontIcon
                                            font.pixelSize: Theme.fontPx(13)
                                            color: clipHover.hovered ? Theme.accent : Theme.fgDim
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.preview
                                            elide: Text.ElideRight
                                            font.family: Theme.font
                                            font.pixelSize: Theme.fontPx(11)
                                            color: clipHover.hovered ? Theme.fg : Theme.fgDim
                                        }

                                        Text {
                                            visible: clipHover.hovered
                                            text: "Copy"
                                            font.family: Theme.font
                                            font.pixelSize: Theme.fontPx(9)
                                            font.weight: Font.Bold
                                            color: Theme.accentLit
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: commandCenterWindow.copyClipboard(modelData.id)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Keyboard listener for Escape key to dismiss
    Item {
        focus: commandCenterWindow.isOpen
        Keys.onEscapePressed: {
            commandCenterWindow.closeRequested()
        }
    }
}
