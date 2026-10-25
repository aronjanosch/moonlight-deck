import QtQuick 2.9
import QtQuick.Controls 2.2

import ComputerModel 1.0
import ComputerManager 1.0
import StreamingPreferences 1.0
import SdlGamepadKeyNavigation 1.0
import "."

// The controller-first home screen: hosts as tabs along the top
// (LB/RB), the selected host's games as a shelf of covers, and a hint
// bar naming what each button does. Hosts that are offline or not yet
// paired show their next step in place of the shelf.
FocusScope {
    id: home
    objectName: qsTr("Moonlight")

    property ComputerModel computerModel: createComputerModel()
    property int hostIndex: 0
    property bool userPickedHost: false
    // Which row has focus: "hosts" (the tabs) or "content" (shelf or panel)
    property string zone: "content"
    property bool showHidden: false

    property var appModel: null
    property string appModelUuid: ""
    property bool appModelShowsHidden: false
    property var lastAppIndex: ({})

    property string pairingUuid: ""
    property string pairingPin: ""
    // Which of the panel's buttons is selected, when it shows two
    property int panelChoice: 0
    // Runs after the text prompt has closed, to ask the next question
    property var nextPrompt: null
    property bool networkTestPending: false

    property int hostsRevision: 0
    readonly property int hostCount: hostRepeater.count
    readonly property bool addSelected: hostIndex >= hostCount
    readonly property var host: {
        hostsRevision
        return addSelected ? null : hostRepeater.itemAt(hostIndex)
    }

    readonly property string mode: {
        if (hostCount === 0) return "empty"
        if (addSelected || !host) return "add"
        if (host.statusUnknown) return "unknown"
        if (!host.online) return "offline"
        if (!host.serverSupported) return "unsupported"
        if (!host.paired) {
            return pairingUuid !== "" && pairingUuid === computerModel.uuidAt(hostIndex) ? "pairing" : "unpaired"
        }
        return "apps"
    }

    readonly property string appModelKey: (mode === "apps" ? hostIndex + "#" + host.hostName : "") + "|" + showHidden
    readonly property var game: mode === "apps" ? shelf.currentItem : null

    readonly property int coverHeight: CouchTheme.px(380)
    readonly property int coverWidth: Math.round(coverHeight * 0.7)

    Binding {
        target: CouchTheme
        property: "s"
        value: Math.max(0.6, Math.min(home.width / 1280, home.height / 800))
    }

    onAppModelKeyChanged: Qt.callLater(syncAppModel)
    onModeChanged: {
        panelChoice = 0
        Qt.callLater(restoreFocus)
    }
    onHostIndexChanged: panelChoice = 0
    onHostCountChanged: {
        if (hostIndex > hostCount) {
            hostIndex = Math.max(0, hostCount - 1)
        }
        Qt.callLater(autoSelectHost)
    }

    StackView.onActivated: {
        toolBar.visible = false
        ComputerManager.computerAddCompleted.connect(addComplete)
        restoreFocus()
    }

    StackView.onDeactivating: {
        toolBar.visible = true
        ComputerManager.computerAddCompleted.disconnect(addComplete)
    }

    function createComputerModel() {
        var model = Qt.createQmlObject('import ComputerModel 1.0; ComputerModel {}', home, '')
        model.initialize(ComputerManager)
        model.pairingCompleted.connect(pairingComplete)
        model.connectionTestCompleted.connect(connectionTestComplete)
        return model
    }

    // Recreate the app model when the selected host changes or becomes
    // ready, so the shelf always shows the selected host's games.
    function syncAppModel() {
        var wanted = mode === "apps" ? computerModel.uuidAt(hostIndex) : ""
        if (wanted === appModelUuid && showHidden === appModelShowsHidden) {
            return
        }

        if (appModel) {
            lastAppIndex[appModelUuid] = shelf.currentIndex
            var old = appModel
            appModel = null
            old.destroy()
        }

        appModelUuid = wanted
        appModelShowsHidden = showHidden

        if (wanted !== "") {
            var model = Qt.createQmlObject('import AppModel 1.0; AppModel {}', home, '')
            model.initialize(ComputerManager, hostIndex, showHidden)
            model.hostSleepCompleted.connect(hostSleepCompleted)
            appModel = model
            shelf.currentIndex = Math.max(0, Math.min(lastAppIndex[wanted] || 0, shelf.count - 1))
            shelf.positionViewAtIndex(shelf.currentIndex, ListView.Beginning)
        }

        restoreFocus()
    }

    // Until the user picks a host, jump to the first one ready to stream
    function autoSelectHost() {
        if (userPickedHost) {
            return
        }
        for (var i = 0; i < hostCount; i++) {
            var item = hostRepeater.itemAt(i)
            if (item && item.online && item.paired) {
                hostIndex = i
                return
            }
        }
    }

    function selectHost(index) {
        if (index < 0 || index > hostCount || hostCount === 0) {
            return
        }
        userPickedHost = true
        hostIndex = index
    }

    function focusHosts() {
        zone = "hosts"
        restoreFocus()
    }

    function focusContent() {
        zone = "content"
        restoreFocus()
    }

    function restoreFocus() {
        if (sheet.visible || prompt.visible || stackView.currentItem !== home) {
            return
        }
        if (zone === "hosts" && hostCount > 0) {
            hostRow.forceActiveFocus()
        }
        else if (mode === "apps" && shelf.count > 0) {
            shelf.forceActiveFocus()
        }
        else {
            panel.forceActiveFocus()
        }
    }

    function showToast(text) {
        toast.text = text
        toast.shown = true
        toastTimer.restart()
    }

    function showMessage(title, text) {
        sheet.present(title, text, [{ text: qsTr("OK") }])
    }

    // ---- Hosts ----

    function promptAddHost() {
        prompt.ask(qsTr("Add a host"), "", qsTr("IP address or hostname"), function(address) {
            ComputerManager.addNewHostManually(address)
            showToast(qsTr("Looking for %1…").arg(address))
        })
    }

    function addComplete(success, detectedPortBlocking) {
        if (success) {
            showToast(qsTr("Host added"))
        }
        else if (detectedPortBlocking) {
            showMessage(qsTr("Couldn't add the host"),
                        qsTr("Unable to connect to the specified PC.") + "\n\n" +
                        qsTr("This PC's Internet connection is blocking Moonlight. Streaming over the Internet may not work while connected to this network."))
        }
        else {
            showMessage(qsTr("Couldn't add the host"),
                        qsTr("Unable to connect to the specified PC. Check the address and that Sunshine or Apollo is running on it."))
        }
    }

    function startPairing() {
        var pin = computerModel.generatePinString()
        pairingUuid = computerModel.uuidAt(hostIndex)
        pairingPin = pin
        computerModel.pairComputer(hostIndex, pin)
    }

    // Apollo and Vibepollo hosts can create a one-time PIN with a
    // passphrase in their web interface, so nothing has to be typed there
    function startOtpPairing() {
        var index = hostIndex
        var uuid = computerModel.uuidAt(index)
        var name = host.hostName
        prompt.ask(qsTr("One-time PIN for %1").arg(name), "", qsTr("4-digit PIN from the host's web interface"), function(pin) {
            askNext(function() {
                prompt.ask(qsTr("Passphrase for %1").arg(name), "", qsTr("Passphrase entered with the PIN"), function(passphrase) {
                    if (computerModel.uuidAt(index) !== uuid) {
                        return
                    }
                    var error = computerModel.pairComputerWithOtp(index, pin, passphrase)
                    if (error !== "") {
                        showMessage(qsTr("Pairing failed"), error)
                        return
                    }
                    pairingUuid = uuid
                    pairingPin = ""
                }, { secret: true })
            })
        }, { digits: true })
    }

    // Asks another question once the prompt that's closing is gone
    function askNext(fn) {
        if (prompt.visible) {
            nextPrompt = fn
        }
        else {
            fn()
        }
    }

    function pairingComplete(error) {
        pairingUuid = ""
        pairingPin = ""
        if (error !== undefined) {
            showMessage(qsTr("Pairing failed"), error)
        }
        else {
            showToast(qsTr("Paired"))
        }
    }

    function wakeHost(index, name) {
        computerModel.wakeComputer(index)
        showToast(qsTr("Sent a wake-up signal to %1").arg(name))
    }

    function testNetwork(index) {
        networkTestPending = true
        computerModel.testConnectionForComputer(index)
        sheet.present(qsTr("Testing the network"),
                      qsTr("Moonlight is testing your network connection to determine if any required ports are blocked.") + "\n\n" +
                      qsTr("This may take a few seconds…"),
                      [{ text: qsTr("Close") }])
    }

    function connectionTestComplete(result, blockedPorts) {
        if (!networkTestPending) {
            return
        }
        networkTestPending = false

        var text
        if (result === -1) {
            text = qsTr("The network test could not be performed because none of Moonlight's connection testing servers were reachable from this PC. Check your Internet connection or try again later.")
        }
        else if (result === 0) {
            text = qsTr("This network does not appear to be blocking Moonlight. If you still have trouble connecting, check your PC's firewall settings.")
        }
        else {
            text = qsTr("Your PC's current network connection seems to be blocking Moonlight. Streaming over the Internet may not work while connected to this network.") +
                   "\n\n" + qsTr("The following network ports were blocked:") + "\n" + blockedPorts
        }
        showMessage(qsTr("Network test"), text)
    }

    function hostStatusText(item) {
        if (!item) return ""
        if (item.statusUnknown) return qsTr("Checking…")
        if (!item.online) return qsTr("Offline")
        if (!item.paired) return qsTr("Not paired")
        if (item.busy) return qsTr("Online · in a game")
        return qsTr("Online")
    }

    function generalActions() {
        return [
            { text: qsTr("Add a host"), run: promptAddHost },
            { text: qsTr("Settings"), run: function() { settingsButton.clicked() } },
            { text: qsTr("Switch to the classic interface"), run: switchToClassic },
            { text: qsTr("Quit Moonlight"), run: function() { Qt.quit() } }
        ]
    }

    function openHostSheet() {
        if (!host) {
            sheet.present(qsTr("Moonlight"), "", generalActions())
            return
        }

        var index = hostIndex
        var item = host
        var name = item.hostName
        var actions = []

        if (!item.online && item.wakeable) {
            actions.push({ text: qsTr("Wake PC"), run: function() { wakeHost(index, name) } })
        }
        if (item.online && item.paired) {
            actions.push({ text: qsTr("Show hidden games"), checked: showHidden,
                           run: function() { showHidden = !showHidden } })
        }
        // Apollo and Vibepollo can create a display just for this stream
        if (item.online && item.paired && item.virtualDisplayCapable) {
            var requested = item.virtualDisplayRequested
            actions.push({ text: item.virtualDisplayReady ? qsTr("Stream from a virtual display")
                                                          : qsTr("Stream from a virtual display (host driver not ready)"),
                           checked: requested,
                           run: function() {
                               computerModel.setVirtualDisplayRequested(index, !requested)
                               showToast(!requested ? qsTr("Games on %1 will start on a virtual display").arg(name)
                                                    : qsTr("Games on %1 will start on the host's display").arg(name))
                           } })
        }
        if (mode === "unpaired" && item.otpPairingSupported) {
            actions.push({ text: qsTr("Pair with one-time PIN"), run: startOtpPairing })
        }
        actions.push({ text: qsTr("Test network"), run: function() { testNetwork(index) } })
        actions.push({ text: qsTr("Rename"), run: function() {
            prompt.ask(qsTr("Rename %1").arg(name), name, "", function(newName) {
                computerModel.renameComputer(index, newName)
            })
        } })
        actions.push({ text: qsTr("Remove"), run: function() {
            sheet.present(qsTr("Remove %1?").arg(name),
                          qsTr("You will need to pair with it again to stream from it."), [
                { text: qsTr("Remove"), run: function() {
                    userPickedHost = true
                    computerModel.deleteComputer(index)
                    hostIndex = Math.max(0, Math.min(index, hostCount - 1))
                } },
                { text: qsTr("Cancel") }
            ])
        } })
        actions.push({ text: qsTr("Details"), run: function() { showMessage(name, item.details) } })

        sheet.present(name, hostStatusText(item), actions.concat(generalActions()))
    }

    function switchToClassic() {
        StreamingPreferences.couchUi = false
        StreamingPreferences.save()
        stackView.replace(home, "qrc:/gui/PcView.qml")
    }

    function confirmQuitMoonlight() {
        sheet.present(qsTr("Quit Moonlight?"), "", [
            { text: qsTr("Quit"), run: function() { Qt.quit() } },
            { text: qsTr("Cancel") }
        ])
    }

    // The main action for a host that can't show games yet
    function panelAction() {
        switch (mode) {
        case "empty":
        case "add":
            promptAddHost()
            break
        case "offline":
            if (host.wakeable) {
                wakeHost(hostIndex, host.hostName)
            }
            else {
                testNetwork(hostIndex)
            }
            break
        case "unsupported":
            showMessage(host.hostName, host.details)
            break
        case "unpaired":
            if (panelChoice === 1 && host.otpPairingSupported) {
                startOtpPairing()
            }
            else {
                startPairing()
            }
            break
        case "apps":
            openHostSheet()
            break
        }
    }

    // ---- Games ----

    function activateGame() {
        var item = shelf.currentItem
        if (!item || !appModel) {
            return
        }

        var index = shelf.currentIndex
        var name = item.name
        var appId = item.appId

        if (item.sleepAction) {
            confirmHostSleep()
            return
        }

        var runningId = appModel.getRunningAppId()
        if (runningId !== 0 && runningId !== appId) {
            var runningName = appModel.getRunningAppName()
            sheet.present(qsTr("%1 is still running").arg(runningName),
                          qsTr("Quit it to start %1? Any unsaved progress will be lost.").arg(name), [
                { text: qsTr("Quit and start %1").arg(name), run: function() { quitRunningGame(index, name) } },
                { text: qsTr("Cancel") }
            ])
            return
        }

        var component = Qt.createComponent("qrc:/gui/StreamSegue.qml")
        var segue = component.createObject(stackView, {
                                               "appName": name,
                                               "session": appModel.createSessionForApp(index),
                                               "isResume": runningId === appId
                                           })
        stackView.push(segue)
    }

    // Quits the running game, then starts the game at nextIndex if given
    function quitRunningGame(nextIndex, nextName) {
        var model = appModel
        var params = {
            "appName": model.getRunningAppName(),
            "quitRunningAppFn": function() { model.quitRunningApp() },
            "nextAppName": nextIndex >= 0 ? nextName : null,
            "nextSession": nextIndex >= 0 ? model.createSessionForApp(nextIndex) : null
        }
        var component = Qt.createComponent("qrc:/gui/QuitSegue.qml")
        stackView.push(component.createObject(stackView, params))
    }

    function confirmQuitGame() {
        var name = appModel.getRunningAppName()
        sheet.present(qsTr("Quit %1?").arg(name), qsTr("Any unsaved progress will be lost."), [
            { text: qsTr("Quit game"), run: function() { quitRunningGame(-1, "") } },
            { text: qsTr("Cancel") }
        ])
    }

    function confirmHostSleep() {
        var model = appModel
        sheet.present(qsTr("Put PC to Sleep"),
                      qsTr("Put this host PC to sleep? All host applications and streaming sessions must be closed first. You will need a way to wake the PC again."), [
            { text: qsTr("Sleep"), run: function() { model.requestHostSleep() } },
            { text: qsTr("Cancel") }
        ])
    }

    function hostSleepCompleted(error) {
        if (error.length) {
            showMessage(qsTr("Host Sleep"), error)
        }
        else {
            showToast(qsTr("The host accepted the sleep request"))
        }
    }

    function openGameSheet() {
        var item = shelf.currentItem
        if (!item) {
            openHostSheet()
            return
        }
        if (item.sleepAction) {
            confirmHostSleep()
            return
        }

        var index = shelf.currentIndex
        var hidden = item.hidden
        var actions = [
            { text: item.running ? qsTr("Resume") : qsTr("Play"), run: activateGame }
        ]
        if (item.running) {
            actions.push({ text: qsTr("Quit game"), run: confirmQuitGame })
        }
        if (hidden || (!item.running && !item.directLaunch)) {
            actions.push({ text: qsTr("Hide game"), checked: hidden,
                           run: function() { appModel.setAppHidden(index, !hidden) } })
        }
        actions.push({ text: qsTr("Show hidden games"), checked: showHidden,
                       run: function() { showHidden = !showHidden } })
        actions.push({ text: qsTr("Host options"), run: openHostSheet })

        sheet.present(item.name, host ? host.hostName : "", actions)
    }

    // ---- Buttons that work everywhere on this screen ----

    Keys.onPressed: {
        if (event.key === Qt.Key_PageUp) {
            selectHost(hostIndex - 1)
            event.accepted = true
        }
        else if (event.key === Qt.Key_PageDown) {
            selectHost(hostIndex + 1)
            event.accepted = true
        }
        else if (event.key === Qt.Key_Context1) {
            openHostSheet()
            event.accepted = true
        }
    }
    Keys.onEscapePressed: confirmQuitMoonlight()
    Keys.onBackPressed: confirmQuitMoonlight()

    // ---- Layout ----

    CouchBackdrop {
        anchors.fill: parent
        source: game && !game.isPlaceholder ? game.boxart : ""
    }

    // Host tabs
    Item {
        id: topBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: CouchTheme.px(80)

        FocusScope {
            id: hostRow
            anchors.left: parent.left
            anchors.leftMargin: CouchTheme.px(40)
            anchors.right: clock.left
            anchors.rightMargin: CouchTheme.px(24)
            anchors.verticalCenter: parent.verticalCenter
            height: CouchTheme.px(44)
            clip: true

            Keys.onLeftPressed: selectHost(hostIndex - 1)
            Keys.onRightPressed: selectHost(hostIndex + 1)
            Keys.onDownPressed: focusContent()
            Keys.onReturnPressed: {
                focusContent()
                if (mode === "add") {
                    promptAddHost()
                }
            }
            Keys.onEnterPressed: focusContent()
            Keys.onMenuPressed: openHostSheet()

            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: CouchTheme.px(8)

                CouchGlyph {
                    button: "LB"
                    anchors.verticalCenter: parent.verticalCenter
                    visible: hostCount > 0
                    opacity: 0.6
                }

                Repeater {
                    id: hostRepeater
                    model: computerModel

                    onItemAdded: hostsRevision++
                    onItemRemoved: hostsRevision++

                    delegate: Rectangle {
                        readonly property string hostName: model.name
                        readonly property bool online: model.online
                        readonly property bool paired: model.paired
                        readonly property bool busy: model.busy
                        readonly property bool wakeable: model.wakeable
                        readonly property bool statusUnknown: model.statusUnknown
                        readonly property bool serverSupported: model.serverSupported
                        readonly property string details: model.details
                        readonly property bool otpPairingSupported: model.otpPairingSupported
                        readonly property bool virtualDisplayCapable: model.virtualDisplayCapable
                        readonly property bool virtualDisplayReady: model.virtualDisplayReady
                        readonly property bool virtualDisplayRequested: model.virtualDisplayRequested
                        readonly property bool current: index === hostIndex
                        readonly property bool lit: current && zone === "hosts" && hostRow.activeFocus

                        onOnlineChanged: Qt.callLater(autoSelectHost)
                        onPairedChanged: Qt.callLater(autoSelectHost)

                        anchors.verticalCenter: parent.verticalCenter
                        width: tabRow.implicitWidth + CouchTheme.px(36)
                        height: CouchTheme.px(44)
                        radius: height / 2
                        color: lit ? CouchTheme.accent : (current ? CouchTheme.surfaceRaised : "transparent")

                        Behavior on color {
                            ColorAnimation { duration: CouchTheme.fast }
                        }

                        Row {
                            id: tabRow
                            anchors.centerIn: parent
                            spacing: CouchTheme.px(10)

                            Rectangle {
                                id: statusDot
                                anchors.verticalCenter: parent.verticalCenter
                                width: CouchTheme.px(10)
                                height: width
                                radius: width / 2
                                color: statusUnknown ? CouchTheme.textFaint :
                                       !online ? CouchTheme.offline :
                                       !paired ? CouchTheme.attention : CouchTheme.online

                                SequentialAnimation on opacity {
                                    running: statusUnknown
                                    loops: Animation.Infinite
                                    NumberAnimation { to: 0.2; duration: 600 }
                                    NumberAnimation { to: 1.0; duration: 600 }
                                    onRunningChanged: if (!running) statusDot.opacity = 1
                                }
                            }

                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: hostName
                                color: lit ? CouchTheme.accentText : (current ? CouchTheme.text : CouchTheme.textDim)
                                font.pixelSize: CouchTheme.px(18)
                                font.bold: current
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                selectHost(index)
                                focusContent()
                            }
                        }
                    }
                }

                // The tab after the last host adds a new one
                Rectangle {
                    readonly property bool current: addSelected && hostCount > 0
                    readonly property bool lit: current && zone === "hosts" && hostRow.activeFocus

                    visible: hostCount > 0
                    anchors.verticalCenter: parent.verticalCenter
                    width: height
                    height: CouchTheme.px(44)
                    radius: height / 2
                    color: lit ? CouchTheme.accent : (current ? CouchTheme.surfaceRaised : "transparent")
                    border.color: current ? "transparent" : CouchTheme.surfaceRaised
                    border.width: CouchTheme.px(2)

                    Text {
                        anchors.centerIn: parent
                        text: "+"
                        color: parent.lit ? CouchTheme.accentText : CouchTheme.textDim
                        font.pixelSize: CouchTheme.px(24)
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            selectHost(hostCount)
                            focusContent()
                        }
                    }
                }

                CouchGlyph {
                    button: "RB"
                    anchors.verticalCenter: parent.verticalCenter
                    visible: hostCount > 0
                    opacity: 0.6
                }
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

    // Title and status of the selected game
    Column {
        id: hero
        visible: mode === "apps" && shelf.count > 0
        anchors.left: parent.left
        anchors.leftMargin: CouchTheme.px(56)
        anchors.right: parent.right
        anchors.rightMargin: CouchTheme.px(56)
        anchors.bottom: shelf.top
        anchors.bottomMargin: CouchTheme.px(8)
        spacing: CouchTheme.px(10)

        Row {
            spacing: CouchTheme.px(8)

            CouchBadge {
                visible: game !== null && game.running
                text: qsTr("RUNNING")
                dot: "" + CouchTheme.online
            }

            CouchBadge {
                visible: game !== null && game.hidden
                text: qsTr("HIDDEN")
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: host ? host.hostName + "  ·  " + qsTr("%1 of %2").arg(shelf.currentIndex + 1).arg(shelf.count) : ""
                color: CouchTheme.textDim
                font.pixelSize: CouchTheme.px(15)
            }
        }

        Text {
            width: parent.width
            text: game ? game.name : ""
            color: CouchTheme.text
            font.pixelSize: CouchTheme.px(48)
            font.bold: true
            elide: Text.ElideRight
        }
    }

    ListView {
        id: shelf
        objectName: "couchShelf"
        visible: mode === "apps"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: hintBar.top
        anchors.bottomMargin: CouchTheme.px(16)
        height: coverHeight + CouchTheme.px(36)

        orientation: ListView.Horizontal
        spacing: CouchTheme.px(6)
        model: appModel
        highlightRangeMode: ListView.StrictlyEnforceRange
        preferredHighlightBegin: CouchTheme.px(56)
        preferredHighlightEnd: CouchTheme.px(56) + coverWidth
        highlightMoveDuration: CouchTheme.normal
        cacheBuffer: coverWidth * 8

        onCountChanged: Qt.callLater(restoreFocus)

        delegate: CouchCover {
            readonly property int appId: model.appid
            readonly property bool directLaunch: model.directLaunch

            y: CouchTheme.px(18)
            width: coverWidth
            height: coverHeight
            name: model.name
            boxart: model.boxart
            running: model.running
            hidden: model.hidden
            sleepAction: model.sleepAction
            appCollectorGame: model.appCollectorGame
            selected: ListView.isCurrentItem
            lit: ListView.isCurrentItem && shelf.activeFocus

            onTapped: {
                if (lit) {
                    activateGame()
                }
                else {
                    shelf.currentIndex = index
                    focusContent()
                }
            }
        }

        Keys.onUpPressed: focusHosts()
        Keys.onReturnPressed: activateGame()
        Keys.onEnterPressed: activateGame()
        Keys.onMenuPressed: openGameSheet()
    }

    // The next step for a host without a game shelf
    FocusScope {
        id: panel
        visible: mode !== "apps" || shelf.count === 0
        anchors.left: parent.left
        anchors.leftMargin: CouchTheme.px(56)
        anchors.right: parent.right
        anchors.rightMargin: CouchTheme.px(56)
        anchors.verticalCenter: parent.verticalCenter

        height: panelColumn.implicitHeight

        Keys.onUpPressed: focusHosts()
        Keys.onLeftPressed: panelChoice = 0
        Keys.onRightPressed: if (panelSecondButton.visible) panelChoice = 1
        Keys.onReturnPressed: panelAction()
        Keys.onEnterPressed: panelAction()
        Keys.onMenuPressed: openHostSheet()

        Column {
            id: panelColumn
            width: Math.min(parent.width, CouchTheme.px(760))
            spacing: CouchTheme.px(16)

            Text {
                width: parent.width
                color: CouchTheme.text
                font.pixelSize: CouchTheme.px(40)
                font.bold: true
                wrapMode: Text.Wrap
                text: {
                    switch (mode) {
                    case "empty": return StreamingPreferences.enableMdns ? qsTr("Looking for hosts…") : qsTr("No hosts yet")
                    case "add": return qsTr("Add a host")
                    case "unknown": return qsTr("Connecting to %1…").arg(host.hostName)
                    case "offline": return qsTr("%1 is offline").arg(host.hostName)
                    case "unsupported": return qsTr("%1 needs a different Moonlight").arg(host.hostName)
                    case "unpaired": return qsTr("Pair with %1").arg(host.hostName)
                    case "pairing": return pairingPin !== "" ? qsTr("Enter this PIN on %1").arg(host.hostName)
                                                             : qsTr("Pairing with %1…").arg(host.hostName)
                    case "apps": return qsTr("No games on %1").arg(host.hostName)
                    }
                    return ""
                }
            }

            Text {
                width: parent.width
                color: CouchTheme.textDim
                font.pixelSize: CouchTheme.px(18)
                lineHeight: 1.25
                wrapMode: Text.Wrap
                text: {
                    switch (mode) {
                    case "empty":
                        return StreamingPreferences.enableMdns
                                ? qsTr("Hosts running Sunshine or Apollo on your network show up here automatically. You can also add one by its address.")
                                : qsTr("Automatic PC discovery is disabled. Add your PC manually.")
                    case "add":
                        return qsTr("Enter the IP address or hostname of a PC running Sunshine or Apollo.")
                    case "unknown":
                        return qsTr("Checking whether the host is reachable.")
                    case "offline":
                        return host.wakeable
                                ? qsTr("Wake it over the network, or make sure it's on and Sunshine or Apollo is running.")
                                : qsTr("Make sure it's on and Sunshine or Apollo is running. Wake-on-LAN becomes available after the host has been seen online once.")
                    case "unsupported":
                        return qsTr("The version of GeForce Experience on %1 is not supported by this build of Moonlight. You must update Moonlight to stream from %1.").arg(host.hostName)
                    case "unpaired":
                        return qsTr("Pairing lets this device stream from %1. You'll get a PIN to enter in the host's web interface.").arg(host.hostName) +
                               (host.otpPairingSupported ? " " + qsTr("Or create a one-time PIN with a passphrase in the host's web interface and enter both here.") : "")
                    case "pairing":
                        return pairingPin !== "" ? qsTr("Open the Sunshine or Apollo web interface on the host and enter the PIN there. This screen continues once pairing completes.")
                                                 : qsTr("Checking the one-time PIN with the host.")
                    case "apps":
                        return showHidden ? qsTr("This host doesn't list any applications.")
                                          : qsTr("This host doesn't list any applications, or they are all hidden.")
                    }
                    return ""
                }
            }

            // PIN digits while pairing
            Row {
                visible: mode === "pairing"
                spacing: CouchTheme.px(12)
                topPadding: CouchTheme.px(8)

                Repeater {
                    model: pairingPin.split("")
                    Rectangle {
                        width: CouchTheme.px(72)
                        height: CouchTheme.px(92)
                        radius: CouchTheme.px(12)
                        color: CouchTheme.surface
                        border.color: CouchTheme.accent
                        border.width: CouchTheme.px(2)

                        Text {
                            anchors.centerIn: parent
                            text: modelData
                            color: CouchTheme.text
                            font.pixelSize: CouchTheme.px(52)
                            font.bold: true
                        }
                    }
                }
            }

            // Actions, also tappable. Left and right pick one when there are two.
            Row {
                spacing: CouchTheme.px(16)

                CouchPanelButton {
                    id: panelButton
                    label: {
                        switch (mode) {
                        case "empty":
                        case "add": return qsTr("Add a host")
                        case "offline": return host.wakeable ? qsTr("Wake PC") : qsTr("Test network")
                        case "unsupported": return qsTr("Details")
                        case "unpaired": return qsTr("Pair")
                        case "apps": return qsTr("Host options")
                        }
                        return ""
                    }
                    selected: panelChoice === 0
                    lit: panel.activeFocus && selected
                    onActivated: {
                        focusContent()
                        panelChoice = 0
                        panelAction()
                    }
                }

                CouchPanelButton {
                    id: panelSecondButton
                    label: mode === "unpaired" && host.otpPairingSupported ? qsTr("Pair with one-time PIN") : ""
                    onVisibleChanged: if (!visible) panelChoice = 0
                    selected: panelChoice === 1
                    lit: panel.activeFocus && selected
                    onActivated: {
                        focusContent()
                        panelChoice = 1
                        panelAction()
                    }
                }
            }
        }
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
                visible: text !== ""
                button: CouchTheme.confirmButton
                text: {
                    if (zone === "hosts" && hostCount > 0) return qsTr("Open")
                    if (mode === "apps" && game) return game.sleepAction ? qsTr("Sleep") : game.running ? qsTr("Resume") : qsTr("Play")
                    return panelChoice === 1 ? panelSecondButton.label : panelButton.label
                }
                onActivated: {
                    if (zone === "hosts" && hostCount > 0) focusContent()
                    else if (mode === "apps" && game) activateGame()
                    else panelAction()
                }
            }

            CouchHint {
                button: CouchTheme.optionsButton
                text: mode === "apps" && game && zone === "content" ? qsTr("Options") : qsTr("Host options")
                onActivated: {
                    if (mode === "apps" && game && zone === "content") openGameSheet()
                    else openHostSheet()
                }
            }

            CouchHint {
                visible: hostCount > 0
                button: "LB"
                text: qsTr("Switch host")
                onActivated: selectHost(hostIndex + 1 > hostCount ? 0 : hostIndex + 1)
            }
        }

        Row {
            anchors.right: parent.right
            anchors.rightMargin: CouchTheme.px(40)
            anchors.verticalCenter: parent.verticalCenter
            spacing: CouchTheme.px(28)

            CouchHint {
                button: "menu"
                text: qsTr("Settings")
                onActivated: settingsButton.clicked()
            }

            CouchHint {
                button: CouchTheme.backButton
                text: qsTr("Quit")
                onActivated: confirmQuitMoonlight()
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
        onClosed: Qt.callLater(restoreFocus)
    }

    CouchTextPrompt {
        id: prompt
        onClosed: {
            var next = nextPrompt
            nextPrompt = null
            if (next) {
                next()
            }
            else if (sheet.visible) {
                // A message such as a pairing error opened while closing
                sheet.refocus()
            }
            else {
                Qt.callLater(restoreFocus)
            }
        }
    }
}
