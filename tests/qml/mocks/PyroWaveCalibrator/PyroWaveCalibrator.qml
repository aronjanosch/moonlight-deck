pragma Singleton
import QtQuick 2.9
QtObject {
    enum Target { Minimum, Recommended, Moderate, Maximum }
    property bool running: false
    property bool bandwidthReady: false
    property var results: []
    property int paceMbps: 0
    function reset() {}
    function cancel() {}
}
