// =============================================================================
// BarControlBar.qml — Temporary mini-bar opened from empty main-bar chrome
// =============================================================================
//
// Right-click blank area of the main bar (wired in shell.qml) toggles this
// strip. Horizontally centered; stacks just inward from the main bar.
//
// Single PopupWindow (grabFocus). Expandable panel on top; toolbar buttons
// along the bottom: Position · Wallpaper · Widgets · Options · Launch · Autostart · Clock
// Widgets = layout; Options = behavior prefs (workspaces, echo cancel, applets, UI scale).
// Window height follows content; tall menus scroll only when needed.
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

    // "" | "position" | "wallpaper" | "widgets" | "options" | "launch" | "autostart" | "clock"
    // ("sizes" accepted as alias of "widgets" for any leftover callers)
    property string activeMenu: ""
    property int menuTick: 0
    // Options panel live reads (refreshed on open / toggle)
    property int optionsTick: 0
    // Options panel: fixed right slot — toggles & fields share the same vertical center line
    readonly property int optControlColW: 40
    readonly property int optToggleW: 28
    readonly property int optToggleH: 26
    readonly property int optFieldW: 40

    readonly property color onGreen: "#4ade80"
    readonly property color offRed:  "#f87171"

    // Desktop app picker (Launch panel)
    property var desktopApps: []
    property string desktopAppsQuery: ""
    property bool desktopAppsLoading: false
    property string customName: ""
    property string customCommand: ""
    property string customIcon: ""

    // Wallpaper panel
    property var wallpaperImages: []
    property string wallpaperDirDisplay: ""
    property bool wallpaperLoading: false
    property string wallpaperBusyPath: ""
    property string wallpaperStatus: ""

    // Autostart panel (XDG ~/.config/autostart)
    property var autostartEntries: []
    property bool autostartLoading: false
    property string autostartStatus: ""
    property string autostartSearch: ""

    readonly property int pad: (bar.popupSpacingTight !== undefined) ? bar.popupSpacingTight : 6
    readonly property int chipH: Math.max(26, Math.round((bar.pillHeight || 36) * 0.78))
    readonly property int chipR: bar.buttonRadius !== undefined ? bar.buttonRadius : 8
    // Cap panel so the popup always fits above/below the bar; short menus shrink to content.
    readonly property int panelMaxH: {
        void root.menuTick
        let screenH = 1080
        try {
            if (bar.screen && bar.screen.height)
                screenH = bar.screen.height
            else if (bar.height > 200)
                screenH = bar.height
        } catch (e) {}
        const reserved = (bar.barHeight || 58) + 110
        return Math.max(240, Math.min(640, screenH - reserved))
    }

    // Height of the *visible* panel section only (ignore hidden menus — childrenRect does not).
    function measurePanelContent() {
        void root.menuTick
        void root.activeMenu
        if (typeof panelStack === "undefined" || !panelStack)
            return 0
        let h = 0
        const kids = panelStack.children
        for (let i = 0; i < kids.length; i++) {
            const c = kids[i]
            if (!c || c.visible === false)
                continue
            const ch = Math.max(
                c.implicitHeight || 0,
                (c.Layout && c.Layout.preferredHeight > 0) ? c.Layout.preferredHeight : 0,
                c.height || 0
            )
            if (ch > h)
                h = ch
        }
        // Fallback if layout has not assigned heights yet
        if (h < 8 && panelStack.implicitHeight > 0)
            h = panelStack.implicitHeight
        return h
    }

    // Menus that commonly overflow the screen and should scroll inside the panel
    readonly property bool panelScrollableMenu: {
        const m = root.activeMenu
        return m === "wallpaper" || m === "widgets" || m === "options"
               || m === "autostart" || m === "launch"
    }

    readonly property bool panelNeedsScroll: {
        void root.menuTick
        void root.activeMenu
        if (!root.panelScrollableMenu)
            return false
        const content = root.measurePanelContent()
        return content + 18 > root.panelMaxH
    }

    function hide() {
        root.activeMenu = ""
        if (!controlPopup.visible)
            return
        controlPopup.visible = false
        root._closedAtMs = Date.now()
    }

    function show() {
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

    function resetPanelScroll() {
        // Switching menus must not keep Widgets' scroll offset (Clock etc. look empty)
        if (typeof panelFlick === "undefined" || !panelFlick)
            return
        panelFlick.contentY = 0
        panelFlick.returnToBounds()
    }

    function toggleMenu(name) {
        // Sizes was merged into Widgets
        if (name === "sizes")
            name = "widgets"
        if (root.activeMenu === name)
            root.activeMenu = ""
        else
            root.activeMenu = name
        if (root.activeMenu === "options")
            root.refreshOptions()
        root.menuTick++
        root.resetPanelScroll()
        // After layout height settles (tall Widgets → short Clock): remeasure + scroll top
        Qt.callLater(function () {
            root.resetPanelScroll()
            root.menuTick++
            root.scheduleReposition()
        })
        root.scheduleReposition()
    }

    function refreshOptions() {
        if (typeof bar.refreshOptionsState === "function")
            bar.refreshOptionsState()
        root.optionsTick++
        root.menuTick++
    }

    function optBool(getter, fallback) {
        void root.optionsTick
        void root.menuTick
        try {
            if (typeof getter === "function")
                return !!getter()
        } catch (e) {}
        return !!fallback
    }

    function optEchoCancel() {
        void root.optionsTick
        if (typeof bar.getEchoCancelEnabled === "function")
            return !!bar.getEchoCancelEnabled()
        return false
    }

    function optNetApplet() {
        void root.optionsTick
        if (typeof bar.getNetworkAppletAutostart === "function")
            return !!bar.getNetworkAppletAutostart()
        return true
    }

    function optBtApplet() {
        void root.optionsTick
        if (typeof bar.getBluetoothAppletAutostart === "function")
            return !!bar.getBluetoothAppletAutostart()
        return true
    }

    function optMetricsLive() {
        void root.optionsTick
        if (typeof bar.getMetricsLiveUpdates === "function")
            return !!bar.getMetricsLiveUpdates()
        return true
    }

    function optUiScaleManual() {
        void root.optionsTick
        void root.menuTick
        const m = Number(bar.uiScaleManual)
        return (m > 0) ? m : 0
    }

    function optUiScaleIsAuto() {
        return !(root.optUiScaleManual() > 0)
    }

    function setOptToggle(setterName, enabled) {
        const on = !!enabled
        switch (setterName) {
        case "setShowMagicWorkspacePill":
            if (typeof bar.setShowMagicWorkspacePill === "function")
                bar.setShowMagicWorkspacePill(on)
            break
        case "setWsShowOnlyActive":
            if (typeof bar.setWsShowOnlyActive === "function")
                bar.setWsShowOnlyActive(on)
            break
        case "setWsStartupCloseMagic":
            if (typeof bar.setWsStartupCloseMagic === "function")
                bar.setWsStartupCloseMagic(on)
            break
        case "setEchoCancel":
            if (typeof bar.setEchoCancel === "function")
                bar.setEchoCancel(on)
            break
        case "setNetworkAppletAutostart":
            if (typeof bar.setNetworkAppletAutostart === "function")
                bar.setNetworkAppletAutostart(on)
            break
        case "setBluetoothAppletAutostart":
            if (typeof bar.setBluetoothAppletAutostart === "function")
                bar.setBluetoothAppletAutostart(on)
            break
        case "setMetricsLiveUpdates":
            if (typeof bar.setMetricsLiveUpdates === "function")
                bar.setMetricsLiveUpdates(on)
            break
        case "setShowControlBarPill":
            if (typeof bar.setShowControlBarPill === "function")
                bar.setShowControlBarPill(on)
            else if (typeof bar.setWidgetVisible === "function")
                bar.setWidgetVisible("controlBar", on)
            break
        case "setShowStatCpu":
            if (typeof bar.setShowStatCpu === "function")
                bar.setShowStatCpu(on)
            break
        case "setShowStatMem":
            if (typeof bar.setShowStatMem === "function")
                bar.setShowStatMem(on)
            break
        case "setShowStatGpu":
            if (typeof bar.setShowStatGpu === "function")
                bar.setShowStatGpu(on)
            break
        case "setShowEchoCancelInMenu":
            if (typeof bar.setShowEchoCancelInMenu === "function")
                bar.setShowEchoCancelInMenu(on)
            break
        }
        Qt.callLater(root.refreshOptions)
    }

    function setOptNumber(setterName, value) {
        const n = Number(value)
        if (!(n >= 0) && setterName !== "setWsStartupWorkspace")
            return
        switch (setterName) {
        case "setWsMinimumShown":
            if (typeof bar.setWsMinimumShown === "function")
                bar.setWsMinimumShown(n)
            break
        case "setWsStartupWorkspace":
            if (typeof bar.setWsStartupWorkspace === "function")
                bar.setWsStartupWorkspace(n)
            break
        }
        Qt.callLater(root.refreshOptions)
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

    // Widget list for the combined Widgets panel (layout + visibility + scale).
    function widgetEntries() {
        void root.menuTick
        void bar.widgetScales
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
        // Script already token-filters + ranks; show more hits so office apps aren't cut off.
        // Autostart also stacks current entries above the picker — keep that list shorter so
        // the panel doesn't bury results below the fold (scroll still available).
        const list = root.desktopApps || []
        const out = []
        const q = root.desktopAppsQuery && root.desktopAppsQuery.length
        const isAs = root.activeMenu === "autostart"
        const max = q ? (isAs ? 50 : 80) : (isAs ? 24 : 60)
        for (let i = 0; i < list.length && out.length < max; i++)
            out.push(list[i])
        return out
    }

    function desktopAppsTruncated() {
        void root.menuTick
        const list = root.desktopApps || []
        const shown = root.filteredDesktopApps().length
        return list.length > shown
    }

    function wallpaperDir() {
        void root.menuTick
        if (bar.wallpaperDir && String(bar.wallpaperDir).length)
            return String(bar.wallpaperDir)
        return "/home/crome/Pictures/wallpapers"
    }

    function wallpaperCurrent() {
        void root.menuTick
        return (bar.wallpaperCurrent && String(bar.wallpaperCurrent).length)
            ? String(bar.wallpaperCurrent)
            : ""
    }

    function refreshWallpapers() {
        if (wallpaperListProcess.running)
            return
        root.wallpaperLoading = true
        root.wallpaperStatus = "Loading…"
        const script = bar.wallpaperListScript || ""
        if (!script.length) {
            root.wallpaperLoading = false
            root.wallpaperStatus = "list script missing"
            return
        }
        wallpaperListProcess.exec([script, root.wallpaperDir()])
    }

    function applyWallpaper(path) {
        if (!path || !String(path).length)
            return
        root.wallpaperBusyPath = String(path)
        root.wallpaperStatus = "Applying…"
        if (typeof bar.applyWallpaper === "function")
            bar.applyWallpaper(path)
        else {
            const script = bar.wallpaperApplyScript || ""
            const mon = bar.wallpaperMonitor || "DP-1"
            if (script.length)
                Quickshell.execDetached([script, path, mon])
        }
        wallpaperApplySettle.restart()
        root.menuTick++
    }

    function pickWallpaperDir() {
        const script = bar.wallpaperPickDirScript || ""
        if (!script.length || wallpaperPickDirProcess.running)
            return
        root.wallpaperStatus = "Pick a folder…"
        wallpaperPickDirProcess.exec([script, root.wallpaperDir()])
    }

    function addWallpapers() {
        const script = bar.wallpaperAddScript || ""
        if (!script.length || wallpaperAddProcess.running)
            return
        root.wallpaperStatus = "Choose images to add…"
        wallpaperAddProcess.exec([script, root.wallpaperDir()])
    }

    function openWallpaperDir() {
        const d = root.wallpaperDir()
        if (d.length)
            Quickshell.execDetached(["xdg-open", d])
    }

    function scalePercentOf(id) {
        // Depend on widgetScales so bindings refresh without menuTick thrash
        void bar.widgetScales
        if (typeof bar.widgetScale === "function")
            return Math.round(bar.widgetScale(id) * 100)
        return 100
    }

    function refreshAutostart() {
        if (autostartListProcess.running)
            return
        root.autostartLoading = true
        root.autostartStatus = "Loading…"
        const script = bar.autostartListScript || ""
        if (!script.length) {
            root.autostartLoading = false
            root.autostartStatus = "list script missing"
            return
        }
        autostartListProcess.exec([script])
    }

    function autostartRows() {
        void root.menuTick
        const list = root.autostartEntries || []
        const q = (root.autostartSearch || "").trim().toLowerCase()
        const out = []
        for (let i = 0; i < list.length; i++) {
            const e = list[i]
            if (q) {
                const blob = ((e.name || "") + " " + (e.id || "") + " " + (e.exec || "")).toLowerCase()
                if (blob.indexOf(q) < 0)
                    continue
            }
            out.push(e)
        }
        return out
    }

    function setAutostartEnabled(id, enabled) {
        const script = bar.autostartSetScript || ""
        if (!script.length || !id)
            return
        autostartSetProcess.exec([script, enabled ? "enable" : "disable", id])
    }

    function removeAutostart(id) {
        const script = bar.autostartSetScript || ""
        if (!script.length || !id)
            return
        autostartSetProcess.exec([script, "remove", id])
    }

    function runAutostartNow(id) {
        const script = bar.autostartRunScript || ""
        if (!script.length)
            return
        if (id)
            Quickshell.execDetached([script, id])
        else
            Quickshell.execDetached([script])
        root.autostartStatus = id ? ("Started " + id) : "Started enabled apps"
    }

    function addAutostartFromApp(app) {
        if (!app)
            return
        const script = bar.autostartAddScript || ""
        if (!script.length)
            return
        const args = [script]
        if (app.id) {
            args.push("--desktop-id", String(app.id))
        } else {
            args.push("--name", String(app.name || app.tooltip || "App"))
            const cmd = app.command
            let execStr = ""
            if (typeof cmd === "string")
                execStr = cmd
            else if (cmd && cmd.length !== undefined) {
                const parts = []
                for (let i = 0; i < cmd.length; i++)
                    parts.push(String(cmd[i]))
                execStr = parts.join(" ")
            }
            if (!execStr.length)
                return
            args.push("--exec", execStr)
            if (app.icon)
                args.push("--icon", String(app.icon))
        }
        root.autostartStatus = "Adding…"
        autostartAddProcess.exec(args)
    }

    function openAutostartDir() {
        Quickshell.execDetached(["xdg-open", "/home/crome/.config/autostart"])
    }

    function setScalePercent(id, percent) {
        let p = Number(percent)
        if (!(p > 0))
            return
        if (p < 80)
            p = 80
        if (p > 180)
            p = 180
        if (typeof bar.setWidgetScale === "function")
            bar.setWidgetScale(id, p / 100)
        // Do not bump menuTick / full panel rebuild while dragging — bar.widgetScales notifies
        sizeRepositionTimer.restart()
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

    // Light debounce when sizes change (avoid reposition every slider step)
    Timer {
        id: sizeRepositionTimer
        interval: 80
        repeat: false
        onTriggered: root.reposition()
    }

    Timer {
        id: wallpaperApplySettle
        interval: 400
        repeat: false
        onTriggered: {
            root.wallpaperBusyPath = ""
            root.wallpaperStatus = "Applied"
            root.menuTick++
        }
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

    Io.Process {
        id: wallpaperListProcess
        running: false
        stdout: Io.StdioCollector {
            id: wallpaperListStdout
            onStreamFinished: {
                root.wallpaperLoading = false
                const text = (wallpaperListStdout.text || "").trim()
                if (!text.startsWith("{")) {
                    root.wallpaperImages = []
                    root.wallpaperStatus = "No images found"
                    return
                }
                try {
                    const j = JSON.parse(text)
                    root.wallpaperDirDisplay = j.dir || root.wallpaperDir()
                    root.wallpaperImages = j.images || []
                    root.wallpaperStatus = (j.count || 0) + " image(s)"
                } catch (e) {
                    root.wallpaperImages = []
                    root.wallpaperStatus = "Parse error"
                }
                root.menuTick++
                if (controlPopup.visible)
                    root.scheduleReposition()
            }
        }
        onExited: (code) => {
            root.wallpaperLoading = false
            if (code !== 0 && !(wallpaperListStdout.text || "").trim()) {
                root.wallpaperImages = []
                root.wallpaperStatus = "Failed to list wallpapers"
            }
        }
    }

    Io.Process {
        id: wallpaperPickDirProcess
        running: false
        stdout: Io.StdioCollector {
            id: wallpaperPickDirStdout
            onStreamFinished: {
                const dir = (wallpaperPickDirStdout.text || "").trim()
                if (!dir.length) {
                    root.wallpaperStatus = "Directory unchanged"
                    return
                }
                if (typeof bar.setWallpaperDir === "function")
                    bar.setWallpaperDir(dir)
                root.wallpaperStatus = "Folder: " + dir
                root.menuTick++
                root.refreshWallpapers()
            }
        }
    }

    Io.Process {
        id: wallpaperAddProcess
        running: false
        stdout: Io.StdioCollector {
            id: wallpaperAddStdout
            onStreamFinished: {
                const text = (wallpaperAddStdout.text || "").trim()
                let n = 0
                try {
                    if (text.startsWith("{")) {
                        const j = JSON.parse(text)
                        n = j.count || 0
                    }
                } catch (e) {}
                root.wallpaperStatus = n > 0 ? ("Added " + n + " file(s)") : "No files added"
                root.refreshWallpapers()
            }
        }
    }

    Io.Process {
        id: autostartListProcess
        running: false
        stdout: Io.StdioCollector {
            id: autostartListStdout
            onStreamFinished: {
                root.autostartLoading = false
                const text = (autostartListStdout.text || "").trim()
                if (!text.startsWith("{")) {
                    root.autostartEntries = []
                    root.autostartStatus = "No entries"
                    return
                }
                try {
                    const j = JSON.parse(text)
                    root.autostartEntries = j.entries || []
                    root.autostartStatus = (j.count || 0) + " entry(ies)"
                } catch (e) {
                    root.autostartEntries = []
                    root.autostartStatus = "Parse error"
                }
                root.menuTick++
                if (controlPopup.visible)
                    root.scheduleReposition()
            }
        }
        onExited: (code) => {
            root.autostartLoading = false
            if (code !== 0 && !(autostartListStdout.text || "").trim()) {
                root.autostartEntries = []
                root.autostartStatus = "Failed to list"
            }
        }
    }

    Io.Process {
        id: autostartSetProcess
        running: false
        stdout: Io.StdioCollector {
            id: autostartSetStdout
            onStreamFinished: {
                const line = (autostartSetStdout.text || "").trim()
                root.autostartStatus = line.length ? line : "Updated"
                root.refreshAutostart()
            }
        }
        onExited: (code) => {
            if (code !== 0)
                root.autostartStatus = "Update failed"
            root.refreshAutostart()
        }
    }

    Io.Process {
        id: autostartAddProcess
        running: false
        stdout: Io.StdioCollector {
            id: autostartAddStdout
            onStreamFinished: {
                const line = (autostartAddStdout.text || "").trim()
                root.autostartStatus = line.length ? line : "Added"
                root.refreshAutostart()
            }
        }
        onExited: (code) => {
            if (code !== 0)
                root.autostartStatus = "Add failed"
            root.refreshAutostart()
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
            implicitWidth: Math.max(mainCol.implicitWidth + root.pad * 2, root.activeMenu === "wallpaper" ? 500 : 420)
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

                // ── Expandable panel (same window = clicks stay inside grabFocus) ──
                Rectangle {
                    id: panelBox
                    visible: root.activeMenu.length > 0
                    Layout.fillWidth: true
                    // Margins (8×2) + slack; height tracks active menu content up to panelMaxH
                    readonly property int panelPad: 18
                    readonly property int contentH: {
                        void root.menuTick
                        void root.activeMenu
                        return root.measurePanelContent()
                    }
                    Layout.preferredHeight: {
                        void root.menuTick
                        void root.activeMenu
                        if (!visible)
                            return 0
                        // Fit content; screen-cap (and scroll) only for tall menus
                        const need = panelBox.contentH + panelPad
                        if (need <= 0)
                            return 72
                        if (root.panelScrollableMenu)
                            return Math.min(root.panelMaxH, Math.max(48, need))
                        // Position / Clock etc.: hug content (still never exceed screen)
                        return Math.min(root.panelMaxH, Math.max(48, need))
                    }
                    Layout.minimumHeight: visible ? 48 : 0
                    Layout.maximumHeight: root.panelMaxH
                    radius: root.chipR
                    color: Qt.rgba(0.05, 0.05, 0.07, 0.85)
                    border.width: bar.controlBorderWidth
                    border.color: bar.dividerStrong
                    clip: true

                    Flickable {
                        id: panelFlick
                        anchors.fill: parent
                        anchors.margins: 8
                        contentWidth: width
                        // Only the visible section — never the sum of hidden menus
                        contentHeight: {
                            void root.menuTick
                            void root.activeMenu
                            return Math.max(root.measurePanelContent(), 1)
                        }
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        flickableDirection: Flickable.VerticalFlick
                        // Scroll only when content exceeds the panel (Wallpaper/Widgets/Autostart/Launch)
                        interactive: root.panelNeedsScroll && (contentHeight > height + 4)

                        onContentHeightChanged: {
                            if (contentHeight <= height + 4)
                                contentY = 0
                            else if (contentY > contentHeight - height)
                                contentY = Math.max(0, contentHeight - height)
                        }
                        onHeightChanged: {
                            if (contentHeight <= height + 4)
                                contentY = 0
                            else if (contentY > contentHeight - height)
                                contentY = Math.max(0, contentHeight - height)
                        }

                        ScrollBar.vertical: ScrollBar {
                            id: panelScrollBar
                            policy: (root.panelNeedsScroll && panelFlick.contentHeight > panelFlick.height + 4)
                                    ? ScrollBar.AsNeeded
                                    : ScrollBar.AlwaysOff
                            width: 8
                            padding: 1
                            contentItem: Rectangle {
                                implicitWidth: 6
                                radius: 3
                                color: bar.accent
                                opacity: 0.55
                            }
                            background: Rectangle {
                                implicitWidth: 8
                                radius: 4
                                color: Qt.rgba(1, 1, 1, 0.06)
                            }
                        }

                        ColumnLayout {
                            id: panelStack
                            width: panelFlick.width - ((root.panelNeedsScroll && panelFlick.contentHeight > panelFlick.height + 4) ? 10 : 0)
                            spacing: 6

                            // ===== POSITION =====
                            ColumnLayout {
                                visible: root.activeMenu === "position"
                                Layout.fillWidth: true
                                spacing: 10

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
                                    Layout.preferredHeight: 52
                                    Layout.minimumHeight: 52
                                    spacing: 8

                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.fillHeight: true
                                        Layout.preferredHeight: 52
                                        Layout.minimumHeight: 52
                                        radius: root.chipR
                                        color: (bar.barPosition === "top")
                                               ? (bar.controlActiveBg || Qt.rgba(0, 0.77, 0.96, 0.22))
                                               : (posTopMa.containsMouse ? bar.glassHover : bar.pillBg)
                                        border.width: bar.controlBorderWidth
                                        border.color: (bar.barPosition === "top") ? bar.accent : bar.pillBorder
                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 12
                                            anchors.rightMargin: 12
                                            anchors.topMargin: 10
                                            anchors.bottomMargin: 10
                                            spacing: 8
                                            Text {
                                                Layout.alignment: Qt.AlignVCenter
                                                text: bar.barPositionIconTop
                                                font.pixelSize: bar.iconSizePill
                                                font.family: bar.fontFamily
                                                color: bar.barPosition === "top" ? bar.accent : bar.subtext
                                            }
                                            Text {
                                                Layout.alignment: Qt.AlignVCenter
                                                text: "Top"
                                                font.pixelSize: 13
                                                font.bold: bar.barPosition === "top"
                                                font.family: bar.fontFamily
                                                color: bar.barPosition === "top" ? bar.accent : bar.text
                                            }
                                            Item { Layout.fillWidth: true }
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
                                        Layout.fillHeight: true
                                        Layout.preferredHeight: 52
                                        Layout.minimumHeight: 52
                                        radius: root.chipR
                                        color: (bar.barPosition === "bottom")
                                               ? (bar.controlActiveBg || Qt.rgba(0, 0.77, 0.96, 0.22))
                                               : (posBotMa.containsMouse ? bar.glassHover : bar.pillBg)
                                        border.width: bar.controlBorderWidth
                                        border.color: (bar.barPosition === "bottom") ? bar.accent : bar.pillBorder
                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 12
                                            anchors.rightMargin: 12
                                            anchors.topMargin: 10
                                            anchors.bottomMargin: 10
                                            spacing: 8
                                            Text {
                                                Layout.alignment: Qt.AlignVCenter
                                                text: bar.barPositionIconBottom
                                                font.pixelSize: bar.iconSizePill
                                                font.family: bar.fontFamily
                                                color: bar.barPosition === "bottom" ? bar.accent : bar.subtext
                                            }
                                            Text {
                                                Layout.alignment: Qt.AlignVCenter
                                                text: "Bottom"
                                                font.pixelSize: 13
                                                font.bold: bar.barPosition === "bottom"
                                                font.family: bar.fontFamily
                                                color: bar.barPosition === "bottom" ? bar.accent : bar.text
                                            }
                                            Item { Layout.fillWidth: true }
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

                            // ===== WALLPAPER =====
                            ColumnLayout {
                                visible: root.activeMenu === "wallpaper"
                                Layout.fillWidth: true
                                spacing: 8

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        Layout.fillWidth: true
                                        text: "Wallpaper"
                                        color: bar.text
                                        font.pixelSize: bar.popupTitleSize
                                        font.bold: true
                                        font.family: bar.fontFamily
                                    }
                                    Rectangle {
                                        Layout.preferredHeight: 26
                                        Layout.preferredWidth: refreshWpLbl.implicitWidth + 12
                                        radius: root.chipR
                                        color: refreshWpMa.containsMouse ? bar.glassHover : bar.pillBg
                                        border.width: 1
                                        border.color: bar.pillBorder
                                        Text {
                                            id: refreshWpLbl
                                            anchors.centerIn: parent
                                            text: root.wallpaperLoading ? "…" : "Refresh"
                                            color: bar.subtext
                                            font.pixelSize: 11
                                            font.family: bar.fontFamily
                                        }
                                        MouseArea {
                                            id: refreshWpMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.refreshWallpapers()
                                        }
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    wrapMode: Text.WrapAnywhere
                                    text: root.wallpaperDirDisplay || root.wallpaperDir()
                                    color: bar.overlay
                                    font.pixelSize: bar.popupHintSize
                                    font.family: bar.fontMono !== undefined ? bar.fontMono : bar.fontFamily
                                }
                                Text {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: root.wallpaperStatus.length ? root.wallpaperStatus : "Click a thumbnail to apply"
                                    color: bar.subtext
                                    font.pixelSize: 11
                                    font.family: bar.fontFamily
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    Rectangle {
                                        Layout.preferredHeight: 30
                                        Layout.preferredWidth: changeDirLbl.implicitWidth + 14
                                        radius: root.chipR
                                        color: changeDirMa.containsMouse ? bar.glassHover : bar.pillBg
                                        border.width: 1
                                        border.color: changeDirMa.containsMouse ? bar.accent : bar.pillBorder
                                        Text {
                                            id: changeDirLbl
                                            anchors.centerIn: parent
                                            text: "Change folder…"
                                            color: changeDirMa.containsMouse ? bar.accent : bar.subtext
                                            font.pixelSize: 11
                                            font.family: bar.fontFamily
                                        }
                                        MouseArea {
                                            id: changeDirMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.pickWallpaperDir()
                                        }
                                    }
                                    Rectangle {
                                        Layout.preferredHeight: 30
                                        Layout.preferredWidth: addWpLbl.implicitWidth + 14
                                        radius: root.chipR
                                        color: addWpMa.containsMouse ? bar.glassHover : bar.pillBg
                                        border.width: 1
                                        border.color: addWpMa.containsMouse ? bar.accent : bar.pillBorder
                                        Text {
                                            id: addWpLbl
                                            anchors.centerIn: parent
                                            text: "Add wallpapers…"
                                            color: addWpMa.containsMouse ? bar.accent : bar.subtext
                                            font.pixelSize: 11
                                            font.family: bar.fontFamily
                                        }
                                        MouseArea {
                                            id: addWpMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.addWallpapers()
                                        }
                                    }
                                    Rectangle {
                                        Layout.preferredHeight: 30
                                        Layout.preferredWidth: openWpLbl.implicitWidth + 14
                                        radius: root.chipR
                                        color: openWpMa.containsMouse ? bar.glassHover : bar.pillBg
                                        border.width: 1
                                        border.color: bar.pillBorder
                                        Text {
                                            id: openWpLbl
                                            anchors.centerIn: parent
                                            text: "Open folder"
                                            color: bar.subtext
                                            font.pixelSize: 11
                                            font.family: bar.fontFamily
                                        }
                                        MouseArea {
                                            id: openWpMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.openWallpaperDir()
                                        }
                                    }
                                }

                                // Visual grid of wallpapers
                                Flow {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Repeater {
                                        model: root.wallpaperImages
                                        delegate: Rectangle {
                                            required property var modelData
                                            readonly property bool isCurrent: root.wallpaperCurrent() === modelData.path
                                            readonly property bool isBusy: root.wallpaperBusyPath === modelData.path
                                            width: 148
                                            height: 108
                                            radius: root.chipR
                                            color: Qt.rgba(0.08, 0.08, 0.10, 0.9)
                                            border.width: isCurrent || thumbMa.containsMouse ? 2 : 1
                                            border.color: isCurrent ? root.onGreen
                                                          : (thumbMa.containsMouse ? bar.accent : bar.dividerStrong)
                                            clip: true

                                            Image {
                                                id: thumb
                                                anchors.fill: parent
                                                anchors.margins: 2
                                                anchors.bottomMargin: 22
                                                source: modelData.url || ("file://" + modelData.path)
                                                fillMode: Image.PreserveAspectCrop
                                                asynchronous: true
                                                cache: true
                                                sourceSize.width: 296
                                                sourceSize.height: 168
                                                smooth: true
                                                mipmap: true
                                            }

                                            // Dim while applying
                                            Rectangle {
                                                anchors.fill: thumb
                                                visible: isBusy
                                                color: Qt.rgba(0, 0, 0, 0.45)
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "…"
                                                    color: bar.accent
                                                    font.pixelSize: 18
                                                }
                                            }

                                            // Footer: name + dimensions
                                            Rectangle {
                                                anchors.left: parent.left
                                                anchors.right: parent.right
                                                anchors.bottom: parent.bottom
                                                height: 22
                                                color: Qt.rgba(0, 0, 0, 0.72)
                                                Text {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 6
                                                    anchors.rightMargin: 6
                                                    verticalAlignment: Text.AlignVCenter
                                                    elide: Text.ElideRight
                                                    text: {
                                                        const dims = (modelData.width > 0 && modelData.height > 0)
                                                            ? (modelData.width + "×" + modelData.height)
                                                            : "?"
                                                        return modelData.name + "  ·  " + dims
                                                    }
                                                    color: isCurrent ? root.onGreen : bar.subtext
                                                    font.pixelSize: 10
                                                    font.family: bar.fontFamily
                                                }
                                            }

                                            MouseArea {
                                                id: thumbMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.applyWallpaper(modelData.path)
                                                ToolTip.visible: containsMouse
                                                ToolTip.delay: bar.tooltipDelay
                                                ToolTip.text: {
                                                    const dims = (modelData.width > 0 && modelData.height > 0)
                                                        ? (modelData.width + " × " + modelData.height)
                                                        : "dimensions unknown"
                                                    return modelData.name + "\n" + dims + "\nClick to apply"
                                                }
                                            }
                                        }
                                    }
                                }

                                Text {
                                    visible: !root.wallpaperLoading && root.wallpaperImages.length === 0
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    text: "No images in this folder. Use “Add wallpapers…” or “Change folder…”."
                                    color: bar.overlay
                                    font.pixelSize: 11
                                    font.family: bar.fontFamily
                                }
                            }

                            // ===== WIDGETS (visibility + zone + order + width scale) =====
                            ColumnLayout {
                                visible: root.activeMenu === "widgets" || root.activeMenu === "sizes"
                                Layout.fillWidth: true
                                spacing: 7

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
                                    Rectangle {
                                        Layout.preferredHeight: 24
                                        Layout.preferredWidth: resetSizesLbl.implicitWidth + 12
                                        radius: root.chipR
                                        color: resetSizesMa.containsMouse ? bar.glassHover : bar.pillBg
                                        border.width: 1
                                        border.color: bar.pillBorder
                                        Text {
                                            id: resetSizesLbl
                                            anchors.centerIn: parent
                                            text: "Reset sizes"
                                            color: bar.subtext
                                            font.pixelSize: 11
                                            font.family: bar.fontFamily
                                        }
                                        MouseArea {
                                            id: resetSizesMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (typeof bar.resetWidgetScales === "function")
                                                    bar.resetWidgetScales()
                                                root.menuTick++
                                                Qt.callLater(root.reposition)
                                            }
                                        }
                                    }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    text: "✓ on / ✕ off · L/C/R zone · ↑↓ order · width % (80–180, height fixed)"
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
                                        readonly property int livePct: root.scalePercentOf(widgetId)
                                        property int localPct: livePct
                                        property bool editing: false

                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 58
                                        radius: root.chipR
                                        color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
                                        border.width: bar.controlBorderWidth
                                        border.color: bar.dividerStrong
                                        opacity: widgetRow.widgetOn ? 1.0 : 0.78

                                        onLivePctChanged: {
                                            if (!widgetRow.editing && !sizeSlider.pressed)
                                                widgetRow.localPct = livePct
                                        }

                                        ColumnLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 8
                                            anchors.rightMargin: 6
                                            anchors.topMargin: 5
                                            anchors.bottomMargin: 5
                                            spacing: 4

                                            // Row 1: visibility · name · zone · order
                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 4

                                                Rectangle {
                                                    Layout.preferredWidth: 28
                                                    Layout.preferredHeight: 24
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
                                                    Layout.preferredWidth: 92
                                                    elide: Text.ElideRight
                                                    text: widgetRow.widgetLabel
                                                    color: bar.text
                                                    font.pixelSize: 12
                                                    font.family: bar.fontFamily
                                                }

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

                                            // Row 2: horizontal width scale
                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 6

                                                Slider {
                                                    id: sizeSlider
                                                    Layout.fillWidth: true
                                                    Layout.preferredHeight: 16
                                                    from: 80
                                                    to: 180
                                                    stepSize: 5
                                                    value: widgetRow.localPct
                                                    onMoved: {
                                                        widgetRow.localPct = Math.round(value)
                                                        root.setScalePercent(widgetRow.widgetId, widgetRow.localPct)
                                                    }
                                                    onPressedChanged: {
                                                        if (!pressed)
                                                            root.setScalePercent(widgetRow.widgetId, widgetRow.localPct)
                                                    }

                                                    background: Rectangle {
                                                        x: sizeSlider.leftPadding
                                                        y: sizeSlider.topPadding + sizeSlider.availableHeight / 2 - height / 2
                                                        implicitWidth: 160
                                                        implicitHeight: 5
                                                        width: sizeSlider.availableWidth
                                                        height: 5
                                                        radius: 3
                                                        color: Qt.rgba(1, 1, 1, 0.12)
                                                        Rectangle {
                                                            width: sizeSlider.visualPosition * parent.width
                                                            height: parent.height
                                                            radius: 3
                                                            color: bar.accent
                                                        }
                                                    }
                                                    handle: Rectangle {
                                                        x: sizeSlider.leftPadding + sizeSlider.visualPosition * (sizeSlider.availableWidth - width)
                                                        y: sizeSlider.topPadding + sizeSlider.availableHeight / 2 - height / 2
                                                        implicitWidth: 12
                                                        implicitHeight: 12
                                                        radius: 3
                                                        color: sizeSlider.pressed ? bar.accent : bar.text
                                                        border.width: 1
                                                        border.color: bar.accent
                                                    }
                                                }

                                                TextField {
                                                    id: pctField
                                                    Layout.preferredWidth: 44
                                                    Layout.preferredHeight: 22
                                                    horizontalAlignment: Text.AlignHCenter
                                                    color: bar.text
                                                    font.pixelSize: 11
                                                    font.family: bar.fontMono !== undefined ? bar.fontMono : bar.fontFamily
                                                    text: String(widgetRow.localPct)
                                                    validator: IntValidator { bottom: 80; top: 180 }
                                                    background: Rectangle {
                                                        radius: 4
                                                        color: bar.pillBg
                                                        border.width: 1
                                                        border.color: pctField.activeFocus ? bar.accent : bar.pillBorder
                                                    }
                                                    onActiveFocusChanged: widgetRow.editing = activeFocus
                                                    onTextChanged: {
                                                        const n = parseInt(text, 10)
                                                        if (!isNaN(n))
                                                            widgetRow.localPct = n
                                                    }
                                                    onAccepted: root.setScalePercent(widgetRow.widgetId, widgetRow.localPct)
                                                    onEditingFinished: root.setScalePercent(widgetRow.widgetId, widgetRow.localPct)
                                                }
                                                Text {
                                                    text: "%"
                                                    color: bar.overlay
                                                    font.pixelSize: 10
                                                    font.family: bar.fontFamily
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

                            // ===== AUTOSTART (XDG) =====
                            ColumnLayout {
                                visible: root.activeMenu === "autostart"
                                Layout.fillWidth: true
                                spacing: 6

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        Layout.fillWidth: true
                                        text: "Autostart"
                                        color: bar.text
                                        font.pixelSize: bar.popupTitleSize
                                        font.bold: true
                                        font.family: bar.fontFamily
                                    }
                                    Rectangle {
                                        Layout.preferredHeight: 24
                                        Layout.preferredWidth: refreshAsLbl.implicitWidth + 12
                                        radius: root.chipR
                                        color: refreshAsMa.containsMouse ? bar.glassHover : bar.pillBg
                                        border.width: 1
                                        border.color: bar.pillBorder
                                        Text {
                                            id: refreshAsLbl
                                            anchors.centerIn: parent
                                            text: root.autostartLoading ? "…" : "Refresh"
                                            color: bar.subtext
                                            font.pixelSize: 11
                                            font.family: bar.fontFamily
                                        }
                                        MouseArea {
                                            id: refreshAsMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.refreshAutostart()
                                        }
                                    }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    text: "XDG apps in ~/.config/autostart (session login). Core Hyprland services stay in autostarts.lua."
                                    color: bar.overlay
                                    font.pixelSize: bar.popupHintSize
                                    font.family: bar.fontFamily
                                }
                                Text {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    text: root.autostartStatus.length ? root.autostartStatus : "Toggle ✓/✕ · add from apps below"
                                    color: bar.subtext
                                    font.pixelSize: 11
                                    font.family: bar.fontFamily
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    Rectangle {
                                        Layout.preferredHeight: 28
                                        Layout.preferredWidth: openAsLbl.implicitWidth + 12
                                        radius: root.chipR
                                        color: openAsMa.containsMouse ? bar.glassHover : bar.pillBg
                                        border.width: 1
                                        border.color: bar.pillBorder
                                        Text {
                                            id: openAsLbl
                                            anchors.centerIn: parent
                                            text: "Open folder"
                                            color: bar.subtext
                                            font.pixelSize: 11
                                            font.family: bar.fontFamily
                                        }
                                        MouseArea {
                                            id: openAsMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.openAutostartDir()
                                        }
                                    }
                                    Rectangle {
                                        Layout.preferredHeight: 28
                                        Layout.preferredWidth: runAllLbl.implicitWidth + 12
                                        radius: root.chipR
                                        color: runAllMa.containsMouse ? bar.glassHover : bar.pillBg
                                        border.width: 1
                                        border.color: runAllMa.containsMouse ? bar.accent : bar.pillBorder
                                        Text {
                                            id: runAllLbl
                                            anchors.centerIn: parent
                                            text: "Run enabled now"
                                            color: runAllMa.containsMouse ? bar.accent : bar.subtext
                                            font.pixelSize: 11
                                            font.family: bar.fontFamily
                                        }
                                        MouseArea {
                                            id: runAllMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.runAutostartNow("")
                                        }
                                    }
                                }

                                // Current autostart entries
                                Repeater {
                                    model: root.autostartRows()
                                    delegate: Rectangle {
                                        id: asRow
                                        required property var modelData
                                        readonly property bool on: !!modelData.enabled
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 40
                                        radius: root.chipR
                                        color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
                                        border.width: 1
                                        border.color: asRow.on ? root.onGreen : bar.dividerStrong
                                        opacity: asRow.on ? 1.0 : 0.78

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 8
                                            anchors.rightMargin: 6
                                            spacing: 6

                                            // Enable toggle
                                            Rectangle {
                                                Layout.preferredWidth: 28
                                                Layout.preferredHeight: 26
                                                radius: 4
                                                color: asToggleMa.containsMouse
                                                       ? (asRow.on ? Qt.rgba(0.29, 0.87, 0.50, 0.18) : Qt.rgba(0.97, 0.44, 0.44, 0.18))
                                                       : "transparent"
                                                border.width: 1
                                                border.color: asRow.on ? root.onGreen : root.offRed
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: asRow.on ? "✓" : "✕"
                                                    color: asRow.on ? root.onGreen : root.offRed
                                                    font.pixelSize: 14
                                                    font.bold: true
                                                }
                                                MouseArea {
                                                    id: asToggleMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.setAutostartEnabled(modelData.id, !asRow.on)
                                                    ToolTip.visible: containsMouse
                                                    ToolTip.delay: bar.tooltipDelay
                                                    ToolTip.text: asRow.on ? "Disable at login" : "Enable at login"
                                                }
                                            }

                                            Image {
                                                visible: (modelData.icon || "").length > 0
                                                Layout.preferredWidth: 22
                                                Layout.preferredHeight: 22
                                                source: modelData.icon ? ("file://" + modelData.icon) : ""
                                                fillMode: Image.PreserveAspectFit
                                                smooth: true
                                            }
                                            Text {
                                                visible: !(modelData.icon || "").length
                                                Layout.preferredWidth: 22
                                                horizontalAlignment: Text.AlignHCenter
                                                text: "󰣆"
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
                                                    text: modelData.name || modelData.id
                                                    color: bar.text
                                                    font.pixelSize: 12
                                                    font.family: bar.fontFamily
                                                }
                                                Text {
                                                    Layout.fillWidth: true
                                                    elide: Text.ElideRight
                                                    text: modelData.exec || modelData.id
                                                    color: bar.overlay
                                                    font.pixelSize: 10
                                                    font.family: bar.fontMono !== undefined ? bar.fontMono : bar.fontFamily
                                                }
                                            }

                                            // Run now
                                            Rectangle {
                                                Layout.preferredWidth: 28
                                                Layout.preferredHeight: 26
                                                radius: 4
                                                color: runOneMa.containsMouse ? bar.glassHover : bar.pillBg
                                                border.width: 1
                                                border.color: bar.pillBorder
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "▶"
                                                    color: bar.subtext
                                                    font.pixelSize: 11
                                                }
                                                MouseArea {
                                                    id: runOneMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.runAutostartNow(modelData.id)
                                                    ToolTip.visible: containsMouse
                                                    ToolTip.delay: bar.tooltipDelay
                                                    ToolTip.text: "Run now"
                                                }
                                            }

                                            // Remove
                                            Rectangle {
                                                Layout.preferredWidth: 28
                                                Layout.preferredHeight: 26
                                                radius: 4
                                                color: rmAsMa.containsMouse ? Qt.rgba(0.97, 0.44, 0.44, 0.18) : "transparent"
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
                                                    id: rmAsMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.removeAutostart(modelData.id)
                                                    ToolTip.visible: containsMouse
                                                    ToolTip.delay: bar.tooltipDelay
                                                    ToolTip.text: "Remove from autostart"
                                                }
                                            }
                                        }
                                    }
                                }

                                Text {
                                    visible: !root.autostartLoading && root.autostartRows().length === 0
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    text: "No XDG autostart entries yet. Add one from installed apps below."
                                    color: bar.overlay
                                    font.pixelSize: 11
                                    font.family: bar.fontFamily
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 1
                                    color: bar.dividerStrong
                                }
                                Text {
                                    text: "Add installed app to autostart"
                                    color: bar.text
                                    font.pixelSize: 12
                                    font.bold: true
                                    font.family: bar.fontFamily
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    TextField {
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
                                            border.color: parent.activeFocus ? bar.accent : bar.pillBorder
                                        }
                                        onTextChanged: {
                                            root.desktopAppsQuery = text
                                            root.autostartSearch = ""
                                            desktopSearchDebounce.restart()
                                        }
                                    }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    visible: root.filteredDesktopApps().length > 0
                                    wrapMode: Text.WordWrap
                                    text: root.desktopAppsTruncated()
                                          ? ("Showing " + root.filteredDesktopApps().length
                                             + " · scroll for more · type to filter")
                                          : ("Scroll if the list is longer than the panel")
                                    color: bar.overlay
                                    font.pixelSize: 10
                                    font.family: bar.fontFamily
                                }

                                // Bounded picker so entries above stay visible; scrolls inside.
                                Flickable {
                                    id: asAppFlick
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: {
                                        const n = root.filteredDesktopApps().length
                                        if (n <= 0)
                                            return 0
                                        const rowH = 36
                                        return Math.min(220, n * rowH)
                                    }
                                    contentWidth: width
                                    contentHeight: asAppCol.implicitHeight
                                    clip: true
                                    boundsBehavior: Flickable.StopAtBounds
                                    flickableDirection: Flickable.VerticalFlick
                                    interactive: contentHeight > height + 2

                                    ScrollBar.vertical: ScrollBar {
                                        policy: asAppFlick.contentHeight > asAppFlick.height + 2
                                                ? ScrollBar.AsNeeded
                                                : ScrollBar.AlwaysOff
                                        width: 6
                                    }

                                    Column {
                                        id: asAppCol
                                        width: asAppFlick.width - 8
                                        spacing: 2

                                        Repeater {
                                            model: root.filteredDesktopApps()
                                            delegate: Rectangle {
                                                required property var modelData
                                                width: asAppCol.width
                                                height: 34
                                                radius: root.chipR
                                                color: addAsMa.containsMouse ? bar.popupButtonHoverBg : Qt.rgba(0.10, 0.10, 0.12, 0.45)
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
                                                        source: modelData.icon ? (String(modelData.icon).indexOf("file:") === 0 ? modelData.icon : ("file://" + modelData.icon)) : ""
                                                        fillMode: Image.PreserveAspectFit
                                                        smooth: true
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
                                                    id: addAsMa
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    // Don't steal vertical drag from asAppFlick
                                                    preventStealing: false
                                                    onClicked: root.addAutostartFromApp(modelData)
                                                    ToolTip.visible: containsMouse
                                                    ToolTip.delay: bar.tooltipDelay
                                                    ToolTip.text: "Add " + (modelData.name || "") + " to login autostart"
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // ===== OPTIONS (behavior prefs — not layout) =====
                            ColumnLayout {
                                visible: root.activeMenu === "options"
                                Layout.fillWidth: true
                                spacing: 8

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        Layout.fillWidth: true
                                        text: "Options"
                                        color: bar.text
                                        font.pixelSize: bar.popupTitleSize
                                        font.bold: true
                                        font.family: bar.fontFamily
                                    }
                                    Rectangle {
                                        Layout.preferredHeight: 24
                                        Layout.preferredWidth: refreshOptLbl.implicitWidth + 12
                                        radius: root.chipR
                                        color: refreshOptMa.containsMouse ? bar.glassHover : bar.pillBg
                                        border.width: 1
                                        border.color: bar.pillBorder
                                        Text {
                                            id: refreshOptLbl
                                            anchors.centerIn: parent
                                            text: "Refresh"
                                            color: bar.subtext
                                            font.pixelSize: 11
                                            font.family: bar.fontFamily
                                        }
                                        MouseArea {
                                            id: refreshOptMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.refreshOptions()
                                        }
                                    }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    text: "Behavior prefs (saved where noted). Layout is under Widgets. Actions stay on keybinds / qs ipc."
                                    color: bar.overlay
                                    font.pixelSize: bar.popupHintSize
                                    font.family: bar.fontFamily
                                }

                                Text {
                                    text: "Bar / UI"
                                    color: bar.text
                                    font.pixelSize: 12
                                    font.bold: true
                                    font.family: bar.fontFamily
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 40
                                    radius: root.chipR
                                    color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
                                    border.width: 1
                                    border.color: bar.dividerStrong
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 10
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            spacing: 0
                                            Text {
                                                text: "UI scale auto"
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: "Scale with monitor width (recommended)"
                                                color: bar.overlay
                                                font.pixelSize: 10
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }
                                        Item {
                                            Layout.preferredWidth: root.optControlColW
                                            Layout.maximumWidth: root.optControlColW
                                            Layout.minimumWidth: root.optControlColW
                                            Layout.fillHeight: true
                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: root.optToggleW
                                                height: root.optToggleH
                                                radius: 4
                                                border.width: 1
                                                border.color: (root.optUiScaleIsAuto()) ? root.onGreen : root.offRed
                                                color: "transparent"
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: (root.optUiScaleIsAuto()) ? "✓" : "✕"
                                                    color: (root.optUiScaleIsAuto()) ? root.onGreen : root.offRed
                                                    font.pixelSize: 14
                                                    font.bold: true
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                    if (root.optUiScaleIsAuto()) {
                                                        const cur = Number(bar.uiScale) || 1
                                                        if (typeof bar.setUiScale === "function")
                                                            bar.setUiScale(cur)
                                                    } else if (typeof bar.setUiScaleAuto === "function") {
                                                        bar.setUiScaleAuto()
                                                    }
                                                    root.refreshOptions()
                                                }
                                                }
                                            }
                                        }
                                    }
                                }
                                Rectangle {
                                    visible: !root.optUiScaleIsAuto()
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 48
                                    radius: root.chipR
                                    color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
                                    border.width: 1
                                    border.color: bar.dividerStrong
                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        anchors.topMargin: 6
                                        anchors.bottomMargin: 6
                                        spacing: 2
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Text {
                                                text: "Manual scale"
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontFamily
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: Math.round(root.optUiScaleManual() * 100) + "%"
                                                color: bar.subtext
                                                font.pixelSize: 11
                                                font.family: bar.fontMono !== undefined ? bar.fontMono : bar.fontFamily
                                                Layout.preferredWidth: root.optControlColW
                                                horizontalAlignment: Text.AlignHCenter
                                            }
                                        }
                                        Slider {
                                            id: uiScaleSlider
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 16
                                            from: 65
                                            to: 100
                                            stepSize: 5
                                            value: Math.round(root.optUiScaleManual() * 100)
                                            onMoved: {
                                                if (typeof bar.setUiScale === "function")
                                                    bar.setUiScale(Math.round(value) / 100)
                                            }
                                            onPressedChanged: {
                                                if (!pressed)
                                                    root.refreshOptions()
                                            }
                                            background: Rectangle {
                                                x: uiScaleSlider.leftPadding
                                                y: uiScaleSlider.topPadding + uiScaleSlider.availableHeight / 2 - height / 2
                                                implicitWidth: 160
                                                implicitHeight: 5
                                                width: uiScaleSlider.availableWidth
                                                height: 5
                                                radius: 3
                                                color: Qt.rgba(1, 1, 1, 0.12)
                                                Rectangle {
                                                    width: uiScaleSlider.visualPosition * parent.width
                                                    height: parent.height
                                                    radius: 3
                                                    color: bar.accent
                                                }
                                            }
                                            handle: Rectangle {
                                                x: uiScaleSlider.leftPadding + uiScaleSlider.visualPosition * (uiScaleSlider.availableWidth - width)
                                                y: uiScaleSlider.topPadding + uiScaleSlider.availableHeight / 2 - height / 2
                                                implicitWidth: 12
                                                implicitHeight: 12
                                                radius: 3
                                                color: uiScaleSlider.pressed ? bar.accent : bar.text
                                                border.width: 1
                                                border.color: bar.accent
                                            }
                                        }
                                    }
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 40
                                    radius: root.chipR
                                    color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
                                    border.width: 1
                                    border.color: bar.dividerStrong
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 10
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            spacing: 0
                                            Text {
                                                text: "Config menu icon on bar"
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: "Gear pill opens this control strip"
                                                color: bar.overlay
                                                font.pixelSize: 10
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }
                                        Item {
                                            Layout.preferredWidth: root.optControlColW
                                            Layout.maximumWidth: root.optControlColW
                                            Layout.minimumWidth: root.optControlColW
                                            Layout.fillHeight: true
                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: root.optToggleW
                                                height: root.optToggleH
                                                radius: 4
                                                border.width: 1
                                                border.color: (bar.showControlBarPill) ? root.onGreen : root.offRed
                                                color: "transparent"
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: (bar.showControlBarPill) ? "✓" : "✕"
                                                    color: (bar.showControlBarPill) ? root.onGreen : root.offRed
                                                    font.pixelSize: 14
                                                    font.bold: true
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.setOptToggle("setShowControlBarPill", !bar.showControlBarPill)
                                                }
                                            }
                                        }
                                    }
                                }
                                Text {
                                    text: "Workspaces"
                                    color: bar.text
                                    font.pixelSize: 12
                                    font.bold: true
                                    font.family: bar.fontFamily
                                }
                                Text {
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    text: "Saved to bar layout"
                                    color: bar.overlay
                                    font.pixelSize: 10
                                    font.family: bar.fontFamily
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 36
                                    radius: root.chipR
                                    color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
                                    border.width: 1
                                    border.color: bar.dividerStrong
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 10
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            spacing: 0
                                            Text {
                                                text: "Magic workspace pill"
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }
                                        Item {
                                            Layout.preferredWidth: root.optControlColW
                                            Layout.maximumWidth: root.optControlColW
                                            Layout.minimumWidth: root.optControlColW
                                            Layout.fillHeight: true
                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: root.optToggleW
                                                height: root.optToggleH
                                                radius: 4
                                                border.width: 1
                                                border.color: (bar.showMagicWorkspacePill) ? root.onGreen : root.offRed
                                                color: "transparent"
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: (bar.showMagicWorkspacePill) ? "✓" : "✕"
                                                    color: (bar.showMagicWorkspacePill) ? root.onGreen : root.offRed
                                                    font.pixelSize: 14
                                                    font.bold: true
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.setOptToggle("setShowMagicWorkspacePill", !bar.showMagicWorkspacePill)
                                                }
                                            }
                                        }
                                    }
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 40
                                    radius: root.chipR
                                    color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
                                    border.width: 1
                                    border.color: bar.dividerStrong
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 10
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            spacing: 0
                                            Text {
                                                text: "Show only active workspace"
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: "Hide empty numbered pills"
                                                color: bar.overlay
                                                font.pixelSize: 10
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }
                                        Item {
                                            Layout.preferredWidth: root.optControlColW
                                            Layout.maximumWidth: root.optControlColW
                                            Layout.minimumWidth: root.optControlColW
                                            Layout.fillHeight: true
                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: root.optToggleW
                                                height: root.optToggleH
                                                radius: 4
                                                border.width: 1
                                                border.color: (bar.wsShowOnlyActive) ? root.onGreen : root.offRed
                                                color: "transparent"
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: (bar.wsShowOnlyActive) ? "✓" : "✕"
                                                    color: (bar.wsShowOnlyActive) ? root.onGreen : root.offRed
                                                    font.pixelSize: 14
                                                    font.bold: true
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.setOptToggle("setWsShowOnlyActive", !bar.wsShowOnlyActive)
                                                }
                                            }
                                        }
                                    }
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 40
                                    radius: root.chipR
                                    color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
                                    border.width: 1
                                    border.color: bar.dividerStrong
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 10
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            spacing: 0
                                            Text {
                                                text: "Minimum workspace pills"
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: "Show 1…N when not “only active”"
                                                color: bar.overlay
                                                font.pixelSize: 10
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }
                                        Item {
                                            Layout.preferredWidth: root.optControlColW
                                            Layout.maximumWidth: root.optControlColW
                                            Layout.minimumWidth: root.optControlColW
                                            Layout.fillHeight: true
                                            TextField {
                                                id: wsMinField
                                                anchors.centerIn: parent
                                                width: root.optFieldW
                                                height: root.optToggleH
                                                horizontalAlignment: Text.AlignHCenter
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontMono !== undefined ? bar.fontMono : bar.fontFamily
                                                text: String(bar.wsMinimumShown)
                                                validator: IntValidator { bottom: 0; top: 10 }
                                                background: Rectangle {
                                                    radius: 4
                                                    color: bar.pillBg
                                                    border.width: 1
                                                    border.color: wsMinField.activeFocus ? bar.accent : bar.pillBorder
                                                }
                                                onAccepted: root.setOptNumber("setWsMinimumShown", parseInt(text, 10))
                                                onEditingFinished: root.setOptNumber("setWsMinimumShown", parseInt(text, 10))
                                            }
                                        }
                                    }
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 40
                                    radius: root.chipR
                                    color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
                                    border.width: 1
                                    border.color: bar.dividerStrong
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 10
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            spacing: 0
                                            Text {
                                                text: "Startup workspace"
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: "0 = leave focus alone (safe on qs reload)"
                                                color: bar.overlay
                                                font.pixelSize: 10
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }
                                        Item {
                                            Layout.preferredWidth: root.optControlColW
                                            Layout.maximumWidth: root.optControlColW
                                            Layout.minimumWidth: root.optControlColW
                                            Layout.fillHeight: true
                                            TextField {
                                                id: wsStartField
                                                anchors.centerIn: parent
                                                width: root.optFieldW
                                                height: root.optToggleH
                                                horizontalAlignment: Text.AlignHCenter
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontMono !== undefined ? bar.fontMono : bar.fontFamily
                                                text: String(bar.wsStartupWorkspace)
                                                validator: IntValidator { bottom: 0; top: 10 }
                                                background: Rectangle {
                                                    radius: 4
                                                    color: bar.pillBg
                                                    border.width: 1
                                                    border.color: wsStartField.activeFocus ? bar.accent : bar.pillBorder
                                                }
                                                onAccepted: root.setOptNumber("setWsStartupWorkspace", parseInt(text, 10))
                                                onEditingFinished: root.setOptNumber("setWsStartupWorkspace", parseInt(text, 10))
                                            }
                                        }
                                    }
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 40
                                    radius: root.chipR
                                    color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
                                    border.width: 1
                                    border.color: bar.dividerStrong
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 10
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            spacing: 0
                                            Text {
                                                text: "Close magic on startup"
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: "Only if startup workspace > 0"
                                                color: bar.overlay
                                                font.pixelSize: 10
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }
                                        Item {
                                            Layout.preferredWidth: root.optControlColW
                                            Layout.maximumWidth: root.optControlColW
                                            Layout.minimumWidth: root.optControlColW
                                            Layout.fillHeight: true
                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: root.optToggleW
                                                height: root.optToggleH
                                                radius: 4
                                                border.width: 1
                                                border.color: (bar.wsStartupCloseMagic) ? root.onGreen : root.offRed
                                                color: "transparent"
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: (bar.wsStartupCloseMagic) ? "✓" : "✕"
                                                    color: (bar.wsStartupCloseMagic) ? root.onGreen : root.offRed
                                                    font.pixelSize: 14
                                                    font.bold: true
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.setOptToggle("setWsStartupCloseMagic", !bar.wsStartupCloseMagic)
                                                }
                                            }
                                        }
                                    }
                                }
                                Text {
                                    text: "Audio"
                                    color: bar.text
                                    font.pixelSize: 12
                                    font.bold: true
                                    font.family: bar.fontFamily
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 40
                                    radius: root.chipR
                                    color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
                                    border.width: 1
                                    border.color: bar.dividerStrong
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 10
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            spacing: 0
                                            Text {
                                                text: "Echo cancel (AEC)"
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: "Sticky PipeWire preference"
                                                color: bar.overlay
                                                font.pixelSize: 10
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }
                                        Item {
                                            Layout.preferredWidth: root.optControlColW
                                            Layout.maximumWidth: root.optControlColW
                                            Layout.minimumWidth: root.optControlColW
                                            Layout.fillHeight: true
                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: root.optToggleW
                                                height: root.optToggleH
                                                radius: 4
                                                border.width: 1
                                                border.color: (root.optEchoCancel()) ? root.onGreen : root.offRed
                                                color: "transparent"
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: (root.optEchoCancel()) ? "✓" : "✕"
                                                    color: (root.optEchoCancel()) ? root.onGreen : root.offRed
                                                    font.pixelSize: 14
                                                    font.bold: true
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.setOptToggle("setEchoCancel", !root.optEchoCancel())
                                                }
                                            }
                                        }
                                    }
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 40
                                    radius: root.chipR
                                    color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
                                    border.width: 1
                                    border.color: bar.dividerStrong
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 10
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            spacing: 0
                                            Text {
                                                text: "Show echo cancel in audio menu"
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: "Hide the Echo cancel section in the audio popup"
                                                color: bar.overlay
                                                font.pixelSize: 10
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }
                                        Item {
                                            Layout.preferredWidth: root.optControlColW
                                            Layout.maximumWidth: root.optControlColW
                                            Layout.minimumWidth: root.optControlColW
                                            Layout.fillHeight: true
                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: root.optToggleW
                                                height: root.optToggleH
                                                radius: 4
                                                border.width: 1
                                                border.color: (bar.showEchoCancelInMenu) ? root.onGreen : root.offRed
                                                color: "transparent"
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: (bar.showEchoCancelInMenu) ? "✓" : "✕"
                                                    color: (bar.showEchoCancelInMenu) ? root.onGreen : root.offRed
                                                    font.pixelSize: 14
                                                    font.bold: true
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.setOptToggle("setShowEchoCancelInMenu", !bar.showEchoCancelInMenu)
                                                }
                                            }
                                        }
                                    }
                                }
                                Text {
                                    text: "Network"
                                    color: bar.text
                                    font.pixelSize: 12
                                    font.bold: true
                                    font.family: bar.fontFamily
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 40
                                    radius: root.chipR
                                    color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
                                    border.width: 1
                                    border.color: bar.dividerStrong
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 10
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            spacing: 0
                                            Text {
                                                text: "nm-applet login autostart"
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: "Sticky · survives reboot"
                                                color: bar.overlay
                                                font.pixelSize: 10
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }
                                        Item {
                                            Layout.preferredWidth: root.optControlColW
                                            Layout.maximumWidth: root.optControlColW
                                            Layout.minimumWidth: root.optControlColW
                                            Layout.fillHeight: true
                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: root.optToggleW
                                                height: root.optToggleH
                                                radius: 4
                                                border.width: 1
                                                border.color: (root.optNetApplet()) ? root.onGreen : root.offRed
                                                color: "transparent"
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: (root.optNetApplet()) ? "✓" : "✕"
                                                    color: (root.optNetApplet()) ? root.onGreen : root.offRed
                                                    font.pixelSize: 14
                                                    font.bold: true
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.setOptToggle("setNetworkAppletAutostart", !root.optNetApplet())
                                                }
                                            }
                                        }
                                    }
                                }
                                Text {
                                    text: "Bluetooth"
                                    color: bar.text
                                    font.pixelSize: 12
                                    font.bold: true
                                    font.family: bar.fontFamily
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 40
                                    radius: root.chipR
                                    color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
                                    border.width: 1
                                    border.color: bar.dividerStrong
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 10
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            spacing: 0
                                            Text {
                                                text: "Blueman tray login autostart"
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: "Sticky · survives reboot"
                                                color: bar.overlay
                                                font.pixelSize: 10
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }
                                        Item {
                                            Layout.preferredWidth: root.optControlColW
                                            Layout.maximumWidth: root.optControlColW
                                            Layout.minimumWidth: root.optControlColW
                                            Layout.fillHeight: true
                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: root.optToggleW
                                                height: root.optToggleH
                                                radius: 4
                                                border.width: 1
                                                border.color: (root.optBtApplet()) ? root.onGreen : root.offRed
                                                color: "transparent"
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: (root.optBtApplet()) ? "✓" : "✕"
                                                    color: (root.optBtApplet()) ? root.onGreen : root.offRed
                                                    font.pixelSize: 14
                                                    font.bold: true
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.setOptToggle("setBluetoothAppletAutostart", !root.optBtApplet())
                                                }
                                            }
                                        }
                                    }
                                }
                                Text {
                                    text: "System stats"
                                    color: bar.text
                                    font.pixelSize: 12
                                    font.bold: true
                                    font.family: bar.fontFamily
                                }
                                Text {
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    text: "Which gauges appear on the Sys Stats pill (saved)"
                                    color: bar.overlay
                                    font.pixelSize: 10
                                    font.family: bar.fontFamily
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 36
                                    radius: root.chipR
                                    color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
                                    border.width: 1
                                    border.color: bar.dividerStrong
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 10
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            spacing: 0
                                            Text {
                                                text: "Show CPU"
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: "Gauge + metrics popup on the pill"
                                                color: bar.overlay
                                                font.pixelSize: 10
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }
                                        Item {
                                            Layout.preferredWidth: root.optControlColW
                                            Layout.maximumWidth: root.optControlColW
                                            Layout.minimumWidth: root.optControlColW
                                            Layout.fillHeight: true
                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: root.optToggleW
                                                height: root.optToggleH
                                                radius: 4
                                                border.width: 1
                                                border.color: (bar.showStatCpu) ? root.onGreen : root.offRed
                                                color: "transparent"
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: (bar.showStatCpu) ? "✓" : "✕"
                                                    color: (bar.showStatCpu) ? root.onGreen : root.offRed
                                                    font.pixelSize: 14
                                                    font.bold: true
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.setOptToggle("setShowStatCpu", !bar.showStatCpu)
                                                }
                                            }
                                        }
                                    }
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 36
                                    radius: root.chipR
                                    color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
                                    border.width: 1
                                    border.color: bar.dividerStrong
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 10
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            spacing: 0
                                            Text {
                                                text: "Show Memory"
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: "Gauge + metrics popup on the pill"
                                                color: bar.overlay
                                                font.pixelSize: 10
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }
                                        Item {
                                            Layout.preferredWidth: root.optControlColW
                                            Layout.maximumWidth: root.optControlColW
                                            Layout.minimumWidth: root.optControlColW
                                            Layout.fillHeight: true
                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: root.optToggleW
                                                height: root.optToggleH
                                                radius: 4
                                                border.width: 1
                                                border.color: (bar.showStatMem) ? root.onGreen : root.offRed
                                                color: "transparent"
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: (bar.showStatMem) ? "✓" : "✕"
                                                    color: (bar.showStatMem) ? root.onGreen : root.offRed
                                                    font.pixelSize: 14
                                                    font.bold: true
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.setOptToggle("setShowStatMem", !bar.showStatMem)
                                                }
                                            }
                                        }
                                    }
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 36
                                    radius: root.chipR
                                    color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
                                    border.width: 1
                                    border.color: bar.dividerStrong
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 10
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            spacing: 0
                                            Text {
                                                text: "Show GPU"
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: "Gauge + metrics popup on the pill"
                                                color: bar.overlay
                                                font.pixelSize: 10
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }
                                        Item {
                                            Layout.preferredWidth: root.optControlColW
                                            Layout.maximumWidth: root.optControlColW
                                            Layout.minimumWidth: root.optControlColW
                                            Layout.fillHeight: true
                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: root.optToggleW
                                                height: root.optToggleH
                                                radius: 4
                                                border.width: 1
                                                border.color: (bar.showStatGpu) ? root.onGreen : root.offRed
                                                color: "transparent"
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: (bar.showStatGpu) ? "✓" : "✕"
                                                    color: (bar.showStatGpu) ? root.onGreen : root.offRed
                                                    font.pixelSize: 14
                                                    font.bold: true
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.setOptToggle("setShowStatGpu", !bar.showStatGpu)
                                                }
                                            }
                                        }
                                    }
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 40
                                    radius: root.chipR
                                    color: Qt.rgba(0.10, 0.10, 0.12, 0.55)
                                    border.width: 1
                                    border.color: bar.dividerStrong
                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 10
                                        anchors.rightMargin: 10
                                        spacing: 10
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.minimumWidth: 0
                                            spacing: 0
                                            Text {
                                                text: "Metrics live updates"
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: "CPU / Mem / GPU popups (session)"
                                                color: bar.overlay
                                                font.pixelSize: 10
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                        }
                                        Item {
                                            Layout.preferredWidth: root.optControlColW
                                            Layout.maximumWidth: root.optControlColW
                                            Layout.minimumWidth: root.optControlColW
                                            Layout.fillHeight: true
                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: root.optToggleW
                                                height: root.optToggleH
                                                radius: 4
                                                border.width: 1
                                                border.color: (root.optMetricsLive()) ? root.onGreen : root.offRed
                                                color: "transparent"
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: (root.optMetricsLive()) ? "✓" : "✕"
                                                    color: (root.optMetricsLive()) ? root.onGreen : root.offRed
                                                    font.pixelSize: 14
                                                    font.bold: true
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.setOptToggle("setMetricsLiveUpdates", !root.optMetricsLive())
                                                }
                                            }
                                        }
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

                // ── Toolbar along the bottom (panel expands above) ──
                Rectangle {
                    visible: root.activeMenu.length > 0
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: bar.dividerStrong
                }
                RowLayout {
                    id: controlRow
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 8

                    Repeater {
                        model: [
                            { id: "position",  label: "Position" },
                            { id: "wallpaper", label: "Wallpaper" },
                            { id: "widgets",   label: "Widgets" },
                            { id: "options",   label: "Options" },
                            { id: "launch",    label: "Launch" },
                            { id: "autostart", label: "Autostart" },
                            { id: "clock",     label: "Clock" }
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
                                    if (modelData.id === "wallpaper")
                                        root.refreshWallpapers()
                                    if (modelData.id === "launch")
                                        root.refreshDesktopApps()
                                    if (modelData.id === "autostart") {
                                        root.refreshAutostart()
                                        root.refreshDesktopApps()
                                    }
                                    if (modelData.id === "options")
                                        root.refreshOptions()
                                    root.toggleMenu(modelData.id)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

