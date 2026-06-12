import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland

// =============================================================================
// WorkspacesPill.qml — Dynamic workspace pills
// =============================================================================
//
// Purpose:
//   Always shows workspaces 1–5 as pills (empty or occupied), plus any
//   additional workspaces that are occupied or active. Supports click
//   activation and scroll wheel switching.
//
// Theme Properties Consumed:
//   - bar.pillRadius, bar.glassPillBg, bar.glassBorder, bar.controlBorderWidth
//   - bar.wsButtonWidth, bar.wsButtonHeight, bar.workspaceRadius
//   - bar.wsSpacing, bar.wsIconSize, bar.wsNumberSize
//   - bar.wsActiveBg, bar.wsActiveBorder, bar.wsActiveText
//   - bar.wsHoverYellow, bar.clock, bar.fontFamily
//
// Dependencies:
//   - required property var bar (from shell.qml)
//   - Quickshell.Hyprland (for workspace state)
//
// Notes:
//   - Filtering, cold-start polling, and scroll logic are preserved exactly.
//   - Delegate styling has been aligned to theme tokens where possible.
// =============================================================================

Rectangle {
    id: root

    required property var bar

    // === Layout (works in any bar zone — left, center, or right) ===
    Layout.preferredWidth: wsRow.implicitWidth + 16
    Layout.preferredHeight: bar.pillHeight
    Layout.alignment: Qt.AlignVCenter
    implicitWidth: wsRow.implicitWidth + 16
    implicitHeight: bar.pillHeight

    // === Appearance via Theme ===
    color: bar.glassPillBg
    radius: bar.pillRadius
    border.width: bar.controlBorderWidth
    border.color: bar.glassBorder

    // ===== Workspace logic (tightly coupled to this widget) =====
    property int minimumWorkspaces: 5
    property var shownWorkspaces: []

    function workspaceHasWindows(w) {
        if (!w || !w.toplevels) return false;
        if (typeof w.toplevels.count === "number") return w.toplevels.count > 0;
        if (w.toplevels.values && typeof w.toplevels.values.length === "number") return w.toplevels.values.length > 0;
        return false;
    }

    function shouldShowExtraWorkspace(w) {
        if (!w || w.id <= 0) return false;
        return workspaceHasWindows(w) || w.active || w.focused;
    }

    function makePlaceholderWorkspace(id, focusedId) {
        return {
            id: id,
            active: false,
            focused: focusedId === id,
            activate: function() { Hyprland.dispatch("workspace " + id); }
        };
    }

    function getWsIcon(id) {
        switch (id) {
            case 1: return "";     //   code
            case 2: return "";     // "🦁 Brave Browser
            case 3: return "";     //  chats
            case 4: return "";     // 
            case 5: return "🕹";    // 🕹 game
            case 6: return "";     //  Misc
            case 7: return "";     // 󰈹 Firefox
            case 8: return "";     //  term
            case 9: return "";     // 󰨞 vscode
            case 10: return "";    // Misc
            default: return "󰈸";
        }
    }

    function updateShownWorkspaces() {
        const wsById = {};
        const idsToShow = {};

        if (Hyprland.workspaces && Hyprland.workspaces.values) {
            Hyprland.workspaces.values.forEach(function(w) {
                if (!w || w.id <= 0) return;
                wsById[w.id] = w;
                if (shouldShowExtraWorkspace(w)) idsToShow[w.id] = true;
            });
        }

        for (let i = 1; i <= root.minimumWorkspaces; i++) {
            idsToShow[i] = true;
        }

        const focusedId = (Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.id)
            ? Hyprland.focusedWorkspace.id
            : 1;

        const sortedIds = Object.keys(idsToShow).map(Number).sort(function(a, b) { return a - b; });
        const result = [];
        for (let i = 0; i < sortedIds.length; i++) {
            const id = sortedIds[i];
            result.push(wsById[id] || root.makePlaceholderWorkspace(id, focusedId));
        }
        root.shownWorkspaces = result;
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

    // === Content ===
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
                color: isActive ? bar.wsActiveBg :
                       (isHovered ? bar.wsHoverYellow : "transparent")
                border.width: isActive ? bar.controlBorderWidth : 0
                border.color: isActive ? bar.wsActiveBorder : bar.dividerStrong

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
                        font.pixelSize: bar.wsIconSize
                        color: isActive ? bar.wsActiveText :
                               (isHovered ? "#111111" : bar.clock)
                        font.family: bar.fontFamily
                        font.bold: true
                    }
                    Text {
                        text: modelData ? modelData.id : ""
                        font.pixelSize: bar.wsNumberSize || 15
                        font.bold: true
                        color: isActive ? bar.wsActiveText :
                               (isHovered ? "#111111" : bar.clock)
                    }
                }
            }
        }
    }
}
