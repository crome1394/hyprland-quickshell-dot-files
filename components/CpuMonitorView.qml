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
    readonly property int sectionSpacing: 8

    readonly property int summaryHeight: Math.max(68, Math.min(94, Math.round(height * 0.12)))
    readonly property int middleHeight: Math.max(124, Math.min(260, Math.round(height * 0.34)))

    readonly property var cpuProcessRows: {
        const tick = service && service.data ? service.data.timestamp : 0
        if (!service || !service.data || !service.data.top_processes) return []
        return service.data.top_processes
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

                TopProcessPanel {
                    anchors.fill: parent
                    anchors.margins: root.cardMargin
                    title: "Top CPU Processes"
                    mode: "cpu"
                    rows: root.cpuProcessRows
                    textColor: root.textColor
                    subtextColor: root.subtextColor
                    accentColor: root.accentColor
                    surfaceColor: root.surfaceColor
                    overlayColor: root.overlayColor
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