import Quickshell
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell.Io as Io

// =============================================================================
// HelpMenu.qml — Rich centered help overlay for Hyprland keybindings
// =============================================================================
//
// This is the polished version originally developed in ~/.config/quickshell-help.
// It was integrated into the main bar config so it can be toggled via IPC
// (`qs ipc call help toggle`) from hyprland.lua without launching a second qs process.
//
// Features:
//   - Tab 0: Key Bindings (parsed live from hyprland.lua with colored key pills)
//   - Tab 1: Environment variables (from hl.env() lines)
//   - Tab 2: System info (fastfetch + clickable copy-to-clipboard values + logo)
//
// The component creates its own PanelWindow so it can float centered on screen
// independently of the main bar.
// =============================================================================

// Use the single source of truth defined in Theme.qml (prevents color drift).
import "."

Item {
    id: root

    Theme { id: th }

    // --- Themed colors (sourced from central Theme.qml) ---
    readonly property color glassPopupBg: th.glassPopupBg
    readonly property color glassPopupBorder: th.glassPopupBorder
    readonly property color glassPopupHighlight: th.glassPopupHighlight
    readonly property color text: th.text
    readonly property color subtext: th.subtext
    readonly property color overlay: th.overlay
    readonly property color accent: th.accent
    readonly property color surface: th.surface

    // --- Public API ---
    property bool open: helpWindow.visible
    signal opened()
    signal closed()

    function toggle() {
        if (helpWindow.visible) hide()
        else show()
    }

    function show() { ... }   // (see implementation below)
    function hide() { helpWindow.visible = false }

    // --- Internal State ---
    property int currentTab: 0
    property string bindFilter: ""

    // Raw + parsed data from hyprland.lua
    property string _rawLuaText: ""
    property var _parsedBinds: []
    property var _parsedEnv: []

    // System info (fastfetch) state
    property string systemOutput: ""
    property bool systemDirty: true
    property var systemEntries: []
    property string copiedValue: ""

    function show() {
        const sw = helpWindow.screen ? helpWindow.screen.width : 1920
        const sh = helpWindow.screen ? helpWindow.screen.height : 1080
        if (typeof helpWindow.x === "number") {
            helpWindow.x = Math.max(40, (sw - helpWindow.width) / 2)
            helpWindow.y = Math.max(40, (sh - helpWindow.height) / 2)
        }
        helpWindow.visible = true
        if (currentTab === 2 && systemDirty) refreshSystemInfo()
    }

    function hide() {
        helpWindow.visible = false
    }

    function refreshLua() {
        hyprCat.running = false
        hyprCat.command = ["cat", "/home/crome/.config/hypr/hyprland.lua"]
        hyprCat.running = true
    }

    Io.Process {
        id: hyprCat
        running: false
        stdout: Io.StdioCollector {
            onTextChanged: {
                if (text && text.length > 50) {
                    _rawLuaText = text
                    _parsedBinds = parseKeybinds(text)
                    _parsedEnv = parseEnvVars(text)
                }
            }
        }
    }

    Component.onCompleted: {
        refreshLua()
    }

    function parseKeybinds(text) {
        if (!text) return []
        const lines = text.split("\n")
        const out = []
        for (let i = 0; i < lines.length; i++) {
            const originalLine = lines[i]
            let line = originalLine.trim()
            if (!line.includes("hl.bind(")) continue
            if (line.startsWith("--hl.bind") || line.startsWith("----hl.bind")) continue
            if (!originalLine.includes("--#")) continue

            const bindIdx = line.indexOf("hl.bind(")
            if (bindIdx === -1) continue
            const afterOpen = line.substring(bindIdx + 8)
            let depth = 0
            let keyEnd = -1
            for (let j = 0; j < afterOpen.length; j++) {
                const ch = afterOpen[j]
                if (ch === '(' || ch === '{' || ch === '[') depth++
                else if (ch === ')' || ch === '}' || ch === ']') depth--
                else if (ch === ',' && depth === 0) {
                    keyEnd = j
                    break
                }
            }
            if (keyEnd === -1) continue
            let keyExpr = afterOpen.substring(0, keyEnd).trim()
            keyExpr = keyExpr.replace(/mainMod\s*\.\.\s*/g, "SUPER + ")
            keyExpr = keyExpr.replace(/["']/g, "")
            keyExpr = keyExpr.replace(/\s*\+\s*/g, " + ")
            keyExpr = keyExpr.replace(/\+\s*\+\s*/g, "+ ")
            keyExpr = keyExpr.replace(/\s+/g, " ").trim()

            let description = ""
            const descMatch = originalLine.match(/--#\s*(.+)$/)
            if (descMatch) description = descMatch[1].trim()

            out.push({ key: keyExpr, action: description, comment: "" })
        }
        return out
    }

    function parseEnvVars(text) {
        if (!text) return []
        const lines = text.split("\n")
        const out = []
        for (let i = 0; i < lines.length; i++) {
            const originalLine = lines[i]
            let line = originalLine.trim()
            if (!line.includes("hl.env(")) continue
            if (line.startsWith("--hl.env") || line.startsWith("----hl.env")) continue
            const m = line.match(/^hl\.env\(\s*["']([^"']+)["']\s*,\s*["']([^"']*)["']\s*\)/)
            if (!m) continue
            let comment = ""
            const hashMatch = originalLine.match(/--#\s*(.+)$/)
            if (hashMatch) comment = hashMatch[1].trim()
            else {
                const oldMatch = originalLine.match(/--\s*(.+)$/)
                if (oldMatch) comment = oldMatch[1].trim()
            }
            out.push({ key: m[1], value: m[2], comment: comment })
        }
        return out
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

    function keyPillColor(key) {
        const k = (key || "").toUpperCase().trim()
        if (k.includes("SUPER") || k.includes("WIN") || k.includes("META")) return "#89b4fa"
        if (k.includes("SHIFT")) return "#fab387"
        if (k.includes("CTRL") || k.includes("CONTROL")) return "#cba6f7"
        if (k.includes("ALT")) return "#94e2d5"
        return "#6c7086"
    }

    function keyPillTextColor(key) {
        return keyPillColor(key) === "#6c7086" ? "#ffffff" : "#000000"
    }

    function refreshSystemInfo() {
        systemProcess.running = false
        systemProcess.running = true
        systemDirty = false
        copiedValue = ""
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
            onRead: (line) => { systemOutput += line + "\n" }
        }
        onStarted: systemOutput = ""
        onExited: (code) => {
            if (code !== 0 && systemOutput.trim() === "") {
                systemOutput = "Failed to collect system information (exit code " + code + ")"
            } else {
                systemEntries = parseFastfetchOutput(systemOutput)
            }
        }
    }

    function filteredBinds() {
        if (!bindFilter || bindFilter.trim() === "") return _parsedBinds
        const q = bindFilter.toLowerCase()
        return _parsedBinds.filter(function(b) {
            return (b.key && b.key.toLowerCase().indexOf(q) !== -1) ||
                   (b.action && b.action.toLowerCase().indexOf(q) !== -1) ||
                   (b.comment && b.comment.toLowerCase().indexOf(q) !== -1)
        })
    }

    PanelWindow {
        id: helpWindow
        visible: false
        color: "transparent"
        exclusiveZone: 0
        implicitWidth: 1060
        implicitHeight: 720

        Item {
            anchors.fill: parent
            focus: helpWindow.visible
            Keys.onEscapePressed: root.hide()
        }

        MouseArea {
            anchors.fill: parent
            z: -1
            onClicked: root.hide()
        }

        Rectangle {
            anchors.centerIn: parent
            width: parent.width - 40
            height: parent.height - 40
            radius: 18
            color: root.glassPopupBg
            border.width: 1
            border.color: root.glassPopupBorder

            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1.5
                color: root.glassPopupHighlight
                radius: parent.radius
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 18
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "Hyprland Help"; color: root.text; font.pixelSize: 18; font.bold: true }
                    Rectangle { Layout.preferredWidth: 1; Layout.preferredHeight: 18; color: Qt.rgba(1,1,1,0.12) }
                    Text { text: "SUPER + ?  ·  live from hyprland.lua"; color: root.overlay; font.pixelSize: 12 }
                    Item { Layout.fillWidth: true }
                    Rectangle {
                        width: 28; height: 28; radius: 6
                        color: closeMa.containsMouse ? root.surface : "transparent"
                        Text { anchors.centerIn: parent; text: "✕"; color: root.text; font.pixelSize: 14 }
                        MouseArea { id: closeMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.hide() }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true; spacing: 6
                    Repeater {
                        model: [
                            {label: "Key Bindings", tab: 0},
                            {label: "Environment", tab: 1},
                            {label: "System Info", tab: 2}
                        ]
                        delegate: Rectangle {
                            Layout.preferredHeight: 30
                            Layout.preferredWidth: modelData.label.length * 9 + 32
                            radius: 7
                            color: (root.currentTab === modelData.tab) ? Qt.rgba(0.55, 0.70, 0.96, 0.18) : (tma.containsMouse ? root.surface : "transparent")
                            border.width: (root.currentTab === modelData.tab) ? 1 : 0
                            border.color: root.accent
                            Text {
                                anchors.centerIn: parent
                                text: modelData.label
                                color: (root.currentTab === modelData.tab) ? root.accent : root.text
                                font.pixelSize: 13
                                font.bold: (root.currentTab === modelData.tab)
                            }
                            MouseArea {
                                id: tma; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: { root.currentTab = modelData.tab; if (modelData.tab === 2 && root.systemDirty) root.refreshSystemInfo() }
                            }
                        }
                    }
                    Item { Layout.fillWidth: true }
                    Rectangle {
                        visible: root.currentTab === 0
                        Layout.preferredWidth: 240; Layout.preferredHeight: 28; radius: 6
                        color: root.surface; border.width: 1; border.color: Qt.rgba(1,1,1,0.08)
                        TextField {
                            anchors.fill: parent; anchors.margins: 4; verticalAlignment: TextInput.AlignVCenter
                            color: root.text; font.pixelSize: 13
                            onTextChanged: root.bindFilter = text
                            placeholderText: "Filter..."; placeholderTextColor: root.overlay
                            background: Rectangle {
                                color: "transparent"
                                border.width: 0
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true; Layout.fillHeight: true; color: "transparent"

                    // Key Bindings Tab - two column grid
                    Flickable {
                        visible: root.currentTab === 0; anchors.fill: parent
                        contentHeight: bindsGrid.implicitHeight + 20; clip: true

                        GridLayout {
                            id: bindsGrid
                            width: parent.width
                            columns: 2
                            columnSpacing: 16
                            rowSpacing: 2

                            Repeater {
                                model: root.filteredBinds()
                                delegate: Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 26
                                    radius: 4
                                    color: rma.containsMouse ? Qt.rgba(1,1,1,0.03) : "transparent"

                                    MouseArea { id: rma; anchors.fill: parent; hoverEnabled: true }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        spacing: 8

                                        // Colored key pills
                                        Row {
                                            spacing: 4
                                            Repeater {
                                                model: modelData.key.split(/\s*\+\s*/)
                                                delegate: Rectangle {
                                                    height: 20
                                                    width: keyText.implicitWidth + 12
                                                    radius: 5
                                                    color: keyPillColor(modelData)

                                                    Text {
                                                        id: keyText
                                                        anchors.centerIn: parent
                                                        text: modelData
                                                        color: keyPillTextColor(modelData)
                                                        font.pixelSize: 10
                                                        font.family: "monospace"
                                                        font.bold: true
                                                    }
                                                }
                                            }
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.action
                                            color: root.text
                                            font.pixelSize: 12
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Environment Tab
                    Flickable {
                        visible: root.currentTab === 1; anchors.fill: parent
                        contentHeight: envCol.implicitHeight + 20; clip: true
                        Column {
                            id: envCol; width: parent.width; spacing: 2
                            Repeater {
                                model: root._parsedEnv
                                delegate: Rectangle {
                                    width: envCol.width; height: 24; radius: 4
                                    color: ema.containsMouse ? Qt.rgba(1,1,1,0.03) : "transparent"
                                    MouseArea { id: ema; anchors.fill: parent; hoverEnabled: true }
                                    RowLayout {
                                        anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8; spacing: 12
                                        Text {
                                            Layout.preferredWidth: 290
                                            text: modelData.key
                                            color: root.accent
                                            font.pixelSize: 12
                                            font.family: "monospace"
                                        }
                                        Text {
                                            Layout.preferredWidth: 380
                                            text: modelData.value
                                            color: root.accent
                                            font.pixelSize: 12
                                            font.family: "monospace"
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            visible: modelData.comment
                                            text: modelData.comment
                                            color: root.text
                                            font.pixelSize: 12
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // System Info Tab
                    Item {
                        visible: root.currentTab === 2
                        anchors.fill: parent
                        anchors.margins: 10

                        RowLayout {
                            anchors.fill: parent
                            spacing: 20

                            Image {
                                source: "/home/crome/.config/quickshell/cachyos-linux.svg"
                                Layout.preferredWidth: 180
                                Layout.preferredHeight: 180
                                fillMode: Image.PreserveAspectFit
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                spacing: 4

                                Text {
                                    text: "crome@crome-dt"
                                    font.pixelSize: 18
                                    font.bold: true
                                    color: root.accent
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 1
                                    color: root.glassPopupBorder
                                    opacity: 0.5
                                }

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
                                                height: 24
                                                color: valueMa.containsMouse ? Qt.rgba(1,1,1,0.06) : "transparent"
                                                RowLayout {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 4
                                                    anchors.rightMargin: 8
                                                    spacing: 12
                                                    Text {
                                                        Layout.preferredWidth: 210
                                                        text: modelData.label + ":"
                                                        color: root.accent
                                                        font.pixelSize: 12
                                                        font.family: "monospace"
                                                    }
                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: modelData.value
                                                        color: root.text
                                                        font.pixelSize: 12
                                                        font.family: "monospace"
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
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: root.currentTab === 0 ? (root.filteredBinds().length + " bindings  ·  open menu or click Reload file")
                            : root.currentTab === 1 ? (root._parsedEnv.length + " environment variables")
                            : "system info"
                        color: root.overlay; font.pixelSize: 11
                    }
                    Item { Layout.fillWidth: true }
                    Rectangle {
                        visible: root.currentTab === 2
                        width: 68; height: 22; radius: 5
                        color: refMa.containsMouse ? root.surface : "transparent"
                        border.width: 1; border.color: Qt.rgba(1,1,1,0.1)
                        Text { anchors.centerIn: parent; text: "Refresh"; color: root.accent; font.pixelSize: 11 }
                        MouseArea { id: refMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.refreshSystemInfo() }
                    }
                    Rectangle {
                        visible: root.currentTab === 0
                        width: 68; height: 22; radius: 5
                        color: refLuaMa.containsMouse ? root.surface : "transparent"
                        border.width: 1; border.color: Qt.rgba(1,1,1,0.1)
                        Text { anchors.centerIn: parent; text: "Reload file"; color: root.accent; font.pixelSize: 11 }
                        MouseArea {
                            id: refLuaMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: root.refreshLua()
                        }
                    }
                }
            }
        }
    }
}