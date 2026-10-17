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

    function tokenizeLineToSingleWords(lineText, lineStartMs, nextLineStartMs) {
        // 1. Clean parenthetical ad-libs like "(All night long)" or "(Forever)" if they duplicate, or split every single whitespace token:
        var rawTokens = lineText.trim().split(/\s+/).filter(function(w) { return w.length > 0; });
        if (rawTokens.length === 0) return [];

        // 2. Pure 1-word array: EVERY element in `rawTokens` is its own standalone row!
        // DO NOT group short words, articles, or pronouns. 1 token = 1 single word string.
        var rawGapMs = Math.max(350, nextLineStartMs - lineStartMs);

        // 3. Adaptive Tempo Window: scales naturally with fast rap/pop or slow ballads
        // Takes 86% of the real timestamp gap (capped at 420ms * wordCount so long instrumental pauses don't stretch words)
        var maxNaturalWindow = rawTokens.length * 420;
        var activeWindowMs = Math.min(rawGapMs * 0.86, maxNaturalWindow);

        // 4. Weight each single word slightly by character length so short words ("I", "a", "in") step fast
        // and longer punch words ("confidence", "measurements", "together?") hold slightly longer:
        var weights = [];
        var totalWeight = 0;
        for (var i = 0; i < rawTokens.length; i++) {
            var cleanLen = rawTokens[i].replace(/[^a-zA-Z0-9\u0900-\u097F]/g, "").length;
            var w = Math.max(1.0, Math.pow(cleanLen, 0.55));
            if (i === rawTokens.length - 1) w *= 1.25; // Slight hold on the last word of a line
            weights.push(w);
            totalWeight += w;
        }

        var result = [];
        var cursorMs = lineStartMs;
        for (var j = 0; j < rawTokens.length; j++) {
            var durMs = (weights[j] / totalWeight) * activeWindowMs;
            result.push({
                word: rawTokens[j],          // STRICTLY 1 WORD STRING (never an array of 2 words!)
                startMs: Math.round(cursorMs),
                endMs: Math.round(cursorMs + durMs)
            });
            cursorMs += durMs;
        }
        return result;
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
            var lineStartMs = Math.round(cur.time * 1000)
            var nextLineStartMs = (i + 1 < rawLines.length)
                ? Math.round(rawLines[i + 1].time * 1000)
                : (lineStartMs + 6000)

            // A. Check for rich word-level timestamps (enhanced LRC)
            if (cur.words && cur.words.length > 0) {
                for (var w = 0; w < cur.words.length; w++) {
                    var cw = cur.words[w]
                    var wStart = Math.round(cw.time * 1000)
                    var isLastWord = (w === cur.words.length - 1)
                    var vocalEnd = (cw.dur !== undefined && cw.dur > 0)
                        ? (wStart + Math.round(cw.dur * 1000))
                        : (!isLastWord ? Math.round(cur.words[w + 1].time * 1000) : Math.min(nextLineStartMs - 80, wStart + 1000))
                    var nextWStart = !isLastWord
                        ? Math.round(cur.words[w + 1].time * 1000)
                        : nextLineStartMs

                    wordsList.push({
                        id: i + "_" + w,
                        text: cw.text,
                        glyph: GlyphMap.lookupGlyph(cw.text) || "",
                        time: wStart / 1000.0,
                        startMs: wStart,
                        endMs: nextWStart,
                        vocalEndMs: Math.max(wStart + 120, vocalEnd),
                        duration: (nextWStart - wStart) / 1000.0,
                        lineIndex: i,
                        chunkIndex: w,
                        rowWords: [{ text: cw.text, startMs: wStart, endMs: Math.max(wStart + 120, vocalEnd) }]
                    })
                }
            } else {
                // B. Pure 1-Word Architecture (Standard .lrc Lines)
                var singleWords = root.tokenizeLineToSingleWords(cur.text, lineStartMs, nextLineStartMs)
                if (singleWords.length === 0) continue

                for (var j = 0; j < singleWords.length; j++) {
                    var sw = singleWords[j]
                    var isLast = (j === singleWords.length - 1)
                    var chunkEndMs = isLast ? nextLineStartMs : singleWords[j + 1].startMs

                    wordsList.push({
                        id: i + "_" + j,
                        text: sw.word,
                        glyph: GlyphMap.lookupGlyph(sw.word) || "",
                        time: sw.startMs / 1000.0,
                        startMs: sw.startMs,
                        endMs: chunkEndMs,
                        vocalEndMs: sw.endMs,
                        duration: (chunkEndMs - sw.startMs) / 1000.0,
                        lineIndex: i,
                        chunkIndex: j,
                        rowWords: [{ text: sw.word, startMs: sw.startMs, endMs: sw.endMs }]
                    })
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
