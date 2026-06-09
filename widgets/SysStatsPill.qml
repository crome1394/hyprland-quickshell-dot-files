import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io as Io

// =============================================================================
// SysStatsPill.qml — System resource gauges (CPU, GPU, RAM, Swap)
// =============================================================================
//
// Purpose:
//   Overlay gauges showing CPU + GPU utilization and temperatures.
//   Left-click CPU launches btop; left-click GPU launches nvtop.
//   Automatically hides when media is playing.
//
// Theme Properties Consumed:
//   - bar.glassPillBg, bar.glassHover, bar.glassBorder, bar.glassHighlight
//   - bar.pillRadius, bar.controlBorderWidth, bar.accent, bar.subtext, bar.text
//   - bar.statGaugeWidth, bar.statGaugeHeight, bar.statGaugeRadius, bar.statTrack
//   - bar.statUtilTier1–4, bar.statUtilThreshold1–3, bar.statUtilColor()
//   - bar.statTempCool, bar.statTempWarm, bar.statTempHot, bar.statTempWarmAt,
//     bar.statTempHotAt, bar.statTempColor(), bar.statValueSeparator
//   - bar.divider, bar.fontFamily, bar.tooltipDelay
//
// Dependencies:
//   - required property var bar (from shell.qml)
//   - property bool mediaActive (from parent)
//
// Notes:
//   - Polling via external script + timer logic is preserved exactly.
//   - CPU/GPU sections remain structurally identical for consistency.
// =============================================================================

