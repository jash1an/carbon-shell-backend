import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import ".."
import "../Singletons"

PanelWindow {
    id: vanishOverlayWindow

    // Anchor purely to the bottom edge, spanning full width
    anchors {
        bottom: true
        left: true
        right: true
    }
    height: 120
    implicitHeight: 120
    color: "transparent"

    // Place above standard windows, but respect compositor rules
    WlrLayershell.namespace: "carbon-vanish-overlay"
    WlrLayershell.layer: WlrLayer.Top

    // Visibility logic: Only show if we are in Vanish Mode AND the user toggled it open
    visible: GlobalState.isVanishMode && GlobalState.isVanishOverlayOpen
    onVisibleChanged: console.log("[VanishOverlay] visible:", visible, "isVanishMode:", GlobalState.isVanishMode, "isVanishOverlayOpen:", GlobalState.isVanishOverlayOpen)

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(5/255, 6/255, 8/255, 0.85) // Obsidian glass
        border.color: Qt.rgba(1, 1, 1, 0.15)
        border.width: 1
        // Blueprint dashed top border for the aesthetic
        // Note: QML Rectangle doesn't natively support dashed borders easily, 
        // so we use a custom Shape or an Image overlay later. For now, solid is fine to scaffold.

        RowLayout {
            anchors.fill: parent
            anchors.margins: 15
            spacing: 20

            // LEFT NODE: CHRONO & ATMOSPHERE
            Rectangle {
                Layout.preferredWidth: parent.width * 0.25
                Layout.fillHeight: true
                color: "transparent"
                border.color: Qt.rgba(1, 1, 1, 0.1)

                ColumnLayout {
                    anchors.centerIn: parent
                    Text { text: "06:05 AM"; color: "white"; font.pixelSize: 32; font.family: "JetBrains Mono" }
                    Text { text: "21°C // Clear Sky"; color: "gray"; font.pixelSize: 14; font.family: "JetBrains Mono" }
                }
            }

            // CENTER NODE: SYSTEM TELEMETRY
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "transparent"
                border.color: Qt.rgba(1, 1, 1, 0.1)

                ColumnLayout {
                    anchors.centerIn: parent
                    Text { text: "CPU [||||||||..........] 44%"; color: "white"; font.family: "JetBrains Mono" }
                    Text { text: "RAM [||||..............] 42%"; color: "white"; font.family: "JetBrains Mono" }
                }
            }

            // RIGHT NODE: MEDIA DECK
            Rectangle {
                Layout.preferredWidth: parent.width * 0.25
                Layout.fillHeight: true
                color: "transparent"
                border.color: Qt.rgba(1, 1, 1, 0.1)

                ColumnLayout {
                    anchors.centerIn: parent
                    Text { text: "CRAZY TRAIN"; color: "white"; font.bold: true; font.pixelSize: 16; font.family: "JetBrains Mono" }
                    Text { text: "Ozzy Osbourne"; color: "gray"; font.pixelSize: 12; font.family: "JetBrains Mono" }
                    Text { text: "[ BACK ]  [ PLAY ]  [ SKIP ]"; color: "white"; font.pixelSize: 12; font.family: "JetBrains Mono" }
                }
            }
        }
    }
}
