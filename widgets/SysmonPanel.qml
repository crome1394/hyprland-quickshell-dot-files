import Quickshell
import QtQuick
import QtQuick.Layouts
import Quickshell.Io as Io

// Local components (CircularGauge, Sparkline)
import "../components" as Components

// Bring parent scope (Theme.qml) into the type namespace exactly like
// HyprConfigInsp.qml does ("import .." + bare TypeName {}). This lets us do
// Theme { id: th } for a live instance while keeping Theme.qml a plain
// QtObject (no pragma Singleton, no qmldir).
//
// The sibling SysMonService.qml (in the same widgets/ dir) becomes available
// as the bare "SysMonService" type when the parent does `import "widgets"`
// (the normal case) or when a root launcher does `import "widgets"`.
import ".."

// =============================================================================
// SysmonPanel.qml — Side PanelWindow for live system monitoring (Quickshell v0.3+)
// =============================================================================
//
// Purpose:
//   Converts the old standalone sysmon dashboard into a proper anchored
//   PanelWindow widget for Hyprland (right side by default, theme driven).
//
// Launching standalone (the old "qs -p .../sysmon" workflow):
//   qs -p ~/.config/quickshell/sysmon.qml     (clean, recommended)
//   qs -p ~/.config/quickshell/sysmon          (dir form, may warn "outside config folder")
//
//   Direct launch of the .qml inside widgets/ does not work on its own
//   (the top level document must be a ShellRoot, and "Theme" / sibling types
//   are registered via the root + `import "widgets"` context).
//
// Embedding in your main bar (later step):
//   After `import "widgets"` in shell.qml you can do:
//     SysmonPanel { id: sysmonPanel }
//   and call sysmonPanel.show() / .hide() (e.g. from a button or IPC handler).
//
// Theme Properties Consumed (ALL visuals come from here):
//   - th.panelWidth, th.panelHeight, th.panelRadius, th.panelPosition
//   - th.panelMargin*, th.panelBg, th.panelBorder, th.panelHighlight
//   - th.panelCardBg, th.panelCardBorder, th.panelTabActive*, th.accent
//   - th.text, th.subtext, th.overlay, th.muted, th.sysmonPollOptions
//   - (plus base tokens used via th.xxx)
//
// Dependencies:
//   - SysMonService (instantiated below via bare type from "import "widgets""; source of truth for metrics + poll)
//   - components/CircularGauge.qml + Sparkline.qml (reused + themed)
//   - scripts/sysmon-poller.sh (via service)
//   - fastfetch (for System Info tab)
//
// Important Notes (binding rules):
//   - service.* properties are read via direct bindings in UI.
//   - Writes to service only happen in onClicked / onValueChanged handlers
//     via direct assignment: service.pollInterval = 1500
//   - No two-way bindings on pollInterval or data.
//   - Service owns pollInterval, histories, data, isRefreshing, etc.
//
// Layout & appearance:
//   - PanelWindow + selective radii so the monitor-edge side stays flat.
//   - Adaptive margins/radii based on th.panelPosition (right is primary).
//   - Generous inner padding from theme.
//
// =============================================================================

