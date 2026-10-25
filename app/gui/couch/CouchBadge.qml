import QtQuick 2.9
import "."

// A small pill label, optionally led by a colored status dot.
Rectangle {
    property alias text: label.text
    property string dot: ""

    implicitWidth: row.implicitWidth + CouchTheme.px(16)
    implicitHeight: CouchTheme.px(24)
    radius: height / 2
    color: "#d0101218"

    Row {
        id: row
        anchors.centerIn: parent
        spacing: CouchTheme.px(6)

        Rectangle {
            visible: dot !== ""
            anchors.verticalCenter: parent.verticalCenter
            width: CouchTheme.px(8)
            height: width
            radius: width / 2
            color: dot
        }

        Text {
            id: label
            anchors.verticalCenter: parent.verticalCenter
            color: CouchTheme.text
            font.pixelSize: CouchTheme.px(12)
            font.bold: true
            font.letterSpacing: CouchTheme.px(1)
        }
    }
}
