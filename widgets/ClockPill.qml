import QtQuick
import QtQuick.Layouts
import Quickshell

// =============================================================================
// ClockPill.qml — Clock + Calendar popup
// =============================================================================
//
// Purpose:
//   Displays a live updating clock. Click opens a self-contained calendar popup
//   with month/year navigation and a 42-cell grid.
//
// Theme Properties Consumed:
//   - bar.pillRadius, bar.pillBg, bar.glassHover, bar.pillBorder, bar.accent
//   - bar.clock, bar.fontClock, bar.fontMono, bar.fontTiny
//   - bar.popupRadius, bar.glassPopupBg, bar.glassPopupBorder, bar.glassPopupHighlight
//   - bar.popupHeaderHighlightHeight, bar.popupSpacing, bar.popupTitleSize,
//     bar.popupSectionSize, bar.popupHintSize, bar.popupSectionSpacing,
//     bar.popupGridSpacing, bar.buttonRadius, bar.controlBorderWidth
//   - bar.todayBg, bar.weekday, bar.text, bar.overlay, bar.bg
//
// Dependencies:
//   - required property var bar (from shell.qml)
//   - required property Item barBg (for accurate popup positioning)
//
// Notes:
//   - Calendar logic and popup positioning are self-contained.
//   - Additional centralization applied only for buttons, spacing, and fonts as requested.
//   - A few small new tokens (popupGridSpacing, popupNavButtonSize, etc.) would be beneficial
//     in Theme.qml for full cleanliness.
// =============================================================================

Rectangle {
    id: root

    // === Required Properties ===
    required property var bar
    required property Item barBg   // needed for accurate popup positioning

    // === Layout (for RowLayout participation in the bar) ===
    Layout.preferredWidth: clockLabel.implicitWidth + 28
    Layout.preferredHeight: 36
    Layout.alignment: Qt.AlignVCenter

    // === Appearance via Theme ===
    radius: bar.pillRadius
    color: clockArea.containsMouse ? bar.glassHover : bar.pillBg
    border.width: bar.controlBorderWidth
    border.color: clockArea.containsMouse ? bar.accent : bar.pillBorder

    // === Content ===
    Text {
        id: clockLabel
        anchors.centerIn: parent
        text: Qt.formatDateTime(new Date(), "dddd, MM·dd·yyyy | HH:mm:ss")
        color: bar.clock
        font.pixelSize: bar.fontClock
        font.family: bar.fontMono
        font.bold: true
    }

    // === Behavior ===
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

    // ===== Calendar Logic (tightly coupled to this widget) =====
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

    // ===== CALENDAR POPUP (owned by the clock) =====
    PopupWindow {
        id: calendarPopup
        anchor.window: bar
        implicitWidth: bar.popupCalendarWidth
        implicitHeight: bar.popupCalendarHeight
        visible: false
        color: "transparent"

        // Glassmorphic popup background
        Rectangle {
            anchors.fill: parent
            radius: bar.popupRadius
            color: bar.glassPopupBg
            border.width: bar.controlBorderWidth
            border.color: bar.glassPopupBorder

            // Top highlight for glass effect
            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: bar.popupHeaderHighlightHeight
                color: bar.glassPopupHighlight
                radius: parent.radius
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: bar.popupSpacing
                spacing: bar.popupSectionSpacing + 4

                // Header: Month + Year + Navigation
                RowLayout {
                    Layout.fillWidth: true
                    spacing: bar.popupSectionSpacing

                    Text {
                        Layout.fillWidth: true
                        text: Qt.formatDateTime(new Date(calendar.viewedYear, calendar.viewedMonth, 1), "MMMM yyyy")
                        color: bar.text
                        font.pixelSize: bar.popupTitleSize
                        font.bold: true
                        horizontalAlignment: Text.AlignLeft
                    }

                    // Nav buttons
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
                            radius: bar.buttonRadius
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
                        radius: bar.buttonRadius
                        color: todayBtnMa.containsMouse ? bar.accent : bar.surface

                        Text {
                            anchors.centerIn: parent
                            text: "Today"
                            color: todayBtnMa.containsMouse ? bar.bg : bar.text
                            font.pixelSize: bar.popupHintSize
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

                // Weekday headers
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
                            font.pixelSize: bar.popupHintSize
                            font.bold: true
                        }
                    }
                }

                // Calendar grid (42 cells)
                GridLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    columns: 7
                    rowSpacing: bar.popupGridSpacing
                    columnSpacing: bar.popupGridSpacing

                    Repeater {
                        model: 42
                        delegate: Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.minimumHeight: 22

                            // Day calculation
                            property int firstDay: new Date(calendar.viewedYear, calendar.viewedMonth, 1).getDay()
                            property int leadingEmpty: (firstDay === 0) ? 6 : (firstDay - 1)
                            property int daysInMonth: new Date(calendar.viewedYear, calendar.viewedMonth + 1, 0).getDate()
                            property int dayNum: index - leadingEmpty + 1

                            property bool isCurrentMonth: dayNum >= 1 && dayNum <= daysInMonth
                            property int displayNum: {
                                if (isCurrentMonth) return dayNum
                                if (dayNum < 1) {
                                    var prevDays = new Date(calendar.viewedYear, calendar.viewedMonth, 0).getDate()
                                    return prevDays + dayNum
                                }
                                return dayNum - daysInMonth
                            }

                            property bool isToday: {
                                var now = new Date()
                                return isCurrentMonth &&
                                       calendar.viewedYear === now.getFullYear() &&
                                       calendar.viewedMonth === now.getMonth() &&
                                       dayNum === now.getDate()
                            }

                            // Today highlight
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
                    Layout.topMargin: bar.popupSectionSpacing

                    Text {
                        Layout.fillWidth: true
                        text: "Current day is highlighted"
                        color: bar.overlay
                        font.pixelSize: bar.fontTiny
                    }

                    Text {
                        text: "click clock to close"
                        color: bar.overlay
                        font.pixelSize: bar.fontTiny
                    }
                }
            }
        }
    }

    // Helper to position + show the calendar popup
    function showCalendarPopup() {
        var pos = root.mapToItem(barBg, root.width / 2, root.height)

        var popupWidth = calendarPopup.implicitWidth
        var targetX = bar.sideMargin + pos.x - (popupWidth / 2)

        var screenW = (bar.screen && bar.screen.width) ? bar.screen.width : 1920
        var minX = 12
        var maxX = screenW - popupWidth - 12

        calendarPopup.anchor.rect.x = Math.max(minX, Math.min(targetX, maxX))
        calendarPopup.anchor.rect.y = bar.implicitHeight + 2

        calendarPopup.visible = true
    }
}