Rectangle {
    id: root

    required property var bar
    property bool mediaActive: false

    Layout.preferredWidth: 430
    Layout.preferredHeight: bar.pillHeight
    Layout.alignment: Qt.AlignVCenter
    visible: !mediaActive && sysStatsReady
    implicitWidth: 430
    implicitHeight: bar.pillHeight
    radius: bar.pillRadius
    color: sysHover.containsMouse ? bar.glassHover : bar.glassPillBg
    border.width: bar.controlBorderWidth
    border.color: sysHover.containsMouse ? bar.accent : bar.glassBorder

    // ===== Stats State & Polling =====
    property real cpuUtil: 0
    property int  cpuTemp: 0
    property real gpuUtil: 0
    property int  gpuTemp: 0
    property bool sysStatsReady: false

    function updateSysStats(d) {
        if (d.cpu) {
            cpuUtil = Number(d.cpu.util) || 0
            cpuTemp = Math.round(Number(d.cpu.temp) || 0)
        }
        if (d.gpu) {
            gpuUtil = Number(d.gpu.util) || 0
            gpuTemp = Math.round(Number(d.gpu.temp) || 0)
        }
        sysStatsReady = true
    }

    Io.Process {
        id: statsPoller
        command: ["/home/crome/.config/quickshell/scripts/bar-stats.sh"]
        stdout: Io.SplitParser {
            splitMarker: "\n"
            onRead: (line) => {
                const trimmed = line.trim()
                if (!trimmed.startsWith("{") || !trimmed.endsWith("}")) return
                try {
                    const d = JSON.parse(trimmed)
                    root.updateSysStats(d)
                } catch (e) {}
            }
        }
        onExited: (code) => {
            // ready for next timer kick
        }
    }

    Timer {
        id: statsTimer
        interval: 1600
        running: true
        repeat: true
        onTriggered: {
            if (!statsPoller.running) statsPoller.running = true
        }
    }

    Component.onCompleted: {
        Qt.callLater(function() {
            if (!statsPoller.running) statsPoller.running = true
        })
    }

    // === Appearance via Theme ===
    // Subtle top glass highlight
    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: bar.glassHighlight
        radius: parent.radius
    }

    MouseArea {
        id: sysHover
        anchors.fill: parent
        hoverEnabled: true
        // Whole pill hover only; clicks are handled by the two child areas below
    }

    Row {
        anchors.centerIn: parent
        spacing: 17

        // ----- CPU HALF -----
        Item {
            width: 195
            height: 26

            MouseArea {
                id: cpuClick
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Quickshell.execDetached(["kitty", "-e", "btop"])
                ToolTip.text: "Click to launch btop"
                ToolTip.visible: cpuClick.containsMouse
                ToolTip.delay: bar.tooltipDelay
            }

            Row {
                anchors.centerIn: parent
                spacing: 7

                Text {
                    text: "CPU"
                    font.pixelSize: 13
                    font.bold: true
                    font.family: bar.fontFamily
                    color: cpuClick.containsMouse ? bar.accent : bar.subtext
                    anchors.verticalCenter: parent.verticalCenter
                }

                // Visual utilization bar (compact, animated)
                Item {
                    width: bar.statGaugeWidth
                    height: bar.statGaugeHeight
                    anchors.verticalCenter: parent.verticalCenter

                    Rectangle {
                        anchors.fill: parent
                        radius: bar.statGaugeRadius
                        color: bar.statTrack
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(2, Math.min(parent.width, parent.width * (root.cpuUtil / 100)))
                        height: bar.statGaugeHeight
                        radius: bar.statGaugeRadius
                        color: bar.statUtilColor(root.cpuUtil)

                        Behavior on width {
                            NumberAnimation { duration: 110; easing.type: Easing.OutQuad }
                        }
                    }
                }

                // Util % | temp (each segment color-coded independently)
                Row {
                    spacing: 4
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        text: Math.round(root.cpuUtil) + "%"
                        font.pixelSize: 13
                        font.bold: true
                        font.family: bar.fontFamily
                        color: bar.statUtilColor(root.cpuUtil)
                    }
                    Text {
                        text: "|"
                        font.pixelSize: 13
                        font.family: bar.fontFamily
                        color: bar.statValueSeparator
                    }
                    Text {
                        text: root.cpuTemp + "°"
                        font.pixelSize: 13
                        font.bold: true
                        font.family: bar.fontFamily
                        color: bar.statTempColor(root.cpuTemp)
                    }
                }
            }
        }

        // Thin vertical divider between CPU and GPU sections
        Rectangle {
            width: 1
            height: 17
            color: bar.divider
            anchors.verticalCenter: parent.verticalCenter
        }

        // ----- GPU HALF -----
        Item {
            width: 195
            height: 26

            MouseArea {
                id: gpuClick
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Quickshell.execDetached(["kitty", "-e", "nvtop"])
                ToolTip.text: "Click to launch nvtop"
                ToolTip.visible: gpuClick.containsMouse
                ToolTip.delay: bar.tooltipDelay
            }

            Row {
                anchors.centerIn: parent
                spacing: 7

                Text {
                    text: "GPU"
                    font.pixelSize: 13
                    font.bold: true
                    font.family: bar.fontFamily
                    color: gpuClick.containsMouse ? bar.accent : bar.subtext
                    anchors.verticalCenter: parent.verticalCenter
                }

                // Visual utilization bar (compact, animated)
                Item {
                    width: bar.statGaugeWidth
                    height: bar.statGaugeHeight
                    anchors.verticalCenter: parent.verticalCenter

                    Rectangle {
                        anchors.fill: parent
                        radius: bar.statGaugeRadius
                        color: bar.statTrack
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(2, Math.min(parent.width, parent.width * (root.gpuUtil / 100)))
                        height: bar.statGaugeHeight
                        radius: bar.statGaugeRadius
                        color: bar.statUtilColor(root.gpuUtil)

                        Behavior on width {
                            NumberAnimation { duration: 110; easing.type: Easing.OutQuad }
                        }
                    }
                }

                // Util % | temp (each segment color-coded independently)
                Row {
                    spacing: 4
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        text: Math.round(root.gpuUtil) + "%"
                        font.pixelSize: 13
                        font.bold: true
                        font.family: bar.fontFamily
                        color: bar.statUtilColor(root.gpuUtil)
                    }
                    Text {
                        text: "|"
                        font.pixelSize: 13
                        font.family: bar.fontFamily
                        color: bar.statValueSeparator
                    }
                    Text {
                        text: root.gpuTemp + "°"
                        font.pixelSize: 13
                        font.bold: true
                        font.family: bar.fontFamily
                        color: bar.statTempColor(root.gpuTemp)
                    }
                }
            }
        }
    }
}
