import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io as Io
import "../components"

// =============================================================================
// SysStatsPill.qml — System resource gauges (CPU, GPU)
// =============================================================================
//
// Purpose:
//   Overlay gauges showing CPU + GPU utilization and temperatures.
//   Left-click CPU launches btop; left-click GPU launches nvtop.
//   Right-click each half opens a metrics dropdown (CpuMonitorView / GpuMonitorView).
//   Automatically hides when media is playing.
//
// Theme Properties Consumed:
//   - bar.glassPillBg, bar.glassHover, bar.glassBorder, bar.glassHighlight
//   - bar.glassPopupBg, bar.glassPopupBorder, bar.glassPopupHighlight
//   - bar.pillRadius, bar.popupRadius, bar.controlBorderWidth, bar.accent, bar.subtext, bar.text
//   - bar.statGaugeWidth, bar.statGaugeHeight, bar.statGaugeRadius, bar.statTrack
//   - bar.statUtilTier1–4, bar.statUtilThreshold1–3, bar.statUtilColor()
//   - bar.statTempCool, bar.statTempWarm, bar.statTempHot, bar.statTempWarmAt,
//     bar.statTempHotAt, bar.statTempColor(), bar.statValueSeparator
//   - bar.divider, bar.fontFamily, bar.tooltipDelay, bar.popupAnchorY()
//   - bar.popupStatsCpu/Gpu Width/Height and per-half position tokens (AnchorX, AnchorWholePill, OffsetX/Y, BarGap)
//   - bar.popupStatsLiveUpdates, bar.popupStatsPersistPause
//   - bar.surface, bar.overlay, bar.gaugeLow/Mid/High (metrics popup views)
//
// Dependencies:
//   - required property var bar (from shell.qml)
//   - required property Item barBg (popup positioning)
//   - property bool mediaActive (from parent)
//   - SysMonService (local; polls only while a metrics popup is open and live updates on)
//
// Notes:
//   - Pill display still uses the lightweight bar-stats.sh poller (unchanged).
//   - Rich metrics popups reuse HyprConfigInsp tab views via sysmon-poller.sh.
// =============================================================================

