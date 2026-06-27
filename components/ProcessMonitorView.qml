import Quickshell
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io as Io

// Processes tab — mirrors ServicesView architecture:
//   - Summary from live sysmon poll (load + process_stats)
//   - Full process list loaded on-demand via own poller (tab open + Refresh only)
Item {
    id: root

    required property var service

    property bool active: false
    property string globalFilter: ""

    property color textColor: "#cdd6f4"
    property color subtextColor: "#a6adc8"
    property color accentColor: "#89b4fa"
    property color surfaceColor: "#313244"
    property color overlayColor: "#6c7086"
    property color okColor: "#a6e3a1"
    property color warnColor: "#f9e2af"
    property color errorColor: "#f38ba8"

    readonly property string pollerScript: "/home/crome/.config/quickshell/scripts/run-process-poller.sh"
    readonly property string controlScript: "/home/crome/.config/quickshell/scripts/process-control.sh"

    readonly property int cardRadius: 6
    readonly property int cardMargin: 10
    readonly property int rowHeight: 22
    readonly property int headerHeight: 20
    readonly property int sectionSpacing: 8
    readonly property int tblSpacing: 4

    readonly property int colPidW: 44
    readonly property int colUserW: 52
    readonly property int colCpuW: 40
    readonly property int colMemW: 40
    readonly property int colTimeW: 54
    readonly property int colThreadsW: 30
    readonly property int colRssW: 42
    readonly property int colVszW: 40
    readonly property int colStartW: 50
    readonly property int colPriW: 28
    readonly property int colShrW: 38
    readonly property int colStatW: 32
    readonly property int colCmdMinW: 96

    property var processes: []
    property int dataVersion: 0
    property bool loading: false
    property string sortKey: "cpu"
    property bool highUsageOnly: false
    property var selectedPids: []
    property int selectionVersion: 0
    property int anchorIndex: -1
    property bool acting: false
    readonly property bool hasSelection: selectedPids.length > 0
    readonly property int selectedCount: selectedPids.length
    // Back-compat for status bar bindings
    readonly property int selectedPid: selectedPids.length === 1 ? selectedPids[0] : 0
    property string lastError: ""
    property string lastAction: ""
    property bool _loadHandled: false
    property bool _actionHandled: false
    property int _lastActionExitCode: 0
    property var _actionQueue: []
    property int _actionIndex: 0
    property string _pendingAction: ""
    property bool killConfirmVisible: false
    property int lastUpdatedMs: 0

    readonly property int summaryHeight: Math.max(68, Math.min(94, Math.round(height * 0.12)))

    function cloneProcessRow(p) {
        return {
            pid: p.pid,
            user: p.user || "",
            name: p.name || "",
            cmd: p.cmd || p.name || "",
            state: p.state || "",
            nice: p.nice,
            pri: p.pri,
            cpu: Number(p.cpu || 0),
            mem: Number(p.mem || 0),
            rss: p.rss,
            vsz: p.vsz,
            shr: p.shr,
            time: p.time || "",
            start: p.start || "",
            threads: p.threads
        }
    }

    function filterQuery() {
        return (globalFilter && globalFilter.trim()) ? globalFilter.toLowerCase().trim() : ""
    }

    function commandGroupKey(p) {
        const cmd = (p.cmd || p.name || "").toLowerCase().trim()
        if (!cmd) return ""
        let base = cmd.split(/\s+/)[0]
        const slash = base.lastIndexOf("/")
        if (slash >= 0) base = base.substring(slash + 1)
        return base
    }

    function filteredProcesses() {
        const tick = dataVersion + "|" + sortKey + "|" + (highUsageOnly ? "1" : "0") + "|" + globalFilter + "|" + processes.length
        void tick

        if (!processes || !processes.length) return []

        const q = filterQuery()
        const rows = []
        for (let i = 0; i < processes.length; i++) {
            const p = processes[i]
            if (!p) continue
            if (highUsageOnly && p.cpu < 1 && p.mem < 1)
                continue
            if (q) {
                const hay = [
                    String(p.pid || ""),
                    p.user, p.name, p.cmd,
                    formatState(p.state),
                    p.start || ""
                ].join(" ").toLowerCase()
                if (hay.indexOf(q) === -1)
                    continue
            }
            rows.push(p)
        }

        const metric = sortKey === "mem" ? "mem" : "cpu"
        rows.sort(function(a, b) {
            const ga = commandGroupKey(a)
            const gb = commandGroupKey(b)
            if (ga !== gb) return ga < gb ? -1 : 1
            return b[metric] - a[metric]
        })

        const out = []
        for (let j = 0; j < rows.length; j++) {
            const row = rows[j]
            out.push({
                pid: row.pid,
                user: row.user,
                name: row.name,
                cmd: row.cmd,
                state: row.state,
                nice: row.nice,
                pri: row.pri,
                cpu: row.cpu,
                mem: row.mem,
                rss: row.rss,
                vsz: row.vsz,
                shr: row.shr,
                time: row.time,
                start: row.start,
                threads: row.threads,
                groupStart: j === 0 || commandGroupKey(row) !== commandGroupKey(rows[j - 1])
            })
        }
        return out
    }

    function copyToClipboard(text) {
        if (!text) return
        Quickshell.execDetached([
            "sh", "-c",
            'printf "%s" "$1" | wl-copy',
            "wl-copy",
            text
        ])
        lastAction = "Copied to clipboard"
        Qt.callLater(function() {
            if (root.lastAction === "Copied to clipboard") root.lastAction = ""
        }, 1200)
    }

    function isPidSelected(pid) {
        const tick = selectionVersion
        void tick
        return selectedPids.indexOf(pid) !== -1
    }

    function setSelectedPids(pids) {
        const unique = []
        for (let i = 0; i < pids.length; i++) {
            const pid = pids[i]
            if (pid && unique.indexOf(pid) === -1)
                unique.push(pid)
        }
        selectedPids = unique
        selectionVersion++
    }

    function clearSelection() {
        selectedPids = []
        anchorIndex = -1
        selectionVersion++
    }

    function selectionLabel() {
        const n = selectedCount
        if (!n) return ""
        if (n === 1) return "PID " + selectedPids[0]
        return n + " selected"
    }

    function handleRowClick(pid, rowIndex, mouse) {
        const mods = mouse.modifiers || 0
        const ctrl = (mods & Qt.ControlModifier) || (mods & Qt.MetaModifier)
        const shift = mods & Qt.ShiftModifier
        const rows = filteredProcesses()

        if (shift && anchorIndex >= 0 && anchorIndex < rows.length) {
            const lo = Math.min(anchorIndex, rowIndex)
            const hi = Math.max(anchorIndex, rowIndex)
            const next = ctrl ? selectedPids.slice() : []
            for (let i = lo; i <= hi; i++)
                next.push(rows[i].pid)
            setSelectedPids(next)
        } else if (ctrl) {
            const next = selectedPids.slice()
            const pos = next.indexOf(pid)
            if (pos === -1) next.push(pid)
            else next.splice(pos, 1)
            setSelectedPids(next)
            anchorIndex = rowIndex
        } else {
            setSelectedPids([pid])
            anchorIndex = rowIndex
        }
    }

    function copySelectedPid() {
        if (!hasSelection) return
        if (selectedCount === 1)
            copyToClipboard(String(selectedPids[0]))
        else
            copyToClipboard(selectedPids.join("\n"))
    }

    function copySelectedCommand() {
        const procs = selectedProcesses()
        if (!procs.length) return
        const lines = []
        for (let i = 0; i < procs.length; i++)
            lines.push(procs[i].cmd || procs[i].name || "")
        copyToClipboard(lines.join("\n"))
    }

    function exportText() {
        const rows = filteredProcesses()
        if (!rows.length) return ""
        const lines = ["PID\tUser\tCPU%\tMem%\tTime\tStart\tThr\tRSS\tVSZ\tPR\tSHR\tCommand\tStat"]
        for (let i = 0; i < rows.length; i++) {
            const p = rows[i]
            lines.push([
                String(p.pid),
                p.user || "",
                p.cpu.toFixed(1),
                p.mem.toFixed(1),
                formatTime(p.time),
                formatStart(p.start),
                p.threads !== undefined ? String(p.threads) : "--",
                formatKiB(p.rss),
                formatKiB(p.vsz),
                p.pri !== undefined ? String(p.pri) : "--",
                formatKiB(p.shr),
                p.cmd || p.name || "",
                formatState(p.state)
            ].join("\t"))
        }
        return lines.join("\n")
    }

    function copyAll() {
        const text = exportText()
        if (text) copyToClipboard(text)
    }

    function fixedTableWidth() {
        return colPidW + colUserW + colCpuW + colMemW + colTimeW + colStartW
            + colThreadsW + colRssW + colVszW + colPriW + colShrW + colStatW
            + tblSpacing * 12 + 8
    }

    function tableContentWidth(viewportWidth) {
        return Math.max(viewportWidth, fixedTableWidth() + colCmdMinW)
    }

    function cmdColWidth(totalWidth) {
        return Math.max(colCmdMinW, totalWidth - fixedTableWidth())
    }

    function formatLoad(load) {
        if (!load || !load.length) return "-- / -- / --"
        const a = Number(load[0] || 0).toFixed(2)
        const b = load.length > 1 ? Number(load[1] || 0).toFixed(2) : "--"
        const c = load.length > 2 ? Number(load[2] || 0).toFixed(2) : "--"
        return a + " / " + b + " / " + c
    }

    function formatState(state) {
        if (!state) return "--"
        return String(state).charAt(0).toUpperCase()
    }

    function stateColor(state) {
        const s = formatState(state)
        if (s === "R") return root.accentColor
        if (s === "D") return root.errorColor
        if (s === "Z") return root.warnColor
        return root.subtextColor
    }

    function formatKiB(kb) {
        const v = Number(kb) || 0
        if (!v) return "--"
        if (v >= 1024) return (v / 1024).toFixed(1) + "M"
        return Math.round(v) + "K"
    }

    function formatTime(value) {
        if (!value) return "--"
        return String(value)
    }

    function formatStart(value) {
        if (!value) return "--"
        return String(value)
    }

    function formatLastUpdated() {
        if (!lastUpdatedMs) return "—"
        const d = new Date(lastUpdatedMs)
        return Qt.formatDateTime(d, "MMM d, hh:mm:ss")
    }

    function summaryStats() {
        const data = service && service.data ? service.data : {}
        const stats = data.process_stats || {}
        return {
            running: stats.running || 0,
            total: stats.total || 0,
            load: data.load || []
        }
    }

    function selectedProcesses() {
        const tick = selectionVersion
        void tick
        if (!hasSelection) return []
        const wanted = {}
        for (let i = 0; i < selectedPids.length; i++)
            wanted[selectedPids[i]] = true
        const out = []
        for (let j = 0; j < processes.length; j++) {
            const p = processes[j]
            if (p && wanted[p.pid])
                out.push(p)
        }
        return out
    }

    function pruneSelection() {
        if (!hasSelection) return
        const rows = filteredProcesses()
        const visible = {}
        for (let i = 0; i < rows.length; i++)
            visible[rows[i].pid] = true
        const next = []
        for (let j = 0; j < selectedPids.length; j++) {
            if (visible[selectedPids[j]])
                next.push(selectedPids[j])
        }
        if (next.length !== selectedPids.length)
            setSelectedPids(next)
        if (anchorIndex >= rows.length)
            anchorIndex = rows.length > 0 ? Math.min(anchorIndex, rows.length - 1) : -1
    }

    function refresh() {
        if (pollProcess.running || acting) return
        loading = true
        lastError = ""
        _loadHandled = false
        pollProcess.running = false
        pollProcess.running = true
    }

    function finishPoll() {
        if (_loadHandled) return
        _loadHandled = true
        loading = false

        const raw = (pollStdout.text || "").trim()
        if (!raw) {
            lastError = "Empty response from process poller"
            return
        }

        try {
            const parsed = JSON.parse(raw)
            const source = parsed.processes || []
            const copy = []
            for (let i = 0; i < source.length; i++) {
                if (source[i]) copy.push(cloneProcessRow(source[i]))
            }
            processes = copy
            dataVersion++
            lastUpdatedMs = parsed.timestamp ? Number(parsed.timestamp) : Date.now()
            pruneSelection()
            lastError = ""
        } catch (e) {
            lastError = "Failed to parse process JSON"
        }
    }

    function requestAction(action) {
        if (!hasSelection || acting || loading) return
        if (action === "kill" && selectedCount > 1) {
            killConfirmVisible = true
            return
        }
        startAction(action)
    }

    function confirmKill() {
        killConfirmVisible = false
        startAction("kill")
    }

    function cancelKill() {
        killConfirmVisible = false
    }

    function startAction(action) {
        if (!hasSelection || acting) return
        _pendingAction = action
        _actionQueue = selectedPids.slice()
        _actionIndex = 0
        acting = true
        lastAction = ""
        lastError = ""
        runNextAction()
    }

    function runNextAction() {
        if (_actionIndex >= _actionQueue.length) {
            finishAllActions()
            return
        }
        _actionHandled = false
        actionProcess.running = false
        actionProcess.command = [root.controlScript, _pendingAction, String(_actionQueue[_actionIndex])]
        actionProcess.running = true
    }

    function finishAction(exitCode) {
        if (_actionHandled) return
        _actionHandled = true
        const code = exitCode !== undefined ? exitCode : _lastActionExitCode
        if (code !== 0) {
            const err = (actionStderr.text || actionStdout.text || "").trim()
            const pid = _actionQueue[_actionIndex]
            lastError = err.length ? err
                : (_pendingAction + " failed for PID " + pid + " (exit " + code + ")")
            acting = false
            _actionQueue = []
            _pendingAction = ""
            return
        }
        _actionIndex++
        if (_actionIndex < _actionQueue.length)
            Qt.callLater(function() { root.runNextAction() })
        else
            finishAllActions()
    }

    function finishAllActions() {
        const count = _actionIndex
        acting = false
        _actionQueue = []
        _pendingAction = ""
        lastAction = count > 1 ? ("Action completed (" + count + " processes)") : "Action completed"
        Qt.callLater(function() { root.refresh() })
    }

    function resetScroll() {
        procFlickable.contentY = 0
    }

    function focusScroll() {
        procFlickable.forceActiveFocus()
    }

    function pageScroll(direction) {
        const maxY = Math.max(0, procFlickable.contentHeight - procFlickable.height)
        if (maxY <= 0) return
        const page = Math.max(80, procFlickable.height * 0.85)
        procFlickable.contentY = Math.max(0, Math.min(maxY, procFlickable.contentY + direction * page))
    }

    function lineScroll(direction) {
        const maxY = Math.max(0, procFlickable.contentHeight - procFlickable.height)
        if (maxY <= 0) return
        const step = Math.max(root.rowHeight * 2, 24)
        procFlickable.contentY = Math.max(0, Math.min(maxY, procFlickable.contentY + direction * step))
    }

    onActiveChanged: {
        if (active) refresh()
    }

    onSortKeyChanged: pruneSelection()
    onHighUsageOnlyChanged: pruneSelection()
    onGlobalFilterChanged: pruneSelection()

    onSelectionVersionChanged: {
        if (killConfirmVisible)
            killConfirmVisible = false
    }

    onVisibleChanged: {
        if (visible && active) Qt.callLater(function() { root.focusScroll() })
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
                    text: "PROCESS SUMMARY"
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
                            property var _bind: service && service.data ? service.data.timestamp : 0
                            text: "Total: " + root.summaryStats().total + "  ·  Running: " + root.summaryStats().running
                            color: root.subtextColor
                            font.pixelSize: 11
                            font.family: "monospace"
                        }
                        Text {
                            property var _bind: service && service.data ? service.data.timestamp : 0
                            text: "Load (1 / 5 / 15 min): " + root.formatLoad(root.summaryStats().load)
                            color: root.subtextColor
                            font.pixelSize: 11
                            font.family: "monospace"
                        }
                        Text {
                            property int _rows: root.dataVersion
                            property int _sel: root.selectionVersion
                            text: root.loading ? "Loading process list…"
                                : ("Showing " + root.filteredProcesses().length + " processes"
                                    + (root.hasSelection ? "  ·  " + root.selectionLabel() : ""))
                            color: root.overlayColor
                            font.pixelSize: 11
                            font.family: "monospace"
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        property var _bind: service && service.data ? service.data.timestamp : 0
                        text: root.summaryStats().load.length ? Number(root.summaryStats().load[0] || 0).toFixed(2) : "--"
                        color: root.textColor
                        font.pixelSize: 25
                        font.bold: true
                        font.family: "monospace"
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Text {
                text: "Sort:"
                color: root.overlayColor
                font.pixelSize: 10
                font.family: "monospace"
            }

            Rectangle {
                width: sortCpuLabel.implicitWidth + 16
                height: 24
                radius: 4
                color: root.sortKey === "cpu" ? Qt.rgba(0.55, 0.70, 0.96, 0.18) : "transparent"
                border.width: root.sortKey === "cpu" ? 1 : 0
                border.color: root.accentColor
                Text {
                    id: sortCpuLabel
                    anchors.centerIn: parent
                    text: "CPU%"
                    color: root.sortKey === "cpu" ? root.accentColor : root.textColor
                    font.pixelSize: 10
                    font.family: "monospace"
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.sortKey = "cpu"
                }
            }

            Rectangle {
                width: sortMemLabel.implicitWidth + 16
                height: 24
                radius: 4
                color: root.sortKey === "mem" ? Qt.rgba(0.55, 0.70, 0.96, 0.18) : "transparent"
                border.width: root.sortKey === "mem" ? 1 : 0
                border.color: root.accentColor
                Text {
                    id: sortMemLabel
                    anchors.centerIn: parent
                    text: "Memory%"
                    color: root.sortKey === "mem" ? root.accentColor : root.textColor
                    font.pixelSize: 10
                    font.family: "monospace"
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.sortKey = "mem"
                }
            }

            Rectangle {
                width: highUsageLabel.implicitWidth + 16
                height: 24
                radius: 4
                color: root.highUsageOnly ? Qt.rgba(0.95, 0.55, 0.66, 0.16) : "transparent"
                border.width: root.highUsageOnly ? 1 : 0
                border.color: root.errorColor
                Text {
                    id: highUsageLabel
                    anchors.centerIn: parent
                    text: "High usage"
                    color: root.highUsageOnly ? root.errorColor : root.textColor
                    font.pixelSize: 10
                    font.family: "monospace"
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.highUsageOnly = !root.highUsageOnly
                }
            }

            Item { Layout.fillWidth: true }

            Rectangle {
                Layout.preferredWidth: 62
                Layout.preferredHeight: 28
                radius: 6
                color: copyPidMa.containsMouse ? root.surfaceColor : "transparent"
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.1)
                opacity: root.hasSelection && !root.loading ? 1 : 0.35
                Text {
                    anchors.centerIn: parent
                    text: "Copy PID"
                    color: root.accentColor
                    font.pixelSize: 10
                }
                MouseArea {
                    id: copyPidMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    enabled: root.hasSelection && !root.loading
                    onClicked: root.copySelectedPid()
                }
            }

            Rectangle {
                Layout.preferredWidth: 88
                Layout.preferredHeight: 28
                radius: 6
                color: copyCmdMa.containsMouse ? root.surfaceColor : "transparent"
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.1)
                opacity: root.hasSelection && !root.loading ? 1 : 0.35
                Text {
                    anchors.centerIn: parent
                    text: "Copy Command"
                    color: root.accentColor
                    font.pixelSize: 10
                }
                MouseArea {
                    id: copyCmdMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    enabled: root.hasSelection && !root.loading
                    onClicked: root.copySelectedCommand()
                }
            }

            Rectangle {
                Layout.preferredWidth: 42
                Layout.preferredHeight: 28
                radius: 6
                color: killMa.containsMouse ? root.surfaceColor : "transparent"
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.1)
                opacity: root.hasSelection && !root.acting && !root.loading ? 1 : 0.35
                Text {
                    anchors.centerIn: parent
                    text: "Kill"
                    color: root.errorColor
                    font.pixelSize: 11
                }
                MouseArea {
                    id: killMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    enabled: root.hasSelection && !root.acting && !root.loading
                    onClicked: root.requestAction("kill")
                }
            }

            Rectangle {
                Layout.preferredWidth: 58
                Layout.preferredHeight: 28
                radius: 6
                color: restartMa.containsMouse ? root.surfaceColor : "transparent"
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.1)
                opacity: root.hasSelection && !root.acting && !root.loading ? 1 : 0.35
                Text {
                    anchors.centerIn: parent
                    text: "Restart"
                    color: root.accentColor
                    font.pixelSize: 11
                }
                MouseArea {
                    id: restartMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    enabled: root.hasSelection && !root.acting && !root.loading
                    onClicked: root.requestAction("restart")
                }
            }

            Text {
                visible: root.lastAction.length > 0 && root.lastError.length === 0
                text: root.lastAction
                color: root.okColor
                font.pixelSize: 10
                font.family: "monospace"
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 120
            radius: root.cardRadius
            color: root.surfaceColor
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.08)
            clip: true

            Flickable {
                id: procFlickable
                anchors.fill: parent
                anchors.margins: 8
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                contentWidth: root.tableContentWidth(width)
                contentHeight: Math.max(height, procTable.implicitHeight)

                property int _dataTick: root.dataVersion
                property string _filterTick: root.globalFilter + "|" + root.sortKey + "|" + (root.highUsageOnly ? "1" : "0")

                focus: true

                WheelHandler {
                    onWheel: function(event) {
                        const delta = event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x
                        if (delta === 0) return
                        const maxY = Math.max(0, procFlickable.contentHeight - procFlickable.height)
                        if (maxY > 0) {
                            const ticks = delta / 120
                            procFlickable.contentY = Math.max(0, Math.min(maxY, procFlickable.contentY - ticks * 28))
                        }
                        event.accepted = true
                    }
                }

                ScrollBar.vertical: ScrollBar {
                    policy: procFlickable.contentHeight > procFlickable.height + 1 ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                    contentItem: Rectangle {
                        implicitWidth: 6
                        radius: 3
                        color: parent.pressed ? root.accentColor : Qt.rgba(1, 1, 1, 0.2)
                    }
                }

                ScrollBar.horizontal: ScrollBar {
                    policy: procFlickable.contentWidth > procFlickable.width + 1 ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                    contentItem: Rectangle {
                        implicitHeight: 6
                        radius: 3
                        color: parent.pressed ? root.accentColor : Qt.rgba(1, 1, 1, 0.2)
                    }
                }

                Column {
                    id: procTable
                    width: root.tableContentWidth(procFlickable.width)
                    spacing: 0

                    Rectangle {
                        width: parent.width
                        height: root.headerHeight
                        radius: 3
                        color: Qt.rgba(0.55, 0.70, 0.96, 0.12)

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 4
                            anchors.rightMargin: 4
                            spacing: root.tblSpacing

                            Text { width: root.colPidW; height: parent.height; text: "PID"; color: root.textColor; font.pixelSize: 10; font.bold: true; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                            Text { width: root.colUserW; height: parent.height; text: "User"; color: root.textColor; font.pixelSize: 10; font.bold: true; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                            Text { width: root.colCpuW; height: parent.height; text: "CPU%"; color: root.textColor; font.pixelSize: 10; font.bold: true; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                            Text { width: root.colMemW; height: parent.height; text: "Mem%"; color: root.textColor; font.pixelSize: 10; font.bold: true; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                            Text { width: root.colTimeW; height: parent.height; text: "Time"; color: root.textColor; font.pixelSize: 10; font.bold: true; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                            Text { width: root.colStartW; height: parent.height; text: "Start"; color: root.textColor; font.pixelSize: 10; font.bold: true; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                            Text { width: root.colThreadsW; height: parent.height; text: "Thr"; color: root.textColor; font.pixelSize: 10; font.bold: true; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                            Text { width: root.colRssW; height: parent.height; text: "RSS"; color: root.textColor; font.pixelSize: 10; font.bold: true; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                            Text { width: root.colVszW; height: parent.height; text: "VSZ"; color: root.textColor; font.pixelSize: 10; font.bold: true; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                            Text { width: root.colPriW; height: parent.height; text: "PR"; color: root.textColor; font.pixelSize: 10; font.bold: true; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                            Text { width: root.colShrW; height: parent.height; text: "SHR"; color: root.textColor; font.pixelSize: 10; font.bold: true; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                            Text { width: root.cmdColWidth(parent.width); height: parent.height; text: "Command"; color: root.textColor; font.pixelSize: 10; font.bold: true; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                            Text { width: root.colStatW; height: parent.height; text: "Stat"; color: root.textColor; font.pixelSize: 10; font.bold: true; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter }
                        }
                    }

                    Text {
                        width: parent.width
                        visible: root.loading && root.filteredProcesses().length === 0
                        text: "Loading processes..."
                        color: root.overlayColor
                        font.pixelSize: 11
                        font.family: "monospace"
                        topPadding: 6
                    }

                    Text {
                        width: parent.width
                        visible: !root.loading && root.lastError.length > 0 && root.filteredProcesses().length === 0
                        text: root.lastError
                        color: root.errorColor
                        font.pixelSize: 11
                        font.family: "monospace"
                        wrapMode: Text.Wrap
                        topPadding: 6
                    }

                    Text {
                        width: parent.width
                        visible: !root.loading && root.filteredProcesses().length === 0 && root.lastError.length === 0
                        text: "(no matching processes)"
                        color: root.overlayColor
                        font.pixelSize: 11
                        font.family: "monospace"
                        topPadding: 6
                    }

                    Repeater {
                        model: root.filteredProcesses()
                        delegate: Item {
                            width: parent.width
                            height: root.rowHeight

                            property int _selTick: root.selectionVersion
                            readonly property bool isSelected: root.isPidSelected(modelData.pid)
                            readonly property bool rowHover: rowMa.containsMouse
                            readonly property bool groupStart: modelData.groupStart === true

                            Rectangle {
                                anchors.top: parent.top
                                width: parent.width
                                height: 1
                                color: Qt.rgba(1, 1, 1, 0.1)
                                visible: parent.groupStart && index > 0
                            }

                            Rectangle {
                                anchors.fill: parent
                                radius: 2
                                color: parent.isSelected ? Qt.rgba(0.55, 0.70, 0.96, 0.18)
                                    : (parent.rowHover ? Qt.rgba(1, 1, 1, 0.04)
                                        : (parent.groupStart ? Qt.rgba(1, 1, 1, 0.03) : (index % 2 === 0 ? "transparent" : Qt.rgba(1, 1, 1, 0.02))))
                            }

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: 4
                                anchors.rightMargin: 4
                                spacing: root.tblSpacing

                                Text { width: root.colPidW; height: parent.height; text: modelData.pid; color: parent.isSelected ? root.accentColor : root.textColor; font.pixelSize: 10; font.family: "monospace"; font.bold: parent.isSelected; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                                Text { width: root.colUserW; height: parent.height; text: modelData.user || "--"; color: root.overlayColor; font.pixelSize: 10; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                                Text { width: root.colCpuW; height: parent.height; text: modelData.cpu.toFixed(1); color: root.accentColor; font.pixelSize: 10; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                                Text { width: root.colMemW; height: parent.height; text: modelData.mem.toFixed(1); color: root.textColor; font.pixelSize: 10; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                                Text { width: root.colTimeW; height: parent.height; text: root.formatTime(modelData.time); color: root.subtextColor; font.pixelSize: 10; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                                Text { width: root.colStartW; height: parent.height; text: root.formatStart(modelData.start); color: root.subtextColor; font.pixelSize: 10; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight; elide: Text.ElideRight }
                                Text { width: root.colThreadsW; height: parent.height; text: modelData.threads !== undefined ? modelData.threads : "--"; color: root.textColor; font.pixelSize: 10; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                                Text { width: root.colRssW; height: parent.height; text: root.formatKiB(modelData.rss); color: root.textColor; font.pixelSize: 10; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                                Text { width: root.colVszW; height: parent.height; text: root.formatKiB(modelData.vsz); color: root.textColor; font.pixelSize: 10; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                                Text { width: root.colPriW; height: parent.height; text: modelData.pri !== undefined ? modelData.pri : "--"; color: root.textColor; font.pixelSize: 10; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                                Text { width: root.colShrW; height: parent.height; text: root.formatKiB(modelData.shr); color: root.textColor; font.pixelSize: 10; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                                Text { width: root.cmdColWidth(parent.width); height: parent.height; text: modelData.cmd || modelData.name || "--"; color: parent.isSelected ? root.textColor : root.subtextColor; font.pixelSize: 10; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                                Text { width: root.colStatW; height: parent.height; text: root.formatState(modelData.state); color: root.stateColor(modelData.state); font.pixelSize: 10; font.bold: true; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter }
                            }

                            MouseArea {
                                id: rowMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: function(mouse) {
                                    root.handleRowClick(modelData.pid, index, mouse)
                                }
                            }
                        }
                    }
                }
            }
        }

        Text {
            Layout.fillWidth: true
            Layout.topMargin: 2
            horizontalAlignment: Text.AlignRight
            visible: root.lastUpdatedMs > 0
            text: root.loading ? "Refreshing…" : ("Last updated: " + root.formatLastUpdated())
            color: root.overlayColor
            font.pixelSize: 10
            font.family: "monospace"
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: root.killConfirmVisible
        color: Qt.rgba(0, 0, 0, 0.55)
        z: 100

        MouseArea {
            anchors.fill: parent
            onClicked: root.cancelKill()
        }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - 40, 360)
            height: killConfirmColumn.implicitHeight + 28
            radius: root.cardRadius
            color: root.surfaceColor
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.12)

            MouseArea {
                anchors.fill: parent
            }

            ColumnLayout {
                id: killConfirmColumn
                anchors.fill: parent
                anchors.margins: 14
                spacing: 12

                Text {
                    Layout.fillWidth: true
                    text: "Kill " + root.selectedCount + " processes?"
                    color: root.textColor
                    font.pixelSize: 13
                    font.bold: true
                    font.family: "monospace"
                    wrapMode: Text.Wrap
                }

                Text {
                    Layout.fillWidth: true
                    text: "This sends SIGTERM to each selected process."
                    color: root.subtextColor
                    font.pixelSize: 11
                    font.family: "monospace"
                    wrapMode: Text.Wrap
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        Layout.preferredWidth: 72
                        Layout.preferredHeight: 28
                        radius: 6
                        color: cancelKillMa.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent"
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.1)
                        Text {
                            anchors.centerIn: parent
                            text: "Cancel"
                            color: root.textColor
                            font.pixelSize: 11
                        }
                        MouseArea {
                            id: cancelKillMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.cancelKill()
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 72
                        Layout.preferredHeight: 28
                        radius: 6
                        color: confirmKillMa.containsMouse ? Qt.rgba(0.95, 0.55, 0.66, 0.2) : Qt.rgba(0.95, 0.55, 0.66, 0.12)
                        border.width: 1
                        border.color: root.errorColor
                        Text {
                            anchors.centerIn: parent
                            text: "Kill"
                            color: root.errorColor
                            font.pixelSize: 11
                            font.bold: true
                        }
                        MouseArea {
                            id: confirmKillMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.confirmKill()
                        }
                    }
                }
            }
        }
    }
}