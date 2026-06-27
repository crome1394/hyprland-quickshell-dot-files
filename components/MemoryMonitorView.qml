import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// Live memory monitoring tab content (SysMonService + gauge + sparkline).
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
    property color sparklineColor: "#7aa2f7"

    readonly property int cardRadius: 6
    readonly property int cardMargin: 10
    readonly property int sectionSpacing: 8

    function formatGiB(mib) {
        if (mib === undefined || mib === null) return "--"
        return (Number(mib) / 1024).toFixed(1) + " GiB"
    }

    function barColor(pct) {
        const v = Number(pct) || 0
        if (v > 85) return root.gaugeHighColor
        if (v > 65) return root.gaugeMidColor
        return root.gaugeLowColor
    }

    readonly property int summaryHeight: Math.max(100, Math.min(130, Math.round(height * 0.16)))
    readonly property int middleHeight: Math.max(124, Math.min(260, Math.round(height * 0.34)))

    readonly property var memProcessRows: {
        const tick = service && service.data ? service.data.timestamp : 0
        if (!service || !service.data || !service.data.top_memory) return []
        return service.data.top_memory
    }

    function resetScroll() {}

    function pageScroll(direction) {}

    function lineScroll(direction) {}

    ColumnLayout {
        anchors.fill: parent
        spacing: root.sectionSpacing

        property int _ramTick: service ? service.ramHistory.length : 0
        property var _dataBind: service ? service.data : ({})

        // Memory Summary
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: root.summaryHeight
            Layout.minimumHeight: 96
            radius: root.cardRadius
            color: root.surfaceColor
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.08)

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: root.cardMargin
                spacing: 4

                Text {
                    text: "MEMORY SUMMARY"
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
                            text: "Total: " + (service.data.memory ? root.formatGiB(service.data.memory.ram_total) : "--")
                            color: root.subtextColor
                            font.pixelSize: 11
                            font.family: "monospace"
                        }
                        Text {
                            text: "Used: " + (service.data.memory ? root.formatGiB(service.data.memory.ram_used) : "--")
                            color: root.subtextColor
                            font.pixelSize: 11
                            font.family: "monospace"
                        }
                        Text {
                            text: "Free: " + (service.data.memory ? root.formatGiB(service.data.memory.ram_free) : "--")
                            color: root.subtextColor
                            font.pixelSize: 11
                            font.family: "monospace"
                        }
                        Text {
                            text: "Available: " + (service.data.memory ? root.formatGiB(service.data.memory.ram_available) : "--")
                            color: root.subtextColor
                            font.pixelSize: 11
                            font.family: "monospace"
                        }
                    }

                    Item { Layout.fillWidth: true }

                    Text {
                        text: (service.data.memory ? Number(service.data.memory.ram_pct || 0).toFixed(0) : "0") + "%"
                        color: root.textColor
                        font.pixelSize: 25
                        font.bold: true
                        font.family: "monospace"
                    }
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 6
                    radius: 3
                    color: Qt.rgba(0, 0, 0, 0.25)

                    Rectangle {
                        width: parent.width * Math.min(1, (service.data.memory ? Number(service.data.memory.ram_pct || 0) : 0) / 100)
                        height: parent.height
                        radius: 3
                        color: root.barColor(service.data.memory ? service.data.memory.ram_pct : 0)
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        text: "SWAP"
                        color: root.subtextColor
                        font.pixelSize: 10
                        font.bold: true
                        font.family: "monospace"
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 5
                        radius: 3
                        color: Qt.rgba(0, 0, 0, 0.25)

                        Rectangle {
                            width: parent.width * Math.min(1, (service.data.memory ? Number(service.data.memory.swap_pct || 0) : 0) / 100)
                            height: parent.height
                            radius: 3
                            color: root.barColor(service.data.memory ? service.data.memory.swap_pct : 0)
                        }
                    }

                    Text {
                        text: (service.data.memory ? Number(service.data.memory.swap_pct || 0).toFixed(0) : "0") + "%"
                        color: root.textColor
                        font.pixelSize: 11
                        font.bold: true
                        font.family: "monospace"
                    }

                    Text {
                        text: service.data.memory
                            ? root.formatGiB(service.data.memory.swap_used) + " / " + root.formatGiB(service.data.memory.swap_total)
                            : "--"
                        color: root.overlayColor
                        font.pixelSize: 10
                        font.family: "monospace"
                    }
                }
            }
        }

        // Gauge + Top Memory Processes
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
                        text: "MEMORY USAGE"
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
                            value: service.data.memory ? Number(service.data.memory.ram_pct || 0) : 0
                            subValue: service.data.memory
                                ? (Number(service.data.memory.ram_used) / 1024).toFixed(1) + "/" + (Number(service.data.memory.ram_total) / 1024).toFixed(1) + " GiB"
                                : ""
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

                TopProcessPanel {
                    anchors.fill: parent
                    anchors.margins: root.cardMargin
                    title: "Top Memory Processes"
                    mode: "mem"
                    rows: root.memProcessRows
                    textColor: root.textColor
                    subtextColor: root.subtextColor
                    accentColor: root.accentColor
                    surfaceColor: root.surfaceColor
                    overlayColor: root.overlayColor
                }
            }
        }

        // Memory Usage History — fills remaining vertical space
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
                    text: "Memory Usage History"
                    color: root.accentColor
                    font.pixelSize: 11
                    font.bold: true
                    font.family: "monospace"
                }

                Sparkline {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 48
                    history: service.ramHistory
                    fixedRange: true
                    minValue: 0
                    maxValue: 100
                    drawGrid: true
                    gridStep: 10
                    chartTitle: ""
                    titleColor: root.textColor
                    lineColor: root.sparklineColor
                    fillColor: Qt.rgba(0.48, 0.64, 0.97, 0.28)
                    leftPadding: 30
                    lineWidth: 1.2
                }
            }
        }
    }
}