import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.UPower
import Quickshell.Services.Mpris
import Quickshell.Services.Notifications
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray
import "Singletons"
import "components"
import "modules"
import "modules/lock"

/**
 * Carbon — a full Quickshell shell with a single left vertical bar.
 *
 * Each monitor gets one layer-shell window pinned to the left edge that
 * reserves its own width (exclusiveZone), so tiled windows always sit beside
 * it. Modules stack vertically inside the bar; nothing else in the shell has
 * its own surface yet, so everything lives in this one window.
 */
ShellRoot {
    id: root

    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string carbonConfigDir: Quickshell.env("CARBON_CONFIG_DIR") || (root.home + "/.config/carbon")
    property bool launcherOpen: false
    property bool wallpaperPickerOpen: false
    property string wallpaperSource: "local"
    property var wallpaperModItem: null

    property bool spotlightOpen: false
    function openSpotlight() {
        root.closeAllPopupsExcept("spotlight")
        root.spotlightOpen = true
    }
    function closeSpotlight() {
        root.spotlightOpen = false
    }
    function toggleSpotlight() {
        if (root.spotlightOpen) root.closeSpotlight()
        else root.openSpotlight()
    }

    function closeAllPopupsExcept(keep) {
        if (keep !== "spotlight") { root.spotlightOpen = false }
        if (keep !== "mixer") { root.mixerOpen = false; root.mixerPinned = false }
        if (keep !== "brightness") { root.brightnessOpen = false; root.brightnessPinned = false }
        if (keep !== "battery") { root.batteryOpen = false; root.batteryPinned = false }
        if (keep !== "tray") { root.trayOpen = false; root.trayPinned = false }
        if (keep !== "music") { root.musicOpen = false; root.musicPinned = false; root.musicHovered = false }
        if (keep !== "smallMusic") { root.smallMusicOpen = false; root.smallMusicPinned = false; root.smallMusicHovered = false }
        if (keep !== "wifi") { root.wifiOpen = false; root.wifiPinned = false }
        if (keep !== "bt") { root.btOpen = false; root.btPinned = false }
        if (keep !== "calendar") { root.calendarOpen = false; root.calendarPinned = false }
        if (keep !== "centerDashboard") { root.centerDashboardOpen = false; root.centerDashboardPinned = false }
        if (keep !== "controls") { root.controlsVisible = false; root.controlsPinned = false }
    }

    property bool smallMusicOpen: false
    property bool smallMusicPinned: false
    property bool smallMusicHovered: false
    function openSmallMusic() {
        root.closeAllPopupsExcept("smallMusic")
        root.smallMusicOpen = true
    }
    function closeSmallMusic() { root.smallMusicOpen = false; root.smallMusicPinned = false }
    function toggleSmallMusic() {
        if (root.smallMusicOpen) {
            root.closeSmallMusic()
        } else {
            root.closeAllPopupsExcept("smallMusic")
            root.smallMusicPinned = true
            root.smallMusicOpen = true
        }
    }

    Timer {
        id: smallMusicLeaveTimer
        interval: 350
        onTriggered: {
            if ((root.barMode !== "minimal" || !root.smallMusicPinned) && !root.smallMusicHovered) root.closeSmallMusic()
        }
    }

    /* Calendar popup state */
    property bool calendarOpen: false
    property bool calendarPinned: false
    property bool centerDashboardAwaitingHover: false
    function openCalendar() {
        if (root.barMode === "nucleus") {
            if (root.nucleusHubItem) root.nucleusHubItem.openCalendarMode()
            return
        }
        centerDashboardLeaveTimer.stop()
        root.centerDashboardPinned = false
        root.centerDashboardAwaitingHover = true
        root.openCenterDashboard()
        centerDashboardLeaveTimer.interval = 1000
        centerDashboardLeaveTimer.restart()
    }
    function closeCalendar() {
        if (root.barMode === "nucleus") {
            if (root.nucleusHubItem) root.nucleusHubItem.activeMode = "hub"
            return
        }
        root.closeCenterDashboard()
    }
    function toggleCalendar() {
        if (root.barMode === "nucleus") {
            if (root.nucleusHubItem) {
                if (root.nucleusHubItem.hubOpen && root.nucleusHubItem.activeMode === "calendar") {
                    root.nucleusHubItem.close()
                } else {
                    root.nucleusHubItem.openCalendarMode()
                }
            }
            return
        }
        root.toggleCenterDashboard()
    }

    onCalendarOpenChanged: {
        if (root.calendarOpen) { calendarOutTimer.stop(); root.calendarHidden = false }
        else { calendarOutTimer.restart() }
    }

    Timer {
        id: calendarLeaveTimer
        interval: 400
        onTriggered: {
            if (!root.calendarPinned && !root.calendarHovered) root.closeCalendar()
        }
    }

    Timer {
        id: calendarOutTimer
        interval: 90
        onTriggered: root.calendarHidden = true
    }

    /* Center Dashboard (Top-Center Calendar, Time & Weather) State */
    property bool centerDashboardOpen: false
    property bool centerDashboardPinned: false
    property bool centerDashboardHovered: false
    property bool centerDashboardHidden: true

    function openCenterDashboard() {
        centerDashboardLeaveTimer.stop()
        root.closeAllPopupsExcept("centerDashboard")
        root.centerDashboardOpen = true
    }
    function closeCenterDashboard(force) {
        root.centerDashboardPinned = false
        root.centerDashboardOpen = false
    }
    function toggleCenterDashboard() {
        if (root.centerDashboardOpen && root.centerDashboardPinned) {
            root.centerDashboardPinned = false
            root.centerDashboardOpen = false
        } else {
            root.closeAllPopupsExcept("centerDashboard")
            root.centerDashboardPinned = true
            root.centerDashboardOpen = true
        }
    }

    onCenterDashboardOpenChanged: {
        if (root.centerDashboardOpen) {
            centerDashboardOutTimer.stop()
            root.centerDashboardHidden = false
        } else {
            centerDashboardOutTimer.restart()
        }
    }

    Timer {
        id: centerDashboardLeaveTimer
        interval: 450
        onTriggered: {
            if (!root.centerDashboardPinned && !root.centerDashboardHovered) {
                root.centerDashboardAwaitingHover = false
                root.closeCenterDashboard()
            }
        }
    }

    Timer {
        id: centerDashboardOutTimer
        interval: 180
        onTriggered: root.centerDashboardHidden = true
    }

    /* Mixer popup state: open/pinned (click) or hover-release behaviour. */
    property bool mixerOpen: false
    property bool mixerPinned: false
    property bool mixerHovered: false
    property bool mixerHidden: true

    function openMixer() {
        root.closeAllPopupsExcept("mixer")
        root.mixerOpen = true
    }
    function closeMixer() { root.mixerOpen = false; root.mixerPinned = false }
    function toggleMixer() {
        if (root.mixerOpen) { root.closeMixer() }
        else { root.closeAllPopupsExcept("mixer"); root.mixerPinned = true; root.mixerOpen = true }
    }

    onMixerOpenChanged: {
        if (root.mixerOpen) { mixerOutTimer.stop(); root.mixerHidden = false }
        else { mixerOutTimer.restart() }
    }

    /* Hover-leave: close briefly after the pointer leaves both the bar icon
     * and the popup, unless the popup is pinned (clicked). */
    Timer {
        id: mixerLeaveTimer
        interval: 350
        onTriggered: {
            if (!root.mixerPinned && !root.mixerHovered) root.closeMixer()
        }
    }

    /* Fade-out grace: keep the window alive a moment so the close animation
     * is visible before the layer surface unmaps. */
    Timer {
        id: mixerOutTimer
        interval: 90
        onTriggered: root.mixerHidden = true
    }

    /* Brightness popup state: open/pinned (click) or hover-release behaviour. */
    property bool brightnessOpen: false
    property bool brightnessPinned: false
    property bool brightnessHovered: false
    property bool brightnessHidden: true

    function openBrightness() {
        root.closeAllPopupsExcept("brightness")
        root.brightnessOpen = true
    }
    function closeBrightness() { root.brightnessOpen = false; root.brightnessPinned = false }
    function toggleBrightness() {
        if (root.brightnessOpen) { root.closeBrightness() }
        else { root.closeAllPopupsExcept("brightness"); root.brightnessPinned = true; root.brightnessOpen = true }
    }

    onBrightnessOpenChanged: {
        if (root.brightnessOpen) { brightnessOutTimer.stop(); root.brightnessHidden = false }
        else { brightnessOutTimer.restart() }
    }

    Timer {
        id: brightnessLeaveTimer
        interval: 350
        onTriggered: {
            if (!root.brightnessPinned && !root.brightnessHovered) root.closeBrightness()
        }
    }

    Timer {
        id: brightnessOutTimer
        interval: 90
        onTriggered: root.brightnessHidden = true
    }

    /* Battery popup state: open/pinned (click) or hover-release behaviour. */
    property bool batteryOpen: false
    property bool batteryPinned: false
    property bool batteryHovered: false
    property bool batteryHidden: true

    function openBattery() {
        root.closeAllPopupsExcept("battery")
        root.batteryOpen = true
    }
    function closeBattery() {
        root.batteryOpen = false
        root.batteryPinned = false
    }
    function toggleBattery() {
        if (root.batteryOpen) {
            root.closeBattery()
        } else {
            root.closeAllPopupsExcept("battery")
            root.batteryPinned = true
            root.batteryOpen = true
        }
    }

    onBatteryOpenChanged: {
        if (root.batteryOpen) { batteryOutTimer.stop(); root.batteryHidden = false }
        else { batteryOutTimer.restart() }
    }

    Timer {
        id: batteryLeaveTimer
        interval: 350
        onTriggered: {
            if (!root.batteryPinned && !root.batteryHovered) root.closeBattery()
        }
    }

    Timer {
        id: batteryOutTimer
        interval: 90
        onTriggered: root.batteryHidden = true
    }

    /* Notification compatibility forwarders (integrated in QuickSettings/Controls) */
    function openNotif() { root.openControls() }
    function closeNotif() { root.closeControls() }
    function toggleNotif() { root.toggleControls() }
    property bool trayOpen: false
    property bool trayPinned: false
    property bool trayHovered: false
    property bool trayHidden: true

    function openTray() {
        root.closeAllPopupsExcept("tray")
        root.trayOpen = true
    }
    function closeTray() { root.trayOpen = false; root.trayPinned = false }
    function toggleTray() {
        if (root.trayOpen) {
            root.closeTray()
        } else {
            root.closeAllPopupsExcept("tray")
            root.trayPinned = true
            root.trayOpen = true
        }
    }

    onTrayOpenChanged: {
        if (root.trayOpen) { trayOutTimer.stop(); root.trayHidden = false }
        else { trayOutTimer.restart() }
    }

    Timer {
        id: trayLeaveTimer
        interval: 350
        onTriggered: {
            if (!root.trayPinned && !root.trayHovered) root.closeTray()
        }
    }

    Timer {
        id: trayOutTimer
        interval: 90
        onTriggered: root.trayHidden = true
    }

    /* Wifi popup state */
    property bool wifiOpen: false
    property bool wifiPinned: false
    property bool wifiHovered: false
    property bool wifiHidden: true

    function openWifi() {
        root.closeAllPopupsExcept("wifi")
        if (!wifiProbe.running) wifiProbe.running = true
        if (!wifiNameProbe.running) wifiNameProbe.running = true
        root.wifiOpen = true
    }
    function closeWifi() { root.wifiOpen = false; root.wifiPinned = false }
    function toggleWifi() {
        if (root.wifiOpen) { root.closeWifi() }
        else { root.closeAllPopupsExcept("wifi"); root.wifiPinned = true; root.wifiOpen = true }
    }

    onWifiOpenChanged: {
        if (root.wifiOpen) { wifiOutTimer.stop(); root.wifiHidden = false }
        else { wifiOutTimer.restart() }
    }

    Timer {
        id: wifiLeaveTimer
        interval: 350
        onTriggered: {
            if (!root.wifiPinned && !root.wifiHovered) root.closeWifi()
        }
    }

    Timer {
        id: wifiOutTimer
        interval: 90
        onTriggered: root.wifiHidden = true
    }

    /* Bluetooth popup state */
    property bool btOpen: false
    property bool btPinned: false
    property bool btHovered: false
    property bool btHidden: true

    function openBt() {
        root.closeAllPopupsExcept("bt")
        if (!btProbe.running) btProbe.running = true
        if (!btNameProbe.running) btNameProbe.running = true
        root.btOpen = true
    }
    function closeBt() { root.btOpen = false; root.btPinned = false }
    function toggleBt() {
        if (root.btOpen) { root.closeBt() }
        else { root.closeAllPopupsExcept("bt"); root.btPinned = true; root.btOpen = true }
    }

    onBtOpenChanged: {
        if (root.btOpen) { btOutTimer.stop(); root.btHidden = false }
        else { btOutTimer.restart() }
    }

    Timer {
        id: btLeaveTimer
        interval: 350
        onTriggered: {
            if (!root.btPinned && !root.btHovered) root.closeBt()
        }
    }

    Timer {
        id: btOutTimer
        interval: 90
        onTriggered: root.btHidden = true
    }

    /* Wifi & Bluetooth System Probes */
    property bool wifiOn: true
    property string wifiName: ""
    Process {
        id: wifiProbe
        command: ["sh", "-c", "nmcli radio wifi | tr -d ' \\n\\r'"]
        stdout: StdioCollector { id: wifiC; waitForEnd: true }
        onExited: root.wifiOn = String(wifiC.text).trim() === "enabled"
    }
    Process {
        id: wifiNameProbe
        command: ["sh", "-c", "wifi=$(nmcli -t -f IN-USE,SSID dev wifi 2>/dev/null | grep -E '^\\*:|^yes:' | head -1 | cut -d: -f2-); [ -n \"$wifi\" ] && echo \"$wifi\" || nmcli -t -f NAME connection show --active 2>/dev/null | grep -v '^lo:' | head -1 | cut -d: -f1"]
        stdout: StdioCollector { id: wifiNameC; waitForEnd: true }
        onExited: root.wifiName = String(wifiNameC.text).trim()
    }
    function toggleWifiPower() {
        root.wifiOn = !root.wifiOn
        Quickshell.execDetached(["sh", "-c", "nmcli radio wifi " + (root.wifiOn ? "on" : "off")])
    }

    property bool btOn: false
    property string btName: ""
    Process {
        id: btProbe
        command: ["sh", "-c", "timeout 4 bluetoothctl show | sed -n 's/.*Powered:[ ]*//p' | tr -d ' \\n\\r'"]
        stdout: StdioCollector { id: btC; waitForEnd: true }
        onExited: root.btOn = String(btC.text).trim() === "yes"
    }
    Process {
        id: btNameProbe
        command: ["sh", "-c", "bluetoothctl devices Connected 2>/dev/null | sed 's/^Device [0-9A-F:]* //'"]
        stdout: StdioCollector { id: btNameC; waitForEnd: true }
        onExited: root.btName = String(btNameC.text).trim()
    }
    function toggleBtPower() {
        root.btOn = !root.btOn
        if (!root.btOn) root.btName = ""
        Quickshell.execDetached(["sh", "-c", "bluetoothctl power " + (root.btOn ? "on" : "off")])
    }

    Timer {
        interval: 12000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            if (!wifiProbe.running) wifiProbe.running = true
            if (!wifiNameProbe.running) wifiNameProbe.running = true
            if (!btProbe.running) btProbe.running = true
            if (!btNameProbe.running) btNameProbe.running = true
        }
    }

    /* Power menu state */
    property bool powerOpen: false
    function openPower() { root.powerOpen = true }
    function closePower() { root.powerOpen = false }
    function togglePower() { root.powerOpen = !root.powerOpen }

    /* Workspaces & Windows Overview state */
    property bool overviewOpen: false
    function openOverview() { root.overviewOpen = true }
    function closeOverview() { root.overviewOpen = false }
    function toggleOverview() { root.overviewOpen = !root.overviewOpen }

    /* Fullscreen Wallpaper Transition (0:13 video reference) */
    property bool wallpaperTransitionOpen: false
    property bool wallpaperTransitionPendingFinish: false
    property string wallpaperTransitionText: "Applying Wallpaper"

    function startWallpaperTransition(name) {
        root.wallpaperTransitionText = "Applying Wallpaper"
        root.wallpaperTransitionPendingFinish = false
        root.wallpaperTransitionOpen = true
    }

    function finishWallpaperTransition() {
        root.wallpaperTransitionPendingFinish = true
    }

    function openLauncher() {
        root.closeWallpaperPicker()
        root.launcherOpen = true
    }
    property real lastLauncherToggleTime: 0
    function closeLauncher() {
        root.launcherOpen = false
        // Preserve active workspace so Hyprland does not revert to old workspace where launcher opened
        Quickshell.execDetached(["sh", "-c", "ws=$(hyprctl activeworkspace -j | jq -r .id 2>/dev/null); [ -n \"$ws\" ] && (sleep 0.05 && hyprctl dispatch workspace \"$ws\")"])
    }
    function toggleLauncher() {
        var now = Date.now()
        if (now - root.lastLauncherToggleTime < 280) return
        root.lastLauncherToggleTime = now
        if (root.launcherOpen) closeLauncher(); else openLauncher()
    }

    property real lastWpToggleTime: 0
    function openWallpaperPicker() {
        root.closeLauncher()
        root.wallpaperPickerOpen = true
    }
    function closeWallpaperPicker() { root.wallpaperPickerOpen = false }
    function toggleWallpaperPicker() {
        var now = Date.now()
        if (now - root.lastWpToggleTime < 280) return
        root.lastWpToggleTime = now
        if (root.wallpaperPickerOpen) closeWallpaperPicker(); else openWallpaperPicker()
    }
    onLauncherOpenChanged: {
        if (!root.launcherOpen && root.launcherItem)
            root.launcherItem.resetToApps()
    }

    /* Music popup & notch dropdown state */
    property bool musicOpen: false
    property bool musicPinned: false
    property bool musicHovered: false
    property bool musicHidden: true

    function openMusic() {
        root.closeAllPopupsExcept("music")
        root.musicOpen = true
        root.musicHovered = true
        musicLeaveTimer.stop()
    }
    function closeMusic() {
        root.musicOpen = false
        root.musicPinned = false
        root.musicHovered = false
    }
    function toggleMusic() {
        if (root.musicOpen && root.musicPinned) {
            root.musicPinned = false
            root.musicOpen = false
        } else {
            root.closeAllPopupsExcept("music")
            root.musicPinned = true
            root.musicOpen = true
        }
    }

    onMusicOpenChanged: {
        if (root.musicOpen) {
            musicOutTimer.stop()
            root.musicHidden = false
        } else {
            musicOutTimer.restart()
        }
    }

    Timer {
        id: musicLeaveTimer
        interval: 320
        onTriggered: {
            if (!root.musicPinned && !root.musicHovered) {
                root.musicOpen = false
            }
        }
    }

    Timer {
        id: musicOutTimer
        interval: 220
        onTriggered: root.musicHidden = true
    }

    /* ── Mode Transitions ───────────────────────────────────────────── */
    signal triggerWallpaperTransition()
    property bool nucleusTransitionActive: false
    property bool nucleusTransitionEnabled: true
    property string nucleusTransitionWord: "Wooshh!!"
    property string nucleusTransitionAnimation: "quantum"

    function startNucleusTransition(force) {
        if (!force && !root.nucleusTransitionEnabled) {
            root.barMode = "nucleus"
            return
        }
        root.nucleusTransitionActive = true
        root.triggerWallpaperTransition()
    }

    function finishNucleusTransition() {
        root.barMode = "nucleus"
        root.nucleusTransitionActive = false
        Quickshell.execDetached(["python3", "-c",
            "import json, os; dir=os.environ.get('CARBON_CONFIG_DIR', os.path.expanduser('~/.config/carbon')); os.makedirs(dir, exist_ok=True); p=os.path.join(dir, 'carbon-bar-mode.json'); d=json.load(open(p)) if os.path.exists(p) else {}; d['mode']='nucleus'; json.dump(d, open(p,'w'), indent=2)"])
    }

    /* ── Bar Mode Configuration: "pill" or "notch" ──────────────────── */
    property string barMode: "pill"
    property bool workspaceOsdActive: false
    property var nucleusRestingSpin: "hover"
    property bool screenshotFreezeActive: false
    property string screenshotFreezePath: ""
    onBarModeChanged: console.log("[BAR-MODE CHANGED] New root.barMode is now: " + root.barMode)

    FileView {
        id: barModeFile
        path: root.carbonConfigDir + "/carbon-bar-mode.json"
        watchChanges: true
        blockLoading: true
        printErrors: false
        onLoaded: root.reloadBarMode()
        onFileChanged: root.reloadBarMode()
    }

    FileView {
        id: hyprBarModeFile
        path: root.home + "/.config/hypr/carbon-bar-mode.json"
        watchChanges: true
        blockLoading: true
        printErrors: false
        onLoaded: root.reloadBarMode()
        onFileChanged: root.reloadBarMode()
    }

    Timer {
        id: barModePoller
        interval: 10000
        running: true
        repeat: true
        onTriggered: {
            if (!root._switchingBarMode) {
                root.reloadBarMode()
            }
        }
    }

    property string islandStyle: "pill"
    property int islandPage: 0
    property bool islandPersistent: true
    property bool islandHovered: false
    readonly property bool islandRevealed: islandPersistent || islandHovered || mixerOpen || trayOpen || brightnessOpen || batteryOpen || wifiOpen || btOpen || calendarOpen || centerDashboardOpen || smallMusicOpen

    property bool _switchingBarMode: false

    Timer {
        id: switchGuardTimer
        interval: 600
        onTriggered: root._switchingBarMode = false
    }

    function reloadBarMode() {
        if (root._switchingBarMode) {
            return
        }
        try {
            barModeFile.reload()
            var txt = barModeFile.text().trim()
            if (!txt || txt.length === 0) {
                hyprBarModeFile.reload()
                txt = hyprBarModeFile.text().trim()
            }

            if (txt.length > 0) {
                const d = JSON.parse(txt)
                if (d.nucleus) {
                    if (d.nucleus.transition !== undefined) {
                        root.nucleusTransitionEnabled = Boolean(d.nucleus.transition)
                    }
                    if (d.nucleus.transitionWord) {
                        root.nucleusTransitionWord = String(d.nucleus.transitionWord)
                    }
                    if (d.nucleus.animation) {
                        root.nucleusTransitionAnimation = String(d.nucleus.animation)
                    }
                    if (d.nucleus.restingSpin !== undefined) {
                        root.nucleusRestingSpin = d.nucleus.restingSpin
                    }
                }
                if (d.mode) {
                    var target = String(d.mode).toLowerCase()
                    if (target === "three_islands") target = "pill"
                    if (target === "vanish") target = "nucleus"
                    if (target === "island") target = "notch"
                    if (root.barMode !== target) {
                        console.log("[BAR-MODE] Switching mode from", root.barMode, "to", target)
                        root.barMode = target
                    }
                }
                if (d.islandStyle) {
                    root.islandStyle = d.islandStyle
                }
                if (d.islandPersistent !== undefined) {
                    root.islandPersistent = Boolean(d.islandPersistent)
                }
                if (root.barMode === "pill" || root.barMode === "minimal") {
                    if (root.mainBarEdge !== "top" && root.mainBarEdge !== "bottom") {
                        root.mainBarEdge = "top"
                        root.barEdge = "top"
                        root.musicBarEdge = "top"
                    }
                }
            }
        } catch (e) {
            console.log("Error loading bar mode: " + e)
        }
    }

    function switchBarMode(m) {
        console.log("[BAR-MODE] switchBarMode called with: " + m)
        if (!m) return
        m = String(m).toLowerCase()
        if (m === "three_islands") m = "pill"
        if (m === "vanish") m = "nucleus"
        if (m === "island") m = "notch"
        if (m === "nucleus" && root.barMode !== "nucleus" && root.nucleusTransitionEnabled) {
            root.startNucleusTransition(false)
            return
        }
        root._switchingBarMode = true
        switchGuardTimer.restart()
        root.barMode = m
        console.log("[BAR-MODE] switchBarMode set root.barMode to: " + root.barMode)
        Quickshell.execDetached(["python3", "-c",
            "import json, os\n" +
            "dirs = [os.environ.get('CARBON_CONFIG_DIR', os.path.expanduser('~/.config/carbon')), os.path.expanduser('~/.config/hypr')]\n" +
            "for dir in dirs:\n" +
            "  try:\n" +
            "    os.makedirs(dir, exist_ok=True)\n" +
            "    p = os.path.join(dir, 'carbon-bar-mode.json')\n" +
            "    d = json.load(open(p)) if os.path.exists(p) else {}\n" +
            "    if d.get('mode') != '" + m + "':\n" +
            "      d['mode'] = '" + m + "'\n" +
            "      d['islandStyle'] = '" + m + "'\n" +
            "      t = p + '.tmp'\n" +
            "      with open(t, 'w') as f: json.dump(d, f, indent=2)\n" +
            "      os.replace(t, p)\n" +
            "  except Exception: pass\n"
        ])
    }

    function switchIslandStyle(s) {
        if (!s) return
        root.islandStyle = s
        Quickshell.execDetached(["python3", "-c",
            "import json, os; dir=os.environ.get('CARBON_CONFIG_DIR', os.path.expanduser('~/.config/carbon')); os.makedirs(dir, exist_ok=True); p=os.path.join(dir, 'carbon-bar-mode.json'); d=json.load(open(p)) if os.path.exists(p) else {}; d['islandStyle']='" + s + "'; json.dump(d, open(p,'w'), indent=2)"])
    }

    function switchIslandPersistent(p) {
        root.islandPersistent = Boolean(p)
        Quickshell.execDetached(["python3", "-c",
            "import json, os; dir=os.environ.get('CARBON_CONFIG_DIR', os.path.expanduser('~/.config/carbon')); os.makedirs(dir, exist_ok=True); p=os.path.join(dir, 'carbon-bar-mode.json'); d=json.load(open(p)) if os.path.exists(p) else {}; d['islandPersistent']=" + (p ? "True" : "False") + "; json.dump(d, open(p,'w'), indent=2)"])
    }

    property real shellOpacity: Theme.shellOpacity
    property bool shellBlur: true
    property int pillHeight: 36
    property int notchHeight: 32
    property int appGap: 1
    property int pillAppGap: 1
    property int notchAppGap: 1
    property real pillOpacity: root.shellOpacity
    property bool pillBlur: root.shellBlur
    property real notchOpacity: root.shellOpacity
    property bool notchBlur: root.shellBlur
    property real minimalOpacity: root.shellOpacity
    property bool minimalBlur: root.shellBlur
    property int barHeight: root.barMode === "notch" ? root.notchHeight : root.pillHeight
    property string barEdge: "top"
    property string mainBarEdge: "top"
    property string musicBarEdge: "top"
    property string musicBarContent: "both"
    property string leftAlign: "left"
    property string centerAlign: "center"
    property string rightAlign: "right"
    property string leftEdge: "top"
    property string centerEdge: "top"
    property string rightEdge: "top"

    /* Panel corner placement for Quick Settings:
     * - Bottom edge -> "top_left"
     * - Top edge (default) -> "bottom_right"
     */
    readonly property string controlsCorner: {
        return (root.mainBarEdge === "bottom" || root.barEdge === "bottom") ? "top_left" : "bottom_right"
    }

    property int notchEarRadius: 10
    property int notchBottomRadius: 14
    property int sideNotchBottomRadius: Math.min(8, root.notchBottomRadius)

    readonly property int popupTopMargin: {
        if (root.mainBarEdge === "bottom") return 0
        if (root.barMode === "notch") return -1
        if (root.barMode === "pill") return root.pillHeight + 10
        return 0
    }

    readonly property int popupBottomMargin: {
        if (root.mainBarEdge !== "bottom") return 0
        if (root.barMode === "notch") return -1
        if (root.barMode === "pill") return root.pillHeight + 10
        return 0
    }

    readonly property int popupRightMargin: {
        if (root.barMode === "notch") return 0
        if (root.barMode === "pill") return 12
        return 0
    }

    FileView {
        id: barPosFile
        path: root.carbonConfigDir + "/carbon-bar-position.json"
        watchChanges: true
        blockLoading: true
        printErrors: false
        onLoaded: root.applyBarPos(barPosFile.text())
        onFileChanged: root.applyBarPos(barPosFile.text())
    }

    function applyBarPos(txt) {
        if (!txt) return
        try {
            var d = JSON.parse(txt)
            var chosenEdge = "top"
            if (d.mainBarEdge === "bottom" || d.edge === "bottom") {
                chosenEdge = "bottom"
            }
            root.mainBarEdge = chosenEdge
            root.musicBarEdge = chosenEdge
            root.barEdge = chosenEdge
            root.leftEdge = chosenEdge
            root.centerEdge = chosenEdge
            root.rightEdge = chosenEdge

            if (d.musicBarContent) root.musicBarContent = d.musicBarContent
            if (d.leftAlign) root.leftAlign = d.leftAlign
            if (d.centerAlign) root.centerAlign = d.centerAlign
            if (d.rightAlign) root.rightAlign = d.rightAlign

            if (d.pillHeight !== undefined) root.pillHeight = parseInt(d.pillHeight) || 36
            if (d.notchHeight !== undefined) root.notchHeight = parseInt(d.notchHeight) || 32
            if (d.notchEarRadius !== undefined) root.notchEarRadius = parseInt(d.notchEarRadius) || 10
            if (d.notchBottomRadius !== undefined) root.notchBottomRadius = parseInt(d.notchBottomRadius) || 14
            if (d.appGap !== undefined) root.appGap = (!isNaN(parseInt(d.appGap))) ? parseInt(d.appGap) : 1
            if (d.pillAppGap !== undefined) root.pillAppGap = (!isNaN(parseInt(d.pillAppGap))) ? parseInt(d.pillAppGap) : root.appGap
            else root.pillAppGap = root.appGap
            if (d.notchAppGap !== undefined) root.notchAppGap = (!isNaN(parseInt(d.notchAppGap))) ? parseInt(d.notchAppGap) : root.appGap
            else root.notchAppGap = root.appGap

            if (d.shellOpacity !== undefined) {
                root.shellOpacity = Math.max(0.10, Math.min(1.0, parseFloat(d.shellOpacity) || 0.85))
                root.pillOpacity = root.shellOpacity
                root.notchOpacity = root.shellOpacity
                root.minimalOpacity = root.shellOpacity
                Theme.shellOpacity = root.shellOpacity
            } else {
                if (d.pillOpacity !== undefined) root.pillOpacity = parseFloat(d.pillOpacity) || 0.85
                if (d.notchOpacity !== undefined) root.notchOpacity = parseFloat(d.notchOpacity) || 0.90
                if (d.minimalOpacity !== undefined) root.minimalOpacity = parseFloat(d.minimalOpacity) || 0.90
            }

            if (d.shellBlur !== undefined) {
                root.shellBlur = !!d.shellBlur
                root.pillBlur = root.shellBlur
                root.notchBlur = root.shellBlur
                root.minimalBlur = root.shellBlur
            } else {
                if (d.pillBlur !== undefined) root.pillBlur = !!d.pillBlur
                if (d.notchBlur !== undefined) root.notchBlur = !!d.notchBlur
                if (d.minimalBlur !== undefined) root.minimalBlur = !!d.minimalBlur
            }

            root.barHeight = (root.barMode === "notch" ? root.notchHeight : root.pillHeight)
        } catch (e) {}
    }

    Component.onCompleted: {
        reloadBarMode()
        applyBarPos(barPosFile.text())
    }

    /* ── MPRIS Music Tracking ────────────────────────────────────────── */
    readonly property var mprisPlayers: Mpris.players.values !== undefined ? Mpris.players.values : Mpris.players
    property var activeMprisPlayer: null

    function resolveActiveMprisPlayer() {
        if (!root.mprisPlayers || root.mprisPlayers.length === 0) return null
        for (let i = 0; i < root.mprisPlayers.length; i++) {
            if (root.mprisPlayers[i].playbackState === MprisPlaybackState.Playing)
                return root.mprisPlayers[i]
        }
        for (let i = 0; i < root.mprisPlayers.length; i++) {
            if (root.mprisPlayers[i].playbackState === MprisPlaybackState.Paused
                && (root.mprisPlayers[i].trackTitle || "").length > 0)
                return root.mprisPlayers[i]
        }
        return root.mprisPlayers[0]
    }

    Timer {
        interval: 1000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.activeMprisPlayer = root.resolveActiveMprisPlayer()
    }

    readonly property string mprisTrackTitle: activeMprisPlayer ? (activeMprisPlayer.trackTitle || "") : ""
    readonly property string mprisTrackArtist: activeMprisPlayer ? (activeMprisPlayer.trackArtist || "") : ""
    readonly property string mprisArtUrl: activeMprisPlayer ? (activeMprisPlayer.trackArtUrl || "") : ""
    readonly property bool mprisHasTrack: root.activeMprisPlayer !== null && root.mprisTrackTitle.trim().length > 0

    /* Quick-settings panel: hover the top-right hot corner to summon it, and
     * keep it while the pointer is over the panel (or the corner). */
    property bool controlsVisible: false
    property bool controlsHovered: false
    property bool controlsPinned: false

    function openControls() {
        root.closeAllPopupsExcept("controls")
        root.controlsPinned = true
        root.controlsVisible = true
    }
    function openControlsHover() {
        root.closeAllPopupsExcept("controls")
        root.controlsPinned = false
        root.controlsVisible = true
        controlsLeaveTimer.stop()
    }
    function closeControls() { root.controlsVisible = false; root.controlsPinned = false }
    function toggleControls() {
        if (root.controlsVisible) {
            root.closeControls()
        } else {
            root.closeAllPopupsExcept("controls")
            root.controlsPinned = true
            root.controlsVisible = true
        }
    }

    Timer {
        id: controlsLeaveTimer
        interval: 350
        onTriggered: {
            if (!root.controlsPinned && !root.controlsHovered) root.closeControls()
        }
    }

    /* Notification daemon: claims org.freedesktop.Notifications (swaync is
     * disabled in Hyprland) and feeds the top-right bar. Exactly one. */
    NotificationServer {
        id: notificationServer
        actionsSupported: true
        bodySupported: true
        bodyHyperlinksSupported: true
        bodyImagesSupported: true
        bodyMarkupSupported: true
        onNotification: notification => {
            notification.tracked = true
            NotificationService.addNotification(notification)
        }
    }

    Binding {
        target: NotificationService
        property: "server"
        value: notificationServer
    }

    /* External trigger (keybinds): Super+W brokered to the launcher in
     * wallpaper mode by carbon-ipc.sh over this unix socket. */
    SocketServer {
        id: cmdSocketServer
        path: "/tmp/carbon-shell.sock"
        active: true
        handler: Component {
            Socket {
                parser: SplitParser {
                splitMarker: "\n"
                onRead: function (message) {
                    var cmd = message.trim()
                    console.log("[IPC RECEIVED] " + cmd)
                    if (cmd === "wallpaper" || cmd === "wallpaper-local") {
                        root.wallpaperSource = "local"
                        if (root.barMode === "nucleus" && root.nucleusHubItem && root.nucleusHubItem.hubOpen) {
                            root.nucleusHubItem.close()
                        }
                        root.toggleWallpaperPicker()
                    }
                    else if (cmd === "wallpaper-live") {
                        root.wallpaperSource = "live"
                        if (root.barMode === "nucleus" && root.nucleusHubItem && root.nucleusHubItem.hubOpen) {
                            root.nucleusHubItem.close()
                        }
                        root.openWallpaperPicker()
                    }
                    else if (cmd === "wallpaper-online") {
                        root.wallpaperSource = "wallhaven"
                        if (root.barMode === "nucleus" && root.nucleusHubItem && root.nucleusHubItem.hubOpen) {
                            root.nucleusHubItem.close()
                        }
                        root.openWallpaperPicker()
                    }
                    else if (cmd === "close-wallpaper") {
                        root.closeWallpaperPicker()
                    }
                    else if (cmd.startsWith("freeze-start ")) {
                        var fpath = cmd.replace(/^freeze-start\s+/, "").trim()
                        root.screenshotFreezePath = fpath
                        root.screenshotFreezeActive = true
                    }
                    else if (cmd === "freeze-stop") {
                        root.screenshotFreezeActive = false
                        root.screenshotFreezePath = ""
                    }
                    else if (cmd.startsWith("apply-wallpaper ") || cmd.startsWith("set-wallpaper ") || (cmd.startsWith("wallpaper ") && cmd !== "wallpaper live" && cmd !== "wallpaper local" && cmd !== "wallpaper online")) {
                        var wpPath = cmd.replace(/^(apply-wallpaper|set-wallpaper|wallpaper)\s+/, "").trim()
                        if (wpPath.length > 0) {
                            if (root.wallpaperModItem) root.wallpaperModItem.applyNewWallpaper(wpPath)
                        }
                    }
                    else if (cmd === "launcher" || cmd === "toggle-launcher") {
                        if (root.barMode === "nucleus") {
                            if (cmd === "toggle-launcher") {
                                if (root.nucleusHubItem) root.nucleusHubItem.toggle()
                            } else {
                                if (root.nucleusHubItem) root.nucleusHubItem.toggleLauncher()
                            }
                        } else {
                            if (cmd === "launcher") root.openLauncher()
                            else root.toggleLauncher()
                        }
                    }
                    else if (cmd === "close-launcher") {
                        if (root.barMode === "nucleus") {
                            if (root.nucleusHubItem) root.nucleusHubItem.close()
                        } else {
                            root.closeLauncher()
                        }
                    }
                    else if (cmd === "spotlight" || cmd === "toggle-spotlight") {
                        if (root.barMode !== "nucleus") {
                            root.toggleSpotlight()
                        }
                    }
                    else if (cmd === "open-spotlight") {
                        if (root.barMode === "nucleus") {
                            if (root.nucleusHubItem) root.nucleusHubItem.open()
                        } else {
                            root.openSpotlight()
                        }
                    }
                    else if (cmd === "close-spotlight") {
                        if (root.barMode === "nucleus") {
                            if (root.nucleusHubItem) root.nucleusHubItem.close()
                        } else {
                            root.closeSpotlight()
                        }
                    }
                    else if (cmd.startsWith("focus-lobe ")) {
                        var lobeTarget = cmd.replace(/^focus-lobe\s+/, "").trim()
                        if (root.barMode === "nucleus" && root.nucleusHubItem) root.nucleusHubItem.focusLobe(lobeTarget)
                    }
                    else if (cmd === "test-hud-vol")
                        HudService.trigger("volume", 0.72, "72%", "Volume", "", false, "volume_up", "", 2500)
                    else if (cmd === "test-hud-bright")
                        HudService.trigger("brightness", 0.85, "85%", "Brightness", "", false, "light_mode", "", 2500)
                    else if (cmd === "test-hud-track")
                        HudService.trigger("track", 1.0, "Now Playing", "Do I Wanna Know?", "Arctic Monkeys", false, "music_note", "", 3500)
                    else if (cmd === "test-wp-transition")
                        root.startWallpaperTransition("Testing")
                    else if (cmd === "test-wp-finish")
                        root.finishWallpaperTransition()
                    else if (cmd === "mixer")
                        root.toggleMixer()
                    else if (cmd === "brightness")
                        root.toggleBrightness()
                    else if (cmd === "battery")
                        root.toggleBattery()
                    else if (cmd === "wifi" || cmd === "connect open wifi") {
                        if (root.barMode === "nucleus") {
                            if (root.nucleusHubItem) root.nucleusHubItem.openWifiMode()
                        } else {
                            root.toggleWifi()
                        }
                    }
                    else if (cmd === "bt" || cmd === "bluetooth" || cmd === "connect open bluetooth") {
                        if (root.barMode === "nucleus") {
                            if (root.nucleusHubItem) root.nucleusHubItem.openBluetoothMode()
                        } else {
                            root.toggleBt()
                        }
                    }
                    else if (cmd === "connect close") {
                        if (root.barMode === "nucleus") {
                            if (root.nucleusHubItem) root.nucleusHubItem.closeConnectivityPicker()
                        }
                    }
                    else if (cmd === "tray")
                        root.toggleTray()
                    else if (cmd === "calendar")
                        root.toggleCalendar()
                    else if (cmd === "dashboard" || cmd === "center-dashboard")
                        root.toggleCenterDashboard()
                    else if (cmd === "small-music")
                        root.toggleSmallMusic()
                    else if (cmd === "controls")
                        root.toggleControls()
                    else if (cmd === "controls volume up") {
                        if (root.barMode === "nucleus" && root.nucleusHubItem) root.nucleusHubItem.volumeAction("up")
                    }
                    else if (cmd === "controls volume down") {
                        if (root.barMode === "nucleus" && root.nucleusHubItem) root.nucleusHubItem.volumeAction("down")
                    }
                    else if (cmd === "controls volume toggle-mute") {
                        if (root.barMode === "nucleus" && root.nucleusHubItem) root.nucleusHubItem.volumeAction("toggle-mute")
                    }
                    else if (cmd === "controls volume open") {
                        if (root.barMode === "nucleus" && root.nucleusHubItem) root.nucleusHubItem.volumeAction("open")
                    }
                    else if (cmd === "controls brightness up") {
                        if (root.barMode === "nucleus" && root.nucleusHubItem) root.nucleusHubItem.brightnessAction("up")
                    }
                    else if (cmd === "controls brightness down") {
                        if (root.barMode === "nucleus" && root.nucleusHubItem) root.nucleusHubItem.brightnessAction("down")
                    }
                    else if (cmd === "controls brightness open") {
                        if (root.barMode === "nucleus" && root.nucleusHubItem) root.nucleusHubItem.brightnessAction("open")
                    }
                    else if (cmd.startsWith("set-bar-mode ")) {
                        const m = cmd.substring(13).trim()
                        if (m) root.switchBarMode(m)
                    }
                    else if (cmd.startsWith("set-opacity ")) {
                        const val = parseFloat(cmd.substring(12))
                        if (!isNaN(val)) {
                            root.shellOpacity = Math.max(0.10, Math.min(1.0, val))
                            root.pillOpacity = root.shellOpacity
                            root.notchOpacity = root.shellOpacity
                            root.minimalOpacity = root.shellOpacity
                            Theme.shellOpacity = root.shellOpacity
                            Theme.reload()
                        }
                    }
                    else if (cmd.startsWith("set-blur ")) {
                        const val = parseInt(cmd.substring(9))
                        root.shellBlur = (val === 1)
                        root.pillBlur = root.shellBlur
                        root.notchBlur = root.shellBlur
                        root.minimalBlur = root.shellBlur
                    }
                    else if (cmd === "reload-config" || cmd === "apply-settings") {
                        root.applyBarPos(barPosFile.text())
                        root.reloadBarMode()
                        Theme.reloadShellOpacity()
                    }
                    else if (cmd === "controls-mode-todo") {
                        root.controlsPinned = true
                        root.controlsVisible = true
                        controlsItem.mode = 1
                    } else if (cmd === "controls-mode-timer") {
                        root.controlsPinned = true
                        root.controlsVisible = true
                        controlsItem.mode = 2
                    } else if (cmd === "controls-mode-quick") {
                        root.controlsPinned = true
                        root.controlsVisible = true
                        controlsItem.mode = 0
                    } else if (cmd === "controls-wifi") {
                        root.controlsPinned = true
                        root.controlsVisible = true
                        controlsItem.mode = 0
                        controlsItem.wifiPopupOpen = !controlsItem.wifiPopupOpen
                        if (controlsItem.wifiPopupOpen) controlsItem.btPopupOpen = false
                    } else if (cmd === "controls-bt") {
                        root.controlsPinned = true
                        root.controlsVisible = true
                        controlsItem.mode = 0
                        controlsItem.btPopupOpen = !controlsItem.btPopupOpen
                        if (controlsItem.btPopupOpen) controlsItem.wifiPopupOpen = false
                    } else if (cmd === "controls-notifs") {
                        root.controlsPinned = true
                        root.controlsVisible = true
                        controlsItem.mode = 0
                        controlsItem.scrollToNotifs()
                    } else if (cmd === "controls-notif-next") {
                        controlsItem.selectNextNotif()
                    } else if (cmd === "controls-notif-prev") {
                        controlsItem.selectPrevNotif()
                    } else if (cmd === "controls-notif-enter") {
                        controlsItem.activateSelectedNotif()
                    } else if (cmd === "controls-mode-timer" || cmd === "timer") {
                        root.controlsPinned = true
                        root.controlsVisible = true
                        controlsItem.mode = 2
                    }
                    else if (cmd === "battery")
                        root.toggleBattery()
                    else if (cmd === "mixer")
                        root.toggleMixer()
                    else if (cmd === "brightness")
                        root.toggleBrightness()
                    else if (cmd === "wifi")
                        root.toggleWifi()
                    else if (cmd === "bt" || cmd === "bluetooth")
                        root.toggleBt()
                    else if (cmd === "power" || cmd === "powermenu" || cmd.startsWith("power ")) {
                        const parts = cmd.split(/\s+/)
                        const sub = parts[1] || "open"
                        const hasConfirm = parts.includes("--confirm")
                        console.log("[IPC power] sub=" + sub + " confirm=" + hasConfirm + " barMode=" + root.barMode)
                        if (sub === "open") {
                            if (root.barMode === "nucleus" && root.nucleusHubItem) {
                                root.nucleusHubItem.openPowerMode()
                            } else {
                                root.openPower()
                            }
                        } else if (sub === "close") {
                            if (root.barMode === "nucleus" && root.nucleusHubItem) {
                                root.nucleusHubItem.close()
                            } else {
                                root.closePower()
                            }
                        } else if (sub === "lock") {
                            if (root.barMode === "nucleus" && root.nucleusHubItem) {
                                root.nucleusHubItem.triggerPowerAction("lock")
                            } else {
                                root.closePower()
                                sessionLock.lock()
                            }
                        } else if (sub === "sleep") {
                            if (root.barMode === "nucleus" && root.nucleusHubItem) {
                                root.nucleusHubItem.triggerPowerAction("sleep")
                            } else {
                                root.closePower()
                                Quickshell.execDetached(["systemctl", "suspend"])
                            }
                        } else if (sub === "restart" || sub === "reboot") {
                            if (hasConfirm) {
                                if (root.barMode === "nucleus" && root.nucleusHubItem) {
                                    root.nucleusHubItem.triggerPowerAction("restart")
                                } else {
                                    root.closePower()
                                    Quickshell.execDetached(["systemctl", "reboot"])
                                }
                            } else {
                                console.log("[IPC power restart] requires --confirm")
                                if (root.barMode === "nucleus" && root.nucleusHubItem) {
                                    root.nucleusHubItem.openPowerMode()
                                }
                            }
                        } else if (sub === "shutdown" || sub === "poweroff") {
                            if (hasConfirm) {
                                if (root.barMode === "nucleus" && root.nucleusHubItem) {
                                    root.nucleusHubItem.triggerPowerAction("shutdown")
                                } else {
                                    root.closePower()
                                    Quickshell.execDetached(["systemctl", "poweroff"])
                                }
                            } else {
                                console.log("[IPC power shutdown] requires --confirm")
                                if (root.barMode === "nucleus" && root.nucleusHubItem) {
                                    root.nucleusHubItem.openPowerMode()
                                }
                            }
                        }
                    }
                    else if (cmd === "tray" || cmd === "toggle-tray")
                        root.toggleTray()
                    else if (cmd === "close-power")
                        root.closePower()
                    else if (cmd === "lock") {
                        root.closePower()
                        sessionLock.lock()
                    }
                    else if (cmd === "lock-test") {
                        root.closePower()
                        LockTransition.testLock()
                    }
                    else if (cmd === "unlock") {
                        sessionLock.unlock()
                    }
                    else if (cmd === "unlock-test") {
                        LockTransition.testUnlock()
                    }
                    else if (cmd === "notifications" || cmd === "notif")
                        root.toggleNotif()
                    else if (cmd === "overview" || cmd === "toggle-overview")
                        root.toggleOverview()
                    else if (cmd === "close-overview")
                        root.closeOverview()
                    else if (cmd === "theme-reload" || cmd === "reload-theme")
                        Theme.reload()
                    else if (cmd === "atomic" || cmd === "mode-atomic" || cmd === "toggle-atomic") {
                        if (root.barMode === "atomic") root.switchBarMode("notch")
                        else root.switchBarMode("atomic")
                    }
                    else if (cmd === "shard" || cmd === "mode-shard" || cmd === "toggle-shard") {
                        if (root.barMode === "shard") root.switchBarMode("notch")
                        else root.switchBarMode("shard")
                    }
                    else if (cmd === "bloom" || cmd === "mode-bloom" || cmd === "toggle-bloom") {
                        if (root.barMode === "bloom") root.switchBarMode("notch")
                        else root.switchBarMode("bloom")
                    }
                    else if (cmd === "nucleus transition" || cmd === "vanish-transition" || cmd === "transition-vanish" || cmd === "woosh") {
                        root.startNucleusTransition(true)
                    }
                    else if (cmd === "nucleus" || cmd === "mode-nucleus" || cmd === "toggle-nucleus") {
                        if (root.barMode === "nucleus") root.switchBarMode("notch")
                        else root.switchBarMode("nucleus")
                    }
                    else if (cmd === "nucleus toggle") {
                        if (root.barMode !== "nucleus") root.switchBarMode("nucleus")
                        if (root.nucleusHubItem) root.nucleusHubItem.toggle()
                    }
                    else if (cmd.startsWith("nucleus focus ")) {
                        if (root.barMode !== "nucleus") root.switchBarMode("nucleus")
                        var lobeTarget = cmd.substring("nucleus focus ".length).trim()
                        if (root.nucleusHubItem) root.nucleusHubItem.focusLobe(lobeTarget)
                    }
                    else if (cmd === "nucleus wallpapers") {
                        root.wallpaperSource = "local"
                        root.toggleWallpaperPicker()
                    }
                    else if (cmd === "nucleus launcher") {
                        if (root.barMode !== "nucleus") root.switchBarMode("nucleus")
                        if (root.nucleusHubItem) root.nucleusHubItem.toggleLauncher()
                    }
                    else if (cmd === "nucleus lyrics" || cmd === "nucleus lyrics toggle" || cmd === "nucleus toggle-lyrics") {
                        if (root.barMode !== "nucleus") root.switchBarMode("nucleus")
                        if (root.nucleusHubItem) root.nucleusHubItem.toggleLyrics()
                    }
                    else if (cmd === "nucleus wifi" || cmd === "nucleus wifi toggle") {
                        if (root.barMode !== "nucleus") root.switchBarMode("nucleus")
                        if (root.nucleusHubItem) root.nucleusHubItem.openWifiMode()
                    }
                    else if (cmd === "nucleus bluetooth" || cmd === "nucleus bt" || cmd === "nucleus bluetooth toggle") {
                        if (root.barMode !== "nucleus") root.switchBarMode("nucleus")
                        if (root.nucleusHubItem) root.nucleusHubItem.openBluetoothMode()
                    }
                    else if (cmd === "nucleus notif" || cmd === "nucleus notifications" || cmd === "nucleus toggle-notif" || cmd === "nucleus alert" || cmd === "nucleus alerts") {
                        if (root.barMode !== "nucleus") root.switchBarMode("nucleus")
                        if (root.nucleusHubItem) root.nucleusHubItem.openNotificationPanel()
                    }
                    else if (cmd === "calendar" || cmd === "center-dashboard" || cmd === "center" || cmd === "time-weather" || cmd === "toggle-dashboard" || cmd === "dashboard")
                        root.toggleCenterDashboard()
                    else if (cmd === "calendar-events") {
                        root.closeAllPopupsExcept("centerDashboard")
                        root.centerDashboardPinned = true
                        root.centerDashboardOpen = true
                        if (centerDashboardItem) {
                            centerDashboardItem.calendarViewMode = "events"
                            centerDashboardItem.selectedDay = 14
                        }
                    }
                    else if (cmd === "calendar-form") {
                        root.closeAllPopupsExcept("centerDashboard")
                        root.centerDashboardPinned = true
                        root.centerDashboardOpen = true
                        if (centerDashboardItem) {
                            centerDashboardItem.calendarViewMode = "events"
                            centerDashboardItem.selectedDay = 14
                            centerDashboardItem.eventFormMode = true
                        }
                    }
                    else if (cmd === "lyrics" || cmd === "toggle-lyrics") {
                        root.closeAllPopupsExcept("centerDashboard")
                        root.centerDashboardPinned = true
                        root.centerDashboardOpen = true
                        if (centerDashboardItem && centerDashboardItem.rightColItem) {
                            centerDashboardItem.rightColItem.viewMode = (centerDashboardItem.rightColItem.viewMode === "lyrics" ? "weather" : "lyrics")
                        }
                    }
                    else if (cmd === "music" || cmd === "music-toggle")
                        root.toggleMusic()
                    else if (cmd === "music-open") {
                        root.musicPinned = true
                        root.openMusic()
                    }
                    else if (cmd === "music-close") {
                        root.musicPinned = false
                        root.closeMusic()
                    }
                    else if (cmd === "toggle-small-music" || cmd === "music-small") {
                        root.toggleSmallMusic()
                    }
                    else if (cmd === "close-small-music") {
                        root.smallMusicOpen = false
                    }
                    else if (cmd.startsWith("bar-mode ") || cmd.startsWith("set-bar-mode ") || cmd.startsWith("mode ") || cmd.startsWith("switch-mode ") || cmd.startsWith("bar_mode ") || cmd.startsWith("set_bar_mode ")) {
                        var m = cmd.replace(/^(bar-mode|set-bar-mode|mode|switch-mode|bar_mode|set_bar_mode)\s+/, "").trim().toLowerCase()
                        root.switchBarMode(m)
                    }
                    else if (cmd === "notch" || cmd === "pill" || cmd === "minimal" || cmd === "vanish" || cmd === "mode-notch" || cmd === "mode-pill" || cmd === "mode-minimal") {
                        var m = cmd.replace(/^mode-/, "")
                        root.switchBarMode(m)
                    }
                    else if (cmd.startsWith("island-style ")) {
                        var is = cmd.substring(13).trim()
                        root.switchIslandStyle(is)
                    }
                    else if (cmd.startsWith("island-persistent ")) {
                        var ip = cmd.substring(18).trim().toLowerCase()
                        root.switchIslandPersistent(ip === "true" || ip === "1")
                    }
                    else if (cmd.startsWith("island-page ")) {
                        var pg = parseInt(cmd.substring(12).trim(), 10)
                        if (!isNaN(pg)) root.islandPage = pg
                    }
                    else if (cmd === "island-next-page") {
                        root.islandPage = (root.islandPage + 1) % 3
                    }
                    else if (cmd === "island-prev-page") {
                        root.islandPage = (root.islandPage - 1 + 3) % 3
                    }
                    else if (cmd === "reload-bar-mode")
                        root.reloadBarMode()
                    else if (cmd === "reload-bar-pos") {
                        barPosFile.reload()
                        root.applyBarPos(barPosFile.text())
                    }
                    else if (cmd === "lock") {
                        sessionLock.lock()
                    }
                    else if (cmd === "lock-test") {
                        LockTransition.testLock()
                    }
                    else if (cmd === "unlock") {
                        sessionLock.unlock()
                    }
                    else if (cmd === "unlock-test") {
                        LockTransition.testUnlock()
                    }
                    else if (cmd === "lock-test-notif") {
                        sessionLock.testNotif()
                    }
                    else if (cmd === "lock-test-notif-center") {
                        sessionLock.testNotifCenter()
                    }
                    else if (cmd === "lock-test-notif-clear") {
                        sessionLock.testNotifClear()
                    }
                    else if (cmd === "desktop-notif-clear") {
                        if (notificationServer && notificationServer.trackedNotifications && notificationServer.trackedNotifications.values) {
                            const list = [...notificationServer.trackedNotifications.values]
                            for (let i = 0; i < list.length; i++) {
                                if (list[i] && typeof list[i].dismiss === "function") list[i].dismiss()
                            }
                        }
                    }
                }
            }
        }
    }
}

    /* ── Lock Screen (Carbon Lewis Dot Structure & Password Card) ───── */
    LockScreen {
        id: sessionLock
        notificationServer: notificationServer
    }

    GlobalShortcut {
        name: "lock"
        onPressed: sessionLock.lock()
    }

    /* ── Fullscreen Desktop Lock Transition Overlay (0-780ms handoff to WlSessionLock) ── */
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: lockOverlayWindow
            required property var modelData

            screen: modelData
            color: "transparent"
            WlrLayershell.namespace: "carbon-lock-transition"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: (!LockTransition.lockSync && LockTransition.phase === "locking" && LockTransition.t < 780.0) ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            aboveWindows: true
            anchors { top: true; bottom: true; left: true; right: true }

            visible: LockTransition.phase === "post_unlock" || (LockTransition.phase === "unlocking" && LockTransition.u >= 800.0) || (!LockTransition.lockSync && LockTransition.phase === "locking")

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                preventStealing: true
            }

            LockTransitionOverlay {
                anchors.fill: parent
            }
        }
    }

    /* Wallpaper: bottom-most fullscreen image, updated live by WallpaperMod */
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: wallpaperWindow
            required property var modelData

            screen: modelData
            color: "#000000"
            WlrLayershell.namespace: "carbon-wallpaper"
            WlrLayershell.layer: WlrLayer.Background
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; left: true; right: true; bottom: true }

            WallpaperMod {
                id: wpInstance
                anchors.fill: parent

                Component.onCompleted: {
                    if (!root.wallpaperModItem) root.wallpaperModItem = wpInstance
                }

                Connections {
                    target: root
                    function onTriggerWallpaperTransition() {
                        wpInstance.retriggerTransition()
                    }
                }
            }
        }
    }

    /* ── Audio-Reactive Active Window Border Daemon (Disabled for low latency & CPU efficiency) ── */
    Process {
        id: audioBorderDaemon
        command: ["python3", root.carbonConfigDir + "/scripts/audio-border.py"]
        running: false
    }

    /* ── Dynamic Edge Reservation Windows (Prevents App Overlap) ────────── */
    readonly property bool hasTopReserve: false
    readonly property bool hasBottomReserve: (root.barMode === "atomic" || root.barMode === "shard" || root.barMode === "bloom" || root.barMode === "nucleus") ? false :
        ((root.barMode === "pill" || (root.barMode === "minimal" && root.islandPersistent))
        ? (root.mainBarEdge === "bottom")
        : (root.barMode === "minimal" ? false : (root.mainBarEdge === "bottom" || root.musicBarEdge === "bottom")))
    readonly property bool hasLeftReserve: false
    readonly property bool hasRightReserve: false

    readonly property int topReserveHeight: 0
    readonly property int bottomReserveHeight: root.hasBottomReserve ? (root.barHeight + (root.barMode === "pill" ? 10 : (root.islandStyle === "notch" ? 4 : 8))) : 0
    readonly property int leftReserveWidth: root.hasLeftReserve ? 38 : 0
    readonly property int rightReserveWidth: root.hasRightReserve ? 38 : 0

    /* Top Edge Reserve */
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: reserveTopWindow
            required property var modelData

            screen: modelData
            color: "transparent"
            WlrLayershell.namespace: "carbon-reserve-top"
            WlrLayershell.layer: WlrLayer.Bottom
            exclusionMode: ExclusionMode.Normal
            exclusiveZone: root.topReserveHeight
            anchors { top: true; left: true; right: true }
            implicitHeight: root.topReserveHeight
            visible: root.hasTopReserve

            mask: Region {}
        }
    }

    /* Bottom Edge Reserve */
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: reserveBottomWindow
            required property var modelData

            screen: modelData
            color: "transparent"
            WlrLayershell.namespace: "carbon-reserve-bottom"
            WlrLayershell.layer: WlrLayer.Bottom
            exclusionMode: ExclusionMode.Normal
            exclusiveZone: root.bottomReserveHeight
            anchors { bottom: true; left: true; right: true }
            implicitHeight: root.bottomReserveHeight
            visible: root.hasBottomReserve

            mask: Region {}
        }
    }

    /* Left Edge Reserve */
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: reserveLeftWindow
            required property var modelData

            screen: modelData
            color: "transparent"
            WlrLayershell.namespace: "carbon-reserve-left"
            WlrLayershell.layer: WlrLayer.Bottom
            exclusionMode: ExclusionMode.Normal
            exclusiveZone: root.leftReserveWidth
            anchors { left: true; top: true; bottom: true }
            implicitWidth: root.leftReserveWidth
            visible: root.hasLeftReserve

            mask: Region {}
        }
    }

    /* Right Edge Reserve */
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: reserveRightWindow
            required property var modelData

            screen: modelData
            color: "transparent"
            WlrLayershell.namespace: "carbon-reserve-right"
            WlrLayershell.layer: WlrLayer.Bottom
            exclusionMode: ExclusionMode.Normal
            exclusiveZone: root.rightReserveWidth
            anchors { right: true; top: true; bottom: true }
            implicitWidth: root.rightReserveWidth
            visible: root.hasRightReserve

            mask: Region {}
        }
    }

    /* ── Pill Mode: Connected Continuous Full Floating Bar ──────────── */
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: pillFullBarWindow
            required property var modelData

            screen: modelData
            color: "transparent"
            WlrLayershell.namespace: "carbon-bar-pill-full"
            WlrLayershell.layer: WlrLayer.Top
            exclusionMode: root.barMode === "pill" ? ExclusionMode.Normal : ExclusionMode.Ignore
            exclusiveZone: root.barMode === "pill" ? Math.max(0, root.pillHeight + (root.mainBarEdge !== "bottom" ? 8 : 0) + root.pillAppGap) : 0
            aboveWindows: true
            anchors {
                top: root.mainBarEdge !== "bottom"
                bottom: root.mainBarEdge === "bottom"
                left: true
                right: true
            }
            margins {
                top: root.mainBarEdge !== "bottom" ? 8 : 0
                bottom: root.mainBarEdge === "bottom" ? 8 : 0
                left: 12
                right: 12
            }

            implicitHeight: root.pillHeight
            visible: root.barMode === "pill" && root.mainBarEdge !== "left" && root.mainBarEdge !== "right"

            Loader {
                id: pillFullBarLoader
                anchors.fill: parent
                active: root.barMode === "pill" && root.mainBarEdge !== "left" && root.mainBarEdge !== "right"
                sourceComponent: Rectangle {
                    id: pillFullCapsule
                    anchors.fill: parent
                    radius: root.pillHeight / 2
                    color: Qt.rgba(Theme.bg.r, Theme.bg.g, Theme.bg.b, root.pillOpacity)
                    border.color: Theme.outline
                    border.width: 1

                    Item {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8

                        /* Left: Workspaces & App Launcher */
                        BarLeft {
                            id: pillLeftItem
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            showBackground: false
                            vertical: false
                            onOpenLauncher: root.openLauncher()
                        }

                        /* Center: Clock, Rotating Vinyl Disc, Equalizer & Music Island */
                        BarCenter {
                            id: pillCenterItem
                            anchors.centerIn: parent
                            barContent: root.musicBarContent
                            onOpenCenterDashboard: root.openCenterDashboard()
                            onCloseCenterDashboard: centerDashboardLeaveTimer.restart()
                            onToggleCenterDashboard: root.toggleCenterDashboard()
                            onToggleMusic: root.toggleCenterDashboard()
                            onOpenMusic: root.openCenterDashboard()
                            onToggleControls: root.toggleCenterDashboard()
                        }

                        /* Right: System Tray & Controls */
                        BarRight {
                            id: pillRightItem
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            showBackground: false
                            vertical: false
                            anchorWindow: pillFullBarWindow
                            notifCount: (notificationServer && notificationServer.trackedNotifications) ? notificationServer.trackedNotifications.values.length : 0
                            onOpenMixer: root.openMixer()
                            onCloseMixer: mixerLeaveTimer.restart()
                            onToggleMixer: root.toggleMixer()
                            onOpenBrightness: root.openBrightness()
                            onCloseBrightness: brightnessLeaveTimer.restart()
                            onToggleBrightness: root.toggleBrightness()
                            onOpenBattery: root.openBattery()
                            onCloseBattery: batteryLeaveTimer.restart()
                            onToggleBattery: root.toggleBattery()
                            onOpenTray: root.openTray()
                            onCloseTray: trayLeaveTimer.restart()
                            onToggleTray: root.toggleTray()
                            onToggleControls: root.toggleControls()
                            onOpenPower: root.openPower()
                        }
                    }
                }
            }
        }
    }

    /* ── Pill Mode: Connected Continuous Full Vertical Floating Bar (Left / Right) ── */
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: pillFullVerticalBarWindow
            required property var modelData

            screen: modelData
            color: "transparent"
            WlrLayershell.namespace: "carbon-bar-pill-vert"
            WlrLayershell.layer: WlrLayer.Top
            exclusionMode: ExclusionMode.Ignore
            aboveWindows: true
            anchors {
                top: true
                bottom: true
                left: root.mainBarEdge === "left"
                right: root.mainBarEdge === "right"
            }
            margins {
                top: 8
                bottom: 8
                left: root.mainBarEdge === "left" ? 8 : 0
                right: root.mainBarEdge === "right" ? 8 : 0
            }

            implicitWidth: 38
            visible: false

            Rectangle {
                id: pillFullVertCapsule
                anchors.fill: parent
                radius: 19
                color: Theme.bg
                border.color: Theme.outline
                border.width: 1

                Item {
                    anchors.fill: parent
                    anchors.topMargin: 8
                    anchors.bottomMargin: 8

                    /* Top: Workspaces & App Launcher */
                    BarLeft {
                        id: pillVertLeftItem
                        anchors.top: parent.top
                        anchors.horizontalCenter: parent.horizontalCenter
                        showBackground: false
                        vertical: true
                        onOpenLauncher: root.openLauncher()
                    }

                    /* Center: Mini Music & Clock Indicator */
                    Item {
                        anchors.centerIn: parent
                        width: 32
                        height: 52

                        Column {
                            anchors.centerIn: parent
                            spacing: 4

                            Rectangle {
                                width: 22
                                height: 22
                                radius: 11
                                color: Theme.bgAlt
                                border.color: Theme.accent
                                border.width: 1.5
                                anchors.horizontalCenter: parent.horizontalCenter
                                clip: true

                                Image {
                                    anchors.fill: parent
                                    source: root.mprisArtUrl
                                    sourceSize: Qt.size(44, 44)
                                    fillMode: Image.PreserveAspectCrop
                                    visible: root.mprisHasTrack && root.mprisArtUrl.length > 0
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: "music_note"
                                    font.family: Theme.fontIcon
                                    font.pixelSize: 14
                                    color: Theme.accent
                                    visible: !root.mprisHasTrack || root.mprisArtUrl.length === 0
                                }
                            }

                            Text {
                                text: {
                                    let d = new Date()
                                    let h = d.getHours() % 12
                                    if (h === 0) h = 12
                                    let m = d.getMinutes()
                                    return (h < 10 ? "0" : "") + h + ":" + (m < 10 ? "0" : "") + m
                                }
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: Theme.fontPx(9)
                                font.weight: Font.Bold
                                color: Theme.fg
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: false
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleMusic()
                        }
                    }

                    /* Bottom: System Controls */
                    BarRight {
                        id: pillVertRightItem
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                        showBackground: false
                        vertical: true
                        anchorWindow: pillFullVerticalBarWindow
                        notifCount: (notificationServer && notificationServer.trackedNotifications) ? notificationServer.trackedNotifications.values.length : 0
                        onOpenMixer: root.openMixer()
                        onCloseMixer: mixerLeaveTimer.restart()
                        onToggleMixer: root.toggleMixer()
                        onOpenBrightness: root.openBrightness()
                        onCloseBrightness: brightnessLeaveTimer.restart()
                        onToggleBrightness: root.toggleBrightness()
                        onOpenBattery: root.openBattery()
                        onCloseBattery: batteryLeaveTimer.restart()
                        onToggleBattery: root.toggleBattery()
                        onOpenTray: root.openTray()
                        onCloseTray: trayLeaveTimer.restart()
                        onToggleTray: root.toggleTray()
                        onToggleControls: root.toggleControls()
                        onOpenPower: root.openPower()
                    }
                }
            }
        }
    }

    /* ── Minimal Mode: Ultra-Lightweight Single Floating Dynamic Island ── */
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: minimalIslandWindow
            required property var modelData

            screen: modelData
            color: "transparent"
            WlrLayershell.namespace: "carbon-bar-minimal"
            WlrLayershell.layer: WlrLayer.Top
            exclusionMode: root.islandPersistent ? ExclusionMode.Normal : ExclusionMode.Ignore
            exclusiveZone: root.islandPersistent ? Math.max(0, (root.islandStyle === "notch" ? (root.notchHeight + root.notchAppGap) : (root.pillHeight + (root.mainBarEdge !== "bottom" ? 8 : 0) + root.pillAppGap))) : 0
            WlrLayershell.keyboardFocus: (root.islandHovered || islandHov.hovered) ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
            Keys.forwardTo: [minimalIslandItem]
            aboveWindows: true
            anchors {
                top: root.mainBarEdge !== "bottom"
                bottom: root.mainBarEdge === "bottom"
            }
            margins {
                top: 0
                bottom: 0
            }

            implicitHeight: Math.max(root.barHeight + 28, minimalIslandItem.height + 16)
            implicitWidth: 600
            visible: root.barMode === "minimal"

            mask: Region {
                item: root.islandRevealed ? minimalIslandItem : edgeTrigger
            }

            Item {
                id: edgeTrigger
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: root.mainBarEdge !== "bottom" ? parent.top : undefined
                anchors.bottom: root.mainBarEdge === "bottom" ? parent.bottom : undefined
                width: Math.max(minimalIslandItem.width, 360)
                height: 8
                visible: !root.islandPersistent

                HoverHandler {
                    id: edgeHov
                    onHoveredChanged: {
                        if (edgeHov.hovered) {
                            islandHoverLeaveTimer.stop()
                            root.islandHovered = true
                        }
                    }
                }
            }

            Timer {
                id: islandHoverLeaveTimer
                interval: 350
                onTriggered: {
                    if (!edgeHov.hovered && !islandHov.hovered) {
                        root.islandHovered = false
                    }
                }
            }

            MinimalIsland {
                id: minimalIslandItem
                attachedBottom: root.mainBarEdge === "bottom"
                islandStyle: root.islandStyle
                islandOpacity: root.minimalOpacity
                pillHeight: root.pillHeight
                notchHeight: root.notchHeight
                notifCount: (notificationServer && notificationServer.trackedNotifications) ? notificationServer.trackedNotifications.values.length : 0
                anchors.horizontalCenter: parent.horizontalCenter

                y: {
                    if (root.mainBarEdge === "bottom") {
                        return root.islandRevealed
                            ? (parent.height - height - ((root.islandStyle === "notch") ? 0 : 8))
                            : (parent.height + 10)
                    } else {
                        return root.islandRevealed
                            ? ((root.islandStyle === "notch") ? 0 : 8)
                            : (-height - 10)
                    }
                }
                opacity: root.islandRevealed ? 1.0 : 0.0

                Behavior on y {
                    NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
                }
                Behavior on opacity {
                    NumberAnimation { duration: 200 }
                }

                HoverHandler {
                    id: islandHov
                    onHoveredChanged: {
                        if (islandHov.hovered) {
                            islandHoverLeaveTimer.stop()
                            root.islandHovered = true
                            minimalIslandItem.forceActiveFocus()
                        } else {
                            islandHoverLeaveTimer.restart()
                        }
                    }
                }

                Binding on currentPage {
                    value: root.islandPage
                }
                onCurrentPageChanged: {
                    if (root.islandPage !== currentPage) root.islandPage = currentPage
                }
                onOpenLauncher: root.openLauncher()
                onToggleControls: root.toggleControls()
                onOpenMixer: root.openMixer()
                onCloseMixer: mixerLeaveTimer.restart()
                onToggleMixer: root.toggleMixer()
                onOpenBrightness: root.openBrightness()
                onCloseBrightness: brightnessLeaveTimer.restart()
                onToggleBrightness: root.toggleBrightness()
                onOpenBattery: root.openBattery()
                onCloseBattery: batteryLeaveTimer.restart()
                onToggleBattery: root.toggleBattery()
                onOpenWifi: root.openWifi()
                onCloseWifi: wifiLeaveTimer.restart()
                onToggleWifi: root.toggleWifi()
                onOpenBt: root.openBt()
                onCloseBt: btLeaveTimer.restart()
                onToggleBt: root.toggleBt()
                onOpenNotif: root.openNotif()
                onCloseNotif: notifLeaveTimer.restart()
                onToggleNotif: root.toggleNotif()
                onOpenCalendar: root.openCalendar()
                onCloseCalendar: {
                    calendarLeaveTimer.restart()
                    if (root.centerDashboardOpen && !root.centerDashboardHovered) {
                        centerDashboardLeaveTimer.interval = 1000
                        centerDashboardLeaveTimer.restart()
                    }
                }
                onToggleCalendar: root.toggleCalendar()
                onOpenSmallMusic: root.openSmallMusic()
                onCloseSmallMusic: smallMusicLeaveTimer.restart()
                onToggleSmallMusic: root.toggleSmallMusic()
                onSwitchIslandStyle: (s) => root.switchIslandStyle(s)
                onConvertToPill: root.switchBarMode("pill")
                onConvertToNotch: root.switchBarMode("notch")
                onToggleSpotlight: root.toggleSpotlight()
                onOpenSpotlight: root.openSpotlight()
            }
        }
    }

    /* ── Small Music Overlay Window (Compact Dropdown Below Island) ── */
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: smallMusicWindow
            required property var modelData

            screen: modelData
            color: "transparent"
            WlrLayershell.namespace: "carbon-music-small"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: root.smallMusicOpen ? (root.barMode === "minimal" ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None) : WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            aboveWindows: true
            anchors {
                top: root.mainBarEdge !== "bottom"
                bottom: root.mainBarEdge === "bottom"
            }
            margins {
                top: root.popupTopMargin
                bottom: root.popupBottomMargin
            }

            implicitWidth: smallMusicItem.implicitWidth
            implicitHeight: smallMusicItem.implicitHeight
            visible: (root.smallMusicOpen || smallMusicItem.animatingOut) && root.barMode !== "minimal"

            mask: Region {
                item: (root.smallMusicOpen || smallMusicItem.animatingOut) ? smallMusicItem : null
            }

            SmallMusicOverlay {
                id: smallMusicItem
                anchors.centerIn: parent
                focus: root.smallMusicOpen
                Keys.onEscapePressed: event => {
                    root.closeSmallMusic()
                    event.accepted = true
                }
                open: root.smallMusicOpen
                attachedBottom: root.mainBarEdge === "bottom"
                onCloseRequested: root.closeSmallMusic()
                HoverHandler {
                    id: smallMusicHov
                    onHoveredChanged: {
                        root.smallMusicHovered = smallMusicHov.hovered
                        if (root.smallMusicHovered) smallMusicLeaveTimer.stop()
                        else smallMusicLeaveTimer.restart()
                    }
                }
            }
        }
    }



    /* Music island: floats top-centre, transparent, independent of the bar.
     * Full-screen window (all four anchors, ukishima-style) so the window
     * resolves its real width; the pill self-centres inside it and the mask
     * Region confines pointer input to the pill. */
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: musicWindow
            required property var modelData

            screen: modelData
            color: "transparent"
            WlrLayershell.namespace: "carbon-music"
            WlrLayershell.layer: WlrLayer.Overlay
            exclusionMode: ExclusionMode.Ignore
            aboveWindows: true
            anchors {
                top: root.musicBarEdge !== "bottom"
                bottom: root.musicBarEdge === "bottom"
            }
            margins {
                top: root.musicBarEdge !== "bottom" ? (root.barMode === "notch" ? 36 : 48) : 0
                bottom: root.musicBarEdge === "bottom" ? (root.barMode === "notch" ? 36 : 48) : 0
            }

            implicitWidth: 600
            implicitHeight: 360
            visible: (!root.musicHidden || musicItem.animatingOut)

            mask: Region {
                item: root.musicOpen ? musicItem.cardItem : null
            }

            MusicMod {
                id: musicItem
                anchors.centerIn: parent
                attachedBottom: root.musicBarEdge === "bottom"
                barMode: root.barMode
                pinned: root.musicPinned
                externalOpen: root.musicOpen
                onPanelHoverChanged: (hovered) => {
                    if (hovered) {
                        root.musicHovered = true
                        musicLeaveTimer.stop()
                    } else {
                        root.musicHovered = false
                        musicLeaveTimer.restart()
                    }
                }
            }
        }
    }

    /* ── Notch Mode: Curved 3-notch bar ──────────────────────────────── */
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: notchBarWindow
            required property var modelData

            screen: modelData
            color: "transparent"
            WlrLayershell.namespace: "carbon-bar-notch"
            WlrLayershell.layer: WlrLayer.Top
            exclusionMode: root.barMode === "notch" ? ExclusionMode.Normal : ExclusionMode.Ignore
            exclusiveZone: root.barMode === "notch" ? Math.max(0, root.notchHeight + root.notchAppGap) : 0
            aboveWindows: true
            anchors {
                top: root.mainBarEdge !== "bottom"
                bottom: root.mainBarEdge === "bottom"
                left: true
                right: true
            }
            margins {
                top: 0
                bottom: 0
            }

            implicitHeight: 280
            WlrLayershell.keyboardFocus: root.centerDashboardOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            visible: root.barMode === "notch"

            Item {
                id: notchKeyHandler
                anchors.fill: parent
                focus: root.centerDashboardOpen
                Keys.enabled: root.centerDashboardOpen
                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Escape) {
                        console.log("[notchBarWindow] ESCAPE PRESSED - closing center dashboard")
                        root.closeCenterDashboard()
                        event.accepted = true
                    }
                }
                Keys.onEscapePressed: (event) => {
                    console.log("[notchBarWindow] onEscapePressed - closing center dashboard")
                    root.closeCenterDashboard()
                    event.accepted = true
                }
            }

            mask: (root.barMode === "notch" && notchBarWindow.visible) ? notchMask : null
            Region {
                id: notchMask
                Region {
                    x: notchLeftItem.x
                    y: root.mainBarEdge === "bottom" ? (notchBarWindow.height - notchLeftItem.height) : 0
                    width: notchLeftItem.width
                    height: notchLeftItem.height
                }
                Region {
                    x: notchCenterItem.x
                    y: root.mainBarEdge === "bottom" ? (notchBarWindow.height - notchCenterItem.height) : 0
                    width: root.musicBarEdge === root.mainBarEdge ? notchCenterItem.width : 0
                    height: root.musicBarEdge === root.mainBarEdge ? notchCenterItem.height : 0
                }
                Region {
                    x: notchRightItem.x
                    y: root.mainBarEdge === "bottom" ? (notchBarWindow.height - notchRightItem.height) : 0
                    width: notchRightItem.width
                    height: notchRightItem.height
                }
            }

            NotchBarLeft {
                id: notchLeftItem
                notchOpacity: root.notchOpacity
                filletRadius: root.notchEarRadius
                bottomRadius: root.sideNotchBottomRadius
                height: root.notchHeight
                implicitHeight: root.notchHeight
                attachedBottom: root.mainBarEdge === "bottom"
                anchors.top: root.mainBarEdge !== "bottom" ? parent.top : undefined
                anchors.bottom: root.mainBarEdge === "bottom" ? parent.bottom : undefined
                anchors.left: parent.left
                leftFillet: false
                rightFillet: true
                onOpenLauncher: root.openLauncher()
            }

            NotchBarCenter {
                id: notchCenterItem
                notchOpacity: root.notchOpacity
                filletRadius: root.notchEarRadius
                bottomRadius: root.notchBottomRadius
                isExpanded: root.centerDashboardOpen
                visible: root.musicBarEdge === root.mainBarEdge
                barContent: root.musicBarContent
                attachedBottom: root.mainBarEdge === "bottom"
                hasAttachedPopup: (root.calendarOpen || root.smallMusicOpen) && !root.centerDashboardOpen
                anchors.top: root.mainBarEdge !== "bottom" ? parent.top : undefined
                anchors.bottom: root.mainBarEdge === "bottom" ? parent.bottom : undefined
                anchors.horizontalCenter: parent.horizontalCenter
                leftFillet: true
                rightFillet: true
                onToggleCenterDashboard: root.toggleCenterDashboard()
                onCloseCenterDashboard: root.closeCenterDashboard()
                onToggleMusic: root.toggleCenterDashboard()
                onOpenMusic: root.toggleCenterDashboard()
                onToggleControls: root.toggleCenterDashboard()
            }

            NotchBarRight {
                id: notchRightItem
                notchOpacity: root.notchOpacity
                filletRadius: root.notchEarRadius
                bottomRadius: root.sideNotchBottomRadius
                height: root.notchHeight
                implicitHeight: root.notchHeight
                attachedBottom: root.mainBarEdge === "bottom"
                hasAttachedPopup: false
                anchors.top: root.mainBarEdge !== "bottom" ? parent.top : undefined
                anchors.bottom: root.mainBarEdge === "bottom" ? parent.bottom : undefined
                anchors.right: parent.right
                leftFillet: true
                rightFillet: false
                onOpenMixer: root.openMixer()
                onCloseMixer: mixerLeaveTimer.restart()
                onToggleMixer: root.toggleMixer()
                onOpenBrightness: root.openBrightness()
                onCloseBrightness: brightnessLeaveTimer.restart()
                onToggleBrightness: root.toggleBrightness()
                onOpenBattery: root.openBattery()
                onCloseBattery: batteryLeaveTimer.restart()
                onToggleBattery: root.toggleBattery()
                onOpenTray: root.openTray()
                onCloseTray: trayLeaveTimer.restart()
                onToggleTray: root.toggleTray()
                onOpenPower: root.openPower()
            }
        }
    }

    /* ── Concept 3: Kinetic Shard (Cybernetic Origami & Asymmetric Crystal) ── */
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: kineticShardWindow
            required property var modelData

            screen: modelData
            color: "transparent"
            WlrLayershell.namespace: "carbon-kinetic-shard"
            WlrLayershell.layer: WlrLayer.Top
            exclusionMode: ExclusionMode.Ignore
            aboveWindows: true
            anchors {
                top: true
            }
            margins {
                top: 8
            }

            implicitWidth: 720
            implicitHeight: 46
            visible: root.barMode === "shard"

            KineticShardBar {
                id: kineticShardItem
                anchors.centerIn: parent
                onOpenLauncher: root.openLauncher()
                onToggleCenterDashboard: root.toggleCenterDashboard()
                onOpenCenterDashboard: root.openCenterDashboard()
                onToggleControls: root.toggleControls()
                onOpenMixer: root.openMixer()
                onToggleMixer: root.toggleMixer()
                onOpenWifi: root.openWifi()
                onToggleWifi: root.toggleWifi()
                onOpenBattery: root.openBattery()
                onToggleBattery: root.toggleBattery()
                onOpenPower: root.openPower()
            }
        }
    }

    /* ── Nucleus Mode: Fullscreen Radial Desktop Layer ── */
    readonly property QtObject nucleusHubItem: QtObject {
        property bool hubOpen: false
        property bool isClosing: false
        property bool notifPanelOpen: false
        property string activeMode: "hub"
        signal toggleRequested()
        signal openRequested()
        signal closeRequested()
        signal focusLobeRequested(string lobe)
        signal wallpaperModeRequested()
        signal launcherModeRequested()
        signal wifiModeRequested()
        signal bluetoothModeRequested()
        signal calendarModeRequested()

        property real lastToggleTime: 0
        function toggle() { 
            var now = Date.now()
            if (now - lastToggleTime < 350) return
            lastToggleTime = now
            if (!hubOpen || isClosing) {
                isClosing = false
                hubOpen = true
                openRequested()
            } else {
                close()
            }
        }
        function open() { 
            isClosing = false
            hubOpen = true
            openRequested() 
        }
        function close() { 
            if (hubOpen && !isClosing) {
                isClosing = true
                closeRequested()
            }
        }
        function focusLobe(l) { 
            isClosing = false
            hubOpen = true
            focusLobeRequested(l) 
        }
        function openWallpaperMode() { 
            isClosing = false
            hubOpen = true
            wallpaperModeRequested() 
        }
        function openLauncherMode() { 
            isClosing = false
            hubOpen = true
            launcherModeRequested() 
        }
        function toggleLauncher() {
            if (!hubOpen || isClosing) {
                isClosing = false
                hubOpen = true
                launcherModeRequested()
            } else {
                close()
            }
        }
        signal toggleLyricsRequested()
        function toggleLyrics() {
            toggleLyricsRequested()
        }
        function openWifiMode() {
            isClosing = false
            hubOpen = true
            wifiModeRequested()
        }
        function openBluetoothMode() {
            isClosing = false
            hubOpen = true
            bluetoothModeRequested()
        }
        function openCalendarMode() {
            isClosing = false
            hubOpen = true
            activeMode = "calendar"
            calendarModeRequested()
        }
        signal powerModeRequested()
        function openPowerMode() {
            isClosing = false
            hubOpen = true
            activeMode = "power"
            powerModeRequested()
        }
        signal powerActionRequested(string action)
        function triggerPowerAction(action) {
            isClosing = false
            hubOpen = true
            powerActionRequested(action)
        }
        signal volumeActionRequested(string action, bool wasClosed)
        signal brightnessActionRequested(string action, bool wasClosed)
        function volumeAction(action) {
            var wasClosed = (!hubOpen || isClosing)
            if (wasClosed) {
                isClosing = false
                hubOpen = true
                openRequested()
            }
            volumeActionRequested(action, wasClosed)
        }
        function brightnessAction(action) {
            var wasClosed = (!hubOpen || isClosing)
            if (wasClosed) {
                isClosing = false
                hubOpen = true
                openRequested()
            }
            brightnessActionRequested(action, wasClosed)
        }
        signal notifPanelRequested()
        function openNotificationPanel() {
            isClosing = false
            hubOpen = true
            openRequested()
            notifPanelRequested()
        }
    }

    Variants {
        model: Quickshell.screens

        // 1. Resting Dot (Sits on desktop below windows, never blocks apps)
        PanelWindow {
            id: nucleusRestingWindow
            required property var modelData

            screen: modelData
            color: "transparent"
            WlrLayershell.namespace: "carbon-nucleus-resting"
            WlrLayershell.layer: WlrLayer.Bottom
            exclusionMode: ExclusionMode.Ignore
            anchors {}
            implicitWidth: 80
            implicitHeight: 80

            visible: root.barMode === "nucleus" && !root.nucleusHubItem.hubOpen

            mask: Region {
                item: nucleusRestingCenterDot
            }

            Item {
                id: nucleusRestingCenterDot
                anchors.centerIn: parent
                width: 80
                height: 80
                opacity: root.workspaceOsdActive ? 0.0 : 1.0
                visible: opacity > 0.002
                Behavior on opacity {
                    NumberAnimation { duration: 140 }
                }

                property bool restingPressing: false
                property real restingHoldProgress: 0.0
                property bool justTriggeredPower: false
                readonly property bool shouldSpin: {
                    if (!nucleusRestingWindow.visible || !nucleusRestingCenterDot.visible) return false
                    if (root.nucleusRestingSpin === "never" || root.nucleusRestingSpin === false) return false
                    if (root.nucleusRestingSpin === "always" || root.nucleusRestingSpin === true) return true
                    return (restingMouseArea && restingMouseArea.containsMouse) || restingPressing
                }

                FrameAnimation {
                    running: nucleusRestingCenterDot.shouldSpin
                    onTriggered: {
                        var dt = frameTime > 0.0 ? Math.min(0.05, frameTime) : 0.016
                        ring1Orbit.rotation = (ring1Orbit.rotation + (20.0 * dt)) % 360
                        ring2Orbit.rotation = (ring2Orbit.rotation - ((360.0 / 28.0) * dt)) % 360
                    }
                }

                // Ring 1 (Inner, 2 electrons)
                Rectangle {
                    anchors.centerIn: parent
                    width: 40; height: 40; radius: 20
                    color: "transparent"
                    border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.22)
                    border.width: 1

                    Item {
                        id: ring1Orbit
                        anchors.centerIn: parent
                        width: parent.width; height: parent.height
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: -3.5; width: 6; height: 6; radius: 3; color: Theme.accent
                        }
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: parent.height - 2.5; width: 6; height: 6; radius: 3; color: Theme.accent
                        }
                    }
                }

                // Ring 2 (Outer, 4 electrons)
                Rectangle {
                    anchors.centerIn: parent
                    width: 72; height: 72; radius: 36
                    color: "transparent"
                    border.color: Qt.rgba(Theme.accent.r, Theme.accent.g, Theme.accent.b, 0.16)
                    border.width: 1

                    Item {
                        id: ring2Orbit
                        anchors.centerIn: parent
                        width: parent.width; height: parent.height
                        rotation: 45
                        Repeater {
                            model: 4
                            delegate: Item {
                                anchors.fill: parent
                                rotation: index * 90
                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: -3.5; width: 6; height: 6; radius: 3; color: Theme.accent
                                }
                            }
                        }
                    }
                }

                // 16px center nucleus dot
                Rectangle {
                    anchors.centerIn: parent
                    width: 16; height: 16; radius: 8
                    color: Theme.accent
                    border.color: "#FFFFFF"
                    border.width: 1.0
                }

                // Clockwise Halo Ring (radius 27px, fills white clockwise over 600ms on hold)
                Shape {
                    id: restingHoldRingShape
                    anchors.centerIn: parent
                    width: 54
                    height: 54
                    visible: nucleusRestingCenterDot.restingHoldProgress > 0.001
                    layer.enabled: true
                    layer.samples: 4
                    ShapePath {
                        strokeWidth: 2.5
                        strokeColor: "#FFFFFF"
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        startX: 27
                        startY: 0
                        PathAngleArc {
                            centerX: 27
                            centerY: 27
                            radiusX: 27
                            radiusY: 27
                            startAngle: -90
                            sweepAngle: Math.max(0.1, Math.min(359.9, nucleusRestingCenterDot.restingHoldProgress * 360.0))
                        }
                    }
                }

                FrameAnimation {
                    running: nucleusRestingCenterDot.restingPressing || nucleusRestingCenterDot.restingHoldProgress > 0.0
                    onTriggered: {
                        var dt = frameTime * 1000.0
                        if (nucleusRestingCenterDot.restingPressing) {
                            nucleusRestingCenterDot.restingHoldProgress = Math.min(1.0, nucleusRestingCenterDot.restingHoldProgress + dt / 600.0)
                            if (nucleusRestingCenterDot.restingHoldProgress >= 1.0) {
                                nucleusRestingCenterDot.restingHoldProgress = 0.0
                                nucleusRestingCenterDot.restingPressing = false
                                nucleusRestingCenterDot.justTriggeredPower = true
                                if (root.nucleusHubItem) root.nucleusHubItem.openPowerMode()
                            }
                        } else if (nucleusRestingCenterDot.restingHoldProgress > 0.0) {
                            nucleusRestingCenterDot.restingHoldProgress = Math.max(0.0, nucleusRestingCenterDot.restingHoldProgress - dt * 0.004)
                        }
                    }
                }

                MouseArea {
                    id: restingMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton
                    onPressed: {
                        nucleusRestingCenterDot.justTriggeredPower = false
                        nucleusRestingCenterDot.restingPressing = true
                    }
                    onReleased: nucleusRestingCenterDot.restingPressing = false
                    onCanceled: nucleusRestingCenterDot.restingPressing = false
                    onClicked: {
                        nucleusRestingCenterDot.restingPressing = false
                        if (nucleusRestingCenterDot.justTriggeredPower) {
                            nucleusRestingCenterDot.justTriggeredPower = false
                            return
                        }
                        if (nucleusRestingCenterDot.restingHoldProgress < 0.99) {
                            if (root.nucleusHubItem) root.nucleusHubItem.open()
                        }
                    }
                }
            }
        }
    }

    Variants {
        model: Quickshell.screens

        // 2. Opened Radial Hub (Always on overlay layer, appears above all windows when active)
        PanelWindow {
            id: nucleusHubWindow
            required property var modelData

            screen: modelData
            color: "transparent"
            WlrLayershell.namespace: "carbon-nucleus-hub"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: (root.barMode === "nucleus" && root.nucleusHubItem.hubOpen && !root.nucleusHubItem.isClosing) ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            aboveWindows: true
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            visible: root.barMode === "nucleus" && (root.nucleusHubItem.hubOpen || root.nucleusHubItem.isClosing)

            NucleusHub {
                id: nucleusHubItemInstance
                anchors.fill: parent
                onOpenLauncher: root.openLauncher()
                onOpenWallpapers: root.openWallpaperPicker()
                onOpenPower: root.openPower()
                onRequestLock: sessionLock.lock()
                onClosingStarted: {
                    root.nucleusHubItem.isClosing = true
                }
                onCloseRequested: {
                    root.nucleusHubItem.hubOpen = false
                    root.nucleusHubItem.isClosing = false
                    root.nucleusHubItem.notifPanelOpen = false
                    root.nucleusHubItem.activeMode = "hub"
                }
                onActiveModeChanged: {
                    root.nucleusHubItem.activeMode = activeMode
                }
                onNotifPanelOpenChanged: {
                    root.nucleusHubItem.notifPanelOpen = notifPanelOpen
                }

                Connections {
                    target: root.nucleusHubItem
                    function onToggleRequested() { nucleusHubItemInstance.toggle() }
                    function onOpenRequested() { nucleusHubItemInstance.open() }
                    function onCloseRequested() { nucleusHubItemInstance.close() }
                    function onFocusLobeRequested(lobe) { nucleusHubItemInstance.focusLobe(lobe) }
                    function onWallpaperModeRequested() { nucleusHubItemInstance.openWallpaperMode() }
                    function onLauncherModeRequested() { nucleusHubItemInstance.openLauncherMode() }
                    function onToggleLyricsRequested() { nucleusHubItemInstance.toggleLyrics() }
                    function onWifiModeRequested() { nucleusHubItemInstance.openWifiMode() }
                    function onBluetoothModeRequested() { nucleusHubItemInstance.openBluetoothMode() }
                    function onCalendarModeRequested() { nucleusHubItemInstance.openCalendarMode() }
                    function onPowerModeRequested() { nucleusHubItemInstance.openPowerMode() }
                    function onPowerActionRequested(action) { nucleusHubItemInstance.triggerPowerAction(action) }
                    function onVolumeActionRequested(action, wasClosed) {
                        if (wasClosed && action !== "open") {
                            nucleusHubItemInstance.osdOpenedHub = true
                        }
                        if (action === "up") nucleusHubItemInstance.stepVolume(0.05)
                        else if (action === "down") nucleusHubItemInstance.stepVolume(-0.05)
                        else if (action === "toggle-mute") nucleusHubItemInstance.toggleVolumeMute()
                        else if (action === "open") nucleusHubItemInstance.openVolumeMode()
                    }
                    function onBrightnessActionRequested(action, wasClosed) {
                        if (wasClosed && action !== "open") {
                            nucleusHubItemInstance.osdOpenedHub = true
                        }
                        if (action === "up") nucleusHubItemInstance.stepBrightness(0.05)
                        else if (action === "down") nucleusHubItemInstance.stepBrightness(-0.05)
                        else if (action === "open") nucleusHubItemInstance.openBrightnessMode()
                    }
                    function onNotifPanelRequested() {
                        nucleusHubItemInstance.notifPanelOpen = true
                        nucleusHubItemInstance.focusedLobe = "alerts"
                    }
                }
            }
        }
    }

    /* ── Nucleus Mode-Switch Transition Overlay Window (~2.3s) ── */
    Variants {
        model: root.nucleusTransitionActive ? Quickshell.screens : []

        PanelWindow {
            id: nucleusTransitionWindow
            required property var modelData

            screen: modelData
            color: "transparent"
            WlrLayershell.namespace: "carbon-nucleus-transition"
            WlrLayershell.layer: WlrLayer.Overlay
            exclusionMode: ExclusionMode.Ignore
            aboveWindows: true
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            visible: true

            NucleusTransitionOverlay {
                id: transitionOverlayItem
                anchors.fill: parent
                isPrimaryScreen: (modelData === Quickshell.screens[0])
                transitionWord: root.nucleusTransitionWord
                transitionEnabled: root.nucleusTransitionEnabled
                transitionAnimation: root.nucleusTransitionAnimation

                Component.onCompleted: {
                    play()
                }

                onTransitionFinished: {
                    root.finishNucleusTransition()
                }
            }
        }
    }

    /* ── Notch Center Island Window (When musicBarEdge is on separate edge or main bar is vertical) ── */
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: notchCenterWindow
            required property var modelData

            screen: modelData
            color: "transparent"
            WlrLayershell.namespace: "carbon-bar-notch-center"
            WlrLayershell.layer: WlrLayer.Top
            exclusionMode: ExclusionMode.Ignore
            aboveWindows: true
            anchors {
                top: root.musicBarEdge !== "bottom"
                bottom: root.musicBarEdge === "bottom"
            }
            implicitHeight: 34
            implicitWidth: separateNotchCenter.implicitWidth
            visible: root.barMode === "notch" && (root.musicBarEdge !== root.mainBarEdge || root.mainBarEdge === "left" || root.mainBarEdge === "right")

            NotchBarCenter {
                id: separateNotchCenter
                barContent: root.musicBarContent
                attachedBottom: root.musicBarEdge === "bottom"
                hasAttachedPopup: root.centerDashboardOpen || root.calendarOpen || root.smallMusicOpen
                anchors.fill: parent
                onOpenMusicHover: root.openCenterDashboard()
                onCloseMusicHover: centerDashboardLeaveTimer.restart()
                onOpenCenterDashboard: root.openCenterDashboard()
                onCloseCenterDashboard: centerDashboardLeaveTimer.restart()
                onToggleCenterDashboard: root.toggleCenterDashboard()
                onToggleMusic: root.toggleCenterDashboard()
                onOpenMusic: root.openCenterDashboard()
                onToggleControls: root.toggleCenterDashboard()
            }
        }
    }

    /* Launcher popup: centred modal over the desktop */
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: launcherWindow
            required property var modelData

            screen: modelData
            color: "transparent"
            WlrLayershell.namespace: "carbon-launcher"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: root.launcherOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; left: true; right: true; bottom: true }

            aboveWindows: true
            visible: root.launcherOpen || (launcherItem && launcherItem.animatingOut)

            MouseArea {
                anchors.fill: parent
                enabled: root.launcherOpen
                onClicked: (mouse) => {
                    var lw = launcherItem.width
                    var lh = launcherItem.height
                    var lx = launcherItem.x
                    var ly = launcherItem.y
                    if (mouse.x < lx || mouse.x > lx + lw || mouse.y < ly || mouse.y > ly + lh)
                        root.closeLauncher()
                }
            }

            LauncherMod {
                id: launcherItem
                open: root.launcherOpen
                barEdge: root.mainBarEdge
                onCloseRequested: root.closeLauncher()
            }
        }
    }

    /* Spotlight Command Palette: centred floating modal over the desktop (Super + K) */
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: spotlightWindow
            required property var modelData

            screen: modelData
            color: "transparent"
            WlrLayershell.namespace: "carbon-spotlight"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: root.spotlightOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; left: true; right: true; bottom: true }

            aboveWindows: true
            visible: root.spotlightOpen || (spotlightItem && spotlightItem.animatingOut)

            MouseArea {
                anchors.fill: parent
                enabled: root.spotlightOpen
                onClicked: (mouse) => {
                    var sw = spotlightItem.width
                    var sh = spotlightItem.height
                    var sx = spotlightItem.x
                    var sy = spotlightItem.y
                    if (mouse.x < sx || mouse.x > sx + sw || mouse.y < sy || mouse.y > sy + sh)
                        root.closeSpotlight()
                }
            }

            SpotlightModal {
                id: spotlightItem
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -40
                barMode: root.barMode
                open: root.spotlightOpen
                shellOpacity: root.shellOpacity
                onCloseRequested: root.closeSpotlight()
            }
        }
    }

    /* Wallhaven Wallpaper Picker popup: bottom-center modal over the desktop */
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: wallpaperPickerWindow
            required property var modelData

            screen: modelData
            color: "transparent"
            WlrLayershell.namespace: "carbon-wallpaper-picker"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: root.wallpaperPickerOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; left: true; right: true; bottom: true }

            aboveWindows: true
            visible: root.wallpaperPickerOpen || (wpItem && wpItem.animatingOut)

            /* Backdrop click dismisses wallpaper picker */
            MouseArea {
                anchors.fill: parent
                enabled: root.wallpaperPickerOpen
                onClicked: root.closeWallpaperPicker()
            }

            WallpaperPicker {
                id: wpItem
                anchors.fill: parent
                open: root.wallpaperPickerOpen
                activeSource: root.wallpaperSource
                onCloseRequested: root.closeWallpaperPicker()
                onWallpaperApplyStarted: (name) => root.startWallpaperTransition(name)
                onWallpaperApplyFinished: () => root.finishWallpaperTransition()

                Connections {
                    target: root
                    function onWallpaperSourceChanged() {
                        wpItem.activeSource = root.wallpaperSource
                    }
                    function onWallpaperPickerOpenChanged() {
                        if (root.wallpaperPickerOpen) {
                            wpItem.activeSource = root.wallpaperSource
                        }
                    }
                }
            }
        }
    }

    /* Full-screen blurred wallpaper applying transition overlay (0:13 video reference) */
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: wallpaperTransitionWindow
            required property var modelData

            screen: modelData
            color: "transparent"
            WlrLayershell.namespace: "carbon-wallpaper-transition"
            WlrLayershell.layer: WlrLayer.Overlay
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; left: true; right: true; bottom: true }

            aboveWindows: true
            visible: root.wallpaperTransitionOpen

            WallpaperTransition {
                anchors.fill: parent
                active: root.wallpaperTransitionOpen
                pendingFinish: root.wallpaperTransitionPendingFinish
                statusText: root.wallpaperTransitionText
                onFinished: {
                    root.wallpaperTransitionOpen = false
                }
            }
        }
    }

    /* Mixer popup: (Centered below island in minimal mode, right-anchored in bar mode) */
    PanelWindow {
        id: mixerWindow
        screen: Quickshell.screens[0]
        color: "transparent"
        WlrLayershell.namespace: "carbon-mixer"
        WlrLayershell.layer: WlrLayer.Overlay
        exclusionMode: ExclusionMode.Ignore
        anchors {
            top: root.mainBarEdge !== "bottom" && root.mainBarEdge !== "right"
            bottom: root.mainBarEdge === "bottom" || root.mainBarEdge === "right"
            right: root.barMode !== "minimal"
        }
        margins {
            top: root.popupTopMargin
            bottom: root.popupBottomMargin
            right: root.popupRightMargin
        }

        implicitWidth: mixerItem.implicitWidth
        implicitHeight: mixerItem.implicitHeight

        visible: (root.mixerOpen || mixerItem.animatingOut) && root.mainBarEdge !== "left" && root.barMode !== "minimal"

        mask: Region {
            item: (root.mixerOpen || mixerItem.animatingOut) ? mixerItem : null
            x: 0; y: 0
            width: (root.mixerOpen || mixerItem.animatingOut) ? mixerItem.implicitWidth : 0
            height: (root.mixerOpen || mixerItem.animatingOut) ? mixerItem.implicitHeight : 0
        }

        MixerMod {
            id: mixerItem
            barMode: root.barMode
            barEdge: root.mainBarEdge
            notchOpacity: root.notchOpacity
            open: root.mixerOpen
            onCloseRequested: root.closeMixer()
            onAnyHoverChanged: {
                root.mixerHovered = mixerItem.anyHover
                if (root.mixerHovered) mixerLeaveTimer.stop()
                else mixerLeaveTimer.restart()
            }
        }
    }

    /* Brightness popup: (Centered below island in minimal mode, right-anchored in bar mode) */
    PanelWindow {
        id: brightnessWindow
        screen: Quickshell.screens[0]
        color: "transparent"
        WlrLayershell.namespace: "carbon-brightness"
        WlrLayershell.layer: WlrLayer.Overlay
        exclusionMode: ExclusionMode.Ignore
        anchors {
            top: root.mainBarEdge !== "bottom" && root.mainBarEdge !== "right"
            bottom: root.mainBarEdge === "bottom" || root.mainBarEdge === "right"
            right: root.barMode !== "minimal"
        }
        margins {
            top: root.popupTopMargin
            bottom: root.popupBottomMargin
            right: root.popupRightMargin
        }

        implicitWidth: brightnessItem.implicitWidth
        implicitHeight: brightnessItem.implicitHeight

        visible: (root.brightnessOpen || brightnessItem.animatingOut) && root.mainBarEdge !== "left" && root.barMode !== "minimal"

        mask: Region {
            item: (root.brightnessOpen || brightnessItem.animatingOut) ? brightnessItem : null
            x: 0; y: 0
            width: (root.brightnessOpen || brightnessItem.animatingOut) ? brightnessItem.implicitWidth : 0
            height: (root.brightnessOpen || brightnessItem.animatingOut) ? brightnessItem.implicitHeight : 0
        }

        BrightnessPopup {
            id: brightnessItem
            barMode: root.barMode
            barEdge: root.mainBarEdge
            notchOpacity: root.notchOpacity
            open: root.brightnessOpen
            onCloseRequested: root.closeBrightness()
            onAnyHoverChanged: {
                root.brightnessHovered = brightnessItem.anyHover
                if (root.brightnessHovered) brightnessLeaveTimer.stop()
                else brightnessLeaveTimer.restart()
            }
        }
    }

    /* Battery popup: (Centered below island in minimal mode, right-anchored in bar mode) */
    PanelWindow {
        id: batteryWindow
        screen: Quickshell.screens[0]
        color: "transparent"
        WlrLayershell.namespace: "carbon-battery"
        WlrLayershell.layer: WlrLayer.Overlay
        exclusionMode: ExclusionMode.Ignore
        anchors {
            top: root.mainBarEdge !== "bottom" && root.mainBarEdge !== "right"
            bottom: root.mainBarEdge === "bottom" || root.mainBarEdge === "right"
            right: root.barMode !== "minimal"
        }
        margins {
            top: root.popupTopMargin
            bottom: root.popupBottomMargin
            right: root.popupRightMargin
        }

        implicitWidth: batteryItem.implicitWidth
        implicitHeight: batteryItem.implicitHeight

        visible: (root.batteryOpen || batteryItem.animatingOut) && root.mainBarEdge !== "left" && root.barMode !== "minimal"

        mask: Region {
            item: (root.batteryOpen || batteryItem.animatingOut) ? batteryItem : null
            x: 0; y: 0
            width: (root.batteryOpen || batteryItem.animatingOut) ? batteryItem.implicitWidth : 0
            height: (root.batteryOpen || batteryItem.animatingOut) ? batteryItem.implicitHeight : 0
        }

        BatteryPopup {
            id: batteryItem
            barMode: root.barMode
            barEdge: root.mainBarEdge
            notchOpacity: root.notchOpacity
            open: root.batteryOpen
            onHoveredChanged: {
                root.batteryHovered = batteryItem.hovered
                if (root.batteryHovered) batteryLeaveTimer.stop()
                else batteryLeaveTimer.restart()
            }
        }
    }

    /* Wifi popup: (Centered below island in minimal mode, right-anchored in bar mode) */
    PanelWindow {
        id: wifiWindow
        screen: Quickshell.screens[0]
        color: "transparent"
        WlrLayershell.namespace: "carbon-wifi"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.wifiOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        anchors {
            top: root.mainBarEdge !== "bottom" && root.mainBarEdge !== "right"
            bottom: root.mainBarEdge === "bottom" || root.mainBarEdge === "right"
            right: root.barMode !== "minimal"
        }
        margins {
            top: root.popupTopMargin
            bottom: root.popupBottomMargin
            right: root.popupRightMargin
        }

        implicitWidth: wifiItem.implicitWidth
        implicitHeight: wifiItem.implicitHeight

        visible: (root.wifiOpen || wifiItem.animatingOut) && root.mainBarEdge !== "left" && root.barMode !== "minimal"

        mask: Region {
            item: (root.wifiOpen || wifiItem.animatingOut) ? wifiItem : null
            x: 0; y: 0
            width: (root.wifiOpen || wifiItem.animatingOut) ? wifiItem.implicitWidth : 0
            height: (root.wifiOpen || wifiItem.animatingOut) ? wifiItem.implicitHeight : 0
        }

        WifiPopup {
            id: wifiItem
            barMode: root.barMode
            barEdge: root.mainBarEdge
            notchOpacity: root.notchOpacity
            open: root.wifiOpen
            powerOn: root.wifiOn
            wifiName: root.wifiName
            onPowerToggled: (on) => root.toggleWifiPower()
            onRequestedClose: root.closeWifi()
            HoverHandler {
                id: wifiHov
                onHoveredChanged: {
                    root.wifiHovered = wifiHov.hovered
                    if (root.wifiHovered) wifiLeaveTimer.stop()
                    else wifiLeaveTimer.restart()
                }
            }
        }
    }

    /* Bluetooth popup: (Centered below island in minimal mode, right-anchored in bar mode) */
    PanelWindow {
        id: btWindow
        screen: Quickshell.screens[0]
        color: "transparent"
        WlrLayershell.namespace: "carbon-bluetooth"
        WlrLayershell.layer: WlrLayer.Overlay
        exclusionMode: ExclusionMode.Ignore
        anchors {
            top: root.mainBarEdge !== "bottom" && root.mainBarEdge !== "right"
            bottom: root.mainBarEdge === "bottom" || root.mainBarEdge === "right"
            right: root.barMode !== "minimal"
        }
        margins {
            top: root.popupTopMargin
            bottom: root.popupBottomMargin
            right: root.popupRightMargin
        }

        implicitWidth: btItem.implicitWidth
        implicitHeight: btItem.implicitHeight

        visible: (root.btOpen || btItem.animatingOut) && root.mainBarEdge !== "left" && root.barMode !== "minimal"

        mask: Region {
            item: (root.btOpen || btItem.animatingOut) ? btItem : null
            x: 0; y: 0
            width: (root.btOpen || btItem.animatingOut) ? btItem.implicitWidth : 0
            height: (root.btOpen || btItem.animatingOut) ? btItem.implicitHeight : 0
        }

        BtPopup {
            id: btItem
            barMode: root.barMode
            barEdge: root.mainBarEdge
            notchOpacity: root.notchOpacity
            open: root.btOpen
            powerOn: root.btOn
            btName: root.btName
            onPowerToggled: (on) => root.toggleBtPower()
            onRequestedClose: root.closeBt()
            HoverHandler {
                id: btHov
                onHoveredChanged: {
                    root.btHovered = btHov.hovered
                    if (root.btHovered) btLeaveTimer.stop()
                    else btLeaveTimer.restart()
                }
            }
        }
    }

    /* Tray overflow popup: Windows-style overflow showing running background apps */
    PanelWindow {
        id: trayWindow
        screen: Quickshell.screens[0]
        color: "transparent"
        WlrLayershell.namespace: "carbon-tray"
        WlrLayershell.layer: WlrLayer.Overlay
        exclusionMode: ExclusionMode.Ignore
        anchors {
            top: root.mainBarEdge !== "bottom" && root.mainBarEdge !== "right"
            bottom: root.mainBarEdge === "bottom" || root.mainBarEdge === "right"
            right: root.barMode !== "minimal"
        }
        margins {
            top: root.popupTopMargin
            bottom: root.popupBottomMargin
            right: root.popupRightMargin
        }

        implicitWidth: trayItem.implicitWidth
        implicitHeight: trayItem.implicitHeight

        visible: (root.trayOpen || trayItem.animatingOut) && root.mainBarEdge !== "left" && root.barMode !== "minimal"

        mask: Region {
            item: (root.trayOpen || trayItem.animatingOut) ? trayItem : null
            x: 0; y: 0
            width: (root.trayOpen || trayItem.animatingOut) ? trayItem.implicitWidth : 0
            height: (root.trayOpen || trayItem.animatingOut) ? trayItem.implicitHeight : 0
        }

        TrayPopup {
            id: trayItem
            barMode: root.barMode
            barEdge: root.mainBarEdge
            notchOpacity: root.notchOpacity
            open: root.trayOpen
            onHoveredChanged: {
                root.trayHovered = trayItem.hovered
                if (root.trayHovered) trayLeaveTimer.stop()
                else trayLeaveTimer.restart()
            }
            onRequestedClose: root.closeTray()
        }
    }

    /* Calendar popup: (Centered below island in minimal mode) */
    PanelWindow {
        id: calendarWindow
        screen: Quickshell.screens[0]
        color: "transparent"
        WlrLayershell.namespace: "carbon-calendar"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.calendarOpen ? (root.barMode === "minimal" ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None) : WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        anchors {
            top: root.mainBarEdge !== "bottom" && root.mainBarEdge !== "right"
            bottom: root.mainBarEdge === "bottom" || root.mainBarEdge === "right"
            right: root.barMode !== "minimal"
        }
        margins {
            top: root.popupTopMargin
            bottom: root.popupBottomMargin
            right: root.barMode === "minimal" ? 0 : 16
        }

        implicitWidth: 216
        implicitHeight: 206

        visible: (root.calendarOpen || calendarItem.animatingOut) && root.mainBarEdge !== "left" && root.barMode !== "minimal"

        mask: Region {
            item: (root.calendarOpen || calendarItem.animatingOut) ? calendarItem : null
            x: 0; y: 0
            width: (root.calendarOpen || calendarItem.animatingOut) ? 216 : 0
            height: (root.calendarOpen || calendarItem.animatingOut) ? 206 : 0
        }

        CalendarPopup {
            id: calendarItem
            barEdge: root.mainBarEdge
            focus: root.calendarOpen
            Keys.onEscapePressed: event => {
                root.closeCalendar()
                event.accepted = true
            }
            open: root.calendarOpen
            onCloseRequested: root.closeCalendar()
            onAnyHoverChanged: {
                root.calendarHovered = calendarItem.anyHover
                if (root.calendarHovered) calendarLeaveTimer.stop()
                else calendarLeaveTimer.restart()
            }
        }
    }

    /* ── Top-Center Calendar, Time & Weather Dashboard Panel ── */
    PanelWindow {
        id: centerDashboardWindow
        screen: Quickshell.screens[0]
        color: "transparent"
        WlrLayershell.namespace: "carbon-center-dashboard"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.centerDashboardOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        aboveWindows: true

        Keys.onEscapePressed: (event) => {
            root.closeCenterDashboard();
            event.accepted = true;
        }

        anchors {
            top: root.mainBarEdge !== "bottom"
            bottom: root.mainBarEdge === "bottom"
        }
        margins {
            top: root.popupTopMargin
            bottom: root.popupBottomMargin
        }

        implicitWidth: centerDashboardItem.implicitWidth
        implicitHeight: centerDashboardItem.implicitHeight

        mask: Region {
            item: (root.centerDashboardOpen || centerDashboardItem.animatingOut) ? centerDashboardItem.cardItem : null
        }

        visible: (root.centerDashboardOpen || centerDashboardItem.animatingOut) && root.barMode !== "notch" && root.barMode !== "minimal"

        function updateHover() {
            var isHov = windowHoverArea.containsMouse || centerDashboardItem.hovered
            root.centerDashboardHovered = isHov
            if (isHov) {
                root.centerDashboardAwaitingHover = false
                centerDashboardLeaveTimer.stop()
            } else if (!root.centerDashboardPinned && !root.centerDashboardAwaitingHover) {
                centerDashboardLeaveTimer.interval = 350
                centerDashboardLeaveTimer.restart()
            }
        }

        MouseArea {
            id: windowHoverArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            z: 99
            onContainsMouseChanged: centerDashboardWindow.updateHover()
        }

        CenterDashboard {
            id: centerDashboardItem
            anchors.centerIn: parent
            open: root.centerDashboardOpen
            minimalCalendarOnly: root.barMode === "minimal"
            attachedBottom: root.mainBarEdge === "bottom"
            onCloseRequested: root.closeCenterDashboard()
            onHoveredChanged: centerDashboardWindow.updateHover()
            Keys.onEscapePressed: root.closeCenterDashboard()
        }
    }

    /* ── Left-anchored Popups for Left Edge Mode ── */
    PanelWindow {
        id: mixerWindowLeft
        screen: Quickshell.screens[0]
        color: "transparent"
        WlrLayershell.namespace: "carbon-mixer-left"
        WlrLayershell.layer: WlrLayer.Overlay
        exclusionMode: ExclusionMode.Ignore
        anchors {
            bottom: true
            left: true
        }
        margins {
            bottom: 14
            left: root.barMode === "notch" ? 38 : 54
        }

        implicitWidth: mixerItemLeft.implicitWidth
        implicitHeight: mixerItemLeft.implicitHeight + 20

        visible: (root.mixerOpen || mixerItemLeft.animatingOut) && root.mainBarEdge === "left"

        mask: Region {
            item: (root.mixerOpen || mixerItemLeft.animatingOut) ? mixerItemLeft : null
            x: 0; y: 0
            width: (root.mixerOpen || mixerItemLeft.animatingOut) ? mixerItemLeft.implicitWidth : 0
            height: (root.mixerOpen || mixerItemLeft.animatingOut) ? mixerItemLeft.implicitHeight + 20 : 0
        }

        MixerMod {
            id: mixerItemLeft
            barEdge: "left"
            open: root.mixerOpen
            onCloseRequested: root.closeMixer()
            onAnyHoverChanged: {
                root.mixerHovered = mixerItemLeft.anyHover
                if (root.mixerHovered) mixerLeaveTimer.stop()
                else mixerLeaveTimer.restart()
            }
        }
    }

    PanelWindow {
        id: brightnessWindowLeft
        screen: Quickshell.screens[0]
        color: "transparent"
        WlrLayershell.namespace: "carbon-brightness-left"
        WlrLayershell.layer: WlrLayer.Overlay
        exclusionMode: ExclusionMode.Ignore
        anchors {
            bottom: true
            left: true
        }
        margins {
            bottom: 14
            left: root.barMode === "notch" ? 38 : 54
        }

        implicitWidth: brightnessItemLeft.implicitWidth
        implicitHeight: brightnessItemLeft.implicitHeight + 20

        visible: (root.brightnessOpen || brightnessItemLeft.animatingOut) && root.mainBarEdge === "left"

        mask: Region {
            item: (root.brightnessOpen || brightnessItemLeft.animatingOut) ? brightnessItemLeft : null
            x: 0; y: 0
            width: (root.brightnessOpen || brightnessItemLeft.animatingOut) ? brightnessItemLeft.implicitWidth : 0
            height: (root.brightnessOpen || brightnessItemLeft.animatingOut) ? brightnessItemLeft.implicitHeight + 20 : 0
        }

        BrightnessPopup {
            id: brightnessItemLeft
            barEdge: "left"
            open: root.brightnessOpen
            onCloseRequested: root.closeBrightness()
            onAnyHoverChanged: {
                root.brightnessHovered = brightnessItemLeft.anyHover
                if (root.brightnessHovered) brightnessLeaveTimer.stop()
                else brightnessLeaveTimer.restart()
            }
        }
    }

    PanelWindow {
        id: batteryWindowLeft
        screen: Quickshell.screens[0]
        color: "transparent"
        WlrLayershell.namespace: "carbon-battery-left"
        WlrLayershell.layer: WlrLayer.Overlay
        exclusionMode: ExclusionMode.Ignore
        anchors {
            bottom: true
            left: true
        }
        margins {
            bottom: 14
            left: root.barMode === "notch" ? 38 : 54
        }

        implicitWidth: batteryItemLeft.implicitWidth
        implicitHeight: batteryItemLeft.implicitHeight + 20

        visible: (root.batteryOpen || batteryItemLeft.animatingOut) && root.mainBarEdge === "left"

        mask: Region {
            item: (root.batteryOpen || batteryItemLeft.animatingOut) ? batteryItemLeft : null
            x: 0; y: 0
            width: (root.batteryOpen || batteryItemLeft.animatingOut) ? batteryItemLeft.implicitWidth : 0
            height: (root.batteryOpen || batteryItemLeft.animatingOut) ? batteryItemLeft.implicitHeight + 20 : 0
        }

        BatteryPopup {
            id: batteryItemLeft
            barEdge: "left"
            open: root.batteryOpen
            onHoveredChanged: {
                root.batteryHovered = batteryItemLeft.hovered
                if (root.batteryHovered) batteryLeaveTimer.stop()
                else batteryLeaveTimer.restart()
            }
        }
    }

    PanelWindow {
        id: trayWindowLeft
        screen: Quickshell.screens[0]
        color: "transparent"
        WlrLayershell.namespace: "carbon-tray-left"
        WlrLayershell.layer: WlrLayer.Overlay
        exclusionMode: ExclusionMode.Ignore
        anchors {
            bottom: true
            left: true
        }
        margins {
            bottom: 14
            left: root.barMode === "notch" ? 38 : 54
        }

        implicitWidth: trayItemLeft.implicitWidth
        implicitHeight: trayItemLeft.implicitHeight + 20

        visible: (root.trayOpen || trayItemLeft.animatingOut) && root.mainBarEdge === "left"

        mask: Region {
            item: (root.trayOpen || trayItemLeft.animatingOut) ? trayItemLeft : null
            x: 0; y: 0
            width: (root.trayOpen || trayItemLeft.animatingOut) ? trayItemLeft.implicitWidth : 0
            height: (root.trayOpen || trayItemLeft.animatingOut) ? trayItemLeft.implicitHeight + 20 : 0
        }

        TrayPopup {
            id: trayItemLeft
            barEdge: "left"
            open: root.trayOpen
            onHoveredChanged: {
                root.trayHovered = trayItemLeft.hovered
                if (root.trayHovered) trayLeaveTimer.stop()
                else trayLeaveTimer.restart()
            }
            onRequestedClose: root.closeTray()
        }
    }

    /* Power menu: full-screen modal overlay */
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: powerWindow
            required property var modelData

            screen: modelData
            color: "transparent"
            WlrLayershell.namespace: "carbon-power"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: root.powerOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; left: true; right: true; bottom: true }

            aboveWindows: true
            visible: root.powerOpen

            PowerMenu {
                anchors.fill: parent
                open: root.powerOpen
                onRequestClose: root.closePower()
                onRequestLock: {
                    root.closePower()
                    sessionLock.lock()
                }
            }
        }
    }

    /* Workspaces Overview: full-screen modal overlay */
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: overviewWindow
            required property var modelData

            screen: modelData
            color: "transparent"
            WlrLayershell.namespace: "carbon-overview"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: root.overviewOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            anchors { top: true; left: true; right: true; bottom: true }

            aboveWindows: true
            visible: root.overviewOpen

            OverviewMod {
                anchors.fill: parent
                open: root.overviewOpen
                onRequestClose: root.closeOverview()
            }
        }
    }


    /* Quick-settings panel: now-playing strip over the quick toggles, positioned
     * dynamically according to root.controlsCorner ("bottom_right", "top_left", or "bottom_left"). */
    PanelWindow {
        id: controlsWindow
        screen: Quickshell.screens[0]
        color: "transparent"
        WlrLayershell.namespace: "carbon-controls"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.controlsVisible ? (root.barMode === "minimal" ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand) : WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore

        anchors {
            top: root.controlsCorner === "top_left"
            bottom: root.controlsCorner !== "top_left"
            left: root.controlsCorner === "top_left" || root.controlsCorner === "bottom_left"
            right: root.controlsCorner === "bottom_right"
        }
        margins {
            top: 0
            bottom: 0
            left: 0
            right: 0
        }

        implicitWidth: controlsItem.implicitWidth
        implicitHeight: controlsItem.implicitHeight

        mask: Region {
            item: (root.controlsVisible || controlsItem.animatingOut) ? controlsItem : null
            x: 0; y: 0
            width: (root.controlsVisible || controlsItem.animatingOut) ? controlsItem.implicitWidth : 0
            height: (root.controlsVisible || controlsItem.animatingOut) ? controlsItem.implicitHeight : 0
        }

        visible: (root.controlsVisible || controlsItem.animatingOut)

        QuickSettings {
            id: controlsItem
            focus: root.controlsVisible
            Keys.onEscapePressed: event => {
                root.closeControls()
                event.accepted = true
            }
            corner: root.controlsCorner
            width: controlsItem.implicitWidth
            height: controlsItem.implicitHeight
            open: root.controlsVisible
            shellOpacity: root.shellOpacity
            server: notificationServer
            onHoveredChanged: {
                root.controlsHovered = controlsItem.hovered
                if (controlsItem.hovered) {
                    controlsLeaveTimer.stop()
                } else {
                    controlsLeaveTimer.restart()
                }
            }
        }
    }

    /* ── Floating Volume & Brightness Notch OSD ─────────────────────────── */
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: osdWindow
            required property var modelData

            screen: modelData
            color: "transparent"
            WlrLayershell.namespace: "carbon-osd"
            WlrLayershell.layer: WlrLayer.Overlay
            exclusionMode: ExclusionMode.Ignore

            anchors {
                top: true
                left: true
                right: true
            }
            margins {
                top: root.mainBarEdge === "bottom" ? 16 : 42
            }

            implicitHeight: osdItem.implicitHeight
            visible: false // Replaced by Dynamic Island in-place morphing HUD

            NotchOsd {
                id: osdItem
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    /* ── Workspace Switcher OSD (Active only in Vanish Mode) ─────────── */
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: workspaceOsdWindow
            required property var modelData

            screen: modelData
            color: "transparent"
            WlrLayershell.namespace: "carbon-workspace-osd"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore

            anchors {
                top: true
            }
            margins {
                top: 16
            }
            implicitWidth: 96
            implicitHeight: 72

            visible: (root.barMode === "nucleus" || root.barMode === "vanish") && (wsOsdItem.active || wsOsdItem.opacity > 0.002)

            // Empty region mask ensures 100% mouse click & touch pass-through to underlying windows!
            mask: Region {}

            WorkspaceOsd {
                id: wsOsdItem
                anchors.centerIn: parent
                barMode: root.barMode
                onActiveChanged: root.workspaceOsdActive = wsOsdItem.active
            }
        }
    }

    /* ── Notification Toast Overlay Window (Top-Right) ───────────────── */
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: toastWindow
            required property var modelData

            screen: modelData
            color: "transparent"
            WlrLayershell.namespace: "carbon-notification-toast"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            aboveWindows: true

            anchors {
                top: true
                right: root.barMode !== "nucleus"
            }

            margins {
                top: (root.barMode === "nucleus")
                    ? Math.round((toastWindow.screen.height / 2) + 226 - (toastItemComp.implicitHeight / 2))
                    : 24
                right: 24
            }

            implicitWidth: toastItemComp.implicitWidth
            implicitHeight: toastItemComp.implicitHeight
            visible: (toastItemComp.active || toastItemComp.opacity > 0.005) && !(root.nucleusHubItem && root.nucleusHubItem.notifPanelOpen)

            NotificationToast {
                id: toastItemComp
                panelOpen: root.nucleusHubItem ? root.nucleusHubItem.notifPanelOpen : false
            }
        }
    }

    /* ── Full-screen Screen Freeze Overlay for Screenshot capture ── */
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: screenshotFreezeWindow
            required property var modelData
            screen: modelData
            color: "#000000"
            visible: root.screenshotFreezeActive && root.screenshotFreezePath.length > 0
            WlrLayershell.namespace: "carbon-screenshot-freeze"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            exclusionMode: ExclusionMode.Ignore
            aboveWindows: true
            anchors { top: true; bottom: true; left: true; right: true }

            Image {
                anchors.fill: parent
                source: (root.screenshotFreezeActive && root.screenshotFreezePath.length > 0) ? ("file://" + root.screenshotFreezePath) : ""
                fillMode: Image.PreserveAspectFit
                cache: false
                asynchronous: false
            }
        }
    }
}