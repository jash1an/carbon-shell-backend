import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../Singletons"

/**
 * WeatherPane: Clean, free web weather monitor & location search for QuickSettings.
 * Powered by wttr.in (zero API key required).
 * Supports automatic device/IP geolocation and instant city search.
 */
Item {
    id: root

    implicitWidth: 264
    implicitHeight: 330

    Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentCol.implicitHeight + 16
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
            width: 4
            anchors.right: flick.right
            anchors.rightMargin: 1
        }

        ColumnLayout {
            id: contentCol
            width: flick.width - 10
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            anchors.topMargin: 4
            spacing: 8

            /* ── 1. Live Weather Overview Card ────────────────────────── */
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 76
                radius: 10
                color: Qt.rgba(Theme.bgAlt.r, Theme.bgAlt.g, Theme.bgAlt.b, 0.45)
                border.color: WeatherService.isError ? Theme.err : Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.4)
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 8

                    // Weather Icon Box
                    Rectangle {
                        Layout.preferredWidth: 46
                        Layout.preferredHeight: 46
                        radius: 23
                        color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.14)
                        border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.3)

                        Text {
                            anchors.centerIn: parent
                            text: WeatherService.icon || "\ue302"
                            font.family: Theme.fontIcon
                            font.pixelSize: 26
                            color: Theme.accentLit
                        }
                    }

                    // Temp, Condition & Location
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1

                        Row {
                            spacing: 6
                            Text {
                                text: WeatherService.temp
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: Theme.fontPx(20)
                                font.weight: Font.Bold
                                color: Theme.fg
                            }
                            Text {
                                text: WeatherService.condition
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: Theme.fontPx(11)
                                font.weight: Font.Medium
                                color: Theme.accentLit
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 3
                                elide: Text.ElideRight
                                width: 110
                            }
                        }

                        Text {
                            text: WeatherService.city.length > 0 ? WeatherService.city : "Current Location"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: Theme.fontPx(10)
                            font.weight: Font.DemiBold
                            color: Theme.fg
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        // Metrics (Feels like, wind, humidity)
                        Row {
                            spacing: 8
                            Row {
                                spacing: 2
                                Text {
                                    text: "thermostat"
                                    font.family: Theme.fontIcon
                                    font.pixelSize: 10
                                    color: Theme.fgDim
                                }
                                Text {
                                    text: WeatherService.feelsLike
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontPx(9)
                                    color: Theme.fgDim
                                }
                            }
                            Row {
                                spacing: 2
                                Text {
                                    text: "air"
                                    font.family: Theme.fontIcon
                                    font.pixelSize: 10
                                    color: Theme.fgDim
                                }
                                Text {
                                    text: WeatherService.wind
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontPx(9)
                                    color: Theme.fgDim
                                }
                            }
                            Row {
                                spacing: 2
                                Text {
                                    text: "water_drop"
                                    font.family: Theme.fontIcon
                                    font.pixelSize: 10
                                    color: Theme.fgDim
                                }
                                Text {
                                    text: WeatherService.humidity
                                    font.family: Theme.font
                                    font.pixelSize: Theme.fontPx(9)
                                    color: Theme.fgDim
                                }
                            }
                        }
                    }
                }
            }

            /* ── 2. Location Search Bar ───────────────────────────────── */
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3

                Text {
                    text: "SEARCH LOCATION"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: Theme.fontPx(9)
                    font.weight: Font.Bold
                    color: Theme.fgDim
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 32
                    radius: 6
                    color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.6)
                    border.color: cityInput.activeFocus ? Theme.accent : Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.4)
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 6
                        spacing: 4

                        Text {
                            text: "search"
                            font.family: Theme.fontIcon
                            font.pixelSize: 13
                            color: Theme.fgDim
                        }

                        TextInput {
                            id: cityInput
                            Layout.fillWidth: true
                            text: WeatherService.configCity
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: Theme.fontPx(11)
                            color: Theme.fg
                            selectByMouse: true
                            selectionColor: Theme.accent
                            clip: true
                            onAccepted: {
                                WeatherService.searchLocation(cityInput.text.trim())
                            }

                            Text {
                                visible: parent.text.length === 0 && !parent.activeFocus
                                text: "Type city (e.g. London, Tokyo)..."
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: Theme.fontPx(10)
                                color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.35)
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        // Clear input button
                        Rectangle {
                            visible: cityInput.text.length > 0
                            Layout.preferredWidth: 16
                            Layout.preferredHeight: 16
                            radius: 8
                            color: clearHov.containsMouse ? Theme.bgHover : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: "close"
                                font.family: Theme.fontIcon
                                font.pixelSize: 11
                                color: Theme.fgDim
                            }
                            MouseArea {
                                id: clearHov
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: cityInput.text = ""
                            }
                        }
                    }
                }
            }

            /* ── 3. Quick Action Buttons ──────────────────────────────── */
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                // Auto-Detect Device Location Button
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 28
                    radius: 6
                    color: autoLocHov.containsMouse ? Theme.bgHover : Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.05)
                    border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.4)
                    border.width: 1

                    Row {
                        anchors.centerIn: parent
                        spacing: 4

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "my_location"
                            font.family: Theme.fontIcon
                            font.pixelSize: 12
                            color: Theme.accentLit
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Auto-Detect"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: Theme.fontPx(10)
                            font.weight: Font.Medium
                            color: Theme.fg
                        }
                    }

                    MouseArea {
                        id: autoLocHov
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            cityInput.text = ""
                            WeatherService.useDeviceLocation()
                        }
                    }
                }

                // Search / Refresh Button
                Rectangle {
                    Layout.preferredWidth: 84
                    Layout.preferredHeight: 28
                    radius: 6
                    color: searchHov.containsMouse ? Theme.accentLit : Theme.accent
                    scale: searchHov.pressed ? 0.96 : (searchHov.containsMouse ? 1.02 : 1.0)
                    Behavior on scale { NumberAnimation { duration: 100 } }

                    Row {
                        anchors.centerIn: parent
                        spacing: 4

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: WeatherService.isFetching ? "hourglass_empty" : "refresh"
                            font.family: Theme.fontIcon
                            font.pixelSize: 12
                            color: Theme.isDark ? "#0e0e12" : "#ffffff"
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: WeatherService.isFetching ? "..." : "Search"
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: Theme.fontPx(10)
                            font.weight: Font.Bold
                            color: Theme.isDark ? "#0e0e12" : "#ffffff"
                        }
                    }

                    MouseArea {
                        id: searchHov
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            WeatherService.searchLocation(cityInput.text.trim())
                        }
                    }
                }
            }

            /* ── 4. 3-Day Forecast Cards ──────────────────────────────── */
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                visible: WeatherService.forecast.length > 0

                Text {
                    text: "3-DAY FORECAST"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: Theme.fontPx(9)
                    font.weight: Font.Bold
                    color: Theme.fgDim
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Repeater {
                        model: WeatherService.forecast
                        delegate: Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 64
                            radius: 8
                            color: Qt.rgba(Theme.bgAlt.r, Theme.bgAlt.g, Theme.bgAlt.b, 0.35)
                            border.color: Qt.rgba(Theme.outline.r, Theme.outline.g, Theme.outline.b, 0.3)
                            border.width: 1

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 4
                                spacing: 2

                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: modelData.day
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: Theme.fontPx(9)
                                    font.weight: Font.DemiBold
                                    color: Theme.fgDim
                                }

                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: modelData.icon || "\ue302"
                                    font.family: Theme.fontIcon
                                    font.pixelSize: 16
                                    color: Theme.accentLit
                                }

                                Text {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: modelData.tempMax + " / " + modelData.tempMin
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: Theme.fontPx(9)
                                    font.weight: Font.Bold
                                    color: Theme.fg
                                }
                            }
                        }
                    }
                }
            }

            /* ── 5. Status / Provider line ────────────────────────────── */
            RowLayout {
                Layout.fillWidth: true
                spacing: 5

                Rectangle {
                    Layout.preferredWidth: 6
                    Layout.preferredHeight: 6
                    radius: 3
                    color: WeatherService.isError ? Theme.err : (WeatherService.isFetching ? Theme.warn : Theme.ok)
                }

                Text {
                    Layout.fillWidth: true
                    text: WeatherService.statusMessage
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: Theme.fontPx(9)
                    color: WeatherService.isError ? Theme.err : Theme.fgDim
                    elide: Text.ElideRight
                }
            }
        }
    }
}
