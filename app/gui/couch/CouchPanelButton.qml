import QtQuick 2.9
import "."

// A pill-shaped button in the panel that stands in for the game shelf.
// The selected one shows the confirm glyph, since that's what A does,
// and lights up while the panel has focus.
Rectangle {
    id: pill

    property string label
    property bool selected: true
    property bool lit: false

    signal activated()

    visible: label !== ""
    width: buttonRow.implicitWidth + CouchTheme.px(40)
    height: CouchTheme.px(52)
    radius: height / 2
    color: lit ? CouchTheme.accent : CouchTheme.surfaceRaised

    Row {
        id: buttonRow
        anchors.centerIn: parent
        spacing: CouchTheme.px(10)

        CouchGlyph {
            anchors.verticalCenter: parent.verticalCenter
            visible: pill.selected
            button: CouchTheme.confirmButton
            tint: pill.lit ? CouchTheme.accentText : CouchTheme.text
            ink: pill.lit ? CouchTheme.accent : CouchTheme.surfaceRaised
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: pill.label
            color: pill.lit ? CouchTheme.accentText : CouchTheme.text
            font.pixelSize: CouchTheme.px(18)
            font.bold: true
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: pill.activated()
    }
}
