// =============================================================================
// shell.qml — Main Quickshell entry point for the Hyprland status bar
// =============================================================================
//
// Widget logic lives in:
//   - widgets/*.qml      (self-contained pills and menus)
//   - components/*.qml   (reusable pieces like VolumeBar, CavaVisualizer)
//   - Config.qml      (colors, spacing, metrics, workspace behavior)
//   - widgets/HyprConfigInsp.qml (Hyprland Config Inspector overlay)
//
// IPC:
//   - qs ipc call hyprConfigInsp toggle
//   - qs ipc call freshRss toggle / refresh / show / hide
//   - qs ipc call shell setShowFreshRssPill true / toggleShowFreshRssPill
//   - qs ipc call shell setShowMediaWidget true
//   - qs ipc call shell setShowStatsWidget false
//   - qs ipc call shell toggleShowMediaWidget
//   - qs ipc call shell toggleShowStatsWidget
//   - qs ipc call shell setShowMagicWorkspacePill true
//   - qs ipc call shell toggleShowMagicWorkspacePill
//   - qs ipc call shell setShowAudioPill false   (and set/toggle for each bar pill)
//   - qs ipc call shell setShowNetworkPill true / toggleShowNetworkPill
//   - qs ipc call shell setShowBluetoothPill true / toggleShowBluetoothPill
//   - qs ipc call audioPill setEchoCancel true|false
//   - qs ipc call audioPill toggleEchoCancel / enableEchoCancel / disableEchoCancel
//   - qs ipc call networkPill showPopup / hidePopup / togglePopup
//   - qs ipc call networkPill setWifi true|false / toggleWifi / enableWifi / disableWifi
//   - qs ipc call networkPill setNetworking true|false / toggleNetworking
//   - qs ipc call networkPill startScan / stopScan / connectSsid / forgetSsid
//   - qs ipc call networkPill disconnectDevice "iface" / openEditor
//   - qs ipc call networkPill refreshIp [iface] / refreshDns [iface]
//   - qs ipc call networkPill activateConnection "uuid|name" / deactivateConnection "uuid|name"
//   - qs ipc call networkPill startApplet / stopApplet / toggleApplet   (session only)
//   - qs ipc call networkPill enableApplet / disableApplet              (survives reboot)
//   - qs ipc call networkPill setAppletAutostart true|false
//   - qs ipc call bluetoothPill showPopup / hidePopup / togglePopup
//   - qs ipc call bluetoothPill setPower true|false / togglePower / enable / disable
//   - qs ipc call bluetoothPill startScan / stopScan / toggleScan
//   - qs ipc call bluetoothPill setDiscoverable true|false / toggleDiscoverable
//   - qs ipc call bluetoothPill startApplet / stopApplet / toggleApplet   (session only)
//   - qs ipc call bluetoothPill disableApplet / enableApplet              (survives reboot)
//   - qs ipc call bluetoothPill setAppletAutostart true|false
//   - qs ipc call bluetoothPill connectDevice|disconnectDevice|pairDevice|forgetDevice "AA:BB:…"
//   - qs ipc call bluetoothPill setTrusted "AA:BB:…" true|false
//   - qs ipc call bluetoothPill setBlocked "AA:BB:…" true|false
//   - qs ipc call bluetoothPill renameDevice "AA:BB:…" "Name"
//   - qs ipc call bluetoothPill setCardProfile "AA:BB:…" "a2dp-sink"
//   - qs ipc call clockPill showCalendar
//   - qs ipc call notificationBell toggleDoNotDisturb
//   - qs ipc call sysStatsPill setMetricsLiveUpdates false
//   - qs ipc call sysStatsPill setCpuLiveUpdates false
//   - qs ipc call sysStatsPill setMemLiveUpdates false
//   - qs ipc call killTargetPill activatePickMode
//   - qs ipc call shell setShowKillTargetPill true
//   - qs ipc call sysStatsPill toggleGpuLiveUpdates
//   - qs ipc call shell setWsMinimumShown 7
//   - qs ipc call shell setWsShowOnlyActive true
//   - qs ipc call shell setWsStartupWorkspace 1
//   - qs ipc call shell setWsStartupCloseMagic false
//   (Run `qs ipc show` for the full list of shell commands.)
//
// Bar position (Config.qml):
//   - barPosition: "top" or "bottom" (Config default; runtime toggle + IPC)
//   - Right-click empty bar chrome → BarControlBar (top/bottom toggle lives there)
//   - qs ipc call shell setBarPosition top|bottom / toggleBarPosition
//   - qs ipc call shell toggleBarControlBar / showBarControlBar / hideBarControlBar
//   - UI scale: auto from screen width (Config.uiDesignWidth); override with
//     qs ipc call shell setUiScale 0.8 | setUiScaleManual 0.85 | setUiScaleAuto
//   - barEdgeMargin: gap from the screen edge
//
// =============================================================================
// BAR LAYOUT — how to move widgets (left / center / right)
// =============================================================================
//
// The bar has three sections. Each one is marked clearly below:
//
//   LEFT ZONE   →  pinned to the left side of the bar
//   CENTER ZONE →  always centered on the bar (screen middle)
//   RIGHT ZONE  →  pinned to the right side of the bar
//
// TO MOVE A WIDGET:
//   1. Find the widget block (starts with // ─ Widget Name ─).
//   2. Select from that comment line down to the closing } of the widget.
//      Include the // ── divider ── line above it if there is one.
//   3. Cut (Ctrl+X) and paste (Ctrl+V) into a different zone.
//   4. Save the file. Quickshell reloads automatically.
//
// That is all — you do not need to change anything inside the block.
// Every widget works in any zone exactly as written.
//
// Default layout (overridable at runtime via BarControlBar → Layout, persisted
// in state/bar-layout.json):
//   LEFT:   App Launcher, Quick Launch, FreshRSS, Media Player
//   CENTER: Workspaces
//   RIGHT:  System Stats, System Tray, Connectivity (Network+Bluetooth),
//           Audio, Clock, Notifications, Power
//
// Right-click empty bar chrome → BarControlBar (position, display, widgets,
// clock format, layout order/zones).
//
// Why CENTER is special: left and right zones are different widths, so a widget
// placed "between" them would look off-center. CENTER ZONE is pinned to the
// true middle of the bar automatically.
// =============================================================================

import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray
import Quickshell.Services.Mpris
import Quickshell.Io as Io
import "components"
import "widgets"

