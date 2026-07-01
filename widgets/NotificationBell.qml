import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell

// =============================================================================
// NotificationBell.qml — Swaync-backed notification indicator
// =============================================================================
//
// Purpose:
//   Shows a bell icon with optional count badge. Supports Do Not Disturb (DND) state.
//   Left-click toggles the notification center. Right-click toggles DND.
//
// Theme Properties Consumed:
//   - bar.pillRadius, bar.pillBg, bar.glassHover, bar.pillBorder, bar.accent
//   - bar.iconSizePillLarge, bar.fontFamily, bar.fontMono, bar.fontTiny
//   - bar.muted, bar.controlBorderWidth, bar.tooltipDelay
//
// Dependencies:
//   - required property var bar (from shell.qml)
//   - required property QtObject notif (shared state from shell.qml, populated by swaync subscribe)
//
// Notes:
//   - The dark text color on the accent badge ("#111111") is a contrast choice.
//     A future "textOnAccent" token could be added if we see this pattern elsewhere.
// =============================================================================

Rectangle {
    id: root

    // === Required Properties ===
    required property var bar
    required property QtObject notif   // shared notification state from shell.qml

    // === Layout — square pill, same size as PowerMenu for a consistent click target ===
    Layout.preferredWidth: 42
    Layout.preferredHeight: bar.pillHeight
    Layout.alignment: Qt.AlignVCenter

    // === Appearance via Theme ===
    radius: bar.pillRadius
    color: bellMouse.containsMouse ? bar.glassHover : bar.pillBg
    border.width: bar.controlBorderWidth
    border.color: bellMouse.containsMouse ? bar.accent : bar.pillBorder

    // === Content ===
    Text {
        id: bellIcon
        anchors.centerIn: parent
        text: notif.icon
        font.pixelSize: bar.iconSizePillLarge
        font.family: bar.fontFamily
        color: notif.dnd ? bar.muted : (notif.count > 0 ? bar.accent : bar.subtext)
    }

    // Counter badge — overlaid so the pill stays the same width
    Rectangle {
        visible: notif.count > 0
        width: Math.max(16, countLabel.implicitWidth + 6)
        height: 16
        radius: 8
        color: notif.dnd ? Qt.rgba(0.6, 0.2, 0.2, 0.9) : bar.accent
        anchors.top: bellIcon.top
        anchors.right: bellIcon.right
        anchors.topMargin: -5
        anchors.rightMargin: -8

        Text {
            id: countLabel
            anchors.centerIn: parent
            text: notif.count > 99 ? "99+" : notif.count
            color: "#111111"
            font.pixelSize: bar.fontTiny
            font.bold: true
            font.family: bar.fontMono
        }
    }

    // === Public API (toggle from shell IPC: qs ipc call notificationBell toggleDoNotDisturb) ===
    function toggleDoNotDisturb() {
        Quickshell.execDetached(["swaync-client", "-d", "-sw"])
    }

    // === Behavior ===
    MouseArea {
        id: bellMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        ToolTip.text: {
            if (notif.dnd) return notif.count + " notifications (DND enabled)"
            if (notif.count > 0) return notif.count + " notifications"
            return "No notifications"
        }
        ToolTip.visible: containsMouse
        ToolTip.delay: bar.tooltipDelay

        onClicked: (mouse) => {
            if (mouse.button === Qt.RightButton) {
                root.toggleDoNotDisturb()
            } else if (mouse.button === Qt.LeftButton) {
                Quickshell.execDetached(["swaync-client", "-t", "-sw"])
            }
        }
    }
}
