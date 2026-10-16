import QtQuick
import Quickshell
import Quickshell.Services.Mpris
import "../../Singletons"
import "VerciGlyphMap.js" as GlyphMap

/**
 * VerciLyricEngine:
 * High-speed MPRIS synchronized lyrics parser with mandatory micro-chunking.
 *
 * Never displays long sentences at once. Subdivides every lyric line into
 * rapid 1-to-2 word micro-beats and feeds them into the 3-slot convex lens stack.
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

    readonly property var weakWords: ({
        "of": true, "a": true, "an": true, "to": true, "in": true, "on": true,
        "the": true, "my": true, "so": true, "or": true, "and": true, "at": true,
        "by": true, "for": true, "if": true, "is": true, "it": true, "as": true,
        "be": true, "we": true, "up": true, "do": true, "no": true
    })

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
            var nextTime = (i + 1 < rawLines.length) ? rawLines[i + 1].time : (cur.time + 4.0)
            var lineWindow = Math.max(0.6, nextTime - cur.time)

            // 1. Split line by whitespace
            var words = cur.text.trim().split(/\s+/).filter(function(w) { return w.length > 0 })
            if (words.length === 0) continue

            // 2. Group weak prepositions/articles
            var microBeats = []
            for (var w = 0; w < words.length; w++) {
                var word = words[w]
                var stripped = GlyphMap.stripWord(word)
                var isWeak = Boolean(root.weakWords[stripped])

                if (isWeak && (w + 1 < words.length)) {
                    var nextWord = words[w + 1]
                    var combined = word + " " + nextWord
                    if (combined.length <= 9) {
                        microBeats.push(combined)
                        w++ // skip paired word
                        continue
                    }
                }
                microBeats.push(word)
            }

            // 3. Subdivide line's time window across micro-beats
            var weights = []
            var totalWeight = 0
            for (var b = 0; b < microBeats.length; b++) {
                var wt = Math.max(3, microBeats[b].length)
                weights.push(wt)
                totalWeight += wt
            }

            var curBeatTime = cur.time
            for (var b = 0; b < microBeats.length; b++) {
                var frac = weights[b] / Math.max(1, totalWeight)
                var beatDur = lineWindow * frac
                // Clamped between 180ms and 650ms
                beatDur = Math.max(0.180, Math.min(0.650, beatDur))

                var beatText = microBeats[b]
                var parts = beatText.split(" ")
                var cleanFirst = GlyphMap.stripWord(parts[0])
                var cleanLast = GlyphMap.stripWord(parts[parts.length - 1])
                var glyph = GlyphMap.lookupGlyph(cleanLast) || GlyphMap.lookupGlyph(cleanFirst) || null

                // Angled cutout tape block for highlighted punch words
                var isPunch = (glyph !== null) || (beatText.length >= 7) || ((b % 3 === 0) && beatText.length >= 4)

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

    // High-precision 40ms position poller while playing
    Timer {
        interval: 40
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

        // 180ms lookahead for audio/render latency compensation
        var pos = root.currentPosition + 0.18

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
