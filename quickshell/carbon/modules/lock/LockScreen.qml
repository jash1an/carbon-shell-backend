import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../Singletons"

/**
 * LockScreen:
 * Wraps Quickshell WlSessionLock protocol.
 */
Scope {
    id: root

    property alias locked: sessionLock.locked
    property var notificationServer: null

    function lock() {
        if (LockTransition.phase === "idle") {
            LockTransition.startLock(false)
        } else if (LockTransition.phase === "locking") {
            // Transition is actively animating desktop pre-roll, do not interrupt!
            return
        } else {
            sessionLock.locked = true
        }
    }

    function unlock() {
        LockTransition.startUnlock()
    }

    Connections {
        target: LockTransition
        function onHandoffToSessionLock() {
            sessionLock.locked = true
        }
        function onUnlockComplete() {
            sessionLock.locked = false
        }
    }

    signal testNotifRequested()
    signal testNotifCenterRequested()
    signal testNotifClearRequested()

    function testNotif() {
        root.testNotifRequested()
    }

    function testNotifCenter() {
        root.testNotifCenterRequested()
    }

    function testNotifClear() {
        root.testNotifClearRequested()
    }

    WlSessionLock {
        id: sessionLock

        LockSurface {
            id: surf
            notificationServer: root.notificationServer

            onRequestUnlock: {
                console.log("[LockScreen] Received onRequestUnlock -> unlocking session lock")
                sessionLock.locked = false
            }

            Connections {
                target: root
                function onTestNotifRequested() { surf.testNotif() }
                function onTestNotifCenterRequested() { surf.testNotifCenter() }
                function onTestNotifClearRequested() { surf.testNotifClear() }
            }
        }
    }
}
