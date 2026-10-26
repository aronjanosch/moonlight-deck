pragma Singleton
import QtQuick 2.9
QtObject {
    property bool usesMaterial3Theme: false
    property bool hasDesktopEnvironment: true
    property bool isGamescopeSession: false
    property bool hasBrowser: true
    property bool hasDiscordIntegration: false
    property bool hasPyroWave: true
    property bool isDarwin: false
    property bool supportsHdr: true
    property bool rendererAlwaysFullScreen: false
    property size maximumResolution: Qt.size(0, 0)
    property string versionString: "0.0.0-test"
    function refreshDisplays() {}
    // One 1280x800 display at 90 Hz, like a Steam Deck
    function getNativeResolution(index) { return index === 0 ? Qt.rect(0, 0, 1280, 800) : Qt.rect(0, 0, 0, 0) }
    function getSafeAreaResolution(index) { return getNativeResolution(index) }
    function getRefreshRate(index) { return index === 0 ? 90 : 0 }
}
