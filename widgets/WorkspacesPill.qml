import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland

// =============================================================================
// WorkspacesPill.qml — Dynamic workspace pills
// =============================================================================
//
// Shows only occupied + active workspaces (filtered).
// - Icons are mapped in getWsIcon()
// - Scroll wheel switches workspaces relative to the current filtered list
// - Cold-start poller helps when Hyprland IPC is slow on login
// - Two Hyprland Connections keep the list reactive
// =============================================================================

Rectangle {
    id: root

    required property var bar

    // Layout properties so this pill participates correctly in the parent RowLayout
    Layout.preferredWidth: wsRow.implicitWidth + 16
    Layout.preferredHeight: 40
    Layout.alignment: Qt.AlignVCenter

    color: bar.glassPillBg
    radius: bar.pillRadius
    border.width: 1
    border.color: bar.glassBorder

    // ===== Workspace logic (moved from main file) =====
    property var shownWorkspaces: []

    function getWsIcon(id) {
        switch (id) {
            case 1: return "";     // code
            case 2: return "🦁";    // Brave Browser
            case 3: return "";     // chats
            case 4: return "";     // Google Chrome
            case 5: return "🕹";    // game
            case 6: return "";     // Misc
            case 7: return "󰈹";     // Firefox
            case 8: return "";     // term
            case 9: return "󰨞";     // vscode
            case 10: return "";    // Misc
            default: return "󰈸";
        }
    }

    function updateShownWorkspaces() {
        if (!Hyprland.workspaces || !Hyprland.workspaces.values) {
            root.shownWorkspaces = [];
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
        root.shownWorkspaces = filtered;
    }

    function switchToRelative(delta) {
        if (!root.shownWorkspaces || root.shownWorkspaces.length === 0) return;
        const activeId = (Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.id) ? Hyprland.focusedWorkspace.id : 1;
        let idx = -1;
        for (let i = 0; i < root.shownWorkspaces.length; i++) {
            if (root.shownWorkspaces[i].id === activeId) { idx = i; break; }
        }
        if (idx < 0) idx = 0;
        let newIdx = idx + delta;
        if (newIdx < 0) newIdx = 0;
        if (newIdx >= root.shownWorkspaces.length) newIdx = root.shownWorkspaces.length - 1;
        const target = root.shownWorkspaces[newIdx];
        if (target && target.activate) target.activate();
    }

    // Hyprland workspace change listeners
    Connections {
        target: Hyprland.workspaces
        function onValuesChanged() { root.updateShownWorkspaces(); }
    }
    Connections {
        target: Hyprland
        function onFocusedWorkspaceChanged() { root.updateShownWorkspaces(); }
    }

    // Cold-start workspace polling
    property int _wsColdPollCount: 0
    Timer {
        id: wsColdStartPoller
        interval: 130
        repeat: true
        onTriggered: {
            root.updateShownWorkspaces();
            root._wsColdPollCount += 1;
            if (root._wsColdPollCount >= 7) {
                stop();
                root._wsColdPollCount = 0;
            }
        }
    }

    // Initial update + start cold-start poller (called from parent onCompleted or we can do it here)
    Component.onCompleted: {
        root.updateShownWorkspaces();
        wsColdStartPoller.start();
    }

    // Mouse wheel support
    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: (event) => {
            const delta = (event.angleDelta.y > 0) ? 1 : -1;
            root.switchToRelative(delta);
        }
    }

    Row {
        id: wsRow
        anchors.centerIn: parent
        spacing: bar.wsSpacing || 4

        Repeater {
            model: root.shownWorkspaces
            delegate: Rectangle {
                id: wsBtn
                required property var modelData
                required property int index
                property bool isActive: modelData && (modelData.active || modelData.focused)
                property bool isHovered: wsMouse.containsMouse

                width: bar.wsButtonWidth
                height: bar.wsButtonHeight
                radius: bar.workspaceRadius
                color: isActive ? Qt.rgba(0.53, 0.69, 0.96, 0.22) :
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
                        if (modelData) modelData.activate();
                    }
                }

                Row {
                    anchors.centerIn: parent
                    spacing: 3
                    Text {
                        text: root.getWsIcon(modelData ? modelData.id : 0)
                        font.pixelSize: bar.wsIconSize || 17
                        color: isActive ? "#e0e7ff" :
                               (isHovered ? "#111111" : bar.clock)
                        font.family: "JetBrains Mono Nerd Font, Symbols Nerd Font, monospace"
                        font.bold: true
                    }
                    Text {
                        text: modelData ? modelData.id : ""
                        font.pixelSize: bar.wsNumberSize || 15
                        font.bold: true
                        color: isActive ? "#e0e7ff" :
                               (isHovered ? "#111111" : bar.clock)
                    }
                }
            }
        }
    }
}
