import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import "../Singletons"
import "../components"

Item {
    id: root

    property bool isOpen: false
    signal closeRequested()
    signal openSettingsRequested()

    property string searchQuery: ""

    // Keyboard dismissal
    Keys.onEscapePressed: root.closeRequested()
    Keys.onPressed: (event) => {
        if ((event.modifiers & Qt.MetaModifier) && event.key === Qt.Key_Slash) {
            event.accepted = true
            root.closeRequested()
        }
    }

    // Backdrop dismissal
    MouseArea {
        anchors.fill: parent
        onClicked: root.closeRequested()
    }

    // Modal HUD Container
    Rectangle {
        id: hudCard
        anchors.centerIn: parent
        width: Math.min(parent.width - Theme.px(60), Theme.px(880))
        height: Math.min(parent.height - Theme.px(60), Theme.px(640))
        radius: Theme.px(10)
        color: Theme.surface
        border.color: Qt.rgba(1, 1, 1, 0.14)
        border.width: 1
        clip: true
        focus: true

        scale: root.isOpen ? 1.0 : 0.95
        opacity: root.isOpen ? 1.0 : 0.0
        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 180 } }

        // Stop propagation so clicking inside dialog does not close it
        MouseArea {
            anchors.fill: parent
            onClicked: {}
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // -----------------------------------------------------------------
            // HEADER BAR
            // -----------------------------------------------------------------
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.px(54)
                color: Qt.rgba(0, 0, 0, 0.35)
                border.color: Qt.rgba(1, 1, 1, 0.08)
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.px(18)
                    anchors.rightMargin: Theme.px(16)
                    spacing: Theme.px(12)

                    Text {
                        text: "󰌌"
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fontPx(18)
                        color: Theme.primary
                    }

                    ColumnLayout {
                        spacing: Theme.px(2)
                        RowLayout {
                            spacing: Theme.px(8)
                            Text {
                                text: "CARBON // KEYBOARD CHEAT SHEET"
                                font.family: Theme.font
                                font.pixelSize: Theme.fontPx(13)
                                font.weight: Font.Bold
                                color: Qt.rgba(1, 1, 1, 0.95)
                            }
                            Rectangle {
                                Layout.preferredHeight: Theme.px(16)
                                Layout.preferredWidth: badgeText.implicitWidth + Theme.px(10)
                                radius: Theme.px(3)
                                color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.16)
                                border.color: Theme.primary
                                border.width: 1

                                Text {
                                    id: badgeText
                                    anchors.centerIn: parent
                                    text: "HUD"
                                    font.family: Theme.fontMono
                                    font.pixelSize: Theme.fontPx(9)
                                    font.weight: Font.Bold
                                    color: Theme.primary
                                }
                            }
                        }

                        Text {
                            text: "Quick-reference shortcuts guide • Press Esc or SUPER + / to dismiss"
                            font.family: Theme.font
                            font.pixelSize: Theme.fontPx(10)
                            color: Qt.rgba(1, 1, 1, 0.45)
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Search inside cheat sheet
                    Rectangle {
                        Layout.preferredWidth: Theme.px(220)
                        Layout.preferredHeight: Theme.px(30)
                        radius: Theme.px(6)
                        color: Qt.rgba(1, 1, 1, 0.06)
                        border.color: cheatSearchInput.activeFocus ? Theme.primary : Qt.rgba(1, 1, 1, 0.12)
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.px(8)
                            anchors.rightMargin: Theme.px(8)
                            spacing: Theme.px(6)

                            Text {
                                text: "󰍉"
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fontPx(11)
                                color: cheatSearchInput.activeFocus ? Theme.primary : Qt.rgba(1, 1, 1, 0.40)
                            }

                            TextInput {
                                id: cheatSearchInput
                                Layout.fillWidth: true
                                font.family: Theme.font
                                font.pixelSize: Theme.fontPx(11)
                                color: Qt.rgba(1, 1, 1, 0.90)
                                clip: true
                                text: root.searchQuery
                                onTextChanged: root.searchQuery = text

                                Text {
                                    anchors.fill: parent
                                    visible: parent.text.length === 0 && !parent.activeFocus
                                    text: "Filter shortcuts..."
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontPx(10)
                                    color: Qt.rgba(1, 1, 1, 0.35)
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }

                            Text {
                                visible: root.searchQuery.length > 0
                                text: "✕"
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fontPx(10)
                                color: Qt.rgba(1, 1, 1, 0.50)
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        cheatSearchInput.text = ""
                                        root.searchQuery = ""
                                    }
                                }
                            }
                        }
                    }

                    // Close Button
                    Rectangle {
                        Layout.preferredWidth: Theme.px(28)
                        Layout.preferredHeight: Theme.px(28)
                        radius: Theme.px(6)
                        color: closeMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.05)
                        border.color: closeMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.25) : "transparent"
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: "✕"
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.fontPx(12)
                            color: Qt.rgba(1, 1, 1, 0.70)
                        }

                        MouseArea {
                            id: closeMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.closeRequested()
                        }
                    }
                }
            }

            // -----------------------------------------------------------------
            // BODY: 2x2 CATEGORIZED SHORTCUTS GRID
            // -----------------------------------------------------------------
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                Flickable {
                    id: cheatFlick
                    anchors.fill: parent
                    anchors.margins: Theme.px(16)
                    contentWidth: width
                    contentHeight: gridLayout.implicitHeight + Theme.px(10)
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    GridLayout {
                        id: gridLayout
                        anchors.left: parent.left
                        anchors.right: parent.right
                        columns: 2
                        columnSpacing: Theme.px(14)
                        rowSpacing: Theme.px(14)

                        // SECTION 1: ESSENTIAL SHELL & DESKTOP
                        ShortcutGroupCard {
                            Layout.fillWidth: true
                            title: "SHELL & DESKTOP"
                            iconGlyph: "󱐋"
                            filterQuery: root.searchQuery
                            shortcuts: [
                                { combo: "SUPER (Tap)", action: "Vanish Orbital Hub & Satellites" },
                                { combo: "SUPER + Space", action: "Spotlight Quick Search & Apps" },
                                { combo: "SUPER + Tab", action: "Workspace Overview (Atom Bohr)" },
                                { combo: "SUPER + C", action: "Carbon Settings Hub" },
                                { combo: "SUPER + B", action: "Control Center / Quick Toggles" },
                                { combo: "SUPER + D", action: "Carbon Drop (Quick Share)" },
                                { combo: "SUPER + V", action: "Clipboard History Picker" },
                                { combo: "SUPER + L", action: "Lock Screen (Hyprlock)" },
                                { combo: "SUPER + /", action: "Toggle This Cheat Sheet (HUD)" }
                            ]
                        }

                        // SECTION 2: WINDOW MANAGEMENT
                        ShortcutGroupCard {
                            Layout.fillWidth: true
                            title: "WINDOW MANAGEMENT"
                            iconGlyph: "󰖲"
                            filterQuery: root.searchQuery
                            shortcuts: [
                                { combo: "SUPER + X", action: "Close Focused Window" },
                                { combo: "F11", action: "Toggle Fullscreen Window" },
                                { combo: "ALT + Tab", action: "Cycle Next Window (MRU History)" },
                                { combo: "ALT + SHIFT + Tab", action: "Cycle Previous Window" },
                                { combo: "SUPER + Arrows", action: "Focus Window (Left / Right / Up / Down)" },
                                { combo: "SUPER + SHIFT + Arrows", action: "Resize Window (±50px)" },
                                { combo: "SUPER + Left Drag", action: "Move Window with Mouse" },
                                { combo: "SUPER + Right Drag", action: "Resize Window with Mouse" },
                                { combo: "SUPER + SHIFT + Q", action: "Force Terminate Active Process" }
                            ]
                        }

                        // SECTION 3: APPLICATIONS & TOOLS
                        ShortcutGroupCard {
                            Layout.fillWidth: true
                            title: "APPLICATIONS & TOOLS"
                            iconGlyph: "󰀻"
                            filterQuery: root.searchQuery
                            shortcuts: [
                                { combo: "SUPER + Return", action: "Launch Terminal (Kitty)" },
                                { combo: "SUPER + SHIFT + Return", action: "Floating Terminal (800x550)" },
                                { combo: "SUPER + E", action: "File Manager (Yazi Terminal)" },
                                { combo: "SUPER + N", action: "GUI File Manager (Nautilus)" },
                                { combo: "SUPER + F", action: "Internet Browser (LibreWolf)" },
                                { combo: "SUPER + SHIFT + S", action: "Screenshot Selected Area" },
                                { combo: "Print", action: "Screenshot Entire Screen" },
                                { combo: "ALT + Print", action: "Screenshot Active Window" },
                                { combo: "SUPER + T", action: "Pomodoro Focus Productivity Timer" },
                                { combo: "SUPER + Escape", action: "Pulse System & Task Monitor" }
                            ]
                        }

                        // SECTION 4: WORKSPACES & MODE TRIGGERS
                        ShortcutGroupCard {
                            Layout.fillWidth: true
                            title: "WORKSPACES & MODE TRIGGERS"
                            iconGlyph: "󰍹"
                            filterQuery: root.searchQuery
                            shortcuts: [
                                { combo: "SUPER + 1..0", action: "Switch to Virtual Workspace 1–10" },
                                { combo: "SUPER + SHIFT + 1..0", action: "Move Window to Workspace 1–10" },
                                { combo: "SUPER + Mouse Wheel", action: "Scroll Workspaces" },
                                { combo: "SUPER + S", action: "Toggle Special Scratchpad Workspace" },
                                { combo: "SUPER + M", action: "Toggle Synced Live Lyrics (Vanish Mode)" },
                                { combo: "SUPER + A", action: "Focus Alerts Satellite (Vanish Mode)" },
                                { combo: "SUPER + B", action: "Quick Control Lobe (Vanish Mode)" },
                                { combo: "SUPER + F1", action: "Toggle Game Mode (Zero Latency Direct Scanout)" },
                                { combo: "CTRL + ALT + Delete", action: "Exit Desktop Session" }
                            ]
                        }
                    }
                }
            }

            // -----------------------------------------------------------------
            // FOOTER BAR
            // -----------------------------------------------------------------
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.px(42)
                color: Qt.rgba(0, 0, 0, 0.40)
                border.color: Qt.rgba(1, 1, 1, 0.08)
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Theme.px(18)
                    anchors.rightMargin: Theme.px(16)
                    spacing: Theme.px(12)

                    Text {
                        text: "💡 Tip: Press SUPER + / anytime from anywhere on the desktop to bring up this HUD."
                        font.family: Theme.font
                        font.pixelSize: Theme.fontPx(11)
                        color: Qt.rgba(1, 1, 1, 0.50)
                    }

                    Item { Layout.fillWidth: true }

                    // Jump to Settings Hub
                    Rectangle {
                        Layout.preferredHeight: Theme.px(28)
                        Layout.preferredWidth: settingsBtnText.implicitWidth + Theme.px(20)
                        radius: Theme.px(6)
                        color: settingsBtnMouse.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.25) : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12)
                        border.color: Theme.primary
                        border.width: 1

                        RowLayout {
                            id: settingsBtnText
                            anchors.centerIn: parent
                            spacing: Theme.px(6)
                            Text {
                                text: "Full Shortcuts Manager"
                                font.family: Theme.font
                                font.pixelSize: Theme.fontPx(11)
                                font.weight: Font.DemiBold
                                color: Theme.primary
                            }
                            Text {
                                text: "󰁔"
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fontPx(11)
                                color: Theme.primary
                            }
                        }

                        MouseArea {
                            id: settingsBtnMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.openSettingsRequested()
                        }
                    }
                }
            }
        }
    }

    // =========================================================================
    // INLINE COMPONENT: SHORTCUT GROUP CARD
    // =========================================================================
    component ShortcutGroupCard: Rectangle {
        property string title: ""
        property string iconGlyph: ""
        property var shortcuts: []
        property string filterQuery: ""

        radius: Theme.px(8)
        color: Qt.rgba(0, 0, 0, 0.25)
        border.color: Qt.rgba(1, 1, 1, 0.08)
        border.width: 1
        implicitHeight: cardCol.implicitHeight + Theme.px(24)

        ColumnLayout {
            id: cardCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Theme.px(12)
            spacing: Theme.px(8)

            // Category Header
            RowLayout {
                spacing: Theme.px(8)
                Text {
                    text: iconGlyph
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fontPx(13)
                    color: Theme.primary
                }
                Text {
                    text: title
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fontPx(11)
                    font.weight: Font.Bold
                    color: Theme.primary
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Qt.rgba(1, 1, 1, 0.08)
            }

            // Shortcuts items
            Repeater {
                model: {
                    var list = []
                    var q = filterQuery.trim().toLowerCase()
                    for (var i = 0; i < shortcuts.length; i++) {
                        var it = shortcuts[i]
                        if (q.length > 0) {
                            var aMatch = it.action.toLowerCase().indexOf(q) !== -1
                            var cMatch = it.combo.toLowerCase().replace(/[\s\+\-_]+/g, "").indexOf(q.replace(/[\s\+\-_]+/g, "")) !== -1
                            if (!aMatch && !cMatch) continue
                        }
                        list.push(it)
                    }
                    return list
                }

                delegate: RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.px(8)

                    Text {
                        text: modelData.action
                        font.family: Theme.font
                        font.pixelSize: Theme.fontPx(11)
                        color: Qt.rgba(1, 1, 1, 0.85)
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }

                    // Keycap badge
                    Rectangle {
                        Layout.preferredHeight: Theme.px(22)
                        Layout.preferredWidth: keyCapLabel.implicitWidth + Theme.px(10)
                        radius: Theme.px(4)
                        color: Qt.rgba(1, 1, 1, 0.08)
                        border.color: Qt.rgba(1, 1, 1, 0.18)
                        border.width: 1

                        Text {
                            id: keyCapLabel
                            anchors.centerIn: parent
                            text: modelData.combo
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.fontPx(10)
                            font.weight: Font.Bold
                            color: Qt.rgba(1, 1, 1, 0.90)
                        }
                    }
                }
            }
        }
    }
}