Rectangle {
    id: root

    required property var bar
    required property Item barBg
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

    readonly property bool metricsPopupOpen: cpuMetricsPopup.visible || gpuMetricsPopup.visible
    property bool cpuLiveUpdates: true
    property bool gpuLiveUpdates: true

    // ===== Stats State & Polling (pill display — unchanged) =====
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
            if (!bar.popupStatsPersistPause) {
                cpuLiveUpdates = bar.popupStatsLiveUpdates
                gpuLiveUpdates = bar.popupStatsLiveUpdates
            }
        })
    }

    // ===== Rich metrics (right-click popups only) =====
    Io.FileView {
        id: statsPauseState
        path: bar.popupStatsPersistPause
              ? "/home/crome/.config/quickshell/state/popup-stats.json"
              : ""
        watchChanges: bar.popupStatsPersistPause
        onFileChanged: if (bar.popupStatsPersistPause) reload()
        onAdapterUpdated: if (bar.popupStatsPersistPause) writeAdapter()
        onLoaded: if (bar.popupStatsPersistPause) root.syncLiveUpdatesFromPersisted()
        onLoadFailed: if (bar.popupStatsPersistPause) root.seedPauseStateFromConfig()

        Io.JsonAdapter {
            id: pauseAdapter
            property bool cpuLiveUpdates: bar.popupStatsLiveUpdates
            property bool gpuLiveUpdates: bar.popupStatsLiveUpdates
        }
    }

    SysMonService {
        id: sysMonService
        autoPoll: false
    }

    function seedPauseStateFromConfig() {
        pauseAdapter.cpuLiveUpdates = bar.popupStatsLiveUpdates
        pauseAdapter.gpuLiveUpdates = bar.popupStatsLiveUpdates
        syncLiveUpdatesFromPersisted()
    }

    function syncLiveUpdatesFromPersisted() {
        cpuLiveUpdates = pauseAdapter.cpuLiveUpdates
        gpuLiveUpdates = pauseAdapter.gpuLiveUpdates
        syncMetricsPolling()
    }

    function setLiveUpdates(isCpu, enabled) {
        if (isCpu) {
            cpuLiveUpdates = enabled
            if (bar.popupStatsPersistPause)
                pauseAdapter.cpuLiveUpdates = enabled
        } else {
            gpuLiveUpdates = enabled
            if (bar.popupStatsPersistPause)
                pauseAdapter.gpuLiveUpdates = enabled
        }
    }

    function metricsPollingEnabled() {
        return (cpuMetricsPopup.visible && cpuLiveUpdates)
            || (gpuMetricsPopup.visible && gpuLiveUpdates)
    }

    function syncMetricsPolling() {
        const poll = metricsPollingEnabled()
        sysMonService.setAutoPoll(poll)
        if (!poll)
            sysMonService.stopPolling()
        else
            sysMonService.refresh()
    }

    // === Public API (shell IPC: qs ipc call sysStatsPill …) ===
    function setCpuLiveUpdates(enabled) {
        setLiveUpdates(true, enabled)
        syncMetricsPolling()
    }

    function setGpuLiveUpdates(enabled) {
        setLiveUpdates(false, enabled)
        syncMetricsPolling()
    }

    function setMetricsLiveUpdates(enabled) {
        setLiveUpdates(true, enabled)
        setLiveUpdates(false, enabled)
        syncMetricsPolling()
    }

    function toggleCpuLiveUpdates() {
        setCpuLiveUpdates(!cpuLiveUpdates)
    }

    function toggleGpuLiveUpdates() {
        setGpuLiveUpdates(!gpuLiveUpdates)
    }

    function toggleMetricsLiveUpdates() {
        setMetricsLiveUpdates(!(cpuLiveUpdates || gpuLiveUpdates))
    }

    function hideMetricsPopups() {
        cpuMetricsPopup.visible = false
        gpuMetricsPopup.visible = false
        syncMetricsPolling()
    }

    function showMetricsPopup(popup, anchorItem, otherPopup, isCpu) {
        if (popup.visible) {
            popup.visible = false
            syncMetricsPolling()
            return
        }
        otherPopup.visible = false
        if (bar.popupStatsPersistPause) {
            if (isCpu)
                cpuLiveUpdates = pauseAdapter.cpuLiveUpdates
            else
                gpuLiveUpdates = pauseAdapter.gpuLiveUpdates
        }

        var anchorXFrac = isCpu ? bar.popupStatsCpuAnchorX : bar.popupStatsGpuAnchorX
        var anchorWholePill = isCpu ? bar.popupStatsCpuAnchorWholePill : bar.popupStatsGpuAnchorWholePill
        var offsetX = isCpu ? bar.popupStatsCpuOffsetX : bar.popupStatsGpuOffsetX
        var offsetY = isCpu ? bar.popupStatsCpuOffsetY : bar.popupStatsGpuOffsetY
        var barGap = isCpu ? bar.popupStatsCpuBarGap : bar.popupStatsGpuBarGap

        var layoutAnchor = anchorWholePill ? root : anchorItem
        var pos = layoutAnchor.mapToItem(barBg, layoutAnchor.width * anchorXFrac, 0)
        var popupW = popup.implicitWidth
        var screenW = (bar.screen && bar.screen.width) ? bar.screen.width : 1920
        var targetX = bar.sideMargin + pos.x - (popupW / 2) + offsetX
        var minX = 12
        var maxX = screenW - popupW - 12

        popup.anchor.rect.x = Math.max(minX, Math.min(targetX, maxX))
        popup.anchor.rect.y = bar.popupAnchorY(popup.implicitHeight, barGap) + offsetY
        popup.visible = true
        syncMetricsPolling()
    }

    // === Appearance via Theme ===
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
    }

    Row {
        anchors.centerIn: parent
        spacing: 17

        // ----- CPU HALF -----
        Item {
            id: cpuSection
            width: 195
            height: 26

            MouseArea {
                id: cpuClick
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: (mouse) => {
                    if (mouse.button === Qt.RightButton) {
                        root.showMetricsPopup(cpuMetricsPopup, cpuSection, gpuMetricsPopup, true)
                    } else {
                        root.hideMetricsPopups()
                        Quickshell.execDetached(["kitty", "-e", "btop"])
                    }
                }
                ToolTip.text: "Left: btop · Right: CPU metrics"
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

        Rectangle {
            width: 1
            height: 17
            color: bar.divider
            anchors.verticalCenter: parent.verticalCenter
        }

        // ----- GPU HALF -----
        Item {
            id: gpuSection
            width: 195
            height: 26

            MouseArea {
                id: gpuClick
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: (mouse) => {
                    if (mouse.button === Qt.RightButton) {
                        root.showMetricsPopup(gpuMetricsPopup, gpuSection, cpuMetricsPopup, false)
                    } else {
                        root.hideMetricsPopups()
                        Quickshell.execDetached(["kitty", "-e", "nvtop"])
                    }
                }
                ToolTip.text: "Left: nvtop · Right: GPU metrics"
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

    // ===== CPU METRICS POPUP =====
    PopupWindow {
        id: cpuMetricsPopup
        anchor.window: bar
        implicitWidth: bar.popupStatsCpuWidth
        implicitHeight: bar.popupStatsCpuHeight
        visible: false
        grabFocus: true
        color: "transparent"
        onVisibleChanged: if (!visible) root.syncMetricsPolling()

        Rectangle {
            anchors.fill: parent
            radius: bar.popupRadius
            color: bar.glassPopupBg
            border.width: bar.controlBorderWidth
            border.color: bar.glassPopupBorder

            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: bar.popupHeaderHighlightHeight
                color: bar.glassPopupHighlight
                radius: parent.radius
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: bar.popupSpacingTight
                spacing: bar.popupSectionSpacing

                RowLayout {
                    Layout.fillWidth: true
                    spacing: bar.popupSectionSpacing

                    Text {
                        text: "CPU Metrics"
                        color: bar.text
                        font.pixelSize: bar.popupTitleSize
                        font.bold: true
                        font.family: bar.fontFamily
                    }

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        Layout.preferredHeight: 24
                        Layout.preferredWidth: cpuLiveBtnLabel.implicitWidth + 16
                        radius: bar.buttonRadius
                        color: cpuLiveBtnMa.containsMouse ? bar.popupButtonHoverBg : Qt.rgba(0.10, 0.10, 0.12, 0.6)
                        border.width: bar.controlBorderWidth
                        border.color: bar.dividerStrong

                        Text {
                            id: cpuLiveBtnLabel
                            anchors.centerIn: parent
                            text: cpuLiveUpdates ? "Pause updates" : "Resume updates"
                            color: cpuLiveUpdates ? bar.subtext : bar.accent
                            font.pixelSize: bar.popupHintSize
                            font.bold: !cpuLiveUpdates
                            font.family: bar.fontFamily
                        }

                        MouseArea {
                            id: cpuLiveBtnMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                setLiveUpdates(true, !cpuLiveUpdates)
                                syncMetricsPolling()
                            }
                        }
                    }

                    Text {
                        text: (cpuLiveUpdates ? "live" : "paused") + " · click outside to close"
                        color: bar.overlay
                        font.pixelSize: bar.popupHintSize
                        font.family: bar.fontFamily
                    }
                }

                CpuMonitorView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    service: sysMonService
                    textColor: bar.text
                    subtextColor: bar.subtext
                    accentColor: bar.accent
                    surfaceColor: bar.surface
                    overlayColor: bar.overlay
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            z: -1
            onClicked: cpuMetricsPopup.visible = false
        }
    }

    // ===== GPU METRICS POPUP =====
    PopupWindow {
        id: gpuMetricsPopup
        anchor.window: bar
        implicitWidth: bar.popupStatsGpuWidth
        implicitHeight: bar.popupStatsGpuHeight
        visible: false
        grabFocus: true
        color: "transparent"
        onVisibleChanged: if (!visible) root.syncMetricsPolling()

        Rectangle {
            anchors.fill: parent
            radius: bar.popupRadius
            color: bar.glassPopupBg
            border.width: bar.controlBorderWidth
            border.color: bar.glassPopupBorder

            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: bar.popupHeaderHighlightHeight
                color: bar.glassPopupHighlight
                radius: parent.radius
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: bar.popupSpacingTight
                spacing: bar.popupSectionSpacing

                RowLayout {
                    Layout.fillWidth: true
                    spacing: bar.popupSectionSpacing

                    Text {
                        text: "GPU Metrics"
                        color: bar.text
                        font.pixelSize: bar.popupTitleSize
                        font.bold: true
                        font.family: bar.fontFamily
                    }

                    Item { Layout.fillWidth: true }

                    Rectangle {
                        Layout.preferredHeight: 24
                        Layout.preferredWidth: gpuLiveBtnLabel.implicitWidth + 16
                        radius: bar.buttonRadius
                        color: gpuLiveBtnMa.containsMouse ? bar.popupButtonHoverBg : Qt.rgba(0.10, 0.10, 0.12, 0.6)
                        border.width: bar.controlBorderWidth
                        border.color: bar.dividerStrong

                        Text {
                            id: gpuLiveBtnLabel
                            anchors.centerIn: parent
                            text: gpuLiveUpdates ? "Pause updates" : "Resume updates"
                            color: gpuLiveUpdates ? bar.subtext : bar.accent
                            font.pixelSize: bar.popupHintSize
                            font.bold: !gpuLiveUpdates
                            font.family: bar.fontFamily
                        }

                        MouseArea {
                            id: gpuLiveBtnMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                setLiveUpdates(false, !gpuLiveUpdates)
                                syncMetricsPolling()
                            }
                        }
                    }

                    Text {
                        text: (gpuLiveUpdates ? "live" : "paused") + " · click outside to close"
                        color: bar.overlay
                        font.pixelSize: bar.popupHintSize
                        font.family: bar.fontFamily
                    }
                }

                GpuMonitorView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    service: sysMonService
                    textColor: bar.text
                    subtextColor: bar.subtext
                    accentColor: bar.accent
                    surfaceColor: bar.surface
                    overlayColor: bar.overlay
                    gaugeLowColor: bar.gaugeLow
                    gaugeMidColor: bar.gaugeMid
                    gaugeHighColor: bar.gaugeHigh
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            z: -1
            onClicked: gpuMetricsPopup.visible = false
        }
    }
}