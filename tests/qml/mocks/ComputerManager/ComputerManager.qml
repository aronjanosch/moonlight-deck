pragma Singleton
import QtQuick 2.9
QtObject {
    property int pollRestarts: 0
    function startPolling() { pollRestarts++ }
    function stopPollingAsync() {}
}
