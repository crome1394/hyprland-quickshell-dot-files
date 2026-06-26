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
    readonly property int processRowHeight: 14
    readonly property int processHeaderHeight: 16

    readonly property var gpuProcessRows: {
        const tick = service && service.data ? service.data.timestamp : 0
        if (!service || !service.data || !service.data.top_gpu) return []
        return service.data.top_gpu.slice(0, 8)
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
        property int _gpuTick: service ? service.gpuHistory.length : 0
        property var _dataBind: service ? service.data : ({})
        contentHeight: gpuColumn.implicitHeight

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
            id: gpuScrollBar
            policy: contentFlickable.contentHeight > contentFlickable.height + 1
                ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
            contentItem: Rectangle {
                implicitWidth: 6
                radius: 3
                color: gpuScrollBar.pressed ? root.accentColor : Qt.rgba(1, 1, 1, 0.2)
            }
        }

        ColumnLayout {
            id: gpuColumn
            width: parent.width
            spacing: 8

            // GPU Summary
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
                        text: "GPU SUMMARY"
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
                                text: "Model: " + (service.data.gpu_info && service.data.gpu_info.name ? service.data.gpu_info.name : "--")
                                color: root.subtextColor
                                font.pixelSize: 10
                                font.family: "monospace"
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            Text {
                                text: "VRAM: " + (service.data.gpu && service.data.gpu.vram_total
                                    ? ((service.data.gpu.vram_total || 0) / 1024).toFixed(0) + " GB"
                                    : "--")
                                color: root.subtextColor
                                font.pixelSize: 10
                                font.family: "monospace"
                            }
                            Text {
                                text: "Driver: " + (service.data.gpu_info && service.data.gpu_info.driver ? service.data.gpu_info.driver : "--")
                                color: root.subtextColor
                                font.pixelSize: 10
                                font.family: "monospace"
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                        }

                        Item { Layout.fillWidth: true }

                        Text {
                            text: (service.data.gpu ? (service.data.gpu.util || 0).toFixed(0) : "0") + "%"
                            color: root.textColor
                            font.pixelSize: 24
                            font.bold: true
                            font.family: "monospace"
                        }
                    }
                }
            }

            // Gauge + Top GPU Processes
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
                            text: "GPU USAGE"
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
                            font.pixelSize: 10
                            font.bold: true
                            font.family: "monospace"
                        }

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
                                        width: parent.width - 40 - 56 - 12
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
                                        width: 56
                                        height: parent.height
                                        text: "VRAM"
                                        color: root.textColor
                                        font.pixelSize: 9
                                        font.bold: true
                                        font.family: "monospace"
                                        verticalAlignment: Text.AlignVCenter
                                        horizontalAlignment: Text.AlignRight
                                    }
                                }
                            }

                            Text {
                                width: parent.width
                                visible: root.gpuProcessRows.length === 0
                                text: "No GPU compute processes reported"
                                color: root.overlayColor
                                font.pixelSize: 9
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
                                        spacing: 6

                                        Text {
                                            width: 40
                                            height: parent.height
                                            text: String(modelData.pid)
                                            color: root.textColor
                                            font.pixelSize: 9
                                            font.family: "monospace"
                                            verticalAlignment: Text.AlignVCenter
                                            horizontalAlignment: Text.AlignRight
                                        }
                                        Text {
                                            width: parent.width - 40 - 56
                                            height: parent.height
                                            text: modelData.name
                                            color: root.subtextColor
                                            font.pixelSize: 9
                                            font.family: "monospace"
                                            verticalAlignment: Text.AlignVCenter
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            width: 56
                                            height: parent.height
                                            text: (modelData.vram || 0) + " MiB"
                                            color: root.accentColor
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

            // GPU Usage History
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
                        text: "GPU Usage History"
                        color: root.accentColor
                        font.pixelSize: 10
                        font.bold: true
                        font.family: "monospace"
                    }

                    Sparkline {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
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
}