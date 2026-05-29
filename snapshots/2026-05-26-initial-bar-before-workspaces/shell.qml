import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

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

            // Left side - identifier
            Text {
                text: "cachy"
                color: bar.subtext
                font.pixelSize: 13
                font.bold: true
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
}
