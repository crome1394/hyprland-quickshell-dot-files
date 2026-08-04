// =============================================================================
// BarControlBar.qml — Temporary mini-bar opened from empty main-bar chrome
// =============================================================================
//
// Right-click blank area of the main bar (wired in shell.qml) toggles this
// strip. Horizontally centered; stacks just inward from the main bar.
//
// Single PopupWindow (grabFocus). Expandable panel on top; toolbar buttons
// along the bottom: Position · Display · Wallpaper · Widgets · Options ·
// Launch · Autostart · Services · Audio · Keybinds · Clock
// Widgets = layout; Options = behavior prefs; Services = systemd;
// Audio = devices/ports/AEC (AudioMonitorView); Keybinds = chord/category/desc.
// Display = monitor resolution / refresh / bit depth (Apply to switch).
// Window height follows content; tall menus scroll only when needed.
//
// =============================================================================

import Quickshell
import Quickshell.Io as Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../components"

Item {
    id: root

    required property var bar

    width: 0
    height: 0

    property double _closedAtMs: 0
    readonly property int _reopenGuardMs: 220
    readonly property bool open: controlPopup.visible

    // "" | "position" | "display" | "wallpaper" | "widgets" | "options" |
    // "launch" | "autostart" | "services" | "audio" | "keybinds" | "clock"
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
    // Slightly lifted fill so TextFields read as editable (not flat chrome)
    readonly property color optFieldBg: Qt.rgba(0.18, 0.19, 0.23, 0.92)
    readonly property color optFieldBgFocus: Qt.rgba(0.22, 0.24, 0.30, 0.95)

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

    // Display panel (monitor resolution / refresh / bit depth)
    property bool displayLoading: false
    property bool displayApplying: false
    property string displayStatus: ""
    property string displayError: ""
    property var displayInfo: ({})
    property var displayResolutions: []     // full catalog from hyprctl
    property var displayFilteredList: []    // cached: res that support displaySelectedRate
    property int displayResIndex: 0         // index into displayFilteredList
    property real displaySelectedRate: 0    // selected refresh (Hz)
    property int displayBitdepth: 10
    property bool displayRateMenuOpen: false
    property bool displayBitdepthMenuOpen: false
    property bool displaySliderPressed: false
    property int displayTick: 0             // UI selection / catalog changes
    property int displayGpuTick: 0          // soft GPU/status poll only (cheap)
    // true while a full list+status load is in flight (not GPU-only poll)
    property bool displayFullFetch: false

    // Autostart panel (XDG ~/.config/autostart)
    property var autostartEntries: []
    property bool autostartLoading: false
    property string autostartStatus: ""
    property string autostartSearch: ""

    // Services panel (reuse components/ServicesView.qml)
    property string servicesFilter: ""

    // Audio panel (reuse components/AudioMonitorView.qml)
    property string audioFilter: ""

    // Keybinds panel (components/KeybindsView.qml)
    property string keybindsFilter: ""

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
               || m === "autostart" || m === "launch" || m === "display"
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
        root.refreshFreshRssSecrets()
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
        case "setShowAudioSummary":
            if (typeof bar.setShowAudioSummary === "function")
                bar.setShowAudioSummary(on)
            break
        case "setShowAudioDefaults":
            if (typeof bar.setShowAudioDefaults === "function")
                bar.setShowAudioDefaults(on)
            break
        case "setShowAudioLevelMeters":
            if (typeof bar.setShowAudioLevelMeters === "function")
                bar.setShowAudioLevelMeters(on)
            break
        case "setAudioSummaryExpanded":
            if (typeof bar.setAudioSummaryExpanded === "function")
                bar.setAudioSummaryExpanded(on)
            break
        case "setAudioDefaultsExpanded":
            if (typeof bar.setAudioDefaultsExpanded === "function")
                bar.setAudioDefaultsExpanded(on)
            break
        case "setFreshRssFiltersExpanded":
            if (typeof bar.setFreshRssFiltersExpanded === "function")
                bar.setFreshRssFiltersExpanded(on)
            break
        }
        Qt.callLater(root.refreshOptions)
    }

    // FreshRSS Options (server credentials — external env file)
    property string frScheme: "https"
    property string frHost: ""
    property string frUser: ""
    property string frPassword: ""
    property bool frHasPassword: false
    property string frStatus: ""
    property bool frLoading: false

    function refreshFreshRssSecrets() {
        const script = bar.freshRssSecretsReadScript || ""
        if (!script.length) {
            root.frStatus = "read script missing"
            return
        }
        if (frSecretsReadProcess.running)
            return
        root.frLoading = true
        frSecretsReadProcess.exec([script])
    }

    function frBuildCredArgs(script) {
        const host = (root.frHost || "").trim()
        if (!host.length)
            return null
        let scheme = (root.frScheme || "https").toLowerCase()
        if (scheme !== "http")
            scheme = "https"
        const args = [script, "--scheme", scheme, "--host", host, "--user", (root.frUser || "admin").trim()]
        if (root.frPassword.length)
            args.push("--password", root.frPassword)
        return args
    }

    function saveFreshRssSecrets() {
        const script = bar.freshRssSecretsWriteScript || ""
        if (!script.length) {
            root.frStatus = "write script missing"
            return
        }
        if (frSecretsWriteProcess.running)
            return
        const args = root.frBuildCredArgs(script)
        if (!args) {
            root.frStatus = "host required"
            return
        }
        root.frStatus = "Saving…"
        root.frLoading = true
        frSecretsWriteProcess.exec(args)
    }

    function testFreshRssConnection() {
        const script = bar.freshRssConnectionTestScript || ""
        if (!script.length) {
            root.frStatus = "test script missing"
            return
        }
        if (frConnectionTestProcess.running)
            return
        const args = root.frBuildCredArgs(script)
        if (!args) {
            root.frStatus = "host required"
            return
        }
        root.frStatus = "Testing…"
        root.frLoading = true
        frConnectionTestProcess.exec(args)
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
        // Alphabetical by label for easier scanning (↑↓ still changes bar layout order)
        out.sort(function (a, b) {
            const la = String(a.label || a.id).toLowerCase()
            const lb = String(b.label || b.id).toLowerCase()
            if (la < lb)
                return -1
            if (la > lb)
                return 1
            return 0
        })
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

    // ── Display (monitor modes via scripts/monitor-mode.sh) ──────────────
    function monitorModeScriptPath() {
        // Resolve relative to this widget so worktrees and ~/.config/quickshell both work.
        try {
            const local = Qt.resolvedUrl("../scripts/monitor-mode.sh").toString().replace("file://", "")
            if (local && local.length)
                return local
        } catch (e) {}
        if (bar.monitorModeScript && String(bar.monitorModeScript).length)
            return String(bar.monitorModeScript)
        return "/home/crome/.config/quickshell/scripts/monitor-mode.sh"
    }

    // Exact match (for applied-vs-pending and EDID labels)
    function displayRateNear(a, b) {
        return Math.abs(Number(a) - Number(b)) < 0.05
    }

    // Family match — EDID reports 239.76 / 239.90 / 239.97 as different values;
    // a 0.05Hz epsilon left only *one* res at "240Hz", which disabled the slider.
    function displayRateBucket(r) {
        const n = Number(r) || 0
        if (n <= 0)
            return 0
        if (n >= 200)
            return 240
        if (n >= 140)
            return 144
        if (n >= 100)
            return 120
        if (n >= 70)
            return 75
        if (n >= 55)
            return 60
        return Math.round(n)
    }

    function displayRateSameFamily(a, b) {
        const ba = root.displayRateBucket(a)
        const bb = root.displayRateBucket(b)
        return ba > 0 && ba === bb
    }

    function displayEntryHasRate(e, rate) {
        if (!e || !e.rates || !(rate > 0))
            return false
        for (let i = 0; i < e.rates.length; i++) {
            if (root.displayRateSameFamily(e.rates[i], rate))
                return true
        }
        return false
    }

    // Rebuild cached filtered list once when catalog or selected rate changes.
    function displayRebuildFilter() {
        const all = root.displayResolutions || []
        const rate = Number(root.displaySelectedRate) || 0
        let out = all
        if (all.length && rate > 0) {
            const filtered = []
            for (let i = 0; i < all.length; i++) {
                if (root.displayEntryHasRate(all[i], rate))
                    filtered.push(all[i])
            }
            if (filtered.length)
                out = filtered
        }
        root.displayFilteredList = out
        if (root.displayResIndex >= out.length)
            root.displayResIndex = Math.max(0, out.length - 1)
        return out
    }

    function displayResEntry() {
        void root.displayTick
        const list = root.displayFilteredList || []
        if (!list.length)
            return null
        const i = Math.max(0, Math.min(root.displayResIndex, list.length - 1))
        return list[i] || null
    }

    // Exact rates for the selected resolution only (from hyprctl).
    function displayPendingRates() {
        void root.displayTick
        const e = root.displayResEntry()
        if (!e || !e.rates)
            return []
        return e.rates
    }

    function displayPendingRes() {
        void root.displayTick
        const e = root.displayResEntry()
        return e && e.res ? String(e.res) : ""
    }

    function displayPendingRate() {
        void root.displayTick
        const r = Number(root.displaySelectedRate) || 0
        if (r > 0)
            return r
        const rates = root.displayPendingRates()
        return rates.length ? Number(rates[0]) : 0
    }

    // Prefer exact EDID mode for this entry in the same rate family as `rate`.
    function displayModeForEntryRate(e, rate) {
        if (!e)
            return ""
        if (e.modes && e.rates) {
            let bestIdx = -1
            let bestDiff = 1e9
            for (let i = 0; i < e.rates.length; i++) {
                if (!root.displayRateSameFamily(e.rates[i], rate))
                    continue
                const d = Math.abs(Number(e.rates[i]) - Number(rate))
                if (d < bestDiff) {
                    bestDiff = d
                    bestIdx = i
                }
            }
            if (bestIdx >= 0 && e.modes[bestIdx])
                return String(e.modes[bestIdx])
            // Fallback: any mode on this entry
            if (e.modes[0])
                return String(e.modes[0])
        }
        if (e.res && rate > 0)
            return String(e.res) + "@" + rate
        return ""
    }

    function displayPendingMode() {
        void root.displayTick
        return root.displayModeForEntryRate(root.displayResEntry(), root.displayPendingRate())
    }

    function displayFormatRate(r) {
        const all = root.displayResolutions || []
        for (let i = 0; i < all.length; i++) {
            const e = all[i]
            if (!e || !e.rateLabels || !e.rates)
                continue
            for (let j = 0; j < e.rates.length; j++) {
                if (root.displayRateNear(e.rates[j], r) && e.rateLabels[j])
                    return String(e.rateLabels[j])
            }
        }
        const n = Number(r)
        if (!(n > 0))
            return "—"
        if (Math.abs(n - Math.round(n)) < 0.005)
            return String(Math.round(n))
        return n.toFixed(2)
    }

    function displayCloseMenus() {
        root.displayRateMenuOpen = false
        root.displayBitdepthMenuOpen = false
    }

    function openNvidiaPanel() {
        Quickshell.execDetached(["nvidia-settings"])
    }

    function displayNotifyUi() {
        // Selection-only refresh — do NOT bump menuTick (avoids layout thrash / slider cancel)
        root.displayTick++
    }

    function displayCurrentLabel() {
        void root.displayTick
        void root.displayGpuTick
        void root.displayInfo
        const info = root.displayInfo || {}
        const w = info.width || 0
        const h = info.height || 0
        const rate = info.refreshRate || 0
        const bd = info.bitdepth || 0
        if (!(w > 0 && h > 0))
            return root.displayLoading ? "Loading…" : "No monitor data"
        return w + "×" + h + " @ " + root.displayFormatRate(rate) + " Hz · " + bd + "-bit"
    }

    function displayIdentityLabel() {
        void root.displayTick
        void root.displayInfo
        const info = root.displayInfo || {}
        const parts = []
        if (info.make)
            parts.push(String(info.make))
        if (info.model)
            parts.push(String(info.model))
        if (info.serial)
            parts.push(String(info.serial))
        return parts.length ? parts.join(" · ") : (info.description || "—")
    }

    function displayConnectorLabel() {
        void root.displayTick
        void root.displayInfo
        const info = root.displayInfo || {}
        const name = info.name || ""
        const fmt = info.format || ""
        const scale = info.scale !== undefined ? Number(info.scale) : 0
        const parts = []
        if (name)
            parts.push(String(name))
        if (fmt)
            parts.push(String(fmt))
        if (scale > 0)
            parts.push("scale " + scale.toFixed(2))
        if (info.vrr)
            parts.push("VRR on")
        return parts.join(" · ")
    }

    function displayMetaLabel() {
        void root.displayTick
        void root.displayInfo
        const info = root.displayInfo || {}
        const parts = []
        const pw = Number(info.physicalWidth) || 0
        const ph = Number(info.physicalHeight) || 0
        if (pw > 0 && ph > 0) {
            const inch = Math.sqrt(pw * pw + ph * ph) / 25.4
            parts.push(pw + "×" + ph + " mm · ~" + inch.toFixed(1) + "\"")
        }
        if (info.x !== undefined && info.y !== undefined)
            parts.push("pos " + info.x + "," + info.y)
        if (info.colorManagementPreset)
            parts.push(String(info.colorManagementPreset))
        if (info.dpmsStatus === false)
            parts.push("DPMS off")
        return parts.join(" · ")
    }

    function displayAdapterLabel() {
        void root.displayGpuTick
        void root.displayInfo
        const info = root.displayInfo || {}
        const a = info.adapter || {}
        const g = info.gpu || {}
        const gpuName = (g && g.name) ? String(g.name)
                        : (a && a.pciName) ? String(a.pciName) : ""
        const driver = (g && g.driver) ? ("driver " + g.driver)
                       : (a && a.driver) ? ("drm " + a.driver) : ""
        const conn = (a && a.connector) ? String(a.connector) : ""
        const pci = (a && a.pci) ? String(a.pci) : ((g && g.pciBus) ? String(g.pciBus) : "")
        const parts = []
        if (gpuName)
            parts.push(gpuName)
        if (driver)
            parts.push(driver)
        if (conn)
            parts.push(conn)
        if (pci)
            parts.push(pci)
        return parts.length ? parts.join(" · ") : "Adapter unknown"
    }

    function displayGpuStatsLine1() {
        void root.displayGpuTick
        void root.displayInfo
        const g = (root.displayInfo && root.displayInfo.gpu) ? root.displayInfo.gpu : null
        if (!g || !g.available)
            return "GPU stats unavailable (nvidia-smi)"
        const util = (g.utilGpu !== undefined) ? Math.round(Number(g.utilGpu)) : 0
        const temp = (g.tempC !== undefined) ? Math.round(Number(g.tempC)) : 0
        const pstate = g.pstate || "—"
        const power = (g.powerW !== undefined) ? Number(g.powerW).toFixed(0) : "—"
        const plim = (g.powerLimitW !== undefined) ? Number(g.powerLimitW).toFixed(0) : "—"
        return "GPU " + util + "% · " + temp + "°C · " + pstate
               + " · " + power + "/" + plim + " W"
    }

    function displayGpuStatsLine2() {
        void root.displayGpuTick
        void root.displayInfo
        const g = (root.displayInfo && root.displayInfo.gpu) ? root.displayInfo.gpu : null
        if (!g || !g.available)
            return ""
        const used = (g.memUsedMiB !== undefined) ? Math.round(Number(g.memUsedMiB)) : 0
        const total = (g.memTotalMiB !== undefined) ? Math.round(Number(g.memTotalMiB)) : 0
        const memUtil = (g.utilMem !== undefined) ? Math.round(Number(g.utilMem)) : 0
        const gfx = (g.clockGfxMHz !== undefined) ? Math.round(Number(g.clockGfxMHz)) : 0
        const memClk = (g.clockMemMHz !== undefined) ? Math.round(Number(g.clockMemMHz)) : 0
        const usedGi = (used / 1024).toFixed(1)
        const totalGi = (total / 1024).toFixed(1)
        return "VRAM " + usedGi + "/" + totalGi + " GiB (" + memUtil + "%)"
               + " · " + gfx + " / " + memClk + " MHz"
    }

    function displayGpuMemFrac() {
        void root.displayGpuTick
        void root.displayInfo
        const g = (root.displayInfo && root.displayInfo.gpu) ? root.displayInfo.gpu : null
        if (!g || !g.available)
            return 0
        const used = Number(g.memUsedMiB) || 0
        const total = Number(g.memTotalMiB) || 0
        if (total <= 0)
            return 0
        return Math.max(0, Math.min(1, used / total))
    }

    function displayGpuUtilFrac() {
        void root.displayGpuTick
        void root.displayInfo
        const g = (root.displayInfo && root.displayInfo.gpu) ? root.displayInfo.gpu : null
        if (!g || !g.available)
            return 0
        return Math.max(0, Math.min(1, (Number(g.utilGpu) || 0) / 100))
    }

    function displayHasPendingChange() {
        void root.displayTick
        const info = root.displayInfo || {}
        const pendRes = root.displayPendingRes()
        const pendRate = root.displayPendingRate()
        const pendBd = root.displayBitdepth
        if (!pendRes.length || !(pendRate > 0))
            return false
        const curRes = (info.width && info.height) ? (info.width + "x" + info.height) : ""
        const curRate = Number(info.refreshRate) || 0
        const curBd = Number(info.bitdepth) || 0
        const rateMatch = root.displayRateNear(curRate, pendRate)
        return pendRes !== curRes || !rateMatch || pendBd !== curBd
    }

    function displayFindResIndex(list, res) {
        if (!list || !res)
            return 0
        for (let i = 0; i < list.length; i++) {
            if (list[i] && list[i].res === res)
                return i
        }
        return 0
    }

    // Closest catalog rate on entry in the same family as preferred (else highest).
    function displayPickRateOnEntry(e, preferred) {
        if (!e || !e.rates || !e.rates.length)
            return 0
        if (preferred > 0) {
            let best = -1
            let bestDiff = 1e9
            for (let i = 0; i < e.rates.length; i++) {
                if (!root.displayRateSameFamily(e.rates[i], preferred))
                    continue
                const d = Math.abs(Number(e.rates[i]) - Number(preferred))
                if (d < bestDiff) {
                    bestDiff = d
                    best = i
                }
            }
            if (best >= 0)
                return Number(e.rates[best])
        }
        return Number(e.rates[0]) || 0
    }

    function displaySyncPendingFromInfo() {
        const info = root.displayInfo || {}
        const all = root.displayResolutions || []
        if (!all.length)
            return
        const curRes = (info.width && info.height) ? (String(info.width) + "x" + String(info.height)) : ""
        const curRate = Number(info.refreshRate) || 0
        const curBd = Number(info.bitdepth) || 10

        let matchedRate = curRate
        for (let i = 0; i < all.length; i++) {
            if (all[i] && all[i].res === curRes && all[i].rates) {
                matchedRate = root.displayPickRateOnEntry(all[i], curRate)
                break
            }
        }
        root.displaySelectedRate = matchedRate
        root.displayBitdepth = (curBd === 8) ? 8 : 10
        root.displayRebuildFilter()
        root.displayResIndex = root.displayFindResIndex(root.displayFilteredList, curRes)
        root.displayCloseMenus()
        root.displayNotifyUi()
    }

    // Slider step within rate-family-filtered list. Snap selected rate to this
    // entry's exact EDID value in the same family (no refilter — list stays stable).
    function displayOnResIndexChanged(newIndex) {
        const list = root.displayFilteredList || []
        if (!list.length)
            return
        const i = Math.max(0, Math.min(Math.round(newIndex), list.length - 1))
        const e = list[i]
        if (!e)
            return
        if (i === root.displayResIndex) {
            // Still snap rate if needed (exact EDID for Apply)
            const snapped = root.displayPickRateOnEntry(e, root.displaySelectedRate)
            if (snapped > 0 && !root.displayRateNear(snapped, root.displaySelectedRate)) {
                root.displaySelectedRate = snapped
                root.displayNotifyUi()
            }
            return
        }
        root.displayResIndex = i
        // Keep family; use this panel's exact Hz so Apply gets a real mode string
        const snapped = root.displayPickRateOnEntry(e, root.displaySelectedRate)
        if (snapped > 0)
            root.displaySelectedRate = snapped
        root.displayNotifyUi()
    }

    // Rate chosen: refilter resolutions to the same Hz *family* (e.g. all ~240).
    function displaySelectRate(rate) {
        const r = Number(rate) || 0
        if (!(r > 0))
            return
        if (root.displayRateNear(r, root.displaySelectedRate)) {
            root.displayCloseMenus()
            return
        }
        const prevRes = root.displayPendingRes()
        root.displaySelectedRate = r
        root.displayRebuildFilter()
        root.displayResIndex = root.displayFindResIndex(root.displayFilteredList, prevRes)
        // Snap to exact rate on the chosen res in this family
        const e = root.displayResEntry()
        if (e) {
            const snapped = root.displayPickRateOnEntry(e, r)
            if (snapped > 0)
                root.displaySelectedRate = snapped
        }
        root.displayCloseMenus()
        root.displayNotifyUi()
    }

    function displaySelectBitdepth(bd) {
        const v = (Number(bd) === 8) ? 8 : 10
        if (v === root.displayBitdepth) {
            root.displayCloseMenus()
            return
        }
        root.displayBitdepth = v
        root.displayCloseMenus()
        root.displayNotifyUi()
    }

    function refreshDisplay() {
        if (displayStatusProcess.running || displayListProcess.running)
            return
        root.displayFullFetch = true
        root.displayLoading = true
        root.displayError = ""
        root.displayStatus = "Loading…"
        root.displayCloseMenus()
        const script = root.monitorModeScriptPath()
        if (!script.length) {
            root.displayLoading = false
            root.displayFullFetch = false
            root.displayError = "monitor-mode script missing"
            root.displayStatus = ""
            return
        }
        displayStatusProcess.exec([script, "status-json"])
        displayListProcess.exec([script, "list-json"])
    }

    // Soft GPU/monitor status — Display panel only; never while dragging the slider
    function refreshDisplayStatusOnly() {
        if (!controlPopup.visible || root.activeMenu !== "display")
            return
        if (root.displaySliderPressed || root.displayApplying || root.displayLoading)
            return
        if (displayStatusProcess.running || displayListProcess.running)
            return
        const script = root.monitorModeScriptPath()
        if (!script.length)
            return
        root.displayFullFetch = false
        displayStatusProcess.exec([script, "status-json"])
    }

    function applyDisplayMode() {
        if (root.displayApplying || displayApplyProcess.running)
            return
        const mode = root.displayPendingMode()
        if (!mode.length) {
            root.displayError = "Select a resolution and refresh rate"
            return
        }
        const script = root.monitorModeScriptPath()
        if (!script.length) {
            root.displayError = "monitor-mode script missing"
            return
        }
        root.displayApplying = true
        root.displayError = ""
        root.displayStatus = "Applying " + mode + " · " + root.displayBitdepth + "-bit…"
        root.displayCloseMenus()
        displayApplyProcess.exec([script, "apply", mode, String(root.displayBitdepth)])
        root.displayTick++
        root.menuTick++
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

    function _displayMaybeFinishFetch() {
        if (displayStatusProcess.running || displayListProcess.running)
            return
        const full = root.displayFullFetch
        root.displayLoading = false
        if (full) {
            root.displayFullFetch = false
            if (!root.displayError.length && !root.displayApplying)
                root.displayStatus = root.displayResolutions.length
                    ? (root.displayResolutions.length + " resolution(s)")
                    : "No modes"
            if ((root.displayResolutions || []).length)
                root.displaySyncPendingFromInfo()
            root.displayGpuTick++
            root.menuTick++
            if (controlPopup.visible)
                root.scheduleReposition()
        } else {
            // Soft poll: update GPU/indicator bindings only — never touch selection or layout
            root.displayGpuTick++
        }
    }

    // Live GPU stats — ONLY while Display is open; paused during slider drag / apply / load
    Timer {
        id: displayStatsTimer
        interval: 3000
        repeat: true
        running: controlPopup.visible
                 && root.activeMenu === "display"
                 && !root.displayApplying
                 && !root.displayLoading
                 && !root.displaySliderPressed
        onTriggered: root.refreshDisplayStatusOnly()
    }

    Io.Process {
        id: displayStatusProcess
        running: false
        stdout: Io.StdioCollector {
            id: displayStatusStdout
            onStreamFinished: {
                const text = (displayStatusStdout.text || "").trim()
                if (text.startsWith("{")) {
                    try {
                        root.displayInfo = JSON.parse(text)
                    } catch (e) {
                        if (root.displayFullFetch)
                            root.displayError = "Status parse error"
                    }
                } else if (root.displayFullFetch && !root.displayError.length) {
                    root.displayError = "Failed to read monitor status"
                }
            }
        }
        onExited: (code) => {
            if (root.displayFullFetch && code !== 0 && !(displayStatusStdout.text || "").trim())
                root.displayError = "status-json failed (" + code + ")"
            // Always re-check; list process may still be running
            root._displayMaybeFinishFetch()
        }
    }

    Io.Process {
        id: displayListProcess
        running: false
        stdout: Io.StdioCollector {
            id: displayListStdout
            onStreamFinished: {
                const text = (displayListStdout.text || "").trim()
                if (text.startsWith("{")) {
                    try {
                        const j = JSON.parse(text)
                        root.displayResolutions = j.resolutions || []
                        root.displayRebuildFilter()
                    } catch (e) {
                        root.displayResolutions = []
                        root.displayFilteredList = []
                        root.displayError = "List parse error"
                    }
                } else {
                    root.displayResolutions = []
                    root.displayFilteredList = []
                    if (!root.displayError.length)
                        root.displayError = "Failed to list modes"
                }
            }
        }
        onExited: (code) => {
            if (code !== 0 && !(displayListStdout.text || "").trim()) {
                root.displayResolutions = []
                root.displayFilteredList = []
                root.displayError = "list-json failed (" + code + ")"
            }
            root._displayMaybeFinishFetch()
        }
    }

    Io.Process {
        id: displayApplyProcess
        running: false
        stdout: Io.StdioCollector {
            id: displayApplyStdout
            onStreamFinished: {
                const text = (displayApplyStdout.text || "").trim()
                if (text.startsWith("{")) {
                    try {
                        root.displayInfo = JSON.parse(text)
                        root.displayError = ""
                        root.displayStatus = "Applied · " + root.displayCurrentLabel()
                        root.displaySyncPendingFromInfo()
                        root.displayGpuTick++
                    } catch (e) {
                        root.displayError = "Apply parse error"
                    }
                }
                root.displayApplying = false
            }
        }
        onExited: (code) => {
            root.displayApplying = false
            if (code !== 0) {
                const t = (displayApplyStdout.text || "").trim()
                root.displayError = t.length
                    ? t.replace(/^error:\s*/i, "").slice(0, 160)
                    : ("Apply failed (" + code + ")")
                root.displayStatus = ""
                root.displayNotifyUi()
            } else if (root.activeMenu === "display") {
                // One catalog refresh after successful apply (not a poll loop)
                Qt.callLater(function () { root.refreshDisplay() })
            }
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

    Io.Process {
        id: frSecretsReadProcess
        running: false
        stdout: Io.StdioCollector {
            id: frSecretsReadStdout
            onStreamFinished: {
                root.frLoading = false
                const text = (frSecretsReadStdout.text || "").trim()
                if (!text.startsWith("{")) {
                    root.frStatus = "No secrets file yet"
                    return
                }
                try {
                    const j = JSON.parse(text)
                    root.frScheme = j.scheme === "http" ? "http" : "https"
                    root.frHost = j.host || ""
                    root.frUser = j.user || ""
                    root.frHasPassword = !!j.hasPassword
                    root.frPassword = ""
                    root.frStatus = j.exists
                        ? ("Loaded · " + (j.hasPassword ? "API password set" : "no API password"))
                        : "No secrets file — fill and Save"
                } catch (e) {
                    root.frStatus = "Parse error"
                }
                root.optionsTick++
            }
        }
        onExited: (code) => {
            root.frLoading = false
            if (code !== 0)
                root.frStatus = "Read failed"
        }
    }

    Io.Process {
        id: frSecretsWriteProcess
        running: false
        stdout: Io.StdioCollector {
            id: frSecretsWriteStdout
            onStreamFinished: {
                root.frLoading = false
                const text = (frSecretsWriteStdout.text || "").trim()
                if (text.startsWith("{")) {
                    try {
                        const j = JSON.parse(text)
                        root.frStatus = j.ok ? ("Saved · " + (j.baseUrl || "")) : "Save failed"
                        root.frPassword = ""
                        root.frHasPassword = !!j.hasPassword
                    } catch (e) {
                        root.frStatus = "Saved"
                        root.frPassword = ""
                    }
                } else {
                    root.frStatus = text.length ? text : "Saved"
                    root.frPassword = ""
                }
                root.refreshFreshRssSecrets()
            }
        }
        onExited: (code) => {
            root.frLoading = false
            if (code !== 0)
                root.frStatus = "Save failed"
        }
    }

    Io.Process {
        id: frConnectionTestProcess
        running: false
        stdout: Io.StdioCollector {
            id: frConnectionTestStdout
            onStreamFinished: {
                root.frLoading = false
                const text = (frConnectionTestStdout.text || "").trim()
                if (text.startsWith("{")) {
                    try {
                        const j = JSON.parse(text)
                        if (j.ok)
                            root.frStatus = j.message || ("OK · " + (j.mode || "connected"))
                        else
                            root.frStatus = j.message || ("Failed · " + (j.error || "connection failed"))
                    } catch (e) {
                        root.frStatus = "Test parse error"
                    }
                } else {
                    root.frStatus = text.length ? text : "Test failed"
                }
                root.optionsTick++
            }
        }
        onExited: (code) => {
            root.frLoading = false
            if (code !== 0 && !(frConnectionTestStdout.text || "").trim())
                root.frStatus = "Test failed"
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
            implicitWidth: Math.max(mainCol.implicitWidth + root.pad * 2,
                                    (root.activeMenu === "wallpaper"
                                     || root.activeMenu === "options"
                                     || root.activeMenu === "widgets"
                                     || root.activeMenu === "display"
                                     || root.activeMenu === "services"
                                     || root.activeMenu === "audio"
                                     || root.activeMenu === "keybinds")
                                        ? ((root.activeMenu === "services"
                                            || root.activeMenu === "audio"
                                            || root.activeMenu === "keybinds") ? 620 : 520)
                                        : 420)
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

                            // ===== DISPLAY (resolution / refresh / bit depth / GPU) =====
                            ColumnLayout {
                                visible: root.activeMenu === "display"
                                Layout.fillWidth: true
                                spacing: 12

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Text {
                                        Layout.fillWidth: true
                                        text: "Display"
                                        color: bar.text
                                        font.pixelSize: bar.popupTitleSize
                                        font.bold: true
                                        font.family: bar.fontFamily
                                    }
                                    Rectangle {
                                        // Nerd Font md-nvidia (U+F135D) — same icon font as the rest of the bar
                                        Layout.preferredHeight: 26
                                        Layout.preferredWidth: Math.max(72, nvidiaPanelRow.implicitWidth + 14)
                                        radius: root.chipR
                                        color: nvidiaPanelMa.containsMouse ? bar.glassHover : bar.pillBg
                                        border.width: 1
                                        border.color: nvidiaPanelMa.containsMouse
                                                      ? "#76b900"   // NVIDIA green accent on hover
                                                      : bar.pillBorder
                                        Row {
                                            id: nvidiaPanelRow
                                            anchors.centerIn: parent
                                            spacing: 5
                                            Text {
                                                // nf-md-nvidia
                                                text: "\uF135D"
                                                color: nvidiaPanelMa.containsMouse ? "#76b900" : bar.subtext
                                                font.pixelSize: 14
                                                font.family: bar.fontFamily
                                                verticalAlignment: Text.AlignVCenter
                                            }
                                            Text {
                                                text: "NVIDIA"
                                                color: nvidiaPanelMa.containsMouse ? "#76b900" : bar.subtext
                                                font.pixelSize: 11
                                                font.bold: true
                                                font.family: bar.fontFamily
                                                verticalAlignment: Text.AlignVCenter
                                            }
                                        }
                                        MouseArea {
                                            id: nvidiaPanelMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.openNvidiaPanel()
                                        }
                                        ToolTip.visible: nvidiaPanelMa.containsMouse
                                        ToolTip.delay: bar.tooltipDelay !== undefined ? bar.tooltipDelay : 400
                                        ToolTip.text: "Open NVIDIA Settings"
                                    }
                                    Rectangle {
                                        Layout.preferredHeight: 26
                                        Layout.preferredWidth: Math.max(56, refreshDispTxt.implicitWidth + 16)
                                        radius: root.chipR
                                        color: refreshDispMa.containsMouse ? bar.glassHover : bar.pillBg
                                        border.width: 1
                                        border.color: bar.pillBorder
                                        Text {
                                            id: refreshDispTxt
                                            anchors.centerIn: parent
                                            text: root.displayLoading ? "…" : "Refresh"
                                            color: bar.subtext
                                            font.pixelSize: 11
                                            font.family: bar.fontFamily
                                        }
                                        MouseArea {
                                            id: refreshDispMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.refreshDisplay()
                                        }
                                    }
                                }

                                // Current monitor indicator
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: dispInfoCol.implicitHeight + 16
                                    radius: root.chipR
                                    color: Qt.rgba(0.10, 0.10, 0.12, 0.65)
                                    border.width: 1
                                    border.color: bar.dividerStrong
                                    ColumnLayout {
                                        id: dispInfoCol
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 12
                                        spacing: 2
                                        Text {
                                            Layout.fillWidth: true
                                            text: root.displayCurrentLabel()
                                            color: bar.accent
                                            font.pixelSize: 13
                                            font.bold: true
                                            font.family: bar.fontMono !== undefined ? bar.fontMono : bar.fontFamily
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: root.displayIdentityLabel()
                                            color: bar.text
                                            font.pixelSize: 11
                                            font.family: bar.fontFamily
                                            elide: Text.ElideRight
                                            wrapMode: Text.WordWrap
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            visible: root.displayConnectorLabel().length > 0
                                            text: root.displayConnectorLabel()
                                            color: bar.overlay
                                            font.pixelSize: 10
                                            font.family: bar.fontMono !== undefined ? bar.fontMono : bar.fontFamily
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            visible: root.displayMetaLabel().length > 0
                                            text: root.displayMetaLabel()
                                            color: bar.overlay
                                            font.pixelSize: 10
                                            font.family: bar.fontFamily
                                            elide: Text.ElideRight
                                        }
                                    }
                                }

                                // GPU / display adapter
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: dispGpuCol.implicitHeight + 16
                                    radius: root.chipR
                                    color: Qt.rgba(0.08, 0.10, 0.12, 0.70)
                                    border.width: 1
                                    border.color: bar.dividerStrong
                                    ColumnLayout {
                                        id: dispGpuCol
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 12
                                        spacing: 4
                                        Text {
                                            Layout.fillWidth: true
                                            text: "Adapter"
                                            color: bar.subtext
                                            font.pixelSize: 10
                                            font.bold: true
                                            font.family: bar.fontFamily
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: root.displayAdapterLabel()
                                            color: bar.text
                                            font.pixelSize: 11
                                            font.family: bar.fontFamily
                                            wrapMode: Text.WordWrap
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: root.displayGpuStatsLine1()
                                            color: bar.overlay
                                            font.pixelSize: 10
                                            font.family: bar.fontMono !== undefined ? bar.fontMono : bar.fontFamily
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            visible: root.displayGpuStatsLine2().length > 0
                                            text: root.displayGpuStatsLine2()
                                            color: bar.overlay
                                            font.pixelSize: 10
                                            font.family: bar.fontMono !== undefined ? bar.fontMono : bar.fontFamily
                                            elide: Text.ElideRight
                                        }
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Layout.topMargin: 2
                                            spacing: 8
                                            visible: {
                                                void root.displayGpuTick
                                                void root.displayInfo
                                                const g = root.displayInfo && root.displayInfo.gpu
                                                return !!(g && g.available)
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 2
                                                Text {
                                                    text: "GPU"
                                                    color: bar.overlay
                                                    font.pixelSize: 9
                                                    font.family: bar.fontFamily
                                                }
                                                Rectangle {
                                                    Layout.fillWidth: true
                                                    Layout.preferredHeight: 5
                                                    radius: 2
                                                    color: Qt.rgba(1, 1, 1, 0.10)
                                                    Rectangle {
                                                        width: parent.width * root.displayGpuUtilFrac()
                                                        height: parent.height
                                                        radius: 2
                                                        color: bar.accent
                                                    }
                                                }
                                            }
                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 2
                                                Text {
                                                    text: "VRAM"
                                                    color: bar.overlay
                                                    font.pixelSize: 9
                                                    font.family: bar.fontFamily
                                                }
                                                Rectangle {
                                                    Layout.fillWidth: true
                                                    Layout.preferredHeight: 5
                                                    radius: 2
                                                    color: Qt.rgba(1, 1, 1, 0.10)
                                                    Rectangle {
                                                        width: parent.width * root.displayGpuMemFrac()
                                                        height: parent.height
                                                        radius: 2
                                                        color: root.onGreen
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                // Resolution | Refresh rate | Bit depth  (spaced, single row)
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 18

                                    // Resolution slider
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 140
                                        spacing: 6
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Text {
                                                text: "Resolution"
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontFamily
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: root.displayPendingRes().length
                                                      ? root.displayPendingRes().replace("x", "×")
                                                      : "—"
                                                color: bar.subtext
                                                font.pixelSize: 12
                                                font.family: bar.fontMono !== undefined ? bar.fontMono : bar.fontFamily
                                            }
                                        }
                                        Slider {
                                            id: displayResSlider
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 28
                                            readonly property int resCount: (root.displayFilteredList || []).length
                                            from: 0
                                            to: Math.max(0, resCount - 1)
                                            stepSize: 1
                                            snapMode: Slider.SnapAlways
                                            live: true
                                            enabled: resCount > 1 && !root.displayApplying && !root.displayLoading
                                            // External value only when not dragging — avoids binding fight
                                            Binding on value {
                                                when: !displayResSlider.pressed
                                                value: root.displayResIndex
                                            }
                                            // Integer steps only — skip redundant work between snaps
                                            property int _lastStep: -1
                                            onMoved: {
                                                const step = Math.round(value)
                                                if (step === _lastStep)
                                                    return
                                                _lastStep = step
                                                root.displayOnResIndexChanged(step)
                                            }
                                            onPressedChanged: {
                                                root.displaySliderPressed = pressed
                                                if (typeof panelFlick !== "undefined" && panelFlick) {
                                                    if (pressed) {
                                                        _lastStep = Math.round(value)
                                                        panelFlick.interactive = false
                                                    } else {
                                                        panelFlick.interactive = root.panelNeedsScroll
                                                                && (panelFlick.contentHeight > panelFlick.height + 4)
                                                        root.displayOnResIndexChanged(Math.round(value))
                                                        _lastStep = -1
                                                    }
                                                } else if (!pressed) {
                                                    root.displayOnResIndexChanged(Math.round(value))
                                                    _lastStep = -1
                                                }
                                            }
                                            background: Rectangle {
                                                x: displayResSlider.leftPadding
                                                y: displayResSlider.topPadding + displayResSlider.availableHeight / 2 - height / 2
                                                implicitWidth: 120
                                                implicitHeight: 6
                                                width: displayResSlider.availableWidth
                                                height: 6
                                                radius: 2
                                                color: Qt.rgba(1, 1, 1, 0.12)
                                                Rectangle {
                                                    width: displayResSlider.visualPosition * parent.width
                                                    height: parent.height
                                                    radius: 2
                                                    color: bar.accent
                                                }
                                            }
                                            handle: Rectangle {
                                                x: displayResSlider.leftPadding + displayResSlider.visualPosition * (displayResSlider.availableWidth - width)
                                                y: displayResSlider.topPadding + displayResSlider.availableHeight / 2 - height / 2
                                                implicitWidth: 16
                                                implicitHeight: 16
                                                radius: 3
                                                color: displayResSlider.pressed ? bar.accent : bar.text
                                                border.width: 1
                                                border.color: bar.accent
                                            }
                                        }
                                        Text {
                                            Layout.fillWidth: true
                                            text: {
                                                void root.displayTick
                                                const n = (root.displayFilteredList || []).length
                                                const all = (root.displayResolutions || []).length
                                                const fam = root.displayRateBucket(root.displaySelectedRate)
                                                if (!all)
                                                    return root.displayLoading ? "Loading…" : "No modes"
                                                if (n <= 1)
                                                    return "1 res near " + fam + " Hz (pick another Refresh)"
                                                return (root.displayResIndex + 1) + "/" + n
                                                       + " res near " + fam + " Hz"
                                            }
                                            color: bar.overlay
                                            font.pixelSize: 10
                                            font.family: bar.fontFamily
                                        }
                                    }

                                    // Refresh rate dropdown
                                    ColumnLayout {
                                        Layout.preferredWidth: 118
                                        Layout.maximumWidth: 130
                                        Layout.alignment: Qt.AlignTop
                                        spacing: 6
                                        Text {
                                            text: "Refresh"
                                            color: bar.text
                                            font.pixelSize: 12
                                            font.family: bar.fontFamily
                                        }
                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 34
                                            radius: root.chipR
                                            color: displayRateMa.containsMouse ? root.optFieldBgFocus : root.optFieldBg
                                            border.width: 1
                                            border.color: root.displayRateMenuOpen ? bar.accent : bar.pillBorder
                                            opacity: root.displayPendingRates().length ? 1 : 0.55
                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 8
                                                anchors.rightMargin: 8
                                                spacing: 4
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: {
                                                        void root.displayTick
                                                        const r = root.displayPendingRate()
                                                        return r > 0 ? (root.displayFormatRate(r) + " Hz") : "—"
                                                    }
                                                    color: bar.text
                                                    font.pixelSize: 11
                                                    font.family: bar.fontMono !== undefined ? bar.fontMono : bar.fontFamily
                                                    elide: Text.ElideRight
                                                }
                                                Text {
                                                    text: root.displayRateMenuOpen ? "▴" : "▾"
                                                    color: bar.overlay
                                                    font.pixelSize: 11
                                                }
                                            }
                                            MouseArea {
                                                id: displayRateMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                enabled: root.displayPendingRates().length > 0 && !root.displayApplying
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    root.displayBitdepthMenuOpen = false
                                                    root.displayRateMenuOpen = !root.displayRateMenuOpen
                                                }
                                            }
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 3
                                            visible: root.displayRateMenuOpen
                                            Repeater {
                                                model: root.displayPendingRates()
                                                delegate: Rectangle {
                                                    required property var modelData
                                                    required property int index
                                                    readonly property bool active: root.displayRateNear(modelData, root.displaySelectedRate)
                                                    Layout.fillWidth: true
                                                    Layout.preferredHeight: 28
                                                    radius: root.chipR
                                                    color: active
                                                           ? (bar.controlActiveBg || Qt.rgba(0, 0.77, 0.96, 0.22))
                                                           : (rateRowMa.containsMouse ? bar.glassHover : Qt.rgba(0.10, 0.10, 0.12, 0.55))
                                                    border.width: 1
                                                    border.color: active ? bar.accent : bar.dividerStrong
                                                    Text {
                                                        anchors.left: parent.left
                                                        anchors.leftMargin: 8
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        text: root.displayFormatRate(modelData) + " Hz"
                                                        color: active ? bar.accent : bar.text
                                                        font.pixelSize: 11
                                                        font.family: bar.fontFamily
                                                        font.bold: active
                                                    }
                                                    MouseArea {
                                                        id: rateRowMa
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: root.displaySelectRate(modelData)
                                                    }
                                                }
                                            }
                                        }
                                    }

                                    // Bit depth dropdown
                                    ColumnLayout {
                                        Layout.preferredWidth: 96
                                        Layout.maximumWidth: 104
                                        Layout.alignment: Qt.AlignTop
                                        spacing: 6
                                        Text {
                                            text: "Bit depth"
                                            color: bar.text
                                            font.pixelSize: 12
                                            font.family: bar.fontFamily
                                        }
                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 34
                                            radius: root.chipR
                                            color: displayBdMa.containsMouse ? root.optFieldBgFocus : root.optFieldBg
                                            border.width: 1
                                            border.color: root.displayBitdepthMenuOpen ? bar.accent : bar.pillBorder
                                            opacity: root.displayApplying ? 0.6 : 1
                                            RowLayout {
                                                anchors.fill: parent
                                                anchors.leftMargin: 8
                                                anchors.rightMargin: 8
                                                spacing: 4
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: root.displayBitdepth + "-bit"
                                                    color: bar.text
                                                    font.pixelSize: 11
                                                    font.family: bar.fontFamily
                                                }
                                                Text {
                                                    text: root.displayBitdepthMenuOpen ? "▴" : "▾"
                                                    color: bar.overlay
                                                    font.pixelSize: 11
                                                }
                                            }
                                            MouseArea {
                                                id: displayBdMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                enabled: !root.displayApplying
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: {
                                                    root.displayRateMenuOpen = false
                                                    root.displayBitdepthMenuOpen = !root.displayBitdepthMenuOpen
                                                }
                                            }
                                        }
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 3
                                            visible: root.displayBitdepthMenuOpen
                                            Repeater {
                                                model: [8, 10]
                                                delegate: Rectangle {
                                                    required property var modelData
                                                    readonly property bool active: root.displayBitdepth === modelData
                                                    Layout.fillWidth: true
                                                    Layout.preferredHeight: 28
                                                    radius: root.chipR
                                                    color: active
                                                           ? (bar.controlActiveBg || Qt.rgba(0, 0.77, 0.96, 0.22))
                                                           : (bdRowMa.containsMouse ? bar.glassHover : Qt.rgba(0.10, 0.10, 0.12, 0.55))
                                                    border.width: 1
                                                    border.color: active ? bar.accent : bar.dividerStrong
                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: modelData + "-bit"
                                                        color: active ? bar.accent : bar.text
                                                        font.pixelSize: 11
                                                        font.bold: active
                                                        font.family: bar.fontFamily
                                                    }
                                                    MouseArea {
                                                        id: bdRowMa
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: root.displaySelectBitdepth(modelData)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                // Apply + status
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 36
                                        radius: root.chipR
                                        readonly property bool canApply: root.displayHasPendingChange()
                                                                         && !root.displayApplying
                                                                         && root.displayPendingMode().length > 0
                                        color: canApply
                                               ? (applyDispMa.containsMouse
                                                  ? (bar.controlActiveBg || Qt.rgba(0, 0.77, 0.96, 0.28))
                                                  : Qt.rgba(0, 0.77, 0.96, 0.18))
                                               : Qt.rgba(0.12, 0.12, 0.14, 0.55)
                                        border.width: 1
                                        border.color: canApply ? bar.accent : bar.dividerStrong
                                        Text {
                                            anchors.centerIn: parent
                                            text: root.displayApplying
                                                  ? "Applying…"
                                                  : (parent.canApply
                                                     ? ("Apply  " + root.displayPendingMode()
                                                        + "  ·  " + root.displayBitdepth + "-bit")
                                                     : "No changes")
                                            color: parent.canApply ? bar.accent : bar.overlay
                                            font.pixelSize: 12
                                            font.bold: parent.canApply
                                            font.family: bar.fontFamily
                                            elide: Text.ElideRight
                                            width: parent.width - 16
                                            horizontalAlignment: Text.AlignHCenter
                                        }
                                        MouseArea {
                                            id: applyDispMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            enabled: parent.canApply
                                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                            onClicked: root.applyDisplayMode()
                                        }
                                    }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    visible: root.displayError.length > 0
                                    text: root.displayError
                                    color: root.offRed
                                    font.pixelSize: 11
                                    font.family: bar.fontFamily
                                    wrapMode: Text.WordWrap
                                }
                                Text {
                                    Layout.fillWidth: true
                                    visible: root.displayStatus.length > 0 && root.displayError.length === 0
                                    text: root.displayStatus
                                    color: root.onGreen
                                    font.pixelSize: 11
                                    font.family: bar.fontFamily
                                    wrapMode: Text.WordWrap
                                }
                                Text {
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    text: "Res ↔ rate linked (hyprctl). GPU stats poll every 3s only while this panel is open (paused while dragging). Apply uses scale 1.0."
                                    color: bar.overlay
                                    font.pixelSize: 10
                                    font.family: bar.fontFamily
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
                                    text: "A–Z · ✓/✕ · name · L/C/R · ↑↓ · width % (80–180)"
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

                                            // Row 1 — three columns: [✓ name] | [L C R] | [↑ ↓]
                                            RowLayout {
                                                Layout.fillWidth: true
                                                spacing: 10

                                                // Column 1: toggle + full name
                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    Layout.minimumWidth: 120
                                                    spacing: 6

                                                    Rectangle {
                                                        Layout.preferredWidth: 28
                                                        Layout.preferredHeight: 24
                                                        Layout.alignment: Qt.AlignVCenter
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
                                                        Layout.fillWidth: true
                                                        Layout.minimumWidth: 72
                                                        // Prefer full labels; elide only if panel is extremely narrow
                                                        elide: Text.ElideRight
                                                        text: widgetRow.widgetLabel
                                                        color: bar.text
                                                        font.pixelSize: 12
                                                        font.family: bar.fontFamily
                                                        verticalAlignment: Text.AlignVCenter
                                                    }
                                                }

                                                // Column 2: zone L C R (flush left of arrows)
                                                RowLayout {
                                                    Layout.preferredWidth: 74
                                                    Layout.maximumWidth: 74
                                                    Layout.minimumWidth: 74
                                                    Layout.alignment: Qt.AlignVCenter
                                                    spacing: 4

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
                                                }

                                                // Column 3: reorder ↑ ↓
                                                RowLayout {
                                                    Layout.preferredWidth: 52
                                                    Layout.maximumWidth: 52
                                                    Layout.minimumWidth: 52
                                                    Layout.alignment: Qt.AlignVCenter
                                                    spacing: 4

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
                                                        color: parent.activeFocus ? root.optFieldBgFocus : root.optFieldBg
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
                                            color: parent.activeFocus ? root.optFieldBgFocus : root.optFieldBg
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
                                        color: parent.activeFocus ? root.optFieldBgFocus : root.optFieldBg
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
                                        color: parent.activeFocus ? root.optFieldBgFocus : root.optFieldBg
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
                                        color: parent.activeFocus ? root.optFieldBgFocus : root.optFieldBg
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
                                            color: parent.activeFocus ? root.optFieldBgFocus : root.optFieldBg
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
                                                    color: parent.activeFocus ? root.optFieldBgFocus : root.optFieldBg
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
                                                    color: parent.activeFocus ? root.optFieldBgFocus : root.optFieldBg
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
                                                text: "Show echo cancel in audio menu"
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: "Show AEC section on Audio pill + control-bar Audio (on/off stays in the panel)"
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
                                // Control-bar Audio panel section visibility
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
                                                text: "Show Audio Summary"
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: "Control-bar Audio panel section"
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
                                                border.color: (bar.showAudioSummary !== false) ? root.onGreen : root.offRed
                                                color: "transparent"
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: (bar.showAudioSummary !== false) ? "✓" : "✕"
                                                    color: (bar.showAudioSummary !== false) ? root.onGreen : root.offRed
                                                    font.pixelSize: 14
                                                    font.bold: true
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.setOptToggle("setShowAudioSummary", !(bar.showAudioSummary !== false))
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
                                                text: "Show device profiles"
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: "Profile dropdowns under Output / Input devices"
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
                                                border.color: (bar.showAudioDefaults !== false) ? root.onGreen : root.offRed
                                                color: "transparent"
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: (bar.showAudioDefaults !== false) ? "✓" : "✕"
                                                    color: (bar.showAudioDefaults !== false) ? root.onGreen : root.offRed
                                                    font.pixelSize: 14
                                                    font.bold: true
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.setOptToggle("setShowAudioDefaults", !(bar.showAudioDefaults !== false))
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
                                                text: "Show Level meters"
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: "Playback / Recording VU meters below Active streams"
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
                                                border.color: (bar.showAudioLevelMeters !== false) ? root.onGreen : root.offRed
                                                color: "transparent"
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: (bar.showAudioLevelMeters !== false) ? "✓" : "✕"
                                                    color: (bar.showAudioLevelMeters !== false) ? root.onGreen : root.offRed
                                                    font.pixelSize: 14
                                                    font.bold: true
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.setOptToggle("setShowAudioLevelMeters", !(bar.showAudioLevelMeters !== false))
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
                                                text: "Keep Audio Summary expanded"
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: "When opening the control-bar Audio panel"
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
                                                border.color: (bar.audioSummaryExpanded !== false) ? root.onGreen : root.offRed
                                                color: "transparent"
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: (bar.audioSummaryExpanded !== false) ? "✓" : "✕"
                                                    color: (bar.audioSummaryExpanded !== false) ? root.onGreen : root.offRed
                                                    font.pixelSize: 14
                                                    font.bold: true
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.setOptToggle("setAudioSummaryExpanded", !(bar.audioSummaryExpanded !== false))
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
                                                text: "Keep Active streams expanded"
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: "When opening the control-bar Audio panel"
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
                                                border.color: (bar.audioDefaultsExpanded !== false) ? root.onGreen : root.offRed
                                                color: "transparent"
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: (bar.audioDefaultsExpanded !== false) ? "✓" : "✕"
                                                    color: (bar.audioDefaultsExpanded !== false) ? root.onGreen : root.offRed
                                                    font.pixelSize: 14
                                                    font.bold: true
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.setOptToggle("setAudioDefaultsExpanded", !(bar.audioDefaultsExpanded !== false))
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

                                // --- FreshRSS ---
                                Text {
                                    text: "FreshRSS"
                                    color: bar.text
                                    font.pixelSize: 12
                                    font.bold: true
                                    font.family: bar.fontFamily
                                }
                                Text {
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    text: "Server + credentials write to ~/.config/freshrss-quickshell/freshrss.env (outside git). API password = Profile → API password."
                                    color: bar.overlay
                                    font.pixelSize: 10
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
                                                text: "Filters expanded on open"
                                                color: bar.text
                                                font.pixelSize: 12
                                                font.family: bar.fontFamily
                                                elide: Text.ElideRight
                                                Layout.fillWidth: true
                                            }
                                            Text {
                                                text: "Search / max days / per feed section"
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
                                            Layout.alignment: Qt.AlignVCenter
                                            Layout.preferredHeight: root.optToggleH
                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: root.optToggleW
                                                height: root.optToggleH
                                                radius: 4
                                                border.width: 1
                                                border.color: (!!bar.freshRssFiltersExpanded) ? root.onGreen : root.offRed
                                                color: "transparent"
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: (!!bar.freshRssFiltersExpanded) ? "✓" : "✕"
                                                    color: (!!bar.freshRssFiltersExpanded) ? root.onGreen : root.offRed
                                                    font.pixelSize: 14
                                                    font.bold: true
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.setOptToggle("setFreshRssFiltersExpanded", !bar.freshRssFiltersExpanded)
                                                }
                                            }
                                        }
                                    }
                                }
                                // Scheme (+ spacer so control column lines up with toggles above)
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10
                                    Text {
                                        text: "Scheme"
                                        color: bar.subtext
                                        font.pixelSize: 12
                                        font.family: bar.fontFamily
                                        Layout.preferredWidth: 56
                                    }
                                    Repeater {
                                        model: [
                                            { id: "https", label: "HTTPS" },
                                            { id: "http", label: "HTTP" }
                                        ]
                                        delegate: Rectangle {
                                            required property var modelData
                                            Layout.preferredHeight: 28
                                            Layout.preferredWidth: frSchemeLbl.implicitWidth + 16
                                            radius: root.chipR
                                            color: root.frScheme === modelData.id
                                                   ? (bar.controlActiveBg || Qt.rgba(0, 0.77, 0.96, 0.22))
                                                   : (frSchemeMa.containsMouse ? bar.glassHover : bar.pillBg)
                                            border.width: 1
                                            border.color: root.frScheme === modelData.id ? bar.accent : bar.pillBorder
                                            Text {
                                                id: frSchemeLbl
                                                anchors.centerIn: parent
                                                text: modelData.label
                                                color: root.frScheme === modelData.id ? bar.accent : bar.subtext
                                                font.pixelSize: 11
                                                font.family: bar.fontFamily
                                            }
                                            MouseArea {
                                                id: frSchemeMa
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: root.frScheme = modelData.id
                                            }
                                        }
                                    }
                                    Item { Layout.fillWidth: true }
                                    Item {
                                        Layout.preferredWidth: root.optControlColW
                                        Layout.maximumWidth: root.optControlColW
                                        Layout.minimumWidth: root.optControlColW
                                    }
                                }
                                // Host
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10
                                    Text {
                                        text: "Host"
                                        color: bar.subtext
                                        font.pixelSize: 12
                                        Layout.preferredWidth: 56
                                    }
                                    TextField {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 30
                                        placeholderText: "freshrss.example or 10.74.10.8"
                                        color: bar.text
                                        placeholderTextColor: bar.overlay
                                        font.pixelSize: 12
                                        font.family: bar.fontFamily
                                        text: root.frHost
                                        onTextChanged: root.frHost = text
                                        background: Rectangle {
                                            radius: root.chipR
                                            color: parent.activeFocus ? root.optFieldBgFocus : root.optFieldBg
                                            border.width: 1
                                            border.color: parent.activeFocus ? bar.accent : bar.pillBorder
                                        }
                                    }
                                    Item {
                                        Layout.preferredWidth: root.optControlColW
                                        Layout.maximumWidth: root.optControlColW
                                        Layout.minimumWidth: root.optControlColW
                                    }
                                }
                                // User
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10
                                    Text {
                                        text: "User"
                                        color: bar.subtext
                                        font.pixelSize: 12
                                        Layout.preferredWidth: 56
                                    }
                                    TextField {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 30
                                        placeholderText: "admin"
                                        color: bar.text
                                        placeholderTextColor: bar.overlay
                                        font.pixelSize: 12
                                        font.family: bar.fontFamily
                                        text: root.frUser
                                        onTextChanged: root.frUser = text
                                        background: Rectangle {
                                            radius: root.chipR
                                            color: parent.activeFocus ? root.optFieldBgFocus : root.optFieldBg
                                            border.width: 1
                                            border.color: parent.activeFocus ? bar.accent : bar.pillBorder
                                        }
                                    }
                                    Item {
                                        Layout.preferredWidth: root.optControlColW
                                        Layout.maximumWidth: root.optControlColW
                                        Layout.minimumWidth: root.optControlColW
                                    }
                                }
                                // API password (write-only)
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10
                                    Text {
                                        text: "API pw"
                                        color: bar.subtext
                                        font.pixelSize: 12
                                        Layout.preferredWidth: 56
                                    }
                                    TextField {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 30
                                        echoMode: TextInput.Password
                                        placeholderText: root.frHasPassword
                                                         ? "•••• set (type to replace)"
                                                         : "Profile → API password"
                                        color: bar.text
                                        placeholderTextColor: bar.overlay
                                        font.pixelSize: 12
                                        font.family: bar.fontFamily
                                        text: root.frPassword
                                        onTextChanged: root.frPassword = text
                                        background: Rectangle {
                                            radius: root.chipR
                                            color: parent.activeFocus ? root.optFieldBgFocus : root.optFieldBg
                                            border.width: 1
                                            border.color: parent.activeFocus ? bar.accent : bar.pillBorder
                                        }
                                    }
                                    Item {
                                        Layout.preferredWidth: root.optControlColW
                                        Layout.maximumWidth: root.optControlColW
                                        Layout.minimumWidth: root.optControlColW
                                    }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Text {
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        text: root.frLoading
                                              ? "…"
                                              : (root.frStatus || "Test connection · Save writes external env")
                                        color: {
                                            const s = root.frStatus || ""
                                            if (s.indexOf("OK") === 0 || s.indexOf("Saved") === 0)
                                                return root.onGreen
                                            if (s.indexOf("Failed") === 0 || s.indexOf("failed") >= 0 || s.indexOf("error") >= 0)
                                                return root.offRed
                                            return bar.subtext
                                        }
                                        font.pixelSize: 11
                                        font.family: bar.fontFamily
                                    }
                                    Rectangle {
                                        Layout.preferredHeight: 28
                                        Layout.preferredWidth: frTestLbl.implicitWidth + 16
                                        radius: root.chipR
                                        color: frTestMa.containsMouse ? bar.glassHover : bar.pillBg
                                        border.width: 1
                                        border.color: frTestMa.containsMouse ? bar.accent : bar.pillBorder
                                        opacity: root.frLoading ? 0.6 : 1.0
                                        Text {
                                            id: frTestLbl
                                            anchors.centerIn: parent
                                            text: "Test"
                                            color: frTestMa.containsMouse ? bar.accent : bar.subtext
                                            font.pixelSize: 11
                                            font.family: bar.fontFamily
                                        }
                                        MouseArea {
                                            id: frTestMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            enabled: !root.frLoading
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.testFreshRssConnection()
                                            ToolTip.visible: containsMouse
                                            ToolTip.delay: bar.tooltipDelay
                                            ToolTip.text: "Probe server with form values (does not Save)"
                                        }
                                    }
                                    Rectangle {
                                        Layout.preferredHeight: 28
                                        Layout.preferredWidth: frSaveLbl.implicitWidth + 16
                                        radius: root.chipR
                                        color: frSaveMa.containsMouse ? bar.glassHover : bar.pillBg
                                        border.width: 1
                                        border.color: frSaveMa.containsMouse ? bar.accent : bar.pillBorder
                                        opacity: root.frLoading ? 0.6 : 1.0
                                        Text {
                                            id: frSaveLbl
                                            anchors.centerIn: parent
                                            text: "Save server"
                                            color: frSaveMa.containsMouse ? bar.accent : bar.subtext
                                            font.pixelSize: 11
                                            font.family: bar.fontFamily
                                        }
                                        MouseArea {
                                            id: frSaveMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            enabled: !root.frLoading
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.saveFreshRssSecrets()
                                            ToolTip.visible: containsMouse
                                            ToolTip.delay: bar.tooltipDelay
                                            ToolTip.text: "Write ~/.config/freshrss-quickshell/freshrss.env"
                                        }
                                    }
                                }
                            }

                            // ===== SERVICES (systemd — same engine as Inspector) =====
                            ColumnLayout {
                                id: servicesPanel
                                visible: root.activeMenu === "services"
                                Layout.fillWidth: true
                                // Fixed tall panel; ServicesView scrolls internally (no outer double-scroll)
                                Layout.preferredHeight: Math.max(320, root.panelMaxH - 12)
                                spacing: 6

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Text {
                                        Layout.fillWidth: true
                                        text: "Services"
                                        color: bar.text
                                        font.pixelSize: bar.popupTitleSize
                                        font.bold: true
                                        font.family: bar.fontFamily
                                    }
                                    Text {
                                        visible: controlServices.lastError.length > 0
                                        text: controlServices.lastError
                                        color: root.offRed
                                        font.pixelSize: 10
                                        font.family: bar.fontFamily
                                        elide: Text.ElideRight
                                        Layout.maximumWidth: 220
                                    }
                                    Text {
                                        visible: controlServices.lastAction.length > 0
                                                 && controlServices.lastError.length === 0
                                        text: controlServices.lastAction
                                        color: root.onGreen
                                        font.pixelSize: 10
                                        font.family: bar.fontFamily
                                    }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    text: "User and system units (same as Inspector Services). Select a row, then Start / Stop / Restart. System scope may prompt for polkit."
                                    color: bar.overlay
                                    font.pixelSize: bar.popupHintSize
                                    font.family: bar.fontFamily
                                }
                                TextField {
                                    id: servicesFilterField
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 30
                                    placeholderText: "Filter services…"
                                    color: bar.text
                                    placeholderTextColor: bar.overlay
                                    font.pixelSize: 12
                                    font.family: bar.fontFamily
                                    text: root.servicesFilter
                                    background: Rectangle {
                                        radius: root.chipR
                                        color: parent.activeFocus ? root.optFieldBgFocus : root.optFieldBg
                                        border.width: 1
                                        border.color: servicesFilterField.activeFocus ? bar.accent : bar.pillBorder
                                    }
                                    onTextChanged: root.servicesFilter = text
                                }
                                ServicesView {
                                    id: controlServices
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    Layout.minimumHeight: 200
                                    active: servicesPanel.visible && controlPopup.visible
                                    globalFilter: root.servicesFilter
                                    textColor: bar.text
                                    subtextColor: bar.subtext
                                    accentColor: bar.accent
                                    surfaceColor: Qt.rgba(0.08, 0.08, 0.10, 0.95)
                                    overlayColor: bar.overlay
                                    okColor: root.onGreen
                                    warnColor: "#e8c56a"
                                    errorColor: root.offRed
                                }
                            }

                            // ===== AUDIO (devices / ports / AEC — same engine as Inspector) =====
                            ColumnLayout {
                                id: audioPanel
                                visible: root.activeMenu === "audio"
                                Layout.fillWidth: true
                                // Fixed tall panel; AudioMonitorView scrolls internally
                                Layout.preferredHeight: Math.max(320, root.panelMaxH - 12)
                                spacing: 6

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Text {
                                        Layout.fillWidth: true
                                        text: "Audio"
                                        color: bar.text
                                        font.pixelSize: bar.popupTitleSize
                                        font.bold: true
                                        font.family: bar.fontFamily
                                    }
                                    Text {
                                        visible: controlAudio.lastError.length > 0
                                        text: controlAudio.lastError
                                        color: root.offRed
                                        font.pixelSize: 10
                                        font.family: bar.fontFamily
                                        elide: Text.ElideRight
                                        Layout.maximumWidth: 220
                                    }
                                    Text {
                                        visible: controlAudio.toolsStatus.length > 0
                                                 && controlAudio.lastError.length === 0
                                        text: controlAudio.toolsStatus
                                        color: root.onGreen
                                        font.pixelSize: 10
                                        font.family: bar.fontFamily
                                        elide: Text.ElideRight
                                        Layout.maximumWidth: 200
                                    }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    text: "Sinks, sources, ports, and defaults (same as Inspector Audio). Tools: Refresh, pw-top, Restart audio, echo cancel. Pill stays the quick volume control."
                                    color: bar.overlay
                                    font.pixelSize: bar.popupHintSize
                                    font.family: bar.fontFamily
                                }
                                TextField {
                                    id: audioFilterField
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 30
                                    placeholderText: "Filter devices / apps…"
                                    color: bar.text
                                    placeholderTextColor: bar.overlay
                                    font.pixelSize: 12
                                    font.family: bar.fontFamily
                                    text: root.audioFilter
                                    background: Rectangle {
                                        radius: root.chipR
                                        color: parent.activeFocus ? root.optFieldBgFocus : root.optFieldBg
                                        border.width: 1
                                        border.color: audioFilterField.activeFocus ? bar.accent : bar.pillBorder
                                    }
                                    onTextChanged: root.audioFilter = text
                                }
                                AudioMonitorView {
                                    id: controlAudio
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    Layout.minimumHeight: 200
                                    active: audioPanel.visible && controlPopup.visible
                                    showTools: true
                                    showSummary: bar.showAudioSummary !== false
                                    showDefaults: bar.showAudioDefaults !== false
                                    showLevelMeters: bar.showAudioLevelMeters !== false
                                    showEchoCancel: bar.showEchoCancelInMenu !== false
                                    summaryExpandedPref: bar.audioSummaryExpanded !== false
                                    defaultsExpandedPref: bar.audioDefaultsExpanded !== false
                                    globalFilter: root.audioFilter
                                    textColor: bar.text
                                    subtextColor: bar.subtext
                                    accentColor: bar.accent
                                    surfaceColor: Qt.rgba(0.08, 0.08, 0.10, 0.95)
                                    overlayColor: bar.overlay
                                    okColor: root.onGreen
                                    warnColor: "#e8c56a"
                                    errorColor: root.offRed
                                }
                            }

                            // ===== KEYBINDS (edit chord / category / description) =====
                            ColumnLayout {
                                id: keybindsPanel
                                visible: root.activeMenu === "keybinds"
                                Layout.fillWidth: true
                                Layout.preferredHeight: Math.max(320, root.panelMaxH - 12)
                                spacing: 6

                                Text {
                                    text: "Keybindings"
                                    color: bar.text
                                    font.pixelSize: bar.popupTitleSize
                                    font.bold: true
                                    font.family: bar.fontFamily
                                }
                                Text {
                                    Layout.fillWidth: true
                                    wrapMode: Text.WordWrap
                                    text: "From keybindings.lua (same categories as Inspector). Edit key, category, or description — not the action. Loop/dynamic binds are read-only. Save writes the file; use Reload Hypr to apply."
                                    color: bar.overlay
                                    font.pixelSize: bar.popupHintSize
                                    font.family: bar.fontFamily
                                }
                                TextField {
                                    id: keybindsFilterField
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 30
                                    placeholderText: "Filter keybindings…"
                                    color: bar.text
                                    placeholderTextColor: bar.overlay
                                    font.pixelSize: 12
                                    font.family: bar.fontFamily
                                    text: root.keybindsFilter
                                    background: Rectangle {
                                        radius: root.chipR
                                        color: parent.activeFocus ? root.optFieldBgFocus : root.optFieldBg
                                        border.width: 1
                                        border.color: keybindsFilterField.activeFocus ? bar.accent : bar.pillBorder
                                    }
                                    onTextChanged: root.keybindsFilter = text
                                }
                                KeybindsView {
                                    id: controlKeybinds
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    Layout.minimumHeight: 200
                                    active: keybindsPanel.visible && controlPopup.visible
                                    filterText: root.keybindsFilter
                                    textColor: bar.text
                                    subtextColor: bar.subtext
                                    accentColor: bar.accent
                                    surfaceColor: Qt.rgba(0.08, 0.08, 0.10, 0.95)
                                    overlayColor: bar.overlay
                                    okColor: root.onGreen
                                    warnColor: "#e8c56a"
                                    errorColor: root.offRed
                                    fieldBg: root.optFieldBg
                                    fieldBgFocus: root.optFieldBgFocus
                                    pillBorder: bar.pillBorder
                                    fontFamily: bar.fontFamily
                                    fontMono: bar.fontMono !== undefined ? bar.fontMono : bar.fontFamily
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
                            { id: "display",   label: "Display" },
                            { id: "wallpaper", label: "Wallpaper" },
                            { id: "widgets",   label: "Widgets" },
                            { id: "options",   label: "Options" },
                            { id: "launch",    label: "Launch" },
                            { id: "autostart", label: "Autostart" },
                            { id: "services",  label: "Services" },
                            { id: "audio",     label: "Audio" },
                            { id: "keybinds",  label: "Keybinds" },
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
                                    if (modelData.id === "display")
                                        root.refreshDisplay()
                                    if (modelData.id === "launch")
                                        root.refreshDesktopApps()
                                    if (modelData.id === "autostart") {
                                        root.refreshAutostart()
                                        root.refreshDesktopApps()
                                    }
                                    if (modelData.id === "options")
                                        root.refreshOptions()
                                    // ServicesView loads via active binding when panel opens
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

