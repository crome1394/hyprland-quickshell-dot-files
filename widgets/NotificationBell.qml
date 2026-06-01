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
//   - bar.iconSizePill, bar.fontFamily, bar.fontMono, bar.fontSmall
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

    // === Layout (for RowLayout participation in the bar) ===
    Layout.preferredWidth: bellRow.implicitWidth + 18
    Layout.preferredHeight: 36
    Layout.alignment: Qt.AlignVCenter

    // === Appearance via Theme ===
    radius: bar.pillRadius
    color: bellMouse.containsMouse ? bar.glassHover : bar.pillBg
    border.width: bar.controlBorderWidth
    border.color: bellMouse.containsMouse ? bar.accent : bar.pillBorder

    // === Content ===
    Row {
        id: bellRow
        anchors.centerIn: parent
        spacing: 6

        Text {
            id: bellIcon
            text: notif.icon
            font.pixelSize: bar.iconSizePill
            font.family: bar.fontFamily
            color: notif.dnd ? bar.muted : (notif.count > 0 ? bar.accent : bar.subtext)
            anchors.verticalCenter: parent.verticalCenter
        }

        // Counter badge (only shown when count > 0)
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
                color: "#111111"   // Contrast text on accent badge (consider future textOnAccent token)
                font.pixelSize: bar.fontSmall
                font.bold: true
                font.family: bar.fontMono
            }
        }
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
                Quickshell.execDetached(["swaync-client", "-d", "-sw"])
            } else if (mouse.button === Qt.LeftButton) {
                Quickshell.execDetached(["swaync-client", "-t", "-sw"])
            }
        }
    }
}
