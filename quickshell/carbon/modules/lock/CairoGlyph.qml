import QtQuick
import QtQuick.Shapes
import "../../Singletons"
import "CairoHinglishMap.js" as GlyphMap

/**
 * CairoGlyph.qml:
 * Native 24x24 Angular Vector Glyph Renderer for Carbon // Cairo.
 * Zero Unicode text emojis. 100% custom geometric evenodd SVG vector paths.
 */
Item {
    id: root
    width: 86
    height: 86

    property string motif: ""
    property color glyphColor: Theme.m3primary || Theme.accent || "#c0c4ee"

    readonly property string svgPathData: GlyphMap.GLYPH_PATHS[root.motif] || ""
    readonly property bool hasValidGlyph: root.svgPathData.length > 0

    visible: hasValidGlyph

    Shape {
        id: glyphShape
        width: 24
        height: 24
        anchors.centerIn: parent
        scale: root.width / 24.0
        asynchronous: true
        layer.enabled: true
        layer.smooth: true

        ShapePath {
            fillRule: ShapePath.OddEvenFill
            fillColor: root.glyphColor
            strokeWidth: 0
            strokeColor: "transparent"

            PathSvg {
                path: root.svgPathData
            }
        }
    }
}
