pragma Singleton
import QtQuick

QtObject {
    property bool isFocusActive: false
    property bool isVanishMode: false
    property bool isVanishOverlayOpen: false

    function toggleVanishOverlay() {
        isVanishOverlayOpen = !isVanishOverlayOpen
    }
}
