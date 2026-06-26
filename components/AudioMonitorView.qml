import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io as Io

// PulseAudio/PipeWire audio devices via pactl (sinks, sources, ports, defaults).
Item {
    id: root

    property string globalFilter: ""
    property bool active: false

    property color textColor: "#cdd6f4"
    property color subtextColor: "#a6adc8"
    property color accentColor: "#89b4fa"
    property color surfaceColor: "#313244"
    property color overlayColor: "#6c7086"
    property color okColor: "#a6e3a1"
    property color warnColor: "#f9e2af"
    property color errorColor: "#f38ba8"

    readonly property string pollerScript: "/home/crome/.config/quickshell/scripts/audio-poller.sh"
    readonly property string controlScript: "/home/crome/.config/quickshell/scripts/audio-control.sh"

    property var audioData: ({
        timestamp: 0,
        default_sink: "",
        default_source: "",
        sinks: [],
        sources: []
    })
    property string selectedSinkName: ""
    property string selectedSourceName: ""
    property bool loading: false
    property bool acting: false
    property string lastError: ""
    property string lastAction: ""
    property int dataVersion: 0

    property bool _loadHandled: false
    property bool _actionHandled: false
    property int _lastActionExitCode: 0

    readonly property int cardRadius: 6
    readonly property int cardMargin: 10
    readonly property int sectionSpacing: 8
    readonly property int deviceRowHeight: 58
    readonly property int summaryHeight: Math.max(68, Math.min(94, Math.round(height * 0.12)))

    function filterQuery() {
        return (globalFilter && globalFilter.trim()) ? globalFilter.toLowerCase().trim() : ""
    }

    function matchesSearch(dev) {
        const q = filterQuery()
        if (!q) return true
        const ports = (dev.ports || []).map(function(p) {
            return (p.name || "") + " " + (p.description || "") + " " + (p.type || "")
        }).join(" ")
        const hay = [
            dev.name, dev.description, dev.state, dev.active_port, ports
        ].join(" ").toLowerCase()
        return hay.indexOf(q) !== -1
    }

    function filteredSinks() {
        const tick = dataVersion + "|" + globalFilter + "|" + (audioData.sinks ? audioData.sinks.length : 0)
        const list = audioData.sinks || []
        const out = []
        for (let i = 0; i < list.length; i++) {
            if (matchesSearch(list[i])) out.push(list[i])
        }
        return out
    }

    function filteredSources() {
        const tick = dataVersion + "|" + globalFilter + "|" + (audioData.sources ? audioData.sources.length : 0)
        const list = audioData.sources || []
        const out = []
        for (let i = 0; i < list.length; i++) {
            if (matchesSearch(list[i])) out.push(list[i])
        }
        return out
    }

    function deviceLabel(dev) {
        if (!dev) return "--"
        return dev.description || dev.name || "--"
    }

    function defaultSinkDevice() {
        const name = audioData.default_sink || ""
        const sinks = audioData.sinks || []
        for (let i = 0; i < sinks.length; i++) {
            if (sinks[i].name === name) return sinks[i]
        }
        return null
    }

    function defaultSourceDevice() {
        const name = audioData.default_source || ""
        const sources = audioData.sources || []
        for (let i = 0; i < sources.length; i++) {
            if (sources[i].name === name) return sources[i]
        }
        return null
    }

    function activePortLabel(dev) {
        if (!dev || !dev.ports || !dev.ports.length) {
            return dev && dev.active_port ? dev.active_port : "--"
        }
        for (let i = 0; i < dev.ports.length; i++) {
            if (dev.ports[i].active) return dev.ports[i].description || dev.ports[i].name
        }
        return dev.active_port || "--"
    }

    function stateColor(state) {
        const s = (state || "").toLowerCase()
        if (s === "running" || s === "idle") return root.okColor
        if (s === "suspended") return root.warnColor
        return root.subtextColor
    }

    function volumeBarColor(pct, mute) {
        if (mute) return root.overlayColor
        const v = Number(pct) || 0
        if (v > 85) return root.errorColor
        if (v > 65) return root.warnColor
        return root.okColor
    }

    function refresh() {
        if (pollProcess.running) return
        loading = true
        lastError = ""
        _loadHandled = false
        pollProcess.running = false
        pollProcess.running = true
    }

    function runControl(action, target, name, port) {
        if (!name || acting || pollProcess.running) return
        acting = true
        lastAction = ""
        lastError = ""
        _actionHandled = false
        const cmd = port
            ? [root.controlScript, action, target, name, port]
            : [root.controlScript, action, target, name]
        actionProcess.running = false
        actionProcess.command = cmd
        actionProcess.running = true
    }

    function setDefaultSink(name) {
        runControl("set-default", "sink", name, "")
    }

    function setDefaultSource(name) {
        runControl("set-default", "source", name, "")
    }

    function setSinkPort(name, port) {
        runControl("set-port", "sink", name, port)
    }

    function setSourcePort(name, port) {
        runControl("set-port", "source", name, port)
    }

    function finishPoll() {
        if (_loadHandled) return
        _loadHandled = true
        loading = false
        const raw = (pollStdout.text || "").trim()
        if (!raw) {
            lastError = "Empty response from audio poller"
            return
        }
        try {
            const parsed = JSON.parse(raw)
            audioData = parsed
            dataVersion++
            const sinkNames = {}
            const sourceNames = {}
            const sinks = parsed.sinks || []
            const sources = parsed.sources || []
            for (let i = 0; i < sinks.length; i++) sinkNames[sinks[i].name] = true
            for (let i = 0; i < sources.length; i++) sourceNames[sources[i].name] = true
            if (selectedSinkName && !sinkNames[selectedSinkName]) selectedSinkName = ""
            if (selectedSourceName && !sourceNames[selectedSourceName]) selectedSourceName = ""
        } catch (e) {
            lastError = "Failed to parse audio JSON"
        }
    }

    function finishAction(exitCode) {
        if (_actionHandled) return
        _actionHandled = true
        acting = false
        const code = exitCode !== undefined ? exitCode : _lastActionExitCode
        if (code !== 0) {
            const err = (actionStderr.text || actionStdout.text || "").trim()
            lastError = err.length ? err : "Audio action failed (exit " + code + ")"
            return
        }
        lastAction = "Updated"
        Qt.callLater(function() { root.refresh() })
    }

    function resetScroll() {
        sinksFlickable.contentY = 0
        sourcesFlickable.contentY = 0
    }

    function focusScroll() {
        sinksFlickable.forceActiveFocus()
    }

    function pageScroll(direction) {
        const flick = sinksFlickable.activeFocus ? sinksFlickable : sourcesFlickable
        const maxY = Math.max(0, flick.contentHeight - flick.height)
        if (maxY <= 0) return
        const page = Math.max(80, flick.height * 0.85)
        flick.contentY = Math.max(0, Math.min(maxY, flick.contentY + direction * page))
    }

    function lineScroll(direction) {
        const flick = sinksFlickable.activeFocus ? sinksFlickable : sourcesFlickable
        const maxY = Math.max(0, flick.contentHeight - flick.height)
        if (maxY <= 0) return
        const step = Math.max(root.deviceRowHeight, 28)
        flick.contentY = Math.max(0, Math.min(maxY, flick.contentY + direction * step))
    }

    onActiveChanged: {
        if (active && !(audioData.sinks && audioData.sinks.length)) refresh()
    }

    Io.Process {
        id: pollProcess
        command: [root.pollerScript]
        running: false
        stdout: Io.StdioCollector {
            id: pollStdout
            onStreamFinished: root.finishPoll()
        }
        onExited: root.finishPoll()
    }

    Io.Process {
        id: actionProcess
        running: false
        stdout: Io.StdioCollector { id: actionStdout }
        stderr: Io.StdioCollector { id: actionStderr }
        onExited: (code) => {
            root._lastActionExitCode = code
            root.finishAction(code)
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: root.sectionSpacing

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: root.summaryHeight
            Layout.minimumHeight: 64
            radius: root.cardRadius
            color: root.surfaceColor
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.08)

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: root.cardMargin
                spacing: 4

                Text {
                    text: "AUDIO SUMMARY"
                    color: root.accentColor
                    font.pixelSize: 12
                    font.bold: true
                    font.family: "monospace"
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10

                    ColumnLayout {
                        spacing: 1
                        Text {
                            text: "Output: " + root.deviceLabel(root.defaultSinkDevice())
                            color: root.textColor
                            font.pixelSize: 11
                            font.family: "monospace"
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Text {
                            text: "Input: " + root.deviceLabel(root.defaultSourceDevice())
                            color: root.textColor
                            font.pixelSize: 11
                            font.family: "monospace"
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }

                    Item { Layout.fillWidth: true }

                    ColumnLayout {
                        spacing: 1
                        Text {
                            text: (audioData.sinks ? audioData.sinks.length : 0) + " sinks"
                            color: root.subtextColor
                            font.pixelSize: 11
                            font.family: "monospace"
                            horizontalAlignment: Text.AlignRight
                        }
                        Text {
                            text: (audioData.sources ? audioData.sources.length : 0) + " sources"
                            color: root.subtextColor
                            font.pixelSize: 11
                            font.family: "monospace"
                            horizontalAlignment: Text.AlignRight
                        }
                        Text {
                            text: root.loading ? "loading..." : (root.lastAction || "pactl")
                            color: root.overlayColor
                            font.pixelSize: 10
                            font.family: "monospace"
                            horizontalAlignment: Text.AlignRight
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: root.sectionSpacing

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: root.cardRadius
                color: root.surfaceColor
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.08)
                clip: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: root.cardMargin
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: "Output Devices"
                            color: root.accentColor
                            font.pixelSize: 11
                            font.bold: true
                            font.family: "monospace"
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: root.filteredSinks().length + " shown"
                            color: root.overlayColor
                            font.pixelSize: 10
                            font.family: "monospace"
                        }
                    }

                    Flickable {
                        id: sinksFlickable
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        contentWidth: width
                        contentHeight: sinksList.implicitHeight
                        focus: true

                        property int _tick: root.dataVersion

                        WheelHandler {
                            onWheel: function(event) {
                                const delta = event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x
                                if (delta === 0) return
                                const maxY = Math.max(0, sinksFlickable.contentHeight - sinksFlickable.height)
                                if (maxY > 0) {
                                    const ticks = delta / 120
                                    sinksFlickable.contentY = Math.max(0, Math.min(maxY, sinksFlickable.contentY - ticks * 28))
                                }
                                event.accepted = true
                            }
                        }

                        ScrollBar.vertical: ScrollBar {
                            policy: sinksFlickable.contentHeight > sinksFlickable.height + 1 ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                            contentItem: Rectangle {
                                implicitWidth: 6
                                radius: 3
                                color: parent.pressed ? root.accentColor : Qt.rgba(1, 1, 1, 0.2)
                            }
                        }

                        Column {
                            id: sinksList
                            width: parent.width
                            spacing: 6

                            Text {
                                width: parent.width
                                visible: root.loading && root.filteredSinks().length === 0
                                text: "Loading audio devices..."
                                color: root.overlayColor
                                font.pixelSize: 10
                                font.family: "monospace"
                            }

                            Text {
                                width: parent.width
                                visible: !root.loading && root.lastError.length > 0 && root.filteredSinks().length === 0
                                text: root.lastError
                                color: root.errorColor
                                font.pixelSize: 10
                                font.family: "monospace"
                                wrapMode: Text.Wrap
                            }

                            Repeater {
                                model: root.filteredSinks()
                                delegate: Rectangle {
                                    readonly property var dev: modelData

                                    width: parent.width
                                    height: root.deviceRowHeight
                                    radius: 4
                                    color: dev.name === root.selectedSinkName
                                        ? Qt.rgba(0.55, 0.70, 0.96, 0.14)
                                        : Qt.rgba(0, 0, 0, 0.12)
                                    border.width: 1
                                    border.color: dev.is_default
                                        ? Qt.rgba(0.65, 0.89, 0.63, 0.35)
                                        : Qt.rgba(1, 1, 1, 0.05)

                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: root.selectedSinkName = dev.name
                                    }

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 6
                                        spacing: 3

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 6

                                            Text {
                                                text: (dev.is_default ? "★ " : "") + (dev.description || dev.name)
                                                color: root.textColor
                                                font.pixelSize: 10
                                                font.bold: dev.is_default
                                                font.family: "monospace"
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }

                                            Text {
                                                text: dev.mute ? "MUTED" : (Number(dev.volume_pct || 0).toFixed(0) + "%")
                                                color: dev.mute ? root.warnColor : root.accentColor
                                                font.pixelSize: 10
                                                font.family: "monospace"
                                            }

                                            Rectangle {
                                                visible: !dev.is_default
                                                Layout.preferredWidth: 52
                                                Layout.preferredHeight: 18
                                                radius: 4
                                                color: defSinkMa.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                                                border.width: 1
                                                border.color: Qt.rgba(1, 1, 1, 0.1)
                                                opacity: root.acting ? 0.4 : 1

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "Default"
                                                    color: root.accentColor
                                                    font.pixelSize: 9
                                                    font.family: "monospace"
                                                }

                                                MouseArea {
                                                    id: defSinkMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    enabled: !root.acting && !root.loading
                                                    onClicked: root.setDefaultSink(dev.name)
                                                }
                                            }
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 6

                                            Rectangle {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 5
                                                radius: 3
                                                color: Qt.rgba(0, 0, 0, 0.25)

                                                Rectangle {
                                                    width: parent.width * Math.min(1, Number(dev.volume_pct || 0) / 100)
                                                    height: parent.height
                                                    radius: 3
                                                    color: root.volumeBarColor(dev.volume_pct, dev.mute)
                                                }
                                            }

                                            Text {
                                                text: dev.state || "--"
                                                color: root.stateColor(dev.state)
                                                font.pixelSize: 9
                                                font.family: "monospace"
                                            }
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 4
                                            visible: dev.ports && dev.ports.length > 0

                                            Text {
                                                text: "Port:"
                                                color: root.overlayColor
                                                font.pixelSize: 9
                                                font.family: "monospace"
                                            }

                                            Repeater {
                                                model: dev.ports || []
                                                delegate: Rectangle {
                                                    readonly property var port: modelData

                                                    Layout.preferredHeight: 16
                                                    Layout.preferredWidth: Math.min(120, portLabel.implicitWidth + 10)
                                                    radius: 3
                                                    color: port.active
                                                        ? Qt.rgba(0.55, 0.70, 0.96, 0.22)
                                                        : (portMa.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.03))
                                                    border.width: 1
                                                    border.color: port.active
                                                        ? Qt.rgba(0.55, 0.70, 0.96, 0.45)
                                                        : Qt.rgba(1, 1, 1, 0.08)
                                                    opacity: root.acting ? 0.45 : 1

                                                    Text {
                                                        id: portLabel
                                                        anchors.centerIn: parent
                                                        text: port.description || port.name
                                                        color: port.active ? root.textColor : root.subtextColor
                                                        font.pixelSize: 8
                                                        font.family: "monospace"
                                                        elide: Text.ElideRight
                                                    }

                                                    MouseArea {
                                                        id: portMa
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        enabled: !port.active && !root.acting && !root.loading
                                                        onClicked: root.setSinkPort(dev.name, port.name)
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

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: root.cardRadius
                color: root.surfaceColor
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.08)
                clip: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: root.cardMargin
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: "Input Devices"
                            color: root.accentColor
                            font.pixelSize: 11
                            font.bold: true
                            font.family: "monospace"
                        }
                        Item { Layout.fillWidth: true }
                        Text {
                            text: root.filteredSources().length + " shown"
                            color: root.overlayColor
                            font.pixelSize: 10
                            font.family: "monospace"
                        }
                    }

                    Flickable {
                        id: sourcesFlickable
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        contentWidth: width
                        contentHeight: sourcesList.implicitHeight

                        property int _tick: root.dataVersion

                        WheelHandler {
                            onWheel: function(event) {
                                const delta = event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x
                                if (delta === 0) return
                                const maxY = Math.max(0, sourcesFlickable.contentHeight - sourcesFlickable.height)
                                if (maxY > 0) {
                                    const ticks = delta / 120
                                    sourcesFlickable.contentY = Math.max(0, Math.min(maxY, sourcesFlickable.contentY - ticks * 28))
                                }
                                event.accepted = true
                            }
                        }

                        ScrollBar.vertical: ScrollBar {
                            policy: sourcesFlickable.contentHeight > sourcesFlickable.height + 1 ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                            contentItem: Rectangle {
                                implicitWidth: 6
                                radius: 3
                                color: parent.pressed ? root.accentColor : Qt.rgba(1, 1, 1, 0.2)
                            }
                        }

                        Column {
                            id: sourcesList
                            width: parent.width
                            spacing: 6

                            Text {
                                width: parent.width
                                visible: root.loading && root.filteredSources().length === 0
                                text: "Loading audio devices..."
                                color: root.overlayColor
                                font.pixelSize: 10
                                font.family: "monospace"
                            }

                            Repeater {
                                model: root.filteredSources()
                                delegate: Rectangle {
                                    readonly property var dev: modelData

                                    width: parent.width
                                    height: root.deviceRowHeight
                                    radius: 4
                                    color: dev.name === root.selectedSourceName
                                        ? Qt.rgba(0.55, 0.70, 0.96, 0.14)
                                        : Qt.rgba(0, 0, 0, 0.12)
                                    border.width: 1
                                    border.color: dev.is_default
                                        ? Qt.rgba(0.65, 0.89, 0.63, 0.35)
                                        : Qt.rgba(1, 1, 1, 0.05)

                                    MouseArea {
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        onClicked: root.selectedSourceName = dev.name
                                    }

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 6
                                        spacing: 3

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 6

                                            Text {
                                                text: (dev.is_default ? "★ " : "") + (dev.description || dev.name)
                                                color: root.textColor
                                                font.pixelSize: 10
                                                font.bold: dev.is_default
                                                font.family: "monospace"
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }

                                            Text {
                                                text: dev.mute ? "MUTED" : (Number(dev.volume_pct || 0).toFixed(0) + "%")
                                                color: dev.mute ? root.warnColor : root.accentColor
                                                font.pixelSize: 10
                                                font.family: "monospace"
                                            }

                                            Rectangle {
                                                visible: !dev.is_default
                                                Layout.preferredWidth: 52
                                                Layout.preferredHeight: 18
                                                radius: 4
                                                color: defSrcMa.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                                                border.width: 1
                                                border.color: Qt.rgba(1, 1, 1, 0.1)
                                                opacity: root.acting ? 0.4 : 1

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "Default"
                                                    color: root.accentColor
                                                    font.pixelSize: 9
                                                    font.family: "monospace"
                                                }

                                                MouseArea {
                                                    id: defSrcMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    enabled: !root.acting && !root.loading
                                                    onClicked: root.setDefaultSource(dev.name)
                                                }
                                            }
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 6

                                            Rectangle {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 5
                                                radius: 3
                                                color: Qt.rgba(0, 0, 0, 0.25)

                                                Rectangle {
                                                    width: parent.width * Math.min(1, Number(dev.volume_pct || 0) / 100)
                                                    height: parent.height
                                                    radius: 3
                                                    color: root.volumeBarColor(dev.volume_pct, dev.mute)
                                                }
                                            }

                                            Text {
                                                text: dev.state || "--"
                                                color: root.stateColor(dev.state)
                                                font.pixelSize: 9
                                                font.family: "monospace"
                                            }
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 4
                                            visible: dev.ports && dev.ports.length > 0

                                            Text {
                                                text: "Port:"
                                                color: root.overlayColor
                                                font.pixelSize: 9
                                                font.family: "monospace"
                                            }

                                            Repeater {
                                                model: dev.ports || []
                                                delegate: Rectangle {
                                                    readonly property var port: modelData

                                                    Layout.preferredHeight: 16
                                                    Layout.preferredWidth: Math.min(120, srcPortLabel.implicitWidth + 10)
                                                    radius: 3
                                                    color: port.active
                                                        ? Qt.rgba(0.55, 0.70, 0.96, 0.22)
                                                        : (srcPortMa.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.03))
                                                    border.width: 1
                                                    border.color: port.active
                                                        ? Qt.rgba(0.55, 0.70, 0.96, 0.45)
                                                        : Qt.rgba(1, 1, 1, 0.08)
                                                    opacity: root.acting ? 0.45 : 1

                                                    Text {
                                                        id: srcPortLabel
                                                        anchors.centerIn: parent
                                                        text: port.description || port.name
                                                        color: port.active ? root.textColor : root.subtextColor
                                                        font.pixelSize: 8
                                                        font.family: "monospace"
                                                        elide: Text.ElideRight
                                                    }

                                                    MouseArea {
                                                        id: srcPortMa
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        enabled: !port.active && !root.acting && !root.loading
                                                        onClicked: root.setSourcePort(dev.name, port.name)
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