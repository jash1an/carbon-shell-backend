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
 * Implements:
 *   - 100% Pitch-Black Stage (#000000) with CairoBorderGlow steady perimeter spotlight.
 *   - 5 Persistent Word Delegates in a True Upward-Gliding 3D Barrel.
 *   - Strictly Single-Word Highlighting: single shared Rectangle highlight block
 *     that glides dynamically to whichever word in Stage 0 is currently active.
 *   - Zero highlight on Stage 1 (middle) and Stage 2 (top).
 *   - 60fps Interpolated Audio Clock with live [ and ] hotkeys for fine-tuning sync offset.
 *   - Instant single-Enter unlock with radial iris reveal.
 */
Item {
    id: root
    anchors.fill: parent

    focus: true

    // Center coordinates on screen
    readonly property real cx: root.width / 2
    readonly property real cy: root.height / 2

    // ── Palette Tokens ─────────────────────────────────────────────────────
    function getVibrantThemeColor() {
        var base = Theme.m3primary || Theme.accent || Qt.rgba(0.46, 0.82, 0.98, 1.0)
        var h = base.hslHue
        var s = base.hslSaturation
        var v = base.hslLightness

        if (h < 0) return Qt.rgba(0.46, 0.82, 0.98, 1.0)

        var boostS = Math.max(0.65, Math.min(s * 1.30, 0.95))
        var boostV = Math.max(0.75, Math.min(v, 0.95))
        return Qt.hsva(h, boostS, boostV, 1.0)
    }

    readonly property color vibrantPrimary: getVibrantThemeColor()
    readonly property color highlightColor: Qt.darker(root.vibrantPrimary, 1.18)

    readonly property real highlightLuminance: 0.299 * highlightColor.r + 0.587 * highlightColor.g + 0.114 * highlightColor.b
    readonly property color highlightedTextColor: "#f7ebed"

    readonly property color bronzeColor: {
        var sec = Theme.m3secondary || Qt.rgba(0.77, 0.77, 0.87, 1.0)
        var dSec = Qt.darker(sec, 1.15)
        var b = Qt.color("#9c6e54")
        return Qt.rgba(
            dSec.r * 0.40 + b.r * 0.60,
            dSec.g * 0.40 + b.g * 0.60,
            dSec.b * 0.40 + b.b * 0.60,
            1.0
        )
    }

    // High-precision effective audio position from 60fps clock
    readonly property real effectivePositionMs: lyricEngine.effectivePositionMs

    // ── 1. Pure Pitch-Black Stage (0% Shaders / 0% Chrome) ────────────────
    Rectangle {
        id: pitchBlackBg
        anchors.fill: parent
        color: "#000000"
        z: 0
    }

    // ── 1b. Music-Sensitive Ambient Perimeter Border ──────────────────────
    CairoAmbientBorder {
        id: ambientBorder
        anchors.fill: parent
        z: 1
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

    // Sync Offset Toast
    property string offsetToastText: ""
    property bool offsetToastVisible: false
    Timer {
        id: toastTimer
        interval: 1400
        onTriggered: root.offsetToastVisible = false
    }
    function showOffsetToast(val) {
        root.offsetToastText = "SYNC: " + (val > 0 ? "+" : "") + val + " ms"
        root.offsetToastVisible = true
        toastTimer.restart()
    }

    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_BracketLeft) {
            event.accepted = true
            lyricEngine.syncOffsetMs -= 50
            root.showOffsetToast(lyricEngine.syncOffsetMs)
        } else if (event.key === Qt.Key_BracketRight) {
            event.accepted = true
            lyricEngine.syncOffsetMs += 50
            root.showOffsetToast(lyricEngine.syncOffsetMs)
        } else if (root.readyToUnlock && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)) {
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
        height: 140
        x: (root.width - width) / 2

        property int stage: 4 // -1: pre-entry, 0: active bottom, 1: middle, 2: top, 3: exiting, 4: idle
        property string chunkText: ""
        property string glyphMotif: ""
        property real currentDuration: 1.0
        property real chunkStartTime: 0.0
        property real chunkStartMs: 0
        property real chunkEndMs: 0
        property real vocalEndMs: 0
        property var rowWords: []


        // Spatial animated properties
        property real stageY: root.cy + 210
        property real stageOpacity: 0.0
        property real stageScaleX: 0.88
        property real stageScaleY: 0.50
        property real stageRotX: 8.0

        property bool enableAnim: true

        y: stageY - height / 2
        opacity: stageOpacity
        visible: stageOpacity > 0.005

        // Transitions: 340ms Easing.OutQuint across all barrel coordinates
        Behavior on stageY {
            enabled: delegateRoot.enableAnim && delegateRoot.stage >= 0
            NumberAnimation { duration: 340; easing.type: Easing.OutQuint }
        }
        Behavior on stageScaleX {
            enabled: delegateRoot.enableAnim && delegateRoot.stage >= 0
            NumberAnimation { duration: 340; easing.type: Easing.OutQuint }
        }
        Behavior on stageScaleY {
            enabled: delegateRoot.enableAnim && delegateRoot.stage >= 0
            NumberAnimation { duration: 340; easing.type: Easing.OutQuint }
        }
        Behavior on stageRotX {
            enabled: delegateRoot.enableAnim && delegateRoot.stage >= 0
            NumberAnimation { duration: 340; easing.type: Easing.OutQuint }
        }
        Behavior on stageOpacity {
            enabled: delegateRoot.enableAnim && delegateRoot.stage >= 0
            NumberAnimation { duration: 340; easing.type: Easing.OutQuint }
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

        function calcFontSize(txt) {
            var len = (txt || "").length
            if (len > 12) return 86
            if (len > 8) return 102
            return 118
        }

        function setStage(newStage) {
            stage = newStage
            if (newStage === -1) {
                // Stage -1 (Pre-Entry Spawn: 0ms teleport without downward animation)
                enableAnim = false
                stageOpacity = 0.0
                stageY = root.cy + 195
                stageScaleX = 0.88
                stageScaleY = 0.50
                stageRotX = 8.0
                z = 1
                enableAnim = true
            } else if (newStage === 0) {
                // Stage 0 (Bottom Active Spoken Row: glides up from +195 to +105)
                stageY = root.cy + 105
                stageOpacity = 1.0
                stageScaleX = 1.0
                stageScaleY = 1.0
                stageRotX = 0.0
                z = 30
            } else if (newStage === 1) {
                // Stage 1 (Middle Row — Just Passed)
                stageY = root.cy - 35
                stageOpacity = 0.92
                stageScaleX = 0.86
                stageScaleY = 0.74
                stageRotX = 20.0
                z = 20
            } else if (newStage === 2) {
                // Stage 2 (Top Row — Receding Barrel Edge)
                stageY = root.cy - 135
                stageOpacity = 0.70
                stageScaleX = 0.72
                stageScaleY = 0.54
                stageRotX = 38.0
                z = 10
            } else if (newStage === 3) {
                // Stage 3 (Exiting Top — Crushing Flat)
                stageY = root.cy - 182
                stageOpacity = 0.0
                stageScaleX = 0.54
                stageScaleY = 0.12
                stageRotX = 58.0
                z = 1
            } else {
                // Stage 4 (Idle Pool Dormant)
                enableAnim = false
                stageOpacity = 0.0
                stageY = root.cy + 400
                z = 0
            }
        }

        Row {
            id: contentRow
            anchors.centerIn: parent
            spacing: 20

            // 18 Custom Cairo Angular SVG Vector Glyph with CurveRenderer
            // Strictly visible only on Stage 0 (hidden on Stage 1 and Stage 2)
            CairoGlyph {
                id: glyphItem
                motif: delegateRoot.glyphMotif
                glyphColor: root.vibrantPrimary
                anchors.verticalCenter: parent.verticalCenter
                width: 86
                height: 86
                opacity: (delegateRoot.stage === 0 && motif.length > 0) ? 1.0 : 0.0
                visible: opacity > 0.01 && motif.length > 0

                Behavior on opacity {
                    NumberAnimation { duration: 120; easing.type: Easing.OutQuad }
                }
            }

            // Word Box: holds the 0.52 translucent glass tape highlight behind the single word text
            Item {
                id: wordBox
                anchors.verticalCenter: parent.verticalCenter
                width: wordText.contentWidth
                height: Math.max(80, wordText.contentHeight)

                // Translucent Glass Tape highlight block
                Rectangle {
                    id: activeWordHighlight
                    z: -1
                    anchors.centerIn: parent
                    width: wordText.contentWidth + 36
                    height: wordText.contentHeight + 12
                    radius: 8
                    color: Qt.rgba(root.highlightColor.r, root.highlightColor.g, root.highlightColor.b, 0.45)
                    opacity: (delegateRoot.stage === 0) ? 1.0 : 0.0
                    visible: opacity > 0.01

                    Behavior on opacity {
                        NumberAnimation { duration: 140; easing.type: Easing.OutQuad }
                    }
                }

                Text {
                    id: wordText
                    anchors.centerIn: parent
                    text: delegateRoot.chunkText
                    font.family: "Plus Jakarta Sans, Manrope, sans-serif"
                    font.weight: Font.ExtraBold
                    font.letterSpacing: -2.8
                    font.pixelSize: delegateRoot.calcFontSize(delegateRoot.chunkText)
                    color: (delegateRoot.stage === 0)
                           ? root.highlightedTextColor
                           : root.bronzeColor

                    Behavior on color {
                        ColorAnimation { duration: 90; easing.type: Easing.OutQuad }
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

    readonly property bool hasActiveWords: {
        for (var i = 0; i < delegates.length; i++) {
            if (delegates[i].stage >= 0 && delegates[i].stage <= 2) return true
        }
        return false
    }

    function pushNewWord(beat) {
        handleBeatTriggered(beat)
    }

    function handleBeatTriggered(beat) {
        if (!beat) return

        if (ambientBorder && typeof ambientBorder.triggerBeat === "function") {
            ambientBorder.triggerBeat()
        }

        // 1. Synchronously increment stage += 1 on EVERY existing active delegate first
        // before activating the new delegate at stage = 0.
        // Assert that at most ONE delegate in the entire pool ever has stage === 0.
        for (var i = 0; i < delegates.length; i++) {
            var d = delegates[i]
            if (d.stage === 2) {
                d.setStage(3)
            } else if (d.stage === 1) {
                d.setStage(2)
            } else if (d.stage === 0) {
                d.setStage(1)
            } else if (d.stage === 3) {
                d.setStage(4)
            }
        }

        // Safety assertion: enforce zero delegates remaining at stage 0
        for (var i = 0; i < delegates.length; i++) {
            if (delegates[i].stage === 0) {
                delegates[i].setStage(1)
            }
        }

        // 2. Pick next delegate from pool
        var nextD = delegates[poolPointer]
        poolPointer = (poolPointer + 1) % delegates.length

        // 3. Set content and reset to spawn at Stage -1 (0ms teleport without downward fly)
        nextD.chunkText = beat.text
        nextD.glyphMotif = beat.glyph || ""
        nextD.currentDuration = beat.duration || 1.0
        nextD.chunkStartTime = beat.time || 0.0
        nextD.chunkStartMs = beat.startMs || Math.round(beat.time * 1000)
        nextD.chunkEndMs = beat.endMs || Math.round((beat.time + beat.duration) * 1000)
        nextD.vocalEndMs = beat.vocalEndMs || nextD.chunkEndMs
        nextD.rowWords = beat.rowWords || [{ text: beat.text, startMs: nextD.chunkStartMs, endMs: nextD.vocalEndMs }]
        nextD.setStage(-1)

        // 4. On next frame, glide smoothly upward into Stage 0 with Behavior enabled
        Qt.callLater(function() {
            // Strictly enforce single-stage-0 invariant across all other delegates
            for (var j = 0; j < delegates.length; j++) {
                if (delegates[j] !== nextD && delegates[j].stage === 0) {
                    delegates[j].setStage(1)
                }
            }
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
            d2.chunkStartTime = w2.time || 0.0
            d2.chunkStartMs = w2.startMs || Math.round(w2.time * 1000)
            d2.chunkEndMs = w2.endMs || Math.round((w2.time + w2.duration) * 1000)
            d2.vocalEndMs = w2.vocalEndMs || d2.chunkEndMs
            d2.rowWords = w2.rowWords || [{ text: w2.text, startMs: d2.chunkStartMs, endMs: d2.vocalEndMs }]
            d2.setStage(2)
        }
        if (idx >= 1) {
            var w1 = lyricEngine.allWords[idx - 1]
            d1.chunkText = w1.text
            d1.glyphMotif = w1.glyph || ""
            d1.currentDuration = w1.duration || 1.0
            d1.chunkStartTime = w1.time || 0.0
            d1.chunkStartMs = w1.startMs || Math.round(w1.time * 1000)
            d1.chunkEndMs = w1.endMs || Math.round((w1.time + w1.duration) * 1000)
            d1.vocalEndMs = w1.vocalEndMs || d1.chunkEndMs
            d1.rowWords = w1.rowWords || [{ text: w1.text, startMs: d1.chunkStartMs, endMs: d1.vocalEndMs }]
            d1.setStage(1)
        }
        var w0 = lyricEngine.allWords[idx]
        d0.chunkText = w0.text
        d0.glyphMotif = w0.glyph || ""
        d0.currentDuration = w0.duration || 1.0
        d0.chunkStartTime = w0.time || 0.0
        d0.chunkStartMs = w0.startMs || Math.round(w0.time * 1000)
        d0.chunkEndMs = w0.endMs || Math.round((w0.time + w0.duration) * 1000)
        d0.vocalEndMs = w0.vocalEndMs || d0.chunkEndMs
        d0.rowWords = w0.rowWords || [{ text: w0.text, startMs: d0.chunkStartMs, endMs: d0.vocalEndMs }]
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
                glyphColor: root.vibrantPrimary
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
                color: root.vibrantPrimary
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

    // ── 8. Sync Offset OSD Toast ──────────────────────────────────────────
    Rectangle {
        id: offsetToastBox
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 36
        width: offsetToastLabel.contentWidth + 32
        height: 38
        radius: 8
        color: "#181a20"
        border.width: 1
        border.color: root.vibrantPrimary
        opacity: root.offsetToastVisible ? 0.94 : 0.0
        visible: opacity > 0.01
        z: 100

        Behavior on opacity { NumberAnimation { duration: 150 } }

        Text {
            id: offsetToastLabel
            anchors.centerIn: parent
            text: root.offsetToastText
            font.family: "Plus Jakarta Sans, Manrope, sans-serif"
            font.weight: Font.Bold
            font.pixelSize: 14
            color: root.vibrantPrimary
        }
    }
}
