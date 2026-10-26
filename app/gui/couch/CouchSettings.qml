import QtQuick 2.9
import QtQuick.Controls 2.2

import StreamingPreferences 1.0
import SystemProperties 1.0
import AutoUpdateChecker 1.0
import ComputerManager 1.0
import PyroWaveCalibrator 1.0
import NetworkBuffers 1.0
import ".."
import "."

// Settings for controller, keyboard and mouse alike: sections in a list
// on the left (LB/RB from anywhere), their settings on the right. Each
// change applies at once and is saved when the page closes.
FocusScope {
    id: settingsPage
    objectName: qsTr("Settings")

    property int sectionIndex: 0
    // Which side has focus: "sections" (the list) or "rows"
    property string zone: "rows"
    property Item activeRow: null
    property Item pickingRow: null

    readonly property var sections: [videoSection, displaySection, audioSection, inputSection,
                                     controllerSection, steamControllerSection, hostSection,
                                     interfaceSection, advancedSection, diagnosticsSection]
    readonly property Item currentSection: sections[sectionIndex]
    // Too little room beside the content puts the sections in a row on top
    readonly property bool narrow: width < CouchTheme.px(960)

    Binding {
        target: CouchTheme
        property: "s"
        value: CouchTheme.scaleFor(settingsPage.width, settingsPage.height)
    }

    StackView.onActivated: {
        toolBar.visible = false
        restoreFocus()
    }

    StackView.onDeactivating: {
        toolBar.visible = true
        // Save the prefs so the Session can observe the changes
        StreamingPreferences.save()
    }

    Component.onCompleted: {
        SystemProperties.refreshDisplays()
        NetworkBuffers.refresh()
        var all = sections
        for (var i = 0; i < all.length; i++) {
            var rows = all[i].settingRows()
            for (var j = 0; j < rows.length; j++) {
                rows[j].page = settingsPage
            }
        }
    }

    // Also save preferences on destruction, since we won't get a
    // deactivating callback if the user just closes Moonlight
    Component.onDestruction: StreamingPreferences.save()

    function restoreFocus() {
        if (sheet.visible || prompt.visible || stackView.currentItem !== settingsPage) {
            return
        }
        if (zone === "sections" || !currentSection.focusFirst()) {
            zone = "sections"
            sectionList.forceActiveFocus()
        }
    }

    function selectSection(index) {
        if (index < 0 || index >= sections.length || index === sectionIndex) {
            return
        }
        sectionIndex = index
        if (zone === "rows") {
            restoreFocus()
        }
    }

    function focusSections() {
        zone = "sections"
        restoreFocus()
    }

    function focusRows() {
        zone = "rows"
        restoreFocus()
    }

    // Called by a row that got focus, also from a click
    function rowFocused(row) {
        activeRow = row
        zone = "rows"
        for (var i = 0; i < sections.length; i++) {
            if (sections[i].focusableRows().indexOf(row) >= 0) {
                sections[i].lastRow = row
                sections[i].reveal(row)
            }
        }
    }

    // Shows a choice row's options as a list
    function chooseOption(row) {
        var actions = []
        for (var i = 0; i < row.options.length; i++) {
            (function(option) {
                actions.push({
                    text: option.text,
                    checked: option.value === row.value ? true : undefined,
                    run: function() { row.picked(option.value) }
                })
            })(row.options[i])
        }
        pickingRow = row
        sheet.present(row.title, "", actions, row.optionIndex)
    }

    // Asks a stepper row for a typed value
    function askNumber(row) {
        pickingRow = row
        prompt.ask(row.title, row.inputText, row.inputHint, function(text) {
            var value = row.fromInput(text)
            if (isNaN(value) || value < row.from || value > row.to) {
                showToast(qsTr("Enter a value: %1").arg(row.inputHint))
                return
            }
            row.stepped(value)
        })
    }

    function showToast(text) {
        toast.text = text
        toast.shown = true
        toastTimer.restart()
    }

    function goBack() {
        window.goBack()
    }

    Keys.onPressed: function(event) {
        if (event.key === Qt.Key_PageUp) {
            selectSection(sectionIndex - 1)
            event.accepted = true
        }
        else if (event.key === Qt.Key_PageDown) {
            selectSection(sectionIndex + 1)
            event.accepted = true
        }
        // Start, which opened this page, closes it again
        else if (event.key === Qt.Key_Hangup) {
            goBack()
            event.accepted = true
        }
    }

    // ---- Video ----

    readonly property bool pyroWave: StreamingPreferences.videoCodecConfig === StreamingPreferences.VCC_FORCE_PYROWAVE
    readonly property int bitrateMin: pyroWave ? 5000 : 500
    readonly property int bitrateMax: pyroWave ? 3000000 : (StreamingPreferences.unlockBitrate ? 500000 : 150000)

    // PyroWave needs several hundred Mbps, up to multi-gigabit LANs
    function defaultBitrate() {
        if (pyroWave) {
            return StreamingPreferences.getDefaultPyroWaveBitrate(StreamingPreferences.width,
                                                                  StreamingPreferences.height,
                                                                  StreamingPreferences.fps,
                                                                  StreamingPreferences.enableYUV444,
                                                                  StreamingPreferences.enableHdr)
        }
        return StreamingPreferences.getDefaultBitrate(StreamingPreferences.width,
                                                      StreamingPreferences.height,
                                                      StreamingPreferences.fps,
                                                      StreamingPreferences.enableYUV444)
    }

    // Keeps the bitrate on its default for the format, unless the
    // user picked one
    function updateDefaultBitrate() {
        if (StreamingPreferences.autoAdjustBitrate) {
            StreamingPreferences.bitrateKbps = defaultBitrate()
        }
        else if (StreamingPreferences.bitrateKbps > bitrateMax) {
            StreamingPreferences.bitrateKbps = bitrateMax
        }
    }

    function mbps(kbps) {
        return qsTr("%1 Mbps").arg(kbps / 1000)
    }

    // Steps get coarser as the bitrate grows, so the d-pad crosses the range quickly
    function bitrateStep(kbps) {
        if (pyroWave) {
            return kbps < 100000 ? 5000 : kbps < 500000 ? 25000 : 100000
        }
        return kbps < 10000 ? 500 : kbps < 50000 ? 1000 : kbps < 100000 ? 5000 : 10000
    }

    function resolutionOptions() {
        var list = [
            { text: qsTr("720p"), width: 1280, height: 720 },
            { text: qsTr("1080p"), width: 1920, height: 1080 },
            { text: qsTr("1440p"), width: 2560, height: 1440 },
            { text: qsTr("4K"), width: 3840, height: 2160 }
        ]

        function add(prefix, rect) {
            if (rect.width === 0) return
            for (var i = 0; i < list.length; i++) {
                if (list[i].width === rect.width && list[i].height === rect.height) return
            }
            list.push({ text: prefix + " (" + rect.width + "x" + rect.height + ")", width: rect.width, height: rect.height })
        }

        // Native and safe area resolutions for all attached displays
        for (var displayIndex = 0; ; displayIndex++) {
            var screenRect = SystemProperties.getNativeResolution(displayIndex)
            if (screenRect.width === 0) break
            add(qsTr("Native"), screenRect)
            add(qsTr("Native (Excluding Notch)"), SystemProperties.getSafeAreaResolution(displayIndex))
        }

        // Drop resolutions that are over the decoder's maximum
        var maxPixels = SystemProperties.maximumResolution.width * SystemProperties.maximumResolution.height
        if (maxPixels > 0) {
            list = list.filter(function(entry) { return entry.width * entry.height <= maxPixels })
        }
        list.sort(function(a, b) { return a.width * a.height - b.width * b.height })

        var saved = StreamingPreferences.width + "x" + StreamingPreferences.height
        var options = list.map(function(entry) { return { text: entry.text, value: entry.width + "x" + entry.height } })
        if (!options.some(function(option) { return option.value === saved })) {
            options.push({ text: qsTr("Custom (%1)").arg(saved), value: saved })
        }
        options.push({ text: qsTr("Custom…"), value: "custom", listOnly: true })
        return options
    }

    function refreshRates() {
        var rates = []
        for (var displayIndex = 0; ; displayIndex++) {
            var rate = SystemProperties.getRefreshRate(displayIndex)
            if (rate === 0) break
            rates.push(rate)
        }
        return rates
    }

    function fpsOptions() {
        var choices = StreamingPreferences.getFpsChoices(refreshRates())
        var options = choices.map(function(choice) {
            var fps = parseInt(choice.video_fps)
            switch (choice.kind) {
            case "vrr": return { text: qsTr("VRR (%1 FPS)").arg(fps), value: fps }
            case "low-latency-vrr": return { text: qsTr("Low-latency VRR (%1 FPS)").arg(fps), value: fps }
            case "custom": return { text: qsTr("Custom (%1 FPS)").arg(fps), value: fps }
            default: return { text: qsTr("%1 FPS").arg(fps), value: fps }
            }
        })
        options.push({ text: qsTr("Custom…"), value: "custom", listOnly: true })
        return options
    }

    function askCustomResolution() {
        prompt.ask(qsTr("Custom resolution"), StreamingPreferences.width + "x" + StreamingPreferences.height,
                   qsTr("Width x height, such as 2560x1600"), function(text) {
            var match = /^\s*(\d+)\s*[x×*]\s*(\d+)\s*$/i.exec(text)
            var width = match ? parseInt(match[1]) : 0
            var height = match ? parseInt(match[2]) : 0
            if (width < 256 || width > 8192 || height < 256 || height > 8192) {
                showToast(qsTr("Enter a width and height from 256 to 8192"))
                return
            }
            setResolution(width, height)
        })
    }

    function setResolution(width, height) {
        if (StreamingPreferences.width !== width || StreamingPreferences.height !== height) {
            StreamingPreferences.width = width
            StreamingPreferences.height = height
            updateDefaultBitrate()
        }
    }

    function askCustomFps() {
        prompt.ask(qsTr("Custom frame rate"), "" + StreamingPreferences.fps, qsTr("Frames per second"), function(text) {
            var fps = parseInt(text)
            if (isNaN(fps) || fps < 10 || fps > 9999) {
                showToast(qsTr("Enter a frame rate from 10 to 9999"))
                return
            }
            setFps(fps)
        }, { digits: true })
    }

    function setFps(fps) {
        if (StreamingPreferences.fps !== fps) {
            StreamingPreferences.fps = fps
            updateDefaultBitrate()
        }
    }

    function openCalibration() {
        calibrationLoader.active = true
        calibrationLoader.item.open()
    }

    // ---- Display ----

    readonly property bool vrrActive: StreamingPreferences.enableVsync && StreamingPreferences.enableVrr
    readonly property int vrrPresetIndex: {
        var p = StreamingPreferences
        if (p.vrrToleranceUs !== 500) return 3
        if (p.vrrBufferPerMille === 500 && p.vrrTargetHundredths === 9900 && p.vrrHistorySeconds === 60) return 0
        if (p.vrrBufferPerMille === 1000 && p.vrrTargetHundredths === 9950 && p.vrrHistorySeconds === 120) return 1
        if (p.vrrBufferPerMille === 4000 && p.vrrTargetHundredths === 9995 && p.vrrHistorySeconds === 300) return 2
        return 3
    }

    function decimal(value, places) {
        return Number(value).toLocaleString(Qt.locale(), 'f', places)
    }

    // Reads a number typed with either decimal separator
    function parseDecimal(text) {
        var value = Number.fromLocaleString(Qt.locale(), text.trim())
        return isNaN(value) ? Number(text.trim().replace(",", ".")) : value
    }

    function windowModeOptions() {
        var options = [
            { text: qsTr("Fullscreen"), value: StreamingPreferences.WM_FULLSCREEN },
            { text: qsTr("Borderless windowed"), value: StreamingPreferences.WM_FULLSCREEN_DESKTOP },
            { text: qsTr("Windowed"), value: StreamingPreferences.WM_WINDOWED }
        ]
        // The recommended mode for this OS comes first
        for (var i = 0; i < options.length; i++) {
            if (options[i].value === StreamingPreferences.recommendedFullScreenMode) {
                var recommended = options.splice(i, 1)[0]
                recommended.text += " " + qsTr("(Recommended)")
                options.unshift(recommended)
                break
            }
        }
        return options
    }

    // ---- Interface ----

    function setLanguage(language) {
        // Retranslating is expensive, so only do it if the language actually changed
        if (StreamingPreferences.language === language) {
            return
        }
        StreamingPreferences.language = language
        if (!StreamingPreferences.retranslate()) {
            showToast(qsTr("You must restart Moonlight for this change to take effect"))
        }
        else {
            // Force the back operation to pop any AppView pages that exist.
            // The AppView stops working after retranslate() for some reason.
            window.clearOnBack = true
        }
    }

    function setMdns(enabled) {
        if (StreamingPreferences.enableMdns === enabled) {
            return
        }
        StreamingPreferences.enableMdns = enabled
        // Restart polling so the mDNS change takes effect
        if (window.pollingActive) {
            ComputerManager.stopPollingAsync()
            ComputerManager.startPolling()
        }
    }

    // ---- Layout ----

    Rectangle {
        anchors.fill: parent
        color: CouchTheme.background
    }

    Item {
        id: topBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: CouchTheme.px(80)

        Row {
            anchors.left: parent.left
            anchors.leftMargin: CouchTheme.px(28)
            anchors.verticalCenter: parent.verticalCenter
            spacing: CouchTheme.px(8)

            // Back, for the mouse
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: CouchTheme.px(44)
                height: width
                radius: width / 2
                color: backMouse.containsMouse ? CouchTheme.surfaceRaised : "transparent"

                Text {
                    anchors.centerIn: parent
                    anchors.verticalCenterOffset: -CouchTheme.px(2)
                    text: "‹"
                    color: CouchTheme.text
                    font.pixelSize: CouchTheme.px(34)
                }

                MouseArea {
                    id: backMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: goBack()
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("Settings")
                color: CouchTheme.text
                font.pixelSize: CouchTheme.px(28)
                font.bold: true
            }
        }

        Text {
            id: clock
            anchors.right: parent.right
            anchors.rightMargin: CouchTheme.px(40)
            anchors.verticalCenter: parent.verticalCenter
            color: CouchTheme.text
            font.pixelSize: CouchTheme.px(20)
            font.bold: true

            Timer {
                interval: 10000
                running: true
                repeat: true
                triggeredOnStart: true
                onTriggered: clock.text = Qt.formatTime(new Date(), Qt.locale().timeFormat(Locale.ShortFormat))
            }
        }
    }

    // The sections, as a column on the left or a row on top
    ListView {
        id: sectionList
        objectName: "couchSettingsSections"
        anchors.left: parent.left
        anchors.top: topBar.bottom
        anchors.leftMargin: CouchTheme.px(narrow ? 24 : 32)
        width: narrow ? parent.width - CouchTheme.px(48) : CouchTheme.px(260)
        height: narrow ? CouchTheme.px(48) : hintBar.y - topBar.height - CouchTheme.px(16)
        orientation: narrow ? ListView.Horizontal : ListView.Vertical
        spacing: CouchTheme.px(4)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: sections.length
        currentIndex: sectionIndex
        highlightMoveDuration: CouchTheme.fast

        delegate: Rectangle {
            readonly property bool current: index === sectionIndex
            readonly property bool lit: current && sectionList.activeFocus

            width: narrow ? sectionLabel.implicitWidth + CouchTheme.px(36) : sectionList.width
            height: CouchTheme.px(48)
            radius: narrow ? height / 2 : CouchTheme.px(10)
            color: lit ? CouchTheme.accent :
                   current ? CouchTheme.surfaceRaised :
                   sectionMouse.containsMouse ? CouchTheme.surface : "transparent"

            Behavior on color {
                ColorAnimation { duration: CouchTheme.fast }
            }

            Text {
                id: sectionLabel
                anchors.left: parent.left
                anchors.leftMargin: CouchTheme.px(narrow ? 18 : 20)
                anchors.verticalCenter: parent.verticalCenter
                text: sections[index].title
                color: lit ? CouchTheme.accentText : current ? CouchTheme.text : CouchTheme.textDim
                font.pixelSize: CouchTheme.px(18)
                font.bold: current
            }

            MouseArea {
                id: sectionMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                    sectionIndex = index
                    focusSections()
                }
            }
        }

        Keys.onUpPressed: if (!narrow) selectSection(sectionIndex - 1)
        Keys.onDownPressed: narrow ? focusRows() : selectSection(sectionIndex + 1)
        Keys.onLeftPressed: if (narrow) selectSection(sectionIndex - 1)
        Keys.onRightPressed: narrow ? selectSection(sectionIndex + 1) : focusRows()
        Keys.onReturnPressed: focusRows()
        Keys.onEnterPressed: focusRows()
    }

    Item {
        id: content
        anchors.left: narrow ? parent.left : sectionList.right
        anchors.right: parent.right
        anchors.top: narrow ? sectionList.bottom : topBar.bottom
        anchors.bottom: hintBar.top
        anchors.leftMargin: CouchTheme.px(narrow ? 12 : 24)
        anchors.rightMargin: CouchTheme.px(narrow ? 12 : 32)
        anchors.topMargin: CouchTheme.px(narrow ? 8 : 0)

        // Long lines are hard to read on a wide screen
        Item {
            id: pages
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(parent.width, CouchTheme.px(980))

            Keys.onLeftPressed: focusSections()
            Keys.onUpPressed: if (narrow) focusSections()

            CouchSettingsSection {
                id: videoSection
                title: qsTr("Video")
                anchors.fill: parent
                visible: currentSection === videoSection

                CouchSettingRow {
                    objectName: "resolution"
                    kind: "choice"
                    title: qsTr("Resolution")
                    description: qsTr("Setting values too high for your PC or network connection may cause lag, stuttering, or errors.")
                    options: resolutionOptions()
                    value: StreamingPreferences.width + "x" + StreamingPreferences.height
                    onPicked: function(value) {
                        if (value === "custom") {
                            askCustomResolution()
                            return
                        }
                        var size = value.split("x")
                        setResolution(parseInt(size[0]), parseInt(size[1]))
                    }
                }

                CouchSettingRow {
                    objectName: "fps"
                    kind: "choice"
                    title: qsTr("Frame rate")
                    description: StreamingPreferences.enableVrr ?
                                     qsTr("With VRR, choose your display's full refresh rate, or a lower VRR option for more headroom or lower latency.") : ""
                    options: {
                        // The choices depend on V-Sync, VRR and a saved custom rate
                        StreamingPreferences.enableVsync
                        StreamingPreferences.enableVrr
                        StreamingPreferences.fps
                        return fpsOptions()
                    }
                    value: StreamingPreferences.fps
                    onPicked: function(value) {
                        if (value === "custom") askCustomFps()
                        else setFps(value)
                    }
                }

                CouchSettingRow {
                    objectName: "codec"
                    kind: "choice"
                    title: qsTr("Video codec")
                    description: pyroWave ? qsTr("PyroWave is a GPU wavelet codec. It needs a wired connection with hundreds of Mbps to spare and a host with PyroWave support; other hosts fall back to H.264. On Linux, GPU readback and upload may limit frame rate.") : ""
                    options: {
                        var list = [
                            { text: qsTr("Automatic (Recommended)"), value: StreamingPreferences.VCC_AUTO },
                            { text: qsTr("H.264"), value: StreamingPreferences.VCC_FORCE_H264 },
                            { text: qsTr("HEVC (H.265)"), value: StreamingPreferences.VCC_FORCE_HEVC },
                            { text: qsTr("AV1"), value: StreamingPreferences.VCC_FORCE_AV1 }
                        ]
                        if (SystemProperties.hasPyroWave) {
                            list.push({ text: qsTr("PyroWave (wired LAN, experimental)"), value: StreamingPreferences.VCC_FORCE_PYROWAVE })
                        }
                        return list
                    }
                    // A deprecated saved codec shows as Automatic
                    value: optionIndexOf(options, StreamingPreferences.videoCodecConfig) >= 0 ?
                               StreamingPreferences.videoCodecConfig : StreamingPreferences.VCC_AUTO
                    onPicked: function(value) {
                        var wasPyroWave = pyroWave
                        StreamingPreferences.videoCodecConfig = value
                        // PyroWave's useful bitrates are an order of magnitude above
                        // the other codecs', so switching in or out resets a default.
                        if (pyroWave !== wasPyroWave && StreamingPreferences.autoAdjustBitrate) {
                            StreamingPreferences.bitrateKbps = defaultBitrate()
                        }
                        else if (StreamingPreferences.bitrateKbps > bitrateMax) {
                            StreamingPreferences.bitrateKbps = bitrateMax
                        }
                    }
                }

                CouchSettingRow {
                    kind: "toggle"
                    title: qsTr("Enable HDR")
                    description: enabled ? qsTr("The stream will be HDR-capable, but some games may require an HDR monitor on your host PC to enable HDR mode.")
                                         : qsTr("HDR streaming is not supported on this PC.")
                    enabled: SystemProperties.supportsHdr
                    checked: enabled && StreamingPreferences.enableHdr
                    onToggled: function(checked) {
                        StreamingPreferences.enableHdr = checked
                        // PyroWave's default bitrate depends on HDR
                        if (pyroWave) updateDefaultBitrate()
                    }
                }

                CouchSettingRow {
                    kind: "toggle"
                    title: qsTr("Enable YUV 4:4:4")
                    description: qsTr("Good for streaming desktop and text-heavy games, but not recommended for fast-paced games.")
                    checked: StreamingPreferences.enableYUV444
                    onToggled: function(checked) {
                        StreamingPreferences.enableYUV444 = checked
                        updateDefaultBitrate()
                    }
                }

                CouchSettingRow {
                    objectName: "bitrate"
                    kind: "stepper"
                    title: qsTr("Video bitrate")
                    description: qsTr("Lower the bitrate on slower connections. Raise the bitrate to increase image quality.") +
                                 (StreamingPreferences.autoAdjustBitrate ? " " + qsTr("Follows the resolution and frame rate until you change it.") : "")
                    value: StreamingPreferences.bitrateKbps
                    from: bitrateMin
                    to: bitrateMax
                    stepSize: bitrateStep(value)
                    valueText: mbps(value)
                    inputText: "" + value / 1000
                    inputHint: qsTr("%1 to %2 Mbps").arg(bitrateMin / 1000).arg(bitrateMax / 1000)
                    fromInput: function(text) { return Math.round(parseDecimal(text) * 1000) }
                    onStepped: function(value) {
                        // Stepping down from a coarse step lands on the finer grid
                        StreamingPreferences.bitrateKbps = value
                        StreamingPreferences.autoAdjustBitrate = false
                    }
                }

                CouchSettingRow {
                    kind: "button"
                    title: qsTr("Use default bitrate (%1)").arg(mbps(defaultBitrate()))
                    visible: StreamingPreferences.bitrateKbps !== defaultBitrate()
                    onActivated: {
                        StreamingPreferences.bitrateKbps = defaultBitrate()
                        StreamingPreferences.autoAdjustBitrate = true
                    }
                }

                CouchSettingRow {
                    objectName: "pyrowavePacketSpeed"
                    kind: "stepper"
                    visible: SystemProperties.hasPyroWave && pyroWave
                    title: qsTr("Packet speed")
                    description: qsTr("Controls how fast each PyroWave frame is sent. Lower it to reduce shimmering from packet loss. Video bitrate controls the amount of data. Changes apply to the next stream.") + " " +
                                 (value === 0 ? qsTr("Automatic: the host chooses the packet speed from the link. Calibration sets a measured speed here.")
                                              : qsTr("The host caps this at its link speed and raises it if needed to carry the video bitrate. Calibration replaces this value when you apply a result."))
                    value: StreamingPreferences.pyroWavePaceMbps
                    from: 0
                    to: 9999
                    stepSize: 50
                    valueText: value === 0 ? qsTr("Automatic") : mbps(value * 1000)
                    inputText: "" + value
                    inputHint: qsTr("0 (Automatic) to 9999 Mbps")
                    fromInput: function(text) { return parseInt(text) }
                    onStepped: function(value) { StreamingPreferences.pyroWavePaceMbps = value }
                }

                CouchSettingRow {
                    kind: "note"
                    warning: true
                    visible: pyroWave && (Qt.platform.os === "linux" || Qt.platform.os === "windows") && NetworkBuffers.needsFix
                    description: NetworkBuffers.problemText
                }

                CouchSettingRow {
                    kind: "button"
                    visible: pyroWave && NetworkBuffers.needsFix && NetworkBuffers.canApply
                    enabled: !NetworkBuffers.busy
                    title: qsTr("Fix it")
                    description: NetworkBuffers.fixDescription
                    onActivated: NetworkBuffers.apply()
                }

                CouchSettingRow {
                    kind: "button"
                    visible: pyroWave && NetworkBuffers.needsFix
                    title: qsTr("Copy command")
                    description: NetworkBuffers.canApply ? "" : NetworkBuffers.manualHint + "\n" + NetworkBuffers.manualCommand
                    onActivated: {
                        NetworkBuffers.copyCommand()
                        showToast(qsTr("Copied"))
                    }
                }

                CouchSettingRow {
                    kind: "note"
                    visible: pyroWave && NetworkBuffers.message !== ""
                    description: NetworkBuffers.message
                }

                CouchSettingRow {
                    objectName: "pyrowaveCalibrationOpen"
                    kind: "button"
                    visible: SystemProperties.hasPyroWave && pyroWave
                    enabled: !PyroWaveCalibrator.running
                    title: qsTr("Calibrate PyroWave…")
                    description: qsTr("Measures the connection to a host and how fast this device decodes each format, then applies the format and bitrate you pick.")
                    onActivated: openCalibration()
                }
            }

            CouchSettingsSection {
                id: displaySection
                title: qsTr("Display")
                anchors.fill: parent
                visible: currentSection === displaySection

                CouchSettingRow {
                    kind: "choice"
                    visible: SystemProperties.hasDesktopEnvironment
                    enabled: !SystemProperties.rendererAlwaysFullScreen && !vrrActive
                    title: qsTr("Display mode")
                    description: vrrActive ? qsTr("Borderless windowed mode is required for active VRR streaming. Your saved display mode will be restored for non-VRR sessions.")
                                           : qsTr("Fullscreen generally provides the best performance, but borderless windowed may work better with features like macOS Spaces, Alt+Tab, screenshot tools, on-screen overlays, etc.")
                    options: windowModeOptions()
                    // VRR sessions use borderless presentation, but the
                    // saved window-mode preference is never overwritten.
                    value: vrrActive ? StreamingPreferences.WM_FULLSCREEN_DESKTOP : StreamingPreferences.windowMode
                    onPicked: function(value) { StreamingPreferences.windowMode = value }
                }

                CouchSettingRow {
                    kind: "toggle"
                    title: qsTr("V-Sync")
                    description: qsTr("Disabling V-Sync allows sub-frame rendering latency, but it can display visible tearing")
                    checked: StreamingPreferences.enableVsync
                    onToggled: function(checked) { StreamingPreferences.enableVsync = checked }
                }

                CouchSettingRow {
                    kind: "toggle"
                    title: qsTr("Frame pacing")
                    description: qsTr("Frame pacing reduces micro-stutter by delaying frames that come in too early")
                    enabled: StreamingPreferences.enableVsync
                    checked: StreamingPreferences.enableVsync && StreamingPreferences.framePacing
                    onToggled: function(checked) { StreamingPreferences.framePacing = checked }
                }

                CouchSettingRow {
                    objectName: "vrr"
                    kind: "toggle"
                    title: qsTr("VRR")
                    description: enabled ? qsTr("VRR uses adaptive presentation in borderless fullscreen. Choose your display's full refresh rate, or a lower VRR option for more headroom or lower latency.")
                                         : qsTr("VRR requires V-Sync. Enable V-Sync to change this setting.")
                    enabled: StreamingPreferences.enableVsync
                    checked: StreamingPreferences.enableVrr
                    onToggled: function(checked) { StreamingPreferences.enableVrr = checked }
                }

                CouchSettingRow {
                    objectName: "vrrPreset"
                    kind: "choice"
                    visible: StreamingPreferences.enableVrr
                    enabled: vrrActive
                    title: qsTr("VRR timing")
                    description: qsTr("Presets fill in the four values below. Larger buffers and higher targets favor steadier timing over lower delay. The target is a goal, not a guarantee. History controls how much recent timing is considered. Actual delay may be below the allowance.") + " " +
                                 qsTr("Reconnect the stream after changing these settings.")
                    // Custom describes the current values; choosing it changes nothing
                    options: [
                        { text: qsTr("Low Latency"), value: 0 },
                        { text: qsTr("Balanced"), value: 1 },
                        { text: qsTr("Smooth"), value: 2 },
                        { text: qsTr("Custom"), value: 3 }
                    ]
                    value: vrrPresetIndex
                    onPicked: function(value) {
                        if (value < 3) StreamingPreferences.applyVrrPreset([2, 1, 0][value])
                    }
                }

                CouchSettingRow {
                    objectName: "vrrBuffer"
                    kind: "stepper"
                    visible: StreamingPreferences.enableVrr
                    enabled: vrrActive
                    title: qsTr("Buffer allowance (source frames)")
                    value: StreamingPreferences.vrrBufferPerMille
                    from: 250
                    to: 4000
                    stepSize: 250
                    valueText: decimal(value / 1000, 2)
                    inputHint: qsTr("0.25 to 4")
                    fromInput: function(text) { return Math.round(parseDecimal(text) * 1000) }
                    onStepped: function(value) { StreamingPreferences.vrrBufferPerMille = value }
                }

                CouchSettingRow {
                    objectName: "vrrTarget"
                    kind: "stepper"
                    visible: StreamingPreferences.enableVrr
                    enabled: vrrActive
                    title: qsTr("Timing target (%)")
                    value: StreamingPreferences.vrrTargetHundredths
                    from: 9000
                    to: 9999
                    stepSize: 50
                    valueText: decimal(value / 100, 2) + " %"
                    inputText: decimal(value / 100, 2)
                    inputHint: qsTr("90 to 99.99")
                    fromInput: function(text) { return Math.round(parseDecimal(text) * 100) }
                    onStepped: function(value) { StreamingPreferences.vrrTargetHundredths = value }
                }

                CouchSettingRow {
                    objectName: "vrrHistory"
                    kind: "stepper"
                    visible: StreamingPreferences.enableVrr
                    enabled: vrrActive
                    title: qsTr("History window (seconds)")
                    value: StreamingPreferences.vrrHistorySeconds
                    from: 10
                    to: 300
                    stepSize: 10
                    valueText: qsTr("%1 s").arg(value)
                    inputText: "" + value
                    inputHint: qsTr("10 to 300")
                    fromInput: function(text) { return parseInt(text) }
                    onStepped: function(value) { StreamingPreferences.vrrHistorySeconds = value }
                }

                CouchSettingRow {
                    objectName: "vrrTolerance"
                    kind: "stepper"
                    visible: StreamingPreferences.enableVrr
                    enabled: vrrActive
                    title: qsTr("Frame interval tolerance (ms)")
                    description: qsTr("Tolerance is the interval variation allowed before timing counts as a miss. A larger tolerance can reduce buffering, but accepts more uneven timing.")
                    value: StreamingPreferences.vrrToleranceUs
                    from: 250
                    to: 2000
                    stepSize: 250
                    valueText: decimal(value / 1000, 2)
                    onStepped: function(value) { StreamingPreferences.vrrToleranceUs = value }
                }

                CouchSettingRow {
                    kind: "toggle"
                    visible: StreamingPreferences.enableVrr
                    enabled: vrrActive
                    title: qsTr("Reduce judder")
                    description: qsTr("Leaves source frame-time variation within your tolerance unchanged. Corrects only the excess, with a total timing adjustment of at most one tolerance. Absorb microstutter allows more smoothing and delay. Does not blend images or eliminate game stalls.") + " " +
                                 qsTr("Reconnect the stream after changing this setting.")
                    checked: StreamingPreferences.smoothVrrFrameTiming
                    onToggled: function(checked) { StreamingPreferences.smoothVrrFrameTiming = checked }
                }

                CouchSettingRow {
                    kind: "toggle"
                    visible: StreamingPreferences.enableVrr
                    enabled: vrrActive && StreamingPreferences.smoothVrrFrameTiming
                    title: qsTr("Absorb microstutter (adds latency)")
                    description: qsTr("Lets Reduce judder even out short frame-time spikes from the game or host. Keeps a small reserve and allows more delay while frame times are uneven. Requires Reduce judder. Large gaps remain visible.") + " " +
                                 qsTr("Reconnect the stream after changing this setting.")
                    checked: StreamingPreferences.absorbVrrMicrostutter
                    onToggled: function(checked) { StreamingPreferences.absorbVrrMicrostutter = checked }
                }

                CouchSettingRow {
                    kind: "toggle"
                    visible: Qt.platform.os === "linux"
                    title: qsTr("High-performance GPU power while streaming")
                    description: qsTr("Holds an AMD GPU at its high-performance clocks for the whole stream so it cannot drop its clocks between frames, which can delay when the display shows a frame that was ready on time. Uses more power and reduces battery life. Has no effect if GPU clocks are already set manually.") + " " +
                                 qsTr("Takes effect at the start of the next stream.")
                    checked: StreamingPreferences.highPerformanceGpuPower
                    onToggled: function(checked) { StreamingPreferences.highPerformanceGpuPower = checked }
                }
            }

            CouchSettingsSection {
                id: audioSection
                title: qsTr("Audio")
                anchors.fill: parent
                visible: currentSection === audioSection

                CouchSettingRow {
                    kind: "choice"
                    title: qsTr("Audio configuration")
                    options: [
                        { text: qsTr("Stereo"), value: StreamingPreferences.AC_STEREO },
                        { text: qsTr("5.1 surround sound"), value: StreamingPreferences.AC_51_SURROUND },
                        { text: qsTr("7.1 surround sound"), value: StreamingPreferences.AC_71_SURROUND }
                    ]
                    value: StreamingPreferences.audioConfig
                    onPicked: function(value) { StreamingPreferences.audioConfig = value }
                }

                CouchSettingRow {
                    kind: "toggle"
                    title: qsTr("Mute host PC speakers while streaming")
                    description: qsTr("You must restart any game currently in progress for this setting to take effect")
                    checked: !StreamingPreferences.playAudioOnHost
                    onToggled: function(checked) { StreamingPreferences.playAudioOnHost = !checked }
                }

                CouchSettingRow {
                    kind: "toggle"
                    visible: SystemProperties.hasDesktopEnvironment
                    title: qsTr("Mute audio stream when Moonlight is not the active window")
                    description: qsTr("Mutes Moonlight's audio when you Alt+Tab out of the stream or click on a different window.")
                    checked: StreamingPreferences.muteOnFocusLoss
                    onToggled: function(checked) { StreamingPreferences.muteOnFocusLoss = checked }
                }
            }

            CouchSettingsSection {
                id: inputSection
                title: qsTr("Mouse & keyboard")
                anchors.fill: parent
                visible: currentSection === inputSection

                CouchSettingRow {
                    kind: "toggle"
                    title: qsTr("Optimize mouse for remote desktop instead of games")
                    description: qsTr("This enables seamless mouse control without capturing the client's mouse cursor. It is ideal for remote desktop usage but will not work in most games.") + " " +
                                 qsTr("You can toggle this while streaming using Ctrl+Alt+Shift+M.")
                    checked: StreamingPreferences.absoluteMouseMode
                    onToggled: function(checked) { StreamingPreferences.absoluteMouseMode = checked }
                }

                CouchSettingRow {
                    kind: "choice"
                    visible: SystemProperties.hasDesktopEnvironment
                    title: qsTr("Capture system keyboard shortcuts")
                    description: qsTr("This enables the capture of system-wide keyboard shortcuts like Alt+Tab that would normally be handled by the client OS while streaming.") + " " +
                                 qsTr("NOTE: Certain keyboard shortcuts like Ctrl+Alt+Del on Windows cannot be intercepted by any application, including Moonlight.")
                    options: [
                        { text: qsTr("Off"), value: StreamingPreferences.CSK_OFF },
                        { text: qsTr("In fullscreen"), value: StreamingPreferences.CSK_FULLSCREEN },
                        { text: qsTr("Always"), value: StreamingPreferences.CSK_ALWAYS }
                    ]
                    value: StreamingPreferences.captureSysKeysMode
                    onPicked: function(value) { StreamingPreferences.captureSysKeysMode = value }
                }

                CouchSettingRow {
                    kind: "toggle"
                    title: qsTr("Use touchscreen as a virtual trackpad")
                    description: qsTr("When checked, the touchscreen acts like a trackpad. When unchecked, the touchscreen will directly control the mouse pointer.")
                    checked: !StreamingPreferences.absoluteTouchMode
                    onToggled: function(checked) { StreamingPreferences.absoluteTouchMode = !checked }
                }

                CouchSettingRow {
                    kind: "toggle"
                    title: qsTr("Swap left and right mouse buttons")
                    checked: StreamingPreferences.swapMouseButtons
                    onToggled: function(checked) { StreamingPreferences.swapMouseButtons = checked }
                }

                CouchSettingRow {
                    kind: "toggle"
                    title: qsTr("Reverse mouse scrolling direction")
                    checked: StreamingPreferences.reverseScrollDirection
                    onToggled: function(checked) { StreamingPreferences.reverseScrollDirection = checked }
                }
            }

            CouchSettingsSection {
                id: controllerSection
                title: qsTr("Controllers")
                anchors.fill: parent
                visible: currentSection === controllerSection

                CouchSettingRow {
                    kind: "toggle"
                    title: qsTr("Swap A/B and X/Y gamepad buttons")
                    description: qsTr("This switches gamepads into a Nintendo-style button layout")
                    checked: StreamingPreferences.swapFaceButtons
                    onToggled: function(checked) { StreamingPreferences.swapFaceButtons = checked }
                }

                CouchSettingRow {
                    kind: "toggle"
                    title: qsTr("Use the controller-first couch interface")
                    description: qsTr("Shows hosts and games in a full-screen layout built for gamepads and handhelds like the Steam Deck. Takes effect after restarting Moonlight.")
                    checked: StreamingPreferences.couchUi
                    onToggled: function(checked) { StreamingPreferences.couchUi = checked }
                }

                CouchSettingRow {
                    kind: "toggle"
                    title: qsTr("Force gamepad #1 always connected")
                    description: qsTr("Forces a single gamepad to always stay connected to the host, even if no gamepads are actually connected to this PC.") + " " +
                                 qsTr("Only enable this option when streaming a game that doesn't support gamepads being connected after startup.")
                    checked: !StreamingPreferences.multiController
                    onToggled: function(checked) { StreamingPreferences.multiController = !checked }
                }

                CouchSettingRow {
                    kind: "toggle"
                    title: qsTr("Enable mouse control with gamepads by holding the 'Start' button")
                    checked: StreamingPreferences.gamepadMouse
                    onToggled: function(checked) { StreamingPreferences.gamepadMouse = checked }
                }

                CouchSettingRow {
                    kind: "toggle"
                    visible: SystemProperties.hasDesktopEnvironment
                    title: qsTr("Process gamepad input when Moonlight is in the background")
                    description: qsTr("Allows Moonlight to capture gamepad inputs even if it's not the current window in focus")
                    checked: StreamingPreferences.backgroundGamepad
                    onToggled: function(checked) { StreamingPreferences.backgroundGamepad = checked }
                }
            }

            CouchSettingsSection {
                id: steamControllerSection
                title: qsTr("Steam Controller")
                anchors.fill: parent
                visible: currentSection === steamControllerSection

                CouchSettingRow {
                    kind: "toggle"
                    title: qsTr("Drive a USB or puck-connected Steam Controller (2026) directly")
                    description: qsTr("Announces a Steam Controller (2026) on a USB cable or the wireless puck to the host as a Steam Controller with both trackpads, gyro, grip sensors, battery and Steam haptics, and relays its firmware attributes.") + " " +
                                 qsTr("A client PC running Steam owns the controller first; close Steam or stop Steam Input for it.")
                    checked: StreamingPreferences.steamControllerDriver
                    onToggled: function(checked) { StreamingPreferences.steamControllerDriver = checked }
                }

                CouchSettingRow {
                    kind: "note"
                    warning: true
                    visible: StreamingPreferences.steamControllerDriver
                    description: qsTr("NEVER start a controller firmware update from Steam while streaming. The update would target the virtual controller on the host, not the real controller; it cannot succeed and may leave Steam confused. Update firmware with the controller connected directly to a PC running Steam.")
                }

                CouchSettingRow {
                    kind: "toggle"
                    enabled: StreamingPreferences.steamControllerDriver
                    title: qsTr("Gyro and accelerometer")
                    description: qsTr("Asks the firmware for the raw IMU and advertises motion to the host; the host decides when it wants the reports.")
                    checked: StreamingPreferences.steamControllerMotion
                    onToggled: function(checked) { StreamingPreferences.steamControllerMotion = checked }
                }

                CouchSettingRow {
                    kind: "toggle"
                    enabled: StreamingPreferences.steamControllerDriver
                    title: qsTr("Trackpads as DualShock touchpad halves")
                    description: qsTr("Sends the left pad as finger 0 in the left half and the right pad as finger 1 in the right half of one touchpad, which a DualShock 4 emulation splits back.") + " " +
                                 qsTr("Turn it off only for a host that understands two touchpads.")
                    checked: StreamingPreferences.steamControllerSplitPads
                    onToggled: function(checked) { StreamingPreferences.steamControllerSplitPads = checked }
                }

                CouchSettingRow {
                    kind: "choice"
                    enabled: StreamingPreferences.steamControllerDriver
                    title: qsTr("Grip buttons")
                    options: [
                        { text: qsTr("Paddles 1-4 (Xbox Elite style)"), value: StreamingPreferences.SCG_PADDLES },
                        { text: qsTr("DualShock extras (Share, touchpad click, L3, R3)"), value: StreamingPreferences.SCG_DS4 },
                        { text: qsTr("Off"), value: StreamingPreferences.SCG_OFF }
                    ]
                    value: StreamingPreferences.steamControllerGrips
                    onPicked: function(value) { StreamingPreferences.steamControllerGrips = value }
                }

                CouchSettingRow {
                    kind: "choice"
                    enabled: StreamingPreferences.steamControllerDriver
                    title: qsTr("Hold host rumble for")
                    description: qsTr("A rumble from the host is refreshed on the controller every 40 ms until this time passes, then the motors stop; choose Unlimited only when the host reliably sends a stop.")
                    options: [
                        { text: qsTr("250 ms"), value: 250 },
                        { text: qsTr("500 ms (default)"), value: 500 },
                        { text: qsTr("1 second"), value: 1000 },
                        { text: qsTr("2 seconds"), value: 2000 },
                        { text: qsTr("Unlimited (the host sends the stop)"), value: 0 }
                    ]
                    value: StreamingPreferences.steamControllerRumbleHold
                    onPicked: function(value) { StreamingPreferences.steamControllerRumbleHold = value }
                }

                CouchSettingRow {
                    kind: "toggle"
                    enabled: StreamingPreferences.steamControllerDriver
                    title: qsTr("Stretch the sticks to the rim")
                    description: qsTr("Divides each stick axis by the largest deflection seen this session and clamps to the unit circle. Off by default: Steam's own calibration expects the controller's native range.")
                    checked: StreamingPreferences.steamControllerStickStretch
                    onToggled: function(checked) { StreamingPreferences.steamControllerStickStretch = checked }
                }

                CouchSettingRow {
                    kind: "choice"
                    enabled: StreamingPreferences.steamControllerDriver
                    title: qsTr("Bluetooth LE: pad click boost")
                    description: qsTr("Bluetooth LE only: added to the gain of Steam's trackpad tick and click commands, clamped to the firmware's +6 dB ceiling. USB and puck links are not affected.")
                    options: [
                        { text: qsTr("Off (as Steam sends it)"), value: 0 },
                        { text: qsTr("+6 dB"), value: 6 },
                        { text: qsTr("+12 dB"), value: 12 },
                        { text: qsTr("+20 dB (everything at the ceiling)"), value: 20 }
                    ]
                    value: StreamingPreferences.steamControllerHapticBoost
                    onPicked: function(value) { StreamingPreferences.steamControllerHapticBoost = value }
                }

                CouchSettingRow {
                    kind: "choice"
                    enabled: StreamingPreferences.steamControllerDriver
                    title: qsTr("Bluetooth LE: pad slide pulse length")
                    description: qsTr("Bluetooth LE only: Steam's slide texture is 400 us pulses with no gain field, so this lengthens their on-time instead. Stops are untouched.")
                    options: [
                        { text: qsTr("100% (as Steam sends it)"), value: 100 },
                        { text: qsTr("150%"), value: 150 },
                        { text: qsTr("200%"), value: 200 },
                        { text: qsTr("300%"), value: 300 }
                    ]
                    value: StreamingPreferences.steamControllerHapticPulseScale
                    onPicked: function(value) { StreamingPreferences.steamControllerHapticPulseScale = value }
                }

                CouchSettingRow {
                    kind: "choice"
                    enabled: StreamingPreferences.steamControllerDriver
                    title: qsTr("Bluetooth LE: haptic master gain")
                    description: qsTr("Bluetooth LE only: written as the firmware's haptic master gain setting (76) with the link's own settings and cleared at stream end. Steam never writes it; if the firmware honours it, everything gets stronger and the two knobs above are unnecessary.")
                    options: [
                        { text: qsTr("Off (not written)"), value: 0 },
                        { text: qsTr("+6 dB"), value: 6 },
                        { text: qsTr("+12 dB"), value: 12 }
                    ]
                    value: StreamingPreferences.steamControllerHapticMasterGain
                    onPicked: function(value) { StreamingPreferences.steamControllerHapticMasterGain = value }
                }
            }

            CouchSettingsSection {
                id: hostSection
                title: qsTr("Host")
                anchors.fill: parent
                visible: currentSection === hostSection

                CouchSettingRow {
                    kind: "toggle"
                    title: qsTr("Optimize game settings for streaming")
                    checked: StreamingPreferences.gameOptimizations
                    onToggled: function(checked) { StreamingPreferences.gameOptimizations = checked }
                }

                CouchSettingRow {
                    kind: "toggle"
                    title: qsTr("Quit app on host PC after ending stream")
                    description: qsTr("This will close the app or game you are streaming when you end your stream. You will lose any unsaved progress!")
                    checked: StreamingPreferences.quitAppAfter
                    onToggled: function(checked) { StreamingPreferences.quitAppAfter = checked }
                }
            }

            CouchSettingsSection {
                id: interfaceSection
                title: qsTr("Interface")
                anchors.fill: parent
                visible: currentSection === interfaceSection

                CouchSettingRow {
                    kind: "choice"
                    title: qsTr("Language")
                    options: [
                        { text: qsTr("Automatic"), value: StreamingPreferences.LANG_AUTO },
                        { text: "Deutsch", value: StreamingPreferences.LANG_DE }, // German
                        { text: "English", value: StreamingPreferences.LANG_EN },
                        { text: "Français", value: StreamingPreferences.LANG_FR }, // French
                        { text: "简体中文", value: StreamingPreferences.LANG_ZH_CN }, // Simplified Chinese
                        { text: "Norwegian Bokmål", value: StreamingPreferences.LANG_NB_NO },
                        { text: "русский", value: StreamingPreferences.LANG_RU }, // Russian
                        { text: "Español", value: StreamingPreferences.LANG_ES }, // Spanish
                        { text: "日本語", value: StreamingPreferences.LANG_JA }, // Japanese
                        { text: "Tiếng Việt", value: StreamingPreferences.LANG_VI }, // Vietnamese
                        { text: "ภาษาไทย", value: StreamingPreferences.LANG_TH }, // Thai
                        { text: "한국어", value: StreamingPreferences.LANG_KO }, // Korean
                        { text: "Magyar", value: StreamingPreferences.LANG_HU }, // Hungarian
                        { text: "Nederlands", value: StreamingPreferences.LANG_NL }, // Dutch
                        { text: "Svenska", value: StreamingPreferences.LANG_SV }, // Swedish
                        { text: "Türkçe", value: StreamingPreferences.LANG_TR }, // Turkish
                        { text: "繁體中文", value: StreamingPreferences.LANG_ZH_TW }, // Traditional Chinese
                        { text: "Português", value: StreamingPreferences.LANG_PT }, // Portuguese
                        { text: "Português do Brasil", value: StreamingPreferences.LANG_PT_BR }, // Brazilian Portuguese
                        { text: "Ελληνικά", value: StreamingPreferences.LANG_EL }, // Greek
                        { text: "Italiano", value: StreamingPreferences.LANG_IT }, // Italian
                        { text: "Język polski", value: StreamingPreferences.LANG_PL }, // Polish
                        { text: "Čeština", value: StreamingPreferences.LANG_CS }, // Czech
                        { text: "Български", value: StreamingPreferences.LANG_BG }, // Bulgarian
                        { text: "தமிழ்", value: StreamingPreferences.LANG_TA } // Tamil
                    ]
                    value: StreamingPreferences.language
                    onPicked: function(value) { setLanguage(value) }
                }

                CouchSettingRow {
                    kind: "choice"
                    // Gaming Mode always shows Moonlight fullscreen
                    visible: SystemProperties.hasDesktopEnvironment && !SystemProperties.isGamescopeSession
                    title: qsTr("GUI display mode")
                    options: [
                        { text: qsTr("Windowed"), value: StreamingPreferences.UI_WINDOWED },
                        { text: qsTr("Maximized"), value: StreamingPreferences.UI_MAXIMIZED },
                        { text: qsTr("Fullscreen"), value: StreamingPreferences.UI_FULLSCREEN }
                    ]
                    value: StreamingPreferences.uiDisplayMode
                    onPicked: function(value) { StreamingPreferences.uiDisplayMode = value }
                }

                CouchSettingRow {
                    kind: "toggle"
                    title: qsTr("Show connection quality warnings")
                    checked: StreamingPreferences.connectionWarnings
                    onToggled: function(checked) { StreamingPreferences.connectionWarnings = checked }
                }

                CouchSettingRow {
                    kind: "toggle"
                    title: qsTr("Hide VRR buffer limit warnings")
                    checked: StreamingPreferences.hideVrrBufferWarnings
                    onToggled: function(checked) { StreamingPreferences.hideVrrBufferWarnings = checked }
                }

                CouchSettingRow {
                    kind: "toggle"
                    title: qsTr("Show configuration warnings")
                    checked: StreamingPreferences.configurationWarnings
                    onToggled: function(checked) { StreamingPreferences.configurationWarnings = checked }
                }

                CouchSettingRow {
                    kind: "toggle"
                    visible: SystemProperties.hasDiscordIntegration
                    title: qsTr("Discord Rich Presence integration")
                    description: qsTr("Updates your Discord status to display the name of the game you're streaming.")
                    checked: StreamingPreferences.richPresence
                    onToggled: function(checked) { StreamingPreferences.richPresence = checked }
                }

                CouchSettingRow {
                    kind: "toggle"
                    title: qsTr("Keep the display awake while streaming")
                    description: qsTr("Prevents the screensaver from starting or the display from going to sleep while streaming.")
                    checked: StreamingPreferences.keepAwake
                    onToggled: function(checked) { StreamingPreferences.keepAwake = checked }
                }

                CouchSettingRow {
                    kind: "toggle"
                    title: qsTr("Notify me about prerelease and nightly updates")
                    description: qsTr("Enabled by default. Turn off to receive only stable update notifications. Updates are never installed automatically.")
                    checked: AutoUpdateChecker.notifyPrereleases
                    onToggled: function(checked) { AutoUpdateChecker.notifyPrereleases = checked }
                }

                CouchSettingRow {
                    kind: "button"
                    visible: SystemProperties.hasBrowser
                    title: qsTr("Join our community on Discord")
                    onActivated: Qt.openUrlExternally("https://moonlight-stream.org/discord")
                }

                CouchSettingRow {
                    kind: "note"
                    description: qsTr("Version %1").arg(SystemProperties.versionString)
                }
            }

            CouchSettingsSection {
                id: advancedSection
                title: qsTr("Advanced")
                anchors.fill: parent
                visible: currentSection === advancedSection

                CouchSettingRow {
                    kind: "choice"
                    title: qsTr("Video decoder")
                    options: [
                        { text: qsTr("Automatic (Recommended)"), value: StreamingPreferences.VDS_AUTO },
                        { text: qsTr("Force software decoding"), value: StreamingPreferences.VDS_FORCE_SOFTWARE },
                        { text: qsTr("Force hardware decoding"), value: StreamingPreferences.VDS_FORCE_HARDWARE }
                    ]
                    value: StreamingPreferences.videoDecoderSelection
                    onPicked: function(value) { StreamingPreferences.videoDecoderSelection = value }
                }

                CouchSettingRow {
                    kind: "choice"
                    visible: SystemProperties.isDarwin
                    title: qsTr("Renderer")
                    options: [
                        { text: qsTr("Automatic (Recommended)"), value: StreamingPreferences.RS_AUTO },
                        { text: "Vulkan", value: StreamingPreferences.RS_VULKAN },
                        { text: "Metal", value: StreamingPreferences.RS_METAL },
                        { text: "AVSampleBufferDisplayLayer", value: StreamingPreferences.RS_AVSBDL }
                    ]
                    value: StreamingPreferences.rendererSelection
                    onPicked: function(value) { StreamingPreferences.rendererSelection = value }
                }

                CouchSettingRow {
                    kind: "toggle"
                    title: qsTr("Unlock bitrate limit (Experimental)")
                    description: qsTr("This unlocks extremely high video bitrates for use with Sunshine hosts. It should only be used when streaming over an Ethernet LAN connection.")
                    checked: StreamingPreferences.unlockBitrate
                    onToggled: function(checked) {
                        StreamingPreferences.unlockBitrate = checked
                        StreamingPreferences.bitrateKbps = Math.min(StreamingPreferences.bitrateKbps, bitrateMax)
                    }
                }

                CouchSettingRow {
                    kind: "toggle"
                    title: qsTr("Automatically find PCs on the local network (Recommended)")
                    checked: StreamingPreferences.enableMdns
                    onToggled: function(checked) { setMdns(checked) }
                }

                CouchSettingRow {
                    kind: "toggle"
                    title: qsTr("Automatically detect blocked connections (Recommended)")
                    checked: StreamingPreferences.detectNetworkBlocking
                    onToggled: function(checked) { StreamingPreferences.detectNetworkBlocking = checked }
                }

                CouchSettingRow {
                    kind: "toggle"
                    title: qsTr("Show performance stats while streaming")
                    description: qsTr("Display real-time stream performance information while streaming.") + " " +
                                 qsTr("You can toggle it at any time while streaming using Ctrl+Alt+Shift+S or Select+L1+R1+X.")
                    checked: StreamingPreferences.showPerformanceOverlay
                    onToggled: function(checked) { StreamingPreferences.showPerformanceOverlay = checked }
                }

                CouchSettingRow {
                    kind: "toggle"
                    title: qsTr("Show frametime graph while streaming")
                    description: qsTr("Shows planned, submitted and displayed frame intervals in separate lanes during VRR streaming, so you can see where a stutter starts. Variation under 1 ms is drawn flat.") + " " +
                                 qsTr("You can toggle it at any time while streaming using Ctrl+Alt+Shift+F or Select+L1+R1+Y (Triangle).")
                    checked: StreamingPreferences.showFrametimeGraph
                    onToggled: function(checked) { StreamingPreferences.showFrametimeGraph = checked }
                }
            }

            CouchSettingsSection {
                id: diagnosticsSection
                title: qsTr("VRR diagnostics")
                anchors.fill: parent
                visible: currentSection === diagnosticsSection

                CouchSettingRow {
                    kind: "toggle"
                    title: qsTr("Trace VRR frames for debugging")
                    description: qsTr("Saves frame traces and session logs to the vrr-diagnostics folder on your Desktop, with a separate folder for each stream. Does not change your VRR timing settings.") + " " +
                                 qsTr("Enable VRR and reconnect the stream to start recording. Tracing can use substantial disk space and add diagnostic overhead. Uncheck this after debugging.")
                    checked: StreamingPreferences.traceVrrFrames
                    onToggled: function(checked) { StreamingPreferences.traceVrrFrames = checked }
                }

                CouchSettingRow {
                    kind: "button"
                    enabled: !StreamingPreferences.exportingDiagnostics
                    title: StreamingPreferences.exportingDiagnostics ? qsTr("Exporting...") : qsTr("Export latest recording (ZIP)")
                    description: qsTr("Disconnect before exporting. Logs contain hardware and connection details; review them before sharing. Nothing is uploaded automatically.")
                    onActivated: StreamingPreferences.exportLatestDiagnostics()
                }

                CouchSettingRow {
                    kind: "button"
                    title: qsTr("Open diagnostics folder")
                    onActivated: StreamingPreferences.openDiagnosticsFolder()
                }

                CouchSettingRow {
                    kind: "note"
                    visible: description !== ""
                    description: StreamingPreferences.diagnosticsStatus
                }
            }
        }
    }

    function optionIndexOf(options, value) {
        for (var i = 0; i < options.length; i++) {
            if (options[i].value === value) return i
        }
        return -1
    }

    // What each button does right now
    Item {
        id: hintBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: CouchTheme.px(60)

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: CouchTheme.px(40)
            anchors.rightMargin: CouchTheme.px(40)
            height: 1
            color: CouchTheme.surfaceRaised
        }

        Row {
            anchors.left: parent.left
            anchors.leftMargin: CouchTheme.px(40)
            anchors.verticalCenter: parent.verticalCenter
            spacing: CouchTheme.px(28)

            CouchHint {
                readonly property Item row: zone === "rows" && activeRow && activeRow.activeFocus ? activeRow : null
                visible: text !== ""
                button: CouchTheme.confirmButton
                text: {
                    if (!row) return zone === "sections" ? qsTr("Open") : ""
                    if (!row.enabled) return ""
                    switch (row.kind) {
                    case "toggle": return row.checked ? qsTr("Turn off") : qsTr("Turn on")
                    case "choice": return qsTr("Choose")
                    case "stepper": return row.fromInput ? qsTr("Enter value") : ""
                    case "button": return qsTr("Select")
                    }
                    return ""
                }
                onActivated: {
                    if (row) row.activate()
                    else focusRows()
                }
            }

            CouchHint {
                readonly property Item row: zone === "rows" && activeRow && activeRow.activeFocus ? activeRow : null
                visible: row !== null && row.steps && row.enabled
                button: "dpad"
                text: qsTr("Change")
            }

            CouchHint {
                button: "LB"
                text: qsTr("Section")
                onActivated: selectSection(sectionIndex + 1 < sections.length ? sectionIndex + 1 : 0)
            }
        }

        Row {
            anchors.right: parent.right
            anchors.rightMargin: CouchTheme.px(40)
            anchors.verticalCenter: parent.verticalCenter

            CouchHint {
                button: CouchTheme.backButton
                text: qsTr("Back")
                onActivated: goBack()
            }
        }
    }

    Rectangle {
        id: toast
        property alias text: toastLabel.text
        property bool shown: false

        anchors.horizontalCenter: parent.horizontalCenter
        y: topBar.height + CouchTheme.px(8)
        width: toastLabel.implicitWidth + CouchTheme.px(40)
        height: CouchTheme.px(44)
        radius: height / 2
        color: CouchTheme.surfaceRaised
        opacity: shown ? 1 : 0
        visible: opacity > 0

        Behavior on opacity {
            NumberAnimation { duration: CouchTheme.normal }
        }

        Text {
            id: toastLabel
            anchors.centerIn: parent
            color: CouchTheme.text
            font.pixelSize: CouchTheme.px(16)
        }

        Timer {
            id: toastTimer
            interval: 3000
            onTriggered: toast.shown = false
        }
    }

    CouchActionSheet {
        id: sheet
        objectName: "couchSettingsSheet"
        onClosed: Qt.callLater(restoreFocus)
    }

    CouchTextPrompt {
        id: prompt
        objectName: "couchSettingsPrompt"
        onClosed: Qt.callLater(restoreFocus)
    }

    Loader {
        id: calibrationLoader
        active: false
        sourceComponent: Component {
            PyroWaveCalibrationDialog {
                onClosed: Qt.callLater(restoreFocus)
            }
        }
    }
}
