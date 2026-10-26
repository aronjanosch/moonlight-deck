import QtQuick 2.9
import QtQuick.Controls 2.3
import "."

// A side sheet listing actions, used for context menus, confirmations
// and messages. Each action is { text, checked (optional), run (optional) }.
// The chosen action runs after the sheet has closed, so it may open
// this sheet again or move focus elsewhere.
Popup {
    id: sheet

    property string title
    property string message
    property var actions: []
    property var pendingRun: null

    function present(newTitle, newMessage, newActions) {
        title = newTitle
        message = newMessage || ""
        actions = newActions
        list.currentIndex = 0
        open()
    }

    // Takes focus back, e.g. from a popup that closed after this opened
    function refocus() {
        list.forceActiveFocus()
    }

    function trigger(index) {
        if (index < 0 || index >= actions.length) {
            return
        }
        pendingRun = actions[index].run || null
        close()
    }

    parent: Overlay.overlay
    y: 0
    width: Math.min(parent ? parent.width * 0.45 : 0, CouchTheme.px(500))
    height: parent ? parent.height : 0
    modal: true
    focus: true
    padding: 0
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    Overlay.modal: Rectangle {
        color: "#a0000000"
    }

    enter: Transition {
        NumberAnimation {
            property: "x"
            from: sheet.parent.width
            to: sheet.parent.width - sheet.width
            duration: CouchTheme.normal
            easing.type: Easing.OutCubic
        }
    }

    exit: Transition {
        NumberAnimation {
            property: "x"
            to: sheet.parent.width
            duration: CouchTheme.fast
            easing.type: Easing.InCubic
        }
    }

    onOpened: list.forceActiveFocus()

    onClosed: {
        if (pendingRun) {
            var run = pendingRun
            pendingRun = null
            run()
        }
    }

    background: Rectangle {
        color: CouchTheme.surface

        Rectangle {
            width: CouchTheme.px(3)
            height: parent.height
            color: CouchTheme.accent
        }
    }

    contentItem: Item {
        Column {
            id: header
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: CouchTheme.px(32)
            anchors.topMargin: CouchTheme.px(48)
            spacing: CouchTheme.px(12)

            Text {
                width: parent.width
                text: sheet.title
                color: CouchTheme.text
                font.pixelSize: CouchTheme.px(26)
                font.bold: true
                wrapMode: Text.Wrap
            }

            Text {
                width: parent.width
                visible: text !== ""
                text: sheet.message
                color: CouchTheme.textDim
                font.pixelSize: CouchTheme.px(16)
                lineHeight: 1.2
                wrapMode: Text.Wrap
            }
        }

        ListView {
            id: list
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: header.bottom
            anchors.bottom: hints.top
            anchors.topMargin: CouchTheme.px(24)
            anchors.leftMargin: CouchTheme.px(16)
            anchors.rightMargin: CouchTheme.px(16)
            clip: true
            spacing: CouchTheme.px(4)
            keyNavigationWraps: true
            boundsBehavior: Flickable.StopAtBounds
            model: sheet.actions

            delegate: Rectangle {
                readonly property bool lit: ListView.isCurrentItem && list.activeFocus

                width: list.width
                height: CouchTheme.px(54)
                radius: CouchTheme.px(10)
                color: lit ? CouchTheme.accent : "transparent"

                Behavior on color {
                    ColorAnimation { duration: CouchTheme.fast }
                }

                Text {
                    anchors.left: parent.left
                    anchors.right: toggle.left
                    anchors.leftMargin: CouchTheme.px(16)
                    anchors.rightMargin: CouchTheme.px(12)
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.text
                    color: lit ? CouchTheme.accentText : CouchTheme.text
                    font.pixelSize: CouchTheme.px(18)
                    font.bold: lit
                    elide: Text.ElideRight
                }

                // On/off indicator for toggles
                Rectangle {
                    id: toggle
                    visible: modelData.checked !== undefined
                    anchors.right: parent.right
                    anchors.rightMargin: CouchTheme.px(16)
                    anchors.verticalCenter: parent.verticalCenter
                    width: visible ? CouchTheme.px(44) : 0
                    height: CouchTheme.px(24)
                    radius: height / 2
                    color: modelData.checked ? (lit ? CouchTheme.accentText : CouchTheme.accent)
                                             : (lit ? "#40000000" : CouchTheme.surfaceRaised)

                    Rectangle {
                        width: parent.height - CouchTheme.px(6)
                        height: width
                        radius: width / 2
                        anchors.verticalCenter: parent.verticalCenter
                        x: modelData.checked ? parent.width - width - CouchTheme.px(3) : CouchTheme.px(3)
                        color: modelData.checked ? (lit ? CouchTheme.accent : CouchTheme.accentText) : CouchTheme.textDim
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: list.currentIndex = index
                    onClicked: sheet.trigger(index)
                }
            }

            Keys.onReturnPressed: sheet.trigger(currentIndex)
            Keys.onEnterPressed: sheet.trigger(currentIndex)
            Keys.onSpacePressed: sheet.trigger(currentIndex)
            Keys.onMenuPressed: sheet.close()
            Keys.onBackPressed: sheet.close()
            // View, Y and Start close the sheet instead of reaching the page below
            Keys.onPressed: {
                if (event.key === Qt.Key_Context1 || event.key === Qt.Key_Hangup) {
                    sheet.close()
                    event.accepted = true
                }
            }
        }

        Row {
            id: hints
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.margins: CouchTheme.px(32)
            spacing: CouchTheme.px(24)

            CouchHint {
                button: CouchTheme.confirmButton
                text: qsTr("Select")
                onActivated: sheet.trigger(list.currentIndex)
            }

            CouchHint {
                button: CouchTheme.backButton
                text: qsTr("Close")
                onActivated: sheet.close()
            }
        }
    }
}
