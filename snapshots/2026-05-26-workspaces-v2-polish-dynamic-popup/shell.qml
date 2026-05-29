import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import Quickshell.Hyprland

PanelWindow {
    id: bar

    anchors.top: true
    anchors.left: true
    anchors.right: true
    implicitHeight: 46
    color: "transparent"

    // ===== Theme =====
    property color bg: "#1e1e2e"
    property color surface: "#313244"
    property color text: "#cdd6f4"
    property color subtext: "#a6adc8"
    property color overlay: "#6c7086"
    property color accent: "#89b4fa"
    property color todayBg: "#89b4fa"
    property color weekday: "#ff5c5c"
    property color clock: "#ffffff"
    property int barRadius: 14
    property int sideMargin: 10

    // ===== Workspaces (eww migration) =====
    // Yellow hover shade taken from eww working scss (rgb(253, 249, 219))
    readonly property color wsHoverYellow: "#fdf9db"
    readonly property color wsActiveBg: "#1e1e1e"
    readonly property color wsText: "#64748b"
    readonly property color wsActiveText: "#e2e8f0"

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

    // ===== Bar Content =====
    Rectangle {
        id: barBg
        anchors.fill: parent
        anchors.leftMargin: bar.sideMargin
        anchors.rightMargin: bar.sideMargin
        anchors.topMargin: 3
        anchors.bottomMargin: 3
        radius: bar.barRadius
        color: bar.bg
        border.width: 1
        border.color: "#45475a"

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            spacing: 12

            // Left side - Workspaces (from eww migration: icons+num, only active/occupied,
            // reactive via Quickshell.Hyprland (no polling), yellow hover, active highlight,
            // scroll wheel, click to focus, hover preview support)
            Item {
                id: workspacesContainer
                Layout.preferredWidth: wsRow.implicitWidth + 8
                Layout.preferredHeight: 32
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
                    spacing: 3

                    Repeater {
                        model: bar.shownWorkspaces
                        delegate: Rectangle {
                            id: wsBtn
                            required property var modelData // HyprlandWorkspace
                            required property int index
                            property bool isActive: modelData && (modelData.active || modelData.focused)
                            property bool isHovered: wsMouse.containsMouse

                            width: 38
                            height: 28
                            radius: 8
                            color: isActive ? bar.wsActiveBg :
                                   (isHovered ? bar.wsHoverYellow : "transparent")
                            border.width: isActive ? 1 : 0
                            border.color: "#45475a"

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
                            Row {
                                anchors.centerIn: parent
                                spacing: 3
                                Text {
                                    text: bar.getWsIcon(modelData ? modelData.id : 0)
                                    font.pixelSize: 12
                                    color: isActive ? bar.wsActiveText :
                                           (isHovered ? "#111111" : bar.wsText)
                                    font.family: "JetBrains Mono Nerd Font, Symbols Nerd Font, monospace"
                                }
                                Text {
                                    text: modelData ? modelData.id : ""
                                    font.pixelSize: 11
                                    font.bold: isActive
                                    color: isActive ? bar.wsActiveText :
                                           (isHovered ? "#111111" : bar.wsText)
                                }
                            }
                        }
                    }
                }
            }

            Item { Layout.fillWidth: true }

            // ===== CLOCK (clickable) =====
            Rectangle {
                id: clockButton
                Layout.preferredWidth: clockLabel.implicitWidth + 28
                Layout.preferredHeight: 30
                radius: 10
                color: clockArea.containsMouse ? bar.surface : "transparent"
                border.width: clockArea.containsMouse ? 1 : 0
                border.color: bar.accent

                Text {
                    id: clockLabel
                    anchors.centerIn: parent
                    text: Qt.formatDateTime(new Date(), "dddd, MM·dd·yyyy | HH:mm:ss")
                    color: bar.clock
                    font.pixelSize: 13
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
        implicitHeight: 355
        visible: false

        // Rounded popup background
        Rectangle {
            anchors.fill: parent
            radius: 16
            color: bar.bg
            border.width: 1
            border.color: "#45475a"

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
                            Layout.minimumHeight: 30

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
        implicitWidth: 280
        implicitHeight: {
            const ws = bar.hoveredWorkspace;
            const count = (ws && ws.toplevels && typeof ws.toplevels.count === "number") ? ws.toplevels.count : 0;
            const base = 46; // header + margins
            return Math.max(60, Math.min(200, base + count * 16));
        }
        visible: bar.hoveredWorkspace !== null
        color: "transparent"

        Rectangle {
            anchors.fill: parent
            radius: 10
            color: bar.bg
            border.width: 1
            border.color: "#45475a"

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 6

                Text {
                    text: bar.hoveredWorkspace ? ("Workspace " + bar.hoveredWorkspace.id + "  ·  " + (bar.hoveredWorkspace.toplevels && bar.hoveredWorkspace.toplevels.count ? bar.hoveredWorkspace.toplevels.count : 0) + " window(s)") : ""
                    color: bar.text
                    font.pixelSize: 12
                    font.bold: true
                }

                // Simple preview list of window titles (or class from lastIpcObject if available)
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 2
                    Repeater {
                        model: (bar.hoveredWorkspace && bar.hoveredWorkspace.toplevels) ? bar.hoveredWorkspace.toplevels : []
                        delegate: Text {
                            required property var modelData
                            Layout.fillWidth: true
                            text: {
                                if (!modelData) return "";
                                const t = modelData.title || "";
                                const klass = (modelData.lastIpcObject && modelData.lastIpcObject["class"]) ? " (" + modelData.lastIpcObject["class"] + ")" : "";
                                return "• " + (t.length > 42 ? t.substring(0,39) + "…" : t) + klass;
                            }
                            color: bar.subtext
                            font.pixelSize: 10
                            elide: Text.ElideRight
                        }
                    }
                    Text {
                        visible: bar.hoveredWorkspace && (!bar.hoveredWorkspace.toplevels || bar.hoveredWorkspace.toplevels.count === 0)
                        text: "(empty workspace - only active)"
                        color: bar.overlay
                        font.pixelSize: 10
                        font.italic: true
                    }
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
}
