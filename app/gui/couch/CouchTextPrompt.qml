import QtQuick 2.9
import QtQuick.Controls 2.3
import "."

// Asks for a line of text, such as a host address or a new name.
// In Steam's Game Mode, STEAM + X brings up the on-screen keyboard.
Popup {
    id: prompt

    property string title
    property string placeholder
    property var acceptHandler: null

    function ask(newTitle, initialText, newPlaceholder, acceptFn) {
        title = newTitle
        field.text = initialText || ""
        placeholder = newPlaceholder || ""
        acceptHandler = acceptFn
        open()
    }

    function accept() {
        var value = field.text.trim()
        var fn = acceptHandler
        close()
        if (value !== "" && fn) {
            fn(value)
        }
    }

    parent: Overlay.overlay
    x: parent ? (parent.width - width) / 2 : 0
    y: parent ? (parent.height - height) / 3 : 0
    width: Math.min(parent ? parent.width - CouchTheme.px(64) : 0, CouchTheme.px(620))
    modal: true
    focus: true
    padding: CouchTheme.px(32)
    closePolicy: Popup.CloseOnEscape

    Overlay.modal: Rectangle {
        color: "#a0000000"
    }

    onOpened: {
        field.forceActiveFocus()
        field.selectAll()
    }

    background: Rectangle {
        color: CouchTheme.surface
        radius: CouchTheme.px(16)
        border.color: CouchTheme.surfaceRaised
        border.width: 1
    }

    contentItem: Column {
        spacing: CouchTheme.px(20)

        Text {
            width: parent.width
            text: prompt.title
            color: CouchTheme.text
            font.pixelSize: CouchTheme.px(24)
            font.bold: true
            wrapMode: Text.Wrap
        }

        TextField {
            id: field
            width: parent.width
            color: CouchTheme.text
            font.pixelSize: CouchTheme.px(20)
            leftPadding: CouchTheme.px(16)
            rightPadding: CouchTheme.px(16)
            topPadding: CouchTheme.px(12)
            bottomPadding: CouchTheme.px(12)
            inputMethodHints: Qt.ImhNoAutoUppercase | Qt.ImhNoPredictiveText

            // Our own placeholder, since Material's floats into the border
            Text {
                anchors.fill: parent
                leftPadding: field.leftPadding
                verticalAlignment: Text.AlignVCenter
                visible: field.text === ""
                text: prompt.placeholder
                color: CouchTheme.textFaint
                font: field.font
            }

            background: Rectangle {
                radius: CouchTheme.px(10)
                color: CouchTheme.background
                border.color: field.activeFocus ? CouchTheme.accent : CouchTheme.surfaceRaised
                border.width: CouchTheme.px(2)
            }

            Keys.onReturnPressed: prompt.accept()
            Keys.onEnterPressed: prompt.accept()
        }

        Text {
            width: parent.width
            text: qsTr("On a Steam Deck in Game Mode, press STEAM + X to show the keyboard.")
            color: CouchTheme.textFaint
            font.pixelSize: CouchTheme.px(14)
            wrapMode: Text.Wrap
        }

        Row {
            spacing: CouchTheme.px(24)

            CouchHint {
                button: CouchTheme.confirmButton
                text: qsTr("Confirm")
                onActivated: prompt.accept()
            }

            CouchHint {
                button: CouchTheme.backButton
                text: qsTr("Cancel")
                onActivated: prompt.close()
            }
        }
    }
}
