import QtQuick
import QtQuick.Shapes
import "../../Singletons"

/**
 * VerciVectorGlyph.qml
 *
 * Dedicated pure-vector glyph renderer.
 * Zero Unicode emojis. Zero colored stickers.
 * 16 song motifs rendered via hardware-accelerated Shape + PathSvg,
 * filled dynamically with Matugen.primary on a 100% transparent background.
 */
Item {
    id: root

    property string motif: ""
    property color glyphColor: Theme.m3primary

    width: 78
    height: 78

    visible: motif.length > 0 && getSvgPath(motif).length > 0

    function getSvgPath(m) {
        switch (m) {
            case "heart":
                return "M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09C13.09 3.81 14.76 3 16.5 3 19.58 3 22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 11.54L12 21.35z"
            case "person":
                return "M12 12c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm0 2c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z"
            case "car":
                return "M18.92 6.01C18.72 5.42 18.16 5 17.5 5h-11c-.66 0-1.21.42-1.42 1.01L3 12v8c0 .55.45 1 1 1h1c.55 0 1-.45 1-1v-1h12v1c0 .55.45 1 1 1h1c.55 0 1-.45 1-1v-8l-2.08-5.99zM6.85 7h10.29l1.04 3H5.81l1.04-3zM19 17H5v-4.66l.12-.34h13.77l.11.34V17z"
            case "play":
                return "M8 5v14l11-7z"
            case "dice":
                return "M5 3h6a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2zm8 8h6a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2h-6a2 2 0 0 1-2-2v-6a2 2 0 0 1 2-2z"
            case "cloud":
                return "M19.35 10.04C18.67 6.59 15.64 4 12 4 9.11 4 6.6 5.64 5.35 8.04 2.34 8.36 0 10.91 0 14c0 3.31 2.69 6 6 6h13c2.76 0 5-2.24 5-5 0-2.64-2.05-4.78-4.65-4.96z"
            case "flame":
                return "M12 23c-4.97 0-9-4.03-9-9 0-4.12 3.03-7.53 7-8.72V10c0 1.66 1.34 3 3 3s3-1.34 3-3V2.1C18.8 3.86 21 7.67 21 12c0 6.08-4.92 11-9 11z"
            case "moon":
                return "M12.3 2a10 10 0 0 0-1.9 19.8 10 10 0 1 1 1.9-19.8z"
            case "star":
                return "M12 0l2.5 8.5L23 11l-8.5 2.5L12 22l-2.5-8.5L1 11l8.5-2.5z"
            case "clock":
                return "M12 2C6.5 2 2 6.5 2 12s4.5 10 10 10 10-4.5 10-10S17.5 2 12 2zm4.2 14.2L11 13V7h1.5v5.2l4.5 2.7-.8 1.3z"
            case "teardrop":
                return "M12 2.69l5.66 5.66a8 8 0 1 1-11.31 0z"
            case "eye":
                return "M12 4.5C7 4.5 2.73 7.61 1 12c1.73 4.39 6 7.5 11 7.5s9.27-3.11 11-7.5c-1.73-4.39-6-7.5-11-7.5zM12 17c-2.76 0-5-2.24-5-5s2.24-5 5-5 5 2.24 5 5-2.24 5-5 5zm0-8c-1.66 0-3 1.34-3 3s1.34 3 3 3 3-1.34 3-3-1.34-3-3-3z"
            case "hand":
                return "M9 11.24V7.5a2.5 2.5 0 0 1 5 0v3.74c1.21-.81 2-2.18 2-3.74a4.5 4.5 0 0 0-9 0c0 1.56.79 2.93 2 3.74zm9.84 4.63l-4.54-2.26a1.5 1.5 0 0 0-.67-.16H13v-6a1 1 0 0 0-2 0v10.5l-3.39-.71a1.5 1.5 0 0 0-1.57.57l-.84.99 5.3 5.3c.47.47 1.11.73 1.77.73h6.58c1.19 0 2.2-.84 2.42-2.01l.83-4.57a2.5 2.5 0 0 0-1.26-2.38z"
            case "broken_heart":
                return "M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09L11 9l2 2-2 3 3 3-2 4.35z M16.5 3c-1.74 0-3.41.81-4.5 2.09L13 9l-2 2 2 3-3 3 2 4.35 1.45-1.32C18.6 15.36 22 12.28 22 8.5 22 5.42 19.58 3 16.5 3z"
            case "diamond":
                return "M12 2L2 9l10 13 10-13L12 2zm0 3.32L17.5 9h-11L12 5.32z M4.76 10h14.48L12 19.42 4.76 10z"
            case "note":
                return "M12 3v10.55c-.59-.34-1.27-.55-2-.55-2.21 0-4 1.79-4 4s1.79 4 4 4 4-1.79 4-4V7h4V3h-6z"
            default:
                return ""
        }
    }

    Shape {
        id: glyphShape
        width: 24
        height: 24
        asynchronous: true
        scale: root.width / 24.0
        transformOrigin: Item.TopLeft

        ShapePath {
            strokeWidth: 0
            strokeColor: "transparent"
            fillColor: root.glyphColor

            PathSvg {
                path: root.getSvgPath(root.motif)
            }
        }
    }
}
