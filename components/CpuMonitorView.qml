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
    readonly property int processRowHeight: 15
    readonly property int processHeaderHeight: 17
    readonly property int sectionSpacing: 8
    readonly property int tblSpacing: 4
    readonly property int colPidW: 34
    readonly property int colUserW: 44
    readonly property int colCpuW: 34
    readonly property int colRamPctW: 34
    readonly property int colMemW: 38
    readonly property int colThreadsW: 30

    function cpuTableFixedWidth() {
        return colPidW + colUserW + colCpuW + colRamPctW + colMemW + colThreadsW + tblSpacing * 6
    }

    function cpuAppColWidth(totalWidth) {
        return Math.max(56, totalWidth - cpuTableFixedWidth())
    }

    function formatRssMiB(rss) {
        if (!rss) return "--"
        return Math.round(rss / 1024) + "M"
    }

    readonly property int summaryHeight: Math.max(68, Math.min(94, Math.round(height * 0.12)))
    readonly property int middleHeight: Math.max(124, Math.min(260, Math.round(height * 0.34)))

    readonly property var cpuProcessRows: {
        const tick = service && service.data ? service.data.timestamp : 0
        if (!service || !service.data || !service.data.top_processes) return []
        return service.data.top_processes.slice(0, 8)
    }

    function resetScroll() {}

    function pageScroll(direction) {}

    function lineScroll(direction) {}

    ColumnLayout {
        anchors.fill: parent
        spacing: root.sectionSpacing

        property int _cpuTick: service ? service.cpuHistory.length : 0
        property var _dataBind: service ? service.data : ({})

        // CPU Summary
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: root.summaryHeight
            Layout.minimumHeight: 64
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
                    font.pixelSize: 12
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
                            font.pixelSize: 11
                            font.family: "monospace"
                        }
                        Text {
                            text: "Model: " + (service.data.cpu_info && service.data.cpu_info.model ? service.data.cpu_info.model : "--")
                            color: root.subtextColor
                            font.pixelSize: 11
                            font.family: "monospace"
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Text {
                            text: "Arch: " + (service.data.cpu_info && service.data.cpu_info.arch ? service.data.cpu_info.arch : "--")
                                + "  ·  Cores: " + (service.data.cpu_info && service.data.cpu_info.cores ? service.data.cpu_info.cores : "--")
                            color: root.subtextColor
                            font.pixelSize: 11
                            font.family: "monospace"
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: (service.data.cpu ? (service.data.cpu.util || 0).toFixed(0) : "0") + "%"
                        color: root.textColor
                        font.pixelSize: 25
                        font.bold: true
                        font.family: "monospace"
                    }
                }
            }
        }

        // Gauge + Top CPU Processes
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: root.middleHeight
            Layout.minimumHeight: 116
            spacing: root.sectionSpacing

            Rectangle {
                Layout.preferredWidth: Math.max(150, Math.min(200, root.width * 0.22))
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
                        font.pixelSize: 11
                        font.bold: true
                        font.family: "monospace"
                    }

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        property int gaugeSz: Math.max(56, Math.min(140, Math.min(width, height) * 0.88))

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
                        font.pixelSize: 11
                        font.bold: true
                        font.family: "monospace"
                    }

                    Flickable {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        contentWidth: width
                        contentHeight: cpuProcessTable.implicitHeight

                        Column {
                            id: cpuProcessTable
                            width: parent.width
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
                                    spacing: root.tblSpacing

                                    Text { width: root.colPidW; height: parent.height; text: "PID"; color: root.textColor; font.pixelSize: 10; font.bold: true; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                                    Text { width: root.cpuAppColWidth(parent.width - 8); height: parent.height; text: "App"; color: root.textColor; font.pixelSize: 10; font.bold: true; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                                    Text { width: root.colUserW; height: parent.height; text: "User"; color: root.textColor; font.pixelSize: 10; font.bold: true; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignLeft }
                                    Text { width: root.colCpuW; height: parent.height; text: "CPU%"; color: root.textColor; font.pixelSize: 10; font.bold: true; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                                    Text { width: root.colRamPctW; height: parent.height; text: "RAM%"; color: root.textColor; font.pixelSize: 10; font.bold: true; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                                    Text { width: root.colMemW; height: parent.height; text: "Mem"; color: root.textColor; font.pixelSize: 10; font.bold: true; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                                    Text { width: root.colThreadsW; height: parent.height; text: "Thr"; color: root.textColor; font.pixelSize: 10; font.bold: true; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                                }
                            }

                            Repeater {
                                model: root.cpuProcessRows
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
                                        spacing: root.tblSpacing

                                        Text { width: root.colPidW; height: parent.height; text: modelData.pid; color: root.textColor; font.pixelSize: 10; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                                        Text { width: root.cpuAppColWidth(parent.width - 8); height: parent.height; text: modelData.name; color: root.subtextColor; font.pixelSize: 10; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                                        Text { width: root.colUserW; height: parent.height; text: modelData.user || "--"; color: root.overlayColor; font.pixelSize: 10; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                                        Text { width: root.colCpuW; height: parent.height; text: (modelData.cpu || 0).toFixed(1) + "%"; color: root.accentColor; font.pixelSize: 10; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                                        Text { width: root.colRamPctW; height: parent.height; text: (modelData.mem || 0).toFixed(1) + "%"; color: root.textColor; font.pixelSize: 10; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                                        Text { width: root.colMemW; height: parent.height; text: root.formatRssMiB(modelData.rss); color: root.textColor; font.pixelSize: 10; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                                        Text { width: root.colThreadsW; height: parent.height; text: modelData.threads !== undefined ? modelData.threads : "--"; color: root.textColor; font.pixelSize: 10; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // CPU Usage History — fills remaining vertical space
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 88
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
                    font.pixelSize: 11
                    font.bold: true
                    font.family: "monospace"
                }

                Sparkline {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 48
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