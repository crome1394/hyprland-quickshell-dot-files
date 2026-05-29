import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io as Io

// =============================================================================
// SysStatsPill.qml — System resource gauges (CPU, GPU, RAM, Swap)
// =============================================================================
//
// Right-click opens btop (CPU) or nvtop (GPU) in a new terminal.
// Visibility is coupled to MediaPill.hasMedia — when media is playing the
// gauges hide to reduce center clutter.
// =============================================================================

Rectangle {
    id: root

    required property var bar
    required property Item barBg
    property bool mediaActive: false

    anchors.centerIn: barBg
    z: 5
    visible: !mediaActive && sysStatsReady
    width: 385
    implicitHeight: 40
    radius: bar.pillRadius
    color: sysHover.containsMouse ? bar.glassHover : bar.glassPillBg
    border.width: 1
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
        // Kick the poller immediately on startup
        Qt.callLater(function() {
            if (!statsPoller.running) statsPoller.running = true
        })
    }

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
            width: 162
            height: 26
            MouseArea {
                id: cpuClick
                anchors.fill: parent
                acceptedButtons: Qt.RightButton
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: (mouse) => {
                    if (mouse.button === Qt.RightButton) {
                        Quickshell.execDetached(["kitty", "-e", "btop"])
                    }
                }
                ToolTip.text: "Right-click to launch btop"
                ToolTip.visible: cpuClick.containsMouse
                ToolTip.delay: 650
            }

            Row {
                anchors.centerIn: parent
                spacing: 7

                Text {
                    text: "CPU"
                    font.pixelSize: 13
                    font.bold: true
                    font.family: "JetBrains Mono Nerd Font, monospace"
                    color: cpuClick.containsMouse ? bar.accent : bar.subtext
                    anchors.verticalCenter: parent.verticalCenter
                }

                // Visual utilization bar (compact, animated)
                Item {
                    width: 73
                    height: 8
                    anchors.verticalCenter: parent.verticalCenter
                    Rectangle {
                        anchors.fill: parent
                        radius: 4
                        color: Qt.rgba(1, 1, 1, 0.09)
                    }
                    Rectangle {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(2, Math.min(parent.width, parent.width * (root.cpuUtil / 100)))
                        height: 8
                        radius: 4
                        color: root.cpuUtil > 85 ? "#f38ba8" :
                               (root.cpuUtil > 65 ? "#f9e2af" : bar.accent)
                        Behavior on width {
                            NumberAnimation { duration: 110; easing.type: Easing.OutQuad }
                        }
                    }
                }

                // Temp (always shown, color coded)
                Text {
                    text: root.cpuTemp + "°"
                    font.pixelSize: 13
                    font.bold: true
                    color: root.cpuTemp > 85 ? "#f38ba8" :
                           (root.cpuTemp > 70 ? "#f9e2af" : bar.text)
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        // Thin vertical divider between CPU and GPU sections
        Rectangle {
            width: 1
            height: 17
            color: Qt.rgba(1, 1, 1, 0.13)
            anchors.verticalCenter: parent.verticalCenter
        }

        // ----- GPU HALF -----
        Item {
            width: 162
            height: 26
            MouseArea {
                id: gpuClick
                anchors.fill: parent
                acceptedButtons: Qt.RightButton
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: (mouse) => {
                    if (mouse.button === Qt.RightButton) {
                        Quickshell.execDetached(["kitty", "-e", "nvtop"])
                    }
                }
                ToolTip.text: "Right-click to launch nvtop"
                ToolTip.visible: gpuClick.containsMouse
                ToolTip.delay: 650
            }

            Row {
                anchors.centerIn: parent
                spacing: 7

                Text {
                    text: "GPU"
                    font.pixelSize: 13
                    font.bold: true
                    font.family: "JetBrains Mono Nerd Font, monospace"
                    color: gpuClick.containsMouse ? bar.accent : bar.subtext
                    anchors.verticalCenter: parent.verticalCenter
                }

                // Visual utilization bar (compact, animated)
                Item {
                    width: 73
                    height: 8
                    anchors.verticalCenter: parent.verticalCenter
                    Rectangle {
                        anchors.fill: parent
                        radius: 4
                        color: Qt.rgba(1, 1, 1, 0.09)
                    }
                    Rectangle {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(2, Math.min(parent.width, parent.width * (root.gpuUtil / 100)))
                        height: 8
                        radius: 4
                        color: root.gpuUtil > 85 ? "#f38ba8" :
                               (root.gpuUtil > 65 ? "#f9e2af" : bar.accent)
                        Behavior on width {
                            NumberAnimation { duration: 110; easing.type: Easing.OutQuad }
                        }
                    }
                }

                // Temp (always shown, color coded)
                Text {
                    text: root.gpuTemp + "°"
                    font.pixelSize: 13
                    font.bold: true
                    color: root.gpuTemp > 85 ? "#f38ba8" :
                           (root.gpuTemp > 70 ? "#f9e2af" : bar.text)
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }
}
