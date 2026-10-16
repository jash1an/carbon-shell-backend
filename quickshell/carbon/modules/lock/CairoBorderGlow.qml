import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import "../../Singletons"

/**
 * CairoBorderGlow.qml:
 * Whisper-subtle ReactBits perimeter glow.
 * - 100% decoupled from lyrics, zero beat triggers, zero pulsing or blinking.
 * - Single color: Matugen.primary (Theme.m3primary || Theme.accent).
 * - Razor-sharp 1.5px inner border rectangle (radius: 12).
 * - Tight 12px soft inner edge shadow.
 * - Masked with a smooth radial gradient spotlight that travels along
 *   the perimeter on a slow, constant 14000ms infinite linear loop.
 */
Item {
    id: root
    anchors.fill: parent

    readonly property color glowColor: Theme.m3primary || Theme.accent || "#76d0f9"

    // Continuous 14000ms perimeter traveling loop
    property real perimeterAngle: 0.0
    NumberAnimation on perimeterAngle {
        from: 0.0
        to: Math.PI * 2
        duration: 14000
        loops: Animation.Infinite
        easing.type: Easing.Linear
    }

    // Map perimeter angle to (x, y) coordinate along the rounded screen perimeter
    readonly property real spotX: {
        var m = 12
        var w = Math.max(100, root.width - 2 * m)
        var h = Math.max(100, root.height - 2 * m)
        var p = 2 * (w + h)
        var d = (root.perimeterAngle / (2 * Math.PI)) * p
        if (d <= w) return m + d
        if (d <= w + h) return m + w
        if (d <= 2 * w + h) return m + w - (d - (w + h))
        return m
    }

    readonly property real spotY: {
        var m = 12
        var w = Math.max(100, root.width - 2 * m)
        var h = Math.max(100, root.height - 2 * m)
        var p = 2 * (w + h)
        var d = (root.perimeterAngle / (2 * Math.PI)) * p
        if (d <= w) return m
        if (d <= w + h) return m + (d - w)
        if (d <= 2 * w + h) return m + h
        return m + h - (d - (2 * w + h))
    }

    // Base subtle border: always visible at whisper-soft 0.08 opacity
    Rectangle {
        anchors.fill: parent
        anchors.margins: 4
        radius: 12
        color: "transparent"
        border.width: 1.5
        border.color: root.glowColor
        opacity: 0.08
    }

    // 1. The glowing border + 12px soft inner shadow
    Item {
        id: borderContent
        anchors.fill: parent
        visible: false

        // Razor-sharp 1.5px inner border rectangle (radius: 12)
        Rectangle {
            anchors.fill: parent
            anchors.margins: 4
            radius: 12
            color: "transparent"
            border.width: 1.5
            border.color: root.glowColor
            opacity: 0.95
        }

        // Tight 12px soft inner edge shadow (concentric subtle falloffs)
        Rectangle {
            anchors.fill: parent
            anchors.margins: 5
            radius: 11
            color: "transparent"
            border.width: 3
            border.color: root.glowColor
            opacity: 0.35
        }
        Rectangle {
            anchors.fill: parent
            anchors.margins: 7
            radius: 10
            color: "transparent"
            border.width: 5
            border.color: root.glowColor
            opacity: 0.18
        }
        Rectangle {
            anchors.fill: parent
            anchors.margins: 10
            radius: 8
            color: "transparent"
            border.width: 6
            border.color: root.glowColor
            opacity: 0.08
        }
    }

    // 2. The spotlight mask: smooth radial gradient spotlight
    Item {
        id: spotlightMask
        anchors.fill: parent
        visible: false

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeWidth: 0
                strokeColor: "transparent"
                fillGradient: RadialGradient {
                    centerX: root.spotX
                    centerY: root.spotY
                    centerRadius: 360
                    focalX: root.spotX
                    focalY: root.spotY
                    focalRadius: 0
                    GradientStop { position: 0.00; color: "#ffffffff" }
                    GradientStop { position: 0.30; color: "#ccffffff" }
                    GradientStop { position: 0.65; color: "#30ffffff" }
                    GradientStop { position: 1.00; color: "#00ffffff" }
                }
                startX: 0; startY: 0
                PathLine { x: root.width; y: 0 }
                PathLine { x: root.width; y: root.height }
                PathLine { x: 0; y: root.height }
                PathLine { x: 0; y: 0 }
            }
        }
    }

    // 3. MultiEffect applying the smooth radial spotlight mask
    MultiEffect {
        anchors.fill: parent
        source: borderContent
        maskEnabled: true
        maskSource: spotlightMask
    }
}
