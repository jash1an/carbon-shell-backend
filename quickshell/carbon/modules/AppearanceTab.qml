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

    function addBlurException(name, cls) {
        var n = (name || "").trim()
        var c = (cls || "").trim()
        if (!c) return
        if (!n) n = c.charAt(0).toUpperCase() + c.slice(1)
        Quickshell.execDetached([root.blurScript, "add", n, c])
        root.newBlurName = ""
        root.newBlurClass = ""
    }

    function removeBlurException(idx) {
        Quickshell.execDetached([root.blurScript, "remove", String(idx)])
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
    }

    Component.onCompleted: {
        root.sendHub({ "module": "appearance", "action": "get_state" })
        root.loadBlurExceptions()
        root.refreshRunningClasses()
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

                    // Add Exception Card
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Theme.px(108)
                        radius: Theme.px(8)
                        color: Qt.rgba(0, 0, 0, 0.35)
                        border.color: Qt.rgba(1, 1, 1, 0.08)
                        border.width: 1

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: Theme.px(10)
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

                            // Quick add chips from running apps (if any)
                            RowLayout {
                                Layout.fillWidth: true
                                visible: root.runningClasses.length > 0
                                spacing: Theme.px(4)

                                Text {
                                    text: "Open:"
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontPx(9)
                                    color: Qt.rgba(1, 1, 1, 0.30)
                                }

                                Repeater {
                                    model: root.runningClasses.slice(0, 4)

                                    delegate: Rectangle {
                                        Layout.preferredHeight: Theme.px(18)
                                        Layout.preferredWidth: chipText.implicitWidth + Theme.px(8)
                                        radius: Theme.px(3)
                                        color: chipMouse.containsMouse ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.20) : Qt.rgba(1, 1, 1, 0.05)
                                        border.color: Qt.rgba(1, 1, 1, 0.10)

                                        Text {
                                            id: chipText
                                            anchors.centerIn: parent
                                            text: modelData
                                            font.family: Theme.fontMono
                                            font.pixelSize: Theme.fontPx(9)
                                            color: chipMouse.containsMouse ? Theme.primary : Qt.rgba(1, 1, 1, 0.60)
                                        }

                                        MouseArea {
                                            id: chipMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.newBlurClass = modelData
                                                root.newBlurName = modelData.charAt(0).toUpperCase() + modelData.slice(1)
                                            }
                                        }
                                    }
                                }
                            }

                            // Submit Button
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Theme.px(26)
                                radius: Theme.px(4)
                                color: addBlurMouse.containsMouse ? Theme.primary : Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.85)

                                Text {
                                    anchors.centerIn: parent
                                    text: "+ ADD BLUR EXCEPTION"
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontPx(10)
                                    font.weight: Font.Bold
                                    color: "#050508"
                                }

                                MouseArea {
                                    id: addBlurMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onEntered: root.describe("Add Exception", "Disable blur and enforce 100% opacity for this window class.")
                                    onExited: root.clearDesc()
                                    onClicked: {
                                        root.addBlurException(root.newBlurName, root.newBlurClass)
                                        root.refreshRunningClasses()
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
}
