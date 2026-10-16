import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import "../../Singletons"
import "CairoGlyphMap.js" as GlyphMap

/**
 * CairoLyricEngine:
 * Strict 2-Word Lyric Timeline & Tempo-Adaptive Pacing Engine for Carbon // Cairo.
 *
 * Enforces 2-word chunks (single word ONLY if long or remainder).
 * Dynamically scales phrase duration so slow songs pace leisurely and fast rap songs sync sharply.
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

    // Strict 2-word chunker: necessarily 2 words long unless words are long or remainder
    function chunkTokens(tokens) {
        var chunks = []
        var w = 0
        while (w < tokens.length) {
            var w1 = tokens[w]
            var g1 = GlyphMap.lookupGlyph(w1)

            // If this is the last word in the line, it must be standalone
            if (w === tokens.length - 1) {
                chunks.push({
                    "text": w1,
                    "glyph": g1 || ""
                })
                w += 1
                break
            }

            var w2 = tokens[w + 1]
            var g2 = GlyphMap.lookupGlyph(w2)

            // A word is single ONLY if:
            // 1. w1 is a long standalone word (>= 8 chars, e.g. "accelerate", "composure")
            // 2. Both words are long (w1 >= 6 && w2 >= 6) and combined length > 12 chars
            var isSingleLong = false
            if (w1.length >= 8) {
                isSingleLong = true
            } else if (w1.length >= 6 && w2.length >= 6 && (w1.length + 1 + w2.length) > 12) {
                isSingleLong = true
            }

            if (isSingleLong) {
                chunks.push({
                    "text": w1,
                    "glyph": g1 || ""
                })
                w += 1
                continue
            }

            // Otherwise, necessarily combine into 2 words!
            var combinedGlyph = (g1 && g1.length > 0) ? g1 : (g2 || "")
            chunks.push({
                "text": w1 + " " + w2,
                "glyph": combinedGlyph
            })
            w += 2
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

            // Strict 2-word chunking
            var chunks = root.chunkTokens(rawTokens)
            if (chunks.length === 0) continue

            // Tempo-adaptive vocal singing duration:
            // Covers ~84% of the natural interval between lines so slow songs do not rush,
            // while leaving a natural 16% breathing gap between lyric lines.
            var singingDuration = lineDuration * 0.84
            if (lineDuration > 6.0) {
                // If there is an extended instrumental gap between lines, allow up to 1.6s per chunk
                singingDuration = Math.min(lineDuration - 1.0, Math.max(2.4, chunks.length * 1.5))
            } else if (lineDuration < 1.6) {
                // Fast rap delivery: use almost the entire available time
                singingDuration = Math.max(0.5, lineDuration - 0.15)
            }

            // Distribute singing duration across chunks weighted by character length
            var weights = []
            var totalWeight = 0
            for (var c = 0; c < chunks.length; c++) {
                var wt = Math.max(4, chunks[c].text.length)
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

        // Perceptual audio lookahead: 120ms (prevents MPRIS D-Bus IPC lag during fast rap songs)
        var pos = root.currentPosition + 0.12

        // If before first word
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

                // Check for seek jump or natural phrase break (gap > 2.0s)
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
