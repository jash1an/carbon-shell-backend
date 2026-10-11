pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * LockTransition.qml
 *
 * Singleton that unifies the lock / unlock transition across Carbon desktop
 * shell and WlSessionLock.
 *
 * States:
 *   - "idle": Normal desktop, 0% CPU, 0 timers/animations active
 *   - "locking": Desktop overlay animates 0 -> 1250ms, at t = 780ms WlSessionLock engages
 *   - "locked": Session is fully locked, WlSessionLock is visible and active
 *   - "unlocking": WlSessionLock animates 0 -> 1250ms, unlocks at end
 *
 * Driven by a single continuous time `t` (ms) updated by FrameAnimation.
 */
Item {
    id: root

    // "idle" | "locking" | "locked" | "unlocking"
    property string phase: "idle"
    property real t: 0.0 // in ms

    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string cacheDir: root.home + "/.cache/carbon"
    readonly property string screenshotPath: root.cacheDir + "/lock_screen_snap.jpg"

    signal handoffToSessionLock()
    signal unlockComplete()

    // Single FrameAnimation driving continuous timeline
    FrameAnimation {
        id: timeDriver
        running: root.phase === "locking" || root.phase === "unlocking"
        onTriggered: {
            root.t += frameTime * 1000.0

            if (root.phase === "locking") {
                if (root.t >= 780.0 && !root.handoffTriggered) {
                    root.handoffTriggered = true
                    root.handoffToSessionLock()
                }
                if (root.t >= 1250.0) {
                    root.phase = "locked"
                    root.t = 1250.0
                }
            } else if (root.phase === "unlocking") {
                if (root.t >= 1250.0) {
                    root.phase = "idle"
                    root.t = 0.0
                    root.unlockComplete()
                }
            }
        }
    }

    property bool handoffTriggered: false

    function startLock() {
        if (root.phase === "locking" || root.phase === "locked") return
        root.handoffTriggered = false
        root.t = 0.0
        root.phase = "locking"
        // Capture screen snapshot for single shared blur
        snapProc.command = ["sh", "-c", "grim -t jpeg -q 75 \"" + root.screenshotPath + "\" 2>/dev/null || true"]
        snapProc.running = true
    }

    function startUnlock() {
        if (root.phase === "unlocking" || root.phase === "idle") return
        root.t = 0.0
        root.phase = "unlocking"
    }

    function cancelLock() {
        root.phase = "idle"
        root.t = 0.0
        root.handoffTriggered = false
    }

    Process {
        id: snapProc
        command: []
    }
}