Item {
    id: root

    // === Live instances (HyprConfigInsp style) ===
    // The "import .." + bare names give us the live Theme instance and the
    // SysMonService (the widgets/ dir import registers the sibling too).
    Theme { id: th }
    SysMonService { id: service }

    // === Local view state (panel only; not owned by service) ===
    property int currentTab: 0   // 0 = CPU, 1 = GPU, 2 = Memory, 3 = Other, 4 = System Info

    // System Info tab state (fastfetch + copy-to-clipboard). Duplicated from
    // HyprConfigInsp only because we must not refactor existing files. Small and
    // self-contained here.
    property string systemOutput: ""
    property bool systemDirty: true
    property var systemEntries: []
    property string copiedValue: ""

    // === Public API (for shell integration / IPC later) ===
    property bool open: window.visible

    signal opened()
    signal closed()

    function toggle() {
        if (window.visible) hide()
        else show()
    }

    function show() {
        window.visible = true
        // If user is on System Info and it is stale, fetch once.
        if (currentTab === 4 && systemDirty) {
            refreshSystemInfo()
        }
    }

    function hide() {
        window.visible = false
    }

    // === Section: System Info helpers (fastfetch + clickable copy) ===
    // These are intentionally local to the panel (UI concern). Service stays
    // focused on numeric monitor metrics + polling.

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

    // Fastfetch process (on-demand, only when System Info tab is shown/refreshed).
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

    // === Section: The actual side panel (PanelWindow) ===
    // Anchored to the right edge by default. All sizing/radii/margins/position
    // come from Theme. The inner rect uses selective corner radii so only the
    // "inner" (left) side is rounded; the right edge (touching monitor border)
    // stays perfectly flat.

    PanelWindow {
        id: window
        visible: false
        color: "transparent"
        exclusiveZone: 0   // do not reserve space; other windows can sit beside

        // Size from theme (width is the important one for side panel).
        implicitWidth: th.panelWidth || 460
        implicitHeight: th.panelHeight || 720

        // === Adaptive anchors + margins (position driven by Theme) ===
        // For "right" (primary): attach right + top + bottom, inset top/bottom.
        // Other positions are prepared for future; change th.panelPosition and
        // reload (runtime toggle can be added in header later).
        anchors.right: (th.panelPosition || "right") === "right"
        anchors.left: (th.panelPosition || "right") === "left"
        anchors.bottom: (th.panelPosition || "right") === "bottom"
        // Also attach top for vertical side panels so margins work nicely.
        anchors.top: ((th.panelPosition || "right") === "right") || ((th.panelPosition || "right") === "left")

        // Generous breathing room (adapts to position via theme values).
        margins.top: th.panelMarginTop || 36
        margins.bottom: th.panelMarginBottom || 36
        margins.left: ((th.panelPosition || "right") === "bottom") ? (th.panelMarginSide || 12) : 0
        margins.right: ((th.panelPosition || "right") === "bottom") ? (th.panelMarginSide || 12) : 0

        // Keyboard escape closes the panel (nice for power users).
        Item {
            anchors.fill: parent
            focus: window.visible
            Keys.onEscapePressed: root.hide()
        }

        // Click-outside does NOT auto-close for a side panel (it is meant to
        // stay visible while you work). Only the explicit X or Esc closes it.

        // === Inner visual container with selective rounded corners ===
        // The right edge (for right position) must remain flat against the
        // monitor border. We zero the radii on the "outer" corners only.
        Rectangle {
            id: panelBg
            anchors.fill: parent
            color: th.panelBg || Qt.rgba(0.07, 0.07, 0.09, 0.90)
            border.width: th.controlBorderWidth || 1
            border.color: th.panelBorder || Qt.rgba(1, 1, 1, 0.13)

            // Compute selective radii so only inner edges are rounded.
            // "right" position -> round left side only.
            // "left"  position -> round right side only.
            // "bottom"-> round top side only.
            readonly property int r: th.panelRadius || 12
            readonly property string pos: th.panelPosition || "right"

            topLeftRadius:     (pos === "right") ? r : ((pos === "bottom") ? r : 0)
            topRightRadius:    (pos === "left")  ? r : ((pos === "bottom") ? r : 0)
            bottomLeftRadius:  (pos === "right") ? r : 0
            bottomRightRadius: (pos === "left")  ? r : 0

            // Top glass highlight line (consistent with bar/popup language)
            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1.5
                color: th.panelHighlight || Qt.rgba(1, 1, 1, 0.18)
                // radius only on the rounded side(s) of the parent
                radius: parent.topLeftRadius > 0 ? parent.topLeftRadius : parent.topRightRadius
            }

            // Main content column
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: th.popupSpacing || 16
                spacing: 10

                // === HEADER ===
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: "sysmon"
                        color: th.text
                        font.pixelSize: th.fontPopupTitle || 16
                        font.bold: true
                        font.family: th.fontFamily
                    }

                    Text {
                        text: "Thelio Mira"   // TODO: make dynamic later via service if desired
                        color: th.overlay
                        font.pixelSize: th.panelCardSmallSize || 11
                        font.family: th.fontFamily
                    }

                    Item { Layout.fillWidth: true }

                    // Refresh button (always available)
                    MouseArea {
                        Layout.preferredWidth: 64
                        Layout.preferredHeight: 22
                        onClicked: service.refresh()
                        cursorShape: Qt.PointingHandCursor

                        Rectangle {
                            anchors.fill: parent
                            radius: th.buttonRadius || 6
                            color: service.isRefreshing ? th.controlActiveBg : th.controlHoverBg || Qt.rgba(1,1,1,0.06)
                            border.width: th.controlBorderWidth || 1
                            border.color: Qt.rgba(1,1,1,0.10)
                        }
                        Text {
                            anchors.centerIn: parent
                            text: service.isRefreshing ? "..." : "Refresh"
                            color: th.accent
                            font.pixelSize: th.panelCardSmallSize || 11
                            font.bold: true
                            font.family: th.fontFamily
                        }
                    }

                    // Close button
                    MouseArea {
                        Layout.preferredWidth: 22
                        Layout.preferredHeight: 22
                        onClicked: root.hide()
                        cursorShape: Qt.PointingHandCursor
                        Text {
                            anchors.centerIn: parent
                            text: "✕"
                            color: th.overlay
                            font.pixelSize: 16
                        }
                    }
                }

                // === TAB SWITCHER ===
                // Wrapped in Item with explicit high z so it always paints above the tab content
                // (contentPane + its children Rects/Columns). This prevents the tab bar from
                // disappearing behind summaries or history pills when switching tabs (GPU/Mem/Other/System Info).
                // The wrapper reserves layout space; Row is anchored inside. z on wrapper ensures stacking.
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 28
                    z: 200  // high z-index so tabs always on top of content below (higher than contentPane z)

                    RowLayout {
                        anchors.fill: parent
                        anchors.topMargin: 2
                        anchors.bottomMargin: 4
                        spacing: 6

                        Repeater {
                            model: [
                                { label: "CPU", tab: 0 },
                                { label: "GPU", tab: 1 },
                                { label: "Memory", tab: 2 },
                                { label: "Other", tab: 3 },
                                { label: "System Info", tab: 4 }
                            ]
                            delegate: MouseArea {
                                Layout.preferredHeight: 24
                                Layout.preferredWidth: modelData.label.length * 7 + 24
                                onClicked: {
                                    root.currentTab = modelData.tab
                                    if (modelData.tab === 4 && root.systemDirty) {
                                        root.refreshSystemInfo()
                                    }
                                }
                                cursorShape: Qt.PointingHandCursor

                                Rectangle {
                                    anchors.fill: parent
                                    radius: th.buttonRadius || 6
                                    color: (root.currentTab === modelData.tab)
                                        ? th.panelTabActiveBg
                                        : (parent.containsMouse ? th.controlHoverBg || Qt.rgba(1,1,1,0.06) : "transparent")
                                    border.width: (root.currentTab === modelData.tab) ? 1 : 0
                                    border.color: th.panelTabActiveBorder || th.accent
                                }
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    color: (root.currentTab === modelData.tab) ? th.accent : th.text
                                    font.pixelSize: th.panelCardSmallSize || 11
                                    font.bold: (root.currentTab === modelData.tab)
                                    font.family: th.fontFamily
                                }
                            }
                        }

                        Item { Layout.fillWidth: true }
                    }
                }

                // Fixed-height content pane. All tabs fill exactly this area (anchors.fill + visible).
                // This prevents the tab bar / overall layout from shifting when switching tabs.
                // Internal content is top-anchored; use a bottom filler Item {Layout.fillHeight: true} to pad to consistent height.
                Item {
                    id: contentPane
                    Layout.fillWidth: true
                    Layout.preferredHeight: th.sysmonTabContentHeight || 650
                    z: 0  // low z; tab bar wrapper above has z:200 so nav never hidden behind content/summaries/charts

                    // === CPU TAB ===
                    Item {
                        width: parent.width
                        height: parent.height
                        visible: root.currentTab === 0
                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 8

                            // 1. CPU Summary Pill at the very top. Title top-left.
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 85
                                radius: th.sysmonPillRadius || 8
                                color: th.panelCardBg
                                border.width: th.controlBorderWidth || 1
                                border.color: th.panelCardBorder

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: th.sysmonPillMargin || 8
                                    spacing: 4

                                    Text {
                                        text: "CPU SUMMARY"
                                        color: th.text
                                        font.pixelSize: th.panelCardSmallSize || 10
                                        font.bold: true
                                        font.family: th.fontFamily
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 10
                                        ColumnLayout {
                                            spacing: 1
                                            Text { text: "Vendor: " + (service.data.cpu_info && service.data.cpu_info.vendor ? service.data.cpu_info.vendor : "--"); color: th.subtext; font.pixelSize: 9; font.family: th.fontFamily }
                                            Text { text: "Model: " + (service.data.cpu_info && service.data.cpu_info.model ? service.data.cpu_info.model : "--"); color: th.subtext; font.pixelSize: 9; font.family: th.fontFamily }
                                            Text { text: "Arch: " + (service.data.cpu_info && service.data.cpu_info.arch ? service.data.cpu_info.arch : "--") + "  Cores: " + (service.data.cpu_info && service.data.cpu_info.cores ? service.data.cpu_info.cores : "--"); color: th.subtext; font.pixelSize: 9; font.family: th.fontFamily }
                                        }
                                        Item { Layout.fillWidth: true }
                                        Text {
                                            text: (service.data.cpu ? (service.data.cpu.util || 0).toFixed(0) : "0") + "%"
                                            color: th.text
                                            font.pixelSize: 22
                                            font.bold: true
                                            font.family: th.fontFamily
                                        }
                                    }
                                }
                            }

                            // 2. Horizontal layout: Gauge left, Top CPU Processes right.
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 160
                                spacing: 8

                                // CPU Usage Gauge (left, in pill)
                                Rectangle {
                                    Layout.preferredWidth: 180
                                    Layout.fillHeight: true
                                    radius: th.sysmonPillRadius || 8
                                    color: th.panelCardBg
                                    border.width: th.controlBorderWidth || 1
                                    border.color: th.panelCardBorder

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: th.sysmonPillMargin || 8
                                        spacing: 2

                                        Text {
                                            text: "CPU USAGE"
                                            color: th.text
                                            font.pixelSize: th.panelCardSmallSize || 9
                                            font.bold: true
                                            font.family: th.fontFamily
                                        }

                                        Item {
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            property int gaugeSz: Math.max(80, Math.min(120, height * 0.9))
                                            Components.CircularGauge {
                                                anchors.centerIn: parent
                                                size: parent.gaugeSz
                                                strokeWidth: Math.max(6, parent.gaugeSz / 10)
                                                value: service.data.cpu ? service.data.cpu.util : 0
                                                subValue: service.data.cpu ? (service.data.cpu.temp || 0).toFixed(0) + "°C" : ""
                                            }
                                        }
                                    }
                                }

                                // Top CPU Processes pill/card (right of gauge)
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: th.sysmonPillRadius || 8
                                    color: th.panelCardBg
                                    border.width: th.controlBorderWidth || 1
                                    border.color: th.panelCardBorder

                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: th.sysmonPillMargin || 8
                                        spacing: 2

                                        Text {
                                            text: "Top CPU Processes"
                                            color: th.text
                                            font.pixelSize: th.panelCardSmallSize || 10
                                            font.bold: true
                                            font.family: th.fontFamily
                                        }

                                        // Compact table: Column avoids ColumnLayout row spacing inflation.
                                        Column {
                                            Layout.fillWidth: true
                                            spacing: 0

                                            Rectangle {
                                                width: parent.width
                                                height: 16
                                                color: th.panelTabActiveBg || Qt.rgba(0.55, 0.70, 0.96, 0.18)
                                                Row {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 4
                                                    anchors.rightMargin: 4
                                                    spacing: 6
                                                    Text { width: 40; height: parent.height; text: "PID"; color: th.text; font.pixelSize: 8; font.bold: true; font.family: th.fontFamily; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                                                    Text { width: parent.width - 40 - 44 - 44 - 18; height: parent.height; text: "App"; color: th.text; font.pixelSize: 8; font.bold: true; font.family: th.fontFamily; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                                                    Text { width: 44; height: parent.height; text: "CPU%"; color: th.text; font.pixelSize: 8; font.bold: true; font.family: th.fontFamily; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                                                    Text { width: 44; height: parent.height; text: "RAM%"; color: th.text; font.pixelSize: 8; font.bold: true; font.family: th.fontFamily; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                                                }
                                            }

                                            Repeater {
                                                model: service.data.top_processes ? service.data.top_processes.slice(0, 8) : []
                                                delegate: Item {
                                                    width: parent.width
                                                    height: 14
                                                    Rectangle {
                                                        anchors.fill: parent
                                                        color: index % 2 === 0 ? "transparent" : Qt.rgba(1, 1, 1, 0.03)
                                                    }
                                                    Row {
                                                        anchors.fill: parent
                                                        anchors.leftMargin: 4
                                                        anchors.rightMargin: 4
                                                        spacing: 6
                                                        Text { width: 40; height: parent.height; text: modelData.pid; color: th.text; font.pixelSize: 8; font.family: th.fontFamily; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                                                        Text { width: parent.width - 40 - 44 - 44; height: parent.height; text: modelData.name; color: th.text; font.pixelSize: 8; font.family: th.fontFamily; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                                                        Text { width: 44; height: parent.height; text: (modelData.cpu || 0).toFixed(1) + "%"; color: th.accent; font.pixelSize: 8; font.family: th.fontFamily; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                                                        Text { width: 44; height: parent.height; text: (modelData.mem || 0).toFixed(1) + "%"; color: th.text; font.pixelSize: 8; font.family: th.fontFamily; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // 3. Wide CPU Usage History pill (full width of card, generous fixed height for chart so it is not squished/cut off)
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 140  // fixed h gives chart ~110-120px after title/margins; full remaining pane space is not split with bottom filler
                                radius: th.sysmonPillRadius || 8
                                color: th.panelCardBg
                                border.width: th.controlBorderWidth || 1
                                border.color: th.panelCardBorder
                                clip: false  // no overflow-hidden; chart + grid labels must fit inside pill borders

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: th.sysmonPillMargin || 8  // consistent padding
                                    spacing: 2

                                    Text {
                                        text: "CPU Usage History"
                                        color: th.text
                                        font.pixelSize: th.panelCardSmallSize || 10
                                        font.bold: true
                                        font.family: th.fontFamily
                                    }

                                    Components.Sparkline {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        history: service.cpuHistory
                                        fixedRange: true
                                        minValue: 0
                                        maxValue: 100
                                        drawGrid: true
                                        gridStep: 10
                                        chartTitle: ""
                                        titleColor: "white"
                                        lineColor: "#7aa2f7"
                                        fillColor: Qt.rgba(0.48, 0.64, 0.97, 0.28)
                                        leftPadding: 30
                                        lineWidth: 1.2
                                    }
                                }
                            }

                            Item { Layout.fillHeight: true }
                        }
                    }
                }

                // === GPU TAB ===
                Item {
                    width: parent.width
                    height: parent.height
                    visible: root.currentTab === 1
                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 8

                        // 1. GPU Summary Pill at the very top. Title top-left.
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 85
                            radius: th.sysmonPillRadius || 8
                            color: th.panelCardBg
                            border.width: th.controlBorderWidth || 1
                            border.color: th.panelCardBorder

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: th.sysmonPillMargin || 8
                                spacing: 4

                                Text {
                                    text: "GPU SUMMARY"
                                    color: th.text
                                    font.pixelSize: th.panelCardSmallSize || 10
                                    font.bold: true
                                    font.family: th.fontFamily
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10
                                    ColumnLayout {
                                        spacing: 1
                                        Text { text: "Model: " + (service.data.gpu_info && service.data.gpu_info.name ? service.data.gpu_info.name : "NVIDIA"); color: th.subtext; font.pixelSize: 9; font.family: th.fontFamily }
                                        Text { text: "VRAM: " + (service.data.gpu ? ((service.data.gpu.vram_total || 0)/1024).toFixed(0) + " GB" : "--"); color: th.subtext; font.pixelSize: 9; font.family: th.fontFamily }
                                        Text { text: "Driver: " + (service.data.gpu_info && service.data.gpu_info.driver ? service.data.gpu_info.driver : "--"); color: th.subtext; font.pixelSize: 9; font.family: th.fontFamily }
                                    }
                                    Item { Layout.fillWidth: true }
                                    Text {
                                        text: (service.data.gpu ? (service.data.gpu.util || 0).toFixed(0) : "0") + "%"
                                        color: th.text
                                        font.pixelSize: 22
                                        font.bold: true
                                        font.family: th.fontFamily
                                    }
                                }
                            }
                        }

                        // 2. Horizontal layout below summary: Gauge left, Top GPU Processes right.
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 160
                            spacing: 8

                            // GPU Usage Gauge (left, in pill)
                            Rectangle {
                                Layout.preferredWidth: 180
                                Layout.fillHeight: true
                                radius: th.sysmonPillRadius || 8
                                color: th.panelCardBg
                                border.width: th.controlBorderWidth || 1
                                border.color: th.panelCardBorder

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: th.sysmonPillMargin || 8
                                    spacing: 2

                                    Text {
                                        text: "GPU USAGE"
                                        color: th.text
                                        font.pixelSize: th.panelCardSmallSize || 9
                                        font.bold: true
                                        font.family: th.fontFamily
                                    }

                                    Item {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        property int gaugeSz: Math.max(80, Math.min(120, height * 0.9))
                                        Components.CircularGauge {
                                            anchors.centerIn: parent
                                            size: parent.gaugeSz
                                            strokeWidth: Math.max(6, parent.gaugeSz / 10)
                                            value: service.data.gpu ? service.data.gpu.util : 0
                                            subValue: service.data.gpu ? (service.data.gpu.temp || 0).toFixed(0) + "°C" : ""
                                            lowColor: th.gaugeLow || "#a6e3a1"
                                            midColor: th.gaugeMid || "#f9e2af"
                                            highColor: th.gaugeHigh || "#f38ba8"
                                        }
                                    }
                                }
                            }

                            // Top GPU Processes pill/card (right of gauge) - GPU specific
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: th.sysmonPillRadius || 8
                                color: th.panelCardBg
                                border.width: th.controlBorderWidth || 1
                                border.color: th.panelCardBorder

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: th.sysmonPillMargin || 8
                                    spacing: 2

                                    Text {
                                        text: "Top GPU Processes"
                                        color: th.text
                                        font.pixelSize: th.panelCardSmallSize || 10
                                        font.bold: true
                                        font.family: th.fontFamily
                                    }

                                    Column {
                                        Layout.fillWidth: true
                                        spacing: 0

                                        Rectangle {
                                            width: parent.width
                                            height: 16
                                            color: th.panelTabActiveBg || Qt.rgba(0.55, 0.70, 0.96, 0.18)
                                            Row {
                                                anchors.fill: parent
                                                anchors.leftMargin: 4
                                                anchors.rightMargin: 4
                                                spacing: 6
                                                Text { width: 40; height: parent.height; text: "PID"; color: th.text; font.pixelSize: 8; font.bold: true; font.family: th.fontFamily; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                                                Text { width: parent.width - 40 - 56 - 12; height: parent.height; text: "App"; color: th.text; font.pixelSize: 8; font.bold: true; font.family: th.fontFamily; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                                                Text { width: 56; height: parent.height; text: "VRAM"; color: th.text; font.pixelSize: 8; font.bold: true; font.family: th.fontFamily; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                                            }
                                        }

                                        Repeater {
                                            model: service.data.top_gpu ? service.data.top_gpu.slice(0, 8) : []
                                            delegate: Item {
                                                width: parent.width
                                                height: 14
                                                Rectangle {
                                                    anchors.fill: parent
                                                    color: index % 2 === 0 ? "transparent" : Qt.rgba(1, 1, 1, 0.03)
                                                }
                                                Row {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 4
                                                    anchors.rightMargin: 4
                                                    spacing: 6
                                                    Text { width: 40; height: parent.height; text: modelData.pid; color: th.text; font.pixelSize: 8; font.family: th.fontFamily; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                                                    Text { width: parent.width - 40 - 56; height: parent.height; text: modelData.name; color: th.text; font.pixelSize: 8; font.family: th.fontFamily; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                                                    Text { width: 56; height: parent.height; text: (modelData.vram || 0) + " MiB"; color: th.accent; font.pixelSize: 8; font.family: th.fontFamily; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // 3. Wide GPU Usage History pill (full width of card, generous fixed height for chart so it is not squished/cut off)
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 140  // fixed h gives chart ~110-120px after title/margins; full remaining pane space is not split with bottom filler
                            radius: th.sysmonPillRadius || 8
                            color: th.panelCardBg
                            border.width: th.controlBorderWidth || 1
                            border.color: th.panelCardBorder
                            clip: false  // no overflow-hidden; chart + grid labels must fit inside pill borders

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: th.sysmonPillMargin || 8  // consistent padding
                                spacing: 2

                                Text {
                                    text: "GPU Usage History"
                                    color: th.text
                                    font.pixelSize: th.panelCardSmallSize || 10
                                    font.bold: true
                                    font.family: th.fontFamily
                                }

                                Components.Sparkline {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    history: service.gpuHistory
                                    fixedRange: true
                                    minValue: 0
                                    maxValue: 100
                                    drawGrid: true
                                    gridStep: 10
                                    chartTitle: ""
                                    titleColor: "white"
                                    lineColor: "#a6e3a1"
                                    fillColor: Qt.rgba(0.65, 0.89, 0.63, 0.25)
                                    leftPadding: 30
                                    lineWidth: 1.2
                                }
                            }
                        }

                        Item { Layout.fillHeight: true }
                    }
                }

                // === MEMORY TAB ===
                Item {
                    width: parent.width
                    height: parent.height
                    visible: root.currentTab === 2
                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 8

                        // 1. Memory Summary Pill
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 95
                            radius: th.sysmonPillRadius || 8
                            color: th.panelCardBg
                            border.width: th.controlBorderWidth || 1
                            border.color: th.panelCardBorder

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: th.sysmonPillMargin || 8
                                spacing: 4

                                Text {
                                    text: "MEMORY SUMMARY"
                                    color: th.text
                                    font.pixelSize: th.panelCardSmallSize || 10
                                    font.bold: true
                                    font.family: th.fontFamily
                                }

                                RowLayout {
                                    spacing: 12
                                    Layout.fillWidth: true

                                    ColumnLayout {
                                        spacing: 1
                                        Text { text: "Total: " + (service.data.memory ? (service.data.memory.ram_total || 0) + " MiB" : "--"); color: th.subtext; font.pixelSize: 9; font.family: th.fontFamily }
                                        Text { text: "Used: " + (service.data.memory ? (service.data.memory.ram_used || 0) + " MiB" : "--"); color: th.subtext; font.pixelSize: 9; font.family: th.fontFamily }
                                        Text { text: "Avail: " + (service.data.memory ? ((service.data.memory.ram_total || 0) - (service.data.memory.ram_used || 0)) + " MiB" : "--"); color: th.subtext; font.pixelSize: 9; font.family: th.fontFamily }
                                    }

                                    Item { Layout.fillWidth: true }

                                    Text {
                                        text: (service.data.memory ? (service.data.memory.ram_pct || 0).toFixed(0) : "0") + "%"
                                        color: th.text
                                        font.pixelSize: 28
                                        font.bold: true
                                        font.family: th.fontFamily
                                    }
                                }

                                // progress bar
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 6
                                    radius: 3
                                    color: th.surface || "#2a2a3a"
                                    Rectangle {
                                        width: parent.width * Math.min(1, (service.data.memory ? (service.data.memory.ram_pct || 0) : 0) / 100)
                                        height: parent.height
                                        radius: 3
                                        color: (service.data.memory && (service.data.memory.ram_pct||0) > 85) ? th.gaugeHigh : (service.data.memory && (service.data.memory.ram_pct||0) > 65) ? th.gaugeMid : th.gaugeLow
                                    }
                                }
                            }
                        }

                        // 2. Swap Usage Pill (separate, immediately below)
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 55
                            radius: th.sysmonPillRadius || 8
                            color: th.panelCardBg
                            border.width: th.controlBorderWidth || 1
                            border.color: th.panelCardBorder

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: th.sysmonPillMargin || 8
                                spacing: 8

                                Text {
                                    text: "SWAP"
                                    color: th.text
                                    font.pixelSize: th.panelCardSmallSize || 10
                                    font.bold: true
                                    font.family: th.fontFamily
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 6
                                    radius: 3
                                    color: th.surface || "#2a2a3a"
                                    Rectangle {
                                        width: parent.width * Math.min(1, (service.data.memory ? (service.data.memory.swap_pct || 0) : 0) / 100)
                                        height: parent.height
                                        radius: 3
                                        color: (service.data.memory && (service.data.memory.swap_pct||0) > 85) ? th.gaugeHigh : (service.data.memory && (service.data.memory.swap_pct||0) > 65) ? th.gaugeMid : th.gaugeLow
                                    }
                                }

                                Text {
                                    text: (service.data.memory ? (service.data.memory.swap_pct || 0).toFixed(0) : "0") + "%"
                                    color: th.text
                                    font.pixelSize: 12
                                    font.bold: true
                                    font.family: th.fontFamily
                                }

                                Text {
                                    text: service.data.memory ? ((service.data.memory.swap_used_mib || 0) + " / " + (service.data.memory.swap_total_mib || 0) + " MiB") : "--"
                                    color: th.subtext
                                    font.pixelSize: 9
                                    font.family: th.fontFamily
                                }
                            }
                        }

                        // 3. Horizontal layout below Swap: left space, right Top Memory Processes
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 140
                            spacing: 8

                            // Left: use the space (combined summary/swap already above)
                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                            }

                            // Right: Top Memory Processes pill/card
                            Rectangle {
                                Layout.preferredWidth: 220
                                Layout.fillHeight: true
                                radius: th.sysmonPillRadius || 8
                                color: th.panelCardBg
                                border.width: th.controlBorderWidth || 1
                                border.color: th.panelCardBorder

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: th.sysmonPillMargin || 8
                                    spacing: 2

                                    Text {
                                        text: "Top Memory Processes"
                                        color: th.text
                                        font.pixelSize: th.panelCardSmallSize || 10
                                        font.bold: true
                                        font.family: th.fontFamily
                                    }

                                    // Header with highlight fill only. Compact table styling (spacing 1 + cell margins for padding).
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 1
                                        Rectangle {
                                            Layout.fillWidth: true; Layout.preferredHeight: 16
                                            color: th.panelTabActiveBg || Qt.rgba(0.55, 0.70, 0.96, 0.18)
                                            RowLayout {
                                                anchors.fill: parent
                                                spacing: 1
                                                Text { text: "PID"; color: th.text; font.pixelSize: 8; font.family: th.fontFamily; Layout.preferredWidth: 42; Layout.leftMargin: 2; Layout.rightMargin: 3; horizontalAlignment: Text.AlignRight }
                                                Text { text: "App"; color: th.text; font.pixelSize: 8; font.family: th.fontFamily; Layout.fillWidth: true; Layout.leftMargin: 3; Layout.rightMargin: 2; horizontalAlignment: Text.AlignLeft }
                                                Text { text: "RAM%"; color: th.text; font.pixelSize: 8; font.family: th.fontFamily; Layout.preferredWidth: 42; Layout.leftMargin: 2; Layout.rightMargin: 3; horizontalAlignment: Text.AlignRight }
                                                Text { text: "Size"; color: th.text; font.pixelSize: 8; font.family: th.fontFamily; Layout.preferredWidth: 52; Layout.leftMargin: 2; Layout.rightMargin: 2; horizontalAlignment: Text.AlignRight }
                                            }
                                        }
                                    }

                                    Repeater {
                                        model: service.data.top_memory ? service.data.top_memory.slice(0, 6) : []
                                        delegate: RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 1
                                            Text { text: modelData.pid; color: th.text; font.pixelSize: 8; font.family: th.fontFamily; Layout.preferredWidth: 42; Layout.leftMargin: 2; Layout.rightMargin: 3; horizontalAlignment: Text.AlignRight }
                                            Text { text: modelData.name; color: th.text; font.pixelSize: 8; font.family: th.fontFamily; Layout.fillWidth: true; Layout.leftMargin: 3; Layout.rightMargin: 2; elide: Text.ElideRight; horizontalAlignment: Text.AlignLeft }
                                            Text { text: modelData.mem.toFixed(1) + "%"; color: th.text; font.pixelSize: 8; font.family: th.fontFamily; Layout.preferredWidth: 42; Layout.leftMargin: 2; Layout.rightMargin: 3; horizontalAlignment: Text.AlignRight }
                                            Text { text: (modelData.rss ? (modelData.rss / 1024).toFixed(0) + "M" : "--"); color: th.text; font.pixelSize: 8; font.family: th.fontFamily; Layout.preferredWidth: 52; Layout.leftMargin: 2; Layout.rightMargin: 2; horizontalAlignment: Text.AlignRight }
                                        }
                                    }
                                }
                            }
                        }

                        // 4. Wide Memory Usage History pill (full width of card, generous fixed height for chart so it is not squished/cut off)
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 140  // fixed h gives chart ~110-120px after title/margins; full remaining pane space is not split with bottom filler
                            radius: th.sysmonPillRadius || 8
                            color: th.panelCardBg
                            border.width: th.controlBorderWidth || 1
                            border.color: th.panelCardBorder
                            clip: false  // no overflow-hidden; chart + grid labels must fit inside pill borders

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: th.sysmonPillMargin || 8  // consistent padding
                                spacing: 2

                                Text {
                                    text: "Memory Usage History"
                                    color: th.text
                                    font.pixelSize: th.panelCardSmallSize || 10
                                    font.bold: true
                                    font.family: th.fontFamily
                                }

                                Components.Sparkline {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    history: service.ramHistory
                                    fixedRange: true
                                    minValue: 0
                                    maxValue: 100
                                    drawGrid: true
                                    gridStep: 10
                                    chartTitle: ""
                                    titleColor: "white"
                                    lineColor: "#7aa2f7"
                                    fillColor: Qt.rgba(0.48, 0.64, 0.97, 0.28)
                                    leftPadding: 30
                                    lineWidth: 1.2
                                }
                            }
                        }

                        Item { Layout.fillHeight: true }
                    }
                }

                // === OTHER TAB (renamed from Storage) ===
                Item {
                    width: parent.width
                    height: parent.height
                    visible: root.currentTab === 3
                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 8

                        // DISK STORAGE (NVMe) - adapted, full width row of gauges
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 100
                            radius: th.sysmonPillRadius || 8
                            color: th.panelCardBg
                            border.width: th.controlBorderWidth || 1
                            border.color: th.panelCardBorder

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: th.sysmonPillMargin || 8
                                spacing: 3

                                Text {
                                    text: "DISK STORAGE (NVMe)"
                                    color: th.text
                                    font.pixelSize: th.panelCardSmallSize || 10
                                    font.bold: true
                                    font.family: th.fontFamily
                                }

                                RowLayout {
                                    spacing: 12
                                    Layout.fillWidth: true

                                    Repeater {
                                        model: (service.data.disks || []).filter(function(d) {
                                            return d.mount === "/" || d.mount === "/run/media/crome/data";
                                        })
                                        delegate: ColumnLayout {
                                            spacing: 1
                                            Components.CircularGauge {
                                                size: 50
                                                value: modelData.pct || 0
                                                label: ""
                                                subValue: (modelData.pct || 0).toFixed(0) + "%"
                                            }
                                            Text {
                                                text: modelData.mount === "/" ? "System" : "Data"
                                                color: th.subtext
                                                font.pixelSize: th.panelCardTinySize || 8
                                                font.family: th.fontFamily
                                                horizontalAlignment: Text.AlignHCenter
                                            }
                                        }
                                    }
                                }
                            }
                        }

                    // CCACHE (below Disk Storage as requested)
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 70
                        radius: th.sysmonPillRadius || 8
                        color: th.panelCardBg
                        border.width: th.controlBorderWidth || 1
                        border.color: th.panelCardBorder

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: th.sysmonPillMargin || 8
                            spacing: 3

                            Text {
                                text: "CCACHE"
                                color: th.text
                                font.pixelSize: th.panelCardSmallSize || 10
                                font.bold: true
                                font.family: th.fontFamily
                            }

                            RowLayout {
                                spacing: 4
                                Layout.fillWidth: true
                                Rectangle {
                                    Layout.preferredWidth: 80
                                    Layout.preferredHeight: 6
                                    radius: 3
                                    color: th.surface || "#2a2a3a"
                                    Rectangle {
                                        width: {
                                            const cur = (service.data.ccache && service.data.ccache.size_gb) || 0
                                            const max = (service.data.ccache && service.data.ccache.max_gb) || 10
                                            return parent.width * Math.min(1, cur / max)
                                        }
                                        height: parent.height
                                        radius: 3
                                        color: th.accent || "#89b4fa"
                                    }
                                }
                                Text {
                                    text: (service.data.ccache ? service.data.ccache.size_gb.toFixed(1) : "0") + "G"
                                    color: th.subtext
                                    font.pixelSize: th.panelCardTinySize || 9
                                    font.family: th.fontFamily
                                }
                            }

                            Text {
                                text: "Hit: " + (service.data.ccache ? service.data.ccache.hit_rate.toFixed(0) + "%" : "--")
                                color: th.subtext
                                font.pixelSize: th.panelCardTinySize || 9
                                font.family: th.fontFamily
                            }
                        }
                    }

                    // optional small network
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 55
                        radius: th.sysmonPillRadius || 8
                        color: th.panelCardBg
                        border.width: th.controlBorderWidth || 1
                        border.color: th.panelCardBorder

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: th.sysmonPillMargin || 8
                            spacing: 1
                            Text {
                                text: "NET (" + (service.data.network ? service.data.network.iface : "?") + ")"
                                color: th.text
                                font.pixelSize: th.panelCardTinySize || 8
                                font.bold: true
                                font.family: th.fontFamily
                            }
                            RowLayout {
                                spacing: 6
                                Layout.fillWidth: true
                                Text { text: "RX " + (service.data.network ? (service.data.network.rx_rate/1024).toFixed(1) : "0") + "KB/s"; color: th.accent || "#89b4fa"; font.pixelSize: 8; font.family: th.fontFamily }
                                Text { text: "TX " + (service.data.network ? (service.data.network.tx_rate/1024).toFixed(1) : "0") + "KB/s"; color: th.gaugeLow || "#a6e3a1"; font.pixelSize: 8; font.family: th.fontFamily }
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }
                }

                // === SYSTEM INFO VIEW ===
                Item {
                    width: parent.width
                    height: parent.height
                    visible: root.currentTab === 4
                    // fills the contentPane; its internal layout is self-contained

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 2  // small inset for the full-tab bg card; inner 10 for list breathing (System Info tab special case)
                        radius: th.panelRadius * 0.6
                        color: th.panelCardBg
                        border.width: th.controlBorderWidth || 1
                        border.color: th.panelCardBorder

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 6

                            Text {
                                text: "crome@crome-dt"
                                font.pixelSize: 14
                                font.bold: true
                                color: th.accent
                                font.family: th.fontFamily
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                height: 1
                                color: Qt.rgba(1,1,1,0.10)
                            }

                            Flickable {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                clip: true
                                contentHeight: sysList.implicitHeight

                                Column {
                                    id: sysList
                                    width: parent.width
                                    spacing: 1

                                    Repeater {
                                        model: root.systemEntries
                                        delegate: Rectangle {
                                            width: parent.width
                                            height: 20
                                            color: valueMa.containsMouse ? th.controlHoverBg || Qt.rgba(1,1,1,0.05) : "transparent"

                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 2
                                                anchors.rightMargin: 6
                                                spacing: 8

                                                Text {
                                                    Layout.preferredWidth: 170
                                                    text: modelData.label + ":"
                                                    color: th.accent
                                                    font.pixelSize: th.panelCardSmallSize || 10
                                                    font.family: th.fontMono || "monospace"
                                                }

                                                Text {
                                                    Layout.fillWidth: true
                                                    text: modelData.value
                                                    color: th.text
                                                    font.pixelSize: th.panelCardSmallSize || 10
                                                    font.family: th.fontMono || "monospace"
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

                        // Refresh button (top-right of the info card)
                        MouseArea {
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.margins: 8
                            width: 58
                            height: 20
                            onClicked: root.refreshSystemInfo()
                            cursorShape: Qt.PointingHandCursor

                            Rectangle {
                                anchors.fill: parent
                                radius: 4
                                color: parent.containsMouse ? Qt.rgba(1,1,1,0.08) : "transparent"
                                border.width: th.controlBorderWidth || 1
                                border.color: Qt.rgba(1,1,1,0.10)
                            }
                            Text {
                                anchors.centerIn: parent
                                text: "Refresh"
                                color: th.accent
                                font.pixelSize: th.panelCardSmallSize || 10
                                font.family: th.fontFamily
                            }
                        }
                    }
                }  // close sysinfo card Rect
                }  // close System Info tab Item
            }  // close contentPane Item (after all 5 tab children)

                // === BOTTOM STATUS (always visible) ===
                RowLayout {
                    Layout.fillWidth: true
                    Item { Layout.fillWidth: true }
                    Text {
                        text: service.lastError !== "" ? service.lastError : service.lastStatus
                        color: service.lastError !== "" ? th.panelErrorText : th.panelStatusText
                        font.pixelSize: th.panelCardSmallSize || 10
                        font.family: th.fontFamily
                    }
                }
            }
        }
    }
