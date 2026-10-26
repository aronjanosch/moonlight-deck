import QtQuick 2.9
import "."

// Full-screen ambient background taken from the selected cover. Decoding
// the art at a tiny size and stretching it gives a cheap blur that needs
// no graphical effects module. Changes crossfade between two layers.
Item {
    id: backdrop

    property url source

    property bool frontIsA: true

    onSourceChanged: {
        if (frontIsA) {
            layerB.source = source
        }
        else {
            layerA.source = source
        }
        frontIsA = !frontIsA
    }

    Rectangle {
        anchors.fill: parent
        color: CouchTheme.background
    }

    Image {
        id: layerA
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        sourceSize: Qt.size(12, 16)
        smooth: true
        asynchronous: true
        opacity: backdrop.frontIsA && status === Image.Ready ? 0.55 : 0
        Behavior on opacity {
            NumberAnimation { duration: 450 }
        }
    }

    Image {
        id: layerB
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        sourceSize: Qt.size(12, 16)
        smooth: true
        asynchronous: true
        opacity: !backdrop.frontIsA && status === Image.Ready ? 0.55 : 0
        Behavior on opacity {
            NumberAnimation { duration: 450 }
        }
    }

    // Darken toward the edges so text and the shelf stay readable
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#e60b0d13" }
            GradientStop { position: 0.35; color: "#660b0d13" }
            GradientStop { position: 0.7; color: "#990b0d13" }
            GradientStop { position: 1.0; color: "#f20b0d13" }
        }
    }
}
