pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * LockTransition.qml
 *
 * Singleton that unifies the lock / unlock transition across Carbon desktop
 * shell and WlSessionLock into ONE continuous shared timeline.
 */
Item {
    id: root

    // "idle" | "locking" | "locked" | "unlocking" | "post_unlock"
    property string phase: "idle"
    property real t: 0.0 // lock timeline in ms (0 -> 1250)
    property real u: 0.0 // unlock timeline in ms (0 -> 1250)

    // Configuration
    property bool lockSync: true
    property real durationScale: 1.0
    property bool reducedMotion: false
    property bool isSystemLock: false

    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string cacheDir: root.home + "/.cache/carbon"
    readonly property string screenshotPath: root.cacheDir + "/lock_screen_snap.jpg"
    readonly property string configPath: root.home + "/.config/hypr/carbon-lockscreen.json"

    signal handoffToSessionLock()
    signal unlockComplete()

    property bool handoffTriggered: false
    property bool unlockHandoffTriggered: false

    FileView {
        id: cfgFile
        path: root.configPath
        watchChanges: true
        onFileChanged: root.reloadConfig()
        onLoaded: root.reloadConfig()
    }

    function reloadConfig() {
        try {
            const txt = cfgFile.text().trim()
            if (txt.length > 0) {
                const parsed = JSON.parse(txt)
                if (parsed.transition) {
                    if (parsed.transition.lockSync !== undefined)
                        root.lockSync = Boolean(parsed.transition.lockSync)
                    if (parsed.transition.durationScale !== undefined)
                        root.durationScale = Math.max(0.1, Number(parsed.transition.durationScale) || 1.0)
                    if (parsed.transition.reducedMotion !== undefined)
                        root.reducedMotion = Boolean(parsed.transition.reducedMotion)
                }
            }
        } catch (e) {
            console.log("[LockTransition] Error loading config:", e)
        }
    }

    Component.onCompleted: {
        root.reloadConfig()
    }

    // Slower, graceful timeline parameters: no rushing, silky smooth delivery
    readonly property real lockPreRollDuration: 1400.0 // Pre-roll before WlSessionLock handoff (was 780ms)
    readonly property real lockTotalDuration: 1800.0   // Total lock settling timeline (was 1250ms)
    readonly property real unlockHandoffTime: 1100.0  // Sharp front reaches full screen before unlock handoff (was 900ms)
    readonly property real unlockTotalDuration: 1400.0 // Desktop restore timeline (was 1250ms)

    property bool screenshotReady: false

    // Single FrameAnimation driving continuous timeline
    FrameAnimation {
        id: timeDriver
        running: root.phase === "locking" || root.phase === "unlocking" || root.phase === "post_unlock"
        onTriggered: {
            var dt = (frameTime * 1000.0) / Math.max(0.1, root.durationScale)

            if (root.phase === "locking") {
                root.t += dt

                if (root.t >= root.lockPreRollDuration && !root.handoffTriggered) {
                    root.handoffTriggered = true
                    root.handoffToSessionLock()
                }

                if (root.t >= root.lockTotalDuration) {
                    root.t = root.lockTotalDuration
                    root.phase = "locked"
                }
            } else if (root.phase === "unlocking") {
                root.u += dt

                if (root.u >= root.unlockHandoffTime && !root.unlockHandoffTriggered) {
                    root.unlockHandoffTriggered = true
                    root.phase = "post_unlock"
                    root.unlockComplete()
                }
            } else if (root.phase === "post_unlock") {
                root.u += dt

                if (root.u >= root.unlockTotalDuration) {
                    root.phase = "idle"
                    root.t = 0.0
                    root.u = 0.0
                }
            }
        }
    }

    function startLock(isSystem) {
        if (root.phase === "locking" || root.phase === "locked") return

        if (!root.lockSync) {
            root.phase = "locked"
            root.t = root.lockTotalDuration
            root.handoffToSessionLock()
            return
        }

        if (isSystem) {
            root.isSystemLock = true
            root.handoffTriggered = true
            root.t = root.lockPreRollDuration
            root.phase = "locked"
            root.handoffToSessionLock()
            return
        }

        root.isSystemLock = false
        root.handoffTriggered = false
        root.unlockHandoffTriggered = false
        root.screenshotReady = false
        root.t = 0.0
        root.u = 0.0
        root.phase = "locking"

        snapProc.command = ["sh", "-c", "grim -t jpeg -q 85 \"" + root.screenshotPath + "\" 2>/dev/null || true"]
        snapProc.running = true
    }

    function startUnlock() {
        if (root.phase === "unlocking" || root.phase === "idle" || root.phase === "post_unlock") return

        if (!root.lockSync) {
            root.phase = "idle"
            root.t = 0.0
            root.u = 0.0
            root.unlockComplete()
            return
        }

        root.u = 0.0
        root.unlockHandoffTriggered = false
        root.phase = "unlocking"
    }

    function cancelLock() {
        root.phase = "idle"
        root.t = 0.0
        root.u = 0.0
        root.handoffTriggered = false
        root.unlockHandoffTriggered = false
    }

    function testLock() {
        startLock(false)
    }

    function testUnlock() {
        startUnlock()
    }

    function failSafeLock() {
        root.phase = "locked"
        root.t = root.lockTotalDuration
        root.handoffToSessionLock()
    }

    Process {
        id: snapProc
        command: []
        onExited: {
            root.screenshotReady = true
        }
    }
}
