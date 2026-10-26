import QtQuick 2.9
import QtQuick.Controls 2.2
import QtTest 1.2
import StreamingPreferences 1.0
import "../../app/gui/couch"

// The settings page as main.qml shows it: pushed onto a StackView whose
// context provides window, toolBar and stackView. Keys are the ones the
// SDL bridge sends for a controller outside UI-navigation mode.
Item {
    id: window
    width: 1280
    height: 800

    property bool clearOnBack: false
    property bool pollingActive: false
    property var page: null

    function goBack() { stackView.pop() }

    Item { id: toolBar }

    // As in main.qml
    Binding {
        target: CouchTheme
        property: "s"
        value: CouchTheme.scaleFor(window.width, window.height)
    }

    StackView {
        id: stackView
        anchors.fill: parent
        initialItem: Item {}
    }

    TestCase {
        name: "CouchSettings"
        when: windowShown

        function init() {
            var p = StreamingPreferences
            p.width = 1280; p.height = 720; p.fps = 60
            p.bitrateKbps = 10000; p.autoAdjustBitrate = true; p.unlockBitrate = false
            p.videoCodecConfig = StreamingPreferences.VCC_AUTO
            p.enableVsync = true; p.enableVrr = false; p.applyVrrPreset(1)
            p.enableHdr = false; p.enableYUV444 = false
            window.width = 1280; window.height = 800
            page = stackView.push(Qt.resolvedUrl("../../app/gui/couch/CouchSettings.qml"))
            tryCompare(stackView, "busy", false)
            waitForRendering(page)
        }

        function cleanup() {
            stackView.pop(null, StackView.Immediate)
        }

        function type(text) {
            for (var i = 0; i < text.length; i++) keyClick(text[i])
        }

        function row(name) {
            var item = findChild(page, name)
            verify(item, name)
            return item
        }

        function screenshot(name) {
            var saved = false
            page.grabToImage(function(result) { saved = result.saveToFile("couch-settings-" + name + ".png") })
            tryVerify(function() { return saved })
        }

        function test_starts_on_the_first_row() {
            verify(row("resolution").activeFocus)
            verify(!toolBar.visible)
            screenshot("video")
        }

        function test_up_and_down_move_between_rows() {
            keyClick(Qt.Key_Down)
            verify(row("fps").activeFocus)
            keyClick(Qt.Key_Down)
            verify(row("codec").activeFocus)
            keyClick(Qt.Key_Up)
            keyClick(Qt.Key_Up)
            verify(row("resolution").activeFocus)
            // Nothing above the first row
            keyClick(Qt.Key_Up)
            verify(row("resolution").activeFocus)
        }

        function test_left_from_a_toggle_opens_the_section_list() {
            keyClick(Qt.Key_Down); keyClick(Qt.Key_Down); keyClick(Qt.Key_Down)
            keyClick(Qt.Key_Left)
            var list = row("couchSettingsSections")
            verify(list.activeFocus)
            keyClick(Qt.Key_Down)
            compare(page.sectionIndex, 1)
            keyClick(Qt.Key_Return)
            compare(page.zone, "rows")
            verify(page.activeRow.activeFocus)
            compare(page.currentSection.title, "Display")
        }

        function test_shoulder_buttons_switch_sections() {
            keyClick(Qt.Key_PageDown)
            compare(page.sectionIndex, 1)
            keyClick(Qt.Key_PageUp)
            keyClick(Qt.Key_PageUp)
            compare(page.sectionIndex, 0)
            verify(row("resolution").activeFocus)
        }

        function test_choices_step_with_left_and_right() {
            keyClick(Qt.Key_Down)
            keyClick(Qt.Key_Right)
            compare(StreamingPreferences.fps, 90)
            // The default bitrate follows the frame rate
            compare(StreamingPreferences.bitrateKbps, StreamingPreferences.getDefaultBitrate(1280, 720, 90, false))
            keyClick(Qt.Key_Left)
            keyClick(Qt.Key_Left)
            keyClick(Qt.Key_Left)
            compare(StreamingPreferences.fps, 30)
        }

        function test_choice_list() {
            var codec = row("codec")
            codec.forceActiveFocus()
            keyClick(Qt.Key_Return)
            tryCompare(findChild(page, "couchSettingsSheet"), "opened", true)
            keyClick(Qt.Key_Down)
            keyClick(Qt.Key_Down)
            keyClick(Qt.Key_Return)
            tryCompare(StreamingPreferences, "videoCodecConfig", StreamingPreferences.VCC_FORCE_HEVC)
            tryVerify(function() { return codec.activeFocus })
        }

        function test_custom_resolution() {
            var resolution = row("resolution")
            // Stepping never lands on Custom…, the last option
            for (var i = 0; i < 10; i++) keyClick(Qt.Key_Right)
            compare(StreamingPreferences.width, 3840)
            // The list opens on 4K, right above it
            keyClick(Qt.Key_Return)
            var sheet = findChild(page, "couchSettingsSheet")
            tryCompare(sheet, "opened", true)
            keyClick(Qt.Key_Down)
            keyClick(Qt.Key_Return)
            var prompt = findChild(page, "couchSettingsPrompt")
            tryCompare(prompt, "opened", true)
            keyClick(Qt.Key_A, Qt.ControlModifier)
            keyClick(Qt.Key_Backspace)
            type("2560x1600")
            keyClick(Qt.Key_Return)
            compare(StreamingPreferences.width, 2560)
            compare(StreamingPreferences.height, 1600)
            tryVerify(function() { return resolution.activeFocus })
            compare(resolution.shownValue, "Custom (2560x1600)")
        }

        function test_bitrate_steps_and_limits() {
            var bitrate = row("bitrate")
            bitrate.forceActiveFocus()
            keyClick(Qt.Key_Right)
            compare(StreamingPreferences.bitrateKbps, 11000)
            verify(!StreamingPreferences.autoAdjustBitrate)
            for (var i = 0; i < 60; i++) keyClick(Qt.Key_Right)
            compare(StreamingPreferences.bitrateKbps, 150000)
            for (i = 0; i < 80; i++) keyClick(Qt.Key_Left)
            compare(StreamingPreferences.bitrateKbps, 500)
            screenshot("bitrate")
        }

        function test_typed_bitrate() {
            row("bitrate").forceActiveFocus()
            keyClick(Qt.Key_Return)
            tryCompare(findChild(page, "couchSettingsPrompt"), "opened", true)
            keyClick(Qt.Key_A, Qt.ControlModifier)
            type("42.5")
            keyClick(Qt.Key_Return)
            compare(StreamingPreferences.bitrateKbps, 42500)
        }

        function test_vrr_timing_rows() {
            StreamingPreferences.enableVrr = true
            keyClick(Qt.Key_PageDown)
            var preset = row("vrrPreset")
            preset.forceActiveFocus()
            keyClick(Qt.Key_Left)
            compare(StreamingPreferences.vrrBufferPerMille, 500)
            compare(StreamingPreferences.vrrTargetHundredths, 9900)
            compare(preset.shownValue, "Low Latency")
            var target = row("vrrTarget")
            target.forceActiveFocus()
            keyClick(Qt.Key_Left)
            compare(StreamingPreferences.vrrTargetHundredths, 9850)
            compare(preset.shownValue, "Custom")
            // Left from Custom is the last preset; choosing Custom changes nothing
            preset.forceActiveFocus()
            keyClick(Qt.Key_Left)
            compare(StreamingPreferences.vrrTargetHundredths, 9995)
            compare(preset.shownValue, "Smooth")
            keyClick(Qt.Key_Right)
            compare(StreamingPreferences.vrrTargetHundredths, 9995)
            compare(preset.shownValue, "Smooth")
            screenshot("display")
        }

        function test_vrr_timing_bounds_data() {
            return [
                { tag: "buffer", row: "vrrBuffer", property: "vrrBufferPerMille", min: 250, max: 4000 },
                { tag: "target", row: "vrrTarget", property: "vrrTargetHundredths", min: 9000, max: 9999 },
                { tag: "history", row: "vrrHistory", property: "vrrHistorySeconds", min: 10, max: 300 },
                { tag: "tolerance", row: "vrrTolerance", property: "vrrToleranceUs", min: 250, max: 2000 }
            ]
        }

        function test_vrr_timing_bounds(data) {
            StreamingPreferences.enableVrr = true
            keyClick(Qt.Key_PageDown)
            row(data.row).forceActiveFocus()
            for (var i = 0; i < 40; i++) keyClick(Qt.Key_Left)
            compare(StreamingPreferences[data.property], data.min)
            for (i = 0; i < 40; i++) keyClick(Qt.Key_Right)
            compare(StreamingPreferences[data.property], data.max)
        }

        function test_hidden_rows_are_skipped() {
            keyClick(Qt.Key_PageDown)
            var vrr = row("vrr")
            vrr.forceActiveFocus()
            keyClick(Qt.Key_Down)
            // With VRR off, its timing rows are hidden
            verify(!row("vrrPreset").activeFocus)
            verify(page.activeRow.activeFocus)
            verify(page.activeRow.title.indexOf("GPU") >= 0 || page.activeRow.title === "", page.activeRow.title)
        }

        function test_toggle_with_confirm() {
            keyClick(Qt.Key_PageDown)
            var vrr = row("vrr")
            vrr.forceActiveFocus()
            keyClick(Qt.Key_Return)
            verify(StreamingPreferences.enableVrr)
            mouseClick(vrr)
            verify(!StreamingPreferences.enableVrr)
        }

        function test_back_saves() {
            var saves = StreamingPreferences.saves
            page.goBack()
            tryCompare(stackView, "depth", 1)
            verify(StreamingPreferences.saves > saves)
            verify(toolBar.visible)
        }

        // A page that closes must not leave its own scale behind, such
        // as after the window changed size during a stream
        function test_scale_follows_window_after_close() {
            window.width = 3840; window.height = 2160
            compare(CouchTheme.s, CouchTheme.scaleFor(3840, 2160))
            page.goBack()
            tryCompare(stackView, "depth", 1)
            window.width = 1280; window.height = 800
            compare(CouchTheme.s, 1)
        }

        function test_layouts() {
            window.width = 1920; window.height = 1080
            waitForRendering(page)
            screenshot("tv")
            verify(!page.narrow)
            window.width = 540; window.height = 720
            waitForRendering(page)
            verify(page.narrow)
            compare(row("couchSettingsSections").orientation, ListView.Horizontal)
            screenshot("narrow")
            keyClick(Qt.Key_Up)
            verify(row("couchSettingsSections").activeFocus)
            keyClick(Qt.Key_Right)
            compare(page.sectionIndex, 1)
            keyClick(Qt.Key_Down)
            verify(page.activeRow.activeFocus)
        }
    }
}
