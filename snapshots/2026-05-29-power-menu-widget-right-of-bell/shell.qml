import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray
import Quickshell.Io as Io

PanelWindow {
    id: bar

    anchors.top: true
    anchors.left: true
    anchors.right: true
    implicitHeight: 54   // Increased for ultrawide readability (was 46)
    color: "transparent"

    // ===== Theme =====
    property color bg: "#3B3B3F"
    property color surface: "#313244"
    property color text: "#cdd6f4"
    property color subtext: "#a6adc8"
    property color overlay: "#6c7086"
    property color accent: "#89b4fa"
    property color todayBg: "#89b4fa"
    property color weekday: "#ff5c5c"
    property color clock: "#ffffff"
    property color muted: "#f38ba8"
    property int barRadius: 14
    property int sideMargin: 10

    // ===== Glassmorphic Theme =====
    // Frosted glass / acrylic style for a more premium, modern look
    readonly property color glassBg: Qt.rgba(0.08, 0.08, 0.10, 0.82)
    readonly property color glassBorder: Qt.rgba(1, 1, 1, 0.10)
    readonly property color glassHighlight: Qt.rgba(1, 1, 1, 0.22)
    readonly property color glassPillBg: Qt.rgba(0.06, 0.06, 0.08, 0.75)
    readonly property color glassHover: Qt.rgba(0.15, 0.15, 0.18, 0.65)

    // Dedicated glassmorphic popup styling (slightly more opaque than the bar for readability)
    readonly property color glassPopupBg: Qt.rgba(0.07, 0.07, 0.09, 0.90)
    readonly property color glassPopupBorder: Qt.rgba(1, 1, 1, 0.13)
    readonly property color glassPopupHighlight: Qt.rgba(1, 1, 1, 0.18)

    // Tray menu button type enums (safe local mirrors of QsMenuButtonType)
    readonly property int menuBtnNone: 0
    readonly property int menuBtnCheck: 1
    readonly property int menuBtnRadio: 2

    // ===== Workspaces (eww migration) =====
    // Yellow hover shade taken from eww working scss (rgb(253, 249, 219))
    readonly property color wsHoverYellow: "#fdf9db"
    readonly property color wsActiveBg: "#1e1e1e"
    readonly property color wsText: "#64748b"
    readonly property color wsActiveText: "#e2e8f0"

    // Glassmorphic pill defaults (translucent backgrounds + light borders)
    readonly property color pillBg: bar.glassPillBg
    readonly property color pillBorder: Qt.rgba(1, 1, 1, 0.08)
    readonly property int pillRadius: 10

    property var hoveredWorkspace: null

    function getWsIcon(id) {
        switch (id) {
            case 1: return "";  // code
            case 2: return "🦁";
            case 3: return "";  // chat
            case 4: return "";  // browser
            case 5: return "🕹";  // game
            case 6: return "";
            case 7: return "󰨞";
            case 8: return "󰈹";
            case 9: return "";  // term
            case 10: return "";
            default: return "󰈸";
        }
    }

    property var shownWorkspaces: []

    function updateShownWorkspaces() {
        if (!Hyprland.workspaces || !Hyprland.workspaces.values) {
            bar.shownWorkspaces = [];
            return;
        }
        const filtered = Hyprland.workspaces.values.filter(function(w) {
            if (!w || w.id <= 0) return false;
            let hasWindows = false;
            if (w.toplevels) {
                if (typeof w.toplevels.count === "number") hasWindows = w.toplevels.count > 0;
                else if (w.toplevels.values && typeof w.toplevels.values.length === "number") hasWindows = w.toplevels.values.length > 0;
            }
            return hasWindows || w.active || w.focused;
        });
        filtered.sort(function(a, b) { return a.id - b.id; });
        bar.shownWorkspaces = filtered;
    }

    // ===== NOTIFICATIONS (swaync-backed bell widget) =====
    // Uses swaync-client -s (subscribe) for live count + DND state.
    // This is purely event-driven (no polling timers). The client process
    // only emits when swaync has changes. Keeps resource use minimal.
    QtObject {
        id: notif
        property int count: 0
        property bool dnd: false
        property bool inhibited: false
        // icon computed from state (using common nerd font bell glyphs)
        readonly property string icon: {
            if (dnd) return notif.count > 0 ? "󰂠" : "󰪓";  // dnd variants
            return notif.count > 0 ? "󱅫" : "󰂜";            // normal bell
        }
    }

    function switchToRelative(delta) {
        if (!bar.shownWorkspaces || bar.shownWorkspaces.length === 0) return;
        const activeId = (Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.id) ? Hyprland.focusedWorkspace.id : 1;
        let idx = -1;
        for (let i = 0; i < bar.shownWorkspaces.length; i++) {
            if (bar.shownWorkspaces[i].id === activeId) { idx = i; break; }
        }
        if (idx < 0) idx = 0;
        let newIdx = idx + delta;
        if (newIdx < 0) newIdx = 0;
        if (newIdx >= bar.shownWorkspaces.length) newIdx = bar.shownWorkspaces.length - 1;
        const target = bar.shownWorkspaces[newIdx];
        if (target && target.activate) target.activate();
    }

    Component.onCompleted: {
        bar.updateShownWorkspaces();
        audio.refreshDevices();
    }

    Connections {
        target: Hyprland.workspaces
        function onValuesChanged() { bar.updateShownWorkspaces(); }
    }
    Connections {
        target: Hyprland
        function onFocusedWorkspaceChanged() { bar.updateShownWorkspaces(); }
    }
    // Note: toplevel open/close is reflected via workspaces.values updates in practice (Hyprland IPC pushes changes).
    // If some windows don't appear/disappear immediately, a manual refresh button or extra Hyprland.toplevels connection can be added.

    // ===== AUDIO WIDGET (Pipewire) =====
    PwObjectTracker {
        id: audioTracker
        objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource].filter(function(n){ return !!n; })
    }

    QtObject {
        id: audio
        property int viewMode: 0  // 0=speaker, 1=mic, 2=dual

        property var sinks: []
        property var sources: []

        readonly property var speaker: Pipewire.defaultAudioSink
        readonly property var mic: Pipewire.defaultAudioSource

        readonly property real speakerVolume: (speaker && speaker.audio) ? speaker.audio.volume : 0.0
        readonly property bool speakerMuted: (speaker && speaker.audio) ? speaker.audio.muted : false
        readonly property real micVolume: (mic && mic.audio) ? mic.audio.volume : 0.0
        readonly property bool micMuted: (mic && mic.audio) ? mic.audio.muted : false

        readonly property int speakerPercent: Math.round(speakerVolume * 100)
        readonly property int micPercent: Math.round(micVolume * 100)

        property bool deviceListForSink: true

        function setVolume(node, v) {
            if (node && node.audio) node.audio.volume = Math.max(0.0, Math.min(1.0, v));
        }
        function stepVolume(node, delta) {
            if (!node || !node.audio) return;
            var nv = Math.max(0.0, Math.min(1.0, node.audio.volume + delta));
            node.audio.volume = nv;
        }
        function toggleMute(node) {
            if (node && node.audio) node.audio.muted = !node.audio.muted;
        }
        function cycleView() { viewMode = (viewMode + 1) % 3; }

        function refreshDevices() {
            var s = [], r = [];
            var vals = (Pipewire.nodes && Pipewire.nodes.values) ? Pipewire.nodes.values : [];
            for (var i = 0; i < vals.length; i++) {
                var n = vals[i];
                if (!n || !n.audio) continue;
                var nm = n.description || n.name || n.nickname || "Device";
                if (n.isSink && !n.isStream) s.push({node: n, name: nm});
                else if (!n.isSink && !n.isStream) r.push({node: n, name: nm});
            }
            var cmp = function(a,b){ return a.name.localeCompare(b.name); };
            s.sort(cmp); r.sort(cmp);
            audio.sinks = s;
            audio.sources = r;
        }

        function getCurrentDeviceName(isSink) {
            var def = isSink ? Pipewire.defaultAudioSink : Pipewire.defaultAudioSource;
            if (!def) return "Default";
            return def.description || def.name || def.nickname || "Device";
        }
    }

    Connections {
        target: Pipewire.nodes
        function onValuesChanged() { audio.refreshDevices(); }
    }

    // Reusable volume bar (clickable fill)
    Component {
        id: volumeBar
        Item {
            id: vbar
            property real value: 0.0
            property var onSet: function(v){}
            property color fill: bar.accent
            property color track: bar.surface
            property int barHeight: 6
            implicitWidth: 110
            implicitHeight: barHeight + 4
            Rectangle {
                anchors.centerIn: parent
                width: parent.width
                height: vbar.barHeight
                radius: height / 2
                color: vbar.track
            }
            Rectangle {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, Math.min(parent.width, parent.width * vbar.value))
                height: vbar.barHeight
                radius: height / 2
                color: vbar.fill
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: (m) => { var f = Math.max(0, Math.min(1, m.x / width)); vbar.onSet(f); }
            }
        }
    }

    // Mini volume bar for dual view
    Component {
        id: miniVolumeBar
        Item {
            id: mbar
            property real value: 0.0
            property var onSet: function(v){}
            property color fill: bar.accent
            property color track: bar.surface
            implicitWidth: 48
            implicitHeight: 5
            Rectangle {
                anchors.fill: parent
                radius: 2
                color: mbar.track
            }
            Rectangle {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, Math.min(parent.width, parent.width * mbar.value))
                height: parent.height
                radius: 2
                color: mbar.fill
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: (m) => { var f = Math.max(0, Math.min(1, m.x / width)); mbar.onSet(f); }
            }
        }
    }

    // ===== Bar Content =====
    // Glassmorphic styling throughout bar + all popups (frosted acrylic style)
    // (Easy to revert - the glass* properties control most of it)
    Rectangle {
        id: barBg
        anchors.fill: parent
        anchors.leftMargin: bar.sideMargin
        anchors.rightMargin: bar.sideMargin
        anchors.topMargin: 4
        anchors.bottomMargin: 4
        radius: bar.barRadius
        color: bar.glassBg
        border.width: 1
        border.color: bar.glassBorder

        // Stronger top light edge for classic glassmorphism
        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1.5
            color: bar.glassHighlight
            radius: parent.radius
        }

        // Very subtle bottom inner shadow for depth
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: Qt.rgba(0, 0, 0, 0.25)
            radius: parent.radius
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 20   // Slightly more breathing room for ultrawide
            anchors.rightMargin: 20
            spacing: 14

            // Left side - Workspaces (from eww migration: icons+num, only active/occupied,
            // reactive via Quickshell.Hyprland (no polling), yellow hover, active highlight,
            // scroll wheel, click to focus, hover preview support)
            // Encapsulated in a pill (matching eww module pill style: #1a1a1a bg, rounded, subtle border)
            Rectangle {
                id: workspacesPill
                color: bar.glassPillBg
                radius: bar.pillRadius
                border.width: 1
                border.color: bar.glassBorder

                Layout.preferredWidth: wsRow.implicitWidth + 16
                Layout.preferredHeight: 40   // Taller pill for ultrawide readability
                Layout.alignment: Qt.AlignVCenter

                // Mouse wheel: up advances "next" in the shown list (per requirements)
                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    onWheel: (event) => {
                        const delta = (event.angleDelta.y > 0) ? 1 : -1;
                        bar.switchToRelative(delta);
                    }
                }

                Row {
                    id: wsRow
                    anchors.centerIn: parent
                    spacing: 4

                    Repeater {
                        model: bar.shownWorkspaces
                        delegate: Rectangle {
                            id: wsBtn
                            required property var modelData // HyprlandWorkspace
                            required property int index
                            property bool isActive: modelData && (modelData.active || modelData.focused)
                            property bool isHovered: wsMouse.containsMouse

                            width: 42   // Slightly wider for bigger text
                            height: 32
                            radius: 8
                            color: isActive ? Qt.rgba(0.53, 0.69, 0.96, 0.22) :   // Glassy accent tint when active
                                   (isHovered ? bar.wsHoverYellow : "transparent")
                            border.width: isActive ? 1 : 0
                            border.color: isActive ? Qt.rgba(0.53, 0.69, 0.96, 0.6) : "#45475a"

                            Behavior on color { ColorAnimation { duration: 140; easing.type: Easing.OutQuad } }

                            MouseArea {
                                id: wsMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    bar.hoveredWorkspace = null;
                                    if (modelData) modelData.activate();
                                }
                                onEntered: { if (modelData) { wsPreviewHideTimer.stop(); bar.hoveredWorkspace = modelData; } }
                                onExited: {
                                    wsPreviewHideTimer.restart();
                                }
                            }

                            // Icon + number (matching eww mapping)
                            // Text is white + bold like the date/time clock, slightly larger
                            Row {
                                anchors.centerIn: parent
                                spacing: 3
                                Text {
                                    text: bar.getWsIcon(modelData ? modelData.id : 0)
                                    font.pixelSize: 17   // Increased for ultrawide readability
                                    color: isActive ? "#e0e7ff" :
                                           (isHovered ? "#111111" : bar.clock)
                                    font.family: "JetBrains Mono Nerd Font, Symbols Nerd Font, monospace"
                                    font.bold: true
                                }
                                Text {
                                    text: modelData ? modelData.id : ""
                                    font.pixelSize: 15   // Increased for ultrawide readability
                                    font.bold: true
                                    color: isActive ? "#e0e7ff" :
                                           (isHovered ? "#111111" : bar.clock)
                                }
                            }
                        }
                    }
                }
            }  // closes workspacesPill Rectangle

            Item { Layout.fillWidth: true }

            // Subtle modern vertical divider
            Rectangle {
                Layout.preferredWidth: 1
                Layout.preferredHeight: 18
                Layout.alignment: Qt.AlignVCenter
                color: Qt.rgba(1, 1, 1, 0.12)
            }

            // ===== SYSTEM TRAY (right side, left of volume widget, pill style, comfortable spacing, efficient reactive) =====
            Rectangle {
                id: trayPill
                visible: SystemTray.items.values.length > 0
                Layout.preferredWidth: visible ? (trayContent.implicitWidth + 14) : 0
                Layout.preferredHeight: 36
                radius: bar.pillRadius
                color: trayHover.containsMouse ? bar.glassHover : bar.pillBg
                border.width: 1
                border.color: trayHover.containsMouse ? bar.accent : bar.pillBorder

                MouseArea {
                    id: trayHover
                    anchors.fill: parent
                    hoverEnabled: true
                }

                Item {
                    id: trayContent
                    anchors.centerIn: parent
                    implicitWidth: trayIconsRow.implicitWidth
                    implicitHeight: trayIconsRow.implicitHeight

                    Row {
                        id: trayIconsRow
                        spacing: 8   // comfortable width between icons
                        anchors.centerIn: parent

                        Repeater {
                            model: SystemTray.items.values
                            delegate: Item {
                                id: trayIconItem
                                required property var modelData
                                width: 20
                                height: 20

                                IconImage {
                                    anchors.centerIn: parent
                                    width: 18
                                    height: 18
                                    source: modelData ? modelData.icon : ""
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: (mouse) => {
                                        if (!modelData) return;
                                        if (mouse.button === Qt.LeftButton) {
                                            modelData.activate();
                                        } else if (mouse.button === Qt.RightButton) {
                                            if (modelData.hasMenu) {
                                                showTrayMenu(modelData, trayIconItem);
                                            } else {
                                                modelData.activate();
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Subtle modern vertical divider
            Rectangle {
                Layout.preferredWidth: 1
                Layout.preferredHeight: 18
                Layout.alignment: Qt.AlignVCenter
                color: Qt.rgba(1, 1, 1, 0.12)
            }

            // ===== AUDIO / VOLUME WIDGET (cycle speaker <-> mic <-> dual, popup on right-click) =====
            Rectangle {
                id: audioPill
                Layout.preferredWidth: audioContent.implicitWidth + 18
                Layout.preferredHeight: 36
                radius: bar.pillRadius
                color: audioHover.containsMouse ? bar.glassHover : bar.pillBg
                border.width: 1
                border.color: audioHover.containsMouse ? bar.accent : bar.pillBorder

                // Main interaction area (left-click cycle, middle mute, right popup)
                MouseArea {
                    id: audioHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton

                    onClicked: (mouse) => {
                        if (mouse.button === Qt.LeftButton) {
                            audio.cycleView();
                        } else if (mouse.button === Qt.MiddleButton) {
                            // Middle: mute the "primary" for current view
                            if (audio.viewMode === 0) audio.toggleMute(audio.speaker);
                            else if (audio.viewMode === 1) audio.toggleMute(audio.mic);
                            else audio.toggleMute(audio.speaker);  // dual: speaker
                        } else if (mouse.button === Qt.RightButton) {
                            showAudioPopup();
                        }
                    }
                }

                // Content switches on viewMode
                Item {
                    id: audioContent
                    anchors.centerIn: parent
                    implicitWidth: audioRow.implicitWidth
                    implicitHeight: audioRow.implicitHeight

                    Row {
                        id: audioRow
                        spacing: 6
                        anchors.centerIn: parent

                        // ========== SPEAKER VIEW ==========
                        Row {
                            visible: audio.viewMode === 0
                            spacing: 6

                            Text {
                                text: audio.speakerMuted ? "" : ""
                                font.pixelSize: 16
                                font.family: "Symbols Nerd Font, JetBrains Mono Nerd Font, monospace"
                                color: audio.speakerMuted ? bar.muted : bar.accent
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            // Clickable slider + wheel for speaker
                            Item {
                                width: 92; height: 16
                                anchors.verticalCenter: parent.verticalCenter

                                Loader {
                                    id: spkBar
                                    anchors.verticalCenter: parent.verticalCenter
                                    sourceComponent: volumeBar
                                    onLoaded: {
                                        item.value = Qt.binding(function(){ return audio.speakerVolume; });
                                        item.onSet = function(v){ audio.setVolume(audio.speaker, v); };
                                        item.fill = Qt.binding(function(){ return audio.speakerMuted ? bar.muted : bar.accent; });
                                    }
                                }

                                WheelHandler {
                                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                                    onWheel: (e) => {
                                        const d = (e.angleDelta.y > 0) ? 0.05 : -0.05;
                                        audio.stepVolume(audio.speaker, d);
                                    }
                                }
                            }

                            Text {
                                text: audio.speakerPercent + "%"
                                font.pixelSize: 12
                                font.bold: true
                                color: audio.speakerMuted ? bar.muted : bar.text
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        // ========== MIC VIEW ==========
                        Row {
                            visible: audio.viewMode === 1
                            spacing: 6

                            Text {
                                text: audio.micMuted ? "󰍭" : "󰍬"
                                font.pixelSize: 16
                                font.family: "Symbols Nerd Font, JetBrains Mono Nerd Font, monospace"
                                color: audio.micMuted ? bar.muted : bar.accent
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Item {
                                width: 92; height: 16
                                anchors.verticalCenter: parent.verticalCenter

                                Loader {
                                    id: micBar
                                    anchors.verticalCenter: parent.verticalCenter
                                    sourceComponent: volumeBar
                                    onLoaded: {
                                        item.value = Qt.binding(function(){ return audio.micVolume; });
                                        item.onSet = function(v){ audio.setVolume(audio.mic, v); };
                                        item.fill = Qt.binding(function(){ return audio.micMuted ? bar.muted : bar.accent; });
                                    }
                                }

                                WheelHandler {
                                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                                    onWheel: (e) => {
                                        const d = (e.angleDelta.y > 0) ? 0.05 : -0.05;
                                        audio.stepVolume(audio.mic, d);
                                    }
                                }
                            }

                            Text {
                                text: audio.micPercent + "%"
                                font.pixelSize: 12
                                font.bold: true
                                color: audio.micMuted ? bar.muted : bar.text
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        // ========== DUAL VIEW ==========
                        Row {
                            visible: audio.viewMode === 2
                            spacing: 8

                            // Speaker mini
                            Row {
                                spacing: 3
                                Text {
                                    text: audio.speakerMuted ? "" : ""
                                    font.pixelSize: 14
                                    font.family: "Symbols Nerd Font, JetBrains Mono Nerd Font, monospace"
                                    color: audio.speakerMuted ? bar.muted : bar.accent
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Item {
                                    width: 44; height: 14
                                    anchors.verticalCenter: parent.verticalCenter
                                    Loader {
                                        anchors.verticalCenter: parent.verticalCenter
                                        sourceComponent: miniVolumeBar
                                        onLoaded: {
                                            item.value = Qt.binding(function(){ return audio.speakerVolume; });
                                            item.onSet = function(v){ audio.setVolume(audio.speaker, v); };
                                            item.fill = Qt.binding(function(){ return audio.speakerMuted ? bar.muted : bar.accent; });
                                        }
                                    }
                                    WheelHandler {
                                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                                        onWheel: (e) => { const d = (e.angleDelta.y > 0) ? 0.05 : -0.05; audio.stepVolume(audio.speaker, d); }
                                    }
                                }
                            }

                            // Mic mini
                            Row {
                                spacing: 3
                                Text {
                                    text: audio.micMuted ? "󰍭" : "󰍬"
                                    font.pixelSize: 14
                                    font.family: "Symbols Nerd Font, JetBrains Mono Nerd Font, monospace"
                                    color: audio.micMuted ? bar.muted : bar.accent
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Item {
                                    width: 44; height: 14
                                    anchors.verticalCenter: parent.verticalCenter
                                    Loader {
                                        anchors.verticalCenter: parent.verticalCenter
                                        sourceComponent: miniVolumeBar
                                        onLoaded: {
                                            item.value = Qt.binding(function(){ return audio.micVolume; });
                                            item.onSet = function(v){ audio.setVolume(audio.mic, v); };
                                            item.fill = Qt.binding(function(){ return audio.micMuted ? bar.muted : bar.accent; });
                                        }
                                    }
                                    WheelHandler {
                                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                                        onWheel: (e) => { const d = (e.angleDelta.y > 0) ? 0.05 : -0.05; audio.stepVolume(audio.mic, d); }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Subtle modern vertical divider
            Rectangle {
                Layout.preferredWidth: 1
                Layout.preferredHeight: 18
                Layout.alignment: Qt.AlignVCenter
                color: Qt.rgba(1, 1, 1, 0.12)
            }

            // ===== CLOCK (clickable) - encapsulated in pill (matching eww .clock style + workspaces pill) =====
            Rectangle {
                id: clockButton
                Layout.preferredWidth: clockLabel.implicitWidth + 28
                Layout.preferredHeight: 36
                radius: bar.pillRadius
                color: clockArea.containsMouse ? bar.glassHover : bar.pillBg
                border.width: 1
                border.color: clockArea.containsMouse ? bar.accent : bar.pillBorder

                Text {
                    id: clockLabel
                    anchors.centerIn: parent
                    text: Qt.formatDateTime(new Date(), "dddd, MM·dd·yyyy | HH:mm:ss")
                    color: bar.clock
                    font.pixelSize: 15   // Increased for ultrawide readability (was 13)
                    font.family: "monospace"
                    font.bold: true
                }

                MouseArea {
                    id: clockArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (calendarPopup.visible) {
                            calendarPopup.visible = false
                        } else {
                            showCalendarPopup()
                        }
                    }
                }

                // Live updating clock
                Timer {
                    interval: 1000
                    running: true
                    repeat: true
                    onTriggered: {
                        clockLabel.text = Qt.formatDateTime(new Date(), "dddd, MM·dd·yyyy | HH:mm:ss")
                    }
                }
            }

            // ===== NOTIFICATION BELL (right of clock, swaync backed) =====
            // Pill style to match clock + tray + audio widgets. Icon + live count badge.
            // Left click: toggle swaync control center (your full rich history + actions + replies)
            // Right click: toggle DND (icon changes to crossed bell, state synced live)
            Rectangle {
                id: notifBell
                Layout.preferredWidth: bellRow.implicitWidth + 18
                Layout.preferredHeight: 36
                radius: bar.pillRadius
                color: bellMouse.containsMouse ? bar.glassHover : bar.pillBg
                border.width: 1
                border.color: bellMouse.containsMouse ? bar.accent : bar.pillBorder

                Row {
                    id: bellRow
                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                        id: bellIcon
                        text: notif.icon
                        font.pixelSize: 16
                        font.family: "Symbols Nerd Font, JetBrains Mono Nerd Font, monospace"
                        color: notif.dnd ? bar.muted : (notif.count > 0 ? bar.accent : bar.subtext)
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    // Counter badge (only when > 0). Compact pill or circle-ish.
                    Rectangle {
                        visible: notif.count > 0
                        width: Math.max(18, countLabel.implicitWidth + 8)
                        height: 18
                        radius: 9
                        color: notif.dnd ? Qt.rgba(0.6, 0.2, 0.2, 0.9) : bar.accent
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            id: countLabel
                            anchors.centerIn: parent
                            text: notif.count > 99 ? "99+" : notif.count
                            color: "#111111"
                            font.pixelSize: 11
                            font.bold: true
                            font.family: "monospace"
                        }
                    }
                }

                MouseArea {
                    id: bellMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton

                    // Attached ToolTip (works because QtQuick.Controls is imported)
                    ToolTip.text: {
                        if (notif.dnd) return notif.count + " notifications (DND enabled)";
                        if (notif.count > 0) return notif.count + " notifications";
                        return "No notifications";
                    }
                    ToolTip.visible: containsMouse
                    ToolTip.delay: 650

                    onClicked: (mouse) => {
                        if (mouse.button === Qt.RightButton) {
                            toggleDnd()
                        } else if (mouse.button === Qt.LeftButton) {
                            toggleNotifPanel()
                        }
                    }
                }
            }

            // Subtle modern vertical divider (between notifications and power menu)
            Rectangle {
                Layout.preferredWidth: 1
                Layout.preferredHeight: 18
                Layout.alignment: Qt.AlignVCenter
                color: Qt.rgba(1, 1, 1, 0.12)
            }

            // ===== POWER / SESSION MENU (right of notification bell) =====
            // Icon-only pill; click opens centered power actions popup (logout, lock, reboot, shutdown, BIOS)
            Rectangle {
                id: powerPill
                Layout.preferredWidth: 42
                Layout.preferredHeight: 36
                radius: bar.pillRadius
                color: powerMouse.containsMouse ? bar.glassHover : bar.pillBg
                border.width: 1
                border.color: powerMouse.containsMouse ? bar.accent : bar.pillBorder

                Text {
                    id: powerIcon
                    anchors.centerIn: parent
                    text: "󰐥"
                    font.pixelSize: 18
                    font.family: "Symbols Nerd Font, JetBrains Mono Nerd Font, monospace"
                    color: powerMouse.containsMouse ? bar.accent : bar.subtext
                }

                MouseArea {
                    id: powerMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor

                    ToolTip.text: "Power / Session"
                    ToolTip.visible: containsMouse
                    ToolTip.delay: 650

                    onClicked: {
                        if (powerPopup.visible) {
                            powerPopup.visible = false
                        } else {
                            showPowerMenu()
                        }
                    }
                }
            }
        }
    }

    // ===== Calendar Logic =====
    QtObject {
        id: calendar
        property int viewedMonth: new Date().getMonth()
        property int viewedYear: new Date().getFullYear()

        function goToToday() {
            var now = new Date()
            viewedMonth = now.getMonth()
            viewedYear = now.getFullYear()
        }

        function changeMonth(delta) {
            viewedMonth += delta
            while (viewedMonth < 0) {
                viewedMonth += 12
                viewedYear -= 1
            }
            while (viewedMonth > 11) {
                viewedMonth -= 12
                viewedYear += 1
            }
        }
    }

    // ===== CALENDAR POPUP =====
    PopupWindow {
        id: calendarPopup
        anchor.window: bar
        implicitWidth: 310
        implicitHeight: 280   // Reduced ~50% from tall version (calendar-specific; other popups untouched)
        visible: false
        color: "transparent"

        // Glassmorphic popup background
        Rectangle {
            anchors.fill: parent
            radius: 16
            color: bar.glassPopupBg
            border.width: 1
            border.color: bar.glassPopupBorder

            // Top highlight for glass effect
            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1.5
                color: bar.glassPopupHighlight
                radius: parent.radius
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                // Header: Month + Year + Navigation
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        Layout.fillWidth: true
                        text: Qt.formatDateTime(new Date(calendar.viewedYear, calendar.viewedMonth, 1), "MMMM yyyy")
                        color: bar.text
                        font.pixelSize: 17
                        font.bold: true
                        horizontalAlignment: Text.AlignLeft
                    }

                    // Nav buttons: year-, month-, today, month+, year+
                    Repeater {
                        model: [
                            { sym: "«", delta: -12, tip: "Previous year" },
                            { sym: "‹", delta: -1,  tip: "Previous month" },
                            { sym: "›", delta:  1,  tip: "Next month" },
                            { sym: "»", delta: 12,  tip: "Next year" }
                        ]
                        delegate: Rectangle {
                            width: 26
                            height: 26
                            radius: 6
                            color: navMa.containsMouse ? bar.surface : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: modelData.sym
                                color: bar.accent
                                font.pixelSize: 15
                                font.bold: true
                            }

                            MouseArea {
                                id: navMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: calendar.changeMonth(modelData.delta)
                            }
                        }
                    }

                    // Today button
                    Rectangle {
                        width: 52
                        height: 24
                        radius: 6
                        color: todayBtnMa.containsMouse ? bar.accent : bar.surface

                        Text {
                            anchors.centerIn: parent
                            text: "Today"
                            color: todayBtnMa.containsMouse ? bar.bg : bar.text
                            font.pixelSize: 11
                            font.bold: true
                        }

                        MouseArea {
                            id: todayBtnMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: calendar.goToToday()
                        }
                    }
                }

                // Weekday headers (Monday first)
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Repeater {
                        model: ["M", "T", "W", "T", "F", "S", "S"]
                        delegate: Text {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: modelData
                            color: bar.weekday
                            font.pixelSize: 11
                            font.bold: true
                        }
                    }
                }

                // Calendar grid (42 cells)
                GridLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    columns: 7
                    rowSpacing: 3
                    columnSpacing: 3

                    Repeater {
                        model: 42
                        delegate: Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.minimumHeight: 22

                            // ===== Day calculation =====
                            property int firstDay: new Date(calendar.viewedYear, calendar.viewedMonth, 1).getDay() // 0=Sun
                            property int leadingEmpty: (firstDay === 0) ? 6 : (firstDay - 1)
                            property int daysInMonth: new Date(calendar.viewedYear, calendar.viewedMonth + 1, 0).getDate()
                            property int dayNum: index - leadingEmpty + 1

                            property bool isCurrentMonth: dayNum >= 1 && dayNum <= daysInMonth
                            property int displayNum: {
                                if (isCurrentMonth) return dayNum
                                if (dayNum < 1) {
                                    // previous month
                                    var prevDays = new Date(calendar.viewedYear, calendar.viewedMonth, 0).getDate()
                                    return prevDays + dayNum
                                }
                                // next month
                                return dayNum - daysInMonth
                            }

                            property bool isToday: {
                                var now = new Date()
                                return isCurrentMonth &&
                                       calendar.viewedYear === now.getFullYear() &&
                                       calendar.viewedMonth === now.getMonth() &&
                                       dayNum === now.getDate()
                            }

                            // Today highlight circle
                            Rectangle {
                                anchors.centerIn: parent
                                width: 26
                                height: 26
                                radius: 13
                                color: bar.todayBg
                                visible: isToday
                            }

                            // Day number
                            Text {
                                anchors.centerIn: parent
                                text: displayNum > 0 ? displayNum : ""
                                color: isToday ? bar.bg :
                                       (isCurrentMonth ? bar.text : bar.overlay)
                                font.pixelSize: isToday ? 13 : 12
                                font.bold: isToday || isCurrentMonth
                            }
                        }
                    }
                }

                // Footer
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 4

                    Text {
                        Layout.fillWidth: true
                        text: "Current day is highlighted"
                        color: bar.overlay
                        font.pixelSize: 10
                    }

                    Text {
                        text: "click clock to close"
                        color: bar.overlay
                        font.pixelSize: 10
                    }
                }
            }
        }
    }

    // ===== AUDIO POPUP (device selectors + full sliders + mutes) =====
    PopupWindow {
        id: audioPopup
        anchor.window: bar
        implicitWidth: 420
        implicitHeight: 260   // Reduced ~50% from tall version (sound widget popup only; others untouched)
        visible: false
        color: "transparent"

        Rectangle {
            anchors.fill: parent
            radius: 12
            color: bar.glassPopupBg
            border.width: 1
            border.color: bar.glassPopupBorder

            // Top highlight for glass effect
            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1.5
                color: bar.glassPopupHighlight
                radius: parent.radius
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 16

                // Header
                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        text: "Audio Controls"
                        color: bar.text
                        font.pixelSize: 16
                        font.bold: true
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: "right-click pill or outside to close"
                        color: bar.overlay
                        font.pixelSize: 11
                    }
                }

                // OUTPUT section
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        text: "Playback"
                        color: bar.accent
                        font.pixelSize: 13
                        font.bold: true
                    }

                    // Device selector (click to open list)
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 28
                        radius: 6
                        color: outDevMouse.containsMouse ? bar.glassHover : Qt.rgba(0.10, 0.10, 0.12, 0.6)
                        border.width: 1
                        border.color: "#45475a"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 6
                            Text {
                                Layout.fillWidth: true
                                text: audio.getCurrentDeviceName(true)
                                color: bar.text
                                font.pixelSize: 12
                                elide: Text.ElideRight
                            }
                            Text {
                                text: "▼"
                                color: bar.subtext
                                font.pixelSize: 11
                            }
                        }

                        MouseArea {
                            id: outDevMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: openAudioDeviceList(true, outDevMouse)
                        }
                    }

                    // Slider row
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: audio.speakerMuted ? "" : ""
                            font.pixelSize: 17
                            font.family: "Symbols Nerd Font"
                            color: audio.speakerMuted ? bar.muted : bar.accent
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 18
                            Loader {
                                anchors.fill: parent
                                anchors.verticalCenter: parent.verticalCenter
                                sourceComponent: volumeBar
                                onLoaded: {
                                    item.value = Qt.binding(function(){ return audio.speakerVolume; });
                                    item.onSet = function(v){ audio.setVolume(audio.speaker, v); };
                                    item.barHeight = 8;
                                    item.fill = Qt.binding(function(){ return audio.speakerMuted ? bar.muted : bar.accent; });
                                }
                            }
                            WheelHandler {
                                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                                onWheel: (e) => { const d = (e.angleDelta.y > 0) ? 0.05 : -0.05; audio.stepVolume(audio.speaker, d); }
                            }
                        }

                        Text {
                            text: audio.speakerPercent + "%"
                            color: audio.speakerMuted ? bar.muted : bar.text
                            font.pixelSize: 13
                            font.bold: true
                            Layout.preferredWidth: 42
                        }

                        // Mute toggle button
                        Rectangle {
                            width: 52; height: 22; radius: 5
                            color: muteOutMa.containsMouse ? (audio.speakerMuted ? bar.muted : bar.accent) : bar.surface
                            border.width: 1
                            border.color: "#45475a"

                            Text {
                                anchors.centerIn: parent
                                text: audio.speakerMuted ? "Unmute" : "Mute"
                                color: muteOutMa.containsMouse ? bar.bg : bar.text
                                font.pixelSize: 11
                                font.bold: true
                            }
                            MouseArea {
                                id: muteOutMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: audio.toggleMute(audio.speaker)
                            }
                        }
                    }
                }

                // INPUT section
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        text: "Recording"
                        color: bar.accent
                        font.pixelSize: 13
                        font.bold: true
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 28
                        radius: 6
                        color: inDevMouse.containsMouse ? bar.glassHover : Qt.rgba(0.10, 0.10, 0.12, 0.6)
                        border.width: 1
                        border.color: "#45475a"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 6
                            Text {
                                Layout.fillWidth: true
                                text: audio.getCurrentDeviceName(false)
                                color: bar.text
                                font.pixelSize: 12
                                elide: Text.ElideRight
                            }
                            Text {
                                text: "▼"
                                color: bar.subtext
                                font.pixelSize: 11
                            }
                        }

                        MouseArea {
                            id: inDevMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: openAudioDeviceList(false, inDevMouse)
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Text {
                            text: audio.micMuted ? "󰍭" : "󰍬"
                            font.pixelSize: 17
                            font.family: "Symbols Nerd Font"
                            color: audio.micMuted ? bar.muted : bar.accent
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 18
                            Loader {
                                anchors.fill: parent
                                anchors.verticalCenter: parent.verticalCenter
                                sourceComponent: volumeBar
                                onLoaded: {
                                    item.value = Qt.binding(function(){ return audio.micVolume; });
                                    item.onSet = function(v){ audio.setVolume(audio.mic, v); };
                                    item.barHeight = 8;
                                    item.fill = Qt.binding(function(){ return audio.micMuted ? bar.muted : bar.accent; });
                                }
                            }
                            WheelHandler {
                                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                                onWheel: (e) => { const d = (e.angleDelta.y > 0) ? 0.05 : -0.05; audio.stepVolume(audio.mic, d); }
                            }
                        }

                        Text {
                            text: audio.micPercent + "%"
                            color: audio.micMuted ? bar.muted : bar.text
                            font.pixelSize: 13
                            font.bold: true
                            Layout.preferredWidth: 42
                        }

                        Rectangle {
                            width: 52; height: 22; radius: 5
                            color: muteInMa.containsMouse ? (audio.micMuted ? bar.muted : bar.accent) : bar.surface
                            border.width: 1
                            border.color: "#45475a"

                            Text {
                                anchors.centerIn: parent
                                text: audio.micMuted ? "Unmute" : "Mute"
                                color: muteInMa.containsMouse ? bar.bg : bar.text
                                font.pixelSize: 11
                                font.bold: true
                            }
                            MouseArea {
                                id: muteInMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: audio.toggleMute(audio.mic)
                            }
                        }
                    }
                }
            }
        }

        // Close on click outside content (simple: whole popup mouse)
        MouseArea {
            anchors.fill: parent
            z: -1
            onClicked: audioPopup.visible = false
        }
    }

    // Device list popup (shared for output/input)
    PopupWindow {
        id: audioDeviceListPopup
        anchor.window: bar
        implicitWidth: 320
        implicitHeight: Math.min(420, Math.max(100, (audio.deviceListForSink ? audio.sinks.length : audio.sources.length) * 39 + 90))  // ~50% taller
        visible: false
        color: "transparent"

        Rectangle {
            anchors.fill: parent
            radius: 10
            color: bar.glassPopupBg
            border.width: 1
            border.color: bar.glassPopupBorder

            // Top highlight for glass effect
            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1.5
                color: bar.glassPopupHighlight
                radius: parent.radius
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 4

                Text {
                    text: audio.deviceListForSink ? "Select Playback Device" : "Select Recording Device"
                    color: bar.text
                    font.pixelSize: 13
                    font.bold: true
                }

                Item { Layout.preferredHeight: 4 }

                // Device rows
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Repeater {
                        model: audio.deviceListForSink ? audio.sinks : audio.sources
                        delegate: Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 24
                            radius: 4
                            color: rowDevMa.containsMouse ? bar.surface : "transparent"

                            required property var modelData

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.name
                                    color: bar.text
                                    font.pixelSize: 12
                                    elide: Text.ElideRight
                                }
                                Text {
                                    visible: isCurrentDevice(modelData)
                                    text: "✓"
                                    color: bar.accent
                                    font.pixelSize: 13
                                }
                            }

                            MouseArea {
                                id: rowDevMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    var node = modelData.node;
                                    if (audio.deviceListForSink) {
                                        Pipewire.preferredDefaultAudioSink = node;
                                    } else {
                                        Pipewire.preferredDefaultAudioSource = node;
                                    }
                                    audioDeviceListPopup.visible = false;
                                }
                            }
                        }
                    }

                    Text {
                        visible: (audio.deviceListForSink ? audio.sinks.length : audio.sources.length) === 0
                        text: "(no devices)"
                        color: bar.overlay
                        font.pixelSize: 11
                        font.italic: true
                    }
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            z: -1
            onClicked: audioDeviceListPopup.visible = false
        }
    }

    function isCurrentDevice(dev) {
        if (!dev || !dev.node) return false;
        var def = audio.deviceListForSink ? Pipewire.defaultAudioSink : Pipewire.defaultAudioSource;
        if (!def) return false;
        return (def.name === dev.node.name) || (def.description === dev.node.description);
    }

    function openAudioDeviceList(forSink, targetItem) {
        audio.deviceListForSink = forSink;
        var popupW = audioDeviceListPopup.implicitWidth;
        var screenW = (bar.screen && bar.screen.width) ? bar.screen.width : 1920;

        // Better position using mapToItem (relative to barBg like calendar)
        var p = (audioPill && barBg) ? audioPill.mapToItem(barBg, 0, audioPill.height) : {x: 200, y: 0};
        var baseX = bar.sideMargin + p.x;
        audioDeviceListPopup.anchor.rect.x = Math.min(baseX, screenW - popupW - 12);
        audioDeviceListPopup.anchor.rect.y = bar.implicitHeight + 46;
        audioDeviceListPopup.visible = true;
    }

    function showAudioPopup() {
        if (audioPopup.visible) {
            audioPopup.visible = false;
            audioDeviceListPopup.visible = false;
            return;
        }
        var pos = audioPill.mapToItem(barBg, audioPill.width / 2, audioPill.height);
        var popupW = audioPopup.implicitWidth;
        var screenW = (bar.screen && bar.screen.width) ? bar.screen.width : 1920;

        var targetX = bar.sideMargin + pos.x - (popupW / 2);
        var minX = 12;
        var maxX = screenW - popupW - 12;
        audioPopup.anchor.rect.x = Math.max(minX, Math.min(targetX, maxX));
        audioPopup.anchor.rect.y = bar.implicitHeight + 2;

        audioPopup.visible = true;
        audioDeviceListPopup.visible = false;
    }

    // Helper to position + show popup nicely under the clock
    function showCalendarPopup() {
        // Map relative to the visual bar background (reliable QQuickItem target)
        var pos = clockButton.mapToItem(barBg, clockButton.width / 2, clockButton.height)
        var popupWidth = calendarPopup.implicitWidth

        // The barBg has leftMargin, so add the bar's side margin for correct window-relative x
        var targetX = bar.sideMargin + pos.x - (popupWidth / 2)

        // Clamp to screen edges using the screen the bar is on
        var screenW = (bar.screen && bar.screen.width) ? bar.screen.width : 1920
        var minX = 12
        var maxX = screenW - popupWidth - 12
        calendarPopup.anchor.rect.x = Math.max(minX, Math.min(targetX, maxX))
        calendarPopup.anchor.rect.y = bar.implicitHeight + 2

        calendarPopup.visible = true
    }

    // ===== NOTIFICATION ACTION HELPERS (swaync-client one-shots, fire-and-forget) =====
    function toggleNotifPanel() {
        Quickshell.execDetached(["swaync-client", "-t", "-sw"])
    }

    function toggleDnd() {
        Quickshell.execDetached(["swaync-client", "-d", "-sw"])
    }

    function clearAllNotifications() {
        Quickshell.execDetached(["swaync-client", "-C", "-sw"])
    }

    // ===== POWER / SESSION MENU HELPERS =====
    function showPowerMenu() {
        var screenW = (bar.screen && bar.screen.width) ? bar.screen.width : 1920;
        var screenH = (bar.screen && bar.screen.height) ? bar.screen.height : 1080;
        var pw = powerPopup.implicitWidth;
        var ph = powerPopup.implicitHeight;

        powerPopup.anchor.rect.x = Math.max(40, (screenW - pw) / 2);
        powerPopup.anchor.rect.y = Math.max(120, (screenH - ph) / 2);

        powerPopup.visible = true;
    }

    function hidePowerMenu() {
        powerPopup.visible = false;
    }

    function powerAction(cmd) {
        Quickshell.execDetached(cmd);
        hidePowerMenu();
    }

    function powerLock()     { powerAction(["hyprlock"]); }
    function powerLogout()   { powerAction(["hyprctl", "dispatch", "exit"]); }
    function powerReboot()   { powerAction(["systemctl", "reboot"]); }
    function powerShutdown() { powerAction(["systemctl", "poweroff"]); }
    function powerBios()     { powerAction(["systemctl", "reboot", "--firmware-setup"]); }

    // ===== TRAY MENU HELPERS (styled, efficient, no polling) =====
    function showTrayMenu(trayItem, sourceItem) {
        if (!trayItem || !trayItem.hasMenu) return;
        trayMenuPopup.currentItem = trayItem;
        trayMenuPopup.menuHandle = trayItem.menu;
        trayMenuPopup.menuStack = [];
        trayMenuPopup.itemTitle = trayItem.title || trayItem.id || "Menu";

        // Position popup near the icon, under the bar
        var p = sourceItem.mapToItem(barBg, sourceItem.width / 2, sourceItem.height);
        var popupW = trayMenuPopup.implicitWidth || 220;
        var screenW = (bar.screen && bar.screen.width) ? bar.screen.width : 1920;

        var targetX = bar.sideMargin + p.x - (popupW / 2);
        var minX = 12;
        var maxX = screenW - popupW - 12;
        trayMenuPopup.anchor.rect.x = Math.max(minX, Math.min(targetX, maxX));
        trayMenuPopup.anchor.rect.y = bar.implicitHeight + 4;

        trayMenuPopup.visible = true;
    }

    function closeTrayMenu() {
        trayMenuPopup.visible = false;
        trayMenuPopup.menuStack = [];
        trayMenuPopup.menuHandle = null;
        trayMenuPopup.currentItem = null;
    }

    // ===== Workspace Hover Preview Popup (simple text list of windows on hovered ws) =====
    // Efficient: only shows on hover, content driven by reactive Hyprland model (no polling)
    // Positioned under left side of bar. Hides shortly after mouse leaves (with popup protection).
    Timer {
        id: wsPreviewHideTimer
        interval: 280
        onTriggered: bar.hoveredWorkspace = null
    }

    PopupWindow {
        id: wsPreviewPopup
        anchor.window: bar
        implicitWidth: 340
        implicitHeight: 420   // Reduced 20% from previous (still comfortably tall with scrolling)
        visible: bar.hoveredWorkspace !== null
        color: "transparent"

        Rectangle {
            anchors.fill: parent
            radius: 10
            color: bar.glassPopupBg
            border.width: 1
            border.color: bar.glassPopupBorder

            // Top highlight for glass effect
            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1.5
                color: bar.glassPopupHighlight
                radius: parent.radius
            }

            ColumnLayout {
                anchors.fill: parent
                // Larger vertical margins and spacing for the bigger popup
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                anchors.topMargin: 27
                anchors.bottomMargin: 32
                spacing: 8   // Reduced to avoid double-spacing feel between header and app list

                // Extra visible blank space above the header
                Item {
                    Layout.preferredHeight: 9
                }

                Text {
                    text: bar.hoveredWorkspace ? ("Workspace " + bar.hoveredWorkspace.id + "  ·  " + (bar.hoveredWorkspace.toplevels && bar.hoveredWorkspace.toplevels.count ? bar.hoveredWorkspace.toplevels.count : 0) + " window(s)") : ""
                    color: bar.text
                    font.pixelSize: 17
                    font.bold: true
                }

                // Scrollable window list — this is what allows many windows without cutoff
                Flickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    contentHeight: windowsColumn.implicitHeight

                    ScrollBar.vertical: ScrollBar {
                        width: 6
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.margins: 2
                        policy: ScrollBar.AsNeeded

                        background: Rectangle {
                            color: "transparent"
                        }
                        contentItem: Rectangle {
                            color: bar.overlay
                            radius: 3
                            implicitWidth: 6
                        }
                    }

                    Column {
                        id: windowsColumn
                        width: parent.width
                        spacing: 2   // Tight single spacing between app rows (was 9)

                        // Breathing space above the first app row
                        Item {
                            width: parent.width
                            height: 10
                        }

                        Repeater {
                            model: (bar.hoveredWorkspace && bar.hoveredWorkspace.toplevels) ? bar.hoveredWorkspace.toplevels : []
                            delegate: Rectangle {
                                id: windowRow
                                required property var modelData
                                width: parent.width
                                implicitHeight: 58
                                radius: 4
                                color: rowMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.09) : "transparent"

                                // Make the entire row (icon + text) clickable
                                MouseArea {
                                    id: rowMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor

                                    onClicked: {
                                        // Capture values before we clear the popup
                                        const ws = bar.hoveredWorkspace;
                                        const addr = modelData && modelData.addressStr ? modelData.addressStr() : "";

                                        // Hide the popup immediately — popups can steal focus back
                                        bar.hoveredWorkspace = null;

                                        if (ws) {
                                            // Explicitly switch to the workspace first
                                            Hyprland.dispatch(`workspace ${ws.id}`);
                                        }

                                        if (addr) {
                                            // Focus the specific window slightly later.
                                            // This gives Hyprland time to settle the workspace switch
                                            // and ensures the popup has fully released focus.
                                            Qt.callLater(function() {
                                                Hyprland.dispatch(`focuswindow address:0x${addr}`);
                                            });
                                        }
                                    }
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 12
                                    spacing: 12

                                    IconImage {
                                        Layout.preferredWidth: 32
                                        Layout.preferredHeight: 32
                                        Layout.alignment: Qt.AlignVCenter
                                        source: {
                                            const klass = (modelData && modelData.lastIpcObject && modelData.lastIpcObject["class"]) || "";
                                            return Quickshell.iconPath(klass, "application-x-executable");
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: {
                                            if (!modelData) return "";
                                            const t = modelData.title || "";
                                            const klass = (modelData.lastIpcObject && modelData.lastIpcObject["class"]) ? " (" + modelData.lastIpcObject["class"] + ")" : "";
                                            return (t.length > 40 ? t.substring(0,37) + "…" : t) + klass;
                                        }
                                        color: bar.subtext
                                        font.pixelSize: 16
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }

                        Text {
                            visible: bar.hoveredWorkspace && (!bar.hoveredWorkspace.toplevels || bar.hoveredWorkspace.toplevels.count === 0)
                            text: "(empty workspace - only active)"
                            color: bar.overlay
                            font.pixelSize: 15
                            font.italic: true
                        }

                        // Breathing space below the last app row
                        Item {
                            width: parent.width
                            height: 10
                        }
                    }
                }

                // Generous bottom spacer for the blank space below the last item
                Item {
                    Layout.preferredHeight: 32
                }
            }
        }

        // Keep preview open if mouse enters the popup itself
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onEntered: wsPreviewHideTimer.stop()
            onExited: wsPreviewHideTimer.restart()
        }
    }

    // ===== STYLED SYSTEM TRAY MENU POPUP (matches bar theme, supports submenus, checks, separators; efficient via QsMenuOpener) =====
    PopupWindow {
        id: trayMenuPopup
        anchor.window: bar
        implicitWidth: Math.max(200, menuContent.implicitWidth + 24)
        implicitHeight: Math.min(520, Math.max(80, menuContent.implicitHeight + 28))
        visible: false
        color: "transparent"

        property var currentItem: null
        property var menuHandle: null
        property var menuStack: []
        property string itemTitle: ""

        // Reactive menu opener - children update when menuHandle changes
        QsMenuOpener {
            id: trayMenuOpener
            menu: trayMenuPopup.menuHandle
        }

        function pushSubMenu(handle) {
            if (!handle) return;
            trayMenuPopup.menuStack.push(trayMenuPopup.menuHandle);
            trayMenuPopup.menuHandle = handle;
        }

        function popSubMenu() {
            if (trayMenuPopup.menuStack.length > 0) {
                trayMenuPopup.menuHandle = trayMenuPopup.menuStack.pop();
            } else {
                closeTrayMenu();
            }
        }

        function activateEntry(entry) {
            if (!entry) return;
            if (entry.hasChildren) {
                pushSubMenu(entry);
            } else {
                entry.triggered();
                closeTrayMenu();
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: 10
            color: bar.glassPopupBg
            border.width: 1
            border.color: bar.glassPopupBorder

            // Top highlight for glass effect
            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1.5
                color: bar.glassPopupHighlight
                radius: parent.radius
            }

            ColumnLayout {
                id: menuContent
                anchors.fill: parent
                anchors.margins: 6
                spacing: 2

                // Header
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 8
                    Layout.rightMargin: 8
                    Layout.topMargin: 4
                    Layout.bottomMargin: 4

                    Text {
                        Layout.fillWidth: true
                        text: trayMenuPopup.itemTitle
                        color: bar.text
                        font.pixelSize: 12
                        font.bold: true
                        elide: Text.ElideRight
                    }

                    // Back button for submenus
                    Rectangle {
                        visible: trayMenuPopup.menuStack.length > 0
                        width: 22; height: 22; radius: 4
                        color: backMa.containsMouse ? bar.surface : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: "←"
                            color: bar.accent
                            font.pixelSize: 14
                            font.bold: true
                        }
                        MouseArea {
                            id: backMa
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: trayMenuPopup.popSubMenu()
                        }
                    }

                    // Close X
                    Rectangle {
                        width: 22; height: 22; radius: 4
                        color: closeMa.containsMouse ? bar.surface : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: "✕"
                            color: bar.subtext
                            font.pixelSize: 11
                        }
                        MouseArea {
                            id: closeMa
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: closeTrayMenu()
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: 6
                    Layout.rightMargin: 6
                    height: 1
                    color: "#45475a"
                }

                // Menu entries
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.margins: 4
                    spacing: 1

                    Repeater {
                        model: trayMenuOpener.children
                        delegate: Rectangle {
                            id: entryRow
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: modelData && modelData.isSeparator ? 6 : 28
                            radius: 4
                            color: entryMouse.containsMouse && !modelData.isSeparator ? bar.glassHover : "transparent"
                            visible: modelData && modelData.enabled !== false

                            MouseArea {
                                id: entryMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: modelData && !modelData.isSeparator
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (modelData) trayMenuPopup.activateEntry(modelData);
                                }
                            }

                            // Separator
                            Rectangle {
                                visible: modelData && modelData.isSeparator
                                anchors.centerIn: parent
                                width: parent.width - 16
                                height: 1
                                color: "#45475a"
                            }

                            // Regular entry content
                            RowLayout {
                                visible: modelData && !modelData.isSeparator
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 8

                                // Checkbox / radio indicator
                                Item {
                                    Layout.preferredWidth: 16
                                    Layout.preferredHeight: 16
                                    Layout.alignment: Qt.AlignVCenter
                                    visible: modelData && modelData.buttonType !== bar.menuBtnNone || (modelData && modelData.checkState !== undefined && modelData.checkState !== 0)

                                    Text {
                                        anchors.centerIn: parent
                                        text: {
                                            if (!modelData) return "";
                                            if (modelData.buttonType === bar.menuBtnRadio) return modelData.checkState === Qt.Checked ? "●" : "○";
                                            if (modelData.buttonType === bar.menuBtnCheck) return modelData.checkState === Qt.Checked ? "✓" : (modelData.checkState === Qt.PartiallyChecked ? "◐" : "");
                                            return "";
                                        }
                                        color: bar.accent
                                        font.pixelSize: 11
                                        font.bold: true
                                    }
                                }

                                // Icon if present
                                IconImage {
                                    Layout.preferredWidth: 16
                                    Layout.preferredHeight: 16
                                    Layout.alignment: Qt.AlignVCenter
                                    visible: modelData && modelData.icon && modelData.icon.length > 0
                                    source: (modelData && modelData.icon) ? modelData.icon : ""
                                }

                                // Label
                                Text {
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                    text: modelData ? (modelData.text || "") : ""
                                    color: entryMouse.containsMouse ? bar.text : bar.subtext
                                    font.pixelSize: 12
                                    elide: Text.ElideRight
                                }

                                // Submenu arrow
                                Text {
                                    visible: modelData && modelData.hasChildren
                                    Layout.alignment: Qt.AlignVCenter
                                    text: "▸"
                                    color: bar.accent
                                    font.pixelSize: 12
                                }
                            }
                        }
                    }

                    Text {
                        visible: (!trayMenuOpener.children || trayMenuOpener.children.length === 0) && !trayMenuPopup.menuHandle
                        Layout.alignment: Qt.AlignHCenter
                        text: "(no menu)"
                        color: bar.overlay
                        font.pixelSize: 11
                        font.italic: true
                    }
                }
            }
        }

        // Click outside to close
        MouseArea {
            anchors.fill: parent
            z: -1
            onClicked: closeTrayMenu()
        }
    }

    // ===== POWER MENU POPUP (centered on screen, glassmorphic, 5 actions incl. BIOS/firmware) =====
    PopupWindow {
        id: powerPopup
        anchor.window: bar
        implicitWidth: 620
        implicitHeight: 192
        visible: false
        color: "transparent"

        // Glassmorphic card background
        Rectangle {
            anchors.fill: parent
            radius: 16
            color: bar.glassPopupBg
            border.width: 1
            border.color: bar.glassPopupBorder

            // Top highlight for glass effect
            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1.5
                color: bar.glassPopupHighlight
                radius: parent.radius
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 8

                // Header row with title + hint + close X
                RowLayout {
                    Layout.fillWidth: true

                    Text {
                        text: "Power Menu"
                        color: bar.text
                        font.pixelSize: 15
                        font.bold: true
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: "Esc or click outside to close"
                        color: bar.overlay
                        font.pixelSize: 10
                    }

                    // Small close button
                    Rectangle {
                        width: 22; height: 22
                        radius: 4
                        color: powerCloseMa.containsMouse ? bar.glassHover : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: "✕"
                            color: bar.subtext
                            font.pixelSize: 13
                        }
                        MouseArea {
                            id: powerCloseMa
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: hidePowerMenu()
                        }
                    }
                }

                // Horizontal action buttons (icon + label)
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    spacing: 10

                    Repeater {
                        model: [
                            { icon: "󰌾", label: "Lock",     action: "lock" },
                            { icon: "󰍃", label: "Logout",   action: "logout" },
                            { icon: "󰑓", label: "Reboot",   action: "reboot" },
                            { icon: "󰐥", label: "Shutdown", action: "shutdown" },
                            { icon: "󰛳", label: "Enter BIOS", action: "bios" }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredHeight: 92
                            radius: 10
                            color: btnMa.containsMouse ? bar.glassHover : Qt.rgba(0.10, 0.10, 0.12, 0.55)
                            border.width: 1
                            border.color: btnMa.containsMouse ? bar.accent : Qt.rgba(1, 1, 1, 0.06)

                            Column {
                                anchors.centerIn: parent
                                spacing: 6
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: modelData.icon
                                    font.pixelSize: 32
                                    font.family: "Symbols Nerd Font, JetBrains Mono Nerd Font, monospace"
                                    color: btnMa.containsMouse ? bar.accent : bar.text
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: modelData.label
                                    font.pixelSize: 12
                                    font.bold: true
                                    color: btnMa.containsMouse ? bar.text : bar.subtext
                                }
                            }

                            MouseArea {
                                id: btnMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    switch (modelData.action) {
                                        case "lock":     powerLock(); break;
                                        case "logout":   powerLogout(); break;
                                        case "reboot":   powerReboot(); break;
                                        case "shutdown": powerShutdown(); break;
                                        case "bios":     powerBios(); break;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // Click on popup background (outside the visual card content) closes it
        MouseArea {
            anchors.fill: parent
            z: -1
            onClicked: hidePowerMenu()
        }

        // Keyboard escape support (works when the popup receives focus)
        Item {
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: hidePowerMenu()
        }
    }

    // Helper: show/position workspace preview popup (called on hover in ws buttons via hoveredWorkspace binding)
    function updateWsPreviewPosition() {
        if (!wsPreviewPopup.visible || !bar.hoveredWorkspace) return;
        const popupW = wsPreviewPopup.implicitWidth;
        const targetX = bar.sideMargin + 4;
        const screenW = (bar.screen && bar.screen.width) ? bar.screen.width : 1920;
        wsPreviewPopup.anchor.rect.x = Math.min(targetX, screenW - popupW - 12);
        wsPreviewPopup.anchor.rect.y = bar.implicitHeight + 4;
    }

    onHoveredWorkspaceChanged: {
        if (bar.hoveredWorkspace) {
            wsPreviewHideTimer.stop();
            // small delay position update
            Qt.callLater(bar.updateWsPreviewPosition);
        } else {
            wsPreviewHideTimer.stop();
        }
    }

    // ===== SWAYNC SUBSCRIBE (event-driven state for bell) =====
    // Long-lived process. swaync-client pushes a JSON line only on relevant changes
    // (new notif, close, dnd toggle, etc.). No timers, no polling, very cheap.
    // Parses simple output from `swaync-client -s -sw`:
    //   { "count": N, "dnd": bool, "visible": bool, "inhibited": bool }
    Io.Process {
        id: swayncSub
        running: true
        command: ["swaync-client", "-s", "-sw"]

        stdout: Io.SplitParser {
            splitMarker: "\n"
            onRead: (data) => {
                // SplitParser emits one chunk per splitMarker (we still trim + guard for safety)
                const line = data.trim();
                if (!line) return;
                try {
                    const j = JSON.parse(line);
                    if (typeof j.count === 'number') {
                        notif.count = j.count;
                    }
                    if (typeof j.dnd === 'boolean') {
                        notif.dnd = j.dnd;
                    }
                    if (typeof j.inhibited === 'boolean') {
                        notif.inhibited = j.inhibited;
                    }
                } catch (e) {
                    // ignore malformed lines (initial handshake or noise)
                }
            }
        }

        onExited: (code) => {
            // If swaync isn't running or client dies, keep trying (Quickshell will restart component on reload)
            // For robustness you could add a short restart Timer here if desired.
            console.log("swaync subscribe exited with code", code);
        }
    }
}
