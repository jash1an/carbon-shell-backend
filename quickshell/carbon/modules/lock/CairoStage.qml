import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import "../../Singletons"
import "CairoHinglishMap.js" as GlyphMap

/**
 * CairoStage.qml:
 * Carbon // Cairo Kinetic Lyric Standby & Lock Screen Engine
 *
 * Visual Features:
 *   - 100% Pure Pitch-Black Stage (#000000) with zero shaders, zero horizon lines, zero UI chrome.
 *   - 5 Persistent Word Delegates in a True Upward-Gliding 3D Barrel.
 *   - Stage 0: Active spoken row with angled sheared tape polygon rotated -1.4deg.
 *   - Tape wipes open horizontally (scaleX: 0.0 -> 1.0, 200ms Easing.OutQuart).
 *   - Tape fill = Qt.darker(Theme.m3primary, 1.2) blended 25% with #9e6b74.
 *   - Text inside active tape = bright pale cream/blush (#f7ebed), NEVER black (#000000).
 *   - Stage 1: Tape polygon fades out, text transitions to warm muted bronze (#9c6e54).
 *   - 18 Custom Angular SVG Vector Glyphs beside active words, scaled and fading through stages.
 *   - Instant single-Enter unlock with radial iris reveal.
 */
Item {
    id: root
    anchors.fill: parent

    focus: true

    // Center coordinates on screen
    readonly property real cx: root.width / 2
    readonly property real cy: root.height / 2

    // ── Tape & Text Palette Tokens ─────────────────────────────────────────
    readonly property color tapeFillColor: {
        var p = Theme.m3primary || Theme.accent || Qt.rgba(0.75, 0.77, 0.93, 1.0)
        var darkP = Qt.darker(p, 1.2)
        var blush = Qt.color("#9e6b74")
        return Qt.rgba(
            darkP.r * 0.75 + blush.r * 0.25,
            darkP.g * 0.75 + blush.g * 0.25,
            darkP.b * 0.75 + blush.b * 0.25,
            1.0
        )
    }

    readonly property color activeTextColor: "#f7ebed"

    readonly property color bronzeColor: {
        var sec = Theme.m3secondary || Qt.rgba(0.77, 0.77, 0.87, 1.0)
        var dSec = Qt.darker(sec, 1.15)
        var b = Qt.color("#9c6e54")
        return Qt.rgba(
            dSec.r * 0.50 + b.r * 0.50,
            dSec.g * 0.50 + b.g * 0.50,
            dSec.b * 0.50 + b.b * 0.50,
            1.0
        )
    }

    // ── 1. Pure Pitch-Black Stage (0% Shaders / 0% Chrome) ────────────────
    Rectangle {
        id: pitchBlackBg
        anchors.fill: parent
        color: "#000000"
        z: 0
    }

    // ── 2. Cairo Lyric Engine ─────────────────────────────────────────────
    CairoLyricEngine {
        id: lyricEngine
    }

    // ── 3. Radial Iris Reveal Unlock Controller ──────────────────────────
    property real irisRadius: 0.0
    property bool unlocking: false

    signal unlocked()

    function triggerUnlock() {
        if (root.unlocking) return
        root.unlocking = true
        irisAnim.restart()
    }

    NumberAnimation {
        id: irisAnim
        target: root
        property: "irisRadius"
        from: 0.0
        to: 950.0
        duration: 480
        easing.type: Easing.InOutCubic
        onFinished: {
            root.unlocked()
            LockState.finishUnlock()
        }
    }

    property bool readyToUnlock: false
    Timer {
        interval: 350
        running: true
        repeat: false
        onTriggered: root.readyToUnlock = true
    }

    Keys.onPressed: (event) => {
        if (!root.readyToUnlock) return
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            event.accepted = true
            root.triggerUnlock()
        }
    }

    MouseArea {
        anchors.fill: parent
        z: 40
        onClicked: {
            root.forceActiveFocus()
        }
    }

    Component.onCompleted: {
        root.forceActiveFocus()
        root.syncInitialCluster()
    }

    // ── 4. Reusable 3-Slot Barrel Word Delegate Component ────────────────
    component CairoWordDelegate: Item {
        id: delegateRoot
        width: root.width
        height: 150
        x: (root.width - width) / 2

        property int stage: 4 // -1: pre-entry, 0: active bottom, 1: middle, 2: top, 3: exiting, 4: idle
        property string chunkText: ""
        property string glyphMotif: ""
        property real currentDuration: 1.0

        // Spatial animated properties
        property real stageY: root.cy + 210
        property real stageOpacity: 0.0
        property real stageScaleX: 0.88
        property real stageScaleY: 0.50
        property real stageRotX: 8.0
        property real tapeScaleX: 0.0

        property bool enableAnim: true

        y: stageY - height / 2
        opacity: stageOpacity
        visible: stageOpacity > 0.005

        // Transitions: 340ms Easing.OutQuint across all barrel coordinates
        Behavior on stageY {
            enabled: delegateRoot.enableAnim
            NumberAnimation { duration: 340; easing.type: Easing.OutQuint }
        }
        Behavior on stageScaleX {
            enabled: delegateRoot.enableAnim
            NumberAnimation { duration: 340; easing.type: Easing.OutQuint }
        }
        Behavior on stageScaleY {
            enabled: delegateRoot.enableAnim
            NumberAnimation { duration: 340; easing.type: Easing.OutQuint }
        }
        Behavior on stageRotX {
            enabled: delegateRoot.enableAnim
            NumberAnimation { duration: 340; easing.type: Easing.OutQuint }
        }
        Behavior on stageOpacity {
            enabled: delegateRoot.enableAnim
            NumberAnimation { duration: 340; easing.type: Easing.OutQuint }
        }

        // Horizontal tape wipe: 200ms Easing.OutQuart
        Behavior on tapeScaleX {
            enabled: delegateRoot.enableAnim
            NumberAnimation { duration: 200; easing.type: Easing.OutQuart }
        }

        transform: [
            Scale {
                origin.x: delegateRoot.width / 2
                origin.y: delegateRoot.height / 2
                xScale: delegateRoot.stageScaleX
                yScale: delegateRoot.stageScaleY
            },
            Rotation {
                origin.x: delegateRoot.width / 2
                origin.y: delegateRoot.height / 2
                axis { x: 1; y: 0; z: 0 }
                angle: delegateRoot.stageRotX
            }
        ]

        function setStage(newStage) {
            stage = newStage
            if (newStage === -1) {
                // Stage -1 (Pre-Entry Spawn): y: cy + 210, opacity: 0.0, xScale: 0.88, yScale: 0.50
                enableAnim = false
                stageY = root.cy + 210
                stageOpacity = 0.0
                stageScaleX = 0.88
                stageScaleY = 0.50
                stageRotX = 8.0
                tapeScaleX = 0.0
                z = 1
                enableAnim = true
            } else if (newStage === 0) {
                // Stage 0 (Bottom Active Spoken Row — With Cutout Tape):
                // y: cy + 110, opacity: 1.0, xScale: 1.0, yScale: 1.0, rotX: 0, z: 30
                stageY = root.cy + 110
                stageOpacity = 1.0
                stageScaleX = 1.0
                stageScaleY = 1.0
                stageRotX = 0.0
                tapeScaleX = 1.0
                z = 30
            } else if (newStage === 1) {
                // Stage 1 (Middle Row — Just Passed):
                // y: cy - 12, opacity: 0.92, xScale: 0.86, yScale: 0.74, rotX: 20, z: 20
                stageY = root.cy - 12
                stageOpacity = 0.92
                stageScaleX = 0.86
                stageScaleY = 0.74
                stageRotX = 20.0
                z = 20
            } else if (newStage === 2) {
                // Stage 2 (Top Row — Receding Barrel Edge):
                // y: cy - 118, opacity: 0.70, xScale: 0.72, yScale: 0.54, rotX: 38, z: 10
                stageY = root.cy - 118
                stageOpacity = 0.70
                stageScaleX = 0.72
                stageScaleY = 0.54
                stageRotX = 38.0
                z = 10
            } else if (newStage === 3) {
                // Stage 3 (Exiting Top — Crushing Flat):
                // y: cy - 195, opacity: 0.0, xScale: 0.54, yScale: 0.12, rotX: 58
                stageY = root.cy - 195
                stageOpacity = 0.0
                stageScaleX = 0.54
                stageScaleY = 0.12
                stageRotX = 58.0
                z = 5
            } else {
                stageOpacity = 0.0
                stage = 4
                z = 0
            }
        }

        Row {
            id: contentRow
            anchors.centerIn: parent
            spacing: 20

            // 18 Custom Cairo Angular SVG Vector Glyph
            CairoGlyph {
                id: glyphItem
                motif: delegateRoot.glyphMotif
                glyphColor: Theme.m3primary || Theme.accent || "#c0c4ee"
                anchors.verticalCenter: parent.verticalCenter
                width: 86
                height: 86
                visible: motif.length > 0
            }

            // Word(s) Item with Active Angled Cutout Tape
            Item {
                id: wordTapeItem
                width: wordText.contentWidth + 56
                height: Math.max(90, wordText.contentHeight + 20)
                anchors.verticalCenter: parent.verticalCenter

                // Active Angled Cutout Tape Polygon:
                // Sheared polygon (top-left 1.5%, 4%; top-right 100%, 0%; bottom-right 98.5%, 96%; bottom-left 0%, 100%; rotation -1.4deg)
                Item {
                    id: tapeContainer
                    anchors.fill: parent
                    rotation: -1.4
                    transformOrigin: Item.Left
                    opacity: delegateRoot.stage === 0 ? 1.0 : (delegateRoot.stage === 1 ? 0.18 : 0.0)
                    scale: delegateRoot.tapeScaleX

                    Behavior on opacity {
                        NumberAnimation { duration: 340; easing.type: Easing.OutQuint }
                    }

                    Shape {
                        id: tapeShape
                        anchors.fill: parent
                        asynchronous: true
                        preferredRendererType: Shape.CurveRenderer
                        antialiasing: true
                        smooth: true

                        ShapePath {
                            fillColor: root.tapeFillColor
                            strokeWidth: 0
                            strokeColor: "transparent"
                            startX: tapeShape.width * 0.015
                            startY: tapeShape.height * 0.04
                            PathLine { x: tapeShape.width * 1.000; y: 0 }
                            PathLine { x: tapeShape.width * 0.985; y: tapeShape.height * 0.96 }
                            PathLine { x: 0;                       y: tapeShape.height * 1.000 }
                            PathLine { x: tapeShape.width * 0.015; y: tapeShape.height * 0.04 }
                        }
                    }
                }

                // Lyric Text:
                // Plus Jakarta Sans / Manrope, ExtraBold, natural casing, letterSpacing: -3.5, pixelSize: 118
                // Active inside tape: #f7ebed, Stage 1/2: bronze #9c6e54
                Text {
                    id: wordText
                    anchors.centerIn: parent
                    text: delegateRoot.chunkText
                    font.family: "Plus Jakarta Sans, Manrope, sans-serif"
                    font.weight: Font.ExtraBold
                    font.italic: delegateRoot.stage === 0
                    font.letterSpacing: -3.5
                    font.pixelSize: Math.min(118, Math.max(56, Math.round((root.width * 0.72) / Math.max(5, text.length * 0.62))))
                    color: delegateRoot.stage === 0 ? root.activeTextColor : root.bronzeColor

                    Behavior on color {
                        ColorAnimation { duration: 340; easing.type: Easing.OutQuint }
                    }
                }
            }
        }
    }

    // ── 5. Delegate Pool Management ──────────────────────────────────────
    Item {
        id: stageContainer
        anchors.fill: parent
        z: 2
        visible: (lyricEngine.hasLyrics || root.hasActiveWords) && root.irisRadius < 900
        opacity: root.unlocking ? Math.max(0.0, 1.0 - root.irisRadius / 400.0) : 1.0

        CairoWordDelegate { id: d0 }
        CairoWordDelegate { id: d1 }
        CairoWordDelegate { id: d2 }
        CairoWordDelegate { id: d3 }
        CairoWordDelegate { id: d4 }
    }

    readonly property var delegates: [d0, d1, d2, d3, d4]
    property int poolPointer: 0

    readonly property bool hasActiveWords: (
        (d0.stage >= 0 && d0.stage <= 2 && d0.stageOpacity > 0.05) ||
        (d1.stage >= 0 && d1.stage <= 2 && d1.stageOpacity > 0.05) ||
        (d2.stage >= 0 && d2.stage <= 2 && d2.stageOpacity > 0.05) ||
        (d3.stage >= 0 && d3.stage <= 2 && d3.stageOpacity > 0.05) ||
        (d4.stage >= 0 && d4.stage <= 2 && d4.stageOpacity > 0.05)
    )

    function handleBeatTriggered(beat) {
        if (!beat || !beat.text) return

        // 1. Advance all active delegates up the barrel
        for (var i = 0; i < delegates.length; i++) {
            var d = delegates[i]
            if (d.stage === 0) {
                d.setStage(1)
            } else if (d.stage === 1) {
                d.setStage(2)
            } else if (d.stage === 2) {
                d.setStage(3)
            } else if (d.stage === 3) {
                d.setStage(4)
            }
        }

        // 2. Pick next delegate from pool
        var nextD = delegates[poolPointer]
        poolPointer = (poolPointer + 1) % delegates.length

        // 3. Set content and spawn at Stage -1
        nextD.chunkText = beat.text
        nextD.glyphMotif = beat.glyph || ""
        nextD.currentDuration = beat.duration || 1.0
        nextD.setStage(-1)

        // 4. Animate immediately into Stage 0
        Qt.callLater(function() {
            nextD.setStage(0)
        })
    }

    function handleClearRequested() {
        for (var i = 0; i < delegates.length; i++) {
            var d = delegates[i]
            if (d.stage >= 0 && d.stage <= 2) {
                d.setStage(3)
            }
        }
    }

    function syncInitialCluster() {
        if (!lyricEngine || !lyricEngine.allWords || lyricEngine.allWords.length === 0) return
        var idx = lyricEngine.currentWordIndex
        if (idx < 0 || idx >= lyricEngine.allWords.length) return

        for (var i = 0; i < delegates.length; i++) {
            delegates[i].setStage(4)
        }

        if (idx >= 2) {
            var w2 = lyricEngine.allWords[idx - 2]
            d2.chunkText = w2.text
            d2.glyphMotif = w2.glyph || ""
            d2.currentDuration = w2.duration || 1.0
            d2.setStage(2)
        }
        if (idx >= 1) {
            var w1 = lyricEngine.allWords[idx - 1]
            d1.chunkText = w1.text
            d1.glyphMotif = w1.glyph || ""
            d1.currentDuration = w1.duration || 1.0
            d1.setStage(1)
        }
        var w0 = lyricEngine.allWords[idx]
        d0.chunkText = w0.text
        d0.glyphMotif = w0.glyph || ""
        d0.currentDuration = w0.duration || 1.0
        d0.setStage(0)

        poolPointer = 3
    }

    Connections {
        target: lyricEngine
        function onBeatTriggered(beatData) {
            root.handleBeatTriggered(beatData)
        }
        function onClearRequested() {
            root.handleClearRequested()
        }
        function onAllWordsChanged() {
            root.syncInitialCluster()
        }
        function onCurrentWordIndexChanged() {
            if (!root.hasActiveWords && lyricEngine.currentWordIndex >= 0) {
                root.syncInitialCluster()
            }
        }
    }

    // ── 6. Standby Fallback (Zero Chrome when no lyrics active) ───────────
    Item {
        id: standbyFallback
        anchors.centerIn: parent
        z: 1
        visible: !root.hasActiveWords && root.irisRadius < 900
        opacity: root.unlocking ? Math.max(0.0, 1.0 - root.irisRadius / 400.0) : (root.hasActiveWords ? 0.0 : 0.88)

        Behavior on opacity { NumberAnimation { duration: 250 } }

        Column {
            anchors.centerIn: parent
            spacing: 14

            CairoGlyph {
                motif: "dhun_play"
                glyphColor: Theme.m3primary || Theme.accent || "#c0c4ee"
                anchors.horizontalCenter: parent.horizontalCenter
                width: 72
                height: 72
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: lyricEngine.hasTrack ? (LyricsService.trackTitle || "STANDBY") : "STANDBY"
                font.family: "Plus Jakarta Sans, Manrope, sans-serif"
                font.weight: Font.ExtraBold
                font.letterSpacing: 4.0
                font.pixelSize: 22
                color: Theme.m3primary || Theme.accent || "#c0c4ee"
                opacity: 0.88
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: lyricEngine.hasTrack ? (LyricsService.trackArtist || "") : ""
                font.family: "Plus Jakarta Sans, Manrope, sans-serif"
                font.weight: Font.DemiBold
                font.letterSpacing: 2.0
                font.pixelSize: 14
                color: root.bronzeColor
                opacity: 0.70
                visible: text.length > 0
            }
        }
    }

    // ── 7. Radial Iris Reveal Cutout Surface ──────────────────────────────
    Canvas {
        id: irisCanvas
        anchors.fill: parent
        z: 25
        visible: root.irisRadius > 0.1

        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            if (root.irisRadius <= 0.1) return

            ctx.save()
            ctx.fillStyle = "#000000"
            ctx.beginPath()
            ctx.rect(0, 0, width, height)
            ctx.arc(root.cx, root.cy, root.irisRadius, 0, 2 * Math.PI, true)
            ctx.closePath()
            ctx.fill()
            ctx.restore()
        }
    }

    onIrisRadiusChanged: irisCanvas.requestPaint()
}
