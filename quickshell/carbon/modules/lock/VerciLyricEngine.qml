import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import "../../Singletons"
import "VerciGlyphMap.js" as GlyphMap

/**
 * VerciLyricEngine:
 * High-speed MPRIS synchronized lyrics parser with mandatory 3-word max chunking.
 *
 * Keeps at most 3 words in every line that appears on screen.
 * Subdivides each line's duration smoothly across the chunks so they match
 * the singing tempo and never rush ahead of the music.
 */
Item {
    id: root

    readonly property bool isPlaying: LyricsService.isPlaying
    readonly property bool hasTrack: LyricsService.hasTrack
    readonly property real currentPosition: LyricsService.currentPosition

    property var allBeats: []
    readonly property bool hasLyrics: allBeats.length > 0 && hasTrack

    // Rolling 3-slot buffer of micro-beats
    property var slotABeat: null // Active present (index 0)
    property var slotBBeat: null // Just passed (index 1)
    property var slotCBeat: null // Exiting top (index 2)
    property int currentBeatIndex: -1

    function chunkLyrics() {
        var rawLines = LyricsService.lines || []
        if (!rawLines || rawLines.length === 0) {
            root.allBeats = []
            root.slotABeat = null
            root.slotBBeat = null
            root.slotCBeat = null
            root.currentBeatIndex = -1
            return
        }

        var beats = []
        for (var i = 0; i < rawLines.length; i++) {
            var cur = rawLines[i]
            var nextTime = (i + 1 < rawLines.length) ? rawLines[i + 1].time : (cur.time + 3.8)
            var lineDuration = Math.max(0.6, nextTime - cur.time)

            // 1. Split line by whitespace into words
            var words = cur.text.trim().split(/\s+/).filter(function(w) { return w.length > 0 })
            if (words.length === 0) continue

            // 2. Strict chunking: at most 3 words per chunk
            var chunks = []
            var w = 0
            while (w < words.length) {
                var remaining = words.length - w
                var take = 3
                if (remaining === 4) {
                    take = 2
                } else if (remaining < 3) {
                    take = remaining
                }
                chunks.push(words.slice(w, w + take).join(" "))
                w += take
            }

            // 3. Singing duration calculation:
            // For normal lines (<= 5.5s), sing throughout the line window.
            // For longer lines with instrumental gaps (>5.5s), clamp to realistic singing length.
            var singingDuration = lineDuration
            if (lineDuration > 5.5) {
                singingDuration = Math.min(lineDuration, Math.max(1.8, chunks.length * 1.35))
            }

            // Distribute singingDuration proportionally across chunks weighted by character length
            var weights = []
            var totalWeight = 0
            for (var b = 0; b < chunks.length; b++) {
                var wt = Math.max(4, chunks[b].length)
                weights.push(wt)
                totalWeight += wt
            }

            var curBeatTime = cur.time
            for (var b = 0; b < chunks.length; b++) {
                var frac = weights[b] / Math.max(1, totalWeight)
                var beatDur = singingDuration * frac

                var beatText = chunks[b]
                var parts = beatText.split(" ")

                // Check EVERY word in the 3-word chunk for a matching glyph
                var glyph = null
                for (var p = 0; p < parts.length; p++) {
                    var g = GlyphMap.lookupGlyph(parts[p])
                    if (g) {
                        glyph = g
                        break
                    }
                }

                // Angled cutout tape block for punch words:
                // punch if matched glyph, or first beat of multi-beat line, or length >= 8
                var isPunch = (glyph !== null) || (beatText.length >= 8) || (b === 0 && chunks.length > 1)

                beats.push({
                    "id": i + "_" + b,
                    "time": curBeatTime,
                    "duration": beatDur,
                    "text": beatText,
                    "glyph": glyph,
                    "isTape": isPunch,
                    "lineIndex": i,
                    "beatIndex": b
                })

                curBeatTime += beatDur
            }
        }

        root.allBeats = beats.sort(function(a, b) { return a.time - b.time })
        root.updateSync()
    }

    Connections {
        target: LyricsService
        function onLinesChanged() {
            root.chunkLyrics()
        }
        function onTrackTitleChanged() {
            root.chunkLyrics()
        }
    }

    // High-precision 30ms position poller while playing
    Timer {
        interval: 30
        repeat: true
        running: root.isPlaying && root.hasTrack
        onTriggered: {
            if (LyricsService.activePlayer && LyricsService.activePlayer.positionSupported) {
                LyricsService.activePlayer.positionChanged()
            }
            root.updateSync()
        }
    }

    function updateSync() {
        if (!root.allBeats || root.allBeats.length === 0) {
            root.slotABeat = null
            root.slotBBeat = null
            root.slotCBeat = null
            root.currentBeatIndex = -1
            return
        }

        // Precision lookahead: 60ms (0.06s) for human visual perception latency
        var pos = root.currentPosition + 0.06

        // If before first beat
        if (pos < root.allBeats[0].time) {
            root.slotABeat = null
            root.slotBBeat = null
            root.slotCBeat = null
            root.currentBeatIndex = -1
            return
        }

        var idx = -1
        for (var i = 0; i < root.allBeats.length; i++) {
            if (root.allBeats[i].time <= pos) {
                idx = i
            } else {
                break
            }
        }

        if (idx !== root.currentBeatIndex) {
            var oldIdx = root.currentBeatIndex
            root.currentBeatIndex = idx

            if (idx >= 0 && idx < root.allBeats.length) {
                var newBeat = root.allBeats[idx]
                root.slotCBeat = root.slotBBeat
                root.slotBBeat = root.slotABeat
                root.slotABeat = newBeat
            } else {
                root.slotABeat = null
                root.slotBBeat = null
                root.slotCBeat = null
            }
        }
    }

    Component.onCompleted: {
        root.chunkLyrics()
    }
}
