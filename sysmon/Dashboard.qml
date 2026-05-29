import Quickshell
import QtQuick
import QtQuick.Layouts
import Quickshell.Io as Io

// Local components
import "components" as Components

// Dashboard.qml
// Uses FloatingWindow so the dashboard appears in `hyprctl clients` and can be
// controlled by Hyprland window rules (float, size, special workspace, etc.).

Item {
    id: root

    // Theme
    readonly property color text: "#cdd6f4"
    readonly property color subtext: "#a6adc8"
    readonly property color accent: "#89b4fa"

    // Data
    property var data: ({})
    property bool autoPoll: false
    property int pollIntervalMs: 2500
    property bool isRefreshing: false

    onPollIntervalMsChanged: {
        if (autoPoll && pollTimer.running) {
            // Restart the timer with the new interval so the change takes effect quickly
            pollTimer.stop()
            pollTimer.start()
        }
    }

    property var cpuHistory: []
    property var gpuHistory: []
    property var netRxHistory: []
    property var netTxHistory: []
    property var diskReadHistory: []
    property var diskWriteHistory: []
    property var ramHistory: []   // for RAM sparkline

    property string lastStatus: "Loading..."
    property string lastError: ""

    // System Info tab (structured two-column version from /home/crome/.config/quickshell-help)
    property int currentTab: 0   // 0 = Monitor, 1 = System Info
    property string systemOutput: ""
    property bool systemDirty: true
    property var systemEntries: []
    property string copiedValue: ""

    function updateHistory() {
        if (!data.cpu) return

        // CPU
        let ch = cpuHistory.slice()
        ch.push(data.cpu.util || 0)
        if (ch.length > 48) ch.shift()
        cpuHistory = ch

        // GPU
        let gh = gpuHistory.slice()
        gh.push(data.gpu ? data.gpu.util : 0)
        if (gh.length > 48) gh.shift()
        gpuHistory = gh

        // Network (KB/s)
        let nrh = netRxHistory.slice()
        nrh.push(data.network ? (data.network.rx_rate / 1024) : 0)
        if (nrh.length > 48) nrh.shift()
        netRxHistory = nrh

        let nth = netTxHistory.slice()
        nth.push(data.network ? (data.network.tx_rate / 1024) : 0)
        if (nth.length > 48) nth.shift()
        netTxHistory = nth

        // Disk (KiB/s)
        let drh = diskReadHistory.slice()
        drh.push(data.disk ? (data.disk.read_rate / 1024) : 0)
        if (drh.length > 48) drh.shift()
        diskReadHistory = drh

        let dwh = diskWriteHistory.slice()
        dwh.push(data.disk ? (data.disk.write_rate / 1024) : 0)
        if (dwh.length > 48) dwh.shift()
        diskWriteHistory = dwh

        // RAM usage % history (for sparkline)
        let rh = ramHistory.slice()
        rh.push(data.memory ? (data.memory.ram_pct || 0) : 0)
        if (rh.length > 48) rh.shift()
        ramHistory = rh
    }

    Io.Process {
        id: poller
        command: ["/home/crome/.config/quickshell/sysmon/scripts/poller.sh"]
        stdout: Io.SplitParser {
            splitMarker: "\n"
            onRead: (line) => {
                const trimmed = line.trim()
                if (!trimmed) return
                if (!trimmed.startsWith("{") || !trimmed.endsWith("}")) return
                try {
                    const parsed = JSON.parse(trimmed)
                    if (parsed.error) {
                        root.lastError = parsed.error
                    } else if (parsed.timestamp && parsed.cpu) {
                        root.data = parsed
                        root.updateHistory()
                        root.lastError = ""
                        root.lastStatus = "Updated " + new Date().toLocaleTimeString()
                    }
                } catch (e) {
                    root.lastError = "JSON error"
                }
                root.isRefreshing = false
            }
        }
        onExited: (code) => {
            root.isRefreshing = false
            if (code !== 0 && !root.lastError) {
                root.lastError = "Poller exited " + code
            }
        }
    }

    Timer {
        id: pollTimer
        interval: root.pollIntervalMs
        running: root.autoPoll
        repeat: true
        onTriggered: root.refresh()
    }

    function refresh() {
        if (poller.running) return
        root.isRefreshing = true
        root.lastStatus = "Refreshing..."
        poller.running = true
    }

    Component.onCompleted: {
        Qt.callLater(function() {
            root.lastStatus = "Ready"
        })
    }

    function hide() {
        root.autoPoll = false
        if (poller.running) poller.running = false
        root.isRefreshing = false
        window.visible = false
    }

    function recenter() {
        const s = window.screen ? window.screen : (Quickshell.screens && Quickshell.screens[0])
        if (s && typeof window.x === "number") {
            window.x = Math.round((s.width - window.width) / 2)
            window.y = Math.round(s.height * 0.68)
        }
    }

    function show() {
        const s = window.screen ? window.screen : (Quickshell.screens && Quickshell.screens[0])
        if (s && typeof window.x === "number") {
            window.x = Math.round((s.width - window.width) / 2)
            window.y = Math.round(s.height * 0.68)
        }
        window.visible = true
        Qt.callLater(function() {
            root.lastStatus = "Ready"
        })
    }

    // Right-click menu
    property bool showSettingsMenu: false
    function toggleSettingsMenu() { showSettingsMenu = !showSettingsMenu }

    // === System Info (fastfetch) - duplicated from HelpMenu ===
    function refreshSystemInfo() {
        systemProcess.running = false
        systemProcess.running = true
        systemDirty = false
        copiedValue = ""
    }

    function parseFastfetchOutput(raw) {
        if (!raw) return []
        const lines = raw.split("\n")
        const entries = []
        for (let line of lines) {
            line = line.trim()
            if (!line) continue
            if (line.includes("@") && !line.includes(":")) continue
            if (line.match(/^[-=]+$/)) continue
            const idx = line.indexOf(":")
            if (idx > 0) {
                const label = line.substring(0, idx).trim()
                let value = line.substring(idx + 1).trim()
                const lower = label.toLowerCase()
                if (lower === "terminal" || lower.includes("font")) continue
                if (value) entries.push({ label: label, value: value })
            }
        }
        return entries
    }

    function copyToClipboard(text) {
        Quickshell.execDetached([
            "sh", "-c",
            'printf "%s" "$1" | wl-copy',
            "wl-copy",
            text
        ])
        copiedValue = text
        Qt.callLater(function() {
            if (copiedValue === text) copiedValue = ""
        }, 1200)
    }

    Io.Process {
        id: systemProcess
        command: ["fastfetch", "--logo", "none"]
        running: false
        stdout: Io.SplitParser {
            splitMarker: "\n"
            onRead: (line) => { root.systemOutput += line + "\n" }
        }
        onStarted: root.systemOutput = ""
        onExited: (code) => {
            if (code !== 0 && root.systemOutput.trim() === "") {
                root.systemOutput = "Failed to collect system information (exit code " + code + ")"
            } else {
                root.systemEntries = root.parseFastfetchOutput(root.systemOutput)
            }
        }
    }

    FloatingWindow {
        id: window
        visible: false
        color: "transparent"
        implicitWidth: 1020
        implicitHeight: 780
        title: "sysmon-dashboard"
        // Using FloatingWindow (Quickshell type) instead of PanelWindow so it appears
        // in `hyprctl clients` (as a normal toplevel) for hyprland special/magic workspaces + window rules.

        Rectangle {
            id: dashboard
            anchors.fill: parent
            color: "#1e1e2e"
            radius: 14

            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1.5
                color: Qt.rgba(1,1,1,0.12)
                radius: parent.radius
            }

            // Right click anywhere for menu
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.RightButton
                onClicked: root.toggleSettingsMenu()
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 10

                // HEADER
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text { text: "sysmon"; color: root.text; font.pixelSize: 18; font.bold: true }
                    Text { text: "Thelio Mira"; color: "#6c7086"; font.pixelSize: 13 }
                    Item { Layout.fillWidth: true }

                    MouseArea {
                        Layout.preferredWidth: 72; Layout.preferredHeight: 26
                        onClicked: root.refresh()
                        Rectangle {
                            anchors.fill: parent; radius: 6
                            color: root.isRefreshing ? "#444455" : Qt.rgba(1,1,1,0.06)
                            border.width: 1; border.color: Qt.rgba(1,1,1,0.1)
                        }
                        Text {
                            anchors.centerIn: parent
                            text: root.isRefreshing ? "..." : "Refresh"
                            color: root.accent; font.pixelSize: 12; font.bold: true
                        }
                    }

                    MouseArea {
                        Layout.preferredWidth: 90; Layout.preferredHeight: 26
                        onClicked: root.autoPoll = !root.autoPoll
                        Rectangle {
                            anchors.fill: parent; radius: 6
                            color: root.autoPoll ? Qt.rgba(0.65,0.9,0.6,0.18) : Qt.rgba(1,1,1,0.06)
                            border.width: 1; border.color: root.autoPoll ? "#a6e3a1" : Qt.rgba(1,1,1,0.1)
                        }
                        Text {
                            anchors.centerIn: parent
                            text: root.autoPoll ? "Auto: ON" : "Auto: OFF"
                            color: root.autoPoll ? "#a6e3a1" : "#a6adc8"; font.pixelSize: 11
                        }
                    }

                    MouseArea {
                        Layout.preferredWidth: 78; Layout.preferredHeight: 26
                        onClicked: root.recenter()
                        Rectangle {
                            anchors.fill: parent; radius: 6
                            color: Qt.rgba(1,1,1,0.06)
                            border.width: 1; border.color: Qt.rgba(1,1,1,0.1)
                        }
                        Text {
                            anchors.centerIn: parent; text: "Re-center"; color: "#a6adc8"; font.pixelSize: 11
                        }
                    }

                    MouseArea {
                        Layout.preferredWidth: 26; Layout.preferredHeight: 26
                        onClicked: root.hide()
                        Text { anchors.centerIn: parent; text: "✕"; color: "#6c7086"; font.pixelSize: 16 }
                    }
                }

                // Tab bar
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    Layout.bottomMargin: 4
                    spacing: 6

                    Repeater {
                        model: [
                            { label: "Monitor", tab: 0 },
                            { label: "System Info", tab: 1 }
                        ]
                        delegate: MouseArea {
                            Layout.preferredHeight: 26
                            Layout.preferredWidth: modelData.label.length * 8 + 28
                            onClicked: {
                                root.currentTab = modelData.tab
                                if (modelData.tab === 1 && root.systemDirty) {
                                    root.refreshSystemInfo()
                                }
                            }
                            Rectangle {
                                anchors.fill: parent
                                radius: 6
                                color: (root.currentTab === modelData.tab)
                                    ? Qt.rgba(0.55, 0.70, 0.96, 0.18)
                                    : (parent.containsMouse ? Qt.rgba(1,1,1,0.06) : "transparent")
                                border.width: (root.currentTab === modelData.tab) ? 1 : 0
                                border.color: root.accent
                            }
                            Text {
                                anchors.centerIn: parent
                                text: modelData.label
                                color: (root.currentTab === modelData.tab) ? root.accent : root.text
                                font.pixelSize: 12
                                font.bold: (root.currentTab === modelData.tab)
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }
                }

                // Monitor view
                ColumnLayout {
                    visible: root.currentTab === 0
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    spacing: 10

                    // Row 1: CPU gauge | Top CPU Processes | Top Memory Processes
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        // CPU (narrower to fit 3 columns)
                        Rectangle {
                            Layout.preferredWidth: 340
                            Layout.preferredHeight: 205
                            radius: 10
                            color: Qt.rgba(0.12, 0.12, 0.14, 0.95)
                            border.width: 1; border.color: Qt.rgba(1,1,1,0.06)

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 4

                                MouseArea {
                                    Layout.preferredWidth: 40; Layout.preferredHeight: 16
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Quickshell.execDetached(["sh", "-c", "kitty -e btop"])
                                    Text { anchors.fill: parent; text: "CPU"; color: root.text; font.pixelSize: 13; font.bold: true }
                                }

                                RowLayout {
                                    spacing: 8; Layout.fillWidth: true
                                    Components.CircularGauge {
                                        size: 88
                                        value: root.data.cpu ? root.data.cpu.util : 0
                                        label: ""
                                        subValue: root.data.cpu ? root.data.cpu.temp.toFixed(0) + "°C" : ""
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true; spacing: 1
                                        Text { text: root.data.cpu ? root.data.cpu.util.toFixed(1) + "%" : "--"; color: root.text; font.pixelSize: 22; font.bold: true }
                                        Text {
                                            text: root.data.cpu ? "Tctl " + root.data.cpu.temp.toFixed(1) + "°  TCCD " + root.data.cpu.tccd1.toFixed(0) + "/" + root.data.cpu.tccd2.toFixed(0) + "°" : "No data"
                                            color: root.subtext; font.pixelSize: 9
                                        }
                                        Components.Sparkline {
                                            Layout.fillWidth: true; Layout.preferredHeight: 42
                                            history: root.cpuHistory; lineColor: "#89b4fa"
                                        }
                                    }
                                }
                            }
                        }

                        // Top Processes by CPU
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 205
                            radius: 10
                            color: Qt.rgba(0.12, 0.12, 0.14, 0.95)
                            border.width: 1; border.color: Qt.rgba(1,1,1,0.06)

                            ColumnLayout {
                                anchors.fill: parent; anchors.margins: 8; spacing: 2
                                Text { text: "TOP PROCESSES (CPU)"; color: root.text; font.pixelSize: 11; font.bold: true }
                                Repeater {
                                    model: root.data.top_processes ? root.data.top_processes.slice(0, 8) : []
                                    delegate: Text {
                                        text: modelData.name + "  " + modelData.cpu.toFixed(1) + "% / " + modelData.mem.toFixed(1) + "%"
                                        color: root.subtext; font.pixelSize: 10
                                    }
                                }
                            }
                        }

                        // Top Processes by Memory (new)
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 205
                            radius: 10
                            color: Qt.rgba(0.12, 0.12, 0.14, 0.95)
                            border.width: 1; border.color: Qt.rgba(1,1,1,0.06)

                            ColumnLayout {
                                anchors.fill: parent; anchors.margins: 8; spacing: 2
                                Text { text: "TOP PROCESSES (MEM)"; color: root.text; font.pixelSize: 11; font.bold: true }
                                Repeater {
                                    model: root.data.top_memory ? root.data.top_memory.slice(0, 8) : []
                                    delegate: Text {
                                        text: modelData.name + "  " + modelData.mem.toFixed(1) + "% / " + modelData.cpu.toFixed(1) + "%"
                                        color: root.subtext; font.pixelSize: 10
                                    }
                                }
                            }
                        }
                    }

                    // Row 2: GPU (left) + RAM (spans right)
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        // GPU
                        Rectangle {
                            Layout.preferredWidth: 340
                            Layout.preferredHeight: 185
                            radius: 10
                            color: Qt.rgba(0.12, 0.12, 0.14, 0.95)
                            border.width: 1; border.color: Qt.rgba(1,1,1,0.06)

                            ColumnLayout {
                                anchors.fill: parent; anchors.margins: 8; spacing: 4

                                MouseArea {
                                    Layout.preferredWidth: 110; Layout.preferredHeight: 16
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Quickshell.execDetached(["sh", "-c", "kitty -e nvtop"])
                                    Text { anchors.fill: parent; text: "GPU (RTX 5080)"; color: root.text; font.pixelSize: 13; font.bold: true }
                                }

                                RowLayout {
                                    spacing: 8; Layout.fillWidth: true
                                    Components.CircularGauge {
                                        size: 88
                                        value: root.data.gpu ? root.data.gpu.util : 0
                                        label: ""
                                        subValue: root.data.gpu ? root.data.gpu.temp.toFixed(0) + "°C" : ""
                                        lowColor: "#a6e3a1"; midColor: "#f9e2af"; highColor: "#f38ba8"
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true; spacing: 1
                                        Text { text: root.data.gpu ? root.data.gpu.util.toFixed(0) + "%" : "--"; color: root.text; font.pixelSize: 22; font.bold: true }
                                        Text {
                                            text: root.data.gpu ? "VRAM " + (root.data.gpu.vram_used / 1024).toFixed(1) + "/" + (root.data.gpu.vram_total / 1024).toFixed(1) + " GiB (" + root.data.gpu.vram_pct.toFixed(1) + "%)" : "No data"
                                            color: root.subtext; font.pixelSize: 9
                                        }
                                        Rectangle {
                                            Layout.preferredWidth: 110; Layout.preferredHeight: 6; radius: 3; color: "#2a2a3a"
                                            Rectangle {
                                                width: parent.width * Math.min(1, (root.data.gpu ? root.data.gpu.vram_pct : 0) / 100)
                                                height: parent.height; radius: 3
                                                color: (root.data.gpu && root.data.gpu.vram_pct > 85) ? "#f38ba8" : (root.data.gpu && root.data.gpu.vram_pct > 65) ? "#f9e2af" : "#a6e3a1"
                                            }
                                        }
                                        Text { text: root.data.gpu ? "Fan " + root.data.gpu.fan.toFixed(0) + " RPM" : ""; color: "#6c7086"; font.pixelSize: 9 }
                                        Components.Sparkline {
                                            Layout.fillWidth: true; Layout.preferredHeight: 38
                                            history: root.gpuHistory; lineColor: "#a6e3a1"
                                        }
                                    }
                                }
                            }
                        }

                        // RAM + SWAP (spans remaining width)
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 185
                            radius: 10
                            color: Qt.rgba(0.12, 0.12, 0.14, 0.95)
                            border.width: 1; border.color: Qt.rgba(1,1,1,0.06)

                            ColumnLayout {
                                anchors.fill: parent; anchors.margins: 8; spacing: 4
                                Text { text: "MEMORY"; color: root.text; font.pixelSize: 13; font.bold: true }

                                // RAM bar
                                RowLayout {
                                    spacing: 8; Layout.fillWidth: true
                                    Rectangle {
                                        Layout.preferredWidth: 200; Layout.preferredHeight: 9; radius: 4; color: "#2a2a3a"
                                        Rectangle {
                                            width: parent.width * Math.min(1, (root.data.memory ? root.data.memory.ram_pct : 0) / 100)
                                            height: parent.height; radius: 4
                                            color: (root.data.memory && root.data.memory.ram_pct > 85) ? "#f38ba8" : (root.data.memory && root.data.memory.ram_pct > 65) ? "#f9e2af" : "#a6e3a1"
                                        }
                                    }
                                    Text {
                                        text: root.data.memory ? root.data.memory.ram_pct.toFixed(1) + "% (" + root.data.memory.ram_used + "/" + root.data.memory.ram_total + " MiB)" : "--"
                                        color: root.subtext; font.pixelSize: 11
                                    }
                                }

                                // RAM sparkline
                                Text {
                                    text: "RAM history"
                                    color: root.subtext
                                    font.pixelSize: 9
                                }
                                Components.Sparkline {
                                    Layout.fillWidth: true; Layout.preferredHeight: 42
                                    history: root.ramHistory; lineColor: "#89b4fa"
                                }

                                // SWAP bar
                                RowLayout {
                                    spacing: 8; Layout.fillWidth: true
                                    Rectangle {
                                        Layout.preferredWidth: 200; Layout.preferredHeight: 9; radius: 4; color: "#2a2a3a"
                                        Rectangle {
                                            width: parent.width * Math.min(1, (root.data.memory ? root.data.memory.swap_pct : 0) / 100)
                                            height: parent.height; radius: 4
                                            color: (root.data.memory && root.data.memory.swap_pct > 85) ? "#f38ba8" : (root.data.memory && root.data.memory.swap_pct > 65) ? "#f9e2af" : "#a6e3a1"
                                        }
                                    }
                                    Text {
                                        text: "SWAP " + (root.data.memory ? root.data.memory.swap_pct.toFixed(1) + "%" : "--")
                                        color: root.subtext; font.pixelSize: 11
                                    }
                                }
                            }
                        }
                    }

                    // Row 3: Disk Storage (NVMe) | PSD | CCACHE
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        // Disk Storage NVMe pills
                        Rectangle {
                            Layout.preferredWidth: 300
                            Layout.preferredHeight: 115
                            radius: 10
                            color: Qt.rgba(0.12, 0.12, 0.14, 0.95)
                            border.width: 1
                            border.color: Qt.rgba(1,1,1,0.06)

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 4

                                Text {
                                    text: "DISK STORAGE (NVMe)"
                                    color: "#cdd6f4"
                                    font.pixelSize: 11
                                    font.bold: true
                                }

                                RowLayout {
                                    spacing: 12
                                    Layout.fillWidth: true

                                    Repeater {
                                        model: (root.data.disks || []).filter(function(d) {
                                            return d.mount === "/" || d.mount === "/run/media/crome/data";
                                        })
                                        delegate: ColumnLayout {
                                            spacing: 1
                                            Components.CircularGauge {
                                                size: 60
                                                value: modelData.pct || 0
                                                label: ""
                                                subValue: (modelData.pct || 0).toFixed(0) + "%"
                                            }
                                            Text {
                                                text: modelData.mount === "/" ? "System" : "Data"
                                                color: "#a6adc8"
                                                font.pixelSize: 9
                                                horizontalAlignment: Text.AlignHCenter
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // PSD OVERLAY
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 115
                            radius: 10
                            color: Qt.rgba(0.12, 0.12, 0.14, 0.95)
                            border.width: 1
                            border.color: Qt.rgba(1,1,1,0.06)

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 4

                                Text {
                                    text: "PSD OVERLAY (psd)"
                                    color: "#cdd6f4"
                                    font.pixelSize: 11
                                    font.bold: true
                                }

                                // Overlay usage bar
                                RowLayout {
                                    spacing: 8; Layout.fillWidth: true
                                    Rectangle {
                                        Layout.preferredWidth: 140; Layout.preferredHeight: 8; radius: 4; color: "#2a2a3a"
                                        Rectangle {
                                            width: {
                                                const total = (root.data.psd && root.data.psd.overlay_total_gb) || 5.5
                                                const used = (root.data.psd && root.data.psd.overlay_used_mb) ? root.data.psd.overlay_used_mb / 1024
                                                    : ((root.data.psd && root.data.psd.profile_total_mb) ? root.data.psd.profile_total_mb / 1024 : 0)
                                                return parent.width * Math.min(1, used / total)
                                            }
                                            height: parent.height; radius: 4
                                            color: "#a6e3a1"
                                        }
                                    }
                                    Text {
                                        text: {
                                            const p = root.data.psd || {}
                                            const prof = (p.profile_total_mb || 0) / 1024
                                            const total = p.overlay_total_gb || 5.5
                                            return prof.toFixed(1) + " / " + total + " GB"
                                        }
                                        color: root.subtext; font.pixelSize: 10
                                    }
                                }

                                Text {
                                    text: (root.data.psd && root.data.psd.profiles && root.data.psd.profiles.length > 0)
                                        ? root.data.psd.profiles.join(", ")
                                        : (root.data.psd && root.data.psd.profile_total_mb > 0 ? "Profiles active" : "No active PSD profiles")
                                    color: "#a6adc8"
                                    font.pixelSize: 10
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        // CCACHE (small card with bar)
                        Rectangle {
                            Layout.preferredWidth: 160
                            Layout.preferredHeight: 115
                            radius: 10
                            color: Qt.rgba(0.12, 0.12, 0.14, 0.95)
                            border.width: 1
                            border.color: Qt.rgba(1,1,1,0.06)

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 4

                                Text {
                                    text: "CCACHE"
                                    color: "#cdd6f4"
                                    font.pixelSize: 11
                                    font.bold: true
                                }

                                // Size bar (current / max)
                                RowLayout {
                                    spacing: 6; Layout.fillWidth: true
                                    Rectangle {
                                        Layout.preferredWidth: 100; Layout.preferredHeight: 8; radius: 4; color: "#2a2a3a"
                                        Rectangle {
                                            width: {
                                                const cur = (root.data.ccache && root.data.ccache.size_gb) || 0
                                                const max = (root.data.ccache && root.data.ccache.max_gb) || 10
                                                return parent.width * Math.min(1, cur / max)
                                            }
                                            height: parent.height; radius: 4
                                            color: "#89b4fa"
                                        }
                                    }
                                    Text {
                                        text: (root.data.ccache ? root.data.ccache.size_gb.toFixed(1) : "0") + "G"
                                        color: root.subtext; font.pixelSize: 10
                                    }
                                }

                                Text {
                                    text: "Hit: " + (root.data.ccache ? root.data.ccache.hit_rate.toFixed(0) + "%" : "--")
                                    color: root.subtext; font.pixelSize: 10
                                }
                            }
                        }
                    }

                    // Row 4: Network - full width
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 100
                        radius: 10
                        color: Qt.rgba(0.12, 0.12, 0.14, 0.95)
                        border.width: 1; border.color: Qt.rgba(1,1,1,0.06)

                        ColumnLayout {
                            anchors.fill: parent; anchors.margins: 8; spacing: 4
                            MouseArea {
                                Layout.preferredWidth: 220; Layout.preferredHeight: 16
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Quickshell.execDetached(["sh", "-c", "kitty -e nmtui"])
                                Text { anchors.fill: parent; text: "NETWORK (" + (root.data.network ? root.data.network.iface : "?") + ")  [click for nmtui]"; color: root.text; font.pixelSize: 12; font.bold: true }
                            }
                            RowLayout {
                                spacing: 12; Layout.fillWidth: true
                                ColumnLayout {
                                    spacing: 1; Layout.fillWidth: true
                                    Text { text: "RX " + (root.data.network ? (root.data.network.rx_rate/1024).toFixed(1) : "0") + " KB/s"; color: "#89b4fa"; font.pixelSize: 11 }
                                    Components.Sparkline { Layout.fillWidth: true; Layout.preferredHeight: 36; history: root.netRxHistory; lineColor: "#89b4fa" }
                                }
                                ColumnLayout {
                                    spacing: 1; Layout.fillWidth: true
                                    Text { text: "TX " + (root.data.network ? (root.data.network.tx_rate/1024).toFixed(1) : "0") + " KB/s"; color: "#a6e3a1"; font.pixelSize: 11 }
                                    Components.Sparkline { Layout.fillWidth: true; Layout.preferredHeight: 36; history: root.netTxHistory; lineColor: "#a6e3a1" }
                                }
                            }
                        }
                    }
                }

                // System Info view - structured two-column layout (from /home/crome/.config/quickshell-help)
                Item {
                    visible: root.currentTab === 1
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 4
                        radius: 10
                        color: Qt.rgba(0.12, 0.12, 0.14, 0.95)
                        border.width: 1
                        border.color: Qt.rgba(1,1,1,0.06)

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 8

                            // Header
                            Text {
                                text: "crome@crome-dt"
                                font.pixelSize: 16
                                font.bold: true
                                color: root.accent
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                height: 1
                                color: Qt.rgba(1,1,1,0.1)
                            }

                            // Scrollable two-column list
                            Flickable {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                clip: true
                                contentHeight: sysList.implicitHeight

                                Column {
                                    id: sysList
                                    width: parent.width
                                    spacing: 2

                                    Repeater {
                                        model: root.systemEntries
                                        delegate: Rectangle {
                                            width: parent.width
                                            height: 22
                                            color: valueMa.containsMouse ? Qt.rgba(1,1,1,0.06) : "transparent"

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 4
                                                anchors.rightMargin: 8
                                                spacing: 10

                                                Text {
                                                    Layout.preferredWidth: 200
                                                    text: modelData.label + ":"
                                                    color: root.accent
                                                    font.pixelSize: 11
                                                    font.family: "monospace"
                                                }

                                                Text {
                                                    Layout.fillWidth: true
                                                    text: modelData.value
                                                    color: root.text
                                                    font.pixelSize: 11
                                                    font.family: "monospace"
                                                    elide: Text.ElideRight

                                                    MouseArea {
                                                        id: valueMa
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: root.copyToClipboard(modelData.value)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Refresh button
                        MouseArea {
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.margins: 12
                            width: 68
                            height: 24
                            onClicked: root.refreshSystemInfo()

                            Rectangle {
                                anchors.fill: parent
                                radius: 5
                                color: parent.containsMouse ? Qt.rgba(1,1,1,0.08) : "transparent"
                                border.width: 1
                                border.color: Qt.rgba(1,1,1,0.1)
                            }
                            Text {
                                anchors.centerIn: parent
                                text: "Refresh"
                                color: root.accent
                                font.pixelSize: 11
                            }
                        }
                    }
                }

                // Push everything above to the top (only for Monitor tab)
                Item {
                    visible: root.currentTab === 0
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                }

                // Bottom status (bottom-right, white text) - only for Monitor
                RowLayout {
                    visible: root.currentTab === 0
                    Layout.fillWidth: true
                    Item { Layout.fillWidth: true }
                    Text {
                        text: root.lastError !== "" ? root.lastError : root.lastStatus
                        color: root.text
                        font.pixelSize: 11
                    }
                }
            }

            // Right-click menu
            Rectangle {
                visible: root.showSettingsMenu
                anchors.top: parent.top; anchors.right: parent.right; anchors.margins: 8
                width: 240; height: 280; radius: 8
                color: Qt.rgba(0.08, 0.08, 0.10, 0.98)
                border.width: 1; border.color: Qt.rgba(1,1,1,0.12); z: 100

                MouseArea { anchors.fill: parent; onClicked: root.showSettingsMenu = false }

                ColumnLayout {
                    anchors.fill: parent; anchors.margins: 10; spacing: 6

                    Text { text: "sysmon — Quick Settings"; color: root.text; font.pixelSize: 12; font.bold: true }

                    MouseArea {
                        Layout.fillWidth: true; Layout.preferredHeight: 22
                        onClicked: {
                            root.autoPoll = !root.autoPoll
                            if (root.autoPoll) {
                                root.refresh()
                            }
                            root.showSettingsMenu = false
                        }
                        Text {
                            text: "Auto Poll: " + (root.autoPoll ? "ON" : "OFF")
                            color: root.subtext; font.pixelSize: 11
                        }
                    }

                    // Polling Speed section
                    Text {
                        text: "Polling Speed"
                        color: root.text
                        font.pixelSize: 10
                        font.bold: true
                        Layout.topMargin: 4
                    }

                    Repeater {
                        model: [
                            { label: "1 second",    value: 1000 },
                            { label: "2 seconds",   value: 2000 },
                            { label: "5 seconds",   value: 5000 },
                            { label: "10 seconds",  value: 10000 },
                            { label: "30 seconds",  value: 30000 }
                        ]
                        delegate: MouseArea {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 20
                            onClicked: {
                                root.pollIntervalMs = modelData.value
                                root.showSettingsMenu = false
                            }
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                spacing: 6
                                Rectangle {
                                    width: 8; height: 8; radius: 4
                                    color: (root.pollIntervalMs === modelData.value) ? root.accent : "transparent"
                                    border.width: 1
                                    border.color: root.accent
                                }
                                Text {
                                    text: modelData.label
                                    color: (root.pollIntervalMs === modelData.value) ? root.accent : root.subtext
                                    font.pixelSize: 11
                                }
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }

                    MouseArea {
                        Layout.fillWidth: true; Layout.preferredHeight: 22
                        onClicked: { root.recenter(); root.showSettingsMenu = false }
                        Text { text: "Re-center Window"; color: root.subtext; font.pixelSize: 11 }
                    }
                    MouseArea {
                        Layout.fillWidth: true; Layout.preferredHeight: 22
                        onClicked: root.hide()
                        Text { text: "Close Dashboard"; color: root.subtext; font.pixelSize: 11 }
                    }

                    Text { text: "(Right-click again to close)"; color: "#6c7086"; font.pixelSize: 9 }
                }
            }
        }
    }
}
