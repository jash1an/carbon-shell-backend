pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris

/**
 * LyricsService: Global singleton managing real-time synced lyrics (LRCLIB)
 * and MPRIS track progress. Automatically fetches and syncs line by line.
 */
Singleton {
    id: root

    readonly property var players: Mpris.players.values !== undefined ? Mpris.players.values : Mpris.players
    property string preferredPlayerBus: ""
    property real lastSkipTime: 0

    readonly property var activePlayer: {
        if (!players || players.length === 0) return null
        // 1. If we have a playing player, track it as preferred
        for (let i = 0; i < players.length; i++) {
            if (players[i].playbackState === MprisPlaybackState.Playing) {
                root.preferredPlayerBus = players[i].dbusName || ""
                return players[i]
            }
        }
        // 2. If recent skip or pause transition, stick with preferred player if still alive
        if (root.preferredPlayerBus && root.preferredPlayerBus.length > 0) {
            for (let i = 0; i < players.length; i++) {
                if ((players[i].dbusName || "") === root.preferredPlayerBus) {
                    return players[i]
                }
            }
        }
        // 3. Fallback to non-browser paused player with track
        for (let i = 0; i < players.length; i++) {
            const p = players[i]
            if (p.playbackState === MprisPlaybackState.Paused && (p.trackTitle || "").length > 0) {
                const name = (p.dbusName || p.identity || "").toLowerCase()
                if (!name.includes("firefox") && !name.includes("chromium") && !name.includes("chrome")) {
                    root.preferredPlayerBus = p.dbusName || ""
                    return p
                }
            }
        }
        // 4. Any paused player with track
        for (let i = 0; i < players.length; i++) {
            if (players[i].playbackState === MprisPlaybackState.Paused && (players[i].trackTitle || "").length > 0) {
                root.preferredPlayerBus = players[i].dbusName || ""
                return players[i]
            }
        }
        return players[0]
    }

    readonly property string trackTitle: activePlayer ? (activePlayer.trackTitle || "") : ""
    readonly property string trackArtist: activePlayer ? (activePlayer.trackArtist || "") : ""
    readonly property string trackAlbum: activePlayer && activePlayer.metadata ? (activePlayer.metadata["xesam:album"] || "") : ""
    readonly property string artUrl: activePlayer ? (activePlayer.trackArtUrl || "") : ""
    readonly property bool isPlaying: activePlayer && activePlayer.playbackState === MprisPlaybackState.Playing
    readonly property bool hasTrack: trackTitle.trim().length > 0

    readonly property real currentPosition: (activePlayer && activePlayer.position) ? activePlayer.position : 0
    readonly property real totalLength: {
        if (!activePlayer || !activePlayer.length) return 0
        return activePlayer.length > 100000 ? (activePlayer.length / 1000000) : activePlayer.length
    }

    property var lines: []
    property bool hasLyrics: lines.length > 0
    property int currentIndex: -1
    property string currentLine: ""
    property string nextLine: ""
    property string prevLine: ""

    onTrackTitleChanged: fetchLyrics()
    onTrackArtistChanged: fetchLyrics()
    onCurrentPositionChanged: updateSync()
    onIsPlayingChanged: updateSync()

    function fetchLyrics() {
        lines = []
        currentIndex = -1
        currentLine = ""
        nextLine = ""
        prevLine = ""
        if (!hasTrack) return

        lyricsProc.command = [
            "python3",
            (Quickshell.env("HOME") || "") + "/.config/hypr/scripts/carbon-lyrics.py",
            "--title", root.trackTitle,
            "--artist", root.trackArtist,
            "--duration", String(root.totalLength)
        ]
        lyricsProc.running = true
    }

    Process {
        id: lyricsProc
        property string buffer: ""

        stdout: SplitParser {
            onRead: (line) => {
                lyricsProc.buffer += line + "\n"
            }
        }

        onRunningChanged: {
            if (running) {
                buffer = ""
            } else {
                if (buffer.trim().length > 0) {
                    try {
                        const res = JSON.parse(buffer)
                        if (res && res.found && Array.isArray(res.lines)) {
                            root.lines = res.lines
                            root.updateSync()
                            console.log("[LyricsService] Loaded " + root.lines.length + " synced lyric lines for:", root.trackTitle)
                        } else {
                            root.lines = []
                        }
                    } catch (e) {
                        root.lines = []
                    }
                }
            }
        }
    }

    /* Poller for position tracking and real-time lyric line resolution */
    Timer {
        interval: 100
        repeat: true
        running: root.isPlaying
        onTriggered: {
            if (root.activePlayer && root.activePlayer.positionSupported) {
                root.activePlayer.positionChanged()
            }
            root.updateSync()
        }
    }

    function updateSync() {
        if (!lines || lines.length === 0) {
            currentIndex = -1
            currentLine = ""
            nextLine = ""
            prevLine = ""
            return
        }

        // Add 250ms lookahead to compensate for MPRIS polling frequency and audio buffer latency
        const pos = root.currentPosition + 0.25

        // Check if we are still in the song intro before singing starts
        if (pos < lines[0].time) {
            currentIndex = -1
            currentLine = ""
            nextLine = lines[0].text
            prevLine = ""
            return
        }

        let idx = -1
        for (let i = 0; i < lines.length; i++) {
            if (lines[i].time <= pos) {
                idx = i
            } else {
                break
            }
        }

        currentIndex = idx
        if (idx >= 0 && idx < lines.length) {
            const lineTime = lines[idx].time
            const nextTime = (idx + 1 < lines.length) ? lines[idx + 1].time : (lineTime + 10.0)
            const elapsed = pos - lineTime

            // If there is an extended instrumental gap (>8s) and the line was sung >6.5s ago, expire line
            if ((nextTime - lineTime > 8.0) && (elapsed > 6.5)) {
                currentLine = ""
            } else {
                currentLine = lines[idx].text
            }
            nextLine = (idx + 1 < lines.length) ? lines[idx + 1].text : ""
            prevLine = (idx - 1 >= 0) ? lines[idx - 1].text : ""
        } else {
            currentIndex = -1
            currentLine = ""
            nextLine = lines.length > 0 ? lines[0].text : ""
            prevLine = ""
        }
    }

    function formatTime(sec) {
        if (!sec || isNaN(sec) || sec < 0) return "0:00"
        const s = Math.floor(sec)
        const m = Math.floor(s / 60)
        const rem = s % 60
        return `${m}:${rem < 10 ? "0" : ""}${rem}`
    }

    function skipNext() {
        const now = Date.now()
        if (now - root.lastSkipTime < 240) return
        root.lastSkipTime = now
        Quickshell.execDetached(["playerctl", "next"])
    }

    function skipPrevious() {
        const now = Date.now()
        if (now - root.lastSkipTime < 240) return
        root.lastSkipTime = now
        Quickshell.execDetached(["playerctl", "previous"])
    }

    function togglePlaying() {
        Quickshell.execDetached(["playerctl", "play-pause"])
    }

    function seekTo(sec) {
        if (root.activePlayer) {
            try { root.activePlayer.position = sec } catch (e) {}
        }
        Quickshell.execDetached(["playerctl", "position", String(Math.floor(sec))])
        if (root.activePlayer && root.activePlayer.positionSupported) {
            root.activePlayer.positionChanged()
        }
    }

    function seekFraction(frac) {
        if (root.totalLength > 0) {
            root.seekTo(Math.max(0, Math.min(1.0, frac)) * root.totalLength)
        }
    }

    Component.onCompleted: {
        fetchLyrics()
    }
}
