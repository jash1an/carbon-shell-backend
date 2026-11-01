import QtQuick
import Quickshell
import Quickshell.Wayland

/**
 * FocusHUDBackground:
 * Renders the full-screen obsidian background and tiled blueprint grid
 * on Wayland Layer Bottom (sits ABOVE the wallpaper, BELOW normal windows).
 */
PanelWindow {
    id: focusHudBg

    WlrLayershell.namespace: "carbon-focus-bg"
    WlrLayershell.layer: WlrLayer.Bottom
    exclusiveZone: 0 
    anchors { top: true; bottom: true; left: true; right: true }
    color: "#050608"

    property var modelData: null
    screen: modelData

    // Pass all mouse events through to wallpaper or windows
    mask: Region {}

    Image {
        anchors.fill: parent
        source: "/home/shogun/.config/carbon/assets/blueprint-grid.svg"
        fillMode: Image.Tile
        opacity: 0.15 
        horizontalAlignment: Image.AlignLeft
        verticalAlignment: Image.AlignTop
    }
}
