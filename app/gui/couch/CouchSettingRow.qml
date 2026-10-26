import QtQuick 2.9
import "."

// One line of the settings page: a title, an explanation, and the
// control for its value. kind picks the control:
//   "toggle"   on or off. A or a click switches it.
//   "choice"   one of options ({ text, value }). Left/right step through
//              them, A or a click opens the whole list. Options marked
//              listOnly, such as one that asks for a custom value, are
//              only offered in the list.
//   "stepper"  a number. Left/right step it, A or a click asks for a
//              value when the row can parse one (fromInput).
//   "button"   A or a click runs activated().
//   "note"     text only. Navigation skips it.
// The settings page sets page, which shows the list and the prompt.
Item {
    id: row

    property string kind: "toggle"
    property string title
    property string description
    property var page: null

    // toggle
    property bool checked: false
    // choice
    property var options: []
    property var value
    // stepper
    property real from: 0
    property real to: 100
    property real stepSize: 1
    property string valueText: ""
    // Turns typed text into a value, or returns NaN; null means no typing
    property var fromInput: null
    property string inputText: valueText
    property string inputHint: ""
    // note
    property bool warning: false

    readonly property bool isSettingRow: true
    readonly property bool focusable: visible && kind !== "note"
    readonly property bool lit: activeFocus
    readonly property int optionIndex: {
        if (kind !== "choice") return -1
        for (var i = 0; i < options.length; i++) {
            if (options[i].value === value) return i
        }
        return -1
    }
    readonly property string shownValue: kind === "choice" ? (optionIndex >= 0 ? options[optionIndex].text : "")
                                                           : valueText
    readonly property bool canStepDown: kind === "choice" ? choiceStep(-1) >= 0 : value > from
    readonly property bool canStepUp: kind === "choice" ? choiceStep(1) >= 0 : value < to

    onActiveFocusChanged: if (activeFocus && page) page.rowFocused(row)

    signal toggled(bool checked)
    signal picked(var value)
    signal stepped(real value)
    signal activated()

    width: parent ? parent.width : 0
    height: Math.max(textColumn.implicitHeight, control.height) + CouchTheme.px(kind === "note" ? 12 : 28)

    function activate() {
        if (!enabled) return
        switch (kind) {
        case "toggle":
            toggled(!checked)
            break
        case "choice":
            if (page) page.chooseOption(row)
            break
        case "stepper":
            if (page && fromInput) page.askNumber(row)
            break
        case "button":
            activated()
            break
        }
    }

    // The option left or right of the current one, or -1
    function choiceStep(direction) {
        var index = optionIndex < 0 ? (direction > 0 ? 0 : options.length - 1) : optionIndex + direction
        while (index >= 0 && index < options.length && options[index].listOnly) {
            index += direction
        }
        return index >= 0 && index < options.length ? index : -1
    }

    function step(direction) {
        if (!enabled) return
        if (kind === "choice") {
            var index = choiceStep(direction)
            if (index >= 0) picked(options[index].value)
        }
        else if (kind === "stepper") {
            var next = Math.max(from, Math.min(to, value + direction * stepSize))
            if (next !== value) stepped(next)
        }
    }

    // Rows without a value to step leave left to the page,
    // which moves to the section list
    readonly property bool steps: kind === "choice" || kind === "stepper"
    Keys.onLeftPressed: function(event) {
        if (steps) step(-1)
        else event.accepted = false
    }
    Keys.onRightPressed: function(event) {
        if (steps) step(1)
        else event.accepted = false
    }
    Keys.onReturnPressed: activate()
    Keys.onEnterPressed: activate()
    Keys.onSpacePressed: activate()

    Rectangle {
        anchors.fill: parent
        visible: row.kind !== "note"
        radius: CouchTheme.px(12)
        color: row.lit ? CouchTheme.surfaceRaised : (mouse.containsMouse ? CouchTheme.surface : "transparent")
        border.color: CouchTheme.accent
        border.width: row.lit ? CouchTheme.px(2) : 0

        Behavior on color {
            ColorAnimation { duration: CouchTheme.fast }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        enabled: row.kind !== "note"
        hoverEnabled: true
        onClicked: {
            row.forceActiveFocus()
            row.activate()
        }
    }

    Column {
        id: textColumn
        anchors.left: parent.left
        anchors.right: control.left
        anchors.leftMargin: CouchTheme.px(row.kind === "note" ? 4 : 20)
        anchors.rightMargin: CouchTheme.px(20)
        anchors.verticalCenter: parent.verticalCenter
        spacing: CouchTheme.px(4)
        opacity: row.enabled ? 1 : 0.45

        Text {
            width: parent.width
            visible: text !== ""
            text: row.title
            color: CouchTheme.text
            font.pixelSize: CouchTheme.px(19)
            font.bold: row.lit
            wrapMode: Text.Wrap
        }

        Text {
            width: parent.width
            visible: text !== ""
            text: row.description
            color: row.warning ? CouchTheme.attention : CouchTheme.textDim
            font.pixelSize: CouchTheme.px(row.kind === "note" ? 15 : 14)
            lineHeight: 1.2
            wrapMode: Text.Wrap
        }
    }

    // The value on the right
    Item {
        id: control
        anchors.right: parent.right
        anchors.rightMargin: CouchTheme.px(20)
        anchors.verticalCenter: parent.verticalCenter
        width: row.kind === "toggle" ? CouchTheme.px(56) :
               row.kind === "button" ? CouchTheme.px(24) :
               row.kind === "note" ? 0 :
               Math.min(CouchTheme.px(300), Math.max(CouchTheme.px(160), row.width * 0.38))
        height: CouchTheme.px(36)
        opacity: row.enabled ? 1 : 0.45

        // On/off switch
        Rectangle {
            visible: row.kind === "toggle"
            anchors.centerIn: parent
            width: CouchTheme.px(52)
            height: CouchTheme.px(28)
            radius: height / 2
            color: row.checked ? CouchTheme.accent : CouchTheme.background
            border.color: row.checked ? CouchTheme.accent : CouchTheme.textFaint
            border.width: CouchTheme.px(2)

            Rectangle {
                width: parent.height - CouchTheme.px(8)
                height: width
                radius: width / 2
                anchors.verticalCenter: parent.verticalCenter
                x: row.checked ? parent.width - width - CouchTheme.px(4) : CouchTheme.px(4)
                color: row.checked ? CouchTheme.accentText : CouchTheme.textDim

                Behavior on x {
                    NumberAnimation { duration: CouchTheme.fast }
                }
            }
        }

        // ‹ value › for choices and numbers. The arrows take clicks.
        Item {
            visible: row.kind === "choice" || row.kind === "stepper"
            anchors.fill: parent

            Text {
                id: leftArrow
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: CouchTheme.px(28)
                horizontalAlignment: Text.AlignHCenter
                text: "‹"
                color: row.canStepDown ? (row.lit ? CouchTheme.accent : CouchTheme.textDim) : CouchTheme.textFaint
                opacity: row.canStepDown ? 1 : 0.4
                font.pixelSize: CouchTheme.px(30)

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -CouchTheme.px(6)
                    onClicked: {
                        row.forceActiveFocus()
                        row.step(-1)
                    }
                }
            }

            Text {
                anchors.left: leftArrow.right
                anchors.right: rightArrow.left
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignHCenter
                text: row.shownValue
                color: CouchTheme.text
                font.pixelSize: CouchTheme.px(17)
                font.bold: row.lit
                elide: Text.ElideRight
            }

            Text {
                id: rightArrow
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: CouchTheme.px(28)
                horizontalAlignment: Text.AlignHCenter
                text: "›"
                color: row.canStepUp ? (row.lit ? CouchTheme.accent : CouchTheme.textDim) : CouchTheme.textFaint
                opacity: row.canStepUp ? 1 : 0.4
                font.pixelSize: CouchTheme.px(30)

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -CouchTheme.px(6)
                    onClicked: {
                        row.forceActiveFocus()
                        row.step(1)
                    }
                }
            }
        }

        Text {
            visible: row.kind === "button"
            anchors.centerIn: parent
            text: "›"
            color: row.lit ? CouchTheme.accent : CouchTheme.textDim
            font.pixelSize: CouchTheme.px(30)
        }
    }
}
