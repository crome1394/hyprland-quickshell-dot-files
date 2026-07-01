import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io as Io

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
//   - bar.notificationCmdArray, bar.notificationSyncEnabled, bar.notificationUsesLiveSubscribe
//   - bar.notificationSyncIntervalMs, bar.execNotificationCommand
//   - bar.notificationSupportsPanel/Dnd/ClearAll, bar.notificationDndAccent
//
// Dependencies:
//   - required property var bar (from shell.qml)
//   - required property Item barBg (popup positioning)
//
// =============================================================================

Rectangle {
    id: root

    required property var bar
    required property Item barBg

    property int count: 0
    property bool dnd: false
    property bool inhibited: false

    readonly property string bellGlyph: {
        if (dnd) return count > 0 ? "󰂠" : "󰪓"
        return count > 0 ? "󱅫" : "󰂜"
    }

    Layout.preferredWidth: 42
    Layout.preferredHeight: bar.pillHeight
    Layout.alignment: Qt.AlignVCenter

    radius: bar.pillRadius
    color: dnd
           ? (bellMouse.containsMouse ? Qt.rgba(0.55, 0.14, 0.14, 0.45) : Qt.rgba(0.40, 0.10, 0.10, 0.32))
           : (bellMouse.containsMouse ? bar.glassHover : bar.pillBg)
    border.width: bar.controlBorderWidth
    border.color: dnd
                  ? bar.notificationDndAccent
                  : (bellMouse.containsMouse ? bar.accent : bar.pillBorder)

    function applyState(j) {
        if (j === undefined || j === null) return
        if (j.count !== undefined && j.count !== null)
            root.count = Math.max(0, Number(j.count) || 0)
        if (j.dnd !== undefined && j.dnd !== null) {
            if (typeof j.dnd === "boolean")
                root.dnd = j.dnd
            else
                root.dnd = String(j.dnd).toLowerCase() === "true"
        }
        if (j.inhibited !== undefined && j.inhibited !== null) {
            if (typeof j.inhibited === "boolean")
                root.inhibited = j.inhibited
            else
                root.inhibited = String(j.inhibited).toLowerCase() === "true"
        }
    }

    function finishSyncPoll() {
        const line = (syncStdout.text || "").trim()
        if (!line.startsWith("{")) return
        try {
            root.applyState(JSON.parse(line))
        } catch (e) {}
    }

    function startSyncPoll() {
        if (!bar.notificationSyncEnabled() || syncProcess.running)
            return
        const args = bar.notificationCmdArray("sync")
        if (args.length <= 0)
            return
        syncProcess.exec(args)
    }

    function startSubscribe() {
        if (!bar.notificationUsesLiveSubscribe() || subscribeProcess.running)
            return
        const args = bar.notificationCmdArray("subscribe")
        if (args.length <= 0)
            return
        subscribeProcess.exec(args)
    }

    function refreshState() {
        root.startSyncPoll()
    }

    Io.Process {
        id: syncProcess
        running: false
        stdout: Io.StdioCollector {
            id: syncStdout
            onStreamFinished: root.finishSyncPoll()
        }
        onExited: Qt.callLater(root.finishSyncPoll)
    }

    Timer {
        id: syncTimer
        interval: bar.notificationSyncIntervalMs
        running: bar.notificationSyncEnabled()
        repeat: true
        triggeredOnStart: true
        onTriggered: root.startSyncPoll()
    }

    Io.Process {
        id: subscribeProcess
        running: false
        stdout: Io.SplitParser {
            splitMarker: "\n"
            onRead: (data) => {
                const line = data.trim()
                if (!line) return
                try {
                    root.applyState(JSON.parse(line))
                } catch (e) {}
            }
        }
        onExited: {
            if (bar.notificationUsesLiveSubscribe())
                subscribeRestartTimer.restart()
        }
    }

    Timer {
        id: subscribeRestartTimer
        interval: 2000
        onTriggered: root.startSubscribe()
    }

    Component.onCompleted: {
        Qt.callLater(function() {
            root.startSyncPoll()
            root.startSubscribe()
        })
    }

    Text {
        id: bellIcon
        anchors.centerIn: parent
        text: root.bellGlyph
        font.pixelSize: bar.iconSizePillLarge
        font.family: bar.fontFamily
        color: dnd
               ? bar.notificationDndAccent
               : (count > 0 ? bar.accent : bar.subtext)
    }

    Rectangle {
        visible: count > 0
        z: 1
        width: Math.max(16, countLabel.implicitWidth + 6)
        height: 16
        radius: 8
        color: dnd ? Qt.rgba(0.75, 0.18, 0.18, 0.95) : bar.accent
        anchors.top: bellIcon.top
        anchors.right: bellIcon.right
        anchors.topMargin: -5
        anchors.rightMargin: -8

        Text {
            id: countLabel
            anchors.centerIn: parent
            text: count > 99 ? "99+" : count
            color: "#111111"
            font.pixelSize: bar.fontTiny
            font.bold: true
            font.family: bar.fontMono
        }
    }

    function toggleDoNotDisturb() {
        bar.execNotificationCommand("toggleDnd")
        Qt.callLater(function() { root.refreshState() })
    }

    function clearAllNotifications() {
        bar.execNotificationCommand("clearAll")
        Qt.callLater(function() { root.refreshState() })
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
            if (dnd) return count + " notifications (DND on) · Right-click: menu"
            if (count > 0) return count + " notifications · Right-click: menu"
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
                        text: dnd ? "Turn off Do Not Disturb" : "Turn on Do Not Disturb"
                        color: dnd ? bar.notificationDndAccent : bar.text
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