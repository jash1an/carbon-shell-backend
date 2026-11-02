import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../Singletons"

/**
 * CommandCenter:
 * Hybrid "Notch Command Center" Bottom-Up Panel for Carbon Shell.
 *
 * Sits anchored to the bottom of the screen (height: 600, WlrLayer.Top).
 * Houses a 760x580 child panel with magnetic slide-up animation (Easing.OutExpo, 450ms).
 * Subtractive / Blueprint aesthetic with 2x2 Grid:
 *   - Tile 1: Obsidian Vault (ListView + 4px custom ScrollBar + Mint kinetic hover)
 *   - Tile 2: System Radar (Running App Classes from Hyprland)
 *   - Tile 3: Clipboard History (ListView + 4px custom ScrollBar + Amber kinetic hover)
 *   - Tile 4: Mission Agenda / Schedule
 */
PanelWindow {
    id: commandCenterWindow

    property bool isOpen: false
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
    implicitHeight: 600

    // Data models populated by carbon-radar-engine
    property var vaultItems: []
    property var clipboardItems: []
    property var appsItems: []
    property var agendaItems: []
    property bool engineConnected: false
    property string feedbackMessage: ""

    Timer {
        id: feedbackClearTimer
        interval: 2200
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
                } catch(e) {
                    console.log("[CommandCenter] JSON Parse error: " + e)
                }
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
        showFeedback("OPENING: " + notePath.split("/").pop())
    }

    function copyClipboard(clipId) {
        if (!clipId) return
        execCommand("echo " + JSON.stringify(clipId) + " | cliphist decode | wl-copy 2>/dev/null || true")
        showFeedback("COPIED CLIP #" + clipId)
    }

    function focusApp(appClass) {
        if (!appClass) return
        execCommand("hyprctl dispatch focuswindow " + JSON.stringify("class:" + appClass) + " 2>/dev/null || true")
        showFeedback("FOCUSED: " + appClass)
    }

    function triggerManualRefresh() {
        if (radarEngineProc.running) {
            radarEngineProc.write("refresh\n")
        }
    }

    // Dismiss overlay background click detector
    MouseArea {
        anchors.fill: parent
        onClicked: {
            commandCenterWindow.closeRequested()
        }
    }

    // ── Main Floating Blueprint Panel ──
    Rectangle {
        id: mainPanel
        width: 760
        height: 580
        anchors.horizontalCenter: parent.horizontalCenter

        // Slide-up physics: y: isOpen ? 20 : 600 with Easing.OutExpo 450ms
        y: commandCenterWindow.isOpen ? 20 : 600

        Behavior on y {
            NumberAnimation {
                duration: 450
                easing.type: Easing.OutExpo
            }
        }

        // Subtractive panel styling
        color: Qt.rgba(5/255, 6/255, 8/255, 0.85)
        border.color: Qt.rgba(1, 1, 1, 0.15)
        border.width: 1
        radius: 12
        clip: true

        // Absorb mouse clicks inside the main panel so they don't dismiss the window
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            preventStealing: true
            onClicked: {}
        }

        // Subtle background grid aesthetic
        Item {
            anchors.fill: parent
            opacity: 0.15
            Canvas {
                anchors.fill: parent
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    ctx.strokeStyle = "rgba(255, 255, 255, 0.25)"
                    ctx.lineWidth = 0.5
                    var step = 20
                    for (var x = 0; x < width; x += step) {
                        ctx.beginPath()
                        ctx.moveTo(x, 0)
                        ctx.lineTo(x, height)
                        ctx.stroke()
                    }
                    for (var y = 0; y < height; y += step) {
                        ctx.beginPath()
                        ctx.moveTo(0, y)
                        ctx.lineTo(width, y)
                        ctx.stroke()
                    }
                }
            }
        }

        // ── Header Bar ──
        Rectangle {
            id: headerBar
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 44
            color: Qt.rgba(1, 1, 1, 0.03)
            border.color: Qt.rgba(1, 1, 1, 0.1)
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 12

                // Status Indicator
                Rectangle {
                    width: 8
                    height: 8
                    radius: 4
                    color: commandCenterWindow.engineConnected ? "#8ee8a8" : "#f5b86e"

                    SequentialAnimation on opacity {
                        loops: Animation.Infinite
                        running: true
                        NumberAnimation { from: 0.4; to: 1.0; duration: 800; easing.type: Easing.InOutQuad }
                        NumberAnimation { from: 1.0; to: 0.4; duration: 800; easing.type: Easing.InOutQuad }
                    }
                }

                // Monospace Title
                Text {
                    text: "// NOTCH COMMAND CENTER [RADAR LIVE]"
                    color: "#ffffff"
                    font.family: (typeof Theme !== "undefined" && Theme.fontMono) ? Theme.fontMono : "monospace"
                    font.pixelSize: 12
                    font.weight: Font.DemiBold
                }

                Item { Layout.fillWidth: true }

                // Dynamic Action Feedback Pill
                Rectangle {
                    visible: commandCenterWindow.feedbackMessage !== ""
                    Layout.preferredHeight: 22
                    Layout.preferredWidth: fbText.implicitWidth + 16
                    radius: 4
                    color: Qt.rgba(142/255, 232/255, 168/255, 0.15)
                    border.color: "#8ee8a8"
                    border.width: 1

                    Text {
                        id: fbText
                        anchors.centerIn: parent
                        text: commandCenterWindow.feedbackMessage
                        color: "#8ee8a8"
                        font.family: (typeof Theme !== "undefined" && Theme.fontMono) ? Theme.fontMono : "monospace"
                        font.pixelSize: 10
                    }
                }

                // Refresh Button
                Rectangle {
                    width: 26
                    height: 22
                    radius: 4
                    color: rHover.hovered ? Qt.rgba(1, 1, 1, 0.15) : Qt.rgba(1, 1, 1, 0.05)
                    border.color: Qt.rgba(1, 1, 1, 0.2)
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "󰑐"
                        color: "#cccccc"
                        font.pixelSize: 12
                    }

                    HoverHandler { id: rHover }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: commandCenterWindow.triggerManualRefresh()
                    }
                }

                // Close ESC button
                Rectangle {
                    width: 54
                    height: 22
                    radius: 4
                    color: cBtnHover.hovered ? Qt.rgba(245/255, 184/255, 110/255, 0.25) : Qt.rgba(1, 1, 1, 0.05)
                    border.color: cBtnHover.hovered ? "#f5b86e" : Qt.rgba(1, 1, 1, 0.2)
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: "ESC"
                        color: cBtnHover.hovered ? "#f5b86e" : "#aaaaaa"
                        font.family: (typeof Theme !== "undefined" && Theme.fontMono) ? Theme.fontMono : "monospace"
                        font.pixelSize: 11
                    }

                    HoverHandler { id: cBtnHover }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: commandCenterWindow.closeRequested()
                    }
                }
            }
        }

        // ── 2x2 Blueprint Grid ──
        GridLayout {
            id: blueprintGrid
            anchors.top: headerBar.bottom
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 12
            columns: 2
            rows: 2
            columnSpacing: 12
            rowSpacing: 12

            // ══════════════════════════════════════════════════════
            // TILE 1 (Top-Left): OBSIDIAN VAULT
            // ══════════════════════════════════════════════════════
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Qt.rgba(1, 1, 1, 0.02)
                border.color: Qt.rgba(1, 1, 1, 0.15)
                border.width: 1
                radius: 8
                clip: true

                // Blueprint Corner Accents
                Text { anchors.top: parent.top; anchors.left: parent.left; anchors.margins: 4; text: "┌"; color: Qt.rgba(1, 1, 1, 0.3); font.family: "monospace"; font.pixelSize: 10 }
                Text { anchors.top: parent.top; anchors.right: parent.right; anchors.margins: 4; text: "┐"; color: Qt.rgba(1, 1, 1, 0.3); font.family: "monospace"; font.pixelSize: 10 }
                Text { anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.margins: 4; text: "└"; color: Qt.rgba(1, 1, 1, 0.3); font.family: "monospace"; font.pixelSize: 10 }
                Text { anchors.bottom: parent.bottom; anchors.right: parent.right; anchors.margins: 4; text: "┘"; color: Qt.rgba(1, 1, 1, 0.3); font.family: "monospace"; font.pixelSize: 10 }

                // Tile Header
                RowLayout {
                    id: t1Header
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 10
                    spacing: 8

                    Text {
                        text: "// 01. OBSIDIAN VAULT"
                        color: "#8ee8a8"
                        font.family: (typeof Theme !== "undefined" && Theme.fontMono) ? Theme.fontMono : "monospace"
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: "[" + commandCenterWindow.vaultItems.length + " NOTES]"
                        color: Qt.rgba(1, 1, 1, 0.4)
                        font.family: (typeof Theme !== "undefined" && Theme.fontMono) ? Theme.fontMono : "monospace"
                        font.pixelSize: 10
                    }
                }

                // Vault Notes ListView
                ListView {
                    id: vaultListView
                    anchors.top: t1Header.bottom
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 8
                    clip: true
                    model: commandCenterWindow.vaultItems

                    // Clean 4px styled ScrollBar
                    ScrollBar.vertical: ScrollBar {
                        id: vaultScrollBar
                        policy: ScrollBar.AsNeeded
                        contentItem: Rectangle {
                            implicitWidth: 4
                            radius: 2
                            color: "#555555"
                        }
                    }

                    delegate: Item {
                        width: vaultListView.width
                        height: 34

                        HoverHandler { id: noteHover }

                        Rectangle {
                            anchors.fill: parent
                            color: noteHover.hovered ? Qt.rgba(142/255, 232/255, 168/255, 0.08) : "transparent"
                            radius: 4

                            Behavior on color { ColorAnimation { duration: 150 } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8

                                // Kinetic left indent
                                x: noteHover.hovered ? 8 : 0
                                Behavior on x {
                                    NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
                                }

                                Text {
                                    text: "󰠮"
                                    color: noteHover.hovered ? "#8ee8a8" : Qt.rgba(1, 1, 1, 0.4)
                                    font.pixelSize: 12
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.name
                                    elide: Text.ElideRight
                                    // Transition text color to Mint (#8ee8a8) on hover
                                    color: noteHover.hovered ? "#8ee8a8" : "#d0d0d0"
                                    font.family: (typeof Theme !== "undefined" && Theme.fontMono) ? Theme.fontMono : "monospace"
                                    font.pixelSize: 11

                                    Behavior on color { ColorAnimation { duration: 150 } }
                                }

                                Text {
                                    text: "MD"
                                    color: Qt.rgba(1, 1, 1, 0.25)
                                    font.family: (typeof Theme !== "undefined" && Theme.fontMono) ? Theme.fontMono : "monospace"
                                    font.pixelSize: 9
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

            // ══════════════════════════════════════════════════════
            // TILE 2 (Top-Right): SYSTEM RADAR / RUNNING APPS
            // ══════════════════════════════════════════════════════
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Qt.rgba(1, 1, 1, 0.02)
                border.color: Qt.rgba(1, 1, 1, 0.15)
                border.width: 1
                radius: 8
                clip: true

                // Blueprint Corner Accents
                Text { anchors.top: parent.top; anchors.left: parent.left; anchors.margins: 4; text: "┌"; color: Qt.rgba(1, 1, 1, 0.3); font.family: "monospace"; font.pixelSize: 10 }
                Text { anchors.top: parent.top; anchors.right: parent.right; anchors.margins: 4; text: "┐"; color: Qt.rgba(1, 1, 1, 0.3); font.family: "monospace"; font.pixelSize: 10 }
                Text { anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.margins: 4; text: "└"; color: Qt.rgba(1, 1, 1, 0.3); font.family: "monospace"; font.pixelSize: 10 }
                Text { anchors.bottom: parent.bottom; anchors.right: parent.right; anchors.margins: 4; text: "┘"; color: Qt.rgba(1, 1, 1, 0.3); font.family: "monospace"; font.pixelSize: 10 }

                // Tile Header
                RowLayout {
                    id: t2Header
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 10
                    spacing: 8

                    Text {
                        text: "// 02. SYSTEM RADAR"
                        color: "#8ee8a8"
                        font.family: (typeof Theme !== "undefined" && Theme.fontMono) ? Theme.fontMono : "monospace"
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: "[" + commandCenterWindow.appsItems.length + " ACTIVE]"
                        color: Qt.rgba(1, 1, 1, 0.4)
                        font.family: (typeof Theme !== "undefined" && Theme.fontMono) ? Theme.fontMono : "monospace"
                        font.pixelSize: 10
                    }
                }

                // Apps Radar View
                ListView {
                    id: appsListView
                    anchors.top: t2Header.bottom
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 8
                    clip: true
                    model: commandCenterWindow.appsItems

                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AsNeeded
                        contentItem: Rectangle {
                            implicitWidth: 4
                            radius: 2
                            color: "#555555"
                        }
                    }

                    delegate: Item {
                        width: appsListView.width
                        height: 36

                        HoverHandler { id: appHover }

                        Rectangle {
                            anchors.fill: parent
                            color: appHover.hovered ? Qt.rgba(142/255, 232/255, 168/255, 0.08) : Qt.rgba(1, 1, 1, 0.03)
                            border.color: appHover.hovered ? "#8ee8a8" : Qt.rgba(1, 1, 1, 0.1)
                            border.width: 1
                            radius: 4

                            Behavior on color { ColorAnimation { duration: 150 } }
                            Behavior on border.color { ColorAnimation { duration: 150 } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 8

                                x: appHover.hovered ? 6 : 0
                                Behavior on x {
                                    NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
                                }

                                Rectangle {
                                    width: 6
                                    height: 6
                                    radius: 3
                                    color: "#8ee8a8"
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: modelData
                                    elide: Text.ElideRight
                                    color: appHover.hovered ? "#8ee8a8" : "#ffffff"
                                    font.family: (typeof Theme !== "undefined" && Theme.fontMono) ? Theme.fontMono : "monospace"
                                    font.pixelSize: 11
                                    font.weight: Font.Medium
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                }

                                Text {
                                    text: "[FOCUS]"
                                    color: appHover.hovered ? "#8ee8a8" : Qt.rgba(1, 1, 1, 0.3)
                                    font.family: (typeof Theme !== "undefined" && Theme.fontMono) ? Theme.fontMono : "monospace"
                                    font.pixelSize: 9
                                }
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

            // ══════════════════════════════════════════════════════
            // TILE 3 (Bottom-Left): CLIPBOARD HISTORY
            // ══════════════════════════════════════════════════════
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Qt.rgba(1, 1, 1, 0.02)
                border.color: Qt.rgba(1, 1, 1, 0.15)
                border.width: 1
                radius: 8
                clip: true

                // Blueprint Corner Accents
                Text { anchors.top: parent.top; anchors.left: parent.left; anchors.margins: 4; text: "┌"; color: Qt.rgba(1, 1, 1, 0.3); font.family: "monospace"; font.pixelSize: 10 }
                Text { anchors.top: parent.top; anchors.right: parent.right; anchors.margins: 4; text: "┐"; color: Qt.rgba(1, 1, 1, 0.3); font.family: "monospace"; font.pixelSize: 10 }
                Text { anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.margins: 4; text: "└"; color: Qt.rgba(1, 1, 1, 0.3); font.family: "monospace"; font.pixelSize: 10 }
                Text { anchors.bottom: parent.bottom; anchors.right: parent.right; anchors.margins: 4; text: "┘"; color: Qt.rgba(1, 1, 1, 0.3); font.family: "monospace"; font.pixelSize: 10 }

                // Tile Header
                RowLayout {
                    id: t3Header
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 10
                    spacing: 8

                    Text {
                        text: "// 03. CLIPBOARD BUFFER"
                        color: "#f5b86e"
                        font.family: (typeof Theme !== "undefined" && Theme.fontMono) ? Theme.fontMono : "monospace"
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: "[" + commandCenterWindow.clipboardItems.length + " CLIPS]"
                        color: Qt.rgba(1, 1, 1, 0.4)
                        font.family: (typeof Theme !== "undefined" && Theme.fontMono) ? Theme.fontMono : "monospace"
                        font.pixelSize: 10
                    }
                }

                // Clipboard ListView
                ListView {
                    id: clipListView
                    anchors.top: t3Header.bottom
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 8
                    clip: true
                    model: commandCenterWindow.clipboardItems

                    // Clean 4px styled ScrollBar
                    ScrollBar.vertical: ScrollBar {
                        id: clipScrollBar
                        policy: ScrollBar.AsNeeded
                        contentItem: Rectangle {
                            implicitWidth: 4
                            radius: 2
                            color: "#555555"
                        }
                    }

                    delegate: Item {
                        width: clipListView.width
                        height: 34

                        HoverHandler { id: clipHover }

                        Rectangle {
                            anchors.fill: parent
                            color: clipHover.hovered ? Qt.rgba(245/255, 184/255, 110/255, 0.08) : "transparent"
                            radius: 4

                            Behavior on color { ColorAnimation { duration: 150 } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 8

                                // Kinetic left indent
                                x: clipHover.hovered ? 8 : 0
                                Behavior on x {
                                    NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
                                }

                                Text {
                                    text: "#" + modelData.id
                                    color: clipHover.hovered ? "#f5b86e" : Qt.rgba(1, 1, 1, 0.35)
                                    font.family: (typeof Theme !== "undefined" && Theme.fontMono) ? Theme.fontMono : "monospace"
                                    font.pixelSize: 10
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.preview
                                    elide: Text.ElideRight
                                    // Transition text color to Amber (#f5b86e) on hover
                                    color: clipHover.hovered ? "#f5b86e" : "#b0b0b0"
                                    font.family: (typeof Theme !== "undefined" && Theme.fontMono) ? Theme.fontMono : "monospace"
                                    font.pixelSize: 11

                                    Behavior on color { ColorAnimation { duration: 150 } }
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

            // ══════════════════════════════════════════════════════
            // TILE 4 (Bottom-Right): AGENDA / SCHEDULE
            // ══════════════════════════════════════════════════════
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: Qt.rgba(1, 1, 1, 0.02)
                border.color: Qt.rgba(1, 1, 1, 0.15)
                border.width: 1
                radius: 8
                clip: true

                // Blueprint Corner Accents
                Text { anchors.top: parent.top; anchors.left: parent.left; anchors.margins: 4; text: "┌"; color: Qt.rgba(1, 1, 1, 0.3); font.family: "monospace"; font.pixelSize: 10 }
                Text { anchors.top: parent.top; anchors.right: parent.right; anchors.margins: 4; text: "┐"; color: Qt.rgba(1, 1, 1, 0.3); font.family: "monospace"; font.pixelSize: 10 }
                Text { anchors.bottom: parent.bottom; anchors.left: parent.left; anchors.margins: 4; text: "└"; color: Qt.rgba(1, 1, 1, 0.3); font.family: "monospace"; font.pixelSize: 10 }
                Text { anchors.bottom: parent.bottom; anchors.right: parent.right; anchors.margins: 4; text: "┘"; color: Qt.rgba(1, 1, 1, 0.3); font.family: "monospace"; font.pixelSize: 10 }

                // Tile Header
                RowLayout {
                    id: t4Header
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 10
                    spacing: 8

                    Text {
                        text: "// 04. MISSION AGENDAS"
                        color: "#f5b86e"
                        font.family: (typeof Theme !== "undefined" && Theme.fontMono) ? Theme.fontMono : "monospace"
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: "[" + commandCenterWindow.agendaItems.length + " SLOTS]"
                        color: Qt.rgba(1, 1, 1, 0.4)
                        font.family: (typeof Theme !== "undefined" && Theme.fontMono) ? Theme.fontMono : "monospace"
                        font.pixelSize: 10
                    }
                }

                // Agenda Timeline List
                ListView {
                    id: agendaListView
                    anchors.top: t4Header.bottom
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 8
                    clip: true
                    model: commandCenterWindow.agendaItems

                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AsNeeded
                        contentItem: Rectangle {
                            implicitWidth: 4
                            radius: 2
                            color: "#555555"
                        }
                    }

                    delegate: Item {
                        width: agendaListView.width
                        height: 38

                        HoverHandler { id: aHover }

                        Rectangle {
                            anchors.fill: parent
                            color: aHover.hovered ? Qt.rgba(1, 1, 1, 0.05) : "transparent"
                            radius: 4

                            Behavior on color { ColorAnimation { duration: 150 } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 10

                                x: aHover.hovered ? 6 : 0
                                Behavior on x {
                                    NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
                                }

                                // Date Badge
                                Rectangle {
                                    Layout.preferredHeight: 20
                                    Layout.preferredWidth: dText.implicitWidth + 12
                                    radius: 3
                                    color: Qt.rgba(245/255, 184/255, 110/255, 0.15)
                                    border.color: "#f5b86e"
                                    border.width: 1

                                    Text {
                                        id: dText
                                        anchors.centerIn: parent
                                        text: modelData.date
                                        color: "#f5b86e"
                                        font.family: (typeof Theme !== "undefined" && Theme.fontMono) ? Theme.fontMono : "monospace"
                                        font.pixelSize: 10
                                        font.weight: Font.DemiBold
                                    }
                                }

                                Text {
                                    text: "──"
                                    color: Qt.rgba(1, 1, 1, 0.2)
                                    font.family: "monospace"
                                    font.pixelSize: 10
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.title
                                    elide: Text.ElideRight
                                    color: aHover.hovered ? "#ffffff" : "#cccccc"
                                    font.family: (typeof Theme !== "undefined" && Theme.fontMono) ? Theme.fontMono : "monospace"
                                    font.pixelSize: 11
                                    Behavior on color { ColorAnimation { duration: 150 } }
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
