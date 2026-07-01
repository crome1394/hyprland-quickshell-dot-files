import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell

// =============================================================================
// NotificationBell.qml — Configurable notification daemon bell
// =============================================================================
//
// Purpose:
//   Bell icon with optional count badge. Backend is set in Config.qml
//   (search NOTIFICATION BELL — edit notification* command lists).
//
// Theme Properties Consumed:
//   - bar.pillRadius, bar.pillBg, bar.glassHover, bar.pillBorder, bar.accent
//   - bar.glassPopupBg, bar.glassPopupBorder, bar.glassPopupHighlight
//   - bar.popupRadius, bar.popupTitleSize, bar.popupHintSize, bar.popupSpacingTight
//   - bar.popupContextMenuWidth, bar.popupContextMenuRowHeight, bar.popupButtonHoverBg
//   - bar.iconSizePillLarge, bar.fontFamily, bar.fontMono, bar.fontTiny
//   - bar.muted, bar.text, bar.subtext, bar.overlay, bar.controlBorderWidth
//   - bar.buttonRadius, bar.dividerStrong, bar.tooltipDelay, bar.popupAnchorY()
//   - bar.execNotificationCommand, bar.notificationSupportsPanel/Dnd/ClearAll

//
// Dependencies:
//   - required property var bar (from shell.qml)
//   - required property Item barBg (popup positioning)
//   - required property QtObject notif (shared state from shell.qml)
//
// =============================================================================

Rectangle {
    id: root

    required property var bar
    required property Item barBg
    required property QtObject notif

    Layout.preferredWidth: 42
    Layout.preferredHeight: bar.pillHeight
    Layout.alignment: Qt.AlignVCenter

    radius: bar.pillRadius
    color: bellMouse.containsMouse ? bar.glassHover : bar.pillBg
    border.width: bar.controlBorderWidth
    border.color: bellMouse.containsMouse ? bar.accent : bar.pillBorder

    Text {
        id: bellIcon
        anchors.centerIn: parent
        text: notif.icon
        font.pixelSize: bar.iconSizePillLarge
        font.family: bar.fontFamily
        color: notif.dnd ? bar.muted : (notif.count > 0 ? bar.accent : bar.subtext)
    }

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

    function toggleDoNotDisturb() {
        bar.execNotificationCommand("toggleDnd")
    }

    function clearAllNotifications() {
        bar.execNotificationCommand("clearAll")
    }

    function hideNotifMenu() {
        notifMenuPopup.visible = false
    }

    function showNotifMenu() {
        if (notifMenuPopup.visible) {
            hideNotifMenu()
            return
        }

        var pos = root.mapToItem(barBg, root.width / 2, 0)
        var popupW = notifMenuPopup.implicitWidth
        var screenW = (bar.screen && bar.screen.width) ? bar.screen.width : 1920
        var targetX = bar.sideMargin + pos.x - (popupW / 2)
        var minX = 12
        var maxX = screenW - popupW - 12

        notifMenuPopup.anchor.rect.x = Math.max(minX, Math.min(targetX, maxX))
        notifMenuPopup.anchor.rect.y = bar.popupAnchorY(notifMenuPopup.implicitHeight, 2)
        notifMenuPopup.visible = true
    }

    MouseArea {
        id: bellMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        ToolTip.text: {
            if (notif.dnd) return notif.count + " notifications (DND on) · Right-click: menu"
            if (notif.count > 0) return notif.count + " notifications · Right-click: menu"
            if (bar.notificationSupportsPanel())
                return "Toggle notification panel · Right-click: menu"
            return "Notifications · Right-click: menu"
        }
        ToolTip.visible: containsMouse
        ToolTip.delay: bar.tooltipDelay

        onClicked: (mouse) => {
            if (mouse.button === Qt.RightButton) {
                showNotifMenu()
            } else {
                hideNotifMenu()
                if (bar.notificationSupportsPanel())
                    bar.execNotificationCommand("togglePanel")
            }
        }
    }

    PopupWindow {
        id: notifMenuPopup
        anchor.window: bar
        implicitWidth: bar.popupContextMenuWidth
        implicitHeight: notifMenuColumn.implicitHeight + bar.popupSpacingTight * 2
        visible: false
        grabFocus: true
        color: "transparent"
        Rectangle {
            anchors.fill: parent
            radius: bar.popupRadius
            color: bar.glassPopupBg
            border.width: bar.controlBorderWidth
            border.color: bar.glassPopupBorder

            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: bar.popupHeaderHighlightHeight
                color: bar.glassPopupHighlight
                radius: parent.radius
            }

            ColumnLayout {
                id: notifMenuColumn
                anchors.fill: parent
                anchors.margins: bar.popupSpacingTight
                spacing: 4

                Text {
                    Layout.fillWidth: true
                    text: "Notifications"
                    color: bar.text
                    font.pixelSize: bar.popupTitleSize
                    font.bold: true
                    font.family: bar.fontFamily
                }

                Rectangle {
                    visible: bar.notificationSupportsDnd()
                    Layout.fillWidth: true
                    Layout.preferredHeight: bar.popupContextMenuRowHeight
                    radius: bar.buttonRadius
                    color: dndRowMa.containsMouse ? bar.popupButtonHoverBg : Qt.rgba(0.10, 0.10, 0.12, 0.6)
                    border.width: bar.controlBorderWidth
                    border.color: bar.dividerStrong

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        text: notif.dnd ? "Turn off Do Not Disturb" : "Turn on Do Not Disturb"
                        color: notif.dnd ? bar.muted : bar.text
                        font.pixelSize: 12
                        font.family: bar.fontFamily
                    }

                    MouseArea {
                        id: dndRowMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            toggleDoNotDisturb()
                            hideNotifMenu()
                        }
                    }
                }

                Rectangle {
                    visible: bar.notificationSupportsClearAll()
                    Layout.fillWidth: true
                    Layout.preferredHeight: bar.popupContextMenuRowHeight
                    radius: bar.buttonRadius
                    color: clearRowMa.containsMouse ? bar.popupButtonHoverBg : Qt.rgba(0.10, 0.10, 0.12, 0.6)
                    border.width: bar.controlBorderWidth
                    border.color: bar.dividerStrong

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        text: "Clear all notifications"
                        color: bar.text
                        font.pixelSize: 12
                        font.family: bar.fontFamily
                    }

                    MouseArea {
                        id: clearRowMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            clearAllNotifications()
                            hideNotifMenu()
                        }
                    }
                }

                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignRight
                    text: "click outside to close"
                    color: bar.overlay
                    font.pixelSize: bar.popupHintSize
                    font.family: bar.fontFamily
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            z: -1
            onClicked: hideNotifMenu()
        }
    }
}