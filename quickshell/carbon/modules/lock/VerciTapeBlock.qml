import QtQuick
import QtQuick.Shapes

/**
 * VerciTapeBlock:
 * Sheared polygon cutout tape block rendered behind punch words.
 * Points matching clip-path:
 *   top-left (1.5%, 4%), top-right (100%, 0%),
 *   bottom-right (98.5%, 96%), bottom-left (0%, 100%),
 *   rotation -1.4deg.
 * Wipes open horizontally (scale: 0.0 -> 1.0, transformOrigin: Left) over 140ms.
 */
Item {
    id: root

    property color fillColor: "#C0C4EE"
    property bool opened: false

    rotation: -1.4
    transformOrigin: Item.Left

    scale: opened ? 1.0 : 0.0
    Behavior on scale {
        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }

    Behavior on fillColor {
        ColorAnimation { duration: 190; easing.type: Easing.OutCubic }
    }

    Shape {
        anchors.fill: parent
        asynchronous: true

        ShapePath {
            fillColor: root.fillColor
            strokeColor: "transparent"
            strokeWidth: 0

            // Top-left: (1.5%, 4%)
            startX: root.width * 0.015
            startY: root.height * 0.04

            // Top-right: (100%, 0%)
            PathLine { x: root.width * 1.0; y: 0.0 }

            // Bottom-right: (98.5%, 96%)
            PathLine { x: root.width * 0.985; y: root.height * 0.96 }

            // Bottom-left: (0%, 100%)
            PathLine { x: 0.0; y: root.height * 1.0 }

            // Close back to top-left
            PathLine { x: root.width * 0.015; y: root.height * 0.04 }
        }
    }
}
