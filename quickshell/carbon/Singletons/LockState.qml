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
    property bool cairoModeEnabled: false
    property alias verciModeEnabled: root.cairoModeEnabled

    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string configPath: root.home + "/.config/hypr/carbon-lockscreen.json"
    readonly property string carbonConfigPath: (Quickshell.env("CARBON_CONFIG_DIR") || (root.home + "/.config/carbon")) + "/carbon-lockscreen.json"

    FileView {
        id: cfgFile
        path: root.configPath
        watchChanges: true
        blockLoading: true
        printErrors: false
        onFileChanged: {
            cfgFile.reload()
            root.reloadConfig()
        }
        onLoaded: root.reloadConfig()
    }

    FileView {
        id: cfgCarbonFile
        path: root.carbonConfigPath
        watchChanges: true
        blockLoading: true
        printErrors: false
        onFileChanged: {
            cfgCarbonFile.reload()
            root.reloadConfig()
        }
        onLoaded: root.reloadConfig()
    }

    Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: {
            cfgFile.reload()
            cfgCarbonFile.reload()
            root.reloadConfig()
        }
    }

    function parseVal(txt) {
        if (!txt || txt.length === 0) return undefined
        try {
            var parsed = JSON.parse(txt)
            if (parsed.cairoModeEnabled !== undefined) {
                return Boolean(parsed.cairoModeEnabled)
            } else if (parsed.verciModeEnabled !== undefined) {
                return Boolean(parsed.verciModeEnabled)
            }
        } catch (e) {}
        return undefined
    }

    function reloadConfig() {
        try {
            var vCarbon = parseVal(cfgCarbonFile.text().trim())
            var vHypr = parseVal(cfgFile.text().trim())
            var finalVal = undefined
            if (vCarbon !== undefined) {
                finalVal = vCarbon
            } else if (vHypr !== undefined) {
                finalVal = vHypr
            }
            if (finalVal !== undefined && root.cairoModeEnabled !== finalVal) {
                root.cairoModeEnabled = finalVal
                console.log("[LockState] cairoModeEnabled updated to:", root.cairoModeEnabled)
            }
        } catch (e) {
            console.log("[LockState] Error reading config:", e)
        }
    }

    function lock() {
        root.isLocked = true
        console.log("[LockState] Cairo lock activated (RAM lazy-load start)")
    }

    function unlock() {
        root.finishUnlock()
    }

    function finishUnlock() {
        root.isLocked = false
        console.log("[LockState] Cairo unlocked -> Loader destroyed (0 MB RAM)")
    }

    Component.onCompleted: {
        cfgFile.reload()
        cfgCarbonFile.reload()
        root.reloadConfig()
    }
}
