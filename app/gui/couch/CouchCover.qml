import QtQuick 2.9
import "."

// One game in the shelf: its box art, or a title card when the host
// only has a placeholder image, plus running and hidden badges.
// Vibepollo's session controls get a shorter tile with their own icon.
Item {
    id: cover

    property string name
    property url boxart
    property bool running
    property bool hidden
    property bool sleepAction
    property bool appCollectorGame
    // A HostControls name, or empty for a game
    property string hostControl
    property bool selected
    property bool lit

    signal tapped()

    // Same detection as AppView: GFE and our own placeholder sizes
    readonly property bool isControl: hostControl !== ""
    readonly property bool isPlaceholder: sleepAction || isControl ||
        String(boxart) === "" || art.status === Image.Error ||
        (!appCollectorGame &&
         ((art.sourceSize.width === 130 && art.sourceSize.height === 180) ||
          (art.sourceSize.width === 628 && art.sourceSize.height === 888) ||
          (art.sourceSize.width === 200 && art.sourceSize.height === 266)))

    Item {
        id: card
        width: parent.width
        height: cover.isControl ? Math.round(parent.height * 0.62) : parent.height
        y: parent.height - height
        scale: cover.selected ? 1.0 : 0.88
        opacity: cover.hidden ? 0.4 : (cover.selected ? 1.0 : 0.72)
        transformOrigin: Item.Bottom

        Behavior on scale {
            NumberAnimation { duration: CouchTheme.normal; easing.type: Easing.OutCubic }
        }
        Behavior on opacity {
            NumberAnimation { duration: CouchTheme.normal }
        }

        // Glow behind the selected cover
        Rectangle {
            anchors.fill: parent
            anchors.margins: -CouchTheme.px(10)
            radius: CouchTheme.px(18)
            color: CouchTheme.accent
            opacity: cover.lit ? 0.18 : 0
            Behavior on opacity {
                NumberAnimation { duration: CouchTheme.normal }
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: CouchTheme.px(8)
            color: CouchTheme.surface
        }

        Image {
            id: art
            anchors.fill: parent
            anchors.margins: CouchTheme.px(1)
            source: cover.sleepAction || cover.isControl ? "" : cover.boxart
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            smooth: true
            visible: !cover.isPlaceholder && status === Image.Ready
        }

        // Host-control tile
        Rectangle {
            anchors.fill: parent
            visible: cover.isControl
            radius: CouchTheme.px(8)
            color: CouchTheme.surface
            border.color: CouchTheme.surfaceRaised
            border.width: CouchTheme.px(2)

            CouchControlIcon {
                id: controlIcon
                kind: cover.hostControl
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height * 0.2
                width: CouchTheme.px(56)
                height: width
                tint: cover.lit ? CouchTheme.accent : CouchTheme.text
            }

            Text {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: controlIcon.bottom
                anchors.bottom: parent.bottom
                anchors.margins: CouchTheme.px(10)
                text: cover.name
                color: CouchTheme.text
                font.pixelSize: CouchTheme.px(17)
                font.bold: true
                wrapMode: Text.Wrap
                elide: Text.ElideRight
                maximumLineCount: 2
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }

        // Title card for apps without real box art
        Rectangle {
            anchors.fill: parent
            visible: cover.isPlaceholder && !cover.isControl
            radius: CouchTheme.px(8)
            gradient: Gradient {
                GradientStop { position: 0.0; color: CouchTheme.surfaceRaised }
                GradientStop { position: 1.0; color: CouchTheme.surface }
            }

            // A crescent for the sleep action
            Item {
                visible: cover.sleepAction
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height * 0.22
                width: CouchTheme.px(64)
                height: width

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: CouchTheme.accent
                }
                Rectangle {
                    x: parent.width * 0.3
                    y: -parent.height * 0.1
                    width: parent.width
                    height: width
                    radius: width / 2
                    color: CouchTheme.surfaceRaised
                }
            }

            Text {
                anchors.fill: parent
                anchors.margins: CouchTheme.px(16)
                anchors.topMargin: cover.sleepAction ? parent.height * 0.45 : CouchTheme.px(16)
                text: cover.name
                color: CouchTheme.text
                font.pixelSize: CouchTheme.px(22)
                font.bold: true
                wrapMode: Text.Wrap
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: cover.sleepAction ? Text.AlignTop : Text.AlignVCenter
            }
        }

        // Selection ring
        Rectangle {
            anchors.fill: parent
            anchors.margins: -CouchTheme.px(5)
            radius: CouchTheme.px(12)
            color: "transparent"
            border.color: CouchTheme.accent
            border.width: CouchTheme.px(3)
            opacity: cover.lit ? 1 : 0
            Behavior on opacity {
                NumberAnimation { duration: CouchTheme.fast }
            }
        }

        Row {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.margins: CouchTheme.px(10)
            spacing: CouchTheme.px(6)

            CouchBadge {
                visible: cover.running
                text: qsTr("RUNNING")
                dot: "" + CouchTheme.online
            }

            CouchBadge {
                visible: cover.hidden
                text: qsTr("HIDDEN")
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: cover.tapped()
    }
}
