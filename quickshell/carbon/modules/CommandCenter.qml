import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../Singletons"
import "../components"

/**
 * CommandCenter:
 * Sleek, modern bottom-up Notch Command Center for Carbon Shell.
 *
 * Sits anchored to the bottom with organic Material Design 3 / Caelestia styling:
 *   - Row 1: Obsidian Notes Tile (Left) + Events / Schedule Tile (Right)
 *   - Row 2: Recent Apps Tile (Compact Dock with icons only, dynamic length) + Clipboard History Tile (Right)
 *
 * Uses Theme.font ("Plus Jakarta Sans") and Theme.fontIcon ("Material Symbols Rounded")
 * to match Carbon Shell perfectly.
 */
PanelWindow {
    id: commandCenterWindow

    property bool isOpen: false
    property bool animatingOut: false
    signal closeRequested()

    WlrLayershell.namespace: "carbon-command-center"
    WlrLayershell.layer: WlrLayer.Top
    aboveWindows: true
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    anchors {
        bottom: true
        left: true
        right: true
    }
    implicitHeight: Theme.px(390)

    // Only visible when open or during slide-out animation to completely prevent blocking clicks/scrolls
    visible: isOpen || animatingOut
    WlrLayershell.keyboardFocus: (isOpen && !animatingOut) ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    onIsOpenChanged: {
        if (!isOpen) {
            animatingOut = true
            closeAnimTimer.restart()
        } else {
            animatingOut = false
            closeAnimTimer.stop()
            commandCenterWindow.refreshWeather()
            escHandler.forceActiveFocus()
        }
    }

    Timer {
        id: closeAnimTimer
        interval: 340
        onTriggered: {
            commandCenterWindow.animatingOut = false
        }
    }

    // System Clock for aesthetic time display
    SystemClock {
        id: sysClock
        precision: SystemClock.Seconds
    }
    property bool use24h: false

    // Weather state
    property string weatherTemp: "22°C"
    property string weatherDesc: "Clear Sky"
    property string weatherCity: "Patna"

    FileView {
        id: weatherCacheWatcher
        path: "/tmp/carbon-weather-cache.json"
        watchChanges: true
        printErrors: false
        onFileChanged: weatherCacheWatcher.reload()
        onLoaded: {
            try {
                const raw = weatherCacheWatcher.text().trim()
                if (raw) {
                    const d = JSON.parse(raw)
                    if (d.temp) commandCenterWindow.weatherTemp = d.temp
                    if (d.description) commandCenterWindow.weatherDesc = d.description
                    if (d.city) commandCenterWindow.weatherCity = d.city
                }
            } catch (e) {}
        }
    }

    Process {
        id: weatherFetcherProc
        command: [
            "sh", "-c",
            "if [ -f \"$HOME/.local/share/quickshell/carbon/scripts/carbon-weather.py\" ]; then python3 \"$HOME/.local/share/quickshell/carbon/scripts/carbon-weather.py\"; elif [ -f \"/home/shogun/carbon-shell/hypr/scripts/carbon-weather.py\" ]; then python3 \"/home/shogun/carbon-shell/hypr/scripts/carbon-weather.py\"; fi"
        ]
        running: false
        stdout: StdioCollector {
            waitForEnd: true
            onTextChanged: {
                if (text && text.trim().length > 0) {
                    try {
                        var d = JSON.parse(text.trim())
                        if (d) {
                            if (d.temp) commandCenterWindow.weatherTemp = d.temp
                            if (d.condition) commandCenterWindow.weatherDesc = d.condition
                            else if (d.description) commandCenterWindow.weatherDesc = d.description
                            if (d.city) {
                                var c = d.city.split(",")[0].trim()
                                commandCenterWindow.weatherCity = c
                            }
                        }
                    } catch (e) {}
                }
            }
        }
    }

    function refreshWeather() {
        if (!weatherFetcherProc.running) {
            weatherFetcherProc.running = true
        }
        weatherCacheWatcher.reload()
    }

    function resolveWeatherIcon(desc) {
        if (!desc) return "wb_sunny"
        var d = desc.toLowerCase()
        if (d.indexOf("rain") !== -1 || d.indexOf("drizzle") !== -1) return "rainy"
        if (d.indexOf("thunder") !== -1 || d.indexOf("storm") !== -1) return "thunderstorm"
        if (d.indexOf("snow") !== -1 || d.indexOf("ice") !== -1) return "ac_unit"
        if (d.indexOf("fog") !== -1 || d.indexOf("haze") !== -1 || d.indexOf("mist") !== -1 || d.indexOf("smoke") !== -1) return "foggy"
        if (d.indexOf("partly") !== -1 || d.indexOf("scattered") !== -1) return "partly_cloudy_day"
        if (d.indexOf("cloud") !== -1 || d.indexOf("overcast") !== -1) return "cloud"
        if (d.indexOf("clear") !== -1 || d.indexOf("sun") !== -1) return "wb_sunny"
        return "wb_sunny"
    }

    // Data models populated by carbon-radar-engine
    property var vaultItems: []
    property var clipboardItems: []
    property var appsItems: []
    property var agendaItems: []
    property bool engineConnected: false
    property string feedbackMessage: ""

    Timer {
        id: feedbackClearTimer
        interval: 2000
        onTriggered: commandCenterWindow.feedbackMessage = ""
    }

    function showFeedback(msg) {
        commandCenterWindow.feedbackMessage = msg
        feedbackClearTimer.restart()
    }

    // ── Engine Subprocess Pipe ──
    Process {
        id: radarEngineProc
        command: [
            "sh", "-c",
            "if command -v carbon-radar-engine >/dev/null 2>&1; then exec carbon-radar-engine; elif [ -x \"$HOME/.local/bin/carbon-radar-engine\" ]; then exec \"$HOME/.local/bin/carbon-radar-engine\"; elif [ -x \"/home/shogun/carbon-shell/apps/carbon-radar/target/release/carbon-radar-engine\" ]; then exec \"/home/shogun/carbon-shell/apps/carbon-radar/target/release/carbon-radar-engine\"; else exec carbon-radar-engine; fi"
        ]
        running: true
        stdinEnabled: true

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) {
                var raw = (line || "").trim()
                if (!raw) return
                try {
                    var payload = JSON.parse(raw)
                    if (!payload) return
                    if (payload.vault !== undefined) commandCenterWindow.vaultItems = payload.vault
                    if (payload.clipboard !== undefined) commandCenterWindow.clipboardItems = payload.clipboard
                    if (payload.apps !== undefined) commandCenterWindow.appsItems = payload.apps
                    if (payload.agenda !== undefined) commandCenterWindow.agendaItems = payload.agenda
                    commandCenterWindow.engineConnected = true
                } catch(e) {}
            }
        }
    }

    // Shell runner process for one-off actions
    Process {
        id: actionRunner
    }

    function execCommand(cmd) {
        actionRunner.command = ["sh", "-c", cmd]
        actionRunner.running = true
    }

    function openNote(notePath) {
        if (!notePath) return
        execCommand("xdg-open " + JSON.stringify(notePath) + " 2>/dev/null || true")
        showFeedback("Opening note")
    }

    function copyClipboard(clipId) {
        if (!clipId) return
        execCommand("echo -n " + JSON.stringify(clipId) + " | cliphist decode | wl-copy 2>/dev/null || true")
        showFeedback("Copied to clipboard")
    }

    function focusApp(appClass) {
        if (!appClass) return
        var c = appClass.replace(/"/g, '\\"')
        var cmd = 'if hyprctl dispatch focuswindow "class:' + c + '" 2>/dev/null; then exit 0; fi; ' +
                  'res=$(hyprctl repl \'for _, w in ipairs(hl.get_windows()) do if string.find(string.lower(w.class), string.lower("' + c + '"), 1, true) then hl.dispatch(hl.dsp.focus{ window = w }) return "ok" end end; return "not_found"\' 2>/dev/null); ' +
                  'if [ "$res" != "ok" ]; then gtk-launch ' + c + ' 2>/dev/null || hyprctl dispatch exec ' + c + ' 2>/dev/null || true; fi'
        execCommand(cmd)
        showFeedback("Focused: " + appClass)
    }

    function triggerManualRefresh() {
        if (radarEngineProc.running) {
            radarEngineProc.write("refresh\n")
        }
        commandCenterWindow.refreshWeather()
    }

    function resolveAppIcon(cls) {
        if (!cls) return ""
        var raw = cls.trim()
        var c = raw.toLowerCase()

        // 1. Obsidian special handling
        if (c.indexOf("obsidian") !== -1) {
            var o = Quickshell.iconPath("obsidian", "") || Quickshell.iconPath("md.obsidian.Obsidian", "")
            if (o) return o
            return "file:///home/shogun/.local/share/icons/hicolor/scalable/apps/obsidian.svg"
        }

        // 2. Direct well-known application mappings
        if (c === "antigravity") {
            return Quickshell.iconPath("antigravity", "")
        }
        if (c === "cz.viceverse.serein" || c === "serein") {
            return Quickshell.iconPath("serein", "")
        }

        // 3. Resolve using DesktopEntries if available
        if (typeof DesktopEntries !== "undefined" && DesktopEntries && DesktopEntries.applications) {
            var apps = DesktopEntries.applications.values || []
            var parts = c.split(".")
            var lastSegment = parts[parts.length - 1]

            // By startupWmClass
            for (var i = 0; i < apps.length; i++) {
                var a = apps[i]
                if (a && a.startupWmClass && a.startupWmClass.toLowerCase() === c) {
                    if (a.icon) {
                        if (a.icon.startsWith("/")) return "file://" + a.icon
                        return Quickshell.iconPath(a.icon.toLowerCase(), "")
                    }
                }
            }

            // By app ID
            for (var i = 0; i < apps.length; i++) {
                var a = apps[i]
                var aid = (a && a.id ? a.id : "").toLowerCase()
                if (aid === c || aid === c + ".desktop" || aid === lastSegment || aid === lastSegment + ".desktop") {
                    if (a.icon) {
                        if (a.icon.startsWith("/")) return "file://" + a.icon
                        return Quickshell.iconPath(a.icon.toLowerCase(), "")
                    }
                }
            }
        }

        // 4. Reverse DNS stripping (e.g. org.mozilla.firefox -> firefox)
        var parts = c.split(".")
        var last = parts[parts.length - 1]
        if (last && last.length > 0 && last !== c) {
            return Quickshell.iconPath(last, "")
        }

        // 5. Default lowercase
        return Quickshell.iconPath(c, "application-x-executable")
    }

    // Scrim overlay to dismiss on outside click (only active when open)
    MouseArea {
        anchors.fill: parent
        enabled: commandCenterWindow.isOpen
        onClicked: commandCenterWindow.closeRequested()
    }

    // ── Main Compact Floating Card ──
    Rectangle {
        id: mainPanel
        focus: true
        Keys.onEscapePressed: function(event) {
            commandCenterWindow.closeRequested()
            if (event) event.accepted = true
        }
        width: Math.min(Theme.px(640), parent.width - Theme.px(32))
        height: Theme.px(360)
        anchors.horizontalCenter: parent.horizontalCenter

        // Slide-up animation
        y: (commandCenterWindow.isOpen && !commandCenterWindow.animatingOut) ? Theme.px(16) : commandCenterWindow.implicitHeight

        Behavior on y {
            NumberAnimation {
                duration: 320
                easing.type: Easing.OutExpo
            }
        }

        // Carbon Shell Modern Frosted Glass Aesthetic
        color: Theme.isDark ? Qt.rgba(0.06, 0.07, 0.09, 0.90) : Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.90)
        border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.16)
        border.width: 1
        radius: Theme.px(16)
        clip: true

        // Absorb clicks inside card so they don't dismiss
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            preventStealing: true
            onClicked: {}
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.px(12)
            spacing: Theme.px(8)

            // ── Minimal Sleek Header ──
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.px(24)
                Layout.maximumHeight: Theme.px(24)
                spacing: Theme.px(8)

                CarbonLogoIcon {
                    width: Theme.px(18)
                    height: Theme.px(18)
                    Layout.alignment: Qt.AlignVCenter
                    color: commandCenterWindow.engineConnected ? Theme.accent : Theme.fgDim
                }

                Text {
                    text: "View Point"
                    Layout.alignment: Qt.AlignVCenter
                    font.family: Theme.font
                    font.pixelSize: Theme.fontPx(12)
                    font.weight: Font.DemiBold
                    color: Theme.fg
                }

                Item { Layout.fillWidth: true }

                // Action Feedback Badge
                Rectangle {
                    visible: commandCenterWindow.feedbackMessage !== ""
                    Layout.preferredHeight: Theme.px(20)
                    Layout.preferredWidth: fbText.implicitWidth + Theme.px(14)
                    radius: Theme.px(10)
                    color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.15)
                    border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.3)
                    border.width: 1

                    Text {
                        id: fbText
                        anchors.centerIn: parent
                        text: commandCenterWindow.feedbackMessage
                        font.family: Theme.font
                        font.pixelSize: Theme.fontPx(10)
                        font.weight: Font.Medium
                        color: Theme.accent
                    }
                }

                // Refresh Button
                Rectangle {
                    width: Theme.px(24)
                    height: Theme.px(24)
                    radius: Theme.px(12)
                    color: rHover.hovered ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.08) : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "refresh"
                        font.family: Theme.fontIcon
                        font.pixelSize: Theme.fontPx(14)
                        color: rHover.hovered ? Theme.accent : Theme.fgDim
                    }

                    HoverHandler { id: rHover }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: commandCenterWindow.triggerManualRefresh()
                    }
                }

                // Close Button
                Rectangle {
                    width: Theme.px(24)
                    height: Theme.px(24)
                    radius: Theme.px(12)
                    color: cBtnHover.hovered ? Qt.rgba(Theme.error.r, Theme.error.g, Theme.error.b, 0.15) : "transparent"

                    Text {
                        anchors.centerIn: parent
                        text: "close"
                        font.family: Theme.fontIcon
                        font.pixelSize: Theme.fontPx(14)
                        color: cBtnHover.hovered ? Theme.error : Theme.fgDim
                    }

                    HoverHandler { id: cBtnHover }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: commandCenterWindow.closeRequested()
                    }
                }
            }

            // ── ROW 1: Obsidian Notes (Left) + Events / Schedule (Right) ──
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.px(144)
                Layout.maximumHeight: Theme.px(144)
                spacing: Theme.px(8)

                // ══════════════════════════════════════════════════
                // TILE 1: OBSIDIAN NOTES
                // ══════════════════════════════════════════════════
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.035) : Qt.rgba(0, 0, 0, 0.03)
                    border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.12)
                    border.width: 1
                    radius: Theme.px(12)
                    clip: true

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.px(10)
                        spacing: Theme.px(6)

                        // Tile Header
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.px(6)

                            Image {
                                Layout.preferredWidth: Theme.px(16)
                                Layout.preferredHeight: Theme.px(16)
                                Layout.alignment: Qt.AlignVCenter
                                source: commandCenterWindow.resolveAppIcon("obsidian")
                                sourceSize: Qt.size(32, 32)
                                fillMode: Image.PreserveAspectFit
                            }

                            Text {
                                text: "Obsidian Notes"
                                Layout.alignment: Qt.AlignVCenter
                                font.family: Theme.font
                                font.pixelSize: Theme.fontPx(11)
                                font.weight: Font.DemiBold
                                color: Theme.fg
                            }

                            Item { Layout.fillWidth: true }

                            Rectangle {
                                Layout.preferredHeight: Theme.px(16)
                                Layout.preferredWidth: vCountText.implicitWidth + Theme.px(10)
                                radius: Theme.px(8)
                                color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.06)

                                Text {
                                    id: vCountText
                                    anchors.centerIn: parent
                                    text: commandCenterWindow.vaultItems.length
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontPx(9)
                                    font.weight: Font.Bold
                                    color: Theme.fgDim
                                }
                            }
                        }

                        // Notes ListView
                        ListView {
                            id: vaultListView
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            model: commandCenterWindow.vaultItems
                            spacing: Theme.px(2)

                            property bool scrollInitialized: false
                            Component.onCompleted: scrollInitialized = true
                            onContentYChanged: if (scrollInitialized) vaultScrollTimer.restart()

                            Timer {
                                id: vaultScrollTimer
                                interval: 700
                                running: false
                            }

                            ScrollBar.vertical: ScrollBar {
                                id: vaultScroll
                                policy: ScrollBar.AsNeeded
                                contentItem: Rectangle {
                                    implicitWidth: Theme.px(3)
                                    radius: Theme.px(2)
                                    color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.4)
                                    opacity: (vaultScroll.active || vaultScrollTimer.running) ? 1.0 : 0.0
                                    Behavior on opacity { NumberAnimation { duration: 200 } }
                                }
                            }

                            delegate: Item {
                                width: vaultListView.width
                                height: Theme.px(28)

                                HoverHandler { id: noteHover }

                                Rectangle {
                                    anchors.fill: parent
                                    radius: Theme.px(6)
                                    color: noteHover.hovered ? (Theme.isDark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(0, 0, 0, 0.06)) : "transparent"

                                    Behavior on color { ColorAnimation { duration: 120 } }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: Theme.px(6)
                                        anchors.rightMargin: Theme.px(6)
                                        spacing: Theme.px(8)

                                        Text {
                                            text: "draft"
                                            font.family: Theme.fontIcon
                                            font.pixelSize: Theme.fontPx(13)
                                            color: noteHover.hovered ? Theme.accent : Theme.fgDim
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.name
                                            elide: Text.ElideRight
                                            font.family: Theme.font
                                            font.pixelSize: Theme.fontPx(11)
                                            font.weight: noteHover.hovered ? Font.Medium : Font.Normal
                                            color: noteHover.hovered ? Theme.accentLit : Theme.fg
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: commandCenterWindow.openNote(modelData.path)
                                    }
                                }
                            }
                        }
                    }
                }

                // ══════════════════════════════════════════════════
                // TILE 2: EVENTS / SCHEDULE (Beside Obsidian Notes)
                // ══════════════════════════════════════════════════
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.035) : Qt.rgba(0, 0, 0, 0.03)
                    border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.12)
                    border.width: 1
                    radius: Theme.px(12)
                    clip: true

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.px(10)
                        spacing: Theme.px(6)

                        // Tile Header
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.px(6)

                            Text {
                                text: "calendar_today"
                                font.family: Theme.fontIcon
                                font.pixelSize: Theme.fontPx(14)
                                color: Theme.accent
                            }

                            Text {
                                text: "Events & Agenda"
                                font.family: Theme.font
                                font.pixelSize: Theme.fontPx(11)
                                font.weight: Font.DemiBold
                                color: Theme.fg
                            }

                            Item { Layout.fillWidth: true }

                            Rectangle {
                                Layout.preferredHeight: Theme.px(16)
                                Layout.preferredWidth: aCountText.implicitWidth + Theme.px(10)
                                radius: Theme.px(8)
                                color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.06)

                                Text {
                                    id: aCountText
                                    anchors.centerIn: parent
                                    text: commandCenterWindow.agendaItems.length
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontPx(9)
                                    font.weight: Font.Bold
                                    color: Theme.fgDim
                                }
                            }
                        }

                        // Agenda ListView
                        ListView {
                            id: agendaListView
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            model: commandCenterWindow.agendaItems
                            spacing: Theme.px(2)

                            property bool scrollInitialized: false
                            Component.onCompleted: scrollInitialized = true
                            onContentYChanged: if (scrollInitialized) agendaScrollTimer.restart()

                            Timer {
                                id: agendaScrollTimer
                                interval: 700
                                running: false
                            }

                            ScrollBar.vertical: ScrollBar {
                                id: agendaScroll
                                policy: ScrollBar.AsNeeded
                                contentItem: Rectangle {
                                    implicitWidth: Theme.px(3)
                                    radius: Theme.px(2)
                                    color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.4)
                                    opacity: (agendaScroll.active || agendaScrollTimer.running) ? 1.0 : 0.0
                                    Behavior on opacity { NumberAnimation { duration: 200 } }
                                }
                            }

                            delegate: Item {
                                width: agendaListView.width
                                height: Theme.px(28)

                                HoverHandler { id: aHover }

                                Rectangle {
                                    anchors.fill: parent
                                    radius: Theme.px(6)
                                    color: aHover.hovered ? (Theme.isDark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(0, 0, 0, 0.06)) : "transparent"

                                    Behavior on color { ColorAnimation { duration: 120 } }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: Theme.px(6)
                                        anchors.rightMargin: Theme.px(6)
                                        spacing: Theme.px(8)

                                        // Date Pill
                                        Rectangle {
                                            Layout.preferredHeight: Theme.px(18)
                                            Layout.preferredWidth: dText.implicitWidth + Theme.px(10)
                                            radius: Theme.px(4)
                                            color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18)
                                            border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.40)
                                            border.width: 1

                                            Text {
                                                id: dText
                                                anchors.centerIn: parent
                                                text: modelData.date
                                                font.family: Theme.font
                                                font.pixelSize: Theme.fontPx(9)
                                                font.weight: Font.Bold
                                                color: Theme.accent
                                            }
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.title
                                            elide: Text.ElideRight
                                            font.family: Theme.font
                                            font.pixelSize: Theme.fontPx(11)
                                            color: aHover.hovered ? Theme.fg : Theme.fgDim
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── ROW 2: Recent Apps Tile (Left, Compact Landscape Dock) + Clipboard Tile (Right) ──
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: Theme.px(144)
                Layout.maximumHeight: Theme.px(144)
                spacing: Theme.px(8)

                // ══════════════════════════════════════════════════
                // TILE 3: RECENT APPS & AESTHETIC CLOCK + WEATHER
                // ══════════════════════════════════════════════════
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: (parent.width - Theme.px(8)) / 2

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: Theme.px(6)

                        // ── Top: Dynamic Recent Apps Landscape Dock ──
                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Theme.px(42)
                            Layout.maximumHeight: Theme.px(42)

                            Rectangle {
                                anchors.top: parent.top
                                anchors.left: parent.left
                                height: Theme.px(42)
                                // Length dynamically hugs only the active apps (up to 5 max)
                                width: Math.max(Theme.px(42), commandCenterWindow.appsItems.length * Theme.px(34) + (commandCenterWindow.appsItems.length > 0 ? (commandCenterWindow.appsItems.length - 1) * Theme.px(4) : 0) + Theme.px(12))

                                color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.035) : Qt.rgba(0, 0, 0, 0.03)
                                border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.12)
                                border.width: 1
                                radius: Theme.px(10)
                                clip: true

                                Row {
                                    anchors.centerIn: parent
                                    spacing: Theme.px(4)

                                    Repeater {
                                        model: commandCenterWindow.appsItems

                                        delegate: Item {
                                            width: Theme.px(30)
                                            height: Theme.px(30)

                                            HoverHandler { id: appHover }

                                            Rectangle {
                                                id: iconBg
                                                anchors.centerIn: parent
                                                width: Theme.px(26)
                                                height: Theme.px(26)
                                                radius: Theme.px(6)
                                                color: appHover.hovered ? (Theme.isDark ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(0, 0, 0, 0.08)) : "transparent"
                                                scale: appHover.hovered ? 1.15 : 1.0

                                                Behavior on scale {
                                                    NumberAnimation { duration: 150; easing.type: Easing.OutQuad }
                                                }
                                                Behavior on color {
                                                    ColorAnimation { duration: 120 }
                                                }

                                                Image {
                                                    id: appImg
                                                    anchors.centerIn: parent
                                                    width: Theme.px(18)
                                                    height: Theme.px(18)
                                                    source: commandCenterWindow.resolveAppIcon(modelData)
                                                    sourceSize: Qt.size(36, 36)
                                                    fillMode: Image.PreserveAspectFit
                                                    visible: status === Image.Ready
                                                }

                                                Text {
                                                    anchors.centerIn: parent
                                                    visible: appImg.status !== Image.Ready
                                                    text: "apps"
                                                    font.family: Theme.fontIcon
                                                    font.pixelSize: Theme.fontPx(16)
                                                    color: appHover.hovered ? Theme.accent : Theme.fgDim
                                                }

                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: commandCenterWindow.focusApp(modelData)
                                                }
                                            }
                                        }
                                    }
                                }

                                // Placeholder icon if no active apps detected
                                Text {
                                    anchors.centerIn: parent
                                    visible: commandCenterWindow.appsItems.length === 0
                                    text: "apps"
                                    font.family: Theme.fontIcon
                                    font.pixelSize: Theme.fontPx(16)
                                    color: Theme.fgDim
                                }
                            }
                        }

                        // ── Bottom: Aesthetic Floating Clock & Weather (Transparent, not in a tile) ──
                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: Theme.px(4)
                                spacing: Theme.px(6)

                                // Clock Section (Left)
                                Item {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true

                                    HoverHandler { id: clockHover }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            commandCenterWindow.use24h = !commandCenterWindow.use24h
                                            commandCenterWindow.showFeedback(commandCenterWindow.use24h ? "24-Hour Clock" : "12-Hour Clock")
                                        }
                                    }

                                    ColumnLayout {
                                        anchors.centerIn: parent
                                        spacing: Theme.px(2)

                                        RowLayout {
                                            Layout.alignment: Qt.AlignHCenter
                                            spacing: Theme.px(4)

                                            Text {
                                                text: Qt.formatDateTime(sysClock.date, commandCenterWindow.use24h ? "HH:mm" : "hh:mm")
                                                font.family: Theme.font
                                                font.pixelSize: Theme.fontPx(22)
                                                font.weight: Font.Bold
                                                color: clockHover.hovered ? Theme.accent : Theme.fg
                                                Behavior on color { ColorAnimation { duration: 120 } }
                                            }

                                            Rectangle {
                                                visible: !commandCenterWindow.use24h
                                                Layout.preferredHeight: Theme.px(16)
                                                Layout.preferredWidth: amPmText.implicitWidth + Theme.px(8)
                                                Layout.alignment: Qt.AlignVCenter
                                                radius: Theme.px(4)
                                                color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18)
                                                border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.40)
                                                border.width: 1

                                                Text {
                                                    id: amPmText
                                                    anchors.centerIn: parent
                                                    text: Qt.formatDateTime(sysClock.date, "AP")
                                                    font.family: Theme.font
                                                    font.pixelSize: Theme.fontPx(9)
                                                    font.weight: Font.Bold
                                                    color: Theme.accent
                                                }
                                            }
                                        }

                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            text: Qt.formatDateTime(sysClock.date, "dddd, MMM d")
                                            font.family: Theme.font
                                            font.pixelSize: Theme.fontPx(10)
                                            font.weight: Font.Medium
                                            color: Theme.fgDim
                                        }
                                    }
                                }

                                // Subtle Hairline Divider
                                Rectangle {
                                    Layout.preferredWidth: 1
                                    Layout.preferredHeight: Theme.px(34)
                                    Layout.alignment: Qt.AlignVCenter
                                    color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.15)
                                }

                                // Weather Section (Right)
                                Item {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true

                                    HoverHandler { id: weatherHover }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            commandCenterWindow.refreshWeather()
                                            commandCenterWindow.showFeedback("Refreshing Weather...")
                                        }
                                    }

                                    ColumnLayout {
                                        anchors.centerIn: parent
                                        spacing: Theme.px(2)

                                        RowLayout {
                                            Layout.alignment: Qt.AlignHCenter
                                            spacing: Theme.px(6)

                                            Text {
                                                text: commandCenterWindow.resolveWeatherIcon(commandCenterWindow.weatherDesc)
                                                font.family: Theme.fontIcon
                                                font.pixelSize: Theme.fontPx(20)
                                                color: Theme.accent
                                            }

                                            Text {
                                                text: commandCenterWindow.weatherTemp !== "" ? commandCenterWindow.weatherTemp : "--"
                                                font.family: Theme.font
                                                font.pixelSize: Theme.fontPx(18)
                                                font.weight: Font.Bold
                                                color: weatherHover.hovered ? Theme.accent : Theme.fg
                                                Behavior on color { ColorAnimation { duration: 120 } }
                                            }
                                        }

                                        RowLayout {
                                            Layout.alignment: Qt.AlignHCenter
                                            spacing: Theme.px(4)

                                            Text {
                                                text: commandCenterWindow.weatherDesc || "Clear Sky"
                                                font.family: Theme.font
                                                font.pixelSize: Theme.fontPx(10)
                                                font.weight: Font.Medium
                                                color: Theme.fgDim
                                                elide: Text.ElideRight
                                                Layout.maximumWidth: Theme.px(70)
                                            }

                                            Text {
                                                text: "•"
                                                font.family: Theme.font
                                                font.pixelSize: Theme.fontPx(9)
                                                color: Qt.rgba(Theme.fgDim.r, Theme.fgDim.g, Theme.fgDim.b, 0.4)
                                                visible: commandCenterWindow.weatherCity !== ""
                                            }

                                            Text {
                                                text: commandCenterWindow.weatherCity
                                                font.family: Theme.font
                                                font.pixelSize: Theme.fontPx(9)
                                                font.weight: Font.Normal
                                                color: Theme.fgDim
                                                elide: Text.ElideRight
                                                visible: commandCenterWindow.weatherCity !== ""
                                                Layout.maximumWidth: Theme.px(45)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ══════════════════════════════════════════════════
                // TILE 4: CLIPBOARD HISTORY (Beside Recent Apps)
                // ══════════════════════════════════════════════════
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: (parent.width - Theme.px(8)) / 2
                    color: Theme.isDark ? Qt.rgba(1, 1, 1, 0.035) : Qt.rgba(0, 0, 0, 0.03)
                    border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.12)
                    border.width: 1
                    radius: Theme.px(12)
                    clip: true

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Theme.px(10)
                        spacing: Theme.px(6)

                        // Tile Header
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.px(6)

                            Text {
                                text: "content_paste"
                                font.family: Theme.fontIcon
                                font.pixelSize: Theme.fontPx(14)
                                color: Theme.accent
                            }

                            Text {
                                text: "Clipboard Buffer"
                                font.family: Theme.font
                                font.pixelSize: Theme.fontPx(11)
                                font.weight: Font.DemiBold
                                color: Theme.fg
                            }

                            Item { Layout.fillWidth: true }

                            Rectangle {
                                Layout.preferredHeight: Theme.px(16)
                                Layout.preferredWidth: cCountText.implicitWidth + Theme.px(10)
                                radius: Theme.px(8)
                                color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.06)

                                Text {
                                    id: cCountText
                                    anchors.centerIn: parent
                                    text: commandCenterWindow.clipboardItems.length
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontPx(9)
                                    font.weight: Font.Bold
                                    color: Theme.fgDim
                                }
                            }
                        }

                        // Clipboard ListView
                        ListView {
                            id: clipListView
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            model: commandCenterWindow.clipboardItems
                            spacing: Theme.px(2)

                            property bool scrollInitialized: false
                            Component.onCompleted: scrollInitialized = true
                            onContentYChanged: if (scrollInitialized) clipScrollTimer.restart()

                            Timer {
                                id: clipScrollTimer
                                interval: 700
                                running: false
                            }

                            ScrollBar.vertical: ScrollBar {
                                id: clipScroll
                                policy: ScrollBar.AsNeeded
                                contentItem: Rectangle {
                                    implicitWidth: Theme.px(3)
                                    radius: Theme.px(2)
                                    color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.4)
                                    opacity: (clipScroll.active || clipScrollTimer.running) ? 1.0 : 0.0
                                    Behavior on opacity { NumberAnimation { duration: 200 } }
                                }
                            }

                            delegate: Item {
                                width: clipListView.width
                                height: Theme.px(28)

                                HoverHandler { id: clipHover }

                                Rectangle {
                                    anchors.fill: parent
                                    radius: Theme.px(6)
                                    color: clipHover.hovered ? (Theme.isDark ? Qt.rgba(1, 1, 1, 0.07) : Qt.rgba(0, 0, 0, 0.06)) : "transparent"

                                    Behavior on color { ColorAnimation { duration: 120 } }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: Theme.px(6)
                                        anchors.rightMargin: Theme.px(6)
                                        spacing: Theme.px(8)

                                        Text {
                                            text: "content_copy"
                                            font.family: Theme.fontIcon
                                            font.pixelSize: Theme.fontPx(13)
                                            color: clipHover.hovered ? Theme.accent : Theme.fgDim
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.preview
                                            elide: Text.ElideRight
                                            font.family: Theme.font
                                            font.pixelSize: Theme.fontPx(11)
                                            color: clipHover.hovered ? Theme.fg : Theme.fgDim
                                        }

                                        Text {
                                            visible: clipHover.hovered
                                            text: "Copy"
                                            font.family: Theme.font
                                            font.pixelSize: Theme.fontPx(9)
                                            font.weight: Font.Bold
                                            color: Theme.accent
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: commandCenterWindow.copyClipboard(modelData.id)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // Keyboard listener for Escape key to dismiss
    Item {
        id: escHandler
        focus: true
        Keys.onEscapePressed: function(event) {
            commandCenterWindow.closeRequested()
            if (event) event.accepted = true
        }
    }
}
