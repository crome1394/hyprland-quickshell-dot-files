import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// NotificationBell.qml
// Swaync-backed notification bell pill with count badge and DND support.
// Extracted from the original monolithic shell.qml.

Rectangle {
    id: root

    required property var bar
    required property QtObject notif   // the shared notif state object

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

        // Counter badge (only when > 0)
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

        ToolTip.text: {
            if (notif.dnd) return notif.count + " notifications (DND enabled)";
            if (notif.count > 0) return notif.count + " notifications";
            return "No notifications";
        }
        ToolTip.visible: containsMouse
        ToolTip.delay: 650

        onClicked: (mouse) => {
            if (mouse.button === Qt.RightButton) {
                Quickshell.execDetached(["swaync-client", "-d", "-sw"])
            } else if (mouse.button === Qt.LeftButton) {
                Quickshell.execDetached(["swaync-client", "-t", "-sw"])
            }
        }
    }
}
