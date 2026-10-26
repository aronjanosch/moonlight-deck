import QtQuick 2.9
import QtQuick.Controls 2.2
import QtQuick.Layouts 1.3
import QtQuick.Window 2.2

import StreamingPreferences 1.0
import ComputerManager 1.0
import ComputerModel 1.0
import SdlGamepadKeyNavigation 1.0
import SystemProperties 1.0
import PyroWaveCalibrator 1.0

// Two steps: measure the connection to a host, then stress-test this
// device's decoder at each format. Applying a result sets the codec,
// resolution, chroma, HDR, bitrate and packet speed.
NavigableDialog {
    id: calibrationDialog
    ComputerModel {
        id: calibrationHosts
        Component.onCompleted: initialize(ComputerManager)
    }
    CalibrationHostSelection {
        id: calibrationSelection
        hosts: calibrationHosts.onlineHosts
        testedUuid: calibrationDialog.testedHostUuid
        onTestedHostUnavailable: {
            calibrationDialog.hasStarted = false
            if (PyroWaveCalibrator.running) {
                calibrationDialog.stopRequested = true
                PyroWaveCalibrator.cancel()
            }
        }
    }
    objectName: "pyrowaveCalibrationDialog"
    property int step: 0
    property int targetIndex: 1
    property bool decoderWasRunning: false
    property int testFps: 60
    property int testedTarget: -1
    property string testedHostUuid: ""
    property bool hasStarted: false
    property bool stopRequested: false
    readonly property int selectedTarget: targets[targetIndex].value
    readonly property string selectedHostUuid: calibrationSelection.selectedUuid
    readonly property bool resultsMatch: hasStarted && testedTarget === selectedTarget && testedHostUuid === selectedHostUuid
    readonly property var targets: [
        { text: qsTr("Minimum"), summary: qsTr("Half recommendation"), value: PyroWaveCalibrator.Minimum,
          description: qsTr("Half the developer's recommended image bitrate. Uses less bandwidth.") },
        { text: qsTr("Recommended"), summary: qsTr("Developer choice"), value: PyroWaveCalibrator.Recommended,
          description: qsTr("The developer's recommended image bitrate for each format.") },
        { text: qsTr("Moderate"), summary: qsTr("60% of link speed"), value: PyroWaveCalibrator.Moderate,
          description: qsTr("Aim for 60% of the link speed including overhead, never below Recommended. Calibration lowers it to what the connection sustains.") },
        { text: qsTr("Maximum"), summary: qsTr("Full measured budget"), value: PyroWaveCalibrator.Maximum,
          description: qsTr("Find the highest tested bitrate the connection and this device can sustain, with network headroom.") }
    ]
    readonly property bool canContinue: resultsMatch && PyroWaveCalibrator.bandwidthReady
    title: step === 0 ? qsTr("1 of 2 · Connection & quality") : qsTr("2 of 2 · Decoder stress test")
    width: Math.min(Overlay.overlay.width - 24, step === 0 ? 850 : 1100)
    height: Math.min(Overlay.overlay.height - 24, step === 0 ? 480 : 760)
    standardButtons: Dialog.NoButton
    focus: true
    background: Rectangle {
        color: "#303030"
        radius: 12
        border.color: "#606060"
    }
    onAboutToShow: {
        PyroWaveCalibrator.reset()
        step = 0
        decoderWasRunning = false
        testFps = StreamingPreferences.fps
        testedTarget = -1
        hasStarted = false
        stopRequested = false
    }
    onOpened: { SdlGamepadKeyNavigation.setUiNavMode(true); focusTarget() }
    onAboutToHide: PyroWaveCalibrator.reset()

    function focusTarget() {
        var card = calibrationTargets.itemAt(targetIndex)
        if (card) card.forceActiveFocus(Qt.TabFocusReason)
    }
    function changeTarget(index) {
        if (PyroWaveCalibrator.running) return
        targetIndex = Math.max(0, Math.min(targets.length - 1, index))
        focusTarget()
    }
    function nextStep() {
        if (!canContinue) return
        step = 1
        stopRequested = false
        PyroWaveCalibrator.startDecoderTest(testedHostUuid, testedTarget)
        calibrationRunButton.forceActiveFocus(Qt.TabFocusReason)
    }
    Connections {
        target: PyroWaveCalibrator
        function onChanged() {
            if (calibrationDialog.step !== 1 || !calibrationDialog.opened) return
            if (PyroWaveCalibrator.running) calibrationDialog.decoderWasRunning = true
            else if (calibrationDialog.decoderWasRunning) {
                calibrationDialog.decoderWasRunning = false
                Qt.callLater(function() {
                    if (calibrationDialog.opened && calibrationDialog.step === 1 && !PyroWaveCalibrator.running)
                        calibrationDialog.focusOption(0, 0, 1)
                })
            }
        }
    }

    function testTarget() {
        if (PyroWaveCalibrator.running || calibrationSelection.currentIndex < 0) return
        testedTarget = selectedTarget
        testedHostUuid = selectedHostUuid
        hasStarted = true
        stopRequested = false
        PyroWaveCalibrator.start(ComputerManager,
                                 testedHostUuid,
                                 testFps,
                                 Math.round(Screen.width * Screen.devicePixelRatio),
                                 Math.round(Screen.height * Screen.devicePixelRatio),
                                 testedTarget)
        calibrationRunButton.forceActiveFocus(Qt.TabFocusReason)
    }

    function focusOption(row, mode, direction) {
        // Up/down follows one chroma column; left/right changes
        // chroma without changing HDR/SDR. Skip unavailable formats.
        var chroma = mode < 2 ? 0 : 2
        var position = row * 2 + mode % 2
        for (var attempt = 0; attempt < rows.length * 2; ++attempt) {
            if (position < 0) { calibrationRunButton.forceActiveFocus(Qt.TabFocusReason); return }
            if (position >= rows.length * 2) { calibrationCloseButton.forceActiveFocus(Qt.TabFocusReason); return }
            var rowItem = calibrationRows.itemAt(Math.floor(position / 2))
            var columnItem = rowItem ? rowItem.columns.itemAt(chroma / 2) : null
            var button = columnItem ? columnItem.formats.itemAt(position % 2) : null
            if (button && button.enabled) { button.forceActiveFocus(Qt.TabFocusReason); return }
            if (!direction) return
            position += direction
        }
        calibrationCloseButton.forceActiveFocus(Qt.TabFocusReason)
    }

    readonly property var rows: (Qt.platform.os === "linux" ? [
        { name: "4K", width: 3840, height: 2160 },
        { name: "1440p", width: 2560, height: 1440 },
        { name: "1080p", width: 1920, height: 1080 },
        { name: "800p", width: 1280, height: 800 },
        { name: "720p", width: 1280, height: 720 }
    ] : [
        { name: "4K", width: 3840, height: 2160 },
        { name: "1440p", width: 2560, height: 1440 },
        { name: "1080p", width: 1920, height: 1080 },
        { name: "720p", width: 1280, height: 720 }
    ])
    readonly property var samples: resultsMatch ? PyroWaveCalibrator.results : []
    readonly property var tierColors: ({
        "any": "#66bb6a",
        "vrr": "#ffca28",
        "vrrLarge": "#ff9800",
        "slow": "#ef5350",
        "error": "#9e9e9e"
    })

    // Results arrive in sweep order: per resolution, 4:4:4 HDR,
    // 4:4:4 SDR, 4:2:0 HDR, 4:2:0 SDR
    function sample(row, mode) {
        var offset = row * 4 + mode
        return offset < samples.length ? samples[offset] : null
    }

    function hdrUnavailable(option) {
        return option && option.hdr && !SystemProperties.supportsHdr
    }

    function canApply(option) {
        return step === 1 && !PyroWaveCalibrator.running && resultsMatch && option && option.valid && !hdrUnavailable(option)
    }

    function headline(option, hdr) {
        var format = hdr ? qsTr("HDR (10-bit)") : qsTr("SDR (8-bit)")
        if (option && option.valid) return format + " · " + qsTr("%1 Mbps").arg(option.bitrateKbps / 1000)
        return format
    }

    function tierText(option) {
        if (!option) return PyroWaveCalibrator.running ? qsTr("Testing…") : qsTr("Not tested")
        if (option.tier === "error") return option.error
        if (hdrUnavailable(option)) return qsTr("No HDR display")
        var text = option.tier === "slow" ? qsTr("Can't keep up") : option.tier === "any" ? qsTr("Any display") :
                   option.tier === "vrr" ? qsTr("Needs VRR") : qsTr("VRR · Smooth")
        if (option.quality === "reduced") text += " · " + qsTr("Reduced quality")
        else if (option.quality === "low") text += " · " + qsTr("Low quality")
        return text
    }

    function tierColor(option) {
        if (!option || hdrUnavailable(option)) return "#9e9e9e"
        if (option.tier !== "slow" && option.tier !== "error") {
            var minimum = Math.max(5000, Math.floor(option.guideKbps / 10000) * 5000)
            var required = selectedTarget === PyroWaveCalibrator.Minimum ? minimum : option.guideKbps
            if (option.imageKbps < minimum) return tierColors.slow
            if (option.imageKbps < required && option.tier === "any") return tierColors.vrr
        }
        return tierColors[option.tier]
    }

    function frameCost(option) {
        return qsTr("99% of frames take up to %1 ms to decode and draw, %2% of each frame at %3 FPS.")
                .arg(option.frameMs.toFixed(1)).arg(option.loadPercent).arg(testFps)
    }

    function optionDetail(option) {
        if (!option || !option.valid) return ""
        var details = [frameCost(option)]
        if (!option.keepsUp) {
            details.push(qsTr("A lower bitrate doesn't make this device fast enough, so the stream will stutter or fall behind. You can still use it."))
        }
        if (option.tier === "vrr") {
            details.push(qsTr("With VRR the occasional slow frame is shown slightly late; on a fixed-refresh display it would stutter."))
        }
        else if (option.tier === "vrrLarge") {
            details.push(qsTr("Slow frames use nearly the whole frame, so only the Smooth VRR latency mode's larger buffer hides them; other modes and fixed-refresh displays would stutter."))
        }
        details.push(qsTr("%1 Mbps of image data reaches %2 dB on the codec author's quality scale; he recommends %3 Mbps of image data (35 dB) for this format. The applied rate includes FEC and packet overhead.")
                     .arg(option.imageKbps / 1000).arg(option.qualityDb.toFixed(1))
                     .arg(option.guideKbps / 1000))
        if (option.deviceLimited) details.push(qsTr("The bitrate was lowered so this device keeps up."))
        if (option.linkLimited) details.push(qsTr("The tested network budget limits the image bitrate for this target."))
        return details.join(" ")
    }

    function applyChoice(option) {
        if (!canApply(option)) return
        StreamingPreferences.videoCodecConfig = StreamingPreferences.VCC_FORCE_PYROWAVE
        StreamingPreferences.width = option.width
        StreamingPreferences.height = option.height
        StreamingPreferences.enableYUV444 = option.chroma444
        StreamingPreferences.enableHdr = option.hdr
        StreamingPreferences.bitrateKbps = option.bitrateKbps
        // The tested frame pace; 0 lets the host use its default.
        StreamingPreferences.pyroWavePaceMbps = PyroWaveCalibrator.paceMbps
        StreamingPreferences.autoAdjustBitrate = false
        StreamingPreferences.save()
        close()
    }

    footer: Pane {
        padding: 12
        contentItem: RowLayout {
            spacing: 8
            CalibrationButton {
                id: calibrationRunButton
                objectName: "pyrowaveCalibrationRun"
                text: PyroWaveCalibrator.running ? (calibrationDialog.stopRequested ? qsTr("Stopping…") : qsTr("Stop test")) :
                      calibrationDialog.step === 0 ? qsTr("Test bandwidth") : qsTr("Test decoder again")
                enabled: PyroWaveCalibrator.running ? !calibrationDialog.stopRequested :
                         calibrationDialog.step === 0 ? calibrationSelection.currentIndex >= 0 : calibrationDialog.canContinue
                implicitHeight: 44
                highlighted: calibrationDialog.step === 0 && !calibrationDialog.canContinue
                onClicked: {
                    if (PyroWaveCalibrator.running) {
                        calibrationDialog.stopRequested = true
                        PyroWaveCalibrator.cancel()
                    }
                    else if (calibrationDialog.step === 0) calibrationDialog.testTarget()
                    else {
                        calibrationDialog.stopRequested = false
                        PyroWaveCalibrator.startDecoderTest(calibrationDialog.testedHostUuid, calibrationDialog.testedTarget)
                    }
                }
                Keys.onPressed: function(event) {
                    if (event.key === Qt.Key_Backtab || event.key === Qt.Key_Up ||
                            (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
                        if (calibrationDialog.step === 0 && !PyroWaveCalibrator.running) calibrationDialog.focusTarget()
                        else calibrationCloseButton.forceActiveFocus(Qt.TabFocusReason)
                    }
                    else if (event.key === Qt.Key_Right && calibrationDialog.step === 1) {
                        calibrationDetails.forceActiveFocus(Qt.TabFocusReason)
                    }
                    else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Down || event.key === Qt.Key_Right) {
                        if (calibrationDialog.step === 1) calibrationDialog.focusOption(0, 0, 1)
                        else if (calibrationNextButton.enabled) calibrationNextButton.forceActiveFocus(Qt.TabFocusReason)
                        else calibrationCloseButton.forceActiveFocus(Qt.TabFocusReason)
                    }
                    else return
                    event.accepted = true
                }
            }
            CalibrationButton {
                id: calibrationDetails
                objectName: "pyrowaveCalibrationDetails"
                visible: calibrationDialog.step === 1
                text: qsTr("About results")
                checkable: true
                implicitHeight: 44
                KeyNavigation.left: calibrationRunButton
                KeyNavigation.right: calibrationCloseButton.enabled ? calibrationCloseButton : calibrationRunButton
                KeyNavigation.backtab: calibrationRunButton
                Keys.onTabPressed: calibrationDialog.focusOption(0, 0, 1)
                Keys.onDownPressed: calibrationDialog.focusOption(0, 0, 1)
            }
            Item { Layout.fillWidth: true }
            CalibrationButton {
                id: calibrationCloseButton
                objectName: "pyrowaveCalibrationBack"
                text: calibrationDialog.step === 0 ? qsTr("Cancel") : qsTr("Back")
                enabled: calibrationDialog.step === 0 || !PyroWaveCalibrator.running
                implicitHeight: 44
                onClicked: {
                    if (calibrationDialog.step === 0) calibrationDialog.close()
                    else { calibrationDialog.step = 0; calibrationDialog.focusTarget() }
                }
                Keys.onTabPressed: {
                    if (calibrationDialog.step === 0 && !PyroWaveCalibrator.running) calibrationHost.forceActiveFocus(Qt.TabFocusReason)
                    else calibrationRunButton.forceActiveFocus(Qt.TabFocusReason)
                }
            }
            CalibrationButton {
                id: calibrationNextButton
                objectName: "pyrowaveCalibrationNext"
                text: qsTr("Next →")
                visible: calibrationDialog.step === 0
                enabled: calibrationDialog.canContinue
                implicitHeight: 44
                highlighted: true
                onClicked: calibrationDialog.nextStep()
                KeyNavigation.backtab: calibrationRunButton
                KeyNavigation.tab: calibrationCloseButton
                KeyNavigation.left: calibrationRunButton
            }
        }
    }

    contentItem: StackLayout {
        currentIndex: calibrationDialog.step
        ScrollView {
            id: calibrationConnectionScroll
            objectName: "pyrowaveCalibrationConnectionScroll"
            clip: true
            contentWidth: availableWidth
            ColumnLayout {
                width: calibrationConnectionScroll.availableWidth
                height: Math.max(implicitHeight, calibrationConnectionScroll.availableHeight)
                spacing: 12
                RowLayout {
                    Layout.fillWidth: true
                    Label { text: qsTr("Host") }
                    AutoResizingComboBox {
                        id: calibrationHost
                        objectName: "pyrowaveCalibrationHost"
                        Layout.fillWidth: true
                        model: calibrationSelection.hosts
                        textRole: "name"
                        currentIndex: calibrationSelection.currentIndex
                        onActivated: calibrationSelection.select(index)
                        displayText: count > 0 ? currentText : qsTr("No online hosts available")
                        enabled: count > 0 && !PyroWaveCalibrator.running
                        // Closed selectors use Tab for controller focus traversal.
                        // An open popup owns arrow keys for selecting a host.
                        KeyNavigation.backtab: calibrationCloseButton
                        Keys.onTabPressed: function(event) {
                            if (popup.visible) {
                                event.accepted = false
                                return
                            }
                            if (event.modifiers & Qt.ShiftModifier)
                                calibrationCloseButton.forceActiveFocus(Qt.TabFocusReason)
                            else calibrationDialog.focusTarget()
                        }
                    }
                    Label { text: qsTr("%1 FPS").arg(calibrationDialog.testFps) }
                }
                Label {
                    Layout.fillWidth: true
                    font.pointSize: 16
                    font.bold: true
                    text: qsTr("Choose your quality target")
                    wrapMode: Text.Wrap
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Repeater {
                        id: calibrationTargets
                        model: calibrationDialog.targets
                        delegate: CalibrationButton {
                            id: targetCard
                            objectName: "pyrowaveCalibrationTarget" + index
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            Layout.preferredHeight: 82
                            text: modelData.text
                            checked: calibrationDialog.targetIndex === index
                            enabled: !PyroWaveCalibrator.running
                            activeFocusOnTab: true
                            Accessible.name: modelData.text
                            Accessible.description: modelData.description
                            contentItem: Column {
                                spacing: 6
                                Label {
                                    width: parent.width
                                    text: (targetCard.checked ? "\u2713 " : "") + targetCard.text
                                    font.bold: targetCard.checked
                                    font.pointSize: 11
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideRight
                                    color: "#ffffff"
                                }
                                Label {
                                    width: parent.width
                                    text: modelData.summary
                                    font.pointSize: 9
                                    horizontalAlignment: Text.AlignHCenter
                                    wrapMode: Text.Wrap
                                    color: "#c7c7c7"
                                }
                            }
                            opacity: targetCard.enabled ? 1 : 0.6
                            onClicked: calibrationDialog.changeTarget(index)
                            Keys.priority: Keys.BeforeItem
                            Keys.onPressed: function(event) {
                                if (event.key === Qt.Key_Left) calibrationDialog.changeTarget(index - 1)
                                else if (event.key === Qt.Key_Right) calibrationDialog.changeTarget(index + 1)
                                else if (event.key === Qt.Key_Backtab || event.key === Qt.Key_Up ||
                                         (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier)))
                                    calibrationHost.forceActiveFocus(Qt.TabFocusReason)
                                else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Down)
                                    (calibrationRunButton.enabled ? calibrationRunButton : calibrationCloseButton).forceActiveFocus(Qt.TabFocusReason)
                                else return
                                event.accepted = true
                            }
                        }
                    }
                }
                Label {
                    Layout.fillWidth: true
                    Layout.minimumHeight: 32
                    wrapMode: Text.Wrap
                    text: calibrationDialog.targets[calibrationDialog.targetIndex].description
                }
                Label {
                    Layout.fillWidth: true
                    text: qsTr("Test your connection first, then continue to test this device's decoder.")
                    wrapMode: Text.Wrap
                    opacity: 0.7
                }
                Item { Layout.fillHeight: true }
                Pane {
                    Layout.fillWidth: true
                    padding: 12
                    readonly property string grade: calibrationDialog.canContinue ? PyroWaveCalibrator.bandwidthQuality : ""
                    readonly property bool warning: grade === "reduced"
                    background: Rectangle {
                        color: parent.grade === "low" ? "#452b2b" : calibrationDialog.canContinue ? (parent.warning ? "#413824" : "#283b2e") : "#252525"
                        radius: 8
                        border.color: parent.grade === "low" ? "#b45c5c" : calibrationDialog.canContinue ? (parent.warning ? "#aa8542" : "#568260") : "#505050"
                    }
                    contentItem: RowLayout {
                        spacing: 12
                        // Keep the text width stable when the spinner appears.
                        Item {
                            Layout.preferredWidth: 28
                            Layout.preferredHeight: 28
                            BusyIndicator {
                                anchors.fill: parent
                                running: PyroWaveCalibrator.running
                                visible: running
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            Label {
                                id: calibrationStatusText
                                objectName: "pyrowaveCalibrationStatus"
                                Layout.fillWidth: true
                                Layout.minimumHeight: fontMetrics.height * 3
                                verticalAlignment: Text.AlignTop
                                wrapMode: Text.Wrap
                                text: PyroWaveCalibrator.running && !calibrationSelection.testedHostAvailable ? qsTr("Host went offline. Stopping test…") :
                                      calibrationSelection.currentIndex < 0 ? qsTr("No online hosts available. Waiting for discovery.") :
                                      !calibrationDialog.hasStarted ? qsTr("Ready to test your connection.") :
                                      !calibrationDialog.resultsMatch ? qsTr("Selection changed. Test bandwidth again to continue.") : PyroWaveCalibrator.message
                            }
                            Label {
                                Layout.fillWidth: true
                                Layout.minimumHeight: fontMetrics.height * 2
                                opacity: calibrationDialog.canContinue ? 1 : 0
                                verticalAlignment: Text.AlignTop
                                wrapMode: Text.Wrap
                                color: PyroWaveCalibrator.bandwidthQuality === "low" ? "#ef9a9a" :
                                       PyroWaveCalibrator.bandwidthQuality === "reduced" ? "#ffd180" : "#a5d6a7"
                                text: qsTr("Measured budget: %1 Mbps · Target needs: %2 Mbps including overhead")
                                    .arg(PyroWaveCalibrator.bandwidthKbps / 1000).arg(PyroWaveCalibrator.bandwidthTargetKbps / 1000)
                            }
                            FontMetrics { id: fontMetrics; font: calibrationStatusText.font }
                        }
                    }
                }
                Label {
                    Layout.fillWidth: true
                    font.pointSize: 9
                    color: "#bdbdbd"
                    wrapMode: Text.Wrap
                    text: qsTr("↑↓ Navigate  ·  ←→ Choose target  ·  %1 Select  ·  %2 Back")
                        .arg(StreamingPreferences.swapFaceButtons ? "B" : "A")
                        .arg(StreamingPreferences.swapFaceButtons ? "A" : "B")
                }
            }
        }
        ColumnLayout {
            spacing: 8
            Label {
                Layout.fillWidth: true
                font.pointSize: 14
                font.bold: true
                text: calibrationDialog.targets[calibrationDialog.targetIndex].text + " · " + qsTr("%1 FPS").arg(calibrationDialog.testFps)
            }
            Label {
                objectName: "pyrowaveDecoderStatus"
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: PyroWaveCalibrator.message
            }
            ProgressBar {
                Layout.fillWidth: true
                from: 0
                to: calibrationDialog.rows.length * 4
                value: calibrationDialog.samples.length
                visible: PyroWaveCalibrator.running
            }
            Row {
                id: calibrationHeaders
                Layout.fillWidth: true
                spacing: 6
                Label { width: 72; text: qsTr("Resolution") }
                Label { width: (calibrationHeaders.width - 84) / 2; text: "4:4:4"; horizontalAlignment: Text.AlignHCenter }
                Label { width: (calibrationHeaders.width - 84) / 2; text: "4:2:0"; horizontalAlignment: Text.AlignHCenter }
            }
            Flickable {
                id: calibrationResults
                objectName: "pyrowaveCalibrationResults"
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width
                contentHeight: calibrationTable.height
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar {}
                function ensureFocusedVisible() {
                    var item = Window.activeFocusItem
                    if (!item) return
                    var ancestor = item
                    while (ancestor && ancestor !== contentItem) ancestor = ancestor.parent
                    if (!ancestor) return
                    var position = item.mapToItem(contentItem, 0, 0)
                    if (position.y < contentY) contentY = position.y
                    else if (position.y + item.height > contentY + height)
                        contentY = Math.min(Math.max(0, contentHeight - height), position.y + item.height - height)
                }
                Window.onActiveFocusItemChanged: ensureFocusedVisible()
                onHeightChanged: ensureFocusedVisible()
                Column {
                    id: calibrationTable
                    width: parent.width
                    spacing: 6
                    Label {
                        width: parent.width
                        visible: calibrationDetails.checked
                        wrapMode: Text.Wrap
                        font.pointSize: 9
                        text: PyroWaveCalibrator.linkSummary + " " +
                              qsTr("Rates include FEC and packet overhead. Quality is relative to the developer's recommended image bitrate. Every selected target is tested afresh.")
                    }
                    Flow {
                        width: parent.width
                        spacing: 12
                        Repeater {
                            model: [
                                { tier: "any", text: qsTr("Any display") },
                                { tier: "vrr", text: qsTr("Needs VRR") },
                                { tier: "vrrLarge", text: qsTr("VRR · Smooth") },
                                { tier: "slow", text: qsTr("Can't keep up") }
                            ]
                            delegate: Row {
                                spacing: 5
                                Rectangle {
                                    width: 8; height: 8; radius: 4
                                    anchors.verticalCenter: parent.verticalCenter
                                    color: calibrationDialog.tierColors[modelData.tier]
                                }
                                Label { text: modelData.text; font.pointSize: 9 }
                            }
                        }
                    }
                    Repeater {
                        model: calibrationDetails.checked ? [
                            { tier: "any", text: qsTr("Any display: 99% of frames use at most 60% of each frame, leaving room for a live stream's extra work with or without VRR.") },
                            { tier: "vrr", text: qsTr("Needs VRR: slow frames use up to 80% of each frame. VRR hides the occasional late one; a fixed-refresh display may stutter.") },
                            { tier: "vrrLarge", text: qsTr("Needs VRR · Smooth mode: slow frames use nearly the whole frame. Only the Smooth VRR latency mode's larger buffer hides them.") },
                            { tier: "slow", text: qsTr("Can't keep up: at %1 FPS, more than 1 frame in 100 takes longer than a frame to decode and draw. Expect stutter; it can still be selected.").arg(calibrationDialog.testFps) }
                        ] : []
                        delegate: Row {
                            spacing: 6
                            Rectangle {
                                width: 10
                                height: 10
                                radius: 5
                                anchors.verticalCenter: parent.verticalCenter
                                color: calibrationDialog.tierColors[modelData.tier]
                            }
                            Label {
                                width: calibrationTable.width - 16
                                wrapMode: Text.Wrap
                                font.pointSize: 9
                                text: modelData.text
                            }
                        }
                    }

                    Label {
                        width: parent.width
                        wrapMode: Text.Wrap
                        font.pointSize: 9
                        visible: calibrationDetails.checked
                        text: qsTr("Reduced or low quality means the image bitrate is below the developer's recommendation. This can follow your chosen target, network limits, or device limits.")
                    }



                    Repeater {
                        id: calibrationRows
                        model: calibrationDialog.rows
                        delegate: Row {
                            id: calibrationRow
                            width: calibrationTable.width
                            spacing: 6
                            readonly property int rowIndex: index
                            readonly property var rowData: modelData
                            property alias columns: calibrationChroma

                            Label {
                                width: 72
                                text: calibrationRow.rowData.name
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Repeater {
                                id: calibrationChroma
                                // 4:4:4 then 4:2:0, each HDR then SDR
                                model: [[0, 1], [2, 3]]
                                delegate: Column {
                                    id: chromaColumn
                                    readonly property var modes: modelData
                                    property alias formats: calibrationFormats
                                    width: (calibrationTable.width - 84) / 2
                                    spacing: 2

                                    Repeater {
                                        id: calibrationFormats
                                        model: chromaColumn.modes
                                        delegate: CalibrationButton {
                                            id: optionButton
                                            objectName: "pyrowaveCalibrationOption" + (calibrationRow.rowIndex * 4 + modelData)
                                            width: parent.width
                                            height: 44
                                            padding: 6
                                            topPadding: 4
                                            bottomPadding: 4
                                            topInset: 0
                                            bottomInset: 0
                                            leftInset: 0
                                            rightInset: 0
                                            readonly property var option: calibrationDialog.sample(calibrationRow.rowIndex, modelData)
                                            readonly property bool hdr: modelData % 2 === 0
                                            enabled: calibrationDialog.canApply(option)
                                            Accessible.name: calibrationDialog.headline(option, hdr)
                                            Accessible.description: option && option.valid ? calibrationDialog.frameCost(option) : ""
                                            ToolTip.delay: 400
                                            ToolTip.visible: hovered && ToolTip.text !== ""
                                            ToolTip.text: calibrationDialog.optionDetail(option)
                                            onClicked: calibrationDialog.applyChoice(option)
                                            Keys.onPressed: function(event) {
                                                var mode = modelData
                                                var row = calibrationRow.rowIndex
                                                if (event.key === Qt.Key_Left || event.key === Qt.Key_Right) {
                                                    calibrationDialog.focusOption(row, event.key === Qt.Key_Left ? mode % 2 : 2 + mode % 2, 0)
                                                }
                                                else if (event.key === Qt.Key_Up || event.key === Qt.Key_Backtab ||
                                                         (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
                                                    calibrationDialog.focusOption(mode % 2 ? row : row - 1,
                                                        mode % 2 ? mode - 1 : mode + 1, -1)
                                                }
                                                else if (event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
                                                    calibrationDialog.focusOption(mode % 2 ? row + 1 : row,
                                                        mode % 2 ? mode - 1 : mode + 1, 1)
                                                }
                                                else return
                                                event.accepted = true
                                            }

                                            contentItem: Column {
                                                spacing: 2
                                                opacity: !optionButton.enabled ? 0.6 : optionButton.activeFocus || optionButton.hovered ? 1.0 : optionButton.option && !optionButton.option.keepsUp ? 0.7 : 1.0

                                                Label {
                                                    width: parent.width
                                                    horizontalAlignment: Text.AlignHCenter
                                                    elide: Text.ElideRight
                                                    font.pointSize: 10
                                                    text: calibrationDialog.headline(optionButton.option, optionButton.hdr)
                                                }

                                                Row {
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    spacing: 6

                                                    Rectangle {
                                                        width: 10
                                                        height: 10
                                                        radius: 5
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        visible: !!optionButton.option
                                                        color: calibrationDialog.tierColor(optionButton.option)
                                                    }

                                                    Label {
                                                        font.pointSize: 9
                                                        width: Math.min(implicitWidth, optionButton.width - 30)
                                                        elide: Text.ElideRight
                                                        text: calibrationDialog.tierText(optionButton.option)

                                                        // Untested cells keep the style's text color
                                                        Binding on color {
                                                            when: !!optionButton.option
                                                            value: calibrationDialog.tierColor(optionButton.option)
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
