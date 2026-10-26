pragma Singleton
import QtQuick 2.9

import StreamingPreferences 1.0

// Shared look of the couch interface. Sizes are authored for the
// Steam Deck's 1280x800 panel and scaled by main.qml to the window.
QtObject {
    property real s: 1.0

    function px(value) {
        return Math.round(value * s)
    }

    // The scale that fits the 1280x800 layout into a window
    function scaleFor(width, height) {
        return Math.max(0.6, Math.min(width / 1280, height / 800))
    }

    readonly property color background: "#0b0d13"
    readonly property color surface: "#171a24"
    readonly property color surfaceRaised: "#252a38"
    readonly property color scrim: "#cc07080c"
    readonly property color text: "#f4f5f9"
    readonly property color textDim: "#a3a9b8"
    readonly property color textFaint: "#646b7c"
    readonly property color accent: "#b69cff"
    readonly property color accentText: "#120b24"
    readonly property color online: "#4ade80"
    readonly property color attention: "#fbbf24"
    readonly property color offline: "#6b7280"
    readonly property color danger: "#f87171"

    // Glyphs for the buttons SdlGamepadKeyNavigation maps to
    // Return, Escape and Menu, honoring the face button swap
    readonly property string confirmButton: StreamingPreferences.swapFaceButtons ? "B" : "A"
    readonly property string backButton: StreamingPreferences.swapFaceButtons ? "A" : "B"
    readonly property string optionsButton: StreamingPreferences.swapFaceButtons ? "Y" : "X"

    readonly property int fast: 120
    readonly property int normal: 200
}
