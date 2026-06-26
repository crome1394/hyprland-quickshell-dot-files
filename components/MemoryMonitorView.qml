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
    readonly property int processRowHeight: 15
    readonly property int processHeaderHeight: 17
    readonly property int sectionSpacing: 8
    readonly property int tblSpacing: 4
    readonly property int colPidW: 34
    readonly property int colUserW: 44
    readonly property int colRamPctW: 34
    readonly property int colMemW: 38
    readonly property int colThreadsW: 30

    function memTableFixedWidth() {
        return colPidW + colUserW + colRamPctW + colMemW + colThreadsW + tblSpacing * 5
    }

    function memAppColWidth(totalWidth) {
        return Math.max(56, totalWidth - memTableFixedWidth())
    }

    function formatGiB(mib) {
        if (mib === undefined || mib === null) return "--"
        return (Number(mib) / 1024).toFixed(1) + " GiB"
    }

    function formatRssMiB(rss) {
        if (!rss) return "--"
        return Math.round(Number(rss) / 1024) + "M"
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
        return service.data.top_memory.slice(0, 8)
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

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: root.cardMargin
                    spacing: 4

                    Text {
                        text: "Top Memory Processes"
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
                        contentHeight: memProcessTable.implicitHeight

                        Column {
                            id: memProcessTable
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
                                    Text { width: root.memAppColWidth(parent.width - 8); height: parent.height; text: "App"; color: root.textColor; font.pixelSize: 10; font.bold: true; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                                    Text { width: root.colUserW; height: parent.height; text: "User"; color: root.textColor; font.pixelSize: 10; font.bold: true; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignLeft }
                                    Text { width: root.colRamPctW; height: parent.height; text: "RAM%"; color: root.textColor; font.pixelSize: 10; font.bold: true; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                                    Text { width: root.colMemW; height: parent.height; text: "Mem"; color: root.textColor; font.pixelSize: 10; font.bold: true; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                                    Text { width: root.colThreadsW; height: parent.height; text: "Thr"; color: root.textColor; font.pixelSize: 10; font.bold: true; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
                                }
                            }

                            Repeater {
                                model: root.memProcessRows
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
                                        Text { width: root.memAppColWidth(parent.width - 8); height: parent.height; text: modelData.name; color: root.subtextColor; font.pixelSize: 10; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                                        Text { width: root.colUserW; height: parent.height; text: modelData.user || "--"; color: root.overlayColor; font.pixelSize: 10; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; elide: Text.ElideRight }
                                        Text { width: root.colRamPctW; height: parent.height; text: Number(modelData.mem || 0).toFixed(1) + "%"; color: root.accentColor; font.pixelSize: 10; font.family: "monospace"; verticalAlignment: Text.AlignVCenter; horizontalAlignment: Text.AlignRight }
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