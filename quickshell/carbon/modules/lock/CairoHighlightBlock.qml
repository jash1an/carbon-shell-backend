import QtQuick

/**
 * CairoHighlightBlock:
 * Standard flat rectangular text highlighter matching a word processor (Word / Docs).
 * Zero shear, zero tilt, clean rectangular geometry behind the spoken lyric phrase.
 * Wipes open horizontally (scaleX: 0.0 -> 1.0, transformOrigin: Left) on entry.
 */
Rectangle {
    id: root

    property color fillColor: "#76d0f9"
    property bool opened: false

    color: fillColor
    radius: 4

    opacity: opened ? 1.0 : 0.0

    transform: Scale {
        origin.x: 0
        origin.y: root.height / 2
        xScale: root.opened ? 1.0 : 0.0

        Behavior on xScale {
            NumberAnimation { duration: 200; easing.type: Easing.OutBack; easing.overshoot: 1.35 }
        }
    }

    Behavior on opacity {
        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
    }

    Behavior on color {
        ColorAnimation { duration: 180; easing.type: Easing.OutCubic }
    }
}
