import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import "../../Singletons"
import "CairoHinglishMap.js" as GlyphMap

/**
 * CairoLyricEngine:
 * Smart 1-to-2 Word Kinetic Lyric Timeline Engine for Carbon // Cairo.
 *
 * Enforces:
 *   - Words >= 6 chars, phrase-ending punch words, or glyph-matched words sit ALONE on their row.
 *   - Consecutive short helper words (<= 9 combined chars, no glyphs) group into 2-word rows.
 *   - Never allows 3+ words per row.
 *   - Line duration interpolation across (nextLineTime - lineStartTime) * 0.92.
 */
Item {
    id: root

    readonly property bool isPlaying: LyricsService.isPlaying
    readonly property bool hasTrack: LyricsService.hasTrack
    readonly property real currentPosition: LyricsService.currentPosition

    property var allWords: []
    readonly property bool hasLyrics: allWords.length > 0 && hasTrack

    // Rolling cluster tracking for compatibility & fallback
    property var row0Word: null
    property var row1Word: null
    property var row2Word: null
    property int clusterSize: 0

    property int currentWordIndex: -1
    property var activeBeat: null

    signal beatTriggered(var beatData)
    signal clearRequested()

    // Smart 1-to-2 word micro-chunker
    function chunkTokens(tokens) {
        var chunks = []
        var w = 0
        while (w < tokens.length) {
            var w1 = tokens[w]
            var g1 = GlyphMap.lookupGlyph(w1)

            // 1. If this is the phrase-ending punch word (last token in line), sit alone:
            if (w === tokens.length - 1) {
                chunks.push({
                    "text": w1,
                    "glyph": g1 || ""
                })
                w += 1
                break
            }

            // 2. Any word >= 6 chars or matched to a Cairo Vector Glyph MUST sit alone
            if (w1.length >= 6 || (g1 && g1.length > 0)) {
                chunks.push({
                    "text": w1,
                    "glyph": g1 || ""
                })
                w += 1
                continue
            }

            // 3. Inspect next word w2
            var w2 = tokens[w + 1]
            var g2 = GlyphMap.lookupGlyph(w2)

            // Only group two consecutive short helper words (<= 9 combined chars, NEITHER matched to a glyph)
            var combinedLen = w1.length + 1 + w2.length
            var canGroup = (!g1 || g1.length === 0) && (!g2 || g2.length === 0) && (w2.length < 6) && (combinedLen <= 9)

            if (canGroup) {
                chunks.push({
                    "text": w1 + " " + w2,
                    "glyph": ""
                })
                w += 2
            } else {
                chunks.push({
                    "text": w1,
                    "glyph": g1 || ""
                })
                w += 1
            }
        }
        return chunks
    }

    function processLyrics() {
        var rawLines = LyricsService.lines || []
        if (!rawLines || rawLines.length === 0) {
            root.allWords = []
            root.row0Word = null
            root.row1Word = null
            root.row2Word = null
            root.clusterSize = 0
            root.currentWordIndex = -1
            root.activeBeat = null
            root.clearRequested()
            return
        }

        var wordsList = []
        for (var i = 0; i < rawLines.length; i++) {
            var cur = rawLines[i]
            var nextTime = (i + 1 < rawLines.length) ? rawLines[i + 1].time : (cur.time + 3.8)
            var lineDuration = Math.max(0.6, nextTime - cur.time)

            // Split line into individual tokens
            var rawTokens = cur.text.trim().split(/\s+/).filter(function(w) { return w.length > 0 })
            if (rawTokens.length === 0) continue

            // Smart 1-to-2 word chunking
            var chunks = root.chunkTokens(rawTokens)
            if (chunks.length === 0) continue

            // Interpolate timed micro-beats across (nextLineTime - lineStartTime) * 0.92
            var singingDuration = lineDuration * 0.92
            if (lineDuration > 6.0) {
                singingDuration = Math.min(lineDuration - 0.8, Math.max(2.4, chunks.length * 1.5))
            } else if (lineDuration < 1.4) {
                singingDuration = Math.max(0.45, lineDuration - 0.10)
            }

            // Distribute singing duration across chunks weighted by character length
            var weights = []
            var totalWeight = 0
            for (var c = 0; c < chunks.length; c++) {
                var wt = Math.max(3, chunks[c].text.length)
                weights.push(wt)
                totalWeight += wt
            }

            var curChunkTime = cur.time
            for (var c = 0; c < chunks.length; c++) {
                var frac = weights[c] / Math.max(1, totalWeight)
                var chunkDur = singingDuration * frac

                wordsList.push({
                    "id": i + "_" + c,
                    "text": chunks[c].text,
                    "time": curChunkTime,
                    "duration": chunkDur,
                    "glyph": chunks[c].glyph || "",
                    "lineIndex": i,
                    "chunkIndex": c
                })

                curChunkTime += chunkDur
            }
        }

        root.allWords = wordsList.sort(function(a, b) { return a.time - b.time })
        root.updateSync()
    }

    Connections {
        target: LyricsService
        function onLinesChanged() {
            root.processLyrics()
        }
        function onTrackTitleChanged() {
            root.processLyrics()
        }
    }

    // High-precision 25ms position poller
    Timer {
        interval: 25
        repeat: true
        running: root.hasTrack
        onTriggered: {
            if (LyricsService.activePlayer && LyricsService.activePlayer.positionSupported) {
                LyricsService.activePlayer.positionChanged()
            }
            root.updateSync()
        }
    }

    function updateSync() {
        if (!root.allWords || root.allWords.length === 0) {
            root.row0Word = null
            root.row1Word = null
            root.row2Word = null
            root.clusterSize = 0
            root.currentWordIndex = -1
            root.activeBeat = null
            root.clearRequested()
            return
        }

        // Audio lookahead: 90ms
        var pos = root.currentPosition + 0.09

        if (pos < root.allWords[0].time) {
            root.row0Word = null
            root.row1Word = null
            root.row2Word = null
            root.clusterSize = 0
            root.currentWordIndex = -1
            root.activeBeat = null
            root.clearRequested()
            return
        }

        var idx = -1
        for (var i = 0; i < root.allWords.length; i++) {
            if (root.allWords[i].time <= pos) {
                idx = i
            } else {
                break
            }
        }

        // Check if current chunk has expired during an instrumental pause or track end
        if (idx >= 0 && idx < root.allWords.length) {
            var curW = root.allWords[idx]
            var nextW = (idx + 1 < root.allWords.length) ? root.allWords[idx + 1] : null
            var endThreshold = curW.time + Math.max(curW.duration + 2.0, 3.2)
            if (nextW) {
                if (pos > endThreshold && (nextW.time - pos > 0.8)) {
                    idx = -1
                }
            } else {
                if (pos > endThreshold) {
                    idx = -1
                }
            }
        }

        if (idx !== root.currentWordIndex) {
            var prevIdx = root.currentWordIndex
            root.currentWordIndex = idx

            if (idx >= 0 && idx < root.allWords.length) {
                var newWord = root.allWords[idx]
                root.activeBeat = newWord

                var isNewPhrase = false
                if (prevIdx >= 0 && (idx < prevIdx || idx > prevIdx + 2)) {
                    isNewPhrase = true
                } else if (root.row2Word) {
                    var gap = newWord.time - (root.row2Word.time + root.row2Word.duration)
                    if (gap > 2.0 || (newWord.lineIndex !== root.row2Word.lineIndex && gap > 1.2)) {
                        isNewPhrase = true
                    }
                }

                if (isNewPhrase || root.clusterSize === 0) {
                    root.row0Word = null
                    root.row1Word = null
                    root.row2Word = newWord
                    root.clusterSize = 1
                } else if (root.clusterSize === 1) {
                    root.row0Word = null
                    root.row1Word = root.row2Word
                    root.row2Word = newWord
                    root.clusterSize = 2
                } else {
                    root.row0Word = root.row1Word
                    root.row1Word = root.row2Word
                    root.row2Word = newWord
                    root.clusterSize = 3
                }

                root.beatTriggered(newWord)
            } else {
                root.row0Word = null
                root.row1Word = null
                root.row2Word = null
                root.clusterSize = 0
                root.activeBeat = null
                root.clearRequested()
            }
        }
    }

    Component.onCompleted: {
        root.processLyrics()
    }
}