ShellRoot {
    id: root

    // --- Widget visibility (config defaults in Config.qml; IPC overrides until qs restart) ---
    property bool showLauncherPill: true
    property bool showQuickLaunchPill: true
    property bool showMediaWidget: false
    property bool showWorkspacesPill: true
    property bool showStatsWidget: true
    property bool showTrayPill: true
    property bool showNetworkPill: true
    property bool showBluetoothPill: true
    property bool showAudioPill: true
    property bool showClockPill: true
    property bool showNotificationPill: true
    property bool showPowerPill: true
    property bool showKillTargetPill: false
    property bool showFreshRssPill: true
    property bool showHyprInspPill: false
    property bool showControlBarPill: true       // Bar control / config menu icon on the bar
    property bool showMagicWorkspacePill: true   // Magic pill inside WorkspacesPill (wsShowSpecialPill)
    // Sys Stats gauges (Options panel; all on by default)
    property bool showStatCpu: true
    property bool showStatMem: true
    property bool showStatGpu: true
    // Hide Echo cancel block in Audio popup when false (Options)
    property bool showEchoCancelInMenu: true
    // FreshRSS reader: Filters section open on window start (Options + bar-layout.json)
    property bool freshRssFiltersExpanded: true

    // Clock format string (Qt.formatDateTime); Config default, persisted override.
    property string clockFormat: "dddd, MM·dd·yyyy | HH:mm:ss"

    // Runtime layout: [{ id, zone }, ...] — zone is left|center|right
    property var widgetLayout: []

    // Runtime Quick Launch pins (Config default, editable from BarControlBar, persisted)
    property var quickLaunchApps: []

    // Wallpaper directory (Config default; editable from BarControlBar, persisted)
    property string wallpaperDir: "/home/crome/Pictures/wallpapers"
    property string wallpaperCurrent: ""

    // Per-widget pill scale (1.0 = default). Keys match widgetCatalog / layout ids.
    property var widgetScales: ({})

    // Density: auto-hide deprioritized pills on narrow screens (see Config.uiDensity*).
    // User/IPC show* flags stay as preferences; density gates actual visibility.
    property bool densityHideQuickLaunch: false
    property bool densityHideStats: false
    property bool densityHideSecondary: false   // FreshRSS, media, kill-target
    property bool densityHideConnectivity: false  // Network + Bluetooth

    // Effective visibility helpers (preference AND density)
    readonly property bool effQuickLaunch: showQuickLaunchPill && !densityHideQuickLaunch
    readonly property bool effStats: showStatsWidget && !densityHideStats
    readonly property bool effFreshRss: showFreshRssPill && !densityHideSecondary
    readonly property bool effMedia: showMediaWidget && !densityHideSecondary
    readonly property bool effKillTarget: showKillTargetPill && !densityHideSecondary
    readonly property bool effNetwork: showNetworkPill && !densityHideConnectivity
    readonly property bool effBluetooth: showBluetoothPill && !densityHideConnectivity
    readonly property bool effConnectivity: effNetwork || effBluetooth

    // Catalog for BarControlBar menus (id → label + visibility property name)
    readonly property var widgetCatalog: [
        { id: "launcher",      label: "Launcher",      vis: "showLauncherPill" },
        { id: "quickLaunch",   label: "Quick Launch",  vis: "showQuickLaunchPill" },
        { id: "freshRss",      label: "FreshRSS",      vis: "showFreshRssPill" },
        { id: "media",         label: "Media",         vis: "showMediaWidget" },
        { id: "workspaces",    label: "Workspaces",    vis: "showWorkspacesPill" },
        { id: "stats",         label: "Sys Stats",     vis: "showStatsWidget" },
        { id: "tray",          label: "System Tray",   vis: "showTrayPill" },
        { id: "connectivity",  label: "Net · BT · Audio", vis: "connectivity" },
        { id: "clock",         label: "Clock",         vis: "showClockPill" },
        { id: "notifications", label: "Notifications", vis: "showNotificationPill" },
        { id: "killTarget",    label: "Kill Target",   vis: "showKillTargetPill" },
        { id: "hyprInsp",      label: "Hypr Inspector", vis: "showHyprInspPill" },
        { id: "controlBar",    label: "Config menu",   vis: "showControlBarPill" },
        { id: "power",         label: "Power",         vis: "showPowerPill" }
    ]

    // Workspace behavior (Config defaults; runtime + bar-layout.json via Options / IPC)
    property int  wsMinimumShown: 3
    property bool wsShowOnlyActive: false
    property int  wsStartupWorkspace: 0   // 0 = do not touch focus (safe for qs reload)
    property bool wsStartupCloseMagic: false

    // Optional startup focus (Config.wsStartupWorkspace > 0 only).
    // IMPORTANT: Quickshell reloads re-run this whole tree — treating reload like login
    // is what forced workspace 1. Default is 0 (no-op). When N > 0, only dispatch if
    // current focus differs; never re-focus a workspace you are already on.
    property int _startupWsAttempts: 0
    Timer {
        id: startupWorkspaceTimer
        interval: 350
        // Stay dormant when disabled; bar.Component.onCompleted can start it if needed.
        running: false
        repeat: true
        onTriggered: {
            const targetWs = root.wsStartupWorkspace
            if (targetWs <= 0) {
                stop()
                root._startupWsAttempts = 0
                return
            }

            root._startupWsAttempts += 1

            // Resolve current Hyprland focus before any dispatch.
            Hyprland.refreshMonitors()
            const focused = Hyprland.focusedWorkspace
            const focusedId = (focused && focused.id > 0) ? focused.id : 0

            let magicOpen = false
            if (bar.wsStartupCloseMagic) {
                const mon = Hyprland.focusedMonitor
                const sw = (mon && mon.lastIpcObject) ? mon.lastIpcObject.specialWorkspace : null
                const magicName = sw ? (sw.name || "") : ""
                magicOpen = magicName.length > 0 && bar.wsIsSpecialName(magicName)
                if (magicOpen) {
                    Hyprland.dispatch("hl.dsp.workspace.toggle_special('" + bar.wsSpecialName + "')")
                }
            }

            // Guard: only focus when not already there (focus(N) can still have side effects).
            if (focusedId !== targetWs) {
                Hyprland.dispatch("hl.dsp.focus({ workspace = " + targetWs + " })")
            }

            // Done when already correct (and magic closed if requested), or after retries.
            const done = (!magicOpen && focusedId === targetWs) || root._startupWsAttempts >= 4
            if (done) {
                stop()
                root._startupWsAttempts = 0
            }
        }
    }

    PanelWindow {
        id: bar
        color: "transparent"
        implicitHeight: bar.barHeight
        anchors.left: true
        anchors.right: true
        anchors.top: bar.barPosition === "top"
        anchors.bottom: bar.barPosition === "bottom"
        margins.top: bar.barPosition === "top" ? bar.barEdgeMargin : 0
        margins.bottom: bar.barPosition === "bottom" ? bar.barEdgeMargin : 0

        // --- Config (single source of truth — see Config.qml) ---
        Config { id: cfg }

        Component.onCompleted: {
            root.showLauncherPill = cfg.showLauncherPill
            root.showQuickLaunchPill = cfg.showQuickLaunchPill
            root.showMediaWidget = cfg.showMediaPill
            root.showWorkspacesPill = cfg.showWorkspacesPill
            root.showStatsWidget = cfg.showStatsPill
            root.showTrayPill = cfg.showTrayPill
            root.showNetworkPill = cfg.showNetworkPill
            root.showBluetoothPill = cfg.showBluetoothPill
            root.showAudioPill = cfg.showAudioPill
            root.showClockPill = cfg.showClockPill
            root.showNotificationPill = cfg.showNotificationPill
            root.showPowerPill = cfg.showPowerPill
            root.showKillTargetPill = cfg.showKillTargetPill
            root.showFreshRssPill = cfg.showFreshRssPill
            root.showHyprInspPill = cfg.showHyprInspPill
            root.showControlBarPill = cfg.showControlBarPill
            root.showMagicWorkspacePill = cfg.wsShowSpecialPill
            root.showStatCpu = true
            root.showStatMem = true
            root.showStatGpu = true
            root.showEchoCancelInMenu = true
            root.freshRssFiltersExpanded = cfg.freshRssFiltersExpandedDefault !== undefined
                ? !!cfg.freshRssFiltersExpandedDefault
                : true
            root.wsMinimumShown = cfg.wsMinimumShown
            root.wsShowOnlyActive = cfg.wsShowOnlyActive
            root.wsStartupWorkspace = cfg.wsStartupWorkspace
            root.wsStartupCloseMagic = cfg.wsStartupCloseMagic
            root.clockFormat = cfg.clockFormat || root.clockFormat
            root.widgetLayout = bar.cloneDefaultLayout()
            root.quickLaunchApps = bar.cloneQuickLaunchApps()
            root.wallpaperDir = cfg.wallpaperDir || root.wallpaperDir

            // Bar edge: Config default, then optional persisted override from state file.
            bar.barPosition = (cfg.barPosition === "bottom") ? "bottom" : "top"
            barLayoutFile.reload()
            bar.applyUiScale()
            Qt.callLater(function() { bar.applyWidgetLayout() })

            // Start optional startup focus only after config is applied (avoids
            // racing the property default before cfg loads). No-op when 0.
            if (root.wsStartupWorkspace > 0)
                startupWorkspaceTimer.start()
        }

        // Recompute scale when the panel is mapped / screen geometry is known.
        onWidthChanged: bar.applyUiScale()
        onScreenChanged: bar.applyUiScale()

        // ---- UI scale (auto from screen width; optional manual override) ----
        function _screenSize() {
            var w = 0
            var h = 0
            try {
                if (bar.screen) {
                    w = bar.screen.width || 0
                    h = bar.screen.height || 0
                }
            } catch (e) {}
            if (!(w > 0))
                w = bar.width || 0
            if (!(w > 0) && Quickshell.screens && Quickshell.screens.length)
                w = Quickshell.screens[0].width || 0
            if (!(h > 0) && Quickshell.screens && Quickshell.screens.length)
                h = Quickshell.screens[0].height || 0
            if (!(w > 0))
                w = cfg.uiDesignWidth
            if (!(h > 0))
                h = 1080
            return { w: w, h: h }
        }

        function applyUiScale() {
            var sz = bar._screenSize()
            cfg.screenWidth = sz.w
            cfg.screenHeight = sz.h
            var next = cfg.computeUiScale(sz.w)
            if (Math.abs(cfg.uiScale - next) > 0.001)
                cfg.uiScale = next
            bar.applyDensity()
        }

        // Hide deprioritized pills so workspaces + core right-side widgets stay visible.
        function applyDensity() {
            var d = cfg.computeDensity(cfg.screenWidth)
            root.densityHideQuickLaunch = !!d.hideQuickLaunch
            root.densityHideStats = !!d.hideStats
            root.densityHideSecondary = !!d.hideSecondary
            root.densityHideConnectivity = !!d.hideConnectivity
            cfg.densityHideQuickLaunch = root.densityHideQuickLaunch
            cfg.densityHideStats = root.densityHideStats
            cfg.densityHideSecondary = root.densityHideSecondary
            cfg.densityHideConnectivity = root.densityHideConnectivity
        }

        // Force scale (persisted). Pass 0 for auto-from-width.
        function setUiScale(scale) {
            var s = Number(scale)
            if (!(s >= 0))
                return
            if (s > 0) {
                if (s < cfg.uiScaleMin) s = cfg.uiScaleMin
                if (s > cfg.uiScaleMax) s = cfg.uiScaleMax
            }
            cfg.uiScaleManual = s
            barLayoutAdapter.uiScaleManual = s
            barLayoutFile.writeAdapter()
            bar.applyUiScale()
        }

        function setUiScaleManual(scale) {
            bar.setUiScale(scale)
        }

        function setUiScaleAuto() {
            bar.setUiScale(0)
        }

        // Persist bar layout prefs (edge, scale, widgets, clock, order/zones).
        // Guard: our own writeAdapter() must not re-enter onLoaded (that reparented
        // widgets and dismissed the control bar via focus loss).
        property bool _barLayoutWriteGuard: false

        Io.FileView {
            id: barLayoutFile
            path: "/home/crome/.config/quickshell/state/bar-layout.json"
            watchChanges: true
            onFileChanged: {
                if (bar._barLayoutWriteGuard)
                    return
                reload()
            }
            onLoaded: {
                if (bar._barLayoutWriteGuard)
                    return
                const p = barLayoutAdapter.barPosition
                if (p === "top" || p === "bottom")
                    bar.barPosition = p
                // Manual scale from state overrides Config default when present.
                if (barLayoutAdapter.uiScaleManual >= 0)
                    cfg.uiScaleManual = barLayoutAdapter.uiScaleManual
                if (barLayoutAdapter.clockFormat && barLayoutAdapter.clockFormat.length)
                    root.clockFormat = barLayoutAdapter.clockFormat
                // Visibility (only apply keys that exist in the adapter defaults)
                root.showLauncherPill = barLayoutAdapter.showLauncherPill
                root.showQuickLaunchPill = barLayoutAdapter.showQuickLaunchPill
                root.showMediaWidget = barLayoutAdapter.showMediaWidget
                root.showWorkspacesPill = barLayoutAdapter.showWorkspacesPill
                root.showStatsWidget = barLayoutAdapter.showStatsWidget
                root.showTrayPill = barLayoutAdapter.showTrayPill
                root.showNetworkPill = barLayoutAdapter.showNetworkPill
                root.showBluetoothPill = barLayoutAdapter.showBluetoothPill
                root.showAudioPill = barLayoutAdapter.showAudioPill
                root.showClockPill = barLayoutAdapter.showClockPill
                root.showNotificationPill = barLayoutAdapter.showNotificationPill
                root.showPowerPill = barLayoutAdapter.showPowerPill
                root.showKillTargetPill = barLayoutAdapter.showKillTargetPill
                root.showFreshRssPill = barLayoutAdapter.showFreshRssPill
                root.showHyprInspPill = barLayoutAdapter.showHyprInspPill
                root.showControlBarPill = barLayoutAdapter.showControlBarPill
                if (barLayoutAdapter.hasStatPrefs) {
                    root.showStatCpu = barLayoutAdapter.showStatCpu
                    root.showStatMem = barLayoutAdapter.showStatMem
                    root.showStatGpu = barLayoutAdapter.showStatGpu
                }
                if (barLayoutAdapter.hasAudioMenuPrefs)
                    root.showEchoCancelInMenu = barLayoutAdapter.showEchoCancelInMenu
                if (barLayoutAdapter.hasFreshRssPrefs)
                    root.freshRssFiltersExpanded = barLayoutAdapter.freshRssFiltersExpanded
                // Layout JSON
                if (barLayoutAdapter.widgetLayoutJson && barLayoutAdapter.widgetLayoutJson.length > 2) {
                    try {
                        const parsed = JSON.parse(barLayoutAdapter.widgetLayoutJson)
                        if (parsed && parsed.length)
                            root.widgetLayout = bar.normalizeLayout(parsed)
                    } catch (e) {}
                }
                if (barLayoutAdapter.quickLaunchAppsJson && barLayoutAdapter.quickLaunchAppsJson.length > 2) {
                    try {
                        const qa = JSON.parse(barLayoutAdapter.quickLaunchAppsJson)
                        if (qa && qa.length !== undefined)
                            root.quickLaunchApps = bar.normalizeQuickLaunchApps(qa)
                    } catch (e) {}
                }
                if (barLayoutAdapter.wallpaperDir && barLayoutAdapter.wallpaperDir.length)
                    root.wallpaperDir = barLayoutAdapter.wallpaperDir
                if (barLayoutAdapter.wallpaperCurrent && barLayoutAdapter.wallpaperCurrent.length)
                    root.wallpaperCurrent = barLayoutAdapter.wallpaperCurrent
                if (barLayoutAdapter.widgetScalesJson && barLayoutAdapter.widgetScalesJson.length > 2) {
                    try {
                        const sc = JSON.parse(barLayoutAdapter.widgetScalesJson)
                        if (sc && typeof sc === "object")
                            root.widgetScales = sc
                    } catch (e) {}
                }
                // Workspace Options (persisted; fall back to Config defaults when absent)
                if (barLayoutAdapter.hasWorkspacePrefs) {
                    root.showMagicWorkspacePill = barLayoutAdapter.showMagicWorkspacePill
                    root.wsMinimumShown = Math.max(1, Math.min(10, barLayoutAdapter.wsMinimumShown))
                    root.wsShowOnlyActive = barLayoutAdapter.wsShowOnlyActive
                    root.wsStartupWorkspace = Math.max(0, Math.min(10, barLayoutAdapter.wsStartupWorkspace))
                    root.wsStartupCloseMagic = barLayoutAdapter.wsStartupCloseMagic
                }
                bar.applyUiScale()
                Qt.callLater(function() { bar.applyWidgetLayout() })
            }
            onLoadFailed: {
                // No saved preference yet — keep Config / current value.
            }
            Io.JsonAdapter {
                id: barLayoutAdapter
                property string barPosition: "top"
                property real uiScaleManual: 0
                property string clockFormat: ""
                property string widgetLayoutJson: ""
                property string quickLaunchAppsJson: ""
                property string wallpaperDir: ""
                property string wallpaperCurrent: ""
                property string widgetScalesJson: ""
                property bool showLauncherPill: true
                property bool showQuickLaunchPill: true
                property bool showMediaWidget: false
                property bool showWorkspacesPill: true
                property bool showStatsWidget: true
                property bool showTrayPill: true
                property bool showNetworkPill: true
                property bool showBluetoothPill: true
                property bool showAudioPill: true
                property bool showClockPill: true
                property bool showNotificationPill: true
                property bool showPowerPill: true
                property bool showKillTargetPill: false
                property bool showFreshRssPill: true
                property bool showHyprInspPill: false
                property bool showControlBarPill: true
                // Workspace Options (BarControlBar → Options)
                property bool hasWorkspacePrefs: false
                property bool showMagicWorkspacePill: true
                property int  wsMinimumShown: 3
                property bool wsShowOnlyActive: false
                property int  wsStartupWorkspace: 0
                property bool wsStartupCloseMagic: false
                // Sys stats section visibility
                property bool hasStatPrefs: false
                property bool showStatCpu: true
                property bool showStatMem: true
                property bool showStatGpu: true
                // Audio popup sections
                property bool hasAudioMenuPrefs: false
                property bool showEchoCancelInMenu: true
                property bool hasFreshRssPrefs: false
                property bool freshRssFiltersExpanded: true
            }
        }

        function persistBarLayout() {
            bar._barLayoutWriteGuard = true
            barLayoutAdapter.barPosition = bar.barPosition
            barLayoutAdapter.uiScaleManual = cfg.uiScaleManual
            barLayoutAdapter.clockFormat = root.clockFormat
            try {
                barLayoutAdapter.widgetLayoutJson = JSON.stringify(root.widgetLayout || [])
            } catch (e) {
                barLayoutAdapter.widgetLayoutJson = "[]"
            }
            try {
                barLayoutAdapter.quickLaunchAppsJson = JSON.stringify(root.quickLaunchApps || [])
            } catch (e) {
                barLayoutAdapter.quickLaunchAppsJson = "[]"
            }
            barLayoutAdapter.wallpaperDir = root.wallpaperDir || ""
            barLayoutAdapter.wallpaperCurrent = root.wallpaperCurrent || ""
            try {
                barLayoutAdapter.widgetScalesJson = JSON.stringify(root.widgetScales || {})
            } catch (e) {
                barLayoutAdapter.widgetScalesJson = "{}"
            }
            barLayoutAdapter.showLauncherPill = root.showLauncherPill
            barLayoutAdapter.showQuickLaunchPill = root.showQuickLaunchPill
            barLayoutAdapter.showMediaWidget = root.showMediaWidget
            barLayoutAdapter.showWorkspacesPill = root.showWorkspacesPill
            barLayoutAdapter.showStatsWidget = root.showStatsWidget
            barLayoutAdapter.showTrayPill = root.showTrayPill
            barLayoutAdapter.showNetworkPill = root.showNetworkPill
            barLayoutAdapter.showBluetoothPill = root.showBluetoothPill
            barLayoutAdapter.showAudioPill = root.showAudioPill
            barLayoutAdapter.showClockPill = root.showClockPill
            barLayoutAdapter.showNotificationPill = root.showNotificationPill
            barLayoutAdapter.showPowerPill = root.showPowerPill
            barLayoutAdapter.showKillTargetPill = root.showKillTargetPill
            barLayoutAdapter.showFreshRssPill = root.showFreshRssPill
            barLayoutAdapter.showHyprInspPill = root.showHyprInspPill
            barLayoutAdapter.showControlBarPill = root.showControlBarPill
            barLayoutAdapter.hasWorkspacePrefs = true
            barLayoutAdapter.showMagicWorkspacePill = root.showMagicWorkspacePill
            barLayoutAdapter.wsMinimumShown = root.wsMinimumShown
            barLayoutAdapter.wsShowOnlyActive = root.wsShowOnlyActive
            barLayoutAdapter.wsStartupWorkspace = root.wsStartupWorkspace
            barLayoutAdapter.wsStartupCloseMagic = root.wsStartupCloseMagic
            barLayoutAdapter.hasStatPrefs = true
            barLayoutAdapter.showStatCpu = root.showStatCpu
            barLayoutAdapter.showStatMem = root.showStatMem
            barLayoutAdapter.showStatGpu = root.showStatGpu
            barLayoutAdapter.hasAudioMenuPrefs = true
            barLayoutAdapter.showEchoCancelInMenu = root.showEchoCancelInMenu
            barLayoutAdapter.hasFreshRssPrefs = true
            barLayoutAdapter.freshRssFiltersExpanded = root.freshRssFiltersExpanded
            barLayoutFile.writeAdapter()
            // Clear guard after filesystem watcher has had a chance to fire.
            Qt.callLater(function() {
                Qt.callLater(function() {
                    bar._barLayoutWriteGuard = false
                })
            })
        }

        // --- Options panel setters (shared with shell IPC) ---
        function setShowControlBarPill(enabled) {
            root.showControlBarPill = !!enabled
            persistBarLayout()
        }
        function setShowStatCpu(enabled) {
            root.showStatCpu = !!enabled
            persistBarLayout()
        }
        function setShowStatMem(enabled) {
            root.showStatMem = !!enabled
            persistBarLayout()
        }
        function setShowStatGpu(enabled) {
            root.showStatGpu = !!enabled
            persistBarLayout()
        }
        function setShowEchoCancelInMenu(enabled) {
            root.showEchoCancelInMenu = !!enabled
            persistBarLayout()
        }
        function setFreshRssFiltersExpanded(enabled) {
            root.freshRssFiltersExpanded = !!enabled
            persistBarLayout()
        }
        function setShowMagicWorkspacePill(enabled) {
            root.showMagicWorkspacePill = !!enabled
            persistBarLayout()
        }
        function setWsMinimumShown(count) {
            let n = Number(count)
            if (!(n >= 1))
                n = 1
            if (n > 10)
                n = 10
            root.wsMinimumShown = Math.round(n)
            persistBarLayout()
        }
        function setWsShowOnlyActive(enabled) {
            root.wsShowOnlyActive = !!enabled
            persistBarLayout()
        }
        function setWsStartupWorkspace(workspace) {
            let n = Number(workspace)
            if (!(n >= 0))
                n = 0
            if (n > 10)
                n = 10
            root.wsStartupWorkspace = Math.round(n)
            persistBarLayout()
        }
        function setWsStartupCloseMagic(enabled) {
            root.wsStartupCloseMagic = !!enabled
            persistBarLayout()
        }
        function setEchoCancel(enabled) {
            if (audioPill && audioPill.setEchoCancelEnabled)
                audioPill.setEchoCancelEnabled(!!enabled)
        }
        function getEchoCancelEnabled() {
            return !!(audioPill && audioPill.echoCancelEnabled)
        }
        function setNetworkAppletAutostart(enabled) {
            if (networkPill && networkPill.setAppletAutostart)
                networkPill.setAppletAutostart(!!enabled)
        }
        function getNetworkAppletAutostart() {
            return networkPill ? !!networkPill.appletAutostartEnabled : true
        }
        function setBluetoothAppletAutostart(enabled) {
            if (bluetoothPill && bluetoothPill.setAppletAutostart)
                bluetoothPill.setAppletAutostart(!!enabled)
        }
        function getBluetoothAppletAutostart() {
            return bluetoothPill ? !!bluetoothPill.bluemanAutostartEnabled : true
        }
        function setMetricsLiveUpdates(enabled) {
            if (sysStatsPill && sysStatsPill.setMetricsLiveUpdates)
                sysStatsPill.setMetricsLiveUpdates(!!enabled)
        }
        function getMetricsLiveUpdates() {
            if (sysStatsPill)
                return !!(sysStatsPill.cpuLiveUpdates || sysStatsPill.memLiveUpdates || sysStatsPill.gpuLiveUpdates)
            return !!cfg.popupStatsLiveUpdates
        }
        function refreshOptionsState() {
            // Nudge applets / echo-cancel to refresh status for Options panel
            try {
                if (audioPill && audioPill.refreshEchoCancelStatus)
                    audioPill.refreshEchoCancelStatus()
            } catch (e) {}
            try {
                if (networkPill && networkPill.refreshAppletStatus)
                    networkPill.refreshAppletStatus()
            } catch (e2) {}
            try {
                if (bluetoothPill && bluetoothPill.refreshBluemanStatus)
                    bluetoothPill.refreshBluemanStatus()
            } catch (e3) {}
        }

        function setBarPosition(pos) {
            const next = (pos === "bottom") ? "bottom" : "top"
            if (bar.barPosition === next)
                return
            bar.barPosition = next
            persistBarLayout()
        }

        function toggleBarPosition() {
            setBarPosition(bar.barPosition === "top" ? "bottom" : "top")
        }

        function cloneDefaultLayout() {
            const src = cfg.defaultWidgetLayout || []
            const out = []
            for (let i = 0; i < src.length; i++) {
                const e = src[i]
                if (!e || !e.id)
                    continue
                out.push({ id: String(e.id), zone: (e.zone === "center" || e.zone === "right") ? e.zone : "left" })
            }
            return out
        }

        function normalizeLayout(arr) {
            const known = {}
            const cat = root.widgetCatalog
            for (let i = 0; i < cat.length; i++)
                known[cat[i].id] = true
            const out = []
            const seen = {}
            if (arr && arr.length) {
                for (let i = 0; i < arr.length; i++) {
                    const e = arr[i]
                    if (!e || !e.id)
                        continue
                    // Migrate legacy standalone "audio" layout entry into connectivity unit
                    let id = String(e.id)
                    if (id === "audio")
                        id = "connectivity"
                    if (!known[id] || seen[id])
                        continue
                    seen[id] = true
                    out.push({
                        id: id,
                        zone: (e.zone === "center" || e.zone === "right") ? String(e.zone) : "left"
                    })
                }
            }
            // Append any missing catalog ids at end of their default zones
            const defaults = bar.cloneDefaultLayout()
            for (let i = 0; i < defaults.length; i++) {
                if (!seen[defaults[i].id])
                    out.push(defaults[i])
            }
            return out
        }

        function widgetItemById(id) {
            switch (String(id)) {
            case "launcher": return launcherPill
            case "quickLaunch": return quickLaunchPill
            case "freshRss": return freshRssPill
            case "media": return mediaPill
            case "workspaces": return workspacesPill
            case "stats": return sysStatsPill
            case "tray": return trayPill
            case "connectivity": return connectivityPill
            case "audio": return null  // audio lives inside connectivityPill
            case "clock": return clockPill
            case "notifications": return notificationBell
            case "killTarget": return killTargetPill
            case "hyprInsp": return hyprInspPill
            case "controlBar": return controlBarPill
            case "power": return powerMenu
            default: return null
            }
        }

        function applyWidgetLayout() {
            if (!leftZone || !centerZone || !rightZone || !widgetPool)
                return
            const layout = (root.widgetLayout && root.widgetLayout.length)
                ? root.widgetLayout
                : bar.cloneDefaultLayout()
            const items = []
            for (let i = 0; i < layout.length; i++) {
                const w = bar.widgetItemById(layout[i].id)
                if (w)
                    items.push(w)
            }
            // Park everything in the pool first (stable reparent order)
            for (let i = 0; i < items.length; i++)
                items[i].parent = widgetPool
            for (let i = 0; i < layout.length; i++) {
                const entry = layout[i]
                const w = bar.widgetItemById(entry.id)
                if (!w)
                    continue
                const zone = entry.zone === "center" ? centerZone
                    : (entry.zone === "right" ? rightZone : leftZone)
                w.parent = zone
            }
        }

        function setClockFormat(fmt) {
            const next = String(fmt || "").trim()
            if (!next.length)
                return
            if (root.clockFormat === next)
                return
            root.clockFormat = next
            persistBarLayout()
        }

        function getWidgetVisible(id) {
            switch (String(id)) {
            case "launcher": return root.showLauncherPill
            case "quickLaunch": return root.showQuickLaunchPill
            case "freshRss": return root.showFreshRssPill
            case "media": return root.showMediaWidget
            case "workspaces": return root.showWorkspacesPill
            case "stats": return root.showStatsWidget
            case "tray": return root.showTrayPill
            case "connectivity": return root.showNetworkPill || root.showBluetoothPill || root.showAudioPill
            case "network": return root.showNetworkPill
            case "bluetooth": return root.showBluetoothPill
            case "audio": return root.showAudioPill
            case "clock": return root.showClockPill
            case "notifications": return root.showNotificationPill
            case "killTarget": return root.showKillTargetPill
            case "hyprInsp": return root.showHyprInspPill
            case "controlBar": return root.showControlBarPill
            case "power": return root.showPowerPill
            default: return false
            }
        }

        function setWidgetVisible(id, enabled) {
            const on = !!enabled
            switch (String(id)) {
            case "launcher": root.showLauncherPill = on; break
            case "quickLaunch": root.showQuickLaunchPill = on; break
            case "freshRss": root.showFreshRssPill = on; break
            case "media": root.showMediaWidget = on; break
            case "workspaces": root.showWorkspacesPill = on; break
            case "stats": root.showStatsWidget = on; break
            case "tray": root.showTrayPill = on; break
            case "connectivity":
                root.showNetworkPill = on
                root.showBluetoothPill = on
                root.showAudioPill = on
                break
            case "network": root.showNetworkPill = on; break
            case "bluetooth": root.showBluetoothPill = on; break
            case "audio": root.showAudioPill = on; break
            case "clock": root.showClockPill = on; break
            case "notifications": root.showNotificationPill = on; break
            case "killTarget": root.showKillTargetPill = on; break
            case "hyprInsp": root.showHyprInspPill = on; break
            case "controlBar": root.showControlBarPill = on; break
            case "power": root.showPowerPill = on; break
            default: return
            }
            persistBarLayout()
        }

        function toggleWidgetVisible(id) {
            setWidgetVisible(id, !getWidgetVisible(id))
        }

        function setWidgetZone(id, zone) {
            const z = (zone === "center" || zone === "right") ? zone : "left"
            const layout = bar.normalizeLayout(root.widgetLayout)
            let found = false
            for (let i = 0; i < layout.length; i++) {
                if (layout[i].id === id) {
                    layout[i].zone = z
                    found = true
                    break
                }
            }
            if (!found)
                layout.push({ id: String(id), zone: z })
            root.widgetLayout = layout
            bar.applyWidgetLayout()
            persistBarLayout()
        }

        function moveWidget(id, delta) {
            const layout = bar.normalizeLayout(root.widgetLayout)
            let idx = -1
            for (let i = 0; i < layout.length; i++) {
                if (layout[i].id === id) {
                    idx = i
                    break
                }
            }
            if (idx < 0)
                return
            const zone = layout[idx].zone
            // Move among siblings in the same zone
            const zoneIdxs = []
            for (let i = 0; i < layout.length; i++) {
                if (layout[i].zone === zone)
                    zoneIdxs.push(i)
            }
            let posInZone = zoneIdxs.indexOf(idx)
            const newPos = posInZone + (delta < 0 ? -1 : 1)
            if (newPos < 0 || newPos >= zoneIdxs.length)
                return
            const swapWith = zoneIdxs[newPos]
            const tmp = layout[idx]
            layout[idx] = layout[swapWith]
            layout[swapWith] = tmp
            root.widgetLayout = layout
            bar.applyWidgetLayout()
            persistBarLayout()
        }

        function resetWidgetLayout() {
            root.widgetLayout = bar.cloneDefaultLayout()
            bar.applyWidgetLayout()
            persistBarLayout()
        }

        function cloneQuickLaunchApps() {
            const src = cfg.quickLaunchApps || []
            return bar.normalizeQuickLaunchApps(src)
        }

        function normalizeQuickLaunchApps(arr) {
            const out = []
            if (!arr || arr.length === undefined)
                return out
            for (let i = 0; i < arr.length; i++) {
                const e = arr[i]
                if (!e)
                    continue
                let command = e.command
                if (typeof command !== "string" && command && command.length !== undefined) {
                    const args = []
                    for (let j = 0; j < command.length; j++)
                        args.push(String(command[j]))
                    command = args
                } else if (command === undefined || command === null) {
                    command = ""
                } else {
                    command = String(command)
                }
                // Skip empty entries
                const hasCmd = (typeof command === "string")
                    ? command.length > 0
                    : (command.length > 0)
                if (!hasCmd && !(e.tooltip || e.icon || e.glyph))
                    continue
                out.push({
                    icon: e.icon ? String(e.icon) : "",
                    glyph: e.glyph ? String(e.glyph) : "",
                    command: command,
                    tooltip: e.tooltip ? String(e.tooltip) : ""
                })
            }
            return out
        }

        function setQuickLaunchApps(arr) {
            root.quickLaunchApps = bar.normalizeQuickLaunchApps(arr)
            persistBarLayout()
        }

        function addQuickLaunchApp(entry) {
            const list = bar.normalizeQuickLaunchApps(root.quickLaunchApps)
            const one = bar.normalizeQuickLaunchApps([entry])
            if (!one.length)
                return false
            list.push(one[0])
            root.quickLaunchApps = list
            persistBarLayout()
            return true
        }

        function removeQuickLaunchApp(index) {
            const list = bar.normalizeQuickLaunchApps(root.quickLaunchApps)
            const i = Number(index)
            if (!(i >= 0) || i >= list.length)
                return
            list.splice(i, 1)
            root.quickLaunchApps = list
            persistBarLayout()
        }

        function moveQuickLaunchApp(index, delta) {
            const list = bar.normalizeQuickLaunchApps(root.quickLaunchApps)
            const i = Number(index)
            const d = Number(delta) || 0
            const j = i + d
            if (!(i >= 0) || i >= list.length || j < 0 || j >= list.length)
                return
            const tmp = list[i]
            list[i] = list[j]
            list[j] = tmp
            root.quickLaunchApps = list
            persistBarLayout()
        }

        function resetQuickLaunchApps() {
            root.quickLaunchApps = bar.cloneQuickLaunchApps()
            persistBarLayout()
        }

        function setWallpaperDir(dir) {
            const d = String(dir || "").trim()
            if (!d.length)
                return
            root.wallpaperDir = d
            persistBarLayout()
        }

        function setWallpaperCurrent(path) {
            root.wallpaperCurrent = String(path || "")
            persistBarLayout()
        }

        function applyWallpaper(path) {
            const p = String(path || "").trim()
            if (!p.length)
                return
            const script = cfg.wallpaperApplyScript || ""
            const mon = cfg.wallpaperMonitor || "DP-1"
            if (!script.length)
                return
            Quickshell.execDetached([script, p, mon])
            root.wallpaperCurrent = p
            persistBarLayout()
        }

        function widgetScale(id) {
            const key = String(id || "")
            const m = root.widgetScales || {}
            let s = 1.0
            try {
                if (m[key] !== undefined && m[key] !== null)
                    s = Number(m[key])
            } catch (e) {}
            if (!(s > 0))
                s = 1.0
            // Floor at 80% — below that labels/icons start colliding even when
            // fonts/gauges scale (especially Sys Stats and Quick Launch).
            if (s < 0.8)
                s = 0.8
            if (s > 1.8)
                s = 1.8
            return s
        }

        // Height stays at the global pill height — scale is horizontal only.
        function widgetPillH(id) {
            return pillHeight
        }

        // Scale a base width (or any horizontal metric) by the widget's size factor.
        function widgetW(id, base) {
            const b = Number(base)
            if (!(b > 0))
                return 0
            return Math.max(1, Math.round(b * widgetScale(id)))
        }

        // Debounce disk writes while dragging size sliders (avoid thrashing bar-layout.json).
        Timer {
            id: scalePersistTimer
            interval: 280
            repeat: false
            onTriggered: bar.persistBarLayout()
        }

        function setWidgetScale(id, scale) {
            const key = String(id || "")
            if (!key.length)
                return
            let s = Number(scale)
            if (!(s > 0))
                return
            if (s < 0.8)
                s = 0.8
            if (s > 1.8)
                s = 1.8
            // Round to 2 decimals for stable UI / fewer no-op updates
            s = Math.round(s * 100) / 100
            const cur = root.widgetScales || {}
            const prev = (cur[key] !== undefined && cur[key] !== null) ? Number(cur[key]) : 1.0
            if (Math.abs(prev - s) < 0.001)
                return
            const next = {}
            const keys = Object.keys(cur)
            for (let i = 0; i < keys.length; i++)
                next[keys[i]] = cur[keys[i]]
            next[key] = s
            root.widgetScales = next
            // Live UI updates via property binding; persist shortly after drag settles
            scalePersistTimer.restart()
        }

        function resetWidgetScales() {
            scalePersistTimer.stop()
            root.widgetScales = ({})
            persistBarLayout()
        }

        readonly property alias notificationSubscribe: cfg.notificationSubscribe
        readonly property alias notificationSyncIntervalMs: cfg.notificationSyncIntervalMs
        readonly property alias notificationDndAccent: cfg.notificationDndAccent

        function notificationCommand(action) {
            return cfg.notificationCommand(action)
        }

        function notificationCmdArray(action) {
            const cmd = cfg.notificationCommand(action)
            if (!cmd || cmd.length === undefined || cmd.length <= 0)
                return []
            const args = []
            for (let i = 0; i < cmd.length; i++)
                args.push(cmd[i])
            return args
        }

        function execNotificationCommand(action) {
            const args = notificationCmdArray(action)
            if (args.length <= 0)
                return
            Quickshell.execDetached(args)
        }

        function notificationUsesLiveSubscribe() {
            return cfg.notificationUsesLiveSubscribe()
        }

        function notificationSupportsPanel() {
            return cfg.notificationSupportsPanel()
        }

        function notificationSupportsDnd() {
            return cfg.notificationSupportsDnd()
        }

        function notificationSupportsClearAll() {
            return cfg.notificationSupportsClearAll()
        }

        function notificationSyncEnabled() {
            return cfg.notificationSyncEnabled()
        }

        function refreshNotificationState() {
            if (notificationBell && notificationBell.refreshState)
                notificationBell.refreshState()
        }

        function powerCmdArray(action) {
            const cmd = cfg.powerCommand(action)
            if (!cmd || cmd.length === undefined || cmd.length <= 0)
                return []
            const args = []
            for (let i = 0; i < cmd.length; i++)
                args.push(cmd[i])
            return args
        }

        function execPowerCommand(action) {
            const cmd = cfg.powerCommand(action)
            if (cmd === undefined || cmd === null)
                return
            if (typeof cmd === "string") {
                if (cmd.length > 0)
                    Quickshell.execDetached(["sh", "-c", cmd])
                return
            }
            const args = powerCmdArray(action)
            if (args.length > 0)
                Quickshell.execDetached(args)
        }

        function powerMenuItems() {
            return cfg.powerMenuItems()
        }

        // --- Base palette
        property alias bg: cfg.bg
        property alias surface: cfg.surface
        property alias text: cfg.text
        property alias subtext: cfg.subtext
        property alias overlay: cfg.overlay
        property alias accent: cfg.accent
        property alias muted: cfg.muted
        property alias todayBg: cfg.todayBg
        property alias weekday: cfg.weekday
        property alias clock: cfg.clock
        readonly property alias statTempCool: cfg.statTempCool
        readonly property alias statTempWarm: cfg.statTempWarm
        readonly property alias statTempHot: cfg.statTempHot
        readonly property alias statValueSeparator: cfg.statValueSeparator

        // --- Glassmorphic tokens
        readonly property alias glassBg: cfg.glassBg
        readonly property alias glassBorder: cfg.glassBorder
        readonly property alias glassHighlight: cfg.glassHighlight
        readonly property alias glassPillBg: cfg.glassPillBg
        readonly property alias glassHover: cfg.glassHover
        readonly property alias glassPopupBg: cfg.glassPopupBg
        readonly property alias glassPopupBorder: cfg.glassPopupBorder
        readonly property alias glassPopupHighlight: cfg.glassPopupHighlight
        readonly property alias pillBg: cfg.pillBg
        readonly property alias pillBorder: cfg.pillBorder
        readonly property alias pillHover: cfg.pillHover

        // --- State colors
        readonly property alias pillHoverBorder: cfg.pillHoverBorder
        readonly property alias iconHoverBg: cfg.iconHoverBg
        readonly property alias controlHoverBg: cfg.controlHoverBg
        readonly property alias controlActiveBg: cfg.controlActiveBg
        readonly property alias popupButtonHoverBg: cfg.popupButtonHoverBg

        // --- Radii
        property alias barRadius: cfg.barRadius
        property alias pillRadius: cfg.pillRadius
        property alias popupRadius: cfg.popupRadius
        property alias popupRadiusLarge: cfg.popupRadiusLarge
        property alias buttonRadius: cfg.buttonRadius
        property alias smallButtonRadius: cfg.smallButtonRadius
        property alias sliderRadius: cfg.sliderRadius
        property alias workspaceRadius: cfg.workspaceRadius
        readonly property alias controlBorderWidth: cfg.controlBorderWidth

        // --- Spacing & padding
        property alias sideMargin: cfg.sideMargin
        readonly property alias barContentHMargin: cfg.barContentHMargin
        readonly property alias barContentVMargin: cfg.barContentVMargin
        readonly property alias pillHPadding: cfg.pillHPadding
        readonly property alias popupPadding: cfg.popupPadding
        readonly property alias popupPaddingSmall: cfg.popupPaddingSmall
        readonly property alias popupHeaderHighlightHeight: cfg.popupHeaderHighlightHeight
        readonly property alias popupTitleSize: cfg.popupTitleSize
        readonly property alias popupSectionSize: cfg.popupSectionSize
        readonly property alias popupHintSize: cfg.popupHintSize
        readonly property alias popupSpacing: cfg.popupSpacing
        readonly property alias popupSpacingTight: cfg.popupSpacingTight
        readonly property alias popupSectionSpacing: cfg.popupSectionSpacing
        readonly property alias widgetSpacing: cfg.widgetSpacing
        readonly property alias iconTextGap: cfg.iconTextGap
        readonly property alias dualAudioSidePadding: cfg.dualAudioSidePadding

        // --- Sizing & bar position (barPosition is runtime-mutable; Config is the default)
        property string barPosition: "top"
        // Clock format is owned on root (persisted); bar exposes it for ClockPill / control bar.
        property alias clockFormat: root.clockFormat
        readonly property alias clockFormatPresets: cfg.clockFormatPresets
        readonly property alias barEdgeMargin: cfg.barEdgeMargin
        readonly property alias popupBarGap: cfg.popupBarGap
        readonly property alias barHeight: cfg.barHeight
        readonly property alias barTopMargin: cfg.barTopMargin
        readonly property alias barPositionIconTop: cfg.barPositionIconTop
        readonly property alias barPositionIconBottom: cfg.barPositionIconBottom
        readonly property alias hyprResolutionBin: cfg.hyprResolutionBin
        readonly property alias uiScale: cfg.uiScale
        readonly property alias uiScaleManual: cfg.uiScaleManual
        readonly property alias uiDesignWidth: cfg.uiDesignWidth
        function sp(n) { return cfg.sp(n) }

        // Widget catalog + layout helpers for BarControlBar
        readonly property alias widgetCatalog: root.widgetCatalog
        readonly property alias widgetLayout: root.widgetLayout

        // Popup Y anchor — opens below the bar (top) or above it (bottom)
        function popupAnchorY(popupHeight, gap) {
            var spacing = (gap !== undefined) ? gap : popupBarGap
            return barPosition === "bottom" ? -popupHeight - spacing : implicitHeight + spacing
        }
        readonly property alias pillHeight: cfg.pillHeight
        readonly property alias audioViewContentWidth: cfg.audioViewContentWidth
        readonly property alias audioViewSidePadding: cfg.audioViewSidePadding
        readonly property alias audioDualBarWidth: cfg.audioDualBarWidth
        readonly property alias audioDualPercentWidth: cfg.audioDualPercentWidth
        readonly property alias iconSizePill: cfg.iconSizePill
        readonly property alias iconSizePillLarge: cfg.iconSizePillLarge
        readonly property alias iconSizePopup: cfg.iconSizePopup
        readonly property alias iconSizePower: cfg.iconSizePower
        readonly property alias iconSizeMediaArt: cfg.iconSizeMediaArt
        readonly property alias iconSizeTray: cfg.iconSizeTray
        readonly property alias quickLaunchIcon: cfg.quickLaunchIcon
        readonly property alias quickLaunchSpacing: cfg.quickLaunchSpacing
        readonly property alias quickLaunchPaddingH: cfg.quickLaunchPaddingH
        // Runtime list (editable from BarControlBar); falls back to Config via clone on start
        property alias quickLaunchApps: root.quickLaunchApps
        property alias wallpaperDir: root.wallpaperDir
        property alias wallpaperCurrent: root.wallpaperCurrent
        property alias widgetScales: root.widgetScales
        // Desktop app picker script for the Launch panel
        readonly property string desktopAppsJsonScript: "/home/crome/.config/quickshell/scripts/desktop-apps-json.sh"
        readonly property alias wallpaperListScript: cfg.wallpaperListScript
        readonly property alias wallpaperApplyScript: cfg.wallpaperApplyScript
        readonly property alias wallpaperAddScript: cfg.wallpaperAddScript
        readonly property alias wallpaperPickDirScript: cfg.wallpaperPickDirScript
        readonly property alias wallpaperMonitor: cfg.wallpaperMonitor
        readonly property alias autostartListScript: cfg.autostartListScript
        readonly property alias autostartSetScript: cfg.autostartSetScript
        readonly property alias autostartAddScript: cfg.autostartAddScript
        readonly property alias autostartRunScript: cfg.autostartRunScript

        // --- Popup sizes
        readonly property alias popupAudioWidth: cfg.popupAudioWidth
        readonly property alias popupAudioHeight: cfg.popupAudioHeight
        readonly property alias popupMediaWidth: cfg.popupMediaWidth
        readonly property alias popupMediaHeight: cfg.popupMediaHeight
        readonly property alias popupPowerWidth: cfg.popupPowerWidth
        readonly property alias popupPowerHeight: cfg.popupPowerHeight
        readonly property alias popupContextMenuWidth: cfg.popupContextMenuWidth
        readonly property alias popupContextMenuRowHeight: cfg.popupContextMenuRowHeight
        readonly property alias popupCalendarWidth: cfg.popupCalendarWidth
        readonly property alias popupCalendarHeight: cfg.popupCalendarHeight
        readonly property alias popupBluetoothWidth: cfg.popupBluetoothWidth
        readonly property alias popupBluetoothHeight: cfg.popupBluetoothHeight
        readonly property alias bluetoothScanSeconds: cfg.bluetoothScanSeconds
        readonly property alias popupNetworkWidth: cfg.popupNetworkWidth
        readonly property alias popupNetworkWifiWidth: cfg.popupNetworkWifiWidth
        readonly property alias popupNetworkHeight: cfg.popupNetworkHeight
        readonly property alias popupStatsCpuWidth: cfg.popupStatsCpuWidth
        readonly property alias popupStatsCpuHeight: cfg.popupStatsCpuHeight
        readonly property alias popupStatsGpuWidth: cfg.popupStatsGpuWidth
        readonly property alias popupStatsGpuHeight: cfg.popupStatsGpuHeight
        readonly property alias popupStatsMemWidth: cfg.popupStatsMemWidth
        readonly property alias popupStatsMemHeight: cfg.popupStatsMemHeight
        readonly property alias popupStatsCpuAnchorX: cfg.popupStatsCpuAnchorX
        readonly property alias popupStatsCpuAnchorWholePill: cfg.popupStatsCpuAnchorWholePill
        readonly property alias popupStatsCpuOffsetX: cfg.popupStatsCpuOffsetX
        readonly property alias popupStatsCpuOffsetY: cfg.popupStatsCpuOffsetY
        readonly property alias popupStatsCpuBarGap: cfg.popupStatsCpuBarGap
        readonly property alias popupStatsGpuAnchorX: cfg.popupStatsGpuAnchorX
        readonly property alias popupStatsGpuAnchorWholePill: cfg.popupStatsGpuAnchorWholePill
        readonly property alias popupStatsGpuOffsetX: cfg.popupStatsGpuOffsetX
        readonly property alias popupStatsGpuOffsetY: cfg.popupStatsGpuOffsetY
        readonly property alias popupStatsGpuBarGap: cfg.popupStatsGpuBarGap
        readonly property alias popupStatsMemAnchorX: cfg.popupStatsMemAnchorX
        readonly property alias popupStatsMemAnchorWholePill: cfg.popupStatsMemAnchorWholePill
        readonly property alias popupStatsMemOffsetX: cfg.popupStatsMemOffsetX
        readonly property alias popupStatsMemOffsetY: cfg.popupStatsMemOffsetY
        readonly property alias popupStatsMemBarGap: cfg.popupStatsMemBarGap
        readonly property alias popupStatsLiveUpdates: cfg.popupStatsLiveUpdates
        readonly property alias popupStatsPersistPause: cfg.popupStatsPersistPause
        readonly property alias popupHelpWidth: cfg.popupHelpWidth
        readonly property alias popupHelpHeight: cfg.popupHelpHeight

        // --- Fonts
        readonly property alias fontFamily: cfg.fontFamily
        readonly property alias fontMono: cfg.fontMono
        readonly property alias fontClock: cfg.fontClock
        readonly property alias fontPillLabel: cfg.fontPillLabel
        readonly property alias fontPopupTitle: cfg.fontPopupTitle
        readonly property alias fontSection: cfg.fontSection
        readonly property alias fontBody: cfg.fontBody
        readonly property alias fontSmall: cfg.fontSmall
        readonly property alias fontTiny: cfg.fontTiny

        // --- Icon glyphs
        readonly property alias iconSpeaker: cfg.iconSpeaker
        readonly property alias iconSpeakerMuted: cfg.iconSpeakerMuted
        readonly property alias iconMic: cfg.iconMic
        readonly property alias iconMicMuted: cfg.iconMicMuted
        readonly property alias iconAudioBluetooth: cfg.iconAudioBluetooth
        readonly property alias iconAudioUsb: cfg.iconAudioUsb
        readonly property alias iconAudioHdmi: cfg.iconAudioHdmi
        readonly property alias iconAudioInternal: cfg.iconAudioInternal
        readonly property alias iconAudioHeadset: cfg.iconAudioHeadset
        readonly property alias iconAudioBattery: cfg.iconAudioBattery
        readonly property alias iconBluetooth: cfg.iconBluetooth
        readonly property alias iconBluetoothOff: cfg.iconBluetoothOff
        readonly property alias iconBluetoothConnected: cfg.iconBluetoothConnected
        readonly property alias iconBluetoothScanning: cfg.iconBluetoothScanning
        readonly property alias iconNetworkWired: cfg.iconNetworkWired
        readonly property alias iconNetworkWifi: cfg.iconNetworkWifi
        readonly property alias iconNetworkWifiFair: cfg.iconNetworkWifiFair
        readonly property alias iconNetworkWifiWeak: cfg.iconNetworkWifiWeak
        readonly property alias iconNetworkWifiNone: cfg.iconNetworkWifiNone
        readonly property alias iconNetworkWifiOff: cfg.iconNetworkWifiOff
        readonly property alias iconNetworkDisconnected: cfg.iconNetworkDisconnected
        readonly property alias iconNetworkOff: cfg.iconNetworkOff
        readonly property alias iconNetworkPortal: cfg.iconNetworkPortal
        readonly property alias iconPower: cfg.iconPower
        readonly property alias killTargetIcon: cfg.killTargetIcon
        readonly property alias killTargetTooltip: cfg.killTargetTooltip
        readonly property alias killTargetOverlayDim: cfg.killTargetOverlayDim
        readonly property alias iconLock: cfg.iconLock
        readonly property alias iconLogout: cfg.iconLogout
        readonly property alias iconReboot: cfg.iconReboot
        readonly property alias iconShutdown: cfg.iconShutdown
        readonly property alias iconBios: cfg.iconBios
        readonly property alias iconLauncher: cfg.iconLauncher
        readonly property alias iconHyprInsp: cfg.iconHyprInsp
        readonly property alias iconControlBar: cfg.iconControlBar
        readonly property alias launcherCommand: cfg.launcherCommand
        readonly property alias launcherTooltip: cfg.launcherTooltip
        readonly property alias audioSpeakerIcon: cfg.audioSpeakerIcon
        readonly property alias audioMicIcon: cfg.audioMicIcon
        readonly property alias audioSpeakerIconMuted: cfg.audioSpeakerIconMuted
        readonly property alias audioMicIconMuted: cfg.audioMicIconMuted

        // --- Sliders
        readonly property alias sliderBarHeight: cfg.sliderBarHeight
        readonly property alias sliderPopupHeight: cfg.sliderPopupHeight
        readonly property alias sliderMiniHeight: cfg.sliderMiniHeight
        readonly property alias sliderFill: cfg.sliderFill
        readonly property alias sliderFillMuted: cfg.sliderFillMuted
        readonly property alias sliderTrack: cfg.sliderTrack
        readonly property alias audioUtilThreshold1: cfg.audioUtilThreshold1
        readonly property alias audioUtilThreshold2: cfg.audioUtilThreshold2
        readonly property alias audioUtilThreshold3: cfg.audioUtilThreshold3
        readonly property alias audioSpeakerTier1: cfg.audioSpeakerTier1
        readonly property alias audioSpeakerTier2: cfg.audioSpeakerTier2
        readonly property alias audioSpeakerTier3: cfg.audioSpeakerTier3
        readonly property alias audioSpeakerTier4: cfg.audioSpeakerTier4
        readonly property alias audioMicTier1: cfg.audioMicTier1
        readonly property alias audioMicTier2: cfg.audioMicTier2
        readonly property alias audioMicTier3: cfg.audioMicTier3
        readonly property alias audioMicTier4: cfg.audioMicTier4
        function audioSpeakerUtilColor(percent) { return cfg.audioSpeakerUtilColor(percent) }
        function audioMicUtilColor(percent) { return cfg.audioMicUtilColor(percent) }

        // --- Workspaces
        readonly property alias wsHoverYellow: cfg.wsHoverYellow
        readonly property alias wsActiveBg: cfg.wsActiveBg
        readonly property alias wsActiveBorder: cfg.wsActiveBorder
        readonly property alias wsActiveText: cfg.wsActiveText
        readonly property alias wsInactiveText: cfg.wsInactiveText
        readonly property alias wsButtonWidth: cfg.wsButtonWidth
        readonly property alias wsButtonHeight: cfg.wsButtonHeight
        readonly property alias wsIconSize: cfg.wsIconSize
        readonly property alias wsNumberSize: cfg.wsNumberSize
        readonly property alias wsSpacing: cfg.wsSpacing
        readonly property alias wsText: cfg.wsText
        readonly property alias wsIcon1: cfg.wsIcon1
        readonly property alias wsIcon2: cfg.wsIcon2
        readonly property alias wsIcon3: cfg.wsIcon3
        readonly property alias wsIcon4: cfg.wsIcon4
        readonly property alias wsIcon5: cfg.wsIcon5
        readonly property alias wsIcon6: cfg.wsIcon6
        readonly property alias wsIcon7: cfg.wsIcon7
        readonly property alias wsIcon8: cfg.wsIcon8
        readonly property alias wsIcon9: cfg.wsIcon9
        readonly property alias wsIcon10: cfg.wsIcon10
        readonly property alias wsIconDefault: cfg.wsIconDefault
        readonly property alias wsSpecialName: cfg.wsSpecialName
        readonly property alias wsIconSpecial: cfg.wsIconSpecial
        readonly property alias wsShowSpecialPill: cfg.wsShowSpecialPill
        // Bound to root so Options / IPC / WorkspacesPill stay in sync
        property alias wsMinimumShown: root.wsMinimumShown
        property alias wsShowOnlyActive: root.wsShowOnlyActive
        property alias wsStartupWorkspace: root.wsStartupWorkspace
        property alias wsStartupCloseMagic: root.wsStartupCloseMagic
        property alias showMagicWorkspacePill: root.showMagicWorkspacePill
        property alias showControlBarPill: root.showControlBarPill
        property alias showStatCpu: root.showStatCpu
        property alias showStatMem: root.showStatMem
        property alias showStatGpu: root.showStatGpu
        property alias showEchoCancelInMenu: root.showEchoCancelInMenu
        property alias freshRssFiltersExpanded: root.freshRssFiltersExpanded
        readonly property alias freshRssSecretsReadScript: cfg.freshRssSecretsReadScript
        readonly property alias freshRssSecretsWriteScript: cfg.freshRssSecretsWriteScript
        readonly property alias freshRssConnectionTestScript: cfg.freshRssConnectionTestScript
        function wsIconForId(id) { return cfg.wsIconForId(id) }
        function wsIsSpecialName(name) { return cfg.wsIsSpecialName(name) }

        // --- System stats gauges
        readonly property alias statGaugeWidth: cfg.statGaugeWidth
        readonly property alias statGaugeHeight: cfg.statGaugeHeight
        readonly property alias statGaugeRadius: cfg.statGaugeRadius
        readonly property alias statPillWidth: cfg.statPillWidth
        readonly property alias statPillSectionWidth: cfg.statPillSectionWidth
        readonly property alias statPillSpacing: cfg.statPillSpacing
        readonly property alias statPillPaddingH: cfg.statPillPaddingH
        readonly property alias statTrack: cfg.statTrack
        readonly property alias gaugeLow: cfg.gaugeLow
        readonly property alias gaugeMid: cfg.gaugeMid
        readonly property alias gaugeHigh: cfg.gaugeHigh
        readonly property alias statUtilTier1: cfg.statUtilTier1
        readonly property alias statUtilTier2: cfg.statUtilTier2
        readonly property alias statUtilTier3: cfg.statUtilTier3
        readonly property alias statUtilTier4: cfg.statUtilTier4
        readonly property alias statUtilThreshold1: cfg.statUtilThreshold1
        readonly property alias statUtilThreshold2: cfg.statUtilThreshold2
        readonly property alias statUtilThreshold3: cfg.statUtilThreshold3
        readonly property alias statTempWarmAt: cfg.statTempWarmAt
        readonly property alias statTempHotAt: cfg.statTempHotAt
        function statUtilColor(util) { return cfg.statUtilColor(util) }
        function statTempColor(temp) { return cfg.statTempColor(temp) }

        // --- Cava visualizer
        readonly property alias cavaBarCount: cfg.cavaBarCount
        readonly property alias cavaBarGap: cfg.cavaBarGap
        readonly property alias cavaInactive: cfg.cavaInactive
        readonly property alias cavaActive: cfg.cavaActive
        readonly property alias cavaAnimFast: cfg.cavaAnimFast
        readonly property alias cavaAnimSlow: cfg.cavaAnimSlow

        // --- Dividers
        readonly property alias divider: cfg.divider
        readonly property alias dividerStrong: cfg.dividerStrong
        readonly property alias dividerThickness: cfg.dividerThickness
        readonly property alias dividerSubtle: cfg.dividerSubtle

        // --- Animation & interaction
        readonly property alias animFast: cfg.animFast
        readonly property alias animMedium: cfg.animMedium
        readonly property alias animSlow: cfg.animSlow
        readonly property alias tooltipDelay: cfg.tooltipDelay

        // --- Tray menu
        readonly property alias menuCheckMark: cfg.menuCheckMark
        readonly property alias menuUncheckedMark: cfg.menuUncheckedMark
        readonly property alias menuCheckedRow: cfg.menuCheckedRow
        readonly property alias menuBtnNone: cfg.menuBtnNone
        readonly property alias menuBtnCheck: cfg.menuBtnCheck
        readonly property alias menuBtnRadio: cfg.menuBtnRadio

        // --- Z layers
        readonly property alias zMediaPill: cfg.zMediaPill
        readonly property alias zSysStats: cfg.zSysStats

        Rectangle {
            id: barBg
            anchors.fill: parent
            anchors.leftMargin: bar.sideMargin
            anchors.rightMargin: bar.sideMargin
            anchors.topMargin: bar.barContentVMargin
            anchors.bottomMargin: bar.barContentVMargin
            radius: bar.barRadius
            color: bar.glassBg
            border.width: Math.max(1, bar.controlBorderWidth)
            border.color: bar.glassBorder

            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: bar.popupHeaderHighlightHeight
                color: bar.glassHighlight
                radius: parent.radius
            }

            // Right-click empty bar chrome → open/close the control mini-bar
            // (top/bottom toggle; room for display controls later).
            // Lives under the widget row (z: 0) so pill MouseAreas still own left-clicks.
            MouseArea {
                id: barBgContext
                anchors.fill: parent
                z: 0
                acceptedButtons: Qt.RightButton
                hoverEnabled: false
                onClicked: (mouse) => {
                    if (mouse.button === Qt.RightButton)
                        barControlBar.toggle()
                }
            }

            // Host for the temporary control strip (PopupWindow; zero-size Item).
            BarControlBar {
                id: barControlBar
                bar: bar
            }

            // Holding pen for reparentable widgets (layout editor moves them between zones).
            // Keep visible so parked children are not force-hidden; park off-screen.
            Item {
                id: widgetPool
                width: 0
                height: 0
                x: -10000
                y: -10000
            }

            RowLayout {
                z: 1
                anchors.fill: parent
                anchors.leftMargin: bar.barContentHMargin
                anchors.rightMargin: bar.barContentHMargin
                spacing: 0

                // --- LEFT ZONE (receives reparented widgets) ---
                RowLayout {
                    id: leftZone
                    spacing: bar.widgetSpacing
                    Layout.alignment: Qt.AlignVCenter
                }

                Item { Layout.fillWidth: true }

                // --- RIGHT ZONE ---
                RowLayout {
                    id: rightZone
                    spacing: bar.widgetSpacing
                    Layout.alignment: Qt.AlignVCenter
                }
            }

            // --- CENTER ZONE (true screen center; receives reparented widgets) ---
            RowLayout {
                id: centerZone
                z: 1
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                spacing: bar.widgetSpacing
            }

            // =================================================================
            // Widget instances (reparented into left/center/right via applyWidgetLayout)
            // Initial parent is widgetPool; Component.onCompleted places them.
            // =================================================================

            // ─ App Launcher ─
            Rectangle {
                id: launcherPill
                parent: widgetPool
                visible: root.showLauncherPill
                Layout.preferredWidth: bar.widgetW("launcher", bar.sp(42))
                Layout.preferredHeight: bar.pillHeight
                Layout.alignment: Qt.AlignVCenter
                radius: bar.pillRadius
                color: launcherMouse.containsMouse ? bar.glassHover : bar.pillBg
                border.width: bar.controlBorderWidth
                border.color: launcherMouse.containsMouse ? bar.accent : bar.pillBorder

                Text {
                    anchors.centerIn: parent
                    text: bar.iconLauncher
                    font.pixelSize: bar.widgetW("launcher", bar.iconSizePillLarge)
                    font.family: bar.fontFamily
                    color: launcherMouse.containsMouse ? bar.accent : bar.subtext
                }

                MouseArea {
                    id: launcherMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Quickshell.execDetached(["sh", "-c", bar.launcherCommand])
                }

                ToolTip.text: bar.launcherTooltip
                ToolTip.visible: launcherMouse.containsMouse
                ToolTip.delay: bar.tooltipDelay
            }

            // ─ Quick Launch ─
            QuickLaunchPill {
                id: quickLaunchPill
                parent: widgetPool
                visible: root.effQuickLaunch
                bar: bar
            }

            // ─ FreshRSS ─
            FreshRssPill {
                id: freshRssPill
                parent: widgetPool
                visible: root.effFreshRss
                bar: bar
            }

            // ─ Media Player ─
            MediaPill {
                id: mediaPill
                parent: widgetPool
                visible: root.effMedia
                bar: bar
                barBg: barBg
            }

            // ─ Workspaces ─
            WorkspacesPill {
                id: workspacesPill
                parent: widgetPool
                visible: root.showWorkspacesPill
                bar: bar
            }

            // ─ System Stats ─
            SysStatsPill {
                id: sysStatsPill
                parent: widgetPool
                visible: root.effStats
                bar: bar
                barBg: barBg
                mediaActive: mediaPill.hasMedia
            }

            // ─ System Tray ─
            SystemTrayPill {
                id: trayPill
                parent: widgetPool
                visible: root.showTrayPill
                bar: bar
                barBg: barBg
            }

            // ─ Connectivity + Audio (Network · Bluetooth · Sound as one pill) ─
            Rectangle {
                id: connectivityPill
                parent: widgetPool
                visible: root.effConnectivity || root.showAudioPill
                Layout.preferredHeight: bar.pillHeight
                Layout.preferredWidth: connectivityRow.implicitWidth + 10
                Layout.alignment: Qt.AlignVCenter
                radius: bar.pillRadius
                color: bar.pillBg
                border.width: bar.controlBorderWidth
                border.color: bar.pillBorder

                Row {
                    id: connectivityRow
                    anchors.centerIn: parent
                    spacing: Math.max(2, bar.widgetW("connectivity", 4))

                    NetworkPill {
                        id: networkPill
                        embedded: true
                        pillScale: bar.widgetScale("connectivity")
                        visible: root.effNetwork
                        bar: bar
                        barBg: barBg
                    }

                    Rectangle {
                        visible: root.effNetwork && root.effBluetooth
                        width: Math.max(1, bar.widgetW("connectivity", bar.dividerThickness))
                        height: 17
                        anchors.verticalCenter: parent.verticalCenter
                        color: bar.divider
                    }

                    BluetoothPill {
                        id: bluetoothPill
                        embedded: true
                        pillScale: bar.widgetScale("connectivity")
                        visible: root.effBluetooth
                        bar: bar
                        barBg: barBg
                    }

                    Rectangle {
                        visible: (root.effNetwork || root.effBluetooth) && root.showAudioPill
                        width: Math.max(1, bar.widgetW("connectivity", bar.dividerThickness))
                        height: 17
                        anchors.verticalCenter: parent.verticalCenter
                        color: bar.divider
                    }

                    AudioPill {
                        id: audioPill
                        embedded: true
                        pillScale: bar.widgetScale("connectivity")
                        visible: root.showAudioPill
                        bar: bar
                        barBg: barBg
                    }
                }
            }

            // ─ Clock + Calendar ─
            ClockPill {
                id: clockPill
                parent: widgetPool
                visible: root.showClockPill
                bar: bar
                barBg: barBg
            }

            // ─ Notifications ─
            NotificationBell {
                id: notificationBell
                parent: widgetPool
                visible: root.showNotificationPill
                bar: bar
                barBg: barBg
            }

            // ─ Kill Target ─
            KillTargetPill {
                id: killTargetPill
                parent: widgetPool
                visible: root.effKillTarget
                bar: bar
            }

            // ─ Hyprland Config Inspector ─
            Rectangle {
                id: hyprInspPill
                parent: widgetPool
                visible: root.showHyprInspPill
                Layout.preferredWidth: bar.widgetW("hyprInsp", bar.sp(42))
                Layout.preferredHeight: bar.pillHeight
                Layout.alignment: Qt.AlignVCenter
                radius: bar.pillRadius
                color: hyprInspMouse.containsMouse ? bar.glassHover : bar.pillBg
                border.width: bar.controlBorderWidth
                border.color: hyprInspMouse.containsMouse ? bar.accent : bar.pillBorder

                Text {
                    anchors.centerIn: parent
                    text: bar.iconHyprInsp
                    font.pixelSize: bar.widgetW("hyprInsp", bar.iconSizePillLarge)
                    font.family: bar.fontFamily
                    color: hyprInspMouse.containsMouse ? bar.accent : bar.subtext
                }

                MouseArea {
                    id: hyprInspMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (hyprConfigInsp && hyprConfigInsp.toggle)
                            hyprConfigInsp.toggle()
                    }
                    ToolTip.visible: containsMouse
                    ToolTip.delay: bar.tooltipDelay
                    ToolTip.text: "Hyprland Config Inspector"
                }
            }

            // ─ Bar control / config menu ─
            Rectangle {
                id: controlBarPill
                parent: widgetPool
                visible: root.showControlBarPill
                Layout.preferredWidth: bar.widgetW("controlBar", bar.sp(42))
                Layout.preferredHeight: bar.pillHeight
                Layout.alignment: Qt.AlignVCenter
                radius: bar.pillRadius
                color: controlBarMouse.containsMouse || (barControlBar && barControlBar.open)
                       ? bar.glassHover : bar.pillBg
                border.width: bar.controlBorderWidth
                border.color: controlBarMouse.containsMouse || (barControlBar && barControlBar.open)
                              ? bar.accent : bar.pillBorder

                Text {
                    anchors.centerIn: parent
                    text: bar.iconControlBar
                    font.pixelSize: bar.widgetW("controlBar", bar.iconSizePillLarge)
                    font.family: bar.fontFamily
                    color: controlBarMouse.containsMouse || (barControlBar && barControlBar.open)
                           ? bar.accent : bar.subtext
                }

                MouseArea {
                    id: controlBarMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (barControlBar && barControlBar.toggle)
                            barControlBar.toggle()
                    }
                    ToolTip.visible: containsMouse
                    ToolTip.delay: bar.tooltipDelay
                    ToolTip.text: "Config menu (or right-click empty bar)"
                }
            }

            // ─ Power Menu ─
            PowerMenu {
                id: powerMenu
                parent: widgetPool
                visible: root.showPowerPill
                bar: bar
                barBg: barBg
            }
        }

        // --- Background services (do not move to zones) ---
        HyprConfigInsp { id: hyprConfigInsp; bar: bar }

        Io.IpcHandler {
            target: "hyprConfigInsp"
            function toggle() {
                if (hyprConfigInsp && hyprConfigInsp.toggle) hyprConfigInsp.toggle()
            }
        }

        Io.IpcHandler {
            target: "freshRss"
            function toggle() {
                if (freshRssPill && freshRssPill.toggle)
                    freshRssPill.toggle()
            }
            function refresh() {
                if (freshRssPill && freshRssPill.refresh)
                    freshRssPill.refresh()
            }
            function show() {
                if (freshRssPill && freshRssPill.show)
                    freshRssPill.show()
            }
            function hide() {
                if (freshRssPill && freshRssPill.hide)
                    freshRssPill.hide()
            }
        }

        Io.IpcHandler {
            target: "audioPill"
            // Echo cancel (sticky AEC). Same as the popup On/Off toggle.
            // Examples:
            //   qs ipc call audioPill setEchoCancel true
            //   qs ipc call audioPill setEchoCancel false
            //   qs ipc call audioPill toggleEchoCancel
            //   qs ipc call audioPill enableEchoCancel
            //   qs ipc call audioPill disableEchoCancel
            function setEchoCancel(enabled: bool): void {
                if (audioPill && audioPill.setEchoCancelEnabled)
                    audioPill.setEchoCancelEnabled(enabled)
            }
            function toggleEchoCancel(): void {
                if (audioPill && audioPill.toggleEchoCancel)
                    audioPill.toggleEchoCancel()
            }
            function enableEchoCancel(): void {
                if (audioPill && audioPill.enableEchoCancel)
                    audioPill.enableEchoCancel()
            }
            function disableEchoCancel(): void {
                if (audioPill && audioPill.disableEchoCancel)
                    audioPill.disableEchoCancel()
            }
        }

        Io.IpcHandler {
            target: "networkPill"
            function showPopup(): void {
                if (networkPill && networkPill.showPopup) networkPill.showPopup()
            }
            function hidePopup(): void {
                if (networkPill && networkPill.hidePopup) networkPill.hidePopup()
            }
            function togglePopup(): void {
                if (networkPill && networkPill.togglePopup) networkPill.togglePopup()
            }
            function setWifi(enabled: bool): void {
                if (networkPill && networkPill.setWifi) networkPill.setWifi(enabled)
            }
            function toggleWifi(): void {
                if (networkPill && networkPill.toggleWifi) networkPill.toggleWifi()
            }
            function enableWifi(): void {
                if (networkPill && networkPill.enableWifi) networkPill.enableWifi()
            }
            function disableWifi(): void {
                if (networkPill && networkPill.disableWifi) networkPill.disableWifi()
            }
            function setNetworking(enabled: bool): void {
                if (networkPill && networkPill.setNetworking) networkPill.setNetworking(enabled)
            }
            function toggleNetworking(): void {
                if (networkPill && networkPill.toggleNetworking) networkPill.toggleNetworking()
            }
            function startScan(): void {
                if (networkPill && networkPill.startScan) networkPill.startScan()
            }
            function stopScan(): void {
                if (networkPill && networkPill.stopScan) networkPill.stopScan()
            }
            function connectSsid(ssid: string): void {
                if (networkPill && networkPill.connectSsid) networkPill.connectSsid(ssid)
            }
            function disconnectDevice(iface: string): void {
                if (networkPill && networkPill.disconnectDevice) networkPill.disconnectDevice(iface)
            }
            function forgetSsid(ssid: string): void {
                if (networkPill && networkPill.forgetSsid) networkPill.forgetSsid(ssid)
            }
            // nm-applet: session-only start/stop (does not change login enablement)
            function startApplet(): void {
                if (networkPill && networkPill.startApplet) networkPill.startApplet()
            }
            function stopApplet(): void {
                if (networkPill && networkPill.stopApplet) networkPill.stopApplet()
            }
            function toggleApplet(): void {
                if (networkPill && networkPill.toggleApplet) networkPill.toggleApplet()
            }
            // nm-applet: persist across reboots (systemctl --user enable/disable)
            function enableApplet(): void {
                if (networkPill && networkPill.enableApplet) networkPill.enableApplet()
            }
            function disableApplet(): void {
                if (networkPill && networkPill.disableApplet) networkPill.disableApplet()
            }
            function setAppletAutostart(enabled: bool): void {
                if (networkPill && networkPill.setAppletAutostart)
                    networkPill.setAppletAutostart(enabled)
            }
            function openEditor(): void {
                if (networkPill && networkPill.openConnectionEditor) networkPill.openConnectionEditor()
            }
            function refreshIp(): void {
                if (networkPill && networkPill.refreshIp) networkPill.refreshIp("")
            }
            function refreshDns(): void {
                if (networkPill && networkPill.refreshDns) networkPill.refreshDns("")
            }
            function activateConnection(id: string): void {
                if (networkPill && networkPill.activateConnection)
                    networkPill.activateConnection(id)
            }
            function deactivateConnection(id: string): void {
                if (networkPill && networkPill.deactivateConnection)
                    networkPill.deactivateConnection(id)
            }
        }

        Io.IpcHandler {
            target: "bluetoothPill"
            // Popup
            function showPopup(): void {
                if (bluetoothPill && bluetoothPill.showPopup) bluetoothPill.showPopup()
            }
            function hidePopup(): void {
                if (bluetoothPill && bluetoothPill.hidePopup) bluetoothPill.hidePopup()
            }
            function togglePopup(): void {
                if (bluetoothPill && bluetoothPill.togglePopup) bluetoothPill.togglePopup()
            }
            // Adapter radio power
            function setPower(enabled: bool): void {
                if (bluetoothPill && bluetoothPill.setPower) bluetoothPill.setPower(enabled)
            }
            function togglePower(): void {
                if (bluetoothPill && bluetoothPill.togglePower) bluetoothPill.togglePower()
            }
            function enable(): void {
                if (bluetoothPill && bluetoothPill.enable) bluetoothPill.enable()
            }
            function disable(): void {
                if (bluetoothPill && bluetoothPill.disable) bluetoothPill.disable()
            }
            // Discovery
            function startScan(): void {
                if (bluetoothPill && bluetoothPill.startScan) bluetoothPill.startScan()
            }
            function stopScan(): void {
                if (bluetoothPill && bluetoothPill.stopScan) bluetoothPill.stopScan()
            }
            function toggleScan(): void {
                if (bluetoothPill && bluetoothPill.toggleScan) bluetoothPill.toggleScan()
            }
            function setDiscoverable(enabled: bool): void {
                if (bluetoothPill && bluetoothPill.setDiscoverable) bluetoothPill.setDiscoverable(enabled)
            }
            function toggleDiscoverable(): void {
                if (bluetoothPill && bluetoothPill.toggleDiscoverable) bluetoothPill.toggleDiscoverable()
            }
            // Blueman monitor applet — session vs sticky (reboot)
            function startApplet(): void {
                if (bluetoothPill && bluetoothPill.startApplet) bluetoothPill.startApplet()
            }
            function stopApplet(): void {
                if (bluetoothPill && bluetoothPill.stopApplet) bluetoothPill.stopApplet()
            }
            function toggleApplet(): void {
                if (bluetoothPill && bluetoothPill.toggleApplet) bluetoothPill.toggleApplet()
            }
            // Permanent: XDG autostart override so applet stays off after reboot
            function disableApplet(): void {
                if (bluetoothPill && bluetoothPill.disableApplet) bluetoothPill.disableApplet()
            }
            function enableApplet(): void {
                if (bluetoothPill && bluetoothPill.enableApplet) bluetoothPill.enableApplet()
            }
            function setAppletAutostart(enabled: bool): void {
                if (bluetoothPill && bluetoothPill.setAppletAutostart)
                    bluetoothPill.setAppletAutostart(enabled)
            }
            // Devices — address is MAC string e.g. "A0:0C:E2:66:FB:7D"
            function connectDevice(address: string): void {
                if (bluetoothPill && bluetoothPill.connectDevice) bluetoothPill.connectDevice(address)
            }
            function disconnectDevice(address: string): void {
                if (bluetoothPill && bluetoothPill.disconnectDevice) bluetoothPill.disconnectDevice(address)
            }
            function pairDevice(address: string): void {
                if (bluetoothPill && bluetoothPill.pairDevice) bluetoothPill.pairDevice(address)
            }
            function cancelPair(address: string): void {
                if (bluetoothPill && bluetoothPill.cancelPair) bluetoothPill.cancelPair(address)
            }
            function forgetDevice(address: string): void {
                if (bluetoothPill && bluetoothPill.forgetDevice) bluetoothPill.forgetDevice(address)
            }
            function setTrusted(address: string, trusted: bool): void {
                if (bluetoothPill && bluetoothPill.setTrusted) bluetoothPill.setTrusted(address, trusted)
            }
            function setBlocked(address: string, blocked: bool): void {
                if (bluetoothPill && bluetoothPill.setBlocked) bluetoothPill.setBlocked(address, blocked)
            }
            function renameDevice(address: string, name: string): void {
                if (bluetoothPill && bluetoothPill.renameDevice) bluetoothPill.renameDevice(address, name)
            }
            // PipeWire bluez card profile for a device (e.g. a2dp-sink, headset-head-unit)
            function setCardProfile(address: string, profileName: string): void {
                if (bluetoothPill && bluetoothPill.setCardProfile) bluetoothPill.setCardProfile(address, profileName)
            }
        }

        Io.IpcHandler {
            target: "clockPill"
            function showCalendar() {
                if (clockPill && clockPill.showCalendar) clockPill.showCalendar()
            }
        }

        Io.IpcHandler {
            target: "notificationBell"
            function toggleDoNotDisturb() {
                if (notificationBell && notificationBell.toggleDoNotDisturb) notificationBell.toggleDoNotDisturb()
            }
        }

        Io.IpcHandler {
            target: "killTargetPill"
            function activatePickMode() {
                if (killTargetPill && killTargetPill.activatePickMode) killTargetPill.activatePickMode()
            }
            function cancelPickMode() {
                if (killTargetPill && killTargetPill.cancelPickMode) killTargetPill.cancelPickMode()
            }
        }

        Io.IpcHandler {
            target: "sysStatsPill"
            function setCpuLiveUpdates(enabled: bool) {
                if (sysStatsPill && sysStatsPill.setCpuLiveUpdates) sysStatsPill.setCpuLiveUpdates(enabled)
            }
            function setGpuLiveUpdates(enabled: bool) {
                if (sysStatsPill && sysStatsPill.setGpuLiveUpdates) sysStatsPill.setGpuLiveUpdates(enabled)
            }
            function setMemLiveUpdates(enabled: bool) {
                if (sysStatsPill && sysStatsPill.setMemLiveUpdates) sysStatsPill.setMemLiveUpdates(enabled)
            }
            function setMetricsLiveUpdates(enabled: bool) {
                if (sysStatsPill && sysStatsPill.setMetricsLiveUpdates) sysStatsPill.setMetricsLiveUpdates(enabled)
            }
            function toggleCpuLiveUpdates() {
                if (sysStatsPill && sysStatsPill.toggleCpuLiveUpdates) sysStatsPill.toggleCpuLiveUpdates()
            }
            function toggleGpuLiveUpdates() {
                if (sysStatsPill && sysStatsPill.toggleGpuLiveUpdates) sysStatsPill.toggleGpuLiveUpdates()
            }
            function toggleMemLiveUpdates() {
                if (sysStatsPill && sysStatsPill.toggleMemLiveUpdates) sysStatsPill.toggleMemLiveUpdates()
            }
            function toggleMetricsLiveUpdates() {
                if (sysStatsPill && sysStatsPill.toggleMetricsLiveUpdates) sysStatsPill.toggleMetricsLiveUpdates()
            }
        }

    }

    // IPC handlers must use explicit types (bool, string, etc.) — `var` is not supported
    Io.IpcHandler {
        target: "shell"
        function setShowLauncherPill(enabled: bool): void {
            bar.setWidgetVisible("launcher", enabled)
        }
        function toggleShowLauncherPill(): void {
            bar.toggleWidgetVisible("launcher")
        }
        function setShowQuickLaunchPill(enabled: bool): void {
            bar.setWidgetVisible("quickLaunch", enabled)
        }
        function toggleShowQuickLaunchPill(): void {
            bar.toggleWidgetVisible("quickLaunch")
        }
        function setShowMediaWidget(enabled: bool): void {
            bar.setWidgetVisible("media", enabled)
        }
        function toggleShowMediaWidget(): void {
            bar.toggleWidgetVisible("media")
        }
        function setShowWorkspacesPill(enabled: bool): void {
            bar.setWidgetVisible("workspaces", enabled)
        }
        function toggleShowWorkspacesPill(): void {
            bar.toggleWidgetVisible("workspaces")
        }
        function setShowStatsWidget(enabled: bool): void {
            bar.setWidgetVisible("stats", enabled)
        }
        function toggleShowStatsWidget(): void {
            bar.toggleWidgetVisible("stats")
        }
        function setShowTrayPill(enabled: bool): void {
            bar.setWidgetVisible("tray", enabled)
        }
        function toggleShowTrayPill(): void {
            bar.toggleWidgetVisible("tray")
        }
        function setShowNetworkPill(enabled: bool): void {
            bar.setWidgetVisible("network", enabled)
        }
        function toggleShowNetworkPill(): void {
            bar.toggleWidgetVisible("network")
        }
        function setShowBluetoothPill(enabled: bool): void {
            bar.setWidgetVisible("bluetooth", enabled)
        }
        function toggleShowBluetoothPill(): void {
            bar.toggleWidgetVisible("bluetooth")
        }
        function setShowAudioPill(enabled: bool): void {
            bar.setWidgetVisible("audio", enabled)
        }
        function toggleShowAudioPill(): void {
            bar.toggleWidgetVisible("audio")
        }
        function setShowClockPill(enabled: bool): void {
            bar.setWidgetVisible("clock", enabled)
        }
        function toggleShowClockPill(): void {
            bar.toggleWidgetVisible("clock")
        }
        function setShowNotificationPill(enabled: bool): void {
            bar.setWidgetVisible("notifications", enabled)
        }
        function toggleShowNotificationPill(): void {
            bar.toggleWidgetVisible("notifications")
        }
        function setShowPowerPill(enabled: bool): void {
            bar.setWidgetVisible("power", enabled)
        }
        function toggleShowPowerPill(): void {
            bar.toggleWidgetVisible("power")
        }
        function setClockFormat(format: string): void {
            bar.setClockFormat(format)
        }
        function setWidgetZone(widgetId: string, zone: string): void {
            bar.setWidgetZone(widgetId, zone)
        }
        function moveWidget(widgetId: string, delta: string): void {
            bar.moveWidget(widgetId, Number(delta) || 0)
        }
        function resetWidgetLayout(): void {
            bar.resetWidgetLayout()
        }
        function setBarPosition(position: string): void {
            bar.setBarPosition(position)
        }
        function toggleBarPosition(): void {
            bar.toggleBarPosition()
        }
        function toggleBarControlBar(): void {
            barControlBar.toggle()
        }
        function showBarControlBar(): void {
            barControlBar.show()
        }
        function hideBarControlBar(): void {
            barControlBar.hide()
        }
        function setUiScale(scale: string): void {
            bar.setUiScale(scale)
        }
        function setUiScaleManual(scale: string): void {
            bar.setUiScaleManual(scale)
        }
        function setUiScaleAuto(): void {
            bar.setUiScaleAuto()
        }
        function setShowKillTargetPill(enabled: bool): void {
            bar.setWidgetVisible("killTarget", enabled)
        }
        function setShowFreshRssPill(enabled: bool): void {
            bar.setWidgetVisible("freshRss", enabled)
        }
        function toggleShowFreshRssPill(): void {
            bar.toggleWidgetVisible("freshRss")
        }
        function toggleShowKillTargetPill(): void {
            bar.toggleWidgetVisible("killTarget")
        }
        function setShowHyprInspPill(enabled: bool): void {
            bar.setWidgetVisible("hyprInsp", enabled)
        }
        function toggleShowHyprInspPill(): void {
            bar.toggleWidgetVisible("hyprInsp")
        }
        function setShowControlBarPill(enabled: bool): void {
            bar.setWidgetVisible("controlBar", enabled)
        }
        function toggleShowControlBarPill(): void {
            bar.toggleWidgetVisible("controlBar")
        }
        function setShowMagicWorkspacePill(enabled: bool): void {
            if (bar && bar.setShowMagicWorkspacePill)
                bar.setShowMagicWorkspacePill(enabled)
            else
                root.showMagicWorkspacePill = enabled
        }
        function toggleShowMagicWorkspacePill(): void {
            setShowMagicWorkspacePill(!root.showMagicWorkspacePill)
        }
        function setWsMinimumShown(count: int): void {
            if (bar && bar.setWsMinimumShown)
                bar.setWsMinimumShown(count)
            else
                root.wsMinimumShown = Math.max(1, Math.min(10, count))
        }
        function setWsShowOnlyActive(enabled: bool): void {
            if (bar && bar.setWsShowOnlyActive)
                bar.setWsShowOnlyActive(enabled)
            else
                root.wsShowOnlyActive = enabled
        }
        function setWsStartupWorkspace(workspace: int): void {
            if (bar && bar.setWsStartupWorkspace)
                bar.setWsStartupWorkspace(workspace)
            else
                root.wsStartupWorkspace = Math.max(0, Math.min(10, workspace))
        }
        function setWsStartupCloseMagic(enabled: bool): void {
            if (bar && bar.setWsStartupCloseMagic)
                bar.setWsStartupCloseMagic(enabled)
            else
                root.wsStartupCloseMagic = enabled
        }
    }
}