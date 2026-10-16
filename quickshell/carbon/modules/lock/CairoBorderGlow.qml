import QtQuick
import QtQuick.Shapes
import QtQuick.Effects
import "../../Singletons"

/**
 * CairoBorderGlow.qml:
 * ReactBits Border Glow (https://reactbits.dev/components/border-glow)
 * Adapted for Cairo Standby / Lockscreen:
 * - Always visible on the screen border at all times (continuous perimeter sweep, zero hover dependency).
 * - Multi-tier inner mesh glow using Google Material 3 tokens (primary, secondary, tertiary).
 * - Base ambient resting border (1.5px, opacity 0.12).
 * - Continuous 8000ms linear traveling spotlight mask (420px radial gradient) via MultiEffect.
 * - Completely decoupled from lyrics (no beat blinks or flash triggers).
 */
Item {
    id: root
    anchors.fill: parent

    readonly property color primaryColor: Theme.m3primary || Theme.accent || "#a1c9fd"
    readonly property color secondaryColor: Theme.m3secondary || Theme.accentLit || Theme.accent || "#bbc7db"
    readonly property color tertiaryColor: Theme.m3tertiary || Theme.accent || "#d7bde4"

    // Continuous 8000ms perimeter traveling loop
    property real sweepProgress: 0.0
    NumberAnimation on sweepProgress {
        from: 0.0
        to: 1.0
        duration: 8000
        loops: Animation.Infinite
        easing.type: Easing.Linear
    }

    readonly property real m: 4
    readonly property real w: Math.max(100, root.width - 2 * m)
    readonly property real h: Math.max(100, root.height - 2 * m)
    readonly property real perimeter: 2 * (w + h)

    readonly property real spotX: {
        var d = root.sweepProgress * root.perimeter
        if (d <= w) return m + d
        if (d <= w + h) return m + w
        if (d <= 2 * w + h) return m + w - (d - (w + h))
        return m
    }

    readonly property real spotY: {
        var d = root.sweepProgress * root.perimeter
        if (d <= w) return m
        if (d <= w + h) return m + (d - w)
        if (d <= 2 * w + h) return m + h
        return m + h - (d - (2 * w + h))
    }

    // 1. Ambient Resting Border (Always visible around entire perimeter)
    Rectangle {
        anchors.fill: parent
        anchors.margins: root.m
        radius: 16
        color: "transparent"
        border.width: 1.5
        border.color: root.primaryColor
        opacity: 0.12
    }

    // 2. ReactBits BorderGlow Content (Border + Soft Inner Mesh Glow)
    Item {
        id: glowContent
        anchors.fill: parent
        visible: false

        // Razor-sharp 2.0px outer border
        Rectangle {
            anchors.fill: parent
            anchors.margins: root.m
            radius: 16
            color: "transparent"
            border.width: 2.0
            border.color: root.primaryColor
            opacity: 0.95
        }

        // Concentric inner mesh glow layers (soft luminous depth)
        Rectangle {
            anchors.fill: parent
            anchors.margins: root.m + 1
            radius: 15
            color: "transparent"
            border.width: 4
            border.color: root.primaryColor
            opacity: 0.50
        }
        Rectangle {
            anchors.fill: parent
            anchors.margins: root.m + 4
            radius: 13
            color: "transparent"
            border.width: 8
            border.color: root.secondaryColor
            opacity: 0.28
        }
        Rectangle {
            anchors.fill: parent
            anchors.margins: root.m + 10
            radius: 10
            color: "transparent"
            border.width: 14
            border.color: root.tertiaryColor
            opacity: 0.14
        }
        Rectangle {
            anchors.fill: parent
            anchors.margins: root.m + 18
            radius: 8
            color: "transparent"
            border.width: 18
            border.color: root.primaryColor
            opacity: 0.05
        }
    }

    // 3. ReactBits Directional Cone / Spotlight Mask
    Item {
        id: glowMask
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
                    centerRadius: 420
                    focalX: root.spotX
                    focalY: root.spotY
                    focalRadius: 0
                    GradientStop { position: 0.00; color: "#ffffffff" }
                    GradientStop { position: 0.25; color: "#f0ffffff" }
                    GradientStop { position: 0.55; color: "#60ffffff" }
                    GradientStop { position: 0.85; color: "#10ffffff" }
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

    // 4. MultiEffect Masking
    MultiEffect {
        anchors.fill: parent
        source: glowContent
        maskEnabled: true
        maskSource: glowMask
    }
}
