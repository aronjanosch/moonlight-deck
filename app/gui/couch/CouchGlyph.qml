import QtQuick 2.9
import "."

// A controller button drawn without relying on glyph fonts:
// face buttons ("A", "B", "X", "Y"), shoulders ("LB", "RB"),
// the "view" and "menu" buttons, and "dpad" for left/right.
Item {
    property string button: "A"
    property color tint: CouchTheme.text
    property color ink: CouchTheme.background

    readonly property bool isFace: button.length === 1
    readonly property bool isShoulder: button === "LB" || button === "RB"
    readonly property bool isDpad: button === "dpad"

    implicitHeight: CouchTheme.px(26)
    implicitWidth: isShoulder || isDpad ? CouchTheme.px(40) : implicitHeight

    Rectangle {
        anchors.fill: parent
        radius: isShoulder || isDpad ? CouchTheme.px(7) : height / 2
        color: tint
    }

    Text {
        visible: isFace || isShoulder
        anchors.centerIn: parent
        text: button
        color: ink
        font.pixelSize: isShoulder ? CouchTheme.px(13) : CouchTheme.px(15)
        font.bold: true
    }

    // View: two overlapping windows
    Item {
        visible: button === "view"
        anchors.centerIn: parent
        width: CouchTheme.px(14)
        height: CouchTheme.px(11)

        Rectangle {
            x: 0; y: 0
            width: parent.width * 0.7; height: parent.height * 0.7
            color: "transparent"
            border.color: ink
            border.width: Math.max(1, CouchTheme.px(2))
        }
        Rectangle {
            x: parent.width * 0.3; y: parent.height * 0.3
            width: parent.width * 0.7; height: parent.height * 0.7
            color: ink
        }
    }

    // Menu: three lines
    Column {
        visible: button === "menu"
        anchors.centerIn: parent
        spacing: CouchTheme.px(2)
        Repeater {
            model: 3
            Rectangle {
                width: CouchTheme.px(13)
                height: Math.max(1, CouchTheme.px(2))
                color: ink
            }
        }
    }

    // D-pad left/right: two arrowheads
    Text {
        visible: isDpad
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -CouchTheme.px(1)
        text: "‹ ›"
        color: ink
        font.pixelSize: CouchTheme.px(18)
        font.bold: true
    }
}
