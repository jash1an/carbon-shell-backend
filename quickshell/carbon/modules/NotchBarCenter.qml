import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import "../Singletons"
import "../components"

/**
 * NotchBarCenter: Top-attached curved notch for Center (Clock & Music)
 *   - Bold two-tone Titan clock (10:19)
 *   - Vertical separator (|)
 *   - Animated spinning vinyl disc / album art
 *   - Two-line track title & artist (Do I Wanna Know? / Arctic Monkeys)
 */
NotchContainer {
    id: root

    property bool isExpanded: false
    clip: true
    bottomRadius: isExpanded ? Theme.px(20) : Theme.px(14)
    implicitHeight: isExpanded ? Theme.px(270) : ((root.dragActive || root.isUploading) ? Theme.px(48) : Theme.px(34))
    implicitWidth: isExpanded ? Theme.px(820) : (contentImplicitWidth + (leftFillet ? filletRadius : 0) + (rightFillet ? filletRadius : 0) + (horizontalPadding * 2))

    earWidth: Theme.px(20)
    contentSpacing: Theme.px(8)

    signal openMusicHover()
    signal closeMusicHover()
    signal toggleMusic()
    signal openMusic()
    signal toggleControls()
    signal toggleCenterDashboard()
    signal openCenterDashboard()
    signal closeCenterDashboard()

    property bool showVinylDisc: true
    property bool showEqualizer: true

    readonly property bool hudActive: HudService.active

    focus: root.isExpanded
    Keys.enabled: root.isExpanded
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Escape) {
            root.closeCenterDashboard()
            event.accepted = true
        }
    }
    Keys.onEscapePressed: (event) => {
        root.closeCenterDashboard()
        event.accepted = true
    }

    onIsExpandedChanged: {
        if (root.isExpanded) {
            root.forceActiveFocus()
        }
    }

    mouseArea.hoverEnabled: false
    mouseArea.cursorShape: Qt.PointingHandCursor
    mouseArea.acceptedButtons: Qt.LeftButton | Qt.RightButton
    mouseArea.onClicked: (mouse) => {
        if (root.hudActive) {
            HudService.dismiss()
            return
        }
        if (mouse.button === Qt.RightButton) {
            root.togglePlayPause()
        } else {
            root.toggleCenterDashboard()
        }
    }

    /* ── Live Clock State ────────────────────────────────────────────── */
    property var currentTime: new Date()
    property int currentHourRaw: currentTime.getHours()
    property int currentHour12: {
        let h = root.currentHourRaw % 12
        return h === 0 ? 12 : h
    }
    property string hourStr: (root.currentHour12 < 10 ? "0" : "") + root.currentHour12
    property string minStr: {
        let m = root.currentTime.getMinutes()
        return (m < 10 ? "0" : "") + m
    }

    Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: root.currentTime = new Date()
    }

    /* ── MPRIS State ─────────────────────────────────────────────────── */
    readonly property var players: Mpris.players.values !== undefined ? Mpris.players.values : Mpris.players
    property var activePlayer: null

    function resolveActivePlayer() {
        if (!root.players || root.players.length === 0) return null
        for (let i = 0; i < root.players.length; i++) {
            if (root.players[i].playbackState === MprisPlaybackState.Playing)
                return root.players[i]
        }
        for (let i = 0; i < root.players.length; i++) {
            if (root.players[i].playbackState === MprisPlaybackState.Paused
                && (root.players[i].trackTitle || "").length > 0)
                return root.players[i]
        }
        return root.players[0]
    }

    Timer {
        interval: 1000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.activePlayer = root.resolveActivePlayer()
    }

    trackTitle: activePlayer ? (activePlayer.trackTitle || "") : ""
    readonly property string trackArtist: activePlayer ? (activePlayer.trackArtist || "") : ""
    readonly property string artUrl: activePlayer ? (activePlayer.trackArtUrl || "") : ""
    isPlaying: activePlayer && activePlayer.playbackState === MprisPlaybackState.Playing
    readonly property bool hasTrack: root.activePlayer !== null && root.trackTitle.trim().length > 0

    function togglePlayPause() {
        if (root.activePlayer) root.activePlayer.togglePlaying()
    }

    property string barContent: "both"

    /* ── Content Inside Notch ────────────────────────────────────────── */
    content: [
        Item {
            id: notchContentContainer
            anchors.verticalCenter: parent.verticalCenter
            implicitHeight: Theme.px(26)
            implicitWidth: root.hudActive ? dynamicPill.implicitWidth : normalNotchRow.implicitWidth
            opacity: root.isExpanded ? 0.0 : 1.0
            visible: opacity > 0.01

            Behavior on opacity {
                NumberAnimation { duration: 180; easing.type: Easing.OutQuad }
            }

            Behavior on implicitWidth {
                NumberAnimation { duration: 280; easing.type: Easing.OutCubic }
            }

            /* HUD Mode: Dynamic Island Pill */
            DynamicIslandPill {
                id: dynamicPill
                anchors.centerIn: parent
                opacity: root.hudActive ? 1.0 : 0.0
                visible: opacity > 0.01

                Behavior on opacity {
                    NumberAnimation { duration: 220; easing.type: Easing.OutQuad }
                }
            }

            /* Normal Mode: Clock & Music Row */
            Row {
                id: normalNotchRow
                anchors.centerIn: parent
                spacing: Theme.px(8)
                opacity: root.hudActive ? 0.0 : 1.0
                visible: opacity > 0.01

                Behavior on opacity {
                    NumberAnimation { duration: 200; easing.type: Easing.OutQuad }
                }

                /* 1. Center Island Clock (Dynamic Design - Click to toggle Dashboard) */
                Item {
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: centerClockItem.implicitWidth
            implicitHeight: centerClockItem.implicitHeight
            visible: root.barContent !== "music"
            z: 10

            CenterClock {
                id: centerClockItem
                anchors.centerIn: parent
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleCenterDashboard()
            }
        }

        /* 2. Vertical Divider */
        Rectangle {
            width: Math.max(1, Theme.px(1.5))
            height: Theme.px(16)
            color: Qt.alpha(Theme.fg, 0.40)
            anchors.verticalCenter: parent.verticalCenter
            visible: root.barContent === "both"
        }

        /* 3. Music Section (Disc + Track Info) */
        Item {
            anchors.verticalCenter: parent.verticalCenter
            implicitHeight: Theme.px(26)
            implicitWidth: musicRow.implicitWidth
            visible: root.barContent !== "clock"

            Row {
                id: musicRow
                spacing: Theme.px(8)
                anchors.verticalCenter: parent.verticalCenter

                /* Spinning Vinyl Disc / Album art */
                Rectangle {
                    id: discContainer
                    width: Theme.px(22)
                    height: Theme.px(22)
                    radius: Theme.px(11)
                    color: Theme.bgAlt
                    border.color: Theme.accent
                    border.width: 1.5
                    anchors.verticalCenter: parent.verticalCenter
                    clip: true
                    visible: root.showVinylDisc

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.togglePlayPause()
                    }

                    Image {
                        id: albumArtImg
                        anchors.fill: parent
                        source: root.artUrl
                        sourceSize: Qt.size(Theme.px(44), Theme.px(44))
                        visible: root.hasTrack && root.artUrl.length > 0
                        fillMode: Image.PreserveAspectCrop
                    }

                    Item {
                        id: vinylDisc
                        anchors.fill: parent
                        visible: !root.hasTrack || root.artUrl.length === 0

                        Text {
                            anchors.centerIn: parent
                            text: "music_note"
                            font.family: Theme.fontIcon
                            font.pixelSize: Theme.fontPx(14)
                            color: Theme.accent
                        }
                    }
                }

                /* Dynamic Island 4-Bar Equalizer Waveform */
                Row {
                    id: eqWaveform
                    spacing: Math.max(1, Theme.px(2))
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.showEqualizer && root.hasTrack

                    Repeater {
                        model: [
                            { minH: Theme.px(3), maxH: Theme.px(13), dur: 380 },
                            { minH: Theme.px(4), maxH: Theme.px(15), dur: 520 },
                            { minH: Theme.px(3), maxH: Theme.px(11), dur: 440 },
                            { minH: Theme.px(4), maxH: Theme.px(14), dur: 610 }
                        ]

                        delegate: Rectangle {
                            id: eqBar
                            required property var modelData
                            required property int index

                            width: Math.max(1, Theme.px(2.5))
                            radius: Math.max(1, Theme.px(1.25))
                            color: Theme.accent
                            anchors.verticalCenter: parent.verticalCenter

                            height: root.isPlaying ? modelData.minH : Math.max(1, Theme.px(2.5))

                            SequentialAnimation on height {
                                running: root.isPlaying && root.visible
                                loops: Animation.Infinite
                                NumberAnimation { to: eqBar.modelData.maxH; duration: eqBar.modelData.dur; easing.type: Easing.InOutQuad }
                                NumberAnimation { to: eqBar.modelData.minH; duration: eqBar.modelData.dur * 0.85; easing.type: Easing.InOutQuad }
                            }

                            Behavior on height {
                                enabled: !root.isPlaying
                                NumberAnimation { duration: 250; easing.type: Easing.OutQuad }
                            }
                        }
                    }
                }

                /* Song & Artist Info (Two lines) */
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0

                    Text {
                        text: root.hasTrack ? root.trackTitle : "Nothing Playing"
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontPx(11)
                        font.weight: Font.Bold
                        color: root.hasTrack ? Theme.fg : Theme.fgDim
                        elide: Text.ElideRight
                        width: Math.min(implicitWidth, Theme.px(150))
                    }

                    Text {
                        text: root.hasTrack ? root.trackArtist : ""
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontPx(9)
                        font.weight: Font.Medium
                        color: Theme.fgDim
                        elide: Text.ElideRight
                        width: Math.min(implicitWidth, Theme.px(150))
                        visible: text.length > 0
                    }
                }
            }
        }
    }
    }
    ]

    CenterDashboard {
        id: dashContent
        parent: root
        z: 5
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.leftMargin: (root.leftFillet && root.filletRadius > 0) ? root.filletRadius : 0
        anchors.right: parent.right
        anchors.rightMargin: (root.rightFillet && root.filletRadius > 0) ? root.filletRadius : 0
        showBackground: false
        open: root.isExpanded
        visible: opacity > 0.01
        opacity: root.isExpanded ? 1.0 : 0.0
        scale: root.isExpanded ? 1.0 : 0.98
        Behavior on opacity {
            NumberAnimation { duration: root.isExpanded ? 220 : 150; easing.type: Easing.OutCubic }
        }
        Behavior on scale {
            NumberAnimation { duration: root.isExpanded ? 260 : 180; easing.type: Easing.OutCubic }
        }
        onCloseRequested: root.closeCenterDashboard()
    }
}
