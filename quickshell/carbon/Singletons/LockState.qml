pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * LockState.qml
 *
 * Singleton managing screen lock state and Carbon // Verci Mode toggle.
 * Reads verciModeEnabled from ~/.config/hypr/carbon-lockscreen.json and ~/.config/carbon/carbon-lockscreen.json
 */
Singleton {
    id: root

    property bool isLocked: false
    property bool verciModeEnabled: false

    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string configPath: root.home + "/.config/hypr/carbon-lockscreen.json"
    readonly property string carbonConfigPath: (Quickshell.env("CARBON_CONFIG_DIR") || (root.home + "/.config/carbon")) + "/carbon-lockscreen.json"

    FileView {
        id: cfgFile
        path: root.configPath
        watchChanges: true
        blockLoading: true
        printErrors: false
        onFileChanged: root.reloadConfig()
        onLoaded: root.reloadConfig()
    }

    FileView {
        id: cfgCarbonFile
        path: root.carbonConfigPath
        watchChanges: true
        blockLoading: true
        printErrors: false
        onFileChanged: root.reloadConfig()
        onLoaded: root.reloadConfig()
    }

    Timer {
        interval: 1500
        repeat: true
        running: true
        onTriggered: root.reloadConfig()
    }

    function reloadConfig() {
        try {
            var txt = cfgFile.text().trim()
            if (!txt || txt.length === 0) {
                txt = cfgCarbonFile.text().trim()
            }
            if (txt && txt.length > 0) {
                var parsed = JSON.parse(txt)
                if (parsed.verciModeEnabled !== undefined) {
                    var newVal = Boolean(parsed.verciModeEnabled)
                    if (root.verciModeEnabled !== newVal) {
                        root.verciModeEnabled = newVal
                        console.log("[LockState] verciModeEnabled updated to:", root.verciModeEnabled)
                    }
                }
            }
        } catch (e) {
            console.log("[LockState] Error reading config:", e)
        }
    }

    function lock() {
        root.isLocked = true
        console.log("[LockState] Verci lock activated (RAM lazy-load start)")
    }

    function unlock() {
        root.finishUnlock()
    }

    function finishUnlock() {
        root.isLocked = false
        console.log("[LockState] Verci unlocked -> Loader destroyed (0 MB RAM)")
    }

    Component.onCompleted: {
        root.reloadConfig()
    }
}
