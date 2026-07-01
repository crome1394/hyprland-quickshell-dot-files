import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland

// =============================================================================
// WorkspacesPill.qml — Dynamic workspace pills
// =============================================================================
//
// Purpose:
//   Shows numbered Hyprland workspace pills and an optional magic-space pill.
//   Display rules come from config.qml (via bar.*): minimum count, active-only
//   mode, and magic pill visibility (config default + IPC override).
//
// Config / bar properties consumed:
//   - bar.wsMinimumShown, bar.wsShowOnlyActive, bar.showMagicWorkspacePill
//   - bar.wsIconForId(id), bar.wsIconSpecial, bar.wsSpecialName, bar.wsIsSpecialName(name)
//   - bar.pillRadius, bar.glassPillBg, bar.glassBorder, bar.controlBorderWidth
//   - bar.wsButtonWidth, bar.wsButtonHeight, bar.workspaceRadius
//   - bar.wsSpacing, bar.wsIconSize, bar.wsNumberSize
//   - bar.wsActiveBg, bar.wsActiveBorder, bar.wsActiveText
//   - bar.wsHoverYellow, bar.clock, bar.fontFamily
//
// IPC (runtime magic pill toggle):
//   qs ipc call shell setShowMagicWorkspacePill false
//   qs ipc call shell toggleShowMagicWorkspacePill
//
// Notes:
//   - Workspace icons live in config.qml (wsIcon1…wsIcon10, wsIconSpecial).
//   - Activation uses root.activateEntry() — do not store functions on model
//     objects (QML Repeater strips them from plain JS objects).
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

    // === Appearance via config (bar aliases) ===
    color: bar.glassPillBg
    radius: bar.pillRadius
    border.width: bar.controlBorderWidth
    border.color: bar.glassBorder

    // ===== Workspace logic (tightly coupled to this widget) =====
    property var shownWorkspaces: []

    function workspaceHasWindows(w) {
        if (!w || !w.toplevels) return false;
        if (typeof w.toplevels.count === "number") return w.toplevels.count > 0;
        if (w.toplevels.values && typeof w.toplevels.values.length === "number") return w.toplevels.values.length > 0;
        return false;
    }

    // Extra numbered workspaces (6+) only appear when occupied or active.
    function shouldShowExtraWorkspace(w) {
        if (!w || w.id <= 0) return false;
        return workspaceHasWindows(w) || w.active || w.focused;
    }

    function makePlaceholderWorkspace(id, focusedId) {
        return {
            id: id,
            isSpecial: false,
            active: false,
            focused: focusedId === id
        };
    }

    // Central activation path — plain JS model objects cannot keep function props.
    // Hyprland 0.55+ lua configs require hl.dsp.* dispatch strings (legacy
    // "workspace N" / "togglespecialworkspace" IPC is rejected by hl.dispatch).
    function activateEntry(entry) {
        if (!entry) return;

        if (entry.isSpecial) {
            Hyprland.dispatch("hl.dsp.workspace.toggle_special('" + bar.wsSpecialName + "')");
            return;
        }

        if (entry.id > 0) {
            Hyprland.dispatch("hl.dsp.focus({ workspace = " + entry.id + " })");
        }
    }

    // Special workspace is an overlay — focusedWorkspace may stay on the last
    // numbered ws while magic is visible. activeToplevel.workspace is reliable.
    function isSpecialWorkspaceActive() {
        const toplevel = Hyprland.activeToplevel;
        if (toplevel && toplevel.workspace && bar.wsIsSpecialName(toplevel.workspace.name))
            return true;
        const hyprWs = root.findSpecialWorkspace();
        if (hyprWs && (hyprWs.active || hyprWs.focused)) return true;
        const focusedWs = Hyprland.focusedWorkspace;
        return focusedWs && bar.wsIsSpecialName(focusedWs.name);
    }

    function findSpecialWorkspace() {
        if (!Hyprland.workspaces || !Hyprland.workspaces.values) return null;
        const values = Hyprland.workspaces.values;
        for (let i = 0; i < values.length; i++) {
            const w = values[i];
            if (w && w.id < 0 && bar.wsIsSpecialName(w.name)) return w;
        }
        return null;
    }

    function makeSpecialWorkspaceEntry() {
        const hyprWs = root.findSpecialWorkspace();
        const specialActive = root.isSpecialWorkspaceActive();

        if (hyprWs) {
            return {
                id: hyprWs.id,
                isSpecial: true,
                active: specialActive,
                focused: specialActive
            };
        }

        return {
            id: -1,
            isSpecial: true,
            active: specialActive,
            focused: specialActive
        };
    }

    function workspaceMatchesFocus(entry, focusedWs) {
        if (!entry) return false;
        if (entry.isSpecial) return root.isSpecialWorkspaceActive();
        if (!focusedWs || focusedWs.id <= 0) return false;
        return entry.id === focusedWs.id;
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

        // config.wsShowOnlyActive false → always show pills 1..wsMinimumShown
        if (!bar.wsShowOnlyActive) {
            const minimum = Math.max(1, bar.wsMinimumShown || 1);
            for (let i = 1; i <= minimum; i++) {
                idsToShow[i] = true;
            }
        }

        const focusedId = (Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.id > 0)
            ? Hyprland.focusedWorkspace.id
            : 1;

        const sortedIds = Object.keys(idsToShow).map(Number).sort(function(a, b) { return a - b; });
        const result = [];
        if (bar.showMagicWorkspacePill) {
            result.push(root.makeSpecialWorkspaceEntry());
        }
        for (let i = 0; i < sortedIds.length; i++) {
            const id = sortedIds[i];
            result.push(wsById[id] || root.makePlaceholderWorkspace(id, focusedId));
        }

        root.shownWorkspaces = result;
    }

    function switchToRelative(delta) {
        if (!root.shownWorkspaces || root.shownWorkspaces.length === 0) return;

        const focusedWs = Hyprland.focusedWorkspace;
        let idx = -1;
        for (let i = 0; i < root.shownWorkspaces.length; i++) {
            if (workspaceMatchesFocus(root.shownWorkspaces[i], focusedWs)) {
                idx = i;
                break;
            }
        }
        if (idx < 0) idx = 0;

        let newIdx = idx + delta;
        if (newIdx < 0) newIdx = 0;
        if (newIdx >= root.shownWorkspaces.length) newIdx = root.shownWorkspaces.length - 1;

        root.activateEntry(root.shownWorkspaces[newIdx]);
    }

    Connections {
        target: Hyprland.workspaces
        function onValuesChanged() { root.updateShownWorkspaces(); }
    }
    Connections {
        target: Hyprland
        function onFocusedWorkspaceChanged() { root.updateShownWorkspaces(); }
        function onActiveToplevelChanged() { root.updateShownWorkspaces(); }
    }
    Connections {
        target: bar
        function onShowMagicWorkspacePillChanged() { root.updateShownWorkspaces(); }
    }

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
                property bool isSpecial: !!(modelData && modelData.isSpecial)
                property bool isActive: !!(modelData && (modelData.active || modelData.focused))
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
                    onClicked: root.activateEntry(modelData)
                }

                Row {
                    anchors.centerIn: parent
                    spacing: 3

                    Text {
                        text: isSpecial
                              ? bar.wsIconSpecial
                              : bar.wsIconForId(modelData ? modelData.id : 0)
                        font.pixelSize: bar.wsIconSize
                        color: isActive ? bar.wsActiveText :
                               (isHovered ? "#111111" : bar.clock)
                        font.family: bar.fontFamily
                        font.bold: true
                    }
                    Text {
                        visible: !isSpecial
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