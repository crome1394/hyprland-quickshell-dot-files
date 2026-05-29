import Quickshell
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell.Io as Io

// Use the single source of truth defined in Theme.qml (prevents drift from the bar).
import "."

Item {
    id: root

    Theme { id: th }

    // Glass + color theme now sourced from the shared Theme.qml.
    // (Previously duplicated here with a tiny opacity difference on glassPopupBg.)
    readonly property color glassPopupBg: th.glassPopupBg
    readonly property color glassPopupBorder: th.glassPopupBorder
    readonly property color glassPopupHighlight: th.glassPopupHighlight
    readonly property color text: th.text
    readonly property color subtext: th.subtext
    readonly property color overlay: th.overlay
    readonly property color accent: th.accent
    readonly property color surface: th.surface

    readonly property bool open: helpWindow.visible
    property int currentTab: 0
    property string bindFilter: ""

    property string _rawLuaText: ""
    property var _parsedBinds: []
    property var _parsedEnv: []

    property string systemOutput: ""
    property bool systemDirty: true

    function toggle() {
        if (helpWindow.visible) hide()
        else show()
    }

    function show() {
        const sw = helpWindow.screen ? helpWindow.screen.width : 1920
        const sh = helpWindow.screen ? helpWindow.screen.height : 1080
        helpWindow.x = Math.max(40, (sw - helpWindow.width) / 2)
        helpWindow.y = Math.max(40, (sh - helpWindow.height) / 2)
        helpWindow.visible = true
        refreshLua()
        if (currentTab === 2 && systemDirty) refreshSystemInfo()
    }

    function hide() { helpWindow.visible = false }

    function refreshLua() {
        hyprLua.path = ""
        hyprLua.path = "/home/crome/.config/hypr/hyprland.lua"
        Qt.callLater(function() {
            _rawLuaText = hyprLua.text()
            _parsedBinds = parseKeybinds(_rawLuaText)
            _parsedEnv = parseEnvVars(_rawLuaText)
        })
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

    Io.FileView {
        id: hyprLua
        path: "/home/crome/.config/hypr/hyprland.lua"
        preload: true
        blockLoading: false
    }

    Component.onCompleted: {
        _rawLuaText = hyprLua.text()
        _parsedBinds = parseKeybinds(_rawLuaText)
        _parsedEnv = parseEnvVars(_rawLuaText)
    }

    function parseKeybinds(text) {
        if (!text) return []
        const lines = text.split("\n")
        const out = []
        for (let i = 0; i < lines.length; i++) {
            let line = lines[i].trim()
            if (!line.startsWith("hl.bind(")) continue
            const m = line.match(/^hl\.bind\(\s*(.+?)\s*,\s*(.+?)(?:\s*,\s*(\{[^}]*\}))?\s*\)\s*(?:--\s*(.*))?$/)
            if (!m) continue
            let keyExpr = m[1].trim()
            let actionExpr = m[2].trim()
            let comment = (m[4] || "").trim()

            keyExpr = keyExpr.replace(/mainMod\s*\.\.\s*["']\s*\+\s*["']/g, "SUPER + ")
            keyExpr = keyExpr.replace(/mainMod\s*\.\.\s*/g, "SUPER + ")
            keyExpr = keyExpr.replace(/^["']|["']$/g, "")

            let nice = actionExpr
            if (actionExpr.indexOf("exec_cmd") !== -1) {
                const em = actionExpr.match(/exec_cmd\(\s*["']([^"']+)["']/)
                if (em) {
                    const cmd = em[1]
                    if (cmd.indexOf("volume.sh") !== -1) nice = "Volume control"
                    else if (cmd.indexOf("media-player-controls") !== -1) nice = "Media control"
                    else if (cmd.indexOf("brightnessctl") !== -1) nice = "Brightness"
                    else if (cmd.indexOf("playerctl") !== -1) nice = "Player control"
                    else if (cmd.indexOf("flameshot") !== -1) nice = "Screenshot"
                    else if (cmd.indexOf("vicinae") !== -1) nice = "Toggle launcher"
                    else if (cmd.indexOf("nwg-drawer") !== -1) nice = "App drawer"
                    else if (cmd.indexOf("brave") !== -1) nice = "Launch Brave"
                    else if (cmd.indexOf("flatpak run") !== -1) nice = "Launch SpeedCrunch"
                    else if (cmd.indexOf("toggle-monitor-dpms") !== -1) nice = "Toggle monitor DPMS"
                    else if (cmd.indexOf("hyprctl reload") !== -1) nice = "Reload Hyprland"
                    else if (cmd.indexOf("systemctl") !== -1 || cmd.indexOf("shutdown") !== -1 || cmd.indexOf("reboot") !== -1) nice = "Power action"
                    else nice = "Launch " + cmd.split("/").pop()
                } else nice = "Execute command"
            } else if (actionExpr.indexOf("window.close") !== -1) nice = "Close window"
            else if (actionExpr.indexOf("window.float") !== -1) nice = "Toggle floating"
            else if (actionExpr.indexOf("window.pseudo") !== -1) nice = "Pseudo-tile"
            else if (actionExpr.indexOf("focus") !== -1) {
                const ws = actionExpr.match(/workspace\s*=\s*["']?([^"'\s,}]+)/)
                nice = ws ? "Workspace " + ws[1] : "Move focus"
            } else if (actionExpr.indexOf("window.move") !== -1) {
                const ws = actionExpr.match(/workspace\s*=\s*["']?([^"'\s,}]+)/)
                nice = ws ? "Move window to " + ws[1] : "Move window"
            } else if (actionExpr.indexOf("layout") !== -1) nice = "Toggle split"
            else if (actionExpr.indexOf("workspace.toggle_special") !== -1) nice = "Toggle special workspace"
            else if (actionExpr.indexOf("mouse_down") !== -1 || actionExpr.indexOf("mouse_up") !== -1) nice = "Scroll workspaces"
            else if (actionExpr.indexOf("mouse:272") !== -1) nice = "Move window (drag)"
            else if (actionExpr.indexOf("mouse:273") !== -1) nice = "Resize window (drag)"
            else if (actionExpr.indexOf("dsp.exit") !== -1) nice = "Exit Hyprland"

            out.push({ key: keyExpr, action: nice, comment: comment })
        }
        return out
    }

    function parseEnvVars(text) {
        if (!text) return []
        const lines = text.split("\n")
        const out = []
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i].trim()
            if (!line.startsWith("hl.env(")) continue
            const m = line.match(/^hl\.env\(\s*["']([^"']+)["']\s*,\s*["']([^"']*)["']\s*\)\s*(?:--\s*(.*))?$/)
            if (m) out.push({ key: m[1], value: m[2], comment: (m[3] || "").trim() })
        }
        return out
    }

    function refreshSystemInfo() {
        systemProcess.running = false
        systemProcess.running = true
        systemDirty = false
    }

    Io.Process {
        id: systemProcess
        command: ["fastfetch"]
        running: false
        stdout: Io.SplitParser {
            splitMarker: "\n"
            onRead: (line) => { systemOutput += line + "\n" }
        }
        onStarted: systemOutput = ""
        onExited: (code) => {
            if (code !== 0 && systemOutput === "")
                systemOutput = "fastfetch exited with code " + code
        }
    }

    PanelWindow {
        id: helpWindow
        visible: false
        color: "transparent"
        exclusiveZone: 0
        width: 1060
        height: 720
        

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
                    Text { text: "ALT + /  ·  live from hyprland.lua"; color: root.overlay; font.pixelSize: 12 }
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

                    Flickable {
                        visible: root.currentTab === 0; anchors.fill: parent
                        contentHeight: bindsCol.implicitHeight + 20; clip: true
                        Column {
                            id: bindsCol; width: parent.width; spacing: 1
                            Repeater {
                                model: root.filteredBinds()
                                delegate: Rectangle {
                                    width: bindsCol.width; height: 26; radius: 4
                                    color: rma.containsMouse ? Qt.rgba(1,1,1,0.03) : "transparent"
                                    MouseArea { id: rma; anchors.fill: parent; hoverEnabled: true }
                                    RowLayout {
                                        anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8; spacing: 12
                                        Text { Layout.preferredWidth: 240; text: modelData.key; color: root.accent; font.pixelSize: 12; font.family: "monospace"; elide: Text.ElideRight }
                                        Text { Layout.fillWidth: true; text: modelData.action + (modelData.comment ? "  — " + modelData.comment : ""); color: root.text; font.pixelSize: 12; elide: Text.ElideRight }
                                    }
                                }
                            }
                        }
                    }

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
                                        anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8; spacing: 16
                                        Text { Layout.preferredWidth: 300; text: modelData.key; color: root.accent; font.pixelSize: 12; font.family: "monospace" }
                                        Text { Layout.fillWidth: true; text: "\"" + modelData.value + "\"" + (modelData.comment ? "  — " + modelData.comment : ""); color: root.text; font.pixelSize: 12; elide: Text.ElideRight }
                                    }
                                }
                            }
                        }
                    }

                    Flickable {
                        visible: root.currentTab === 2; anchors.fill: parent
                        contentHeight: sysText.implicitHeight + 20; clip: true
                        TextEdit {
                            id: sysText; width: parent.width - 10
                            text: root.systemOutput || "Loading..."; color: root.text
                            font.pixelSize: 11; font.family: "NotoSansMono, monospace"
                            readOnly: true; selectByMouse: true; wrapMode: TextEdit.NoWrap
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: root.currentTab === 0 ? (root.filteredBinds().length + " bindings  ·  open menu or click Reload file")
                            : root.currentTab === 1 ? (root._parsedEnv.length + " environment variables")
                            : "fastfetch"
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