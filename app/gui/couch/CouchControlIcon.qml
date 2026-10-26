import QtQuick 2.9
import "."

// The symbol on a Vibepollo host-control tile, drawn from shapes so it
// doesn't depend on the fonts installed on the device.
Item {
    id: icon

    // A HostControls name from AppModel, e.g. "resume" or "remoteMonitor"
    property string kind
    property color tint: CouchTheme.text

    readonly property bool monitor: kind === "remoteMonitor" || kind === "disconnectMonitor"
    readonly property bool input: kind === "remoteInput" || kind === "disconnectInput"
    readonly property bool disconnect: kind === "disconnectMonitor" || kind === "disconnectInput"

    implicitWidth: CouchTheme.px(56)
    implicitHeight: implicitWidth

    // Play triangle for resume and the running game
    Canvas {
        anchors.fill: parent
        visible: icon.kind === "resume" || icon.kind === "runningGame"
        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            ctx.fillStyle = paintTint
            ctx.beginPath()
            ctx.moveTo(width * 0.28, height * 0.18)
            ctx.lineTo(width * 0.84, height * 0.5)
            ctx.lineTo(width * 0.28, height * 0.82)
            ctx.closePath()
            ctx.fill()
        }
        readonly property color paintTint: icon.tint
        onPaintTintChanged: requestPaint()
        onVisibleChanged: requestPaint()
    }

    // Stop square for terminate
    Rectangle {
        visible: icon.kind === "terminate"
        anchors.centerIn: parent
        width: parent.width * 0.56
        height: width
        radius: CouchTheme.px(4)
        color: icon.tint
    }

    // A monitor on its stand
    Item {
        visible: icon.monitor
        anchors.fill: parent

        Rectangle {
            x: parent.width * 0.1
            y: parent.height * 0.16
            width: parent.width * 0.8
            height: parent.height * 0.52
            radius: CouchTheme.px(4)
            color: "transparent"
            border.color: icon.tint
            border.width: Math.max(2, CouchTheme.px(4))
        }
        Rectangle {
            x: parent.width * 0.45
            y: parent.height * 0.68
            width: parent.width * 0.1
            height: parent.height * 0.12
            color: icon.tint
        }
        Rectangle {
            x: parent.width * 0.28
            y: parent.height * 0.8
            width: parent.width * 0.44
            height: Math.max(2, CouchTheme.px(4))
            radius: height / 2
            color: icon.tint
        }
    }

    // A keyboard: an outline with rows of keys
    Item {
        visible: icon.input
        anchors.fill: parent

        Rectangle {
            x: parent.width * 0.06
            y: parent.height * 0.24
            width: parent.width * 0.88
            height: parent.height * 0.52
            radius: CouchTheme.px(5)
            color: "transparent"
            border.color: icon.tint
            border.width: Math.max(2, CouchTheme.px(4))
        }
        Grid {
            x: parent.width * 0.2
            y: parent.height * 0.36
            columns: 4
            spacing: parent.width * 0.06
            Repeater {
                model: 8
                Rectangle {
                    width: icon.width * 0.1
                    height: width
                    color: icon.tint
                }
            }
        }
    }

    // A strike through the symbol for the disconnect controls
    Rectangle {
        visible: icon.disconnect
        anchors.centerIn: parent
        width: parent.width * 1.05
        height: Math.max(3, CouchTheme.px(5))
        radius: height / 2
        rotation: -40
        color: CouchTheme.danger
    }
}
