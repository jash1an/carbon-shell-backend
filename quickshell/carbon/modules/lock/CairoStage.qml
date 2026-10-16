import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../../Singletons"

/**
 * CairoStage.qml:
 * Carbon // Cairo Synced-Lyric Standby & Lock Screen Replacement
 *
 * Visual Features:
 *   - Pure OLED solid black screen (#000000) with ZERO background animations or GPU overhead.
 *   - Clean Word-document style flat rectangular highlighter behind the active spoken lyric phrase.
 *   - Dynamic wallpaper theme palette colors: automatic HSV saturation booster transforms pale/pastel
 *     tones into lively, vibrant colors.
 *   - Strict 2-word vertical stack gliding upward with tempo-adaptive duration.
 *   - High-contrast text: crisp dark ink (#07080c) over bright highlight, vivid theme palette on upper rows.
 *   - Standby note and typography in vibrant theme color.
 *   - Instant unlock: Return / Enter / Space triggers radial iris reveal.
 */
Item {
    id: root
    anchors.fill: parent

    focus: true

    // Center coordinates on screen
    readonly property real cx: root.width / 2
    readonly property real cy: root.height / 2

    // ── Dynamic Wallpaper Theme Color Booster ─────────────────────────────
    // Transforms pale/lifeless palette colors into vivid, punchy tones
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
        // If color is pale (low saturation), boost to vivid level (>= 0.82)
        var boostS = Math.max(s, 0.82)
        // Keep brightness in rich punchy range (0.75 - 0.95)
        var boostV = Math.max(0.75, Math.min(v, 0.95))
        return Qt.hsva(h, boostS, boostV, 1.0)
    }

    readonly property color vibrantPrimary: getVibrantThemeColor()

    // Calculate perceived luminance to select high-contrast highlight text
    readonly property real highlightLuminance: {
        var c = root.vibrantPrimary
        return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
    }

    // Text inside the Word-document highlighter: crisp dark ink if bright, white if deep
    readonly property color highlightTextColor: highlightLuminance > 0.38 ? "#07080c" : "#ffffff"

    // Upper rows: vibrant theme palette color
    readonly property color rowTextColor: root.vibrantPrimary

    // ── 1. Pure Pitch Black Background (Zero Aurora / Zero Overhead) ─────
    Rectangle {
        id: pitchBlackBg
        anchors.fill: parent
        color: "#000000"
        z: 0
    }

    // ── 2. Synced Lyric Engine ───────────────────────────────────────────
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

    // Capture Return / Enter / Space key for instant unlock
    Keys.onPressed: (event) => {
        if (!root.readyToUnlock) return
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            event.accepted = true
            root.triggerUnlock()
        }
    }

    MouseArea {
        anchors.fill: parent
        z: 30
        onClicked: {
            root.forceActiveFocus()
        }
    }

    Component.onCompleted: {
        root.forceActiveFocus()
        root.syncInitialCluster()
    }

    // ── 4. Reusable Word Delegate Component ──────────────────────────────
    component CairoWordDelegate: Item {
        id: delegateRoot
        width: root.width
        height: 110
        x: (root.width - width) / 2

        property int stage: 4 // -1: pre-entry, 0: active bottom, 1: middle, 2: top, 3: exiting, 4: idle
        property string chunkText: ""
        property string glyphMotif: ""
        property real currentDuration: 1.0

        // Parse individual words
        readonly property var words: {
            var s = (delegateRoot.chunkText || "").trim()
            if (!s || s.length === 0) return []
            return s.split(/\s+/)
        }
        readonly property string word0: words.length > 0 ? words[0] : ""
        readonly property string word1: words.length > 1 ? words[1] : ""
        readonly property bool hasSecondWord: word1.length > 0

        // Tracks which single word inside this row is highlighted (0 or 1)
        property int activeWordSubIndex: 0

        Timer {
            id: subWordTimer
            interval: {
                if (!delegateRoot.hasSecondWord) return 1000
                var len0 = Math.max(1, delegateRoot.word0.length)
                var len1 = Math.max(1, delegateRoot.word1.length)
                var ratio0 = Math.min(0.70, Math.max(0.30, (len0 + 1.0) / (len0 + len1 + 2.0)))
                return Math.max(150, Math.round(delegateRoot.currentDuration * 1000 * ratio0))
            }
            running: delegateRoot.stage === 0 && delegateRoot.hasSecondWord && delegateRoot.activeWordSubIndex === 0
            repeat: false
            onTriggered: {
                delegateRoot.activeWordSubIndex = 1
            }
        }

        // Adaptive animation duration based on tempo
        readonly property int animDur: currentDuration < 0.65 ? 240 : 330

        // Direct spatial animated properties with springy elastic "bumpy" pop
        property real stageY: root.cy + 190
        property real stageOpacity: 0.0
        property real stageScaleX: 0.88
        property real stageScaleY: 0.50
        property real stageRotX: 0.0
        property real textSlideY: 0.0

        property bool enableAnim: true

        y: stageY - height / 2
        opacity: stageOpacity
        visible: stageOpacity > 0.005

        // Expressive bouncy overshoot physics on entry
        Behavior on stageY { enabled: delegateRoot.enableAnim; NumberAnimation { duration: delegateRoot.animDur; easing.type: Easing.OutBack; easing.overshoot: 1.55 } }
        Behavior on stageScaleX { enabled: delegateRoot.enableAnim; NumberAnimation { duration: delegateRoot.animDur; easing.type: Easing.OutBack; easing.overshoot: 1.35 } }
        Behavior on stageScaleY { enabled: delegateRoot.enableAnim; NumberAnimation { duration: delegateRoot.animDur; easing.type: Easing.OutBack; easing.overshoot: 1.50 } }
        Behavior on stageRotX { enabled: delegateRoot.enableAnim; NumberAnimation { duration: delegateRoot.animDur; easing.type: Easing.OutBack; easing.overshoot: 1.25 } }
        Behavior on stageOpacity { enabled: delegateRoot.enableAnim; NumberAnimation { duration: Math.max(160, delegateRoot.animDur - 50); easing.type: Easing.OutCubic } }
        Behavior on textSlideY { enabled: delegateRoot.enableAnim; NumberAnimation { duration: Math.max(160, delegateRoot.animDur - 50); easing.type: Easing.OutBack; easing.overshoot: 1.45 } }

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

        function calcFontSize(txt, isHighlighted) {
            var len = (txt || "").length
            if (delegateRoot.stage === 0) {
                if (len > 10) return 68
                if (len > 6) return 80
                return 92
            } else if (delegateRoot.stage === 1) {
                if (len > 10) return 56
                if (len > 6) return 66
                return 76
            } else {
                if (len > 10) return 46
                if (len > 6) return 54
                return 64
            }
        }

        function setStage(newStage) {
            stage = newStage
            if (newStage === -1) {
                // Pre-entry: initialize below active slot without animation
                enableAnim = false
                activeWordSubIndex = 0
                subWordTimer.stop()
                stageY = root.cy + 195
                stageOpacity = 0.0
                stageScaleX = 0.88
                stageScaleY = 0.50
                stageRotX = 8.0
                textSlideY = 24.0
                z = 10
                enableAnim = true
            } else if (newStage === 0) {
                // Stage 0: Active Bottom Row — Bumpy pop into view
                activeWordSubIndex = 0
                if (hasSecondWord) subWordTimer.restart()
                stageY = root.cy + 105
                stageOpacity = 1.0
                stageScaleX = 1.0
                stageScaleY = 1.0
                stageRotX = 0.0
                textSlideY = 0.0
                z = 10
            } else if (newStage === 1) {
                // Stage 1: Middle Row — Just Spoken, Unhighlighted Vibrant Theme Color
                subWordTimer.stop()
                stageY = root.cy - 10
                stageOpacity = 0.88
                stageScaleX = 0.88
                stageScaleY = 0.80
                stageRotX = 16.0
                z = 8
            } else if (newStage === 2) {
                // Stage 2: Top Row — Receding Dimmer Theme Color
                subWordTimer.stop()
                stageY = root.cy - 110
                stageOpacity = 0.58
                stageScaleX = 0.74
                stageScaleY = 0.60
                stageRotX = 32.0
                z = 6
            } else if (newStage === 3) {
                // Stage 3: Exiting Top — Flat and Fades Out
                subWordTimer.stop()
                stageY = root.cy - 185
                stageOpacity = 0.0
                stageScaleX = 0.55
                stageScaleY = 0.15
                stageRotX = 52.0
                z = 4
            } else {
                subWordTimer.stop()
                stageOpacity = 0.0
                stage = 4
                z = 1
            }
        }

        Row {
            id: contentRow
            anchors.centerIn: parent
            spacing: 20

            // Companion pure SVG vector glyph
            CairoVectorGlyph {
                id: glyphItem
                motif: delegateRoot.glyphMotif
                glyphColor: root.vibrantPrimary
                anchors.verticalCenter: parent.verticalCenter
                width: 68
                height: 68
                opacity: (delegateRoot.stage === 0) ? 1.0 : 0.0
                visible: motif.length > 0 && opacity > 0.01

                Behavior on opacity { NumberAnimation { duration: 160 } }
            }

            // Word 0 Item
            Item {
                id: wordBox0
                visible: delegateRoot.word0.length > 0
                readonly property bool isHighlighted: delegateRoot.stage === 0 && delegateRoot.activeWordSubIndex === 0
                width: wordText0.contentWidth + 28
                height: wordText0.contentHeight + 14
                anchors.verticalCenter: parent.verticalCenter

                // Flat rectangular highlighter (Word-document style) strictly for Word 0
                CairoHighlightBlock {
                    id: highlight0
                    anchors.fill: parent
                    opened: wordBox0.isHighlighted
                    fillColor: root.vibrantPrimary
                }

                Text {
                    id: wordText0
                    anchors.centerIn: parent
                    text: delegateRoot.word0
                    font.family: "Google Sans Flex, Plus Jakarta Sans, Manrope, sans-serif"
                    font.weight: delegateRoot.stage === 0 ? Font.Bold : (delegateRoot.stage === 1 ? Font.DemiBold : Font.Medium)
                    font.letterSpacing: -1.8
                    font.pixelSize: delegateRoot.calcFontSize(text, wordBox0.isHighlighted)
                    color: wordBox0.isHighlighted ? root.highlightTextColor : root.rowTextColor

                    Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }

                    transform: Translate {
                        y: delegateRoot.textSlideY
                    }
                }
            }

            // Word 1 Item (if present in this chunk)
            Item {
                id: wordBox1
                visible: delegateRoot.hasSecondWord
                readonly property bool isHighlighted: delegateRoot.stage === 0 && delegateRoot.activeWordSubIndex === 1
                width: wordText1.contentWidth + 28
                height: wordText1.contentHeight + 14
                anchors.verticalCenter: parent.verticalCenter

                // Flat rectangular highlighter (Word-document style) strictly for Word 1
                CairoHighlightBlock {
                    id: highlight1
                    anchors.fill: parent
                    opened: wordBox1.isHighlighted
                    fillColor: root.vibrantPrimary
                }

                Text {
                    id: wordText1
                    anchors.centerIn: parent
                    text: delegateRoot.word1
                    font.family: "Google Sans Flex, Plus Jakarta Sans, Manrope, sans-serif"
                    font.weight: delegateRoot.stage === 0 ? Font.Bold : (delegateRoot.stage === 1 ? Font.DemiBold : Font.Medium)
                    font.letterSpacing: -1.8
                    font.pixelSize: delegateRoot.calcFontSize(text, wordBox1.isHighlighted)
                    color: wordBox1.isHighlighted ? root.highlightTextColor : root.rowTextColor

                    Behavior on color { ColorAnimation { duration: 160; easing.type: Easing.OutCubic } }

                    transform: Translate {
                        y: delegateRoot.textSlideY
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

        // 1. Advance all active delegates
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

            CairoVectorGlyph {
                motif: "note"
                glyphColor: root.vibrantPrimary
                anchors.horizontalCenter: parent.horizontalCenter
                width: 64
                height: 64
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: lyricEngine.hasTrack ? (LyricsService.trackTitle || "STANDBY") : "STANDBY"
                font.family: "Google Sans Flex, Plus Jakarta Sans, Manrope, sans-serif"
                font.weight: Font.ExtraBold
                font.letterSpacing: 4.0
                font.pixelSize: 22
                color: root.vibrantPrimary
                opacity: 0.88
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: lyricEngine.hasTrack ? (LyricsService.trackArtist || "") : ""
                font.family: "Google Sans Flex, Plus Jakarta Sans, Manrope, sans-serif"
                font.weight: Font.DemiBold
                font.letterSpacing: 2.0
                font.pixelSize: 14
                color: root.vibrantPrimary
                opacity: 0.60
                visible: text.length > 0
            }
        }
    }

    // ── 7. Radial Iris Reveal Cutout Surface ──────────────────────────────
    Canvas {
        id: irisCanvas
        anchors.fill: parent
        z: 20
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
