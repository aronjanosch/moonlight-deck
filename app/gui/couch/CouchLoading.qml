import QtQuick 2.9
import "."

// Full-screen progress for starting, resuming or quitting a game: its
// cover over a blurred backdrop of the same art, what's happening, and
// a bar that fills as the connection stages complete. Without a
// progress value the bar sweeps instead.
Item {
    id: loading

    property url boxart
    property string title
    // What's happening, such as "STARTING"
    property string overline
    property string hostName
    property string status
    property string hint
    // 0 to 1, or below 0 while there's no way to tell
    property real progress: -1
    property bool shown: false

    Binding {
        target: CouchTheme
        property: "s"
        value: CouchTheme.scaleFor(loading.width, loading.height)
    }

    Rectangle {
        anchors.fill: parent
        color: CouchTheme.background
    }

    CouchBackdrop {
        anchors.fill: parent
        source: cover.isPlaceholder ? "" : loading.boxart
    }

    Item {
        id: content
        anchors.fill: parent
        opacity: loading.shown ? 1 : 0

        Behavior on opacity {
            NumberAnimation { duration: 350; easing.type: Easing.OutCubic }
        }

        Row {
            id: layout
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -CouchTheme.px(16)
            spacing: CouchTheme.px(48)

            CouchCover {
                id: cover
                anchors.verticalCenter: parent.verticalCenter
                width: Math.round(height * 0.7)
                height: CouchTheme.px(340)
                name: loading.title
                boxart: loading.boxart
                selected: true

                // Breathes while waiting
                SequentialAnimation on scale {
                    running: loading.shown && loading.visible
                    loops: Animation.Infinite
                    NumberAnimation { to: 1.025; duration: 1400; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1.0; duration: 1400; easing.type: Easing.InOutSine }
                }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(CouchTheme.px(240), Math.min(CouchTheme.px(560), loading.width - cover.width - layout.spacing - CouchTheme.px(112)))
                spacing: CouchTheme.px(10)

                Text {
                    text: loading.overline
                    color: CouchTheme.accent
                    font.pixelSize: CouchTheme.px(15)
                    font.bold: true
                    font.letterSpacing: CouchTheme.px(2)
                }

                Text {
                    width: parent.width
                    text: loading.title
                    color: CouchTheme.text
                    font.pixelSize: CouchTheme.px(44)
                    font.bold: true
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }

                Text {
                    visible: text !== ""
                    text: loading.hostName
                    color: CouchTheme.textDim
                    font.pixelSize: CouchTheme.px(18)
                }

                Item {
                    width: 1
                    height: CouchTheme.px(22)
                }

                // Progress
                Rectangle {
                    id: track
                    width: parent.width
                    height: CouchTheme.px(6)
                    radius: height / 2
                    color: CouchTheme.surfaceRaised
                    clip: true

                    Rectangle {
                        visible: loading.progress >= 0
                        height: parent.height
                        radius: parent.radius
                        width: parent.width * Math.max(0.04, Math.min(1, loading.progress))
                        color: CouchTheme.accent

                        Behavior on width {
                            NumberAnimation { duration: 450; easing.type: Easing.OutCubic }
                        }
                    }

                    // A highlight that keeps moving, so the screen never looks stuck
                    Rectangle {
                        id: sweep
                        height: parent.height
                        radius: parent.radius
                        width: parent.width * (loading.progress >= 0 ? 0.18 : 0.32)
                        color: loading.progress >= 0 ? "#80ffffff" : CouchTheme.accent
                        opacity: loading.progress >= 0 ? 0.35 : 1

                        NumberAnimation on x {
                            running: loading.shown && loading.visible
                            loops: Animation.Infinite
                            from: -sweep.width
                            to: track.width
                            duration: 1600
                            easing.type: Easing.InOutQuad
                        }
                    }
                }

                Text {
                    width: parent.width
                    text: loading.status
                    color: CouchTheme.textDim
                    font.pixelSize: CouchTheme.px(17)
                    wrapMode: Text.Wrap
                }
            }
        }

        Text {
            anchors.bottom: parent.bottom
            anchors.bottomMargin: CouchTheme.px(40)
            anchors.horizontalCenter: parent.horizontalCenter
            width: parent.width - CouchTheme.px(80)
            horizontalAlignment: Text.AlignHCenter
            text: loading.hint
            color: CouchTheme.textFaint
            font.pixelSize: CouchTheme.px(16)
            wrapMode: Text.Wrap
        }
    }
}
