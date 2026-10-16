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
 *   - Flat Rectangular Highlighter (Word Document Style): clean 90-degree untilted rectangle
 *     wrapping strictly the active word with natural padding and smooth horizontal wipe.
 *   - High-contrast text: crisp dark ink (#08090d) on luminous highlights, pale cream on deep tones.
 *   - Wallpaper Theme Palette: auto-boosts saturation on pale/pastel wallpapers to maintain vibrancy.
 *   - Precision Audio-Synchronized Sub-Word Stepping: locked to microsecond MPRIS position so
 *     words stay tightly synced on fast rap songs and slow ballads alike.
 *   - 18 Custom Angular SVG Vector Glyphs with native GPU CurveRenderer anti-aliasing.
 *   - Instant single-Enter unlock with radial iris reveal.
 */
Item {
    id: root
    anchors.fill: parent

    focus: true

    // Center coordinates on screen
    readonly property real cx: root.width / 2
    readonly property real cy: root.height / 2

    // ── Wallpaper Theme Palette Saturation Booster ─────────────────────────
    function getVibrantThemeColor() {
        var c = Theme.m3primary || Theme.accent || Qt.rgba(0.46, 0.81, 0.97, 1.0)
        var r = c.r, g = c.g, b = c.b
        var max = Math.max(r, g, b), min = Math.min(r, g, b)
        var d = max - min
        var h = 0
        if (d > 0.0001) {
            if (max === r) h = ((g - b) / d + (g < b ? 6 : 0)) / 6
            else if (max === g) h = ((b - r) / d + 2) / 6
            else h = ((r - g) / d + 4) / 6
        }
        var s = max === 0 ? 0 : d / max
        var v = max
        var boostS = Math.max(s, 0.78)
        var boostV = Math.max(0.75, Math.min(v, 0.95))
        return Qt.hsva(h, boostS, boostV, 1.0)
    }

    readonly property color vibrantPrimary: getVibrantThemeColor()
    readonly property color highlightColor: root.vibrantPrimary

    readonly property real highlightLuminance: 0.299 * highlightColor.r + 0.587 * highlightColor.g + 0.114 * highlightColor.b
    readonly property color highlightedTextColor: highlightLuminance > 0.42 ? "#08090d" : "#f7ebed"

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

    // Live continuous audio position for instant sub-word stepping
    readonly property real liveAudioPosition: lyricEngine.currentPosition

    onLiveAudioPositionChanged: {
        var pos = root.liveAudioPosition + 0.22
        for (var i = 0; i < delegates.length; i++) {
            if (delegates[i].stage === 0) {
                delegates[i].updateSubWord(pos)
            }
        }
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
        height: 140
        x: (root.width - width) / 2

        property int stage: 4 // -1: pre-entry, 0: active bottom, 1: middle, 2: top, 3: exiting, 4: idle
        property string chunkText: ""
        property string glyphMotif: ""
        property real currentDuration: 1.0
        property real chunkStartTime: 0.0

        // Parse individual words
        readonly property var words: {
            var s = (delegateRoot.chunkText || "").trim()
            if (!s || s.length === 0) return []
            return s.split(/\s+/)
        }
        readonly property string word0: words.length > 0 ? words[0] : ""
        readonly property string word1: words.length > 1 ? words[1] : ""
        readonly property bool hasSecondWord: word1.length > 0

        readonly property real word0Ratio: {
            if (!hasSecondWord) return 1.0
            var len0 = Math.max(1, word0.length)
            var len1 = Math.max(1, word1.length)
            return Math.min(0.70, Math.max(0.30, (len0 + 0.5) / (len0 + len1 + 1.0)))
        }

        readonly property real word1StartTime: chunkStartTime + Math.max(0.06, (currentDuration * word0Ratio) - 0.07)

        // Single-word highlight stepping
        property int activeWordSubIndex: 0

        function updateSubWord(pos) {
            if (stage !== 0 || !hasSecondWord) return
            if (chunkStartTime > 0.0 && pos >= word1StartTime) {
                if (activeWordSubIndex !== 1) activeWordSubIndex = 1
            } else if (chunkStartTime > 0.0 && pos < word1StartTime) {
                if (activeWordSubIndex !== 0) activeWordSubIndex = 0
            }
        }

        Timer {
            id: subWordTimer
            interval: Math.max(60, Math.round((delegateRoot.currentDuration * delegateRoot.word0Ratio - 0.07) * 1000))
            running: delegateRoot.stage === 0 && delegateRoot.hasSecondWord && delegateRoot.activeWordSubIndex === 0
            repeat: false
            onTriggered: {
                delegateRoot.activeWordSubIndex = 1
            }
        }

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
                // Stage -1 (Pre-Entry Spawn)
                enableAnim = false
                activeWordSubIndex = 0
                subWordTimer.stop()
                stageY = root.cy + 210
                stageOpacity = 0.0
                stageScaleX = 0.88
                stageScaleY = 0.50
                stageRotX = 8.0
                z = 1
                enableAnim = true
            } else if (newStage === 0) {
                // Stage 0 (Bottom Active Spoken Row)
                activeWordSubIndex = 0
                if (hasSecondWord) subWordTimer.restart()
                stageY = root.cy + 110
                stageOpacity = 1.0
                stageScaleX = 1.0
                stageScaleY = 1.0
                stageRotX = 0.0
                z = 30
            } else if (newStage === 1) {
                // Stage 1 (Middle Row — Just Passed)
                subWordTimer.stop()
                stageY = root.cy - 12
                stageOpacity = 0.92
                stageScaleX = 0.86
                stageScaleY = 0.74
                stageRotX = 20.0
                z = 20
            } else if (newStage === 2) {
                // Stage 2 (Top Row — Receding Barrel Edge)
                subWordTimer.stop()
                stageY = root.cy - 118
                stageOpacity = 0.70
                stageScaleX = 0.72
                stageScaleY = 0.54
                stageRotX = 38.0
                z = 10
            } else if (newStage === 3) {
                // Stage 3 (Exiting Top — Crushing Flat)
                subWordTimer.stop()
                stageY = root.cy - 195
                stageOpacity = 0.0
                stageScaleX = 0.54
                stageScaleY = 0.12
                stageRotX = 58.0
                z = 5
            } else {
                subWordTimer.stop()
                stageOpacity = 0.0
                stage = 4
                z = 0
            }
        }

        Row {
            id: contentRow
            anchors.centerIn: parent
            spacing: 20

            // 18 Custom Cairo Angular SVG Vector Glyph with CurveRenderer
            CairoGlyph {
                id: glyphItem
                motif: delegateRoot.glyphMotif
                glyphColor: root.vibrantPrimary
                anchors.verticalCenter: parent.verticalCenter
                width: 86
                height: 86
                visible: motif.length > 0
            }

            // Words Row: renders individual words with clean Word document rectangular highlighting
            Row {
                id: wordsRow
                anchors.verticalCenter: parent.verticalCenter
                spacing: 16

                // Word 0 Item
                Item {
                    id: wordBox0
                    visible: delegateRoot.word0.length > 0
                    readonly property bool isHighlighted: delegateRoot.stage === 0 && delegateRoot.activeWordSubIndex === 0
                    width: wordText0.contentWidth + 28
                    height: wordText0.contentHeight + 10
                    anchors.verticalCenter: parent.verticalCenter

                    // Word Document Rectangular Highlighter (Untilted, radius: 4)
                    Rectangle {
                        id: highlightRect0
                        anchors.fill: parent
                        radius: 4
                        color: root.highlightColor
                        transformOrigin: Item.Left
                        scale: wordBox0.isHighlighted ? 1.0 : 0.0
                        opacity: wordBox0.isHighlighted ? 1.0 : 0.0

                        Behavior on scale {
                            NumberAnimation { duration: 90; easing.type: Easing.OutQuad }
                        }
                        Behavior on opacity {
                            NumberAnimation { duration: 90; easing.type: Easing.OutQuad }
                        }
                    }

                    Text {
                        id: wordText0
                        anchors.centerIn: parent
                        text: delegateRoot.word0
                        font.family: "Plus Jakarta Sans, Manrope, sans-serif"
                        font.weight: Font.ExtraBold
                        font.letterSpacing: -2.8
                        font.pixelSize: delegateRoot.calcFontSize(delegateRoot.chunkText)
                        color: wordBox0.isHighlighted ? root.highlightedTextColor : (delegateRoot.stage === 0 ? root.vibrantPrimary : root.bronzeColor)

                        Behavior on color {
                            ColorAnimation { duration: 90; easing.type: Easing.OutQuad }
                        }
                    }
                }

                // Word 1 Item
                Item {
                    id: wordBox1
                    visible: delegateRoot.hasSecondWord
                    readonly property bool isHighlighted: delegateRoot.stage === 0 && delegateRoot.activeWordSubIndex === 1
                    width: wordText1.contentWidth + 28
                    height: wordText1.contentHeight + 10
                    anchors.verticalCenter: parent.verticalCenter

                    // Word Document Rectangular Highlighter (Untilted, radius: 4)
                    Rectangle {
                        id: highlightRect1
                        anchors.fill: parent
                        radius: 4
                        color: root.highlightColor
                        transformOrigin: Item.Left
                        scale: wordBox1.isHighlighted ? 1.0 : 0.0
                        opacity: wordBox1.isHighlighted ? 1.0 : 0.0

                        Behavior on scale {
                            NumberAnimation { duration: 90; easing.type: Easing.OutQuad }
                        }
                        Behavior on opacity {
                            NumberAnimation { duration: 90; easing.type: Easing.OutQuad }
                        }
                    }

                    Text {
                        id: wordText1
                        anchors.centerIn: parent
                        text: delegateRoot.word1
                        font.family: "Plus Jakarta Sans, Manrope, sans-serif"
                        font.weight: Font.ExtraBold
                        font.letterSpacing: -2.8
                        font.pixelSize: delegateRoot.calcFontSize(delegateRoot.chunkText)
                        color: wordBox1.isHighlighted ? root.highlightedTextColor : (delegateRoot.stage === 0 ? root.vibrantPrimary : root.bronzeColor)

                        Behavior on color {
                            ColorAnimation { duration: 90; easing.type: Easing.OutQuad }
                        }
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
        nextD.chunkStartTime = beat.time || 0.0
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
            d2.chunkStartTime = w2.time || 0.0
            d2.setStage(2)
        }
        if (idx >= 1) {
            var w1 = lyricEngine.allWords[idx - 1]
            d1.chunkText = w1.text
            d1.glyphMotif = w1.glyph || ""
            d1.currentDuration = w1.duration || 1.0
            d1.chunkStartTime = w1.time || 0.0
            d1.setStage(1)
        }
        var w0 = lyricEngine.allWords[idx]
        d0.chunkText = w0.text
        d0.glyphMotif = w0.glyph || ""
        d0.currentDuration = w0.duration || 1.0
        d0.chunkStartTime = w0.time || 0.0
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
}
