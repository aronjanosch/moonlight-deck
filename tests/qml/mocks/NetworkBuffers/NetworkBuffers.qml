pragma Singleton
import QtQuick 2.9
QtObject {
    property bool needsFix: false
    property bool canApply: true
    property bool busy: false
    property string problemText: ""
    property string fixDescription: ""
    property string manualHint: ""
    property string manualCommand: ""
    property string message: ""
    function refresh() {}
    function apply() {}
    function copyCommand() {}
}
