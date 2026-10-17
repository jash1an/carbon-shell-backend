import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import "../../Singletons"
import "CairoHinglishMap.js" as GlyphMap

/**
 * CairoLyricEngine:
 * High-Precision 60fps Kinetic Lyric Timeline Engine for Carbon // Cairo.
 *
 * Implements:
 *   - 60fps interpolated audio clock with MPRIS D-Bus drift-nudging & seek snapping.
 *   - Live keyboard sync offset (default -120ms lead compensation).
 *   - Enhanced word-level LRC parser (<mm:ss.xx> or [mm:ss.xx]).
 *   - Syllable-clamped vocal window cadence (fixes slow-motion instrumental stretching).
 *   - Holds final word calmly in Stage 0 across instrumental gaps.
 *   - Structured 1-to-2 word rows with per-word startMs/endMs tokens for single-word highlighting.
 */
Item {
    id: root

    readonly property bool isPlaying: LyricsService.isPlaying
    readonly property bool hasTrack: LyricsService.hasTrack
    readonly property real currentPosition: LyricsService.currentPosition

    // ── 1. 60fps Interpolated Audio Clock ──────────────────────────────────
    property real livePositionMs: 0
    property real lastFrameMs: 0
    property int syncOffsetMs: -120 // -120ms lead compensation for instantaneous visual perception

    readonly property real effectivePositionMs: Math.max(0, root.livePositionMs - root.syncOffsetMs)
    readonly property real effectivePositionSec: root.effectivePositionMs / 1000.0

    // Smooth drift nudging & seek snapping on MPRIS D-Bus position updates
    onCurrentPositionChanged: {
        var mprisPosMs = Math.round(root.currentPosition * 1000)
        var diff = Math.abs(mprisPosMs - root.livePositionMs)
        if (diff > 160 || root.livePositionMs === 0) {
            root.livePositionMs = mprisPosMs
        } else {
            root.livePositionMs += (mprisPosMs - root.livePositionMs) * 0.15
        }
        root.updateSync()
    }

    // High-precision 60fps clock driver (16ms)
    Timer {
        id: clock60fps
        interval: 16
        repeat: true
        running: root.hasTrack
        onTriggered: {
            var now = Date.now()
            var delta = root.lastFrameMs > 0 ? Math.min(60, now - root.lastFrameMs) : 16
            root.lastFrameMs = now

            if (root.isPlaying) {
                root.livePositionMs += delta
            }
            root.updateSync()
        }
    }

    // MPRIS position refresh pinger (250ms) to ensure D-Bus position ticks arrive
    Timer {
        interval: 250
        repeat: true
        running: root.hasTrack
        onTriggered: {
            if (LyricsService.activePlayer && LyricsService.activePlayer.positionSupported) {
                LyricsService.activePlayer.positionChanged()
            }
        }
    }

    // ── 2. Lyric Data & Timeline Storage ───────────────────────────────────
    property var allWords: []
    readonly property bool hasLyrics: allWords.length > 0 && hasTrack

    property var row0Word: null
    property var row1Word: null
    property var row2Word: null
    property int clusterSize: 0

    property int currentWordIndex: -1
    property var activeBeat: null

    signal beatTriggered(var beatData)
    signal clearRequested()

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
            var lineStartMs = Math.round(cur.time * 1000)
            var nextLineStartMs = (i + 1 < rawLines.length)
                ? Math.round(rawLines[i + 1].time * 1000)
                : (lineStartMs + 6000)
            var rawGapMs = Math.max(300, nextLineStartMs - lineStartMs)

            var lineWords = []

            // A. Check for rich word-level timestamps (enhanced LRC)
            if (cur.words && cur.words.length > 0) {
                for (var w = 0; w < cur.words.length; w++) {
                    var cw = cur.words[w]
                    var wStart = Math.round(cw.time * 1000)
                    var wEnd = (w + 1 < cur.words.length)
                        ? Math.round(cur.words[w + 1].time * 1000)
                        : Math.min(nextLineStartMs - 80, wStart + 1000)
                    lineWords.push({
                        text: cw.text,
                        startMs: wStart,
                        endMs: Math.max(wStart + 120, wEnd),
                        glyph: GlyphMap.lookupGlyph(cw.text) || ""
                    })
                }
            } else {
                // B. Vocal-Window Clamping for Standard .lrc Lines (Crucial)
                var rawTokens = cur.text.trim().split(/\s+/).filter(function(tk) { return tk.length > 0 })
                if (rawTokens.length === 0) continue

                var N = rawTokens.length
                var C = 0
                for (var t = 0; t < N; t++) {
                    C += rawTokens[t].length
                }

                // Natural vocal singing duration estimate based on syllable/vowel clusters:
                var estimatedVocalMs = (N * 240) + (C * 42)
                // Clamp active singing window so instrumental pauses NEVER stretch words:
                var vocalWindowMs = Math.min(rawGapMs * 0.90, Math.max(estimatedVocalMs, N * 180))

                // Distribute vocalWindowMs across words weighted by syllable count (plus 1.3x on final punch word)
                var weights = []
                var totalWeight = 0
                for (var k = 0; k < N; k++) {
                    var token = rawTokens[k]
                    var sylMatches = token.match(/[aeiouy]+/gi)
                    var syl = sylMatches ? Math.max(1, sylMatches.length) : 1
                    var wt = syl * (k === N - 1 ? 1.3 : 1.0)
                    weights.push(wt)
                    totalWeight += wt
                }

                var curMs = lineStartMs
                for (var k = 0; k < N; k++) {
                    var wDurMs = Math.round(vocalWindowMs * (weights[k] / Math.max(1, totalWeight)))
                    wDurMs = Math.max(120, wDurMs)
                    lineWords.push({
                        text: rawTokens[k],
                        startMs: curMs,
                        endMs: curMs + wDurMs,
                        glyph: GlyphMap.lookupGlyph(rawTokens[k]) || ""
                    })
                    curMs += wDurMs
                }
            }

            if (lineWords.length === 0) continue

            // C. Group timed words into 1-to-2 word rows for the kinetic barrel
            var wIdx = 0
            while (wIdx < lineWords.length) {
                var w1 = lineWords[wIdx]
                var isLastWord = (wIdx === lineWords.length - 1)

                // 1. Phrase-ending punch word (last token in line) sits ALONE:
                if (isLastWord) {
                    wordsList.push({
                        id: i + "_" + wIdx,
                        text: w1.text,
                        glyph: w1.glyph || "",
                        time: w1.startMs / 1000.0,
                        startMs: w1.startMs,
                        // Hold the final word in Stage 0 calmly until nextLineStartMs arrives!
                        endMs: nextLineStartMs,
                        vocalEndMs: w1.endMs,
                        duration: (nextLineStartMs - w1.startMs) / 1000.0,
                        lineIndex: i,
                        chunkIndex: wIdx,
                        rowWords: [ w1 ]
                    })
                    wIdx += 1
                    break
                }

                // 2. Word >= 6 chars or matched to a Cairo Vector Glyph MUST sit alone:
                if (w1.text.length >= 6 || (w1.glyph && w1.glyph.length > 0)) {
                    var nextWStart = (wIdx + 1 < lineWords.length) ? lineWords[wIdx + 1].startMs : nextLineStartMs
                    wordsList.push({
                        id: i + "_" + wIdx,
                        text: w1.text,
                        glyph: w1.glyph || "",
                        time: w1.startMs / 1000.0,
                        startMs: w1.startMs,
                        endMs: nextWStart,
                        vocalEndMs: w1.endMs,
                        duration: (nextWStart - w1.startMs) / 1000.0,
                        lineIndex: i,
                        chunkIndex: wIdx,
                        rowWords: [ w1 ]
                    })
                    wIdx += 1
                    continue
                }

                // 3. Inspect next word w2 for helper pairing:
                var w2 = lineWords[wIdx + 1]
                var isW2Last = (wIdx + 1 === lineWords.length - 1)
                var combinedLen = w1.text.length + 1 + w2.text.length
                var canGroup = (!w1.glyph || w1.glyph.length === 0) &&
                               (!w2.glyph || w2.glyph.length === 0) &&
                               (w2.text.length < 6) &&
                               (combinedLen <= 9) &&
                               !isW2Last // keep last punch word alone

                if (canGroup) {
                    var nextChunkStart = (wIdx + 2 < lineWords.length) ? lineWords[wIdx + 2].startMs : nextLineStartMs
                    wordsList.push({
                        id: i + "_" + wIdx,
                        text: w1.text + " " + w2.text,
                        glyph: "",
                        time: w1.startMs / 1000.0,
                        startMs: w1.startMs,
                        endMs: nextChunkStart,
                        vocalEndMs: w2.endMs,
                        duration: (nextChunkStart - w1.startMs) / 1000.0,
                        lineIndex: i,
                        chunkIndex: wIdx,
                        rowWords: [ w1, w2 ]
                    })
                    wIdx += 2
                } else {
                    var nextChunkStart = (wIdx + 1 < lineWords.length) ? lineWords[wIdx + 1].startMs : nextLineStartMs
                    wordsList.push({
                        id: i + "_" + wIdx,
                        text: w1.text,
                        glyph: w1.glyph || "",
                        time: w1.startMs / 1000.0,
                        startMs: w1.startMs,
                        endMs: nextChunkStart,
                        vocalEndMs: w1.endMs,
                        duration: (nextChunkStart - w1.startMs) / 1000.0,
                        lineIndex: i,
                        chunkIndex: wIdx,
                        rowWords: [ w1 ]
                    })
                    wIdx += 1
                }
            }
        }

        root.allWords = wordsList.sort(function(a, b) { return a.startMs - b.startMs })

        // 3rd-Beat Rhythm Fallback Pass:
        // Only trigger fallback on words with length >= 4 that are NOT in the stop-word list!
        var RHYTHM_FALLBACK_MOTIFS = [
            "dhun_play", "jaan_sparkle", "bijli_bolt", "nasha_vortex", "sona_diamond"
        ]
        var rhythmBeatCount = 0

        for (var b = 0; b < root.allWords.length; b++) {
            var item = root.allWords[b]
            if (item.glyph && item.glyph.length > 0) {
                rhythmBeatCount = 0
                continue
            }

            rhythmBeatCount++
            if (rhythmBeatCount >= 3) {
                var candidateWord = ""
                if (item.rowWords && item.rowWords.length > 0) {
                    candidateWord = item.rowWords[0].text
                } else {
                    candidateWord = (item.text || "").split(/\s+/)[0] || ""
                }

                var normWord = GlyphMap.normalizeLyricToken(candidateWord)
                if (normWord.length >= 4 && !GlyphMap.isStopWord(normWord)) {
                    var fallbackMotif = RHYTHM_FALLBACK_MOTIFS[b % RHYTHM_FALLBACK_MOTIFS.length]
                    item.glyph = fallbackMotif
                    rhythmBeatCount = 0
                }
            }
        }

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

    // ── 3. Update Sync & Beat Triggering ───────────────────────────────────
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

        var posMs = root.effectivePositionMs

        if (posMs < root.allWords[0].startMs) {
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
            if (root.allWords[i].startMs <= posMs) {
                idx = i
            } else {
                break
            }
        }

        // Expire chunk during extended instrumental pauses (> 4.5s after vocalEndMs and next chunk is > 1.2s away)
        if (idx >= 0 && idx < root.allWords.length) {
            var curChunk = root.allWords[idx]
            var nextChunk = (idx + 1 < root.allWords.length) ? root.allWords[idx + 1] : null
            var expireMs = curChunk.vocalEndMs + 4500
            if (nextChunk) {
                if (posMs > expireMs && (nextChunk.startMs - posMs > 1200)) {
                    idx = -1
                }
            } else {
                if (posMs > expireMs) {
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
                    var gap = newWord.startMs - root.row2Word.endMs
                    if (gap > 2000 || (newWord.lineIndex !== root.row2Word.lineIndex && gap > 1200)) {
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
