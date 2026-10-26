import QtQuick 2.9
import QtQuick.Controls 2.2
import "."

// One page of settings: a scrolling column of CouchSettingRow items and
// headings. Up and down move between the rows that take focus and keep
// the focused one in view.
Flickable {
    id: section

    property string title
    default property alias rows: column.data
    // The row to return to when the section gets focus again
    property Item lastRow: null

    contentWidth: width
    contentHeight: column.implicitHeight + CouchTheme.px(24)
    boundsBehavior: Flickable.StopAtBounds
    clip: true

    ScrollBar.vertical: ScrollBar {
        policy: section.contentHeight > section.height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
    }

    function settingRows() {
        var result = []
        for (var i = 0; i < column.children.length; i++) {
            if (column.children[i].isSettingRow) {
                result.push(column.children[i])
            }
        }
        return result
    }

    function focusableRows() {
        var result = []
        for (var i = 0; i < column.children.length; i++) {
            var item = column.children[i]
            if (item.isSettingRow && item.focusable) {
                result.push(item)
            }
        }
        return result
    }

    function focusRow(item) {
        if (!item) return false
        lastRow = item
        item.forceActiveFocus(Qt.TabFocusReason)
        reveal(item)
        return true
    }

    // Focuses the row used last, or the first one
    function focusFirst() {
        if (lastRow && lastRow.focusable) return focusRow(lastRow)
        contentY = 0
        return focusRow(focusableRows()[0])
    }

    function moveFocus(direction) {
        var list = focusableRows()
        var index = -1
        for (var i = 0; i < list.length; i++) {
            if (list[i].activeFocus) index = i
        }
        if (index < 0) index = list.indexOf(lastRow)
        var next = index + direction
        if (next < 0 || next >= list.length) {
            // Show the notes above the first row and below the last
            contentY = direction < 0 ? 0 : Math.max(0, contentHeight - height)
            return false
        }
        return focusRow(list[next])
    }

    function reveal(item) {
        var margin = CouchTheme.px(56)
        var y = item.mapToItem(column, 0, 0).y
        if (y - margin < contentY) {
            contentY = Math.max(0, y - margin)
        }
        else if (y + item.height + margin > contentY + height) {
            contentY = Math.min(Math.max(0, contentHeight - height), y + item.height + margin - height)
        }
    }

    Behavior on contentY {
        enabled: !section.moving
        NumberAnimation { duration: CouchTheme.fast; easing.type: Easing.OutCubic }
    }

    Keys.onUpPressed: function(event) { event.accepted = moveFocus(-1) }
    Keys.onDownPressed: function(event) { event.accepted = moveFocus(1) }

    Column {
        id: column
        width: section.width
        topPadding: CouchTheme.px(8)
        spacing: CouchTheme.px(4)
    }
}
