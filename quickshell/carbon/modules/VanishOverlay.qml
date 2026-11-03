import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import ".."
import "../Singletons"

PanelWindow {
    id: vanishOverlayWindow

    // Anchor purely to the bottom edge, spanning full width
    anchors {
        bottom: true
        left: true
        right: true
    }
    implicitHeight: 120
    color: "transparent"

    // Wayland layer configuration: overlay above windows, never shrink screen
    WlrLayershell.namespace: "carbon-vanish-overlay"
    WlrLayershell.layer: WlrLayer.Top
    aboveWindows: true
    exclusionMode: ExclusionMode.Ignore

    mask: Region {
        item: (vanishOverlayWindow.isOpen || vanishOverlayWindow.animatingOut) ? overlayCard : null
    }

    // Dynamic Sliding & Fade Animation Engine
    property real panelY: 120
    property real panelOpacity: 0.0
    property bool animatingOut: false
    readonly property bool isOpen: GlobalState.isVanishMode && GlobalState.isVanishOverlayOpen

    visible: GlobalState.isVanishMode && (isOpen || animatingOut)
    onVisibleChanged: console.log("[VanishOverlay] visible:", visible, "isVanishMode:", GlobalState.isVanishMode, "isVanishOverlayOpen:", GlobalState.isVanishOverlayOpen)

    // ── Live System Clock Engine ──
    SystemClock {
        id: sysClock
        precision: SystemClock.Seconds
    }

    property bool use24h: false
    property string weatherTemp: "--"
    property string weatherDesc: "Clear Sky"
    property string weatherCity: ""
    property string weatherFeels: ""
    property string weatherIconName: "wb_sunny"
    property bool weatherRefreshing: false

    FileView {
        id: weatherCacheFile
        path: (Quickshell.env("HOME") || "") + "/.cache/quickshell/weather.json"
        watchChanges: true
        blockLoading: false
        printErrors: false
        onLoaded: vanishOverlayWindow.parseWeatherCache(weatherCacheFile.text())
        onFileChanged: vanishOverlayWindow.parseWeatherCache(weatherCacheFile.text())
    }

    Process {
        id: weatherFetcherProc
        command: [
            "sh", "-c",
            "if [ -f \"$HOME/.config/carbon/scripts/carbon-weather.py\" ]; then python3 \"$HOME/.config/carbon/scripts/carbon-weather.py\"; elif [ -f \"$HOME/.local/share/quickshell/carbon/scripts/carbon-weather.py\" ]; then python3 \"$HOME/.local/share/quickshell/carbon/scripts/carbon-weather.py\"; fi"
        ]
        running: false
        stdout: StdioCollector {
            waitForEnd: true
            onTextChanged: {
                if (text && text.trim().length > 0) {
                    vanishOverlayWindow.parseWeatherOutput(text.trim())
                }
            }
        }
        onExited: function(code) {
            vanishOverlayWindow.weatherRefreshing = false
        }
    }

    function refreshWeather() {
        if (!weatherFetcherProc.running) {
            weatherRefreshing = true
            weatherFetcherProc.running = true
        }
        weatherCacheFile.reload()
    }

    function parseWeatherOutput(raw) {
        try {
            var d = JSON.parse(raw)
            if (d.temp) weatherTemp = d.temp
            if (d.condition) weatherDesc = d.condition
            if (d.city) weatherCity = d.city.split(",")[0].trim()
            if (d.humidity) weatherFeels = d.humidity + " hum"
            weatherIconName = resolveWeatherIcon(weatherDesc)
        } catch(e) {}
    }

    function parseWeatherCache(raw) {
        if (!raw || weatherTemp !== "--") return
        try {
            var d = JSON.parse(raw)
            if (d.data && d.data.current_condition && d.data.current_condition.length > 0) {
                var cur = d.data.current_condition[0]
                if (cur.temp_C) weatherTemp = cur.temp_C + "°C"
                if (cur.weatherDesc && cur.weatherDesc.length > 0) weatherDesc = cur.weatherDesc[0].value
                if (d.location) weatherCity = d.location
                if (cur.FeelsLikeC) weatherFeels = "Feels " + cur.FeelsLikeC + "°C"
                weatherIconName = resolveWeatherIcon(weatherDesc)
            }
        } catch(e) {}
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

    Component.onCompleted: {
        refreshWeather()
    }

    onIsOpenChanged: {
        if (isOpen) {
            animatingOut = false
            slideAnim.stop()
            slideAnim.from = panelY
            slideAnim.to = 0
            slideAnim.easing.type = Easing.OutCubic
            slideAnim.duration = 280
            slideAnim.restart()

            fadeAnim.stop()
            fadeAnim.from = panelOpacity
            fadeAnim.to = 1.0
            fadeAnim.duration = 220
            fadeAnim.restart()
        } else {
            if (visible) {
                animatingOut = true
                slideAnim.stop()
                slideAnim.from = panelY
                slideAnim.to = 120
                slideAnim.easing.type = Easing.InCubic
                slideAnim.duration = 240
                slideAnim.restart()

                fadeAnim.stop()
                fadeAnim.from = panelOpacity
                fadeAnim.to = 0.0
                fadeAnim.duration = 200
                fadeAnim.restart()
            } else {
                panelY = 120
                panelOpacity = 0.0
            }
        }
    }

    NumberAnimation {
        id: slideAnim
        target: vanishOverlayWindow
        property: "panelY"
        onFinished: {
            if (!vanishOverlayWindow.isOpen) {
                vanishOverlayWindow.animatingOut = false
            }
        }
    }

    NumberAnimation {
        id: fadeAnim
        target: vanishOverlayWindow
        property: "panelOpacity"
    }

    Rectangle {
        id: overlayCard
        x: 0
        y: vanishOverlayWindow.panelY
        width: parent.width
        height: 120
        opacity: vanishOverlayWindow.panelOpacity
        clip: true
        color: Qt.rgba(5/255, 6/255, 8/255, 0.85) // Obsidian glass
        border.color: Qt.rgba(1, 1, 1, 0.15)
        border.width: 1
        // Blueprint dashed top border for the aesthetic
        // Note: QML Rectangle doesn't natively support dashed borders easily, 
        // so we use a custom Shape or an Image overlay later. For now, solid is fine to scaffold.

        RowLayout {
            anchors.fill: parent
            anchors.margins: 15
            spacing: 20

            // LEFT NODE: CHRONO & ATMOSPHERE (View Point Aesthetic Evolution)
            Rectangle {
                id: chronoAtmosphereNode
                Layout.preferredWidth: Math.max(340, parent.width * 0.32)
                Layout.fillHeight: true
                radius: 10
                color: Qt.rgba(12/255, 14/255, 18/255, 0.60)
                border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.20)
                border.width: 1

                // Top highlight rim
                Rectangle {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    height: 1
                    color: Qt.rgba(255/255, 255/255, 255/255, 0.12)
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 12

                    // ── CLOCK SUB-TILE (Left) ──
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        HoverHandler { id: clockHover }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                vanishOverlayWindow.use24h = !vanishOverlayWindow.use24h
                            }
                        }

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 4

                            RowLayout {
                                Layout.alignment: Qt.AlignHCenter
                                spacing: 6

                                // Time digits (HH:mm or hh:mm)
                                Text {
                                    text: Qt.formatDateTime(sysClock.date, vanishOverlayWindow.use24h ? "HH:mm" : "hh:mm")
                                    font.family: "JetBrains Mono"
                                    font.pixelSize: 26
                                    font.bold: true
                                    color: clockHover.hovered ? Theme.accentLit : "white"
                                    Behavior on color { ColorAnimation { duration: 140 } }
                                }

                                // Ticking Seconds & Mode Badge Stack
                                ColumnLayout {
                                    Layout.alignment: Qt.AlignVCenter
                                    spacing: 3

                                    // AM / PM or 24H Badge
                                    Rectangle {
                                        Layout.preferredHeight: 14
                                        Layout.preferredWidth: amPmText.implicitWidth + 8
                                        radius: 3
                                        color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.18)
                                        border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.45)
                                        border.width: 1

                                        Text {
                                            id: amPmText
                                            anchors.centerIn: parent
                                            text: vanishOverlayWindow.use24h ? "24H" : Qt.formatDateTime(sysClock.date, "AP")
                                            font.family: "JetBrains Mono"
                                            font.pixelSize: 8
                                            font.bold: true
                                            color: Theme.accent
                                        }
                                    }

                                    // Seconds Indicator
                                    Text {
                                        text: ":" + Qt.formatDateTime(sysClock.date, "ss")
                                        font.family: "JetBrains Mono"
                                        font.pixelSize: 10
                                        font.bold: true
                                        color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.55)
                                    }
                                }
                            }

                            // Full Date with Dot
                            RowLayout {
                                Layout.alignment: Qt.AlignHCenter
                                spacing: 5

                                Rectangle {
                                    width: 4; height: 4; radius: 2
                                    color: Theme.accent
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                Text {
                                    text: Qt.formatDateTime(sysClock.date, "dddd, MMM d")
                                    font.family: "JetBrains Mono"
                                    font.pixelSize: 11
                                    font.weight: Font.Medium
                                    color: Qt.rgba(255/255, 255/255, 255/255, 0.65)
                                }
                            }
                        }
                    }

                    // ── DELICATE LUMINOUS HAIRLINE DIVIDER ──
                    Rectangle {
                        Layout.preferredWidth: 1
                        Layout.preferredHeight: 46
                        Layout.alignment: Qt.AlignVCenter
                        color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.22)
                    }

                    // ── WEATHER & ATMOSPHERE SUB-TILE (Right) ──
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        HoverHandler { id: weatherHover }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                vanishOverlayWindow.refreshWeather()
                            }
                        }

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 4

                            // Weather Icon + Temperature Row
                            RowLayout {
                                Layout.alignment: Qt.AlignHCenter
                                spacing: 8

                                Text {
                                    text: vanishOverlayWindow.weatherIconName
                                    font.family: Theme.fontIcon
                                    font.pixelSize: 24
                                    color: weatherHover.hovered ? Theme.accentLit : Theme.accent
                                    Behavior on color { ColorAnimation { duration: 140 } }
                                    scale: vanishOverlayWindow.weatherRefreshing ? 0.9 : 1.0
                                    Behavior on scale { NumberAnimation { duration: 150 } }
                                }

                                Text {
                                    text: vanishOverlayWindow.weatherTemp
                                    font.family: "JetBrains Mono"
                                    font.pixelSize: 22
                                    font.bold: true
                                    color: weatherHover.hovered ? Theme.accentLit : "white"
                                    Behavior on color { ColorAnimation { duration: 140 } }
                                }
                            }

                            // Condition + City / Feels Readout
                            RowLayout {
                                Layout.alignment: Qt.AlignHCenter
                                spacing: 4

                                Text {
                                    text: vanishOverlayWindow.weatherDesc
                                    font.family: "JetBrains Mono"
                                    font.pixelSize: 11
                                    color: Qt.rgba(255/255, 255/255, 255/255, 0.70)
                                    elide: Text.ElideRight
                                    Layout.maximumWidth: 85
                                }

                                Text {
                                    text: "•"
                                    font.family: "JetBrains Mono"
                                    font.pixelSize: 10
                                    color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.50)
                                    visible: vanishOverlayWindow.weatherCity !== "" || vanishOverlayWindow.weatherFeels !== ""
                                }

                                Text {
                                    text: vanishOverlayWindow.weatherCity || vanishOverlayWindow.weatherFeels || "Atmosphere"
                                    font.family: "JetBrains Mono"
                                    font.pixelSize: 10
                                    color: Qt.rgba(255/255, 255/255, 255/255, 0.50)
                                    elide: Text.ElideRight
                                    Layout.maximumWidth: 80
                                }
                            }
                        }
                    }
                }
            }

            // CENTER NODE: SYSTEM TELEMETRY
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: "transparent"
                border.color: Qt.rgba(1, 1, 1, 0.1)

                ColumnLayout {
                    anchors.centerIn: parent
                    Text { text: "CPU [||||||||..........] 44%"; color: "white"; font.family: "JetBrains Mono" }
                    Text { text: "RAM [||||..............] 42%"; color: "white"; font.family: "JetBrains Mono" }
                }
            }

            // RIGHT NODE: MEDIA DECK
            Rectangle {
                Layout.preferredWidth: parent.width * 0.25
                Layout.fillHeight: true
                color: "transparent"
                border.color: Qt.rgba(1, 1, 1, 0.1)

                ColumnLayout {
                    anchors.centerIn: parent
                    Text { text: "CRAZY TRAIN"; color: "white"; font.bold: true; font.pixelSize: 16; font.family: "JetBrains Mono" }
                    Text { text: "Ozzy Osbourne"; color: "gray"; font.pixelSize: 12; font.family: "JetBrains Mono" }
                    Text { text: "[ BACK ]  [ PLAY ]  [ SKIP ]"; color: "white"; font.pixelSize: 12; font.family: "JetBrains Mono" }
                }
            }
        }
    }
}
