import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import "../Singletons"
import "../components"

/**
 * CenterDashboard: Top-center panel
 *  - Left: Compact month calendar with month navigation and day selector
 *  - Center: Digital clock surrounded by a small dotted circle, with the weather capsule
 *            smoothly orbiting and rotating through the whole circle (360°)
 *  - Right: Weather overview + Compact Music Player Overlay in the bottom right
 */
Item {
    id: root

    property bool open: false
    property bool minimalCalendarOnly: false
    property bool attachedBottom: false
    property bool showBackground: true
    readonly property bool hovered: (rootHover && rootHover.hovered) || (mainCardHover && mainCardHover.hovered)
    signal closeRequested()

    implicitWidth: root.minimalCalendarOnly ? 310 : 820
    implicitHeight: root.minimalCalendarOnly ? 276 : 260
    width: implicitWidth
    height: implicitHeight
    clip: true

    focus: root.open
    Keys.enabled: root.open
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Escape) {
            console.log("[CenterDashboard] ESCAPE PRESSED - requesting close")
            root.closeRequested()
            event.accepted = true
        }
    }
    Keys.onEscapePressed: (event) => {
        console.log("[CenterDashboard] onEscapePressed - requesting close")
        root.closeRequested()
        event.accepted = true
    }

    HoverHandler {
        id: rootHover
    }

    readonly property var cardItem: mainCard
    readonly property var rightColItem: rightCol
    property bool animatingOut: false

    /* ── Live Clock State ────────────────────────────────────────────── */
    property var currentDate: new Date()
    property int currentHourRaw: currentDate.getHours()
    property string clockFormat: "12"
    property bool showDateInClock: true

    FileView {
        id: dashClockCfg
        path: (Quickshell.env("HOME") || "") + "/.config/hypr/carbon-clock-style.json"
        watchChanges: true
        blockLoading: true
        printErrors: false
        onLoaded: root.applyClockCfg(dashClockCfg.text())
        onFileChanged: reload()
    }

    function applyClockCfg(txt) {
        if (!txt) return
        try {
            var parsed = JSON.parse(txt)
            if (parsed && parsed.format) {
                root.clockFormat = parsed.format
            }
            if (parsed && parsed.showDate !== undefined) {
                root.showDateInClock = Boolean(parsed.showDate)
            }
        } catch (e) {}
    }

    property string hourStr: {
        let h = root.currentHourRaw
        if (root.clockFormat !== "24") {
            h = h % 12 || 12
        }
        return (h < 10 ? "0" : "") + h
    }
    property string minStr: {
        let m = currentDate.getMinutes()
        return (m < 10 ? "0" : "") + m
    }
    property string secStr: {
        let s = currentDate.getSeconds()
        return (s < 10 ? "0" : "") + s
    }
    property string dayOfWeekStr: currentDate.toLocaleDateString(Qt.locale(), "dddd")
    property string fullDateStr: currentDate.toLocaleDateString(Qt.locale(), "dddd, MMMM dd")

    property real secondPulse: 1.0
    NumberAnimation on secondPulse {
        id: pulseReset
        to: 1.0
        duration: 600
        easing.type: Easing.OutQuint
        running: false
    }

    onOpenChanged: {
        if (root.open) {
            root.animatingOut = false
            animatingOutTimer.stop()
            root.currentDate = new Date()
            root.calendarViewMode = "grid"
            root.eventFormMode = false
            root.reloadEvents()
            if (!root.minimalCalendarOnly) {
                centerCol.syncClockAngle()
                if (centerCol.levAnim) centerCol.levAnim.restart()
                if (centerCol.breathAnim) centerCol.breathAnim.restart()
            }
        } else {
            root.animatingOut = true
            animatingOutTimer.restart()
        }
    }

    Timer {
        id: animatingOutTimer
        interval: 200
        onTriggered: root.animatingOut = false
    }

    FrameAnimation {
        id: orbitSmoothAnim
        running: root.open && !root.minimalCalendarOnly && !centerCol.userDragging && root.visible
        onTriggered: centerCol.syncClockAngle()
    }

    Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: {
            root.currentDate = new Date()
            root.secondPulse = 1.08
            pulseReset.start()
        }
    }

    /* ── Weather State from WeatherService ───────────────────────────── */
    property int weatherDayIndex: 0
    readonly property var curDayForecast: (WeatherService.forecast && WeatherService.forecast.length > root.weatherDayIndex) ? WeatherService.forecast[root.weatherDayIndex] : null

    readonly property string weatherTemp: curDayForecast ? (root.weatherDayIndex === 0 ? WeatherService.temp : curDayForecast.max_temp) : WeatherService.temp
    readonly property string weatherTempFull: WeatherService.tempFull
    readonly property string weatherCond: curDayForecast ? curDayForecast.condition : WeatherService.condition
    readonly property string weatherIcon: curDayForecast ? curDayForecast.icon : WeatherService.icon
    readonly property string weatherDayTitle: curDayForecast ? curDayForecast.day : root.dayOfWeekStr.toUpperCase()
    readonly property string weatherWind: curDayForecast ? (curDayForecast.wind || "") : (WeatherService.wind || "")
    readonly property string weatherHumid: curDayForecast ? (curDayForecast.humidity || "") : (WeatherService.humidity || "")

    function prevWeatherDay() {
        if (root.weatherDayIndex > 0) root.weatherDayIndex--
    }
    function nextWeatherDay() {
        if (WeatherService.forecast && root.weatherDayIndex < WeatherService.forecast.length - 1) root.weatherDayIndex++
    }

    /* ── Calendar State & Event Management ───────────────────────────── */
    property int calYear: currentDate.getFullYear()
    property int calMonth: currentDate.getMonth() // 0-11
    property int selectedDay: currentDate.getDate()
    property var monthEvents: ({})
    property string calendarViewMode: "grid" // "grid" or "events"
    property bool eventFormMode: false
    property string editingEventId: ""

    readonly property var monthNames: [
        "JANUARY", "FEBRUARY", "MARCH", "APRIL", "MAY", "JUNE",
        "JULY", "AUGUST", "SEPTEMBER", "OCTOBER", "NOVEMBER", "DECEMBER"
    ]

    readonly property var weekdayShortNames: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    function prevMonth() {
        if (calMonth === 0) {
            calMonth = 11
            calYear--
        } else {
            calMonth--
        }
        root.reloadEvents()
    }

    function nextMonth() {
        if (calMonth === 11) {
            calMonth = 0
            calYear++
        } else {
            calMonth++
        }
        root.reloadEvents()
    }

    function daysInMonth(y, m) {
        return new Date(y, m + 1, 0).getDate()
    }

    function firstDayWeekday(y, m) {
        let d = new Date(y, m, 1).getDay()
        return d === 0 ? 6 : d - 1
    }

    function getDayKey(day) {
        let mm = (root.calMonth + 1 < 10 ? "0" : "") + (root.calMonth + 1)
        let dd = (day < 10 ? "0" : "") + day
        return root.calYear + "-" + mm + "-" + dd
    }

    function getEventsForDay(day) {
        let key = root.getDayKey(day)
        return (root.monthEvents && root.monthEvents[key]) ? root.monthEvents[key] : []
    }

    function hasEvent(day) {
        return root.getEventsForDay(day).length > 0
    }

    function hasFestival(day) {
        let evs = root.getEventsForDay(day)
        for (let i = 0; i < evs.length; i++) {
            if (evs[i].type === "festival") return true
        }
        return false
    }

    function getSelectedDateWeekday() {
        let d = new Date(root.calYear, root.calMonth, root.selectedDay).getDay()
        return root.weekdayShortNames[d]
    }

    readonly property string calScript: (Quickshell.env("HOME") || "") + "/.config/hypr/scripts/carbon-calendar.py"

    Process {
        id: eventLoaderProc
        command: ["python3", root.calScript, "--get-month", String(root.calYear), String(root.calMonth + 1)]
        stdout: StdioCollector { id: eventLoaderC; waitForEnd: true }
        onExited: {
            try {
                let txt = String(eventLoaderC.text).trim()
                if (txt.length > 2) {
                    root.monthEvents = JSON.parse(txt)
                } else {
                    root.monthEvents = ({})
                }
            } catch (e) {
                root.monthEvents = ({})
            }
        }
    }

    Process {
        id: eventOpProc
        command: ["true"]
        onExited: {
            root.eventFormMode = false
            root.editingEventId = ""
            root.reloadEvents()
        }
    }

    function reloadEvents() {
        eventLoaderProc.command = ["python3", root.calScript, "--get-month", String(root.calYear), String(root.calMonth + 1)]
        eventLoaderProc.running = true
    }

    function addOrSaveEvent(title, time) {
        if (!title || title.trim().length === 0) return
        let t = (time && time.trim().length > 0) ? time.trim() : "All day"
        if (root.editingEventId.length > 0) {
            eventOpProc.command = ["python3", root.calScript, "--edit", root.editingEventId, "--title", title.trim(), "--time", t]
        } else {
            let key = root.getDayKey(root.selectedDay)
            eventOpProc.command = ["python3", root.calScript, "--add", key, title.trim(), "--time", t]
        }
        eventOpProc.running = true
    }

    function deleteEvent(evId) {
        if (!evId) return
        eventOpProc.command = ["python3", root.calScript, "--delete", evId]
        eventOpProc.running = true
    }

    onCalMonthChanged: reloadEvents()
    onCalYearChanged: reloadEvents()

    /* ── MPRIS Music State ───────────────────────────────────────────── */
    readonly property var mprisPlayer: LyricsService.activePlayer
    readonly property bool isMusicPlaying: LyricsService.isPlaying
    readonly property bool hasMusicTrack: LyricsService.hasTrack
    readonly property string musicTitle: hasMusicTrack ? (LyricsService.trackTitle || "No title") : "No media playing"
    readonly property string musicArtist: hasMusicTrack ? (LyricsService.trackArtist || "Unknown artist") : "Carbon Audio"
    readonly property string musicArtUrl: LyricsService.artUrl
    readonly property real musicPosition: LyricsService.currentPosition
    readonly property real musicLength: LyricsService.totalLength
    readonly property real musicProgress: musicLength > 0 ? Math.max(0, Math.min(1.0, musicPosition / musicLength)) : 0.0

    function formatTime(secs) {
        if (isNaN(secs) || secs < 0) return "00:00"
        let m = Math.floor(secs / 60)
        let s = Math.floor(secs % 60)
        return (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s
    }

    /* ── Main Card ───────────────────────────────────────────────────── */
    Item {
        id: mainCard
        width: parent.width
        height: parent.height

        HoverHandler {
            id: mainCardHover
        }

        /* Dead-zone click absorber inside card boundary so clicks never fall through */
        MouseArea {
            anchors.fill: parent
            z: 0
        }

        Shape {
            id: cardBgShape
            anchors.fill: parent
            layer.enabled: true
            layer.smooth: true
            preferredRendererType: Shape.CurveRenderer
            visible: root.showBackground

            // 1. Fill background (Seamlessly attached: square top, rounded bottom)
            ShapePath {
                fillColor: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, Theme.shellOpacity)
                strokeColor: "transparent"
                strokeWidth: 0
                startX: 0; startY: 0
                PathLine { x: mainCard.width; y: 0 }
                PathLine { x: mainCard.width; y: mainCard.height - 20 }
                PathArc { x: mainCard.width - 20; y: mainCard.height; radiusX: 20; radiusY: 20 }
                PathLine { x: 20; y: mainCard.height }
                PathArc { x: 0; y: mainCard.height - 20; radiusX: 20; radiusY: 20 }
                PathLine { x: 0; y: 0 }
            }

            // 2. Continuous stroke (Right, Bottom, Left - NO stroke on top edge to blend seamlessly into the bar)
            ShapePath {
                fillColor: "transparent"
                strokeColor: root.open ? Qt.rgba(Theme.accentLit.r, Theme.accentLit.g, Theme.accentLit.b, 0.45) : Theme.outline
                strokeWidth: 1
                startX: mainCard.width; startY: 0
                PathLine { x: mainCard.width; y: mainCard.height - 20 }
                PathArc { x: mainCard.width - 20; y: mainCard.height; radiusX: 20; radiusY: 20 }
                PathLine { x: 20; y: mainCard.height }
                PathArc { x: 0; y: mainCard.height - 20; radiusX: 20; radiusY: 20 }
                PathLine { x: 0; y: 0 }
            }
        }

        opacity: root.showBackground ? (root.open ? 1.0 : 0.0) : 1.0
        y: root.showBackground ? (root.open ? 0 : (root.attachedBottom ? height : -height)) : 0

        Behavior on opacity {
            enabled: root.showBackground
            NumberAnimation {
                duration: root.open ? 180 : 140
                easing.bezierCurve: Theme.animCurves.expressiveDefaultEffects
            }
        }
        Behavior on y {
            NumberAnimation {
                duration: root.open ? 240 : 160
                easing.bezierCurve: root.open ? Theme.animCurves.expressiveDefaultSpatial : Theme.animCurves.standardAccel
            }
        }

        /* Ambient subtle color blobs from imperative-dots */
        Rectangle {
            visible: !root.minimalCalendarOnly
            width: parent.width * 0.45; height: width; radius: width / 2
            x: (parent.width * 0.7 - width / 2) + Math.cos(centerCol.orbitAngle * Math.PI / 180 * 1.5) * 40
            y: (parent.height * 0.3 - height / 2) + Math.sin(centerCol.orbitAngle * Math.PI / 180 * 1.5) * 20
            opacity: 0.03
            color: Theme.accentLit
        }
        Rectangle {
            visible: !root.minimalCalendarOnly
            width: parent.width * 0.4; height: width; radius: width / 2
            x: (parent.width * 0.3 - width / 2) + Math.sin(centerCol.orbitAngle * Math.PI / 180 * 1.2) * -30
            y: (parent.height * 0.7 - height / 2) + Math.cos(centerCol.orbitAngle * Math.PI / 180 * 1.2) * -25
            opacity: 0.02
            color: Theme.accent
        }

        /* ── 3-Column Layout ─────────────────────────────────────────── */
        RowLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 12
            z: 1

            /* ========================================================= */
            /* 1. LEFT COLUMN: CALENDAR                                 */
            /* ========================================================= */
            Item {
                id: calendarCol
                Layout.preferredWidth: root.minimalCalendarOnly ? 282 : 220
                Layout.fillWidth: root.minimalCalendarOnly
                Layout.fillHeight: true
                clip: true

                /* ── 1A. Month Grid View ──────────────────────────────── */
                ColumnLayout {
                    id: monthGridView
                    anchors.fill: parent
                    spacing: 6
                    visible: opacity > 0.001
                    opacity: root.calendarViewMode === "grid" ? 1.0 : 0.0
                    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    transform: Translate {
                        x: root.calendarViewMode === "grid" ? 0 : -20
                        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    }

                    /* Header: <  MONTH YEAR  >  Today */
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        Rectangle {
                            width: 20
                            height: 20
                            radius: 10
                            color: prevM.containsMouse ? Theme.bgHover : "transparent"
                            Text {
                                anchors.centerIn: parent
                                text: "‹"
                                font.pixelSize: Theme.fontPx(14)
                                font.weight: Font.Bold
                                color: prevM.containsMouse ? Theme.fg : Theme.fgDim
                            }
                            MouseArea {
                                id: prevM
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.prevMonth()
                            }
                        }

                        Text {
                            Layout.fillWidth: true
                            text: root.monthNames[root.calMonth] + " " + root.calYear
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: Theme.fontPx(11)
                            font.weight: Font.Bold
                            font.letterSpacing: 1.0
                            color: Theme.fg
                            horizontalAlignment: Text.AlignHCenter
                        }

                        Rectangle {
                            width: 20
                            height: 20
                            radius: 10
                            color: nextM.containsMouse ? Theme.bgHover : "transparent"
                            Text {
                                anchors.centerIn: parent
                                text: "›"
                                font.pixelSize: Theme.fontPx(14)
                                font.weight: Font.Bold
                                color: nextM.containsMouse ? Theme.fg : Theme.fgDim
                            }
                            MouseArea {
                                id: nextM
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.nextMonth()
                            }
                        }

                        Rectangle {
                            width: 20
                            height: 20
                            radius: 10
                            color: addM.containsMouse ? Theme.bgHover : "transparent"
                            Text {
                                anchors.centerIn: parent
                                text: "•"
                                font.pixelSize: Theme.fontPx(14)
                                font.weight: Font.Bold
                                color: addM.containsMouse ? Theme.accentLit : Theme.fgDim
                            }
                            MouseArea {
                                id: addM
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.calMonth = root.currentDate.getMonth()
                                    root.calYear = root.currentDate.getFullYear()
                                    root.selectedDay = root.currentDate.getDate()
                                    root.reloadEvents()
                                }
                            }
                        }
                    }

                    /* Weekday Names Row */
                    Row {
                        Layout.fillWidth: true
                        spacing: 0
                        readonly property var dayHeaders: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
                        Repeater {
                            model: parent.dayHeaders
                            Item {
                                width: calendarCol.width / 7
                                height: 18
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: Theme.fontPx(9)
                                    font.weight: Font.DemiBold
                                    color: Theme.fgDim
                                }
                            }
                        }
                    }

                    /* Days Grid */
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        Grid {
                            id: daysGrid
                            anchors.fill: parent
                            columns: 7
                            rows: 6

                            readonly property int totalDaysCur: root.daysInMonth(root.calYear, root.calMonth)
                            readonly property int firstDayIndex: root.firstDayWeekday(root.calYear, root.calMonth)
                            readonly property int prevMonthDays: {
                                let pm = root.calMonth === 0 ? 11 : root.calMonth - 1
                                let py = root.calMonth === 0 ? root.calYear - 1 : root.calYear
                                return root.daysInMonth(py, pm)
                            }

                            Repeater {
                                model: 42
                                Item {
                                    width: daysGrid.width / 7
                                    height: daysGrid.height / 6

                                    readonly property int cellIndex: index
                                    readonly property bool isPrevMonth: cellIndex < daysGrid.firstDayIndex
                                    readonly property bool isNextMonth: cellIndex >= (daysGrid.firstDayIndex + daysGrid.totalDaysCur)
                                    readonly property bool isCurMonth: !isPrevMonth && !isNextMonth

                                    readonly property int dayNum: {
                                        if (isPrevMonth) {
                                            return daysGrid.prevMonthDays - (daysGrid.firstDayIndex - cellIndex - 1)
                                        } else if (isCurMonth) {
                                            return cellIndex - daysGrid.firstDayIndex + 1
                                        } else {
                                            return cellIndex - (daysGrid.firstDayIndex + daysGrid.totalDaysCur) + 1
                                        }
                                    }

                                    readonly property bool isToday: isCurMonth &&
                                                                    dayNum === root.currentDate.getDate() &&
                                                                    root.calMonth === root.currentDate.getMonth() &&
                                                                    root.calYear === root.currentDate.getFullYear()

                                    readonly property bool isSelected: isCurMonth && dayNum === root.selectedDay
                                    readonly property bool dayHasEvent: isCurMonth && root.hasEvent(dayNum)
                                    readonly property bool dayHasFest: isCurMonth && root.hasFestival(dayNum)

                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: 22
                                        height: 22
                                        radius: 11
                                        color: isToday
                                            ? Theme.accentLit
                                            : (isSelected
                                                ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.40)
                                                : (dayMouseArea.containsMouse
                                                    ? (isCurMonth ? Qt.rgba(Theme.accentLit.r, Theme.accentLit.g, Theme.accentLit.b, 0.22) : Qt.rgba(1, 1, 1, 0.08))
                                                    : "transparent"))
                                        border.color: isToday
                                            ? "transparent"
                                            : (isSelected
                                                ? Theme.accentLit
                                                : (dayMouseArea.containsMouse
                                                    ? (isCurMonth ? Qt.rgba(Theme.accentLit.r, Theme.accentLit.g, Theme.accentLit.b, 0.60) : Qt.rgba(1, 1, 1, 0.18))
                                                    : "transparent"))
                                        border.width: 1

                                        scale: dayMouseArea.containsMouse && !isToday ? 1.08 : 1.0
                                        Behavior on scale { NumberAnimation { duration: 120 } }
                                        Behavior on color { ColorAnimation { duration: 100 } }
                                        Behavior on border.color { ColorAnimation { duration: 100 } }
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        anchors.verticalCenterOffset: dayHasEvent ? -2 : 0
                                        text: dayNum
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: Theme.fontPx(10)
                                        font.weight: (isToday || isSelected || dayMouseArea.containsMouse) ? Font.Bold : Font.Normal
                                        color: isToday
                                            ? (Theme.isDark ? "#121118" : "#ffffff")
                                            : ((isSelected || (dayMouseArea.containsMouse && isCurMonth))
                                                ? Theme.accentLit
                                                : (dayMouseArea.containsMouse
                                                    ? Theme.fg
                                                    : (isCurMonth ? Theme.fg : Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.22))))
                                    }

                                    /* Small Event Indicator Dot */
                                    Rectangle {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.bottom: parent.bottom
                                        anchors.bottomMargin: 1.5
                                        width: 3.5
                                        height: 3.5
                                        radius: 1.75
                                        visible: dayHasEvent
                                        color: dayHasFest ? "#ffb86c" : Theme.accentLit
                                    }

                                    MouseArea {
                                        id: dayMouseArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: parent.isCurMonth ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        onClicked: {
                                            if (parent.isCurMonth) {
                                                if (root.minimalCalendarOnly) {
                                                    if (root.selectedDay === parent.dayNum && (dayHasEvent || dayHasFest)) {
                                                        root.calendarViewMode = "events"
                                                        root.eventFormMode = false
                                                        root.editingEventId = ""
                                                    } else {
                                                        root.selectedDay = parent.dayNum
                                                    }
                                                } else {
                                                    root.selectedDay = parent.dayNum
                                                    root.calendarViewMode = "events"
                                                    root.eventFormMode = false
                                                    root.editingEventId = ""
                                                }
                                            } else if (parent.isPrevMonth) {
                                                root.prevMonth()
                                            } else if (parent.isNextMonth) {
                                                root.nextMonth()
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                /* ── 1B. Day Events View ──────────────────────────────── */
                ColumnLayout {
                    id: dayEventsView
                    anchors.fill: parent
                    spacing: 6
                    visible: opacity > 0.001
                    opacity: root.calendarViewMode === "events" ? 1.0 : 0.0
                    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    transform: Translate {
                        x: root.calendarViewMode === "events" ? 0 : 20
                        Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                    }

                    /* Day Header */
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 4

                        Rectangle {
                            width: 22
                            height: 22
                            radius: 11
                            color: backHov.containsMouse ? Theme.bgHover : "transparent"
                            Text {
                                anchors.centerIn: parent
                                text: "‹"
                                font.pixelSize: Theme.fontPx(16)
                                font.weight: Font.Bold
                                color: backHov.containsMouse ? Theme.accentLit : Theme.fg
                            }
                            MouseArea {
                                id: backHov
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.eventFormMode = false
                                    root.editingEventId = ""
                                    root.calendarViewMode = "grid"
                                }
                            }
                        }

                        Column {
                            Layout.fillWidth: true
                            spacing: 0
                            Text {
                                text: root.selectedDay + " " + root.monthNames[root.calMonth].substring(0, 3) + " " + root.calYear
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: Theme.fontPx(11)
                                font.weight: Font.Bold
                                color: Theme.fg
                                elide: Text.ElideRight
                            }
                            Text {
                                text: root.getSelectedDateWeekday()
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: Theme.fontPx(9)
                                color: Theme.accentLit
                            }
                        }

                        Rectangle {
                            width: 22
                            height: 22
                            radius: 11
                            color: addEvHov.containsMouse ? Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.25) : Theme.bgAlt
                            border.color: Theme.accent
                            border.width: 1
                            Text {
                                anchors.centerIn: parent
                                text: root.eventFormMode ? "✕" : "+"
                                font.pixelSize: Theme.fontPx(12)
                                font.weight: Font.Bold
                                color: Theme.accentLit
                            }
                            MouseArea {
                                id: addEvHov
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (root.eventFormMode) {
                                        root.eventFormMode = false
                                        root.editingEventId = ""
                                    } else {
                                        root.editingEventId = ""
                                        formTitleInput.text = ""
                                        formTimeInput.text = ""
                                        root.eventFormMode = true
                                        Qt.callLater(() => formTitleInput.forceActiveFocus())
                                    }
                                }
                            }
                        }
                    }

                    /* Content area: Form OR Event List */
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        /* Inline Add / Edit Form */
                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 6
                            visible: root.eventFormMode

                            Text {
                                text: root.editingEventId.length > 0 ? "Edit Event" : "New Event"
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: Theme.fontPx(11)
                                font.weight: Font.Bold
                                color: Theme.accentLit
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 28
                                radius: 6
                                color: Theme.bgAlt
                                border.color: formTitleInput.activeFocus ? Theme.accent : Theme.outline
                                border.width: 1

                                TextInput {
                                    id: formTitleInput
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    verticalAlignment: Text.AlignVCenter
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: Theme.fontPx(11)
                                    color: Theme.fg
                                    clip: true
                                    Text {
                                        text: "Event title…"
                                        color: Theme.fgFaint
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: Theme.fontPx(11)
                                        anchors.fill: parent
                                        verticalAlignment: Text.AlignVCenter
                                        visible: !formTitleInput.text && !formTitleInput.activeFocus
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 28
                                radius: 6
                                color: Theme.bgAlt
                                border.color: formTimeInput.activeFocus ? Theme.accent : Theme.outline
                                border.width: 1

                                TextInput {
                                    id: formTimeInput
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    verticalAlignment: Text.AlignVCenter
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: Theme.fontPx(11)
                                    color: Theme.fg
                                    clip: true
                                    Text {
                                        text: "Time (e.g. 15:30 or All day)…"
                                        color: Theme.fgFaint
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: Theme.fontPx(11)
                                        anchors.fill: parent
                                        verticalAlignment: Text.AlignVCenter
                                        visible: !formTimeInput.text && !formTimeInput.activeFocus
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 26
                                    radius: 6
                                    color: Theme.bgAlt
                                    border.color: Theme.outline
                                    border.width: 1
                                    Text {
                                        anchors.centerIn: parent
                                        text: "Cancel"
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: Theme.fontPx(10)
                                        color: Theme.fgDim
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.eventFormMode = false
                                            root.editingEventId = ""
                                        }
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 26
                                    radius: 6
                                    color: Theme.accent
                                    Text {
                                        anchors.centerIn: parent
                                        text: "Save"
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: Theme.fontPx(10)
                                        font.weight: Font.Bold
                                        color: Theme.isDark ? "#0E0E12" : "#ffffff"
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.addOrSaveEvent(formTitleInput.text, formTimeInput.text)
                                        }
                                    }
                                }
                            }

                            Item { Layout.fillHeight: true }
                        }

                        /* Event List */
                        ListView {
                            id: eventListView
                            anchors.fill: parent
                            visible: !root.eventFormMode
                            clip: true
                            spacing: 5
                            model: root.getEventsForDay(root.selectedDay)

                            ScrollBar.vertical: ScrollBar {
                                policy: ScrollBar.AsNeeded
                                width: 4
                            }

                            delegate: Rectangle {
                                width: eventListView.width - 4
                                height: 38
                                radius: 8
                                color: Theme.bgAlt
                                border.color: modelData.type === "festival" ? Qt.rgba(1, 0.72, 0.42, 0.35) : Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.25)
                                border.width: 1

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 6
                                    anchors.rightMargin: 6
                                    spacing: 6

                                    Text {
                                        text: modelData.icon || (modelData.type === "festival" ? "🪔" : "📌")
                                        font.pixelSize: Theme.fontPx(12)
                                    }

                                    Column {
                                        Layout.fillWidth: true
                                        spacing: 1

                                        Text {
                                            width: parent.width
                                            text: modelData.title
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: Theme.fontPx(10)
                                            font.weight: Font.DemiBold
                                            color: modelData.type === "festival" ? "#ffb86c" : Theme.fg
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            width: parent.width
                                            text: modelData.type === "festival" ? (modelData.category === "national" ? "National Holiday" : "Indian Festival") : (modelData.time || "All day")
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: Theme.fontPx(8)
                                            color: Theme.fgDim
                                            elide: Text.ElideRight
                                        }
                                    }

                                    /* Edit & Delete actions for user events */
                                    Row {
                                        spacing: 4
                                        visible: modelData.is_user === true

                                        Rectangle {
                                            width: 18
                                            height: 18
                                            radius: 4
                                            color: editEvHov.containsMouse ? Theme.bgHover : "transparent"
                                            Text {
                                                anchors.centerIn: parent
                                                text: "✎"
                                                font.pixelSize: Theme.fontPx(10)
                                                color: Theme.accentLit
                                            }
                                            MouseArea {
                                                id: editEvHov
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    root.editingEventId = modelData.id
                                                    formTitleInput.text = modelData.title
                                                    formTimeInput.text = modelData.time || ""
                                                    root.eventFormMode = true
                                                    Qt.callLater(() => formTitleInput.forceActiveFocus())
                                                }
                                            }
                                        }

                                        Rectangle {
                                            width: 18
                                            height: 18
                                            radius: 4
                                            color: delEvHov.containsMouse ? Qt.rgba(1, 0.3, 0.3, 0.25) : "transparent"
                                            Text {
                                                anchors.centerIn: parent
                                                text: "✕"
                                                font.pixelSize: Theme.fontPx(9)
                                                color: delEvHov.containsMouse ? "#ff6b6b" : Theme.fgDim
                                            }
                                            MouseArea {
                                                id: delEvHov
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.deleteEvent(modelData.id)
                                            }
                                        }
                                    }
                                }
                            }

                            /* Empty state */
                            Item {
                                anchors.centerIn: parent
                                width: parent.width
                                height: 110
                                visible: eventListView.count === 0 && !root.eventFormMode

                                Column {
                                    anchors.centerIn: parent
                                    spacing: 6

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: "calendar_today"
                                        font.family: Theme.fontIcon
                                        font.pixelSize: 22
                                        color: Theme.fgFaint
                                    }

                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: "No events on this day"
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: Theme.fontPx(10)
                                        color: Theme.fgDim
                                    }

                                    Rectangle {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: 80
                                        height: 22
                                        radius: 6
                                        color: addEmptyHov.containsMouse ? Theme.accent : Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.2)
                                        border.color: Theme.accent
                                        border.width: 1

                                        Text {
                                            anchors.centerIn: parent
                                            text: "+ Add Event"
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: Theme.fontPx(9)
                                            font.weight: Font.Bold
                                            color: addEmptyHov.containsMouse ? (Theme.isDark ? "#0E0E12" : "#ffffff") : Theme.accentLit
                                        }

                                        MouseArea {
                                            id: addEmptyHov
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.editingEventId = ""
                                                formTitleInput.text = ""
                                                formTimeInput.text = ""
                                                root.eventFormMode = true
                                                Qt.callLater(() => formTitleInput.forceActiveFocus())
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            /* Vertical Divider 1 */
            Rectangle {
                visible: !root.minimalCalendarOnly
                Layout.preferredWidth: 1.5
                Layout.fillHeight: true
                color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.16)
            }

            /* ========================================================= */
            /* 2. CENTER COLUMN: SOLAR SYSTEM ORBIT WITH 3D WATCH OCCLUSION */
            /* ========================================================= */
            Item {
                id: centerCol
                visible: !root.minimalCalendarOnly
                Layout.fillWidth: !root.minimalCalendarOnly
                Layout.fillHeight: true

                readonly property real cx: centerCol.width / 2
                readonly property real cy: centerCol.height / 2
                readonly property real orbitRadiusX: 155 * centerCol.orbitBreath
                readonly property real orbitRadiusY: 60 * centerCol.orbitBreath
                readonly property real orbitTiltDeg: -13
                readonly property real orbitTiltRad: orbitTiltDeg * Math.PI / 180
                readonly property real cosTilt: Math.cos(orbitTiltRad)
                readonly property real sinTilt: Math.sin(orbitTiltRad)

                // Organic levitation & breathing from imperative-dots
                property real levitation: 0
                property alias levAnim: levAnimItem
                SequentialAnimation {
                    id: levAnimItem
                    loops: Animation.Infinite
                    running: true
                    paused: !(root.open && root.visible)
                    NumberAnimation { target: centerCol; property: "levitation"; from: 0; to: -5; duration: 4000; easing.type: Easing.InOutSine }
                    NumberAnimation { target: centerCol; property: "levitation"; from: -5; to: 0; duration: 4000; easing.type: Easing.InOutSine }
                }

                property real orbitBreath: 1.0
                property alias breathAnim: breathAnimItem
                SequentialAnimation {
                    id: breathAnimItem
                    loops: Animation.Infinite
                    running: true
                    paused: !(root.open && root.visible)
                    NumberAnimation { target: centerCol; property: "orbitBreath"; from: 1.0; to: 1.025; duration: 3500; easing.type: Easing.InOutSine }
                    NumberAnimation { target: centerCol; property: "orbitBreath"; from: 1.025; to: 1.0; duration: 3500; easing.type: Easing.InOutSine }
                }

                // Real clock seconds revolution: takes exactly 60 seconds (1 minute) for 1 full 360° revolution
                // 00 seconds sits at 12 o'clock (270° in standard Cartesian coordinates)
                readonly property bool userDragging: false
                property real clockAngle: 270

                function syncClockAngle() {
                    let d = new Date()
                    let sec = d.getSeconds() + (d.getMilliseconds() / 1000.0)
                    clockAngle = (270 + sec * 6) % 360
                }

                readonly property real orbitAngle: clockAngle
                readonly property string displayedSecStr: root.secStr

                readonly property real rad: centerCol.orbitAngle * Math.PI / 180
                readonly property real ex: orbitRadiusX * Math.cos(rad)
                readonly property real ey: orbitRadiusY * Math.sin(rad)
                readonly property real posX: cx + ex * cosTilt - ey * sinTilt
                readonly property real posY: cy + ex * sinTilt + ey * cosTilt
                readonly property real zDepth: Math.sin(rad)

                readonly property real tangentAngle: {
                    var dx = -orbitRadiusX * Math.sin(rad) * cosTilt - orbitRadiusY * Math.cos(rad) * sinTilt
                    var dy = -orbitRadiusX * Math.sin(rad) * sinTilt + orbitRadiusY * Math.cos(rad) * cosTilt
                    return Math.atan2(dy, dx) * 180 / Math.PI
                }

                /* ── Canvas: Tilted Dashed Ellipse Orbit Track (z: 4) ──────── */
                Canvas {
                    id: orbitCanvas
                    anchors.fill: parent
                    z: 4

                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.reset()
                        ctx.clearRect(0, 0, width, height)

                        var cx = centerCol.cx
                        var cy = centerCol.cy
                        var a = centerCol.orbitRadiusX
                        var b = centerCol.orbitRadiusY
                        var cosT = centerCol.cosTilt
                        var sinT = centerCol.sinTilt

                        ctx.beginPath()
                        var steps = 120
                        for (var i = 0; i <= steps; i++) {
                            var theta = (i / steps) * 2 * Math.PI
                            var ex = a * Math.cos(theta)
                            var ey = b * Math.sin(theta)
                            var px = cx + ex * cosT - ey * sinT
                            var py = cy + ex * sinT + ey * cosT
                            if (i === 0) ctx.moveTo(px, py)
                            else ctx.lineTo(px, py)
                        }
                        ctx.strokeStyle = Theme.isDark ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.35) : "#000000"
                        ctx.lineWidth = Theme.isDark ? 1.3 : 1.5
                        ctx.setLineDash([4, 5])
                        ctx.stroke()
                    }
                    Component.onCompleted: requestPaint()
                    Connections {
                        target: centerCol
                        function onWidthChanged() { orbitCanvas.requestPaint() }
                        function onHeightChanged() { orbitCanvas.requestPaint() }
                    }
                    Connections {
                        target: Theme
                        function onFgChanged() { orbitCanvas.requestPaint() }
                        function onAccentChanged() { orbitCanvas.requestPaint() }
                        function onIsDarkChanged() { orbitCanvas.requestPaint() }
                    }
                }

                /* ── Big Digital Clock & Subtitle (z: 6) ─────────────────── */
                Column {
                    anchors.centerIn: parent
                    spacing: 3
                    z: 6
                    transform: Translate { y: centerCol.levitation }

                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 4

                        Text {
                            text: root.hourStr
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: Theme.fontPx(42)
                            font.weight: Font.Bold
                            color: Theme.fg
                        }

                        // Circular colon dots
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.verticalCenterOffset: -1
                            spacing: 7
                            Rectangle { width: 5; height: 5; radius: 2.5; color: Theme.fg }
                            Rectangle { width: 5; height: 5; radius: 2.5; color: Theme.fg }
                        }

                        Text {
                            text: root.minStr
                            font.family: "JetBrainsMono Nerd Font"
                            font.pixelSize: Theme.fontPx(42)
                            font.weight: Font.Bold
                            color: Theme.fg
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: root.fullDateStr
                        visible: root.showDateInClock
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: Theme.fontPx(9)
                        font.weight: Font.DemiBold
                        font.letterSpacing: 1.0
                        color: Theme.fgDim
                    }
                }

                /* ── Seconds Satellite Capsule (z: 10 in front, z: 2 when behind) ──── */
                Item {
                    id: capsuleAnchor
                    x: centerCol.posX
                    y: centerCol.posY
                    z: centerCol.zDepth >= 0 ? 10 : 2
                    scale: 0.88 + 0.16 * ((centerCol.zDepth + 1.0) / 2.0)

                    Rectangle {
                        id: secondCapsule
                        width: 32
                        height: 42
                        radius: 16
                        anchors.centerIn: parent
                        color: Theme.isDark ? Theme.accentLit : Theme.accent
                        border.color: Theme.isDark ? Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.40) : "#000000"
                        border.width: Theme.isDark ? 1 : 1.2

                        // Rotates tangentially along the planetary ellipse
                        rotation: centerCol.tangentAngle + 90

                        // Content remains upright
                        Column {
                            anchors.centerIn: parent
                            spacing: 0
                            rotation: -secondCapsule.rotation

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: centerCol.displayedSecStr
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: Theme.fontPx(13)
                                font.weight: Font.Black
                                color: Theme.isDark ? "#121118" : "#ffffff"
                            }

                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "SEC"
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: Theme.fontPx(6)
                                font.weight: Font.Bold
                                font.letterSpacing: 0.8
                                 color: Theme.isDark ? Qt.rgba(0.07, 0.06, 0.10, 0.60) : Qt.rgba(1, 1, 1, 0.65)
                            }
                        }
                    }
                }
            }

            /* Vertical Divider 2 */
            Rectangle {
                visible: !root.minimalCalendarOnly
                Layout.preferredWidth: 1.5
                Layout.fillHeight: true
                color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.16)
            }

            /* ========================================================= */
            /* 3. RIGHT COLUMN: WEATHER OVERVIEW OR SYNCED LYRICS VIEW  */
            /* ========================================================= */
            Item {
                id: rightCol
                visible: !root.minimalCalendarOnly
                Layout.preferredWidth: 235
                Layout.fillHeight: true

                property string viewMode: "lyrics" // "lyrics"

                function cycleView(delta) {
                    if (delta < 0 && rightCol.viewMode !== "lyrics") {
                        rightCol.viewMode = "lyrics"
                    } else if (delta > 0 && rightCol.viewMode !== "weather") {
                        rightCol.viewMode = "weather"
                    }
                }

                WheelHandler {
                    target: null
                    orientation: Qt.Vertical
                    onWheel: (event) => rightCol.cycleView(event.angleDelta.y)
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                    z: -1
                    onWheel: (wheel) => rightCol.cycleView(wheel.angleDelta.y)
                }

                /* View A: Weather Overview & Compact Music Overlay */
                Item {
                    id: weatherView
                    anchors.fill: parent
                    visible: opacity > 0.001
                    opacity: rightCol.viewMode === "weather" ? 1.0 : 0.0
                    scale: rightCol.viewMode === "weather" ? 1.0 : 0.95
                    enabled: rightCol.viewMode === "weather"
                    Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutQuad } }
                    Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutQuad } }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                        z: -1
                        onWheel: (wheel) => rightCol.cycleView(wheel.angleDelta.y)
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 8

                    /* Top: Weather Overview */
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 76

                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 2

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 4

                                Rectangle {
                                    width: 18
                                    height: 18
                                    radius: 9
                                    opacity: root.weatherDayIndex > 0 ? 1.0 : 0.3
                                    color: prevDayM.containsMouse && root.weatherDayIndex > 0 ? Theme.bgHover : "transparent"
                                    Text {
                                        anchors.centerIn: parent
                                        text: "‹"
                                        font.pixelSize: Theme.fontPx(13)
                                        font.weight: Font.Bold
                                        color: prevDayM.containsMouse && root.weatherDayIndex > 0 ? Theme.fg : Theme.fgDim
                                    }
                                    MouseArea {
                                        id: prevDayM
                                        anchors.fill: parent
                                        hoverEnabled: root.weatherDayIndex > 0
                                        cursorShape: root.weatherDayIndex > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        onClicked: root.prevWeatherDay()
                                        onWheel: (wheel) => rightCol.cycleView(wheel.angleDelta.y)
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: root.weatherDayTitle
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: Theme.fontPx(10)
                                    font.weight: Font.Bold
                                    font.letterSpacing: 1.2
                                    color: Theme.fg
                                    horizontalAlignment: Text.AlignHCenter
                                }

                                Rectangle {
                                    width: 18
                                    height: 18
                                    radius: 9
                                    opacity: (WeatherService.forecast && root.weatherDayIndex < WeatherService.forecast.length - 1) ? 1.0 : 0.3
                                    color: nextDayM.containsMouse && (WeatherService.forecast && root.weatherDayIndex < WeatherService.forecast.length - 1) ? Theme.bgHover : "transparent"
                                    Text {
                                        anchors.centerIn: parent
                                        text: "›"
                                        font.pixelSize: Theme.fontPx(13)
                                        font.weight: Font.Bold
                                        color: nextDayM.containsMouse ? Theme.fg : Theme.fgDim
                                    }
                                    MouseArea {
                                        id: nextDayM
                                        anchors.fill: parent
                                        hoverEnabled: (WeatherService.forecast && root.weatherDayIndex < WeatherService.forecast.length - 1)
                                        cursorShape: (WeatherService.forecast && root.weatherDayIndex < WeatherService.forecast.length - 1) ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        onClicked: root.nextWeatherDay()
                                        onWheel: (wheel) => rightCol.cycleView(wheel.angleDelta.y)
                                    }
                                }
                            }

                            /* Weather overview: Icon beside Temperature */
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.topMargin: 2
                                spacing: 8

                                Text {
                                    text: root.weatherIcon || "cloud"
                                    font.family: Theme.fontIcon
                                    font.pixelSize: 32
                                    color: Theme.accentLit
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                Column {
                                    Layout.fillWidth: true
                                    spacing: 1
                                    Layout.alignment: Qt.AlignVCenter

                                    Text {
                                        text: root.weatherTemp
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: Theme.fontPx(28)
                                        font.weight: Font.Bold
                                        color: Theme.fg
                                        lineHeight: 0.95
                                    }

                                    Row {
                                        spacing: 4
                                        Text {
                                            text: root.weatherCond
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: Theme.fontPx(10)
                                            font.weight: Font.Medium
                                            color: Theme.fgDim
                                        }
                                        Text {
                                            visible: WeatherService.city.length > 0
                                            text: "• " + WeatherService.city
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: Theme.fontPx(10)
                                            color: Theme.fgFaint
                                            elide: Text.ElideRight
                                            width: 80
                                        }
                                    }
                                }
                            }
                        }
                    }

                    /* Bottom: ONEUI-STYLED MUSIC OVERLAY WITH WAVY VISUALIZER */
                    Rectangle {
                        id: compactMusicBox
                        Layout.fillWidth: true
                        Layout.preferredHeight: 144
                        Layout.maximumHeight: 148
                        radius: 14
                        color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.94)
                        border.color: Qt.rgba(Theme.accentLit.r, Theme.accentLit.g, Theme.accentLit.b, 0.28)
                        border.width: 1
                        clip: true

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.NoButton
                            z: -1
                            onWheel: (wheel) => rightCol.cycleView(wheel.angleDelta.y)
                        }

                        /* Ambient dimmed album art background */
                        Image {
                            anchors.fill: parent
                            source: root.musicArtUrl
                            sourceSize: Qt.size(240, 200)
                            asynchronous: true
                            cache: true
                            fillMode: Image.PreserveAspectCrop
                            opacity: (status === Image.Ready) ? 0.12 : 0.0
                            visible: root.hasMusicTrack && root.musicArtUrl.length > 0 && status === Image.Ready
                            Behavior on opacity { NumberAnimation { duration: 150 } }
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 4

                            /* 1. Header: Output Device / Spotify Badge */
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 5

                                Text {
                                    text: "music_note"
                                    font.family: Theme.fontIcon
                                    font.pixelSize: 12
                                    color: Theme.accentLit
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: (Pipewire.defaultAudioSink && Pipewire.defaultAudioSink.description && Pipewire.defaultAudioSink.description.length > 0)
                                        ? Pipewire.defaultAudioSink.description
                                        : (root.mprisPlayer && root.mprisPlayer.identity ? root.mprisPlayer.identity : "Audio Output")
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: Theme.fontPx(9)
                                    font.weight: Font.DemiBold
                                    color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.75)
                                    elide: Text.ElideRight
                                }
                            }

                            /* 2. Track Info & Album Art Thumbnail */
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1

                                    Text {
                                        Layout.fillWidth: true
                                        text: root.hasMusicTrack ? root.musicTitle : "No Media Playing"
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: Theme.fontPx(11)
                                        font.weight: Font.Bold
                                        color: Theme.fg
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: root.hasMusicTrack ? (root.musicArtist || "Unknown Artist") : "Waiting for playback..."
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: Theme.fontPx(8)
                                        font.weight: Font.Normal
                                        color: Theme.accent
                                        elide: Text.ElideRight
                                    }
                                }

                                Rectangle {
                                    Layout.preferredWidth: 28
                                    Layout.preferredHeight: 28
                                    radius: 6
                                    color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, 0.90)
                                    border.color: Qt.rgba(Theme.accentLit.r, Theme.accentLit.g, Theme.accentLit.b, 0.35)
                                    border.width: 1
                                    clip: true

                                    Image {
                                        anchors.fill: parent
                                        source: root.musicArtUrl
                                        sourceSize: Qt.size(64, 64)
                                        asynchronous: true
                                        cache: true
                                        visible: root.hasMusicTrack && root.musicArtUrl.length > 0 && status === Image.Ready
                                        fillMode: Image.PreserveAspectCrop
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        text: "music_note"
                                        font.family: Theme.fontIcon
                                        font.pixelSize: 14
                                        color: root.isMusicPlaying ? Theme.accentLit : Theme.fgDim
                                        visible: !root.hasMusicTrack || root.musicArtUrl.length === 0
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (root.mprisPlayer) root.mprisPlayer.togglePlaying()
                                        }
                                        onWheel: (wheel) => rightCol.cycleView(wheel.angleDelta.y)
                                    }
                                }
                            }

                            /* 3. Wavy Visualizer & Interactive Seek Bar */
                            WavySeekBar {
                                Layout.fillWidth: true
                                currentPosition: root.musicPosition
                                totalLength: root.musicLength
                                isPlaying: root.isMusicPlaying
                                waveHeight: 14
                                barHeight: 7
                                timeLabelSize: 7
                                accentColor: Theme.accent
                                accentLitColor: Theme.accentLit
                                onSeekRequested: (frac) => {
                                    if (root.mprisPlayer && root.musicLength > 0) {
                                        root.mprisPlayer.position = frac * root.musicLength
                                    }
                                }
                            }

                            /* 4. Transport Controls (Shuffle, Prev, Play/Pause, Next, Loop) */
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignHCenter

                                Item { Layout.fillWidth: true }

                                // Shuffle
                                Rectangle {
                                    Layout.preferredWidth: 20
                                    Layout.preferredHeight: 20
                                    radius: 10
                                    color: shufCM.containsMouse ? Theme.bgHover : "transparent"

                                    Text {
                                        anchors.centerIn: parent
                                        text: "shuffle"
                                        font.family: Theme.fontIcon
                                        font.pixelSize: 12
                                        color: shufCM.containsMouse ? Theme.accentLit : Theme.fgDim
                                    }

                                    MouseArea {
                                        id: shufCM
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Quickshell.execDetached(["playerctl", "shuffle", "Toggle"])
                                        onWheel: (wheel) => rightCol.cycleView(wheel.angleDelta.y)
                                    }
                                }

                                Item { Layout.preferredWidth: 6 }

                                // Previous
                                Rectangle {
                                    Layout.preferredWidth: 22
                                    Layout.preferredHeight: 22
                                    radius: 11
                                    color: prevCM.containsMouse ? Theme.bgHover : "transparent"

                                    Text {
                                        anchors.centerIn: parent
                                        text: "skip_previous"
                                        font.family: Theme.fontIcon
                                        font.pixelSize: 14
                                        color: prevCM.containsMouse ? Theme.accentLit : Theme.fg
                                    }

                                    MouseArea {
                                        id: prevCM
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (root.mprisPlayer) root.mprisPlayer.previous()
                                        }
                                        onWheel: (wheel) => rightCol.cycleView(wheel.angleDelta.y)
                                    }
                                }

                                Item { Layout.preferredWidth: 6 }

                                // Play / Pause
                                Rectangle {
                                    Layout.preferredWidth: 26
                                    Layout.preferredHeight: 26
                                    radius: 13
                                    color: playCM.containsMouse ? Theme.accentLit : Qt.rgba(Theme.accentLit.r, Theme.accentLit.g, Theme.accentLit.b, 0.25)
                                    border.color: Theme.accentLit
                                    border.width: 1

                                    Text {
                                        anchors.centerIn: parent
                                        text: root.isMusicPlaying ? "pause" : "play_arrow"
                                        font.family: Theme.fontIcon
                                        font.pixelSize: 14
                                        color: playCM.containsMouse ? (Theme.isDark ? "#121118" : "#ffffff") : Theme.fg
                                    }

                                    MouseArea {
                                        id: playCM
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (root.mprisPlayer) root.mprisPlayer.togglePlaying()
                                        }
                                        onWheel: (wheel) => rightCol.cycleView(wheel.angleDelta.y)
                                    }
                                }

                                Item { Layout.preferredWidth: 6 }

                                // Next
                                Rectangle {
                                    Layout.preferredWidth: 22
                                    Layout.preferredHeight: 22
                                    radius: 11
                                    color: nextCM.containsMouse ? Theme.bgHover : "transparent"

                                    Text {
                                        anchors.centerIn: parent
                                        text: "skip_next"
                                        font.family: Theme.fontIcon
                                        font.pixelSize: 14
                                        color: nextCM.containsMouse ? Theme.accentLit : Theme.fg
                                    }

                                    MouseArea {
                                        id: nextCM
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (root.mprisPlayer) root.mprisPlayer.next()
                                        }
                                        onWheel: (wheel) => rightCol.cycleView(wheel.angleDelta.y)
                                    }
                                }

                                Item { Layout.preferredWidth: 6 }

                                // Loop
                                Rectangle {
                                    Layout.preferredWidth: 20
                                    Layout.preferredHeight: 20
                                    radius: 10
                                    color: loopCM.containsMouse ? Theme.bgHover : "transparent"

                                    Text {
                                        anchors.centerIn: parent
                                        text: "repeat"
                                        font.family: Theme.fontIcon
                                        font.pixelSize: 12
                                        color: loopCM.containsMouse ? Theme.accentLit : Theme.fgDim
                                    }

                                    MouseArea {
                                        id: loopCM
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Quickshell.execDetached(["playerctl", "loop", "Track"])
                                        onWheel: (wheel) => rightCol.cycleView(wheel.angleDelta.y)
                                    }
                                }

                                Item { Layout.fillWidth: true }
                            }
                        }
                    }
                }
            }

                /* View B: Full Synced Lyrics Display */
                Item {
                    id: lyricsView
                    anchors.fill: parent
                    visible: opacity > 0.001
                    opacity: rightCol.viewMode === "lyrics" ? 1.0 : 0.0
                    scale: rightCol.viewMode === "lyrics" ? 1.0 : 0.95
                    enabled: rightCol.viewMode === "lyrics"
                    Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutQuad } }
                    Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutQuad } }

                    Item {
                        anchors.fill: parent
                        clip: true

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.NoButton
                            z: -1
                            onWheel: (wheel) => rightCol.cycleView(wheel.angleDelta.y)
                        }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 8
                            spacing: 4

                            /* Top Bar: Title + Switch back to Weather */
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 4

                                Text {
                                    text: "music_note"
                                    font.family: Theme.fontIcon
                                    font.pixelSize: 12
                                    color: Theme.accent
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: LyricsService.hasTrack ? LyricsService.trackTitle : "Lyrics"
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: Theme.fontPx(9)
                                    font.weight: Font.Bold
                                    color: Theme.fg
                                    elide: Text.ElideRight
                                }

                                Text {
                                    visible: LyricsService.hasTrack && LyricsService.trackArtist.length > 0
                                    text: LyricsService.trackArtist
                                    font.family: "JetBrainsMono Nerd Font"
                                    font.pixelSize: Theme.fontPx(8)
                                    color: Theme.fgDim
                                    elide: Text.ElideRight
                                    Layout.maximumWidth: 80
                                }
                            }

                            /* Divider */
                            Rectangle {
                                Layout.fillWidth: true
                                height: 1
                                color: Qt.rgba(Theme.fg.r, Theme.fg.g, Theme.fg.b, 0.08)
                            }

                            /* Lyrics Content Area */
                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                clip: true

                                // 1. Lyrics Available
                                ColumnLayout {
                                    anchors.centerIn: parent
                                    width: parent.width
                                    spacing: 6
                                    visible: LyricsService.hasTrack && LyricsService.hasLyrics

                                    // Previous line
                                    Text {
                                        Layout.fillWidth: true
                                        text: LyricsService.prevLine || ""
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: Theme.fontPx(8)
                                        font.weight: Font.Normal
                                        color: Qt.alpha(Theme.fg, 0.35)
                                        horizontalAlignment: Text.AlignHCenter
                                        wrapMode: Text.Wrap
                                        elide: Text.ElideRight
                                        maximumLineCount: 2
                                        visible: text.length > 0
                                    }

                                    // Current line (Highlighted)
                                    Item {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: curLineTxt.contentHeight + 8

                                        Text {
                                            id: curLineTxt
                                            anchors.centerIn: parent
                                            width: parent.width - 10
                                            text: LyricsService.currentLine || "♪ ♫ ♪"
                                            font.family: "JetBrainsMono Nerd Font"
                                            font.pixelSize: Theme.fontPx(11)
                                            font.weight: Font.Bold
                                            color: Theme.accentLit
                                            horizontalAlignment: Text.AlignHCenter
                                            wrapMode: Text.Wrap
                                            elide: Text.ElideRight
                                            maximumLineCount: 3
                                        }
                                    }

                                    // Next line
                                    Text {
                                        Layout.fillWidth: true
                                        text: LyricsService.nextLine || ""
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: Theme.fontPx(8)
                                        font.weight: Font.Normal
                                        color: Qt.alpha(Theme.fg, 0.40)
                                        horizontalAlignment: Text.AlignHCenter
                                        wrapMode: Text.Wrap
                                        elide: Text.ElideRight
                                        maximumLineCount: 2
                                        visible: text.length > 0
                                    }
                                }

                                // 2. Track playing but no lyrics found
                                ColumnLayout {
                                    anchors.centerIn: parent
                                    width: parent.width
                                    spacing: 4
                                    visible: LyricsService.hasTrack && !LyricsService.hasLyrics

                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: "headphones"
                                        font.family: Theme.fontIcon
                                        font.pixelSize: 22
                                        color: Qt.alpha(Theme.fg, 0.3)
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: LyricsService.trackTitle
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: Theme.fontPx(9)
                                        font.weight: Font.Bold
                                        color: Theme.fg
                                        horizontalAlignment: Text.AlignHCenter
                                        elide: Text.ElideRight
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: "No synced lyrics available"
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: Theme.fontPx(8)
                                        color: Theme.fgDim
                                        horizontalAlignment: Text.AlignHCenter
                                    }
                                }

                                // 3. Nothing playing
                                ColumnLayout {
                                    anchors.centerIn: parent
                                    width: parent.width
                                    spacing: 4
                                    visible: !LyricsService.hasTrack

                                    Text {
                                        Layout.alignment: Qt.AlignHCenter
                                        text: "music_note"
                                        font.family: Theme.fontIcon
                                        font.pixelSize: 22
                                        color: Qt.alpha(Theme.fg, 0.25)
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: "Nothing Playing"
                                        font.family: "JetBrainsMono Nerd Font"
                                        font.pixelSize: Theme.fontPx(9)
                                        font.weight: Font.Bold
                                        color: Theme.fgDim
                                        horizontalAlignment: Text.AlignHCenter
                                    }
                                }
                            }

                            /* Bottom Mini Playback Controls */
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                visible: LyricsService.hasTrack

                                Rectangle {
                                    width: 16
                                    height: 16
                                    radius: 8
                                    color: lyrPrevM.containsMouse ? Theme.bgHover : "transparent"
                                    Text {
                                        anchors.centerIn: parent
                                        text: "skip_previous"
                                        font.family: Theme.fontIcon
                                        font.pixelSize: 11
                                        color: Theme.fgDim
                                    }
                                    MouseArea {
                                        id: lyrPrevM
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: { if (LyricsService.activePlayer) LyricsService.activePlayer.previous() }
                                        onWheel: (wheel) => rightCol.cycleView(wheel.angleDelta.y)
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 2.5
                                    radius: 1.25
                                    color: Qt.alpha(Theme.fg, 0.15)
                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.top: parent.top
                                        anchors.bottom: parent.bottom
                                        width: parent.width * (LyricsService.totalLength > 0 ? Math.min(1.0, LyricsService.currentPosition / LyricsService.totalLength) : 0)
                                        radius: 1.25
                                        color: Theme.accent
                                    }
                                }

                                Rectangle {
                                    width: 18
                                    height: 18
                                    radius: 9
                                    color: Theme.accent
                                    Text {
                                        anchors.centerIn: parent
                                        text: LyricsService.isPlaying ? "pause" : "play_arrow"
                                        font.family: Theme.fontIcon
                                        font.pixelSize: 12
                                        color: Theme.isDark ? "#121118" : "#ffffff"
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: { if (LyricsService.activePlayer) LyricsService.activePlayer.togglePlaying() }
                                        onWheel: (wheel) => rightCol.cycleView(wheel.angleDelta.y)
                                    }
                                }

                                Rectangle {
                                    width: 16
                                    height: 16
                                    radius: 8
                                    color: lyrNextM.containsMouse ? Theme.bgHover : "transparent"
                                    Text {
                                        anchors.centerIn: parent
                                        text: "skip_next"
                                        font.family: Theme.fontIcon
                                        font.pixelSize: 11
                                        color: Theme.fgDim
                                    }
                                    MouseArea {
                                        id: lyrNextM
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: { if (LyricsService.activePlayer) LyricsService.activePlayer.next() }
                                        onWheel: (wheel) => rightCol.cycleView(wheel.angleDelta.y)
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
