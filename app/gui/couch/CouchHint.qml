import QtQuick 2.9
import "."

// A button glyph with its action, as shown in the hint bar.
// Tapping it on a touchscreen performs the same action.
Item {
    property alias button: glyph.button
    property alias text: label.text

    signal activated()

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight

    Row {
        id: row
        spacing: CouchTheme.px(8)

        CouchGlyph {
            id: glyph
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            id: label
            anchors.verticalCenter: parent.verticalCenter
            color: CouchTheme.text
            font.pixelSize: CouchTheme.px(16)
        }
    }

    MouseArea {
        anchors.fill: parent
        anchors.margins: -CouchTheme.px(8)
        onClicked: parent.activated()
    }
}
