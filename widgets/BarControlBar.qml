// =============================================================================
// BarControlBar.qml — Temporary mini-bar opened from empty main-bar chrome
// =============================================================================
//
// Right-click blank area of the main bar (wired in shell.qml) toggles this
// strip. Horizontally centered; stacks just inward from the main bar.
//
// Single PopupWindow (grabFocus). Toolbar buttons open panels:
//   Position · Monitor · Widgets · Launch · Clock
//
// =============================================================================

import Quickshell
import Quickshell.Io as Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

Item {
    id: root

    required property var bar

    width: 0
    height: 0

    property double _closedAtMs: 0
    readonly property int _reopenGuardMs: 220
    readonly property bool open: controlPopup.visible

    property string displayFamily: ""
    property int displayHz: 0
    property string displayProfile: ""
    property string displayStatus: ""
    property bool displayBusy: false
    property bool displayKnown: false

    // "" | "position" | "monitor" | "widgets" | "launch" | "clock"
    property string activeMenu: ""
    property int menuTick: 0

    readonly property color onGreen: "#4ade80"
    readonly property color offRed:  "#f87171"

    // Desktop app picker (Launch panel)
    property var desktopApps: []
    property string desktopAppsQuery: ""
    property bool desktopAppsLoading: false
    property string customName: ""
    property string customCommand: ""
    property string customIcon: ""

    readonly property string resolutionBin: {
        if (bar.hyprResolutionBin && String(bar.hyprResolutionBin).length)
            return String(bar.hyprResolutionBin)
        return "hypr-resolution"
    }

    readonly property var familyModel: [
        { id: "native", label: "Native", tip: "5120×1440 · scale 1 · 10-bit" },
        { id: "perf",   label: "Perf",   tip: "3840×1080 · scale 0.75 · 8-bit (DPI-matched)" }
    ]
    readonly property var hzModel: [
        { id: 60,  label: "60" },
        { id: 120, label: "120" },
        { id: 240, label: "240" }
    ]

    readonly property int pad: (bar.popupSpacingTight !== undefined) ? bar.popupSpacingTight : 6
    readonly property int chipH: Math.max(26, Math.round((bar.pillHeight || 36) * 0.78))
    readonly property int chipR: bar.buttonRadius !== undefined ? bar.buttonRadius : 8
    readonly property int panelMaxH: 420

    function profileFor(family, hz) {
        const f = String(family || "")
        const h = Number(hz) || 0
        if (f === "native") {
            if (h === 60) return "native-60"
            if (h === 120) return "native-120"
            if (h === 240) return "native"
        } else if (f === "perf") {
            if (h === 60) return "perf-60"
            if (h === 120) return "perf-120"
            if (h === 240) return "perf"
        }
        return ""
    }

    function hide() {
        root.activeMenu = ""
        if (!controlPopup.visible)
            return
        controlPopup.visible = false
        root._closedAtMs = Date.now()
    }

    function show() {
        refreshDisplayStatus()
        root.menuTick++
        controlPopup.visible = true
        root.scheduleReposition()
    }

    function toggle() {
        if (controlPopup.visible) {
            hide()
            return
        }
        if (Date.now() - root._closedAtMs < root._reopenGuardMs)
            return
        show()
    }

    function reposition() {
        // Prefer chrome's laid-out size; popup implicit* can lag one frame and
        // park a tall panel mid-screen (especially with bar on bottom).
        var popupW = Math.max(
            controlChrome.implicitWidth || 0,
            controlPopup.implicitWidth || 0,
            mainCol.implicitWidth + pad * 2,
            320
        )
        var popupH = Math.max(
            controlChrome.implicitHeight || 0,
            controlPopup.implicitHeight || 0,
            mainCol.implicitHeight + pad * 2,
            48
        )
        var screenW = 1920
        var screenH = 1080
        try {
            if (bar.screen && bar.screen.width)
                screenW = bar.screen.width
            else if (bar.width > 0)
                screenW = bar.width
            if (bar.screen && bar.screen.height)
                screenH = bar.screen.height
        } catch (e) {}

        var gap = (bar.popupBarGap !== undefined) ? bar.popupBarGap : 4
        var minX = 12
        var maxX = Math.max(minX, screenW - popupW - 12)
        // Center on the bar / screen
        var targetX = Math.round((screenW - popupW) / 2)

        controlPopup.anchor.rect.x = Math.max(minX, Math.min(targetX, maxX))
        // popupAnchorY keeps the edge of the popup against the bar (not floating mid-screen)
        var y = bar.popupAnchorY(popupH, gap)
        // Clamp so a huge panel never starts above the top of the monitor
        if (bar.barPosition === "bottom") {
            // y is top of popup relative to bar top; keep at least a few px on-screen
            var minY = -(screenH - (bar.barHeight || 58) - 8)
            if (y < minY)
                y = minY
        }
        controlPopup.anchor.rect.y = y
        controlPopup.anchor.rect.width = 1
        controlPopup.anchor.rect.height = 1
    }

    function scheduleReposition() {
        Qt.callLater(function() {
            root.reposition()
            // Second pass after ColumnLayout/Flickable settle
            settleRepositionTimer.restart()
        })
    }

    function toggleMenu(name) {
        if (root.activeMenu === name)
            root.activeMenu = ""
        else
            root.activeMenu = name
        root.menuTick++
        root.scheduleReposition()
    }

    function refreshDisplayStatus() {
        if (statusProcess.running)
            return
        statusProcess.exec([root.resolutionBin, "json"])
    }

    function applyDisplayStatus(j) {
        if (!j || typeof j !== "object")
            return
        root.displayProfile = j.profile ? String(j.profile) : ""
        root.displayFamily = j.family ? String(j.family) : ""
        root.displayHz = j.hz !== undefined && j.hz !== null ? Number(j.hz) || 0 : 0
        root.displayStatus = j.status ? String(j.status) : ""
        if (!root.displayStatus && j.width && j.height) {
            const rr = j.refreshRate !== undefined ? Number(j.refreshRate) : 0
            const rrTxt = rr > 0 ? ("@" + Math.round(rr)) : ""
            root.displayStatus = String(j.width) + "×" + String(j.height) + rrTxt
        }
        root.displayKnown = !!(root.displayFamily && root.displayHz)
        root.displayBusy = false
    }

    function selectFamily(familyId) {
        if (root.displayBusy)
            return
        const hz = root.displayHz > 0 ? root.displayHz : 240
        const name = profileFor(familyId, hz)
        if (!name)
            return
        root.displayFamily = familyId
        root.displayHz = hz
        applyProfile(name)
    }

    function selectHz(hzVal) {
        if (root.displayBusy)
            return
        const family = root.displayFamily.length ? root.displayFamily : "native"
        const name = profileFor(family, hzVal)
        if (!name)
            return
        root.displayFamily = family
        root.displayHz = hzVal
        applyProfile(name)
    }

    function applyProfile(name) {
        if (!name || root.displayBusy)
            return
        if (name === root.displayProfile && root.displayKnown)
            return
        root.displayBusy = true
        root.displayProfile = name
        root.displayStatus = "Applying " + name + "…"
        Quickshell.execDetached([root.resolutionBin, name])
        applySettleTimer.restart()
    }

    function openFullMenu() {
        Quickshell.execDetached([root.resolutionBin])
        hide()
    }

    function chipBg(active, hovered) {
        if (active)
            return bar.controlActiveBg !== undefined ? bar.controlActiveBg : Qt.rgba(0.0, 0.77, 0.96, 0.22)
        if (hovered)
            return bar.glassHover
        return bar.pillBg
    }

    function chipBorder(active, hovered) {
        if (active || hovered)
            return bar.accent
        return bar.pillBorder
    }

    function chipText(active, hovered) {
        if (active || hovered)
            return bar.accent
        return bar.subtext
    }

    function isWidgetOn(id) {
        void root.menuTick
        if (typeof bar.getWidgetVisible === "function")
            return !!bar.getWidgetVisible(id)
        return false
    }

    function toggleWidget(id) {
        if (typeof bar.toggleWidgetVisible === "function")
            bar.toggleWidgetVisible(id)
        root.menuTick++
        // Keep panel open; only refresh list state
        Qt.callLater(reposition)
    }

    function currentClockFormat() {
        void root.menuTick
        return (bar.clockFormat && String(bar.clockFormat).length)
            ? String(bar.clockFormat)
            : "dddd, MM·dd·yyyy | HH:mm:ss"
    }

    function setClockFormat(fmt) {
        if (typeof bar.setClockFormat === "function")
            bar.setClockFormat(fmt)
        root.menuTick++
        Qt.callLater(reposition)
    }

    // Combined widget list: layout order + zone + visibility for the Widgets panel.
    function widgetEntries() {
        void root.menuTick
        const layout = bar.widgetLayout
        const cat = bar.widgetCatalog || []
        const labels = {}
        for (let i = 0; i < cat.length; i++)
            labels[cat[i].id] = cat[i].label
        const out = []
        if (layout && layout.length) {
            for (let i = 0; i < layout.length; i++) {
                const e = layout[i]
                out.push({
                    id: e.id,
                    zone: e.zone,
                    label: labels[e.id] || e.id,
                    on: root.isWidgetOn(e.id)
                })
            }
        } else {
            for (let i = 0; i < cat.length; i++) {
                out.push({
                    id: cat[i].id,
                    zone: "right",
                    label: cat[i].label,
                    on: root.isWidgetOn(cat[i].id)
                })
            }
        }
        return out
    }

    function clockPresets() {
        return bar.clockFormatPresets || []
    }

    function quickLaunchEntries() {
        void root.menuTick
        const apps = bar.quickLaunchApps || []
        const out = []
        for (let i = 0; i < apps.length; i++) {
            const e = apps[i]
            out.push({
                index: i,
                icon: e.icon || "",
                glyph: e.glyph || "",
                tooltip: e.tooltip || "",
                command: e.command,
                commandText: root.commandToText(e.command)
            })
        }
        return out
    }

    function commandToText(cmd) {
        if (cmd === undefined || cmd === null)
            return ""
        if (typeof cmd === "string")
            return cmd
        const parts = []
        const len = cmd.length
        if (len === undefined)
            return String(cmd)
        for (let i = 0; i < len; i++)
            parts.push(String(cmd[i]))
        return parts.join(" ")
    }

    function refreshDesktopApps() {
        if (desktopAppsProcess.running)
            return
        root.desktopAppsLoading = true
        const script = bar.desktopAppsJsonScript || ""
        if (!script.length) {
            root.desktopAppsLoading = false
            return
        }
        const args = [script]
        if (root.desktopAppsQuery && root.desktopAppsQuery.length)
            args.push(root.desktopAppsQuery)
        desktopAppsProcess.exec(args)
    }

    function addDesktopApp(app) {
        if (!app)
            return
        const entry = {
            icon: app.icon || "",
            glyph: "",
            command: app.command || ["gtk-launch", String(app.id || "").replace(/\.desktop$/, "")],
            tooltip: app.name || app.tooltip || ""
        }
        if (typeof bar.addQuickLaunchApp === "function")
            bar.addQuickLaunchApp(entry)
        root.menuTick++
        Qt.callLater(reposition)
    }

    function addCustomApp() {
        const name = String(root.customName || "").trim()
        const cmd = String(root.customCommand || "").trim()
        const icon = String(root.customIcon || "").trim()
        if (!cmd.length)
            return
        const entry = {
            icon: icon,
            glyph: icon.length ? "" : "󰣆",
            command: cmd,
            tooltip: name || cmd
        }
        if (typeof bar.addQuickLaunchApp === "function")
            bar.addQuickLaunchApp(entry)
        root.customName = ""
        root.customCommand = ""
        root.customIcon = ""
        root.menuTick++
        Qt.callLater(reposition)
    }

    function removeLaunchApp(index) {
        if (typeof bar.removeQuickLaunchApp === "function")
            bar.removeQuickLaunchApp(index)
        root.menuTick++
        Qt.callLater(reposition)
    }

    function moveLaunchApp(index, delta) {
        if (typeof bar.moveQuickLaunchApp === "function")
            bar.moveQuickLaunchApp(index, delta)
        root.menuTick++
        Qt.callLater(reposition)
    }

    function filteredDesktopApps() {
        void root.menuTick
        // Script already token-filters + ranks; show more hits so office apps aren't cut off
        const list = root.desktopApps || []
        const out = []
        const max = root.desktopAppsQuery && root.desktopAppsQuery.length ? 80 : 60
        for (let i = 0; i < list.length && out.length < max; i++)
            out.push(list[i])
        return out
    }

    Connections {
        target: bar
        function onBarPositionChanged() {
            if (controlPopup.visible)
                root.scheduleReposition()
        }
        function onClockFormatChanged() {
            root.menuTick++
        }
    }

    Io.Process {
        id: statusProcess
        running: false
        stdout: Io.StdioCollector {
            id: statusStdout
            onStreamFinished: {
                const line = (statusStdout.text || "").trim()
                if (!line.startsWith("{"))
                    return
                try {
                    root.applyDisplayStatus(JSON.parse(line))
                    if (controlPopup.visible)
                        Qt.callLater(root.reposition)
                } catch (e) {}
            }
        }
        onExited: (code) => {
            if (code !== 0 && !(statusStdout.text || "").trim())
                root.displayStatus = "hypr-resolution unavailable"
        }
    }

    Timer {
        id: applySettleTimer
        interval: 900
        repeat: false
        onTriggered: {
            root.displayBusy = false
            root.refreshDisplayStatus()
        }
    }

    Timer {
        id: desktopSearchDebounce
        interval: 280
        repeat: false
        onTriggered: root.refreshDesktopApps()
    }

    Timer {
        id: settleRepositionTimer
        interval: 48
        repeat: false
        onTriggered: root.reposition()
    }

    Io.Process {
        id: desktopAppsProcess
        running: false
        stdout: Io.StdioCollector {
            id: desktopAppsStdout
            onStreamFinished: {
                root.desktopAppsLoading = false
                const text = (desktopAppsStdout.text || "").trim()
                if (!text.startsWith("[")) {
                    root.desktopApps = []
                    return
                }
                try {
                    root.desktopApps = JSON.parse(text)
                } catch (e) {
                    root.desktopApps = []
                }
                root.menuTick++
                if (controlPopup.visible)
                    root.scheduleReposition()
            }
        }
        onExited: (code) => {
            root.desktopAppsLoading = false
            if (code !== 0 && !(desktopAppsStdout.text || "").trim())
                root.desktopApps = []
        }
    }

    // -------------------------------------------------------------------------
    // One popup: toolbar row + optional expandable panel (stays under grabFocus)
    // -------------------------------------------------------------------------
    PopupWindow {
        id: controlPopup
        anchor.window: bar
        implicitWidth: controlChrome.implicitWidth
        implicitHeight: controlChrome.implicitHeight
        visible: false
        grabFocus: true
        color: "transparent"

        onVisibleChanged: {
            if (!visible) {
                root._closedAtMs = Date.now()
                root.activeMenu = ""
            }
        }

        onImplicitWidthChanged: if (visible) root.scheduleReposition()
        onImplicitHeightChanged: if (visible) root.scheduleReposition()

        Rectangle {
            id: controlChrome
            implicitWidth: Math.max(mainCol.implicitWidth + root.pad * 2, 420)
            implicitHeight: mainCol.implicitHeight + root.pad * 2
            radius: bar.popupRadius !== undefined ? bar.popupRadius : bar.barRadius
            color: bar.glassPopupBg
            border.width: bar.controlBorderWidth
            border.color: bar.glassPopupBorder

            // Keep clicks on empty chrome from falling through / dismissing oddly
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onPressed: (mouse) => { mouse.accepted = true }
                // Let children receive events — z below content
                z: -1
            }

            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: bar.popupHeaderHighlightHeight
                color: bar.glassPopupHighlight
                radius: parent.radius
                z: 2
            }

            ColumnLayout {
                id: mainCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: root.pad
                spacing: 8

                // ── Toolbar: clean menu buttons only ──
                RowLayout {
                    id: controlRow
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 8

                    Repeater {
                        model: [
                            { id: "position", label: "Position" },
                            { id: "monitor",  label: "Monitor" },
                            { id: "widgets",  label: "Widgets" },
                            { id: "launch",   label: "Launch" },
                            { id: "clock",    label: "Clock" }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool active: root.activeMenu === modelData.id
                            readonly property bool hovered: menuBtnMa.containsMouse
                            Layout.preferredHeight: root.chipH + 4
                            Layout.preferredWidth: Math.max(72, menuBtnLabel.implicitWidth + 20)
                            radius: root.chipR
                            color: root.chipBg(active, hovered)
                            border.width: bar.controlBorderWidth
                            border.color: root.chipBorder(active, hovered)
                            Text {
                                id: menuBtnLabel
                                anchors.centerIn: parent
                                text: modelData.label
                                font.pixelSize: bar.fontPillLabel !== undefined ? bar.fontPillLabel : 12
                                font.family: bar.fontFamily
                                font.bold: active
                                color: root.chipText(active, hovered)
                            }
                            MouseArea {
                                id: menuBtnMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (modelData.id === "monitor")
                                        root.refreshDisplayStatus()
                                    if (modelData.id === "launch")
                                        root.refreshDesktopApps()
                                    root.toggleMenu(modelData.id)
                                }
                            }
                        }
                    }
                }

                // ── Expandable panel (same window = clicks stay inside grabFocus) ──
                Rectangle {
                    id: panelBox
                    visible: root.activeMenu.length > 0
                    Layout.fillWidth: true
                    Layout.preferredHeight: visible
                        ? Math.min(root.panelMaxH, panelFlick.contentHeight + 8)
                        : 0
                    radius: root.chipR
                    color: Qt.rgba(0.05, 0.05, 0.07, 0.85)
                    border.width: bar.controlBorderWidth
                    border.color: bar.dividerStrong
                    clip: true

                    Flickable {
                        id: panelFlick
                        anchors.fill: parent
                        anchors.margins: 6
                        contentWidth: width
                        contentHeight: panelStack.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        flickableDirection: Flickable.VerticalFlick

                        ColumnLayout {
                            id: panelStack
                            width: panelFlick.width
                            spacing: 4

                            // ===== POSITION =====
                            ColumnLayout {
                                visible: root.activeMenu === "position"
                                Layout.fillWidth: true
                                spacing: 8

                                Text {
                                    text: "Bar position"
                                    color: bar.text
                                    font.pixelSize: bar.popupTitleSize
                                    font.bold: true
                                    font.family: bar.fontFamily
                                }
                                Text {
                                    text: "Pin the status bar to the top or bottom edge"
                                    color: bar.overlay
                                    font.pixelSize: bar.popupHintSize
                                    font.family: bar.fontFamily
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 44
                                        radius: root.chipR
                                        color: (bar.barPosition === "top")
                                               ? (bar.controlActiveBg || Qt.rgba(0, 0.77, 0.96, 0.22))
                                               : (posTopMa.containsMouse ? bar.glassHover : bar.pillBg)
                                        border.width: bar.controlBorderWidth
                                        border.color: (bar.barPosition === "top") ? bar.accent : bar.pillBorder
                                        RowLayout {
                                            anchors.centerIn: parent
                                            spacing: 8
                                            Text {
                                                text: bar.barPositionIconTop
                                                font.pixelSize: bar.iconSizePill
                                                font.family: bar.fontFamily
                                                color: bar.barPosition === "top" ? bar.accent : bar.subtext
                                            }
                                            Text {
                                                text: "Top"
                                                font.pixelSize: 13
                                                font.bold: bar.barPosition === "top"
                                                font.family: bar.fontFamily
                                                color: bar.barPosition === "top" ? bar.accent : bar.text
                                            }
                                        }
                                        MouseArea {
                                            id: posTopMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (typeof bar.setBarPosition === "function")
                                                    bar.setBarPosition("top")
                                                Qt.callLater(root.reposition)
                                            }
                                        }
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 44
                                        radius: root.chipR
                                        color: (bar.barPosition === "bottom")
                                               ? (bar.controlActiveBg || Qt.rgba(0, 0.77, 0.96, 0.22))
                                               : (posBotMa.containsMouse ? bar.glassHover : bar.pillBg)
                                        border.width: bar.controlBorderWidth
                                        border.color: (bar.barPosition === "bottom") ? bar.accent : bar.pillBorder
                                        RowLayout {
                                            anchors.centerIn: parent
                                            spacing: 8
                                            Text {
                                                text: bar.barPositionIconBottom
                                                font.pixelSize: bar.iconSizePill
                                                font.family: bar.fontFamily
                                                color: bar.barPosition === "bottom" ? bar.accent : bar.subtext
                                            }
                                            Text {
                                                text: "Bottom"
                                                font.pixelSize: 13
                                                font.bold: bar.barPosition === "bottom"
                                                font.family: bar.fontFamily
                                                color: bar.barPosition === "bottom" ? bar.accent : bar.text
                                            }
                                        }
                                        MouseArea {
                                            id: posBotMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (typeof bar.setBarPosition === "function")
                                                    bar.setBarPosition("bottom")
                                                Qt.callLater(root.reposition)
                                            }
                                        }
                                    }
                                }
                            }

                            // ===== MONITOR / RESOLUTION =====
                            ColumnLayout {
                                visible: root.activeMenu === "monitor"
                                Layout.fillWidth: true
                                spacing: 8

                                Text {
                                    text: "Monitor"
                                    color: bar.text
                                    font.pixelSize: bar.popupTitleSize
                                    font.bold: true
                                    font.family: bar.fontFamily
                                }
                                Text {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: {
                                        if (root.displayBusy && root.displayProfile)
                                            return "Applying " + root.displayProfile + "…"
                                        if (root.displayStatus)
                                            return root.displayStatus
                                        if (root.displayProfile)
                                            return root.displayProfile
                                        return "Loading…"
                                    }
                                    color: root.displayBusy ? bar.accent : bar.subtext
                                    font.pixelSize: 12
                                    font.family: bar.fontMono !== undefined ? bar.fontMono : bar.fontFamily
                                }

                                Text {
                                    text: "Resolution family"
                                    color: bar.overlay
                                    font.pixelSize: bar.popupHintSize
                                    font.family: bar.fontFamily
                                }
                                RowLayout {
                                    spacing: 6
                                    Repeater {
                                        model: root.familyModel
                                        delegate: Rectangle {
                                            required property var modelData
                                            readonly property bool active: root.displayFamily === modelData.id
                                            readonly property bool hovered: famMa.containsMouse
                                            Layout.preferredHeight: 34
                                            Layout.preferredWidth: Math.max(72, famLabel.implicitWidth + 20)
                                            radius: root.chipR
                                            color: root.chipBg(active, hovered)
                                            border.width: bar.controlBorderWidth
                                            border.color: root.chipBorder(active, hovered)
                                            opacity: root.displayBusy ? 0.65 : 1.0
                                            Text {
                                                id: famLabel
                                                anchors.centerIn: parent
                                                text: modelData.label
                                                font.pixelSize: 12
                                                font.family: bar.fontFamily
                                                font.bold: active
                                                color: root.chipText(active, hovered)
                                            }
                                            MouseArea {
                                                id: famMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                enabled: !root.displayBusy
                                                onClicked: root.selectFamily(modelData.id)
                                                ToolTip.visible: containsMouse
                                                ToolTip.delay: bar.tooltipDelay
                                                ToolTip.text: modelData.tip
                                            }
                                        }
                                    }
                                }

                                Text {
                                    text: "Refresh rate (Hz)"
                                    color: bar.overlay
                                    font.pixelSize: bar.popupHintSize
                                    font.family: bar.fontFamily
                                }
                                RowLayout {
                                    spacing: 6
                                    Repeater {
                                        model: root.hzModel
                                        delegate: Rectangle {
                                            required property var modelData
                                            readonly property bool active: root.displayHz === modelData.id
                                            readonly property bool hovered: hzMa.containsMouse
                                            Layout.preferredHeight: 34
                                            Layout.preferredWidth: 52
                                            radius: root.chipR
                                            color: root.chipBg(active, hovered)
                                            border.width: bar.controlBorderWidth
                                            border.color: root.chipBorder(active, hovered)
                                            opacity: root.displayBusy ? 0.65 : 1.0
                                            Text {
                                                anchors.centerIn: parent
                                                text: modelData.label
                                                font.pixelSize: 12
                                                font.family: bar.fontFamily
                                                font.bold: active
                                                color: root.chipText(active, hovered)
                                            }
                                            MouseArea {
                                                id: hzMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                enabled: !root.displayBusy
                                                onClicked: root.selectHz(modelData.id)
                                                ToolTip.visible: containsMouse
                                                ToolTip.delay: bar.tooltipDelay
                                                ToolTip.text: modelData.label + " Hz"
                                            }
                                        }
                                    }
                                }

                                Rectangle {
                                    Layout.preferredHeight: 32
                                    Layout.preferredWidth: moreLabel.implicitWidth + 18
                                    radius: root.chipR
                                    color: moreMa.containsMouse ? bar.glassHover : bar.pillBg
                                    border.width: bar.controlBorderWidth
                                    border.color: moreMa.containsMouse ? bar.accent : bar.pillBorder
                                    Text {
                                        id: moreLabel
                                        anchors.centerIn: parent
                                        text: "Full menu (Rofi)…"
                                        font.pixelSize: 12
                                        font.family: bar.fontFamily
                                        color: moreMa.containsMouse ? bar.accent : bar.subtext
                                    }
                                    MouseArea {
                                        id: moreMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.openFullMenu()
                                        ToolTip.visible: containsMouse
                                        ToolTip.delay: bar.tooltipDelay
                                        ToolTip.text: "All profiles including recording modes"
                                    }
                                }
                            }

                            // ===== WIDGETS (visibility + zone + order) =====
                            ColumnLayout {
                                visible: root.activeMenu === "widgets"
                                Layout.fillWidth: true
                                spacing: 4

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        Layout.fillWidth: true
                                        text: "Widgets"
                                        color: bar.text
                                        font.pixelSize: bar.popupTitleSize
                                        font.bold: true
                                        font.family: bar.fontFamily
                                    }
                                    Rectangle {
                                        Layout.preferredHeight: 24
                                        Layout.preferredWidth: resetLbl.implicitWidth + 12
                                        radius: root.chipR
                                        color: resetMa.containsMouse ? bar.glassHover : bar.pillBg
                                        border.width: bar.controlBorderWidth
                                        border.color: bar.pillBorder
                                        Text {
                                            id: resetLbl
                                            anchors.centerIn: parent
                                            text: "Reset layout"
                                            color: bar.subtext
                                            font.pixelSize: 11
                                            font.family: bar.fontFamily
                                        }
                                        MouseArea {
                                            id: resetMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (typeof bar.resetWidgetLayout === "function")
                                                    bar.resetWidgetLayout()
                                                root.menuTick++
                                                Qt.callLater(root.reposition)
                                            }
                                        }
                                    }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    text: "✓ green = on · ✕ red = off · L/C/R zone · ↑↓ order · saved"
                                    color: bar.overlay
                                    font.pixelSize: bar.popupHintSize
                                    font.family: bar.fontFamily
                                }

                                Repeater {
                                    model: root.widgetEntries()
                                    delegate: Rectangle {
                                        id: widgetRow
                                        required property var modelData
                                        readonly property string widgetId: modelData.id
                                        readonly property string widgetZone: modelData.zone
                                        readonly property string widgetLabel: modelData.label
                                        readonly property bool widgetOn: modelData.on

                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 34
                                        radius: root.chipR
                                        color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
                                        border.width: bar.controlBorderWidth
                                        border.color: widgetRow.widgetOn ? root.onGreen : bar.dividerStrong
                                        opacity: widgetRow.widgetOn ? 1.0 : 0.78

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 8
                                            anchors.rightMargin: 6
                                            spacing: 4

                                            // Visibility toggle: green ✓ / red ✕
                                            Rectangle {
                                                Layout.preferredWidth: 28
                                                Layout.preferredHeight: 26
                                                radius: 4
                                                color: visMa.containsMouse
                                                       ? (widgetRow.widgetOn
                                                          ? Qt.rgba(0.29, 0.87, 0.50, 0.18)
                                                          : Qt.rgba(0.97, 0.44, 0.44, 0.18))
                                                       : "transparent"
                                                border.width: 1
                                                border.color: widgetRow.widgetOn ? root.onGreen : root.offRed
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: widgetRow.widgetOn ? "✓" : "✕"
                                                    color: widgetRow.widgetOn ? root.onGreen : root.offRed
                                                    font.pixelSize: 14
                                                    font.bold: true
                                                    font.family: bar.fontFamily
                                                }
                                                MouseArea {
                                                    id: visMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.toggleWidget(widgetRow.widgetId)
                                                    ToolTip.visible: containsMouse
                                                    ToolTip.delay: bar.tooltipDelay
                                                    ToolTip.text: widgetRow.widgetOn ? "Hide from bar" : "Show on bar"
                                                }
                                            }

                                            Text {
                                                Layout.preferredWidth: 100
                                                elide: Text.ElideRight
                                                text: widgetRow.widgetLabel
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontFamily
                                            }

                                            // Zone chips
                                            Rectangle {
                                                Layout.preferredWidth: 22
                                                Layout.preferredHeight: 22
                                                radius: 4
                                                color: widgetRow.widgetZone === "left" ? bar.controlActiveBg : bar.pillBg
                                                border.width: 1
                                                border.color: widgetRow.widgetZone === "left" ? bar.accent : bar.pillBorder
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "L"
                                                    font.pixelSize: 10
                                                    font.family: bar.fontFamily
                                                    color: widgetRow.widgetZone === "left" ? bar.accent : bar.subtext
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        if (typeof bar.setWidgetZone === "function")
                                                            bar.setWidgetZone(widgetRow.widgetId, "left")
                                                        root.menuTick++
                                                        Qt.callLater(root.reposition)
                                                    }
                                                }
                                            }
                                            Rectangle {
                                                Layout.preferredWidth: 22
                                                Layout.preferredHeight: 22
                                                radius: 4
                                                color: widgetRow.widgetZone === "center" ? bar.controlActiveBg : bar.pillBg
                                                border.width: 1
                                                border.color: widgetRow.widgetZone === "center" ? bar.accent : bar.pillBorder
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "C"
                                                    font.pixelSize: 10
                                                    font.family: bar.fontFamily
                                                    color: widgetRow.widgetZone === "center" ? bar.accent : bar.subtext
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        if (typeof bar.setWidgetZone === "function")
                                                            bar.setWidgetZone(widgetRow.widgetId, "center")
                                                        root.menuTick++
                                                        Qt.callLater(root.reposition)
                                                    }
                                                }
                                            }
                                            Rectangle {
                                                Layout.preferredWidth: 22
                                                Layout.preferredHeight: 22
                                                radius: 4
                                                color: widgetRow.widgetZone === "right" ? bar.controlActiveBg : bar.pillBg
                                                border.width: 1
                                                border.color: widgetRow.widgetZone === "right" ? bar.accent : bar.pillBorder
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "R"
                                                    font.pixelSize: 10
                                                    font.family: bar.fontFamily
                                                    color: widgetRow.widgetZone === "right" ? bar.accent : bar.subtext
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        if (typeof bar.setWidgetZone === "function")
                                                            bar.setWidgetZone(widgetRow.widgetId, "right")
                                                        root.menuTick++
                                                        Qt.callLater(root.reposition)
                                                    }
                                                }
                                            }

                                            Item { Layout.fillWidth: true }

                                            Rectangle {
                                                Layout.preferredWidth: 24
                                                Layout.preferredHeight: 24
                                                radius: 4
                                                color: upMa.containsMouse ? bar.glassHover : bar.pillBg
                                                border.width: 1
                                                border.color: bar.pillBorder
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "↑"
                                                    color: bar.subtext
                                                    font.pixelSize: 12
                                                }
                                                MouseArea {
                                                    id: upMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        if (typeof bar.moveWidget === "function")
                                                            bar.moveWidget(widgetRow.widgetId, -1)
                                                        root.menuTick++
                                                        Qt.callLater(root.reposition)
                                                    }
                                                }
                                            }
                                            Rectangle {
                                                Layout.preferredWidth: 24
                                                Layout.preferredHeight: 24
                                                radius: 4
                                                color: dnMa.containsMouse ? bar.glassHover : bar.pillBg
                                                border.width: 1
                                                border.color: bar.pillBorder
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "↓"
                                                    color: bar.subtext
                                                    font.pixelSize: 12
                                                }
                                                MouseArea {
                                                    id: dnMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        if (typeof bar.moveWidget === "function")
                                                            bar.moveWidget(widgetRow.widgetId, 1)
                                                        root.menuTick++
                                                        Qt.callLater(root.reposition)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // ===== QUICK LAUNCH =====
                            ColumnLayout {
                                visible: root.activeMenu === "launch"
                                Layout.fillWidth: true
                                spacing: 6

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        Layout.fillWidth: true
                                        text: "Quick Launch"
                                        color: bar.text
                                        font.pixelSize: bar.popupTitleSize
                                        font.bold: true
                                        font.family: bar.fontFamily
                                    }
                                    Rectangle {
                                        Layout.preferredHeight: 24
                                        Layout.preferredWidth: resetLaunchLbl.implicitWidth + 12
                                        radius: root.chipR
                                        color: resetLaunchMa.containsMouse ? bar.glassHover : bar.pillBg
                                        border.width: bar.controlBorderWidth
                                        border.color: bar.pillBorder
                                        Text {
                                            id: resetLaunchLbl
                                            anchors.centerIn: parent
                                            text: "Reset"
                                            color: bar.subtext
                                            font.pixelSize: 11
                                            font.family: bar.fontFamily
                                        }
                                        MouseArea {
                                            id: resetLaunchMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (typeof bar.resetQuickLaunchApps === "function")
                                                    bar.resetQuickLaunchApps()
                                                root.menuTick++
                                                Qt.callLater(root.reposition)
                                            }
                                        }
                                    }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    text: "Pinned icons on the bar · ✕ remove · ↑↓ reorder · add from installed apps or custom"
                                    color: bar.overlay
                                    font.pixelSize: bar.popupHintSize
                                    font.family: bar.fontFamily
                                }

                                // Current pins
                                Repeater {
                                    model: root.quickLaunchEntries()
                                    delegate: Rectangle {
                                        id: launchRow
                                        required property var modelData
                                        readonly property int appIndex: modelData.index
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 40
                                        radius: root.chipR
                                        color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
                                        border.width: bar.controlBorderWidth
                                        border.color: bar.dividerStrong

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 8
                                            anchors.rightMargin: 6
                                            spacing: 6

                                            // Remove
                                            Rectangle {
                                                Layout.preferredWidth: 28
                                                Layout.preferredHeight: 26
                                                radius: 4
                                                color: rmMa.containsMouse ? Qt.rgba(0.97, 0.44, 0.44, 0.18) : "transparent"
                                                border.width: 1
                                                border.color: root.offRed
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "✕"
                                                    color: root.offRed
                                                    font.pixelSize: 13
                                                    font.bold: true
                                                }
                                                MouseArea {
                                                    id: rmMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.removeLaunchApp(launchRow.appIndex)
                                                    ToolTip.visible: containsMouse
                                                    ToolTip.delay: bar.tooltipDelay
                                                    ToolTip.text: "Remove"
                                                }
                                            }

                                            Image {
                                                visible: (modelData.icon || "").length > 0
                                                Layout.preferredWidth: 22
                                                Layout.preferredHeight: 22
                                                source: modelData.icon || ""
                                                fillMode: Image.PreserveAspectFit
                                                smooth: true
                                                mipmap: true
                                            }
                                            Text {
                                                visible: !(modelData.icon || "").length
                                                Layout.preferredWidth: 22
                                                horizontalAlignment: Text.AlignHCenter
                                                text: modelData.glyph || "󰣆"
                                                font.pixelSize: 16
                                                font.family: bar.fontFamily
                                                color: bar.subtext
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 0
                                                Text {
                                                    Layout.fillWidth: true
                                                    elide: Text.ElideRight
                                                    text: modelData.tooltip || "(unnamed)"
                                                    color: bar.text
                                                    font.pixelSize: 12
                                                    font.family: bar.fontFamily
                                                }
                                                Text {
                                                    Layout.fillWidth: true
                                                    elide: Text.ElideRight
                                                    text: modelData.commandText
                                                    color: bar.overlay
                                                    font.pixelSize: 10
                                                    font.family: bar.fontMono !== undefined ? bar.fontMono : bar.fontFamily
                                                }
                                            }

                                            Rectangle {
                                                Layout.preferredWidth: 24
                                                Layout.preferredHeight: 24
                                                radius: 4
                                                color: upLMa.containsMouse ? bar.glassHover : bar.pillBg
                                                border.width: 1
                                                border.color: bar.pillBorder
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "↑"
                                                    color: bar.subtext
                                                    font.pixelSize: 12
                                                }
                                                MouseArea {
                                                    id: upLMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.moveLaunchApp(launchRow.appIndex, -1)
                                                }
                                            }
                                            Rectangle {
                                                Layout.preferredWidth: 24
                                                Layout.preferredHeight: 24
                                                radius: 4
                                                color: dnLMa.containsMouse ? bar.glassHover : bar.pillBg
                                                border.width: 1
                                                border.color: bar.pillBorder
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "↓"
                                                    color: bar.subtext
                                                    font.pixelSize: 12
                                                }
                                                MouseArea {
                                                    id: dnLMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.moveLaunchApp(launchRow.appIndex, 1)
                                                }
                                            }
                                        }
                                    }
                                }

                                // Add from installed apps
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 1
                                    color: bar.dividerStrong
                                }
                                Text {
                                    text: "Add installed app"
                                    color: bar.text
                                    font.pixelSize: 12
                                    font.bold: true
                                    font.family: bar.fontFamily
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    TextField {
                                        id: appSearchField
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 30
                                        placeholderText: "Search apps…"
                                        color: bar.text
                                        placeholderTextColor: bar.overlay
                                        font.pixelSize: 12
                                        font.family: bar.fontFamily
                                        background: Rectangle {
                                            radius: root.chipR
                                            color: bar.pillBg
                                            border.width: 1
                                            border.color: appSearchField.activeFocus ? bar.accent : bar.pillBorder
                                        }
                                        onTextChanged: {
                                            root.desktopAppsQuery = text
                                            desktopSearchDebounce.restart()
                                        }
                                    }
                                    Rectangle {
                                        Layout.preferredHeight: 30
                                        Layout.preferredWidth: searchBtnLbl.implicitWidth + 14
                                        radius: root.chipR
                                        color: searchBtnMa.containsMouse ? bar.glassHover : bar.pillBg
                                        border.width: 1
                                        border.color: bar.pillBorder
                                        Text {
                                            id: searchBtnLbl
                                            anchors.centerIn: parent
                                            text: root.desktopAppsLoading ? "…" : "Search"
                                            color: bar.subtext
                                            font.pixelSize: 11
                                            font.family: bar.fontFamily
                                        }
                                        MouseArea {
                                            id: searchBtnMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.refreshDesktopApps()
                                        }
                                    }
                                }

                                Repeater {
                                    model: root.filteredDesktopApps()
                                    delegate: Rectangle {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 34
                                        radius: root.chipR
                                        color: addAppMa.containsMouse ? bar.popupButtonHoverBg : Qt.rgba(0.10, 0.10, 0.12, 0.45)
                                        border.width: 1
                                        border.color: bar.dividerStrong

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 8
                                            anchors.rightMargin: 8
                                            spacing: 8
                                            Image {
                                                visible: (modelData.icon || "").length > 0
                                                Layout.preferredWidth: 20
                                                Layout.preferredHeight: 20
                                                source: modelData.icon || ""
                                                fillMode: Image.PreserveAspectFit
                                                smooth: true
                                            }
                                            Text {
                                                visible: !(modelData.icon || "").length
                                                text: "󰣆"
                                                font.pixelSize: 14
                                                font.family: bar.fontFamily
                                                color: bar.subtext
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                elide: Text.ElideRight
                                                text: modelData.name || modelData.id
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontFamily
                                            }
                                            Text {
                                                text: "+"
                                                color: root.onGreen
                                                font.pixelSize: 16
                                                font.bold: true
                                            }
                                        }
                                        MouseArea {
                                            id: addAppMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.addDesktopApp(modelData)
                                            ToolTip.visible: containsMouse
                                            ToolTip.delay: bar.tooltipDelay
                                            ToolTip.text: "Add " + (modelData.name || "")
                                        }
                                    }
                                }

                                // Custom add
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 1
                                    color: bar.dividerStrong
                                }
                                Text {
                                    text: "Add custom"
                                    color: bar.text
                                    font.pixelSize: 12
                                    font.bold: true
                                    font.family: bar.fontFamily
                                }
                                TextField {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 28
                                    placeholderText: "Name (tooltip)"
                                    color: bar.text
                                    placeholderTextColor: bar.overlay
                                    font.pixelSize: 12
                                    text: root.customName
                                    onTextChanged: root.customName = text
                                    background: Rectangle {
                                        radius: root.chipR
                                        color: bar.pillBg
                                        border.width: 1
                                        border.color: bar.pillBorder
                                    }
                                }
                                TextField {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 28
                                    placeholderText: "Command (e.g. gtk-launch firefox or /usr/bin/app)"
                                    color: bar.text
                                    placeholderTextColor: bar.overlay
                                    font.pixelSize: 12
                                    text: root.customCommand
                                    onTextChanged: root.customCommand = text
                                    background: Rectangle {
                                        radius: root.chipR
                                        color: bar.pillBg
                                        border.width: 1
                                        border.color: bar.pillBorder
                                    }
                                }
                                TextField {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 28
                                    placeholderText: "Icon path (optional, e.g. /home/…/icons/app.svg)"
                                    color: bar.text
                                    placeholderTextColor: bar.overlay
                                    font.pixelSize: 12
                                    text: root.customIcon
                                    onTextChanged: root.customIcon = text
                                    background: Rectangle {
                                        radius: root.chipR
                                        color: bar.pillBg
                                        border.width: 1
                                        border.color: bar.pillBorder
                                    }
                                }
                                Rectangle {
                                    Layout.preferredHeight: 32
                                    Layout.preferredWidth: addCustomLbl.implicitWidth + 18
                                    radius: root.chipR
                                    color: addCustomMa.containsMouse ? bar.glassHover : bar.pillBg
                                    border.width: 1
                                    border.color: addCustomMa.containsMouse ? bar.accent : bar.pillBorder
                                    opacity: root.customCommand.trim().length ? 1 : 0.5
                                    Text {
                                        id: addCustomLbl
                                        anchors.centerIn: parent
                                        text: "Add custom app"
                                        color: addCustomMa.containsMouse ? bar.accent : bar.subtext
                                        font.pixelSize: 12
                                        font.family: bar.fontFamily
                                    }
                                    MouseArea {
                                        id: addCustomMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        enabled: root.customCommand.trim().length > 0
                                        onClicked: root.addCustomApp()
                                    }
                                }
                            }

                            // ===== CLOCK =====
                            ColumnLayout {
                                visible: root.activeMenu === "clock"
                                Layout.fillWidth: true
                                spacing: 4

                                Text {
                                    text: "Clock format"
                                    color: bar.text
                                    font.pixelSize: bar.popupTitleSize
                                    font.bold: true
                                    font.family: bar.fontFamily
                                }
                                Text {
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    text: "Preview: " + Qt.formatDateTime(new Date(), root.currentClockFormat())
                                    color: bar.accent
                                    font.pixelSize: 12
                                    font.family: bar.fontMono !== undefined ? bar.fontMono : bar.fontFamily
                                }

                                Repeater {
                                    model: root.clockPresets()
                                    delegate: Rectangle {
                                        required property var modelData
                                        readonly property bool active: root.currentClockFormat() === modelData.format
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 36
                                        radius: root.chipR
                                        color: cRowMa.containsMouse ? bar.popupButtonHoverBg : Qt.rgba(0.10, 0.10, 0.12, 0.55)
                                        border.width: bar.controlBorderWidth
                                        border.color: active ? bar.accent : bar.dividerStrong

                                        ColumnLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 10
                                            anchors.rightMargin: 10
                                            anchors.topMargin: 4
                                            anchors.bottomMargin: 4
                                            spacing: 0
                                            Text {
                                                text: modelData.label + (active ? "  · active" : "")
                                                color: active ? bar.accent : bar.text
                                                font.pixelSize: 12
                                                font.bold: active
                                                font.family: bar.fontFamily
                                            }
                                            Text {
                                                text: modelData.tip || modelData.format
                                                color: bar.overlay
                                                font.pixelSize: 10
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }
                                        MouseArea {
                                            id: cRowMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.setClockFormat(modelData.format)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Text {
                    visible: root.activeMenu.length > 0
                    Layout.alignment: Qt.AlignRight
                    text: "click outside to close"
                    color: bar.overlay
                    font.pixelSize: bar.popupHintSize
                    font.family: bar.fontFamily
                }
            }
        }
    }
}

