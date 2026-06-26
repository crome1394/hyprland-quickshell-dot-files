import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Live CPU monitoring tab content (SysMonService + gauge + sparkline).
Item {
    id: root

    required property var service

    property color textColor: "#cdd6f4"
    property color subtextColor: "#a6adc8"
    property color accentColor: "#89b4fa"
    property color surfaceColor: "#313244"
    property color overlayColor: "#6c7086"

    readonly property int cardRadius: 6
    readonly property int cardMargin: 10
    readonly property int processRowHeight: 14
    readonly property int processHeaderHeight: 16

    function topCpuProcesses() {
        if (!service || !service.data || !service.data.top_processes) return []
        return service.data.top_processes.slice(0, 8)
    }

    function resetScroll() {
        contentFlickable.contentY = 0
    }

    function pageScroll(direction) {
        const maxY = Math.max(0, contentFlickable.contentHeight - contentFlickable.height)
        if (maxY <= 0) return
        const page = Math.max(80, contentFlickable.height * 0.85)
        contentFlickable.contentY = Math.max(0, Math.min(maxY, contentFlickable.contentY + direction * page))
    }

    function lineScroll(direction) {
        const maxY = Math.max(0, contentFlickable.contentHeight - contentFlickable.height)
        if (maxY <= 0) return
        const step = 28
        contentFlickable.contentY = Math.max(0, Math.min(maxY, contentFlickable.contentY + direction * step))
    }

    Flickable {
        id: contentFlickable
        anchors.fill: parent
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: true
        contentWidth: width
        property int _cpuTick: service ? service.cpuHistory.length : 0
        property var _dataBind: service ? service.data : ({})
        contentHeight: cpuColumn.implicitHeight

        WheelHandler {
            onWheel: function(event) {
                const delta = event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x
                if (delta === 0) return
                const maxY = Math.max(0, contentFlickable.contentHeight - contentFlickable.height)
                if (maxY <= 0) return
                const step = 42
                const ticks = delta / 120
                contentFlickable.contentY = Math.max(0, Math.min(maxY, contentFlickable.contentY - ticks * step))
                event.accepted = true
            }
        }

        ScrollBar.vertical: ScrollBar {
            id: cpuScrollBar
            policy: contentFlickable.contentHeight > contentFlickable.height + 1
                ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
            contentItem: Rectangle {
                implicitWidth: 6
                radius: 3
                color: cpuScrollBar.pressed ? root.accentColor : Qt.rgba(1, 1, 1, 0.2)
            }
        }

        ColumnLayout {
            id: cpuColumn
            width: parent.width
            spacing: 8

            // CPU Summary
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 78
                radius: root.cardRadius
                color: root.surfaceColor
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.08)

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: root.cardMargin
                    spacing: 4

                    Text {
                        text: "CPU SUMMARY"
                        color: root.accentColor
                        font.pixelSize: 11
                        font.bold: true
                        font.family: "monospace"
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        ColumnLayout {
                            spacing: 1
                            Text {
                                text: "Vendor: " + (service.data.cpu_info && service.data.cpu_info.vendor ? service.data.cpu_info.vendor : "--")
                                color: root.subtextColor
                                font.pixelSize: 10
                                font.family: "monospace"
                            }
                            Text {
                                text: "Model: " + (service.data.cpu_info && service.data.cpu_info.model ? service.data.cpu_info.model : "--")
                                color: root.subtextColor
                                font.pixelSize: 10
                                font.family: "monospace"
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            Text {
                                text: "Arch: " + (service.data.cpu_info && service.data.cpu_info.arch ? service.data.cpu_info.arch : "--")
                                    + "  ·  Cores: " + (service.data.cpu_info && service.data.cpu_info.cores ? service.data.cpu_info.cores : "--")
                                color: root.subtextColor
                                font.pixelSize: 10
                                font.family: "monospace"
                            }
                        }

                        Item { Layout.fillWidth: true }

                        Text {
                            text: (service.data.cpu ? (service.data.cpu.util || 0).toFixed(0) : "0") + "%"
                            color: root.textColor
                            font.pixelSize: 24
                            font.bold: true
                            font.family: "monospace"
                        }
                    }
                }
            }

            // Gauge + Top CPU Processes
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 168
                spacing: 8

                Rectangle {
                    Layout.preferredWidth: 170
                    Layout.fillHeight: true
                    radius: root.cardRadius
                    color: root.surfaceColor
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.08)

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: root.cardMargin
                        spacing: 2

                        Text {
                            text: "CPU USAGE"
                            color: root.accentColor
                            font.pixelSize: 10
                            font.bold: true
                            font.family: "monospace"
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            property int gaugeSz: Math.max(72, Math.min(112, height * 0.88))

                            CircularGauge {
                                anchors.centerIn: parent
                                size: parent.gaugeSz
                                strokeWidth: Math.max(6, parent.gaugeSz / 10)
                                value: service.data.cpu ? service.data.cpu.util : 0
                                subValue: service.data.cpu ? (service.data.cpu.temp || 0).toFixed(0) + "°C" : ""
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: root.cardRadius
                    color: root.surfaceColor
                    border.width: 1
                    border.color: Qt.rgba(1, 1, 1, 0.08)
                    clip: true

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: root.cardMargin
                        spacing: 4

                        Text {
                            text: "Top CPU Processes"
                            color: root.accentColor
                            font.pixelSize: 10
                            font.bold: true
                            font.family: "monospace"
                        }

                        // Compact table: Column (not ColumnLayout) avoids extra row spacing from layouts.
                        Column {
                            Layout.fillWidth: true
                            spacing: 0

                            Rectangle {
                                width: parent.width
                                height: root.processHeaderHeight
                                radius: 3
                                color: Qt.rgba(0.55, 0.70, 0.96, 0.12)

                                Row {
                                    anchors.fill: parent
                                    anchors.leftMargin: 4
                                    anchors.rightMargin: 4
                                    spacing: 6

                                    Text {
                                        width: 40
                                        height: parent.height
                                        text: "PID"
                                        color: root.textColor
                                        font.pixelSize: 9
                                        font.bold: true
                                        font.family: "monospace"
                                        verticalAlignment: Text.AlignVCenter
                                        horizontalAlignment: Text.AlignRight
                                    }
                                    Text {
                                        width: parent.width - 40 - 44 - 44 - 18
                                        height: parent.height
                                        text: "App"
                                        color: root.textColor
                                        font.pixelSize: 9
                                        font.bold: true
                                        font.family: "monospace"
                                        verticalAlignment: Text.AlignVCenter
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        width: 44
                                        height: parent.height
                                        text: "CPU%"
                                        color: root.textColor
                                        font.pixelSize: 9
                                        font.bold: true
                                        font.family: "monospace"
                                        verticalAlignment: Text.AlignVCenter
                                        horizontalAlignment: Text.AlignRight
                                    }
                                    Text {
                                        width: 44
                                        height: parent.height
                                        text: "RAM%"
                                        color: root.textColor
                                        font.pixelSize: 9
                                        font.bold: true
                                        font.family: "monospace"
                                        verticalAlignment: Text.AlignVCenter
                                        horizontalAlignment: Text.AlignRight
                                    }
                                }
                            }

                            Repeater {
                                model: root.topCpuProcesses()
                                delegate: Item {
                                    width: parent.width
                                    height: root.processRowHeight

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 2
                                        color: index % 2 === 0 ? "transparent" : Qt.rgba(1, 1, 1, 0.02)
                                    }

                                    Row {
                                        anchors.fill: parent
                                        anchors.leftMargin: 4
                                        anchors.rightMargin: 4
                                        spacing: 6

                                        Text {
                                            width: 40
                                            height: parent.height
                                            text: modelData.pid
                                            color: root.textColor
                                            font.pixelSize: 9
                                            font.family: "monospace"
                                            verticalAlignment: Text.AlignVCenter
                                            horizontalAlignment: Text.AlignRight
                                        }
                                        Text {
                                            width: parent.width - 40 - 44 - 44
                                            height: parent.height
                                            text: modelData.name
                                            color: root.subtextColor
                                            font.pixelSize: 9
                                            font.family: "monospace"
                                            verticalAlignment: Text.AlignVCenter
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            width: 44
                                            height: parent.height
                                            text: (modelData.cpu || 0).toFixed(1) + "%"
                                            color: root.accentColor
                                            font.pixelSize: 9
                                            font.family: "monospace"
                                            verticalAlignment: Text.AlignVCenter
                                            horizontalAlignment: Text.AlignRight
                                        }
                                        Text {
                                            width: 44
                                            height: parent.height
                                            text: (modelData.mem || 0).toFixed(1) + "%"
                                            color: root.textColor
                                            font.pixelSize: 9
                                            font.family: "monospace"
                                            verticalAlignment: Text.AlignVCenter
                                            horizontalAlignment: Text.AlignRight
                                        }
                                    }
                                }
                            }
                        }

                        Item { Layout.fillHeight: true }
                    }
                }
            }

            // CPU Usage History
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 132
                radius: root.cardRadius
                color: root.surfaceColor
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.08)

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: root.cardMargin
                    spacing: 4

                    Text {
                        text: "CPU Usage History"
                        color: root.accentColor
                        font.pixelSize: 10
                        font.bold: true
                        font.family: "monospace"
                    }

                    Sparkline {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        history: service.cpuHistory
                        fixedRange: true
                        minValue: 0
                        maxValue: 100
                        drawGrid: true
                        gridStep: 10
                        chartTitle: ""
                        titleColor: root.textColor
                        lineColor: root.accentColor
                        fillColor: Qt.rgba(0.55, 0.70, 0.96, 0.22)
                        leftPadding: 30
                        lineWidth: 1.2
                    }
                }
            }
        }
    }
}