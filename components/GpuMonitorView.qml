import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Live GPU monitoring tab content (SysMonService + gauge + sparkline).
Item {
    id: root

    required property var service

    property color textColor: "#cdd6f4"
    property color subtextColor: "#a6adc8"
    property color accentColor: "#89b4fa"
    property color surfaceColor: "#313244"
    property color overlayColor: "#6c7086"
    property color gaugeLowColor: "#a6e3a1"
    property color gaugeMidColor: "#f9e2af"
    property color gaugeHighColor: "#f38ba8"

    readonly property int cardRadius: 6
    readonly property int cardMargin: 10
    readonly property int processRowHeight: 15
    readonly property int processHeaderHeight: 17
    readonly property int sectionSpacing: 8
    readonly property int tblSpacing: 4
    readonly property int colPidW: 34
    readonly property int colTypeW: 36
    readonly property int colVramW: 52

    function gpuTableFixedWidth() {
        return colPidW + colTypeW + colVramW + tblSpacing * 3
    }

    function gpuAppColWidth(totalWidth) {
        return Math.max(64, totalWidth - gpuTableFixedWidth())
    }

    function formatGpuType(type) {
        if (!type || type.length === 0) return "--"
        return type
    }

    readonly property int summaryHeight: Math.max(68, Math.min(94, Math.round(height * 0.12)))
    readonly property int middleHeight: Math.max(124, Math.min(260, Math.round(height * 0.34)))

    readonly property var gpuProcessRows: {
        const tick = service && service.data ? service.data.timestamp : 0
        if (!service || !service.data || !service.data.top_gpu) return []
        return service.data.top_gpu.slice(0, 8)
    }

    function resetScroll() {}

    function pageScroll(direction) {}

    function lineScroll(direction) {}

    ColumnLayout {
        anchors.fill: parent
        spacing: root.sectionSpacing

        property int _gpuTick: service ? service.gpuHistory.length : 0
        property var _dataBind: service ? service.data : ({})

        // GPU Summary
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
                    text: "GPU SUMMARY"
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
                            text: "Model: " + (service.data.gpu_info && service.data.gpu_info.name ? service.data.gpu_info.name : "--")
                            color: root.subtextColor
                            font.pixelSize: 11
                            font.family: "monospace"
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                        Text {
                            text: "VRAM: " + (service.data.gpu && service.data.gpu.vram_total
                                ? ((service.data.gpu.vram_total || 0) / 1024).toFixed(0) + " GB"
                                : "--")
                            color: root.subtextColor
                            font.pixelSize: 11
                            font.family: "monospace"
                        }
                        Text {
                            text: "Driver: " + (service.data.gpu_info && service.data.gpu_info.driver ? service.data.gpu_info.driver : "--")
                            color: root.subtextColor
                            font.pixelSize: 11
                            font.family: "monospace"
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: (service.data.gpu ? (service.data.gpu.util || 0).toFixed(0) : "0") + "%"
                        color: root.textColor
                        font.pixelSize: 25
                        font.bold: true
                        font.family: "monospace"
                    }
                }
            }
        }

        // Gauge + Top GPU Processes
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
                        text: "GPU USAGE"
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
                            value: service.data.gpu ? service.data.gpu.util : 0
                            subValue: service.data.gpu ? (service.data.gpu.temp || 0).toFixed(0) + "°C" : ""
                            lowColor: root.gaugeLowColor
                            midColor: root.gaugeMidColor
                            highColor: root.gaugeHighColor
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
                        text: "Top GPU Processes"
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
                        contentHeight: gpuProcessTable.implicitHeight

                        Column {
                            id: gpuProcessTable
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
                                    Text { width: root.gpuAppColWidth(parent.width - 8); height: parent.height; text: "App"; color: root.textColor; font.pixelSize: 10; font.bold: true; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                                    Text { width: root.colTypeW; height: parent.height; text: "Type"; color: root.textColor; font.pixelSize: 10; font.bold: true; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter }
                                    Text { width: root.colVramW; height: parent.height; text: "VRAM"; color: root.textColor; font.pixelSize: 10; font.bold: true; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                                }
                            }

                            Text {
                                width: parent.width
                                visible: root.gpuProcessRows.length === 0
                                text: "No GPU compute processes reported"
                                color: root.overlayColor
                                font.pixelSize: 10
                                font.family: "monospace"
                                topPadding: 4
                            }

                            Repeater {
                                model: root.gpuProcessRows
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

                                        Text { width: root.colPidW; height: parent.height; text: String(modelData.pid); color: root.textColor; font.pixelSize: 10; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                                        Text { width: root.gpuAppColWidth(parent.width - 8); height: parent.height; text: modelData.name; color: root.subtextColor; font.pixelSize: 10; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                                        Text { width: root.colTypeW; height: parent.height; text: root.formatGpuType(modelData.type); color: root.overlayColor; font.pixelSize: 10; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignHCenter }
                                        Text { width: root.colVramW; height: parent.height; text: (modelData.vram || 0) + " MiB"; color: root.accentColor; font.pixelSize: 10; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // GPU Usage History — fills remaining vertical space
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
                    text: "GPU Usage History"
                    color: root.accentColor
                    font.pixelSize: 11
                    font.bold: true
                    font.family: "monospace"
                }

                Sparkline {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 48
                    history: service.gpuHistory
                    fixedRange: true
                    minValue: 0
                    maxValue: 100
                    drawGrid: true
                    gridStep: 10
                    chartTitle: ""
                    titleColor: root.textColor
                    lineColor: root.gaugeLowColor
                    fillColor: Qt.rgba(0.65, 0.89, 0.63, 0.22)
                    leftPadding: 30
                    lineWidth: 1.2
                }
            }
        }
    }
}