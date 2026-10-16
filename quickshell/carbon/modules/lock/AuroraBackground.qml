import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import "../../Singletons"

/**
 * AuroraBackground:
 * ReactBits Top-Edge Aurora Shader matching reactbits.dev/backgrounds/aurora
 *
 * Flowing curtain ribbons anchored at top edge (uv.y = 0.0) that extend
 * downward to ~48% of screen height and fade smoothly into pure pitch black
 * vec4(0.0, 0.0, 0.0, 1.0) with 0.28 master alpha so center lyric text
 * contrast is 100% preserved.
 *
 * Pauses uTime progression when music is paused for zero-idle motion.
 */
Item {
    id: root
    anchors.fill: parent

    readonly property bool isPlaying: LyricsService.isPlaying
    property real uTime: 0.0

    // Pitch-black base background
    Rectangle {
        anchors.fill: parent
        color: "#000000"
        z: -1
    }

    // Zero-idle-motion: driver only runs when music is actively playing
    FrameAnimation {
        id: timeDriver
        running: root.isPlaying
        onTriggered: {
            root.uTime += frameTime
        }
    }

    // High-performance ShaderEffect using compiled QSB shader
    ShaderEffect {
        id: auroraShader
        anchors.fill: parent
        z: 0

        property real uTime: root.uTime
        property color cPrimary: Theme.m3primary
        property color cSecondary: Theme.m3secondary
        property color cTertiary: Theme.m3tertiary

        fragmentShader: "aurora.frag.qsb"
        blending: true
    }
}
