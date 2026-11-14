import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../Singletons"
import "../components"

Item {
    id: root

    property var hub: null
    function describe(name, desc) { if (hub && hub.describe) hub.describe(name, desc) }
    function clearDesc() { if (hub && hub.clearDescription) hub.clearDescription() }

    implicitWidth: 800
    implicitHeight: 600

    readonly property string wallpaperDir: (Quickshell.env("HOME") || "") + "/Pictures/Wallpapers"
    readonly property string stateFile: (Quickshell.env("CARBON_CONFIG_DIR") || ((Quickshell.env("HOME") || "") + "/.config/carbon")) + "/current_wallpaper_path"
    readonly property string hyprStateFile: (Quickshell.env("HOME") || "") + "/.config/hypr/current_wallpaper_path"
    readonly property string ambientGlowFile: (Quickshell.env("CARBON_CONFIG_DIR") || ((Quickshell.env("HOME") || "") + "/.config/carbon")) + "/ambient_glow_state"
    readonly property string schemeFile: (Quickshell.env("CARBON_CONFIG_DIR") || ((Quickshell.env("HOME") || "") + "/.config/carbon")) + "/carbon-scheme.txt"
    readonly property string blurScript: (Quickshell.env("CARBON_CONFIG_DIR") || ((Quickshell.env("HOME") || "") + "/.config/carbon")) + "/scripts/carbon-blur-apply.py"

    property string currentWallpaperPath: ""
    property var localWallpapers: []
    property string activeScheme: "Tonal Spot"
    property bool liveBgPaused: false

    // Blur Exceptions
    property var blurExceptions: []
    property var allAvailableApps: []
    property string appSearchQuery: ""
    property bool appBrowserOpen: false
    property bool showManualEntry: false
    property string newBlurName: ""
    property string newBlurClass: ""
    property var runningClasses: []

    // Hyprland compositor options
    readonly property string applyScript: (Quickshell.env("CARBON_CONFIG_DIR") || ((Quickshell.env("HOME") || "") + "/.config/carbon")) + "/scripts/carbon-settings-apply.py"
    property real blurRadius: 5
    property real blurPasses: 2
    property real gapsOut: 6
    property real gapsIn: 6
    property real activeOpacity: 1.0
    property real inactiveOpacity: 1.0
    property real borderWidth: 1
    property real rounding: 0
    property real shadowRange: 25
    property string windowLayout: "dwindle"
    property bool windowShadows: true
    property bool ambientGlow: false
    property bool m3Transitions: false

    // Fonts & Typography
    property int ifFontSize: 11
    property int monoFontSize: 11
    property real fontScaling: 1.0

    Process {
        id: lookProc
        command: [root.applyScript, "dump-all"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) {
                var raw = line.trim()
                if (!raw) return
                try {
                    var d = JSON.parse(raw)
                    if (d.looknfeel) {
                        var lnf = d.looknfeel
                        if (lnf.gaps_in !== undefined) root.gapsIn = lnf.gaps_in
                        if (lnf.gaps_out !== undefined) root.gapsOut = lnf.gaps_out
                        if (lnf.rounding !== undefined) root.rounding = lnf.rounding
                        if (lnf.blur_passes !== undefined) root.blurPasses = lnf.blur_passes
                        if (lnf.shadow_range !== undefined) root.shadowRange = lnf.shadow_range
                        if (lnf.layout !== undefined) root.windowLayout = lnf.layout
                    }
                    if (d.fonts) {
                        var f = d.fonts
                        if (f.interface_size !== undefined) root.ifFontSize = parseInt(f.interface_size) || 11
                        if (f.monospace_size !== undefined) root.monoFontSize = parseInt(f.monospace_size) || 11
                        if (f.scaling_factor !== undefined) root.fontScaling = parseFloat(f.scaling_factor) || 1.0
                    }
                } catch(e) {}
            }
        }
    }

    function setLnf(key, val) {
        Quickshell.execDetached([root.applyScript, "set", "looknfeel", key, String(val)])
    }

    function setFont(key, val) {
        Quickshell.execDetached([root.applyScript, "set", "fonts", key, String(val)])
    }

    // -----------------------------------------------------------------------
    // RUST BACKEND IPC SOCKET CLIENT (/tmp/carbon-hub.sock)
    // -----------------------------------------------------------------------
    Socket {
        id: hubSocket
        path: "/tmp/carbon-hub.sock"
        connected: true

        onConnectedChanged: {
            if (connected) {
                root.sendHub({ "module": "appearance", "action": "get_state" })
            }
        }

        parser: SplitParser {
            splitMarker: "\n"
            onRead: function(chunk) {
                var raw = chunk.trim()
                if (!raw) return
                try {
                    var resp = JSON.parse(raw)
                    if (resp && resp.status === "ok" && resp.data) {
                        if (resp.action === "get_state") {
                            var d = resp.data
                            if (d.hypr) {
                                if (d.hypr.blur !== undefined) root.blurRadius = d.hypr.blur
                                if (d.hypr.gaps !== undefined) root.gapsOut = d.hypr.gaps
                                if (d.hypr.active_opacity !== undefined) root.activeOpacity = d.hypr.active_opacity
                                if (d.hypr.inactive_opacity !== undefined) root.inactiveOpacity = d.hypr.inactive_opacity
                                if (d.hypr.border !== undefined) root.borderWidth = d.hypr.border
                                if (d.hypr.shadow !== undefined) root.windowShadows = d.hypr.shadow
                            }
                            if (d.current_wallpaper) {
                                root.currentWallpaperPath = d.current_wallpaper
                            }
                            if (d.wallpapers && Array.isArray(d.wallpapers) && d.wallpapers.length > 0) {
                                root.localWallpapers = d.wallpapers
                            }
                        } else if (resp.action === "set_wallpaper" || resp.action === "shuffle_wallpaper") {
                            if (resp.data && resp.data.path) {
                                root.currentWallpaperPath = resp.data.path
                            }
                        } else if (resp.action === "list_wallpapers") {
                            if (Array.isArray(resp.data)) {
                                root.localWallpapers = resp.data
                            }
                        }
                    }
                } catch (e) {
                    console.log("[AppearanceTab] Socket parse error:", e)
                }
            }
        }
    }

    Timer {
        id: reconnectTimer
        interval: 1500
        repeat: true
        running: !hubSocket.connected
        onTriggered: {
            hubSocket.connected = true
        }
    }

    function sendHub(obj) {
        if (hubSocket.connected) {
            hubSocket.write(JSON.stringify(obj) + "\n")
            hubSocket.flush()
        }
    }

    // Debounce timers for 60fps real-time compositor sliders
    Timer {
        id: blurDebounce
        interval: 16
        repeat: false
        onTriggered: root.sendHub({ "module": "appearance", "action": "set_blur", "value": root.blurRadius })
    }
    function queueBlur(val) {
        root.blurRadius = val
        blurDebounce.restart()
    }

    Timer {
        id: gapsDebounce
        interval: 16
        repeat: false
        onTriggered: root.sendHub({ "module": "appearance", "action": "set_gaps", "value": root.gapsOut })
    }
    function queueGaps(val) {
        root.gapsOut = val
        gapsDebounce.restart()
    }

    Timer {
        id: activeOpacityDebounce
        interval: 16
        repeat: false
        onTriggered: root.sendHub({ "module": "appearance", "action": "set_active_opacity", "value": root.activeOpacity })
    }
    function queueActiveOpacity(val) {
        root.activeOpacity = val
        activeOpacityDebounce.restart()
    }

    Timer {
        id: inactiveOpacityDebounce
        interval: 16
        repeat: false
        onTriggered: root.sendHub({ "module": "appearance", "action": "set_inactive_opacity", "value": root.inactiveOpacity })
    }
    function queueInactiveOpacity(val) {
        root.inactiveOpacity = val
        inactiveOpacityDebounce.restart()
    }

    Timer {
        id: borderDebounce
        interval: 16
        repeat: false
        onTriggered: root.sendHub({ "module": "appearance", "action": "set_border", "value": root.borderWidth })
    }
    function queueBorder(val) {
        root.borderWidth = val
        borderDebounce.restart()
    }

    // FileView for live wallpaper state tracking (fallback/live sync across shell)
    FileView {
        id: wpLinkFile
        path: root.stateFile
        blockLoading: true
        watchChanges: true
        printErrors: false
        onLoaded: {
            var t = wpLinkFile.text().trim()
            if (t) root.currentWallpaperPath = t
        }
        onFileChanged: {
            reload()
            var t = wpLinkFile.text().trim()
            if (t) root.currentWallpaperPath = t
        }
    }

    FileView {
        id: hyprWpLinkFile
        path: root.hyprStateFile
        blockLoading: true
        watchChanges: true
        printErrors: false
        onLoaded: {
            var t = hyprWpLinkFile.text().trim()
            if (t && !root.currentWallpaperPath) root.currentWallpaperPath = t
        }
        onFileChanged: {
            reload()
            var t = hyprWpLinkFile.text().trim()
            if (t) root.currentWallpaperPath = t
        }
    }

    FileView {
        id: glowFile
        path: root.ambientGlowFile
        blockLoading: true
        watchChanges: true
        printErrors: false
        onLoaded: {
            var t = glowFile.text().trim()
            root.ambientGlow = (t === "1")
        }
        onFileChanged: {
            reload()
            var t = glowFile.text().trim()
            root.ambientGlow = (t === "1")
        }
    }

    FileView {
        id: schemeLinkFile
        path: root.schemeFile
        blockLoading: true
        watchChanges: true
        printErrors: false
        onLoaded: {
            var t = schemeLinkFile.text().trim()
            if (t) root.activeScheme = t
        }
        onFileChanged: {
            reload()
            var t = schemeLinkFile.text().trim()
            if (t) root.activeScheme = t
        }
    }

    FileView {
        id: blurJsonFile
        path: (Quickshell.env("CARBON_CONFIG_DIR") || ((Quickshell.env("HOME") || "") + "/.config/carbon")) + "/carbon-blur-exceptions.json"
        blockLoading: true
        watchChanges: true
        printErrors: false
        onLoaded: root.loadBlurExceptions()
        onFileChanged: {
            reload()
            root.loadBlurExceptions()
        }
    }

    function loadBlurExceptions() {
        try {
            var txt = blurJsonFile.text().trim()
            if (txt.length > 0) {
                var d = JSON.parse(txt)
                if (Array.isArray(d)) {
                    root.blurExceptions = d
                }
            }
        } catch (e) {}
    }

    function isException(cls) {
        if (!cls) return false
        var c = cls.toLowerCase()
        for (var i = 0; i < root.blurExceptions.length; i++) {
            var ex = root.blurExceptions[i]
            if (ex && ex.class && ex.class.toLowerCase() === c) return true
        }
        return false
    }

    function loadAvailableApps() {
        if (!availableAppsProc.running) availableAppsProc.running = true
    }

    function addBlurException(name, cls, icon) {
        var n = (name || "").trim()
        var c = (cls || "").trim()
        var ic = (icon || "application-x-executable").trim()
        if (!c) return
        if (!n) n = c.charAt(0).toUpperCase() + c.slice(1)
        Quickshell.execDetached([root.blurScript, "add", n, c, ic])
        root.newBlurName = ""
        root.newBlurClass = ""
        root.appSearchQuery = ""
        root.describe("Blur Exception Added", "Excluded " + n + " (" + c + ") from compositor blur.")
        root.refreshRunningClasses()
        root.loadAvailableApps()
    }

    function removeBlurException(idx) {
        Quickshell.execDetached([root.blurScript, "remove", String(idx)])
        root.refreshRunningClasses()
        root.loadAvailableApps()
    }

    Process {
        id: availableAppsProc
        command: [root.blurScript, "available-apps"]
        stdout: StdioCollector {
            id: availableAppsCollector
            waitForEnd: true
        }
        onExited: {
            try {
                var raw = availableAppsCollector.text.trim()
                if (raw.length > 0) {
                    var data = JSON.parse(raw)
                    if (Array.isArray(data)) {
                        root.allAvailableApps = data
                    }
                }
            } catch(e) {}
        }
    }

    Process {
        id: runningClientsProc
        command: ["bash", "-c", "hyprctl clients -j 2>/dev/null | jq -r '.[].class' 2>/dev/null | sort -u | grep -v '^$' | head -n 8"]
        stdout: StdioCollector {
            id: clientsCollector
            waitForEnd: true
        }
        onExited: {
            var raw = clientsCollector.text.trim()
            if (raw) {
                var lines = raw.split("\n").map(function(s) { return s.trim(); }).filter(function(s) { return s.length > 0; })
                root.runningClasses = lines
            }
        }
    }

    function refreshRunningClasses() {
        if (!runningClientsProc.running) runningClientsProc.running = true
        root.loadAvailableApps()
    }

    Component.onCompleted: {
        root.sendHub({ "module": "appearance", "action": "get_state" })
        root.loadBlurExceptions()
        root.refreshRunningClasses()
        root.loadAvailableApps()
    }

    // -----------------------------------------------------------------------
    // 2-COLUMN ASYMMETRIC SPLIT LAYOUT (Left: Gallery & Colors, Right: Compositor)
    // -----------------------------------------------------------------------
    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ===================================================================
        // LEFT COLUMN: Wallpapers & Matugen Engine (58%)
        // ===================================================================
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredWidth: Theme.px(460)

            Flickable {
                anchors.fill: parent
                contentWidth: width
                contentHeight: leftColContent.implicitHeight + Theme.px(40)
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: leftColContent
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Theme.px(20)
                    spacing: Theme.px(16)

                    // Section Header: Wallpaper Gallery
                    Text {
                        text: "WALLPAPER GALLERY"
                        font.family: Theme.font
                        font.pixelSize: Theme.fontPx(11)
                        font.weight: Font.Bold
                        color: Qt.rgba(1, 1, 1, 0.45)
                    }

                    // Active Hero Wallpaper Preview (radius: Theme.px(10), clip: true, NO text overlay)
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Theme.px(280)
                        radius: Theme.px(10)
                        color: Qt.rgba(0, 0, 0, 0.40)
                        border.color: Qt.rgba(1, 1, 1, 0.12)
                        border.width: 1
                        clip: true

                        Image {
                            id: heroWpImage
                            anchors.fill: parent
                            fillMode: Image.PreserveAspectCrop
                            source: root.currentWallpaperPath ? (root.currentWallpaperPath.startsWith("file://") ? root.currentWallpaperPath : ("file://" + root.currentWallpaperPath)) : ""
                            asynchronous: true
                            smooth: true
                            mipmap: true
                            sourceSize: Qt.size(1920, 1080)
                            cache: true

                            // Subtle loading / fallback placeholder
                            Rectangle {
                                anchors.fill: parent
                                color: Qt.rgba(0, 0, 0, 0.40)
                                visible: heroWpImage.status !== Image.Ready
                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: Theme.px(8)
                                    Text {
                                        text: "󰸉"
                                        font.family: Theme.fontMono
                                        font.pixelSize: Theme.fontPx(22)
                                        color: Qt.rgba(1, 1, 1, 0.35)
                                    }
                                    Text {
                                        text: "Loading Wallpaper Preview..."
                                        font.family: Theme.font
                                        font.pixelSize: Theme.fontPx(12)
                                        color: Qt.rgba(1, 1, 1, 0.45)
                                    }
                                }
                            }
                        }
                    }

                    // Controls Row: [ ⤨ SHUFFLE RANDOM ] + Live BG Pause Badge
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.px(12)

                        // Flush Shuffle Random Button
                        Rectangle {
                            Layout.preferredWidth: shuffleText.implicitWidth + Theme.px(24)
                            Layout.preferredHeight: Theme.px(32)
                            radius: Theme.px(6)
                            color: shuffleMouse.pressed ? Qt.rgba(1, 1, 1, 0.14) : (shuffleMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.04))
                            border.color: Qt.rgba(1, 1, 1, 0.12)
                            border.width: 1

                            Text {
                                id: shuffleText
                                anchors.centerIn: parent
                                text: "⤨  SHUFFLE RANDOM"
                                font.family: Theme.font
                                font.pixelSize: Theme.fontPx(11)
                                font.weight: Font.DemiBold
                                color: Qt.rgba(1, 1, 1, 0.90)
                            }

                            MouseArea {
                                id: shuffleMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: root.describe("Shuffle Wallpaper", "Shuffle and apply a random wallpaper image from ~/Pictures/Wallpapers.")
                                onExited: root.clearDesc()
                                ToolTip.visible: containsMouse
                                ToolTip.text: "Shuffle and apply a random wallpaper image from ~/Pictures/Wallpapers."
                                ToolTip.delay: 300
                                onClicked: root.sendHub({ "module": "appearance", "action": "shuffle_wallpaper" })
                            }
                        }

                        Item { Layout.fillWidth: true }

                        // Live BG Pause Toggle Row
                        RowLayout {
                            spacing: Theme.px(8)
                            Text {
                                text: "Live BG Pause"
                                font.family: Theme.font
                                font.pixelSize: Theme.fontPx(12)
                                color: Qt.rgba(1, 1, 1, 0.70)
                            }

                            TerminalStatusBadge {
                                checked: root.liveBgPaused
                                settingName: "Live BG Pause"
                                description: "Pause animated and video background shaders when on battery to reduce GPU power."
                                onClicked: {
                                    root.liveBgPaused = !root.liveBgPaused
                                    root.sendHub({ "module": "appearance", "action": "pause_live_bg", "value": root.liveBgPaused })
                                }
                            }
                        }
                    }

                    // Horizontal Scrolling Thumbnails Carousel (140x80, radius 8, NO text overlays)
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Theme.px(88)

                        ListView {
                            id: thumbList
                            anchors.fill: parent
                            orientation: ListView.Horizontal
                            spacing: Theme.px(12)
                            clip: true
                            model: root.localWallpapers

                            delegate: Rectangle {
                                width: Theme.px(140)
                                height: Theme.px(80)
                                radius: Theme.px(8)
                                clip: true
                                color: Qt.rgba(0, 0, 0, 0.35)
                                border.color: (modelData.path === root.currentWallpaperPath) ? Theme.primary : (thumbMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.30) : Qt.rgba(1, 1, 1, 0.10))
                                border.width: (modelData.path === root.currentWallpaperPath) ? 2 : 1

                                Image {
                                    anchors.fill: parent
                                    anchors.margins: (modelData.path === root.currentWallpaperPath) ? Theme.px(2) : 0
                                    fillMode: Image.PreserveAspectCrop
                                    source: modelData.thumb ? (modelData.thumb.startsWith("file://") ? modelData.thumb : ("file://" + modelData.thumb)) : (modelData.path ? (modelData.path.startsWith("file://") ? modelData.path : ("file://" + modelData.path)) : "")
                                    asynchronous: true
                                    smooth: true
                                    mipmap: true
                                    sourceSize: Qt.size(280, 160)
                                    cache: true
                                }

                                MouseArea {
                                    id: thumbMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onEntered: root.describe("Wallpaper", "Click to apply " + (modelData.name || "this wallpaper") + " and regenerate system Material 3 colors.")
                                    onExited: root.clearDesc()
                                    ToolTip.visible: containsMouse
                                    ToolTip.text: "Apply " + (modelData.name || "wallpaper")
                                    ToolTip.delay: 300
                                    onClicked: {
                                        root.currentWallpaperPath = modelData.path
                                        root.sendHub({ "module": "appearance", "action": "set_wallpaper", "path": modelData.path })
                                    }
                                }
                            }
                        }
                    }

                    // Section Divider
                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Qt.rgba(1, 1, 1, 0.08)
                    }

                    // =======================================================
                    // MATUGEN COLOR ENGINE
                    // =======================================================
                    Text {
                        text: "Matugen Color Scheme"
                        font.family: Theme.font
                        font.pixelSize: Theme.fontPx(12)
                        font.weight: Font.Medium
                        color: Qt.rgba(1, 1, 1, 0.85)
                    }

                    // 5 Live Circular Color Chips (radius: Theme.px(12), 24px)
                    RowLayout {
                        spacing: Theme.px(14)

                        Repeater {
                            model: [
                                { name: "Primary", col: Theme.primary },
                                { name: "Secondary", col: Theme.secondary },
                                { name: "Tertiary", col: Theme.tertiary },
                                { name: "Surface", col: Theme.surface },
                                { name: "Error", col: Theme.error }
                            ]

                            delegate: ColumnLayout {
                                spacing: Theme.px(4)
                                Layout.alignment: Qt.AlignHCenter

                                Rectangle {
                                    width: Theme.px(24)
                                    height: Theme.px(24)
                                    radius: Theme.px(12)
                                    color: modelData.col
                                    border.color: Qt.rgba(1, 1, 1, 0.20)
                                    border.width: 1

                                    Behavior on color { ColorAnimation { duration: 250 } }
                                }

                                Text {
                                    text: modelData.name
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontPx(9)
                                    color: Qt.rgba(1, 1, 1, 0.40)
                                    Layout.alignment: Qt.AlignHCenter
                                }
                            }
                        }
                    }

                    // Segmented Scheme Selector: Tonal Spot | Expressive | Fidelity | Monochrome
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        Repeater {
                            model: ["Tonal Spot", "Expressive", "Fidelity", "Monochrome"]

                            delegate: Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Theme.px(30)
                                color: (root.activeScheme === modelData) ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15) : (segMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(1, 1, 1, 0.02))
                                border.color: (root.activeScheme === modelData) ? Theme.primary : Qt.rgba(1, 1, 1, 0.08)
                                border.width: 1

                                Text {
                                    anchors.centerIn: parent
                                    text: modelData
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontPx(11)
                                    font.weight: (root.activeScheme === modelData) ? Font.DemiBold : Font.Normal
                                    color: (root.activeScheme === modelData) ? Theme.primary : Qt.rgba(1, 1, 1, 0.65)
                                }

                                MouseArea {
                                    id: segMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    readonly property string schemeDesc: {
                                        if (modelData === "Tonal Spot") return "Balanced Material 3 color scheme with neutral foundations and vivid accents."
                                        if (modelData === "Expressive") return "High-saturation palette pairing bold complementary and analogous hues."
                                        if (modelData === "Fidelity") return "Exact-match palette directly reflecting dominant wallpaper hues."
                                        if (modelData === "Monochrome") return "Grayscale minimal palette derived from wallpaper luminance."
                                        return "Material You algorithmic color scheme strategy."
                                    }
                                    onEntered: root.describe(modelData + " Scheme", schemeDesc)
                                    onExited: root.clearDesc()
                                    ToolTip.visible: containsMouse
                                    ToolTip.text: schemeDesc
                                    ToolTip.delay: 300
                                    onClicked: {
                                        root.activeScheme = modelData
                                        root.sendHub({ "module": "appearance", "action": "set_scheme", "scheme": modelData })
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ===================================================================
        // 1PX VERTICAL HAIRLINE SEPARATOR
        // ===================================================================
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 1
            color: Qt.rgba(1, 1, 1, 0.08)
        }

        // ===================================================================
        // RIGHT COLUMN: Compositor & Window Rules (42%)
        // ===================================================================
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredWidth: Theme.px(340)

            Flickable {
                anchors.fill: parent
                contentWidth: width
                contentHeight: rightColContent.implicitHeight + Theme.px(40)
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: rightColContent
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Theme.px(20)
                    spacing: Theme.px(16)

                    // Section Header: Hyprland Compositor Controls
                    Text {
                        text: "COMPOSITOR & EFFECTS"
                        font.family: Theme.font
                        font.pixelSize: Theme.fontPx(11)
                        font.weight: Font.Bold
                        color: Qt.rgba(1, 1, 1, 0.45)
                    }

                    // Slider 1: Blur Radius
                    RazorWireSlider {
                        Layout.fillWidth: true
                        label: "Blur Radius"
                        description: "Radius of the hardware compositor blur effect applied behind transparent windows."
                        from: 0
                        to: 20
                        stepSize: 1
                        decimals: 0
                        unit: "px"
                        value: root.blurRadius
                        onMoved: (val) => root.queueBlur(val)
                    }

                    // Slider 1b: Blur Passes
                    RazorWireSlider {
                        Layout.fillWidth: true
                        label: "Blur Passes"
                        description: "Number of sequential blur passes. Higher values yield smoother glass blur with higher GPU usage."
                        from: 1
                        to: 5
                        stepSize: 1
                        decimals: 0
                        unit: "pass"
                        value: root.blurPasses
                        onMoved: (val) => {
                            root.blurPasses = val
                            root.setLnf("blur_passes", val)
                        }
                    }

                    // Section Divider & Blur Exceptions Header
                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Qt.rgba(1, 1, 1, 0.08)
                    }

                    RowLayout {
                        Layout.fillWidth: true

                        Text {
                            text: "BLUR EXCEPTIONS (APP EXCLUSIONS)"
                            font.family: Theme.font
                            font.pixelSize: Theme.fontPx(11)
                            font.weight: Font.Bold
                            color: Qt.rgba(1, 1, 1, 0.45)
                            Layout.fillWidth: true
                        }

                        Text {
                            text: root.blurExceptions.length + " rules"
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.fontPx(9.5)
                            color: Theme.primary
                        }
                    }

                    Text {
                        text: "Exclude specific applications (games, video players, browsers) from compositor blur and force full opacity."
                        font.family: Theme.font
                        font.pixelSize: Theme.fontPx(10.5)
                        color: Qt.rgba(1, 1, 1, 0.45)
                        wrapMode: Text.WordWrap
                        Layout.fillWidth: true
                    }

                    // List of Blur Exception Apps
                    Repeater {
                        model: root.blurExceptions

                        delegate: Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Theme.px(44)
                            radius: Theme.px(6)
                            color: Qt.rgba(0, 0, 0, 0.25)
                            border.color: Qt.rgba(1, 1, 1, 0.08)
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.px(10)
                                anchors.rightMargin: Theme.px(10)
                                spacing: Theme.px(8)

                                Text {
                                    text: "󰣆"
                                    font.family: Theme.fontMono
                                    font.pixelSize: Theme.fontPx(14)
                                    color: Theme.primary
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1

                                    Text {
                                        text: modelData.name || "App Exception"
                                        font.family: Theme.font
                                        font.pixelSize: Theme.fontPx(11.5)
                                        font.weight: Font.DemiBold
                                        color: Qt.rgba(1, 1, 1, 0.90)
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        text: "class: " + (modelData.class || "")
                                        font.family: Theme.fontMono
                                        font.pixelSize: Theme.fontPx(9)
                                        color: Qt.rgba(1, 1, 1, 0.40)
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }

                                // Delete exception button
                                Rectangle {
                                    Layout.preferredWidth: Theme.px(24)
                                    Layout.preferredHeight: Theme.px(24)
                                    radius: Theme.px(4)
                                    color: delBlurMouse.containsMouse ? Qt.rgba(1, 0.3, 0.3, 0.15) : "transparent"
                                    border.color: delBlurMouse.containsMouse ? "#ff6b6b" : "transparent"
                                    border.width: 1

                                    Text {
                                        anchors.centerIn: parent
                                        text: "󰅖"
                                        font.family: Theme.fontMono
                                        font.pixelSize: Theme.fontPx(11)
                                        color: delBlurMouse.containsMouse ? "#ff6b6b" : Qt.rgba(1, 1, 1, 0.35)
                                    }

                                    MouseArea {
                                        id: delBlurMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onEntered: root.describe("Remove Exception", "Re-enable compositor blur for " + (modelData.name || modelData.class) + ".")
                                        onExited: root.clearDesc()
                                        ToolTip.visible: containsMouse
                                        ToolTip.text: "Remove exception for " + (modelData.name || modelData.class)
                                        ToolTip.delay: 300
                                        onClicked: root.removeBlurException(index)
                                    }
                                }
                            }
                        }
                    }

                    // Add Exception Card (Search & Exclude Apps)
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: addCardContent.implicitHeight + Theme.px(20)
                        radius: Theme.px(8)
                        color: Qt.rgba(0, 0, 0, 0.35)
                        border.color: Qt.rgba(1, 1, 1, 0.08)
                        border.width: 1
                        clip: true

                        ColumnLayout {
                            id: addCardContent
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: Theme.px(10)
                            spacing: Theme.px(8)

                            // Search bar & Browse button
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.px(6)

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: Theme.px(32)
                                    radius: Theme.px(6)
                                    color: Qt.rgba(0, 0, 0, 0.30)
                                    border.color: appSearchInput.activeFocus ? Theme.primary : Qt.rgba(1, 1, 1, 0.12)
                                    border.width: 1

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: Theme.px(8)
                                        anchors.rightMargin: Theme.px(8)
                                        spacing: Theme.px(6)

                                        Text {
                                            text: "󰍉"
                                            font.family: Theme.fontMono
                                            font.pixelSize: Theme.fontPx(12)
                                            color: appSearchInput.activeFocus ? Theme.primary : Qt.rgba(1, 1, 1, 0.40)
                                        }

                                        TextInput {
                                            id: appSearchInput
                                            Layout.fillWidth: true
                                            font.family: Theme.font
                                            font.pixelSize: Theme.fontPx(11)
                                            color: Qt.rgba(1, 1, 1, 0.95)
                                            selectByMouse: true
                                            text: root.appSearchQuery
                                            onTextChanged: root.appSearchQuery = text

                                            Text {
                                                visible: !appSearchInput.text && !appSearchInput.activeFocus
                                                text: "Search apps to exclude (Steam, LibreWolf, Files)..."
                                                font: appSearchInput.font
                                                color: Qt.rgba(1, 1, 1, 0.30)
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                        }

                                        Rectangle {
                                            visible: root.appSearchQuery.length > 0
                                            Layout.preferredWidth: Theme.px(16)
                                            Layout.preferredHeight: Theme.px(16)
                                            radius: Theme.px(8)
                                            color: Qt.rgba(1, 1, 1, 0.15)
                                            Text {
                                                anchors.centerIn: parent
                                                text: "✕"
                                                font.family: Theme.fontMono
                                                font.pixelSize: Theme.fontPx(8)
                                                color: Qt.rgba(1, 1, 1, 0.70)
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.appSearchQuery = ""
                                            }
                                        }
                                    }
                                }

                                // Browse All Button
                                Rectangle {
                                    Layout.preferredHeight: Theme.px(32)
                                    Layout.preferredWidth: browseBtnTxt.implicitWidth + Theme.px(16)
                                    radius: Theme.px(6)
                                    color: browseBtnMouse.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.20) : Qt.rgba(1, 1, 1, 0.06)
                                    border.color: browseBtnMouse.containsMouse ? Theme.primary : Qt.rgba(1, 1, 1, 0.12)
                                    border.width: 1

                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: Theme.px(4)
                                        Text {
                                            text: "󰀻"
                                            font.family: Theme.fontMono
                                            font.pixelSize: Theme.fontPx(11)
                                            color: Theme.primary
                                        }
                                        Text {
                                            id: browseBtnTxt
                                            text: "Browse All"
                                            font.family: Theme.font
                                            font.pixelSize: Theme.fontPx(10.5)
                                            font.weight: Font.DemiBold
                                            color: Qt.rgba(1, 1, 1, 0.90)
                                        }
                                    }

                                    MouseArea {
                                        id: browseBtnMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onEntered: root.describe("Browse All Applications", "Open the application catalog to browse and search all apps to exclude.")
                                        onExited: root.clearDesc()
                                        onClicked: {
                                            root.appBrowserOpen = true
                                            root.loadAvailableApps()
                                        }
                                    }
                                }
                            }

                            // Instant Filtered Results (when query is entered)
                            ColumnLayout {
                                Layout.fillWidth: true
                                visible: root.appSearchQuery.trim().length > 0
                                spacing: Theme.px(4)

                                Repeater {
                                    model: {
                                        var q = root.appSearchQuery.toLowerCase().trim()
                                        if (!q) return []
                                        var matches = root.allAvailableApps.filter(function(a) {
                                            return (a.name && a.name.toLowerCase().indexOf(q) !== -1) ||
                                                   (a.class && a.class.toLowerCase().indexOf(q) !== -1) ||
                                                   (a.comment && a.comment.toLowerCase().indexOf(q) !== -1) ||
                                                   (a.id && a.id.toLowerCase().indexOf(q) !== -1)
                                        })
                                        return matches.slice(0, 5)
                                    }

                                    delegate: Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: Theme.px(38)
                                        radius: Theme.px(5)
                                        readonly property bool alreadyAdded: root.isException(modelData.class)
                                        color: resMouse.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.15) : Qt.rgba(1, 1, 1, 0.04)
                                        border.color: resMouse.containsMouse ? Theme.primary : Qt.rgba(1, 1, 1, 0.08)
                                        border.width: 1

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: Theme.px(8)
                                            anchors.rightMargin: Theme.px(8)
                                            spacing: Theme.px(8)

                                            Text {
                                                text: "󰣆"
                                                font.family: Theme.fontMono
                                                font.pixelSize: Theme.fontPx(13)
                                                color: alreadyAdded ? Theme.primary : Qt.rgba(1, 1, 1, 0.60)
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 0

                                                RowLayout {
                                                    spacing: Theme.px(6)
                                                    Text {
                                                        text: modelData.name || modelData.class
                                                        font.family: Theme.font
                                                        font.pixelSize: Theme.fontPx(11)
                                                        font.weight: Font.DemiBold
                                                        color: Qt.rgba(1, 1, 1, 0.95)
                                                    }
                                                    Rectangle {
                                                        visible: modelData.isOpen
                                                        Layout.preferredHeight: Theme.px(13)
                                                        Layout.preferredWidth: openTxt.implicitWidth + Theme.px(6)
                                                        radius: Theme.px(3)
                                                        color: Qt.rgba(0.2, 0.8, 0.4, 0.2)
                                                        border.color: "#34d399"
                                                        border.width: 1
                                                        Text {
                                                            id: openTxt
                                                            anchors.centerIn: parent
                                                            text: "RUNNING"
                                                            font.family: Theme.fontMono
                                                            font.pixelSize: Theme.fontPx(7)
                                                            font.bold: true
                                                            color: "#34d399"
                                                        }
                                                    }
                                                }

                                                Text {
                                                    text: "class: " + (modelData.class || "")
                                                    font.family: Theme.fontMono
                                                    font.pixelSize: Theme.fontPx(9)
                                                    color: Qt.rgba(1, 1, 1, 0.40)
                                                    elide: Text.ElideRight
                                                    Layout.fillWidth: true
                                                }
                                            }

                                            Rectangle {
                                                Layout.preferredHeight: Theme.px(22)
                                                Layout.preferredWidth: addBtnTxt.implicitWidth + Theme.px(12)
                                                radius: Theme.px(4)
                                                color: alreadyAdded ? Qt.rgba(1, 1, 1, 0.05) : (resMouse.containsMouse ? Theme.primary : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.85))

                                                Text {
                                                    id: addBtnTxt
                                                    anchors.centerIn: parent
                                                    text: alreadyAdded ? "󰄬 Added" : "+ Add"
                                                    font.family: Theme.font
                                                    font.pixelSize: Theme.fontPx(9.5)
                                                    font.weight: Font.Bold
                                                    color: alreadyAdded ? Qt.rgba(1, 1, 1, 0.40) : "#050508"
                                                }
                                            }
                                        }

                                        MouseArea {
                                            id: resMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: alreadyAdded ? Qt.ArrowCursor : Qt.PointingHandCursor
                                            onClicked: {
                                                if (!alreadyAdded) {
                                                    root.addBlurException(modelData.name, modelData.class, modelData.icon)
                                                }
                                            }
                                        }
                                    }
                                }

                                Text {
                                    visible: {
                                        var q = root.appSearchQuery.toLowerCase().trim()
                                        if (!q) return false
                                        var matches = root.allAvailableApps.filter(function(a) {
                                            return (a.name && a.name.toLowerCase().indexOf(q) !== -1) ||
                                                   (a.class && a.class.toLowerCase().indexOf(q) !== -1) ||
                                                   (a.id && a.id.toLowerCase().indexOf(q) !== -1)
                                        })
                                        return matches.length === 0
                                    }
                                    text: "No applications found. You can enter class manually below."
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontPx(9.5)
                                    color: Qt.rgba(1, 1, 1, 0.40)
                                    Layout.fillWidth: true
                                }
                            }

                            // Quick add chips from open windows (when search is empty)
                            ColumnLayout {
                                id: openSectionCol
                                Layout.fillWidth: true
                                visible: root.appSearchQuery.trim().length === 0 && openAppsList.length > 0
                                spacing: Theme.px(4)

                                readonly property var openAppsList: {
                                    return root.allAvailableApps.filter(function(a) {
                                        return a.isOpen === true && !root.isException(a.class)
                                    })
                                }

                                Text {
                                    text: "Active Windows (Click to exclude):"
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontPx(9.5)
                                    color: Qt.rgba(1, 1, 1, 0.40)
                                }

                                Flow {
                                    Layout.fillWidth: true
                                    spacing: Theme.px(4)

                                    Repeater {
                                        model: openSectionCol.openAppsList

                                        delegate: Rectangle {
                                            height: Theme.px(22)
                                            width: openChipRow.implicitWidth + Theme.px(10)
                                            radius: Theme.px(4)
                                            color: openChipMouse.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.22) : Qt.rgba(1, 1, 1, 0.05)
                                            border.color: openChipMouse.containsMouse ? Theme.primary : Qt.rgba(1, 1, 1, 0.10)
                                            border.width: 1

                                            RowLayout {
                                                id: openChipRow
                                                anchors.centerIn: parent
                                                spacing: Theme.px(5)

                                                Rectangle {
                                                    width: Theme.px(5)
                                                    height: Theme.px(5)
                                                    radius: Theme.px(2.5)
                                                    color: "#34d399"
                                                }

                                                Text {
                                                    text: modelData.name || modelData.class
                                                    font.family: Theme.font
                                                    font.pixelSize: Theme.fontPx(9.5)
                                                    color: openChipMouse.containsMouse ? Theme.primary : Qt.rgba(1, 1, 1, 0.85)
                                                }

                                                Text {
                                                    text: "+"
                                                    font.family: Theme.fontMono
                                                    font.pixelSize: Theme.fontPx(9.5)
                                                    font.bold: true
                                                    color: Theme.primary
                                                }
                                            }

                                            MouseArea {
                                                id: openChipMouse
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onEntered: root.describe("Quick Exclude Window", "Exclude " + (modelData.name || modelData.class) + " (" + modelData.class + ") from compositor blur.")
                                                onExited: root.clearDesc()
                                                onClicked: {
                                                    root.addBlurException(modelData.name, modelData.class, modelData.icon)
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // Manual Entry Expander Toggle
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Theme.px(20)
                                color: "transparent"

                                Text {
                                    anchors.centerIn: parent
                                    text: root.showManualEntry ? "▲ Hide manual window class entry" : "▼ Enter custom window class manually..."
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontPx(9.5)
                                    color: manualToggleMouse.containsMouse ? Theme.primary : Qt.rgba(1, 1, 1, 0.40)
                                }

                                MouseArea {
                                    id: manualToggleMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.showManualEntry = !root.showManualEntry
                                }
                            }

                            // Manual input fields
                            ColumnLayout {
                                Layout.fillWidth: true
                                visible: root.showManualEntry
                                spacing: Theme.px(6)

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Theme.px(6)

                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: Theme.px(28)
                                        radius: Theme.px(4)
                                        color: Qt.rgba(0, 0, 0, 0.30)
                                        border.color: blurNameInput.activeFocus ? Theme.primary : Qt.rgba(1, 1, 1, 0.12)
                                        border.width: 1

                                        TextInput {
                                            id: blurNameInput
                                            anchors.fill: parent
                                            anchors.margins: Theme.px(5)
                                            text: root.newBlurName
                                            onTextChanged: root.newBlurName = text
                                            font.family: Theme.font
                                            font.pixelSize: Theme.fontPx(11)
                                            color: Qt.rgba(1, 1, 1, 0.90)
                                            selectByMouse: true

                                            Text {
                                                visible: !blurNameInput.text && !blurNameInput.activeFocus
                                                text: "App Name"
                                                font: blurNameInput.font
                                                color: Qt.rgba(1, 1, 1, 0.30)
                                            }
                                        }
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: Theme.px(28)
                                        radius: Theme.px(4)
                                        color: Qt.rgba(0, 0, 0, 0.30)
                                        border.color: blurClassInput.activeFocus ? Theme.primary : Qt.rgba(1, 1, 1, 0.12)
                                        border.width: 1

                                        TextInput {
                                            id: blurClassInput
                                            anchors.fill: parent
                                            anchors.margins: Theme.px(5)
                                            text: root.newBlurClass
                                            onTextChanged: root.newBlurClass = text
                                            font.family: Theme.fontMono
                                            font.pixelSize: Theme.fontPx(10.5)
                                            color: Qt.rgba(1, 1, 1, 0.90)
                                            selectByMouse: true

                                            Text {
                                                visible: !blurClassInput.text && !blurClassInput.activeFocus
                                                text: "Window Class"
                                                font: blurClassInput.font
                                                color: Qt.rgba(1, 1, 1, 0.30)
                                            }
                                        }
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: Theme.px(26)
                                    radius: Theme.px(4)
                                    color: addManualMouse.containsMouse ? Theme.primary : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.85)

                                    Text {
                                        anchors.centerIn: parent
                                        text: "+ ADD CUSTOM CLASS"
                                        font.family: Theme.font
                                        font.pixelSize: Theme.fontPx(10)
                                        font.weight: Font.Bold
                                        color: "#050508"
                                    }

                                    MouseArea {
                                        id: addManualMouse
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.addBlurException(root.newBlurName, root.newBlurClass, "application-x-executable")
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Divider after Blur Exceptions
                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Qt.rgba(1, 1, 1, 0.08)
                    }

                    // Slider 2: Gaps Out
                    RazorWireSlider {
                        Layout.fillWidth: true
                        label: "Gaps Out"
                        description: "Outer gap distance (px) between tiled windows and monitor display borders."
                        from: 0
                        to: 32
                        stepSize: 1
                        decimals: 0
                        unit: "px"
                        value: root.gapsOut
                        onMoved: (val) => root.queueGaps(val)
                    }

                    // Slider 2b: Gaps In
                    RazorWireSlider {
                        Layout.fillWidth: true
                        label: "Gaps In"
                        description: "Inner gap distance (px) between adjacent tiled client windows."
                        from: 0
                        to: 32
                        stepSize: 1
                        decimals: 0
                        unit: "px"
                        value: root.gapsIn
                        onMoved: (val) => {
                            root.gapsIn = val
                            root.setLnf("gaps_in", val)
                        }
                    }

                    // Slider 3: Corner Rounding
                    RazorWireSlider {
                        Layout.fillWidth: true
                        label: "Corner Rounding"
                        description: "Border corner radius (px) applied to client window frames and modal popups."
                        from: 0
                        to: 32
                        stepSize: 1
                        decimals: 0
                        unit: "px"
                        value: root.rounding
                        onMoved: (val) => {
                            root.rounding = val
                            root.setLnf("rounding", val)
                        }
                    }

                    // Slider 4: Active Opacity
                    RazorWireSlider {
                        Layout.fillWidth: true
                        label: "Active Opacity"
                        description: "Opacity multiplier for currently focused active window."
                        from: 0.20
                        to: 1.00
                        stepSize: 0.05
                        decimals: 2
                        value: root.activeOpacity
                        onMoved: (val) => root.queueActiveOpacity(val)
                    }

                    // Slider 5: Inactive Opacity
                    RazorWireSlider {
                        Layout.fillWidth: true
                        label: "Inactive Opacity"
                        description: "Opacity multiplier for inactive unfocused windows to indicate focus state."
                        from: 0.20
                        to: 1.00
                        stepSize: 0.05
                        decimals: 2
                        value: root.inactiveOpacity
                        onMoved: (val) => root.queueInactiveOpacity(val)
                    }

                    // Slider 6: Border Width
                    RazorWireSlider {
                        Layout.fillWidth: true
                        label: "Border Width"
                        description: "Outer border outline thickness (px) rendered around client windows."
                        from: 0
                        to: 8
                        stepSize: 1
                        decimals: 0
                        unit: "px"
                        value: root.borderWidth
                        onMoved: (val) => root.queueBorder(val)
                    }

                    // Slider 7: Shadow Range
                    RazorWireSlider {
                        Layout.fillWidth: true
                        label: "Shadow Range"
                        description: "Diffusion distance (px) of drop shadows cast beneath floating and active windows."
                        from: 0
                        to: 50
                        stepSize: 1
                        decimals: 0
                        unit: "px"
                        value: root.shadowRange
                        onMoved: (val) => {
                            root.shadowRange = val
                            root.setLnf("shadow_range", val)
                        }
                    }

                    // Window Layout Mode (Dwindle vs Master)
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.px(8)

                        Text {
                            text: "Tiling Layout"
                            font.family: Theme.font
                            font.pixelSize: Theme.fontPx(13)
                            color: Qt.rgba(1, 1, 1, 0.85)
                            Layout.fillWidth: true
                        }

                        Rectangle {
                            Layout.preferredWidth: Theme.px(80)
                            Layout.preferredHeight: Theme.px(26)
                            radius: Theme.px(4)
                            color: root.windowLayout === "dwindle" ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.20) : Qt.rgba(0, 0, 0, 0.30)
                            border.color: root.windowLayout === "dwindle" ? Theme.primary : Qt.rgba(1, 1, 1, 0.10)
                            Text { anchors.centerIn: parent; text: "Dwindle"; font.family: Theme.font; font.pixelSize: Theme.fontPx(11); color: root.windowLayout === "dwindle" ? Theme.primary : Theme.fgDim }
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: root.describe("Dwindle Layout", "Spiral binary split layout. Each new window halves the available container area.")
                                onExited: root.clearDesc()
                                ToolTip.visible: containsMouse
                                ToolTip.text: "Spiral binary split layout. Each new window halves the container area."
                                ToolTip.delay: 300
                                onClicked: {
                                    root.windowLayout = "dwindle"
                                    root.setLnf("layout", "dwindle")
                                }
                            }
                        }

                        Rectangle {
                            Layout.preferredWidth: Theme.px(80)
                            Layout.preferredHeight: Theme.px(26)
                            radius: Theme.px(4)
                            color: root.windowLayout === "master" ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.20) : Qt.rgba(0, 0, 0, 0.30)
                            border.color: root.windowLayout === "master" ? Theme.primary : Qt.rgba(1, 1, 1, 0.10)
                            Text { anchors.centerIn: parent; text: "Master"; font.family: Theme.font; font.pixelSize: Theme.fontPx(11); color: root.windowLayout === "master" ? Theme.primary : Theme.fgDim }
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: root.describe("Master Layout", "Master-stack layout. One large master window alongside a vertical stack of child windows.")
                                onExited: root.clearDesc()
                                ToolTip.visible: containsMouse
                                ToolTip.text: "Master-stack layout. One master window alongside a vertical stack."
                                ToolTip.delay: 300
                                onClicked: {
                                    root.windowLayout = "master"
                                    root.setLnf("layout", "master")
                                }
                            }
                        }
                    }

                    // Structural Hairline
                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Qt.rgba(1, 1, 1, 0.08)
                    }

                    // Section: Fonts & Typography
                    Text {
                        text: "FONTS & TYPOGRAPHY"
                        font.family: Theme.font
                        font.pixelSize: Theme.fontPx(11)
                        font.weight: Font.Bold
                        color: Qt.rgba(1, 1, 1, 0.45)
                    }

                    RazorWireSlider {
                        Layout.fillWidth: true
                        label: "UI Font Size"
                        description: "Primary interface font size (pt) for labels, titles, and shell menus."
                        from: 8
                        to: 20
                        stepSize: 1
                        decimals: 0
                        unit: "pt"
                        value: root.ifFontSize
                        onMoved: (val) => {
                            root.ifFontSize = val
                            root.setFont("interface_size", val)
                        }
                    }

                    RazorWireSlider {
                        Layout.fillWidth: true
                        label: "Monospace Font Size"
                        description: "Monospace font size (pt) for terminal widgets, clock typography, and code blocks."
                        from: 8
                        to: 20
                        stepSize: 1
                        decimals: 0
                        unit: "pt"
                        value: root.monoFontSize
                        onMoved: (val) => {
                            root.monoFontSize = val
                            root.setFont("monospace_size", val)
                        }
                    }

                    RazorWireSlider {
                        Layout.fillWidth: true
                        label: "Font Scaling"
                        description: "Global typography scale factor across all Carbon desktop elements."
                        from: 0.75
                        to: 1.50
                        stepSize: 0.05
                        decimals: 2
                        unit: "x"
                        value: root.fontScaling
                        onMoved: (val) => {
                            root.fontScaling = val
                            root.setFont("scaling_factor", val)
                        }
                    }

                    // Structural Hairline
                    Rectangle {
                        Layout.fillWidth: true
                        height: 1
                        color: Qt.rgba(1, 1, 1, 0.08)
                    }

                    // Feature Matrix Header
                    Text {
                        text: "FEATURE TOGGLE MATRIX"
                        font.family: Theme.font
                        font.pixelSize: Theme.fontPx(11)
                        font.weight: Font.Bold
                        color: Qt.rgba(1, 1, 1, 0.45)
                    }

                    // Feature 1: Enable Window Shadows
                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: "Enable Window Shadows"
                            font.family: Theme.font
                            font.pixelSize: Theme.fontPx(13)
                            font.weight: Font.Medium
                            color: Qt.rgba(1, 1, 1, 0.85)
                            Layout.fillWidth: true
                        }

                        TerminalStatusBadge {
                            checked: root.windowShadows
                            settingName: "Window Shadows"
                            description: "Enable or disable compositor drop shadows beneath desktop client windows."
                            onClicked: {
                                root.windowShadows = !root.windowShadows
                                root.sendHub({ "module": "appearance", "action": "set_shadow", "value": root.windowShadows })
                            }
                        }
                    }

                    // Feature 2: Ambient Glow (Audio Borders)
                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: "Ambient Glow (Audio Borders)"
                            font.family: Theme.font
                            font.pixelSize: Theme.fontPx(13)
                            font.weight: Font.Medium
                            color: Qt.rgba(1, 1, 1, 0.85)
                            Layout.fillWidth: true
                        }

                        TerminalStatusBadge {
                            checked: root.ambientGlow
                            settingName: "Ambient Glow"
                            description: "Pulsing audio-reactive ambient glow rendered on window borders during media playback."
                            onClicked: {
                                root.ambientGlow = !root.ambientGlow
                                root.sendHub({ "module": "appearance", "action": "set_ambient_glow", "value": root.ambientGlow })
                            }
                        }
                    }

                    // Feature 3: Material-3 Transitions (Dimmed Opacity 0.40 Placeholder)
                    RowLayout {
                        Layout.fillWidth: true
                        opacity: 0.40

                        Text {
                            text: "Material-3 Transitions"
                            font.family: Theme.font
                            font.pixelSize: Theme.fontPx(13)
                            font.weight: Font.Medium
                            color: Qt.rgba(1, 1, 1, 0.85)
                            Layout.fillWidth: true
                        }

                        TerminalStatusBadge {
                            checked: false
                            interactive: false
                            settingName: "Material-3 Transitions"
                            description: "Material You animated surface transitions across shell components."
                        }
                    }
                }
            }
        }
    }

    // =======================================================================
    // APPLICATION BROWSER MODAL (SEARCH & SELECT APPS FOR BLUR EXCEPTION)
    // =======================================================================
    Rectangle {
        id: blurAppModalOverlay
        anchors.fill: parent
        visible: root.appBrowserOpen
        color: Qt.rgba(0, 0, 0, 0.75)
        z: 999

        MouseArea {
            anchors.fill: parent
            onClicked: root.appBrowserOpen = false
        }

        Rectangle {
            id: modalDialogBox
            anchors.centerIn: parent
            width: Math.min(parent.width - Theme.px(40), Theme.px(640))
            height: Math.min(parent.height - Theme.px(40), Theme.px(540))
            radius: Theme.px(12)
            color: "#121316"
            border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.35)
            border.width: 1
            clip: true

            MouseArea {
                anchors.fill: parent
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.px(16)
                spacing: Theme.px(12)

                // Dialog Header
                RowLayout {
                    Layout.fillWidth: true

                    Text {
                        text: "󰣆"
                        font.family: Theme.fontMono
                        font.pixelSize: Theme.fontPx(20)
                        color: Theme.primary
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Theme.px(2)

                        Text {
                            text: "Add Application to Blur Exceptions"
                            font.family: Theme.font
                            font.pixelSize: Theme.fontPx(14)
                            font.weight: Font.Bold
                            color: Qt.rgba(1, 1, 1, 0.95)
                        }

                        Text {
                            text: "Search or browse installed applications and active windows to exclude from blur."
                            font.family: Theme.font
                            font.pixelSize: Theme.fontPx(10.5)
                            color: Qt.rgba(1, 1, 1, 0.45)
                        }
                    }

                    // Close button
                    Rectangle {
                        Layout.preferredWidth: Theme.px(28)
                        Layout.preferredHeight: Theme.px(28)
                        radius: Theme.px(6)
                        color: closeModalMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : "transparent"
                        border.color: closeModalMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.20) : "transparent"
                        border.width: 1

                        Text {
                            anchors.centerIn: parent
                            text: "✕"
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.fontPx(13)
                            color: Qt.rgba(1, 1, 1, 0.70)
                        }

                        MouseArea {
                            id: closeModalMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.appBrowserOpen = false
                        }
                    }
                }

                // 1px Hairline
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: Qt.rgba(1, 1, 1, 0.08)
                }

                // Search Bar inside Modal
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.px(38)
                    radius: Theme.px(8)
                    color: Qt.rgba(0, 0, 0, 0.35)
                    border.color: modalSearchInput.activeFocus ? Theme.primary : Qt.rgba(1, 1, 1, 0.12)
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.px(12)
                        anchors.rightMargin: Theme.px(12)
                        spacing: Theme.px(10)

                        Text {
                            text: "󰍉"
                            font.family: Theme.fontMono
                            font.pixelSize: Theme.fontPx(13)
                            color: modalSearchInput.activeFocus ? Theme.primary : Qt.rgba(1, 1, 1, 0.40)
                        }

                        TextInput {
                            id: modalSearchInput
                            Layout.fillWidth: true
                            font.family: Theme.font
                            font.pixelSize: Theme.fontPx(12)
                            color: Qt.rgba(1, 1, 1, 0.95)
                            selectByMouse: true
                            text: root.appSearchQuery
                            onTextChanged: root.appSearchQuery = text

                            Text {
                                visible: !modalSearchInput.text && !modalSearchInput.activeFocus
                                text: "Search by application name, category, or window class..."
                                font: modalSearchInput.font
                                color: Qt.rgba(1, 1, 1, 0.30)
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        Rectangle {
                            visible: root.appSearchQuery.length > 0
                            Layout.preferredWidth: Theme.px(20)
                            Layout.preferredHeight: Theme.px(20)
                            radius: Theme.px(10)
                            color: Qt.rgba(1, 1, 1, 0.12)

                            Text {
                                anchors.centerIn: parent
                                text: "✕"
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fontPx(9)
                                color: Qt.rgba(1, 1, 1, 0.60)
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.appSearchQuery = ""
                            }
                        }
                    }
                }

                // Scrollable List of Apps
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Theme.px(8)
                    color: Qt.rgba(0, 0, 0, 0.20)
                    border.color: Qt.rgba(1, 1, 1, 0.06)
                    border.width: 1
                    clip: true

                    ListView {
                        id: modalListView
                        anchors.fill: parent
                        anchors.margins: Theme.px(6)
                        spacing: Theme.px(4)
                        boundsBehavior: Flickable.StopAtBounds

                        model: {
                            var q = root.appSearchQuery.toLowerCase().trim()
                            if (!q) return root.allAvailableApps
                            return root.allAvailableApps.filter(function(a) {
                                return (a.name && a.name.toLowerCase().indexOf(q) !== -1) ||
                                       (a.class && a.class.toLowerCase().indexOf(q) !== -1) ||
                                       (a.comment && a.comment.toLowerCase().indexOf(q) !== -1) ||
                                       (a.id && a.id.toLowerCase().indexOf(q) !== -1)
                            })
                        }

                        delegate: Rectangle {
                            width: modalListView.width
                            height: Theme.px(48)
                            radius: Theme.px(6)
                            readonly property bool isExc: root.isException(modelData.class)
                            color: isExc ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.12) : (modalItemMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent")
                            border.color: isExc ? Theme.primary : (modalItemMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : "transparent")
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Theme.px(12)
                                anchors.rightMargin: Theme.px(12)
                                spacing: Theme.px(12)

                                // Icon box
                                Rectangle {
                                    Layout.preferredWidth: Theme.px(30)
                                    Layout.preferredHeight: Theme.px(30)
                                    radius: Theme.px(6)
                                    color: Qt.rgba(1, 1, 1, 0.06)
                                    border.color: Qt.rgba(1, 1, 1, 0.10)
                                    border.width: 1

                                    Text {
                                        anchors.centerIn: parent
                                        text: "󰣆"
                                        font.family: Theme.fontMono
                                        font.pixelSize: Theme.fontPx(14)
                                        color: isExc ? Theme.primary : Qt.rgba(1, 1, 1, 0.70)
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: Theme.px(1)

                                    RowLayout {
                                        spacing: Theme.px(6)
                                        Text {
                                            text: modelData.name || modelData.class
                                            font.family: Theme.font
                                            font.pixelSize: Theme.fontPx(12)
                                            font.weight: isExc ? Font.DemiBold : Font.Normal
                                            color: isExc ? Qt.rgba(1, 1, 1, 0.98) : Qt.rgba(1, 1, 1, 0.85)
                                        }

                                        Rectangle {
                                            visible: modelData.isOpen
                                            Layout.preferredHeight: Theme.px(14)
                                            Layout.preferredWidth: modalOpenTxt.implicitWidth + Theme.px(8)
                                            radius: Theme.px(3)
                                            color: Qt.rgba(0.2, 0.8, 0.4, 0.2)
                                            border.color: "#34d399"
                                            border.width: 1
                                            Text {
                                                id: modalOpenTxt
                                                anchors.centerIn: parent
                                                text: "RUNNING"
                                                font.family: Theme.fontMono
                                                font.pixelSize: Theme.fontPx(7.5)
                                                font.bold: true
                                                color: "#34d399"
                                            }
                                        }
                                    }

                                    Text {
                                        text: "class: " + (modelData.class || "") + (modelData.comment ? "  •  " + modelData.comment : "")
                                        font.family: Theme.fontMono
                                        font.pixelSize: Theme.fontPx(9.5)
                                        color: Qt.rgba(1, 1, 1, 0.35)
                                        elide: Text.ElideRight
                                        Layout.fillWidth: true
                                    }
                                }

                                // Status or Action badge
                                Rectangle {
                                    visible: isExc
                                    Layout.preferredHeight: Theme.px(24)
                                    Layout.preferredWidth: excBadgeTxt.implicitWidth + Theme.px(14)
                                    radius: Theme.px(4)
                                    color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.18)
                                    border.color: Theme.primary
                                    border.width: 1

                                    RowLayout {
                                        anchors.centerIn: parent
                                        spacing: Theme.px(4)
                                        Text { text: "󰄬"; font.family: Theme.fontMono; font.pixelSize: Theme.fontPx(9); color: Theme.primary }
                                        Text { id: excBadgeTxt; text: "EXCLUDED"; font.family: Theme.font; font.pixelSize: Theme.fontPx(9); font.weight: Font.Bold; color: Theme.primary }
                                    }
                                }

                                Rectangle {
                                    visible: !isExc && modalItemMouse.containsMouse
                                    Layout.preferredHeight: Theme.px(24)
                                    Layout.preferredWidth: addExcTxt.implicitWidth + Theme.px(16)
                                    radius: Theme.px(4)
                                    color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.20)
                                    border.color: Theme.primary
                                    border.width: 1

                                    Text {
                                        id: addExcTxt
                                        anchors.centerIn: parent
                                        text: "+ Exclude"
                                        font.family: Theme.font
                                        font.pixelSize: Theme.fontPx(10)
                                        font.weight: Font.Bold
                                        color: Theme.primary
                                    }
                                }
                            }

                            MouseArea {
                                id: modalItemMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: isExc ? Qt.ArrowCursor : Qt.PointingHandCursor
                                onClicked: {
                                    if (!isExc) {
                                        root.addBlurException(modelData.name, modelData.class, modelData.icon)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
