import QtQuick 2.9
import QtQuick.Controls 2.2
import QtTest 1.2
import SdlGamepadKeyNavigation 1.0
import "../../app/gui"

Item {
    width: 640; height: 900
    // Same component and model role used by the PyroWave host chooser.
    AutoResizingComboBox {
        id: host
        y: 820; width: 420
        textRole: "name"
        KeyNavigation.tab: afterHost
        model: ListModel {
            ListElement { name: "Host A" }
            ListElement { name: "Host B" }
            ListElement { name: "Host C" }
        }
    }
    Button { id: afterHost; x: 440; y: 820; text: "Continue" }
    TestCase {
        name: "HostChooser"
        when: windowShown
        function init() {
            host.currentIndex = 0
        }
        function cleanup() {
            host.popup.close()
            wait(200) // Finish style popup transitions before moving focus in the next test.
        }
        function test_controller_popup() {
            host.forceActiveFocus()
            keyClick(Qt.Key_Space) // Controller A in UI-navigation mode.
            tryCompare(host.popup, "opened", true)
            compare(SdlGamepadKeyNavigation.uiNavMode, false)
            keyClick(Qt.Key_Down)
            keyClick(Qt.Key_Return) // Controller A in popup mode.
            tryCompare(host.popup, "visible", false)
            compare(host.currentIndex, 1)
            compare(SdlGamepadKeyNavigation.uiNavMode, true)
            verify(host.activeFocus)
            keyClick(Qt.Key_Space)
            tryCompare(host.popup, "opened", true)
            keyClick(Qt.Key_Down)
            keyClick(Qt.Key_Escape) // Controller B cancels selection.
            tryCompare(host.popup, "visible", false)
            compare(host.currentIndex, 1)
            compare(SdlGamepadKeyNavigation.uiNavMode, true)
        }
        function test_popup_does_not_apply_sideways_navigation() {
            host.forceActiveFocus()
            keyClick(Qt.Key_Space)
            tryCompare(host.popup, "opened", true)
            keyClick(Qt.Key_Down)
            compare(host.highlightedIndex, 1)
            keyClick(Qt.Key_Right)
            compare(host.currentIndex, 0)
            keyClick(Qt.Key_Left)
            compare(host.currentIndex, 0)
            verify(host.popup.visible)
            keyClick(Qt.Key_Escape)
            tryCompare(host.popup, "visible", false)
            compare(host.currentIndex, 0)
            verify(host.activeFocus)
            keyClick(Qt.Key_Tab)
            verify(afterHost.activeFocus)
        }
    }
}
