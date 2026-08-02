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
//   - qs ipc call radar toggle / refresh / show / hide
//   - qs ipc call shell setShowFreshRssPill true / toggleShowFreshRssPill
//   - qs ipc call shell setShowRadarPill true / toggleShowRadarPill
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
//   - barPosition: "top" or "bottom"
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
// Current layout:
//   LEFT:   App Launcher, Quick Launch, Media Player
//   CENTER: Workspaces
//   RIGHT:  System Stats, System Tray, Connectivity (Network+Bluetooth),
//           Audio, Clock, Notifications, Power
//
// Why CENTER is special: left and right zones are different widths, so a widget
// placed "between" them would look off-center. CENTER ZONE is pinned to the
// true middle of the bar automatically — you still just cut and paste blocks.
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
    property bool showRadarPill: true
    property bool showMagicWorkspacePill: true   // Magic pill inside WorkspacesPill (wsShowSpecialPill)

    // Workspace behavior (config defaults in Config.qml; IPC overrides until qs restart)
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
            root.showRadarPill = cfg.showRadarPill
            root.showMagicWorkspacePill = cfg.wsShowSpecialPill
            root.wsMinimumShown = cfg.wsMinimumShown
            root.wsShowOnlyActive = cfg.wsShowOnlyActive
            root.wsStartupWorkspace = cfg.wsStartupWorkspace
            root.wsStartupCloseMagic = cfg.wsStartupCloseMagic

            // Start optional startup focus only after config is applied (avoids
            // racing the property default before cfg loads). No-op when 0.
            if (root.wsStartupWorkspace > 0)
                startupWorkspaceTimer.start()
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

        // --- Sizing & bar position
        readonly property alias barPosition: cfg.barPosition
        readonly property alias barEdgeMargin: cfg.barEdgeMargin
        readonly property alias popupBarGap: cfg.popupBarGap
        readonly property alias barHeight: cfg.barHeight
        readonly property alias barTopMargin: cfg.barTopMargin

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
        readonly property alias quickLaunchApps: cfg.quickLaunchApps

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
        property int wsMinimumShown: root.wsMinimumShown
        property bool wsShowOnlyActive: root.wsShowOnlyActive
        property int wsStartupWorkspace: root.wsStartupWorkspace
        property bool wsStartupCloseMagic: root.wsStartupCloseMagic
        property bool showMagicWorkspacePill: root.showMagicWorkspacePill
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
            border.width: bar.controlBorderWidth
            border.color: bar.glassBorder

            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: bar.popupHeaderHighlightHeight
                color: bar.glassHighlight
                radius: parent.radius
            }

            // Bottom edge strip removed — soft shadow washed true-black chrome

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: bar.barContentHMargin
                anchors.rightMargin: bar.barContentHMargin
                spacing: 0

                // --- LEFT ZONE ---
                RowLayout {
                    id: leftZone
                    spacing: bar.widgetSpacing

                    // ─ App Launcher (command + tooltip from Config.qml: launcherCommand, launcherTooltip) ─
                    Rectangle {
                        id: launcherPill
                        visible: root.showLauncherPill
                        Layout.preferredWidth: 42
                        Layout.preferredHeight: bar.pillHeight
                        radius: bar.pillRadius
                        color: launcherMouse.containsMouse ? bar.glassHover : bar.pillBg
                        border.width: bar.controlBorderWidth
                        border.color: launcherMouse.containsMouse ? bar.accent : bar.pillBorder

                        Text {
                            anchors.centerIn: parent
                            text: bar.iconLauncher
                            font.pixelSize: bar.iconSizePillLarge
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

                    // ── divider ──
                    Rectangle {
                        visible: root.showLauncherPill && root.showQuickLaunchPill
                        Layout.preferredWidth: bar.dividerThickness
                        Layout.preferredHeight: 18
                        Layout.alignment: Qt.AlignVCenter
                        color: bar.divider
                    }

                    // ─ Quick Launch ─
                    QuickLaunchPill {
                        visible: root.showQuickLaunchPill
                        bar: bar
                    }

                    // ── divider ──
                    Rectangle {
                        visible: root.showQuickLaunchPill && (root.showFreshRssPill || root.showRadarPill)
                        Layout.preferredWidth: bar.dividerThickness
                        Layout.preferredHeight: 18
                        Layout.alignment: Qt.AlignVCenter
                        color: bar.divider
                    }

                    // ─ FreshRSS ─
                    FreshRssPill {
                        id: freshRssPill
                        visible: root.showFreshRssPill
                        bar: bar
                    }

                    // ── divider ──
                    Rectangle {
                        visible: root.showFreshRssPill && root.showRadarPill
                        Layout.preferredWidth: bar.dividerThickness
                        Layout.preferredHeight: 18
                        Layout.alignment: Qt.AlignVCenter
                        color: bar.divider
                    }

                    // ─ NWS Radar ─
                    RadarPill {
                        id: radarPill
                        visible: root.showRadarPill
                        bar: bar
                    }

                    // ── divider ──
                    Rectangle {
                        visible: (root.showFreshRssPill || root.showRadarPill) && root.showMediaWidget
                        Layout.preferredWidth: bar.dividerThickness
                        Layout.preferredHeight: 18
                        Layout.alignment: Qt.AlignVCenter
                        color: bar.divider
                    }

                    // ─ Media Player ─
                    MediaPill {
                        id: mediaPill
                        visible: root.showMediaWidget
                        bar: bar
                        barBg: barBg
                    }
                }

                Item { Layout.fillWidth: true }

                // --- RIGHT ZONE ---
                RowLayout {
                    id: rightZone
                    spacing: bar.widgetSpacing

                    // ─ System Stats ─
                    SysStatsPill {
                        id: sysStatsPill
                        visible: root.showStatsWidget
                        bar: bar
                        barBg: barBg
                        mediaActive: mediaPill.hasMedia
                    }

                    // ── divider ──
                    Rectangle {
                        visible: root.showStatsWidget && (root.showTrayPill || root.showNetworkPill || root.showBluetoothPill || root.showAudioPill)
                        Layout.preferredWidth: bar.dividerThickness
                        Layout.preferredHeight: 18
                        Layout.alignment: Qt.AlignVCenter
                        color: bar.divider
                    }

                    // ─ System Tray ─
                    SystemTrayPill {
                        visible: root.showTrayPill
                        bar: bar
                        barBg: barBg
                    }

                    // ── divider ──
                    Rectangle {
                        visible: root.showTrayPill && (root.showNetworkPill || root.showBluetoothPill || root.showAudioPill)
                        Layout.preferredWidth: bar.dividerThickness
                        Layout.preferredHeight: 18
                        Layout.alignment: Qt.AlignVCenter
                        color: bar.divider
                    }

                    // ─ Connectivity (Network + Bluetooth in one shared pill) ─
                    // Widgets stay separate files; embedded: true strips their own
                    // chrome so this shell is the single visual capsule.
                    Rectangle {
                        id: connectivityPill
                        visible: root.showNetworkPill || root.showBluetoothPill
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
                            spacing: 4

                            NetworkPill {
                                id: networkPill
                                embedded: true
                                visible: root.showNetworkPill
                                bar: bar
                                barBg: barBg
                            }

                            // Thin inner separator (same style as SysStats sections)
                            Rectangle {
                                visible: root.showNetworkPill && root.showBluetoothPill
                                width: bar.dividerThickness
                                height: 17
                                anchors.verticalCenter: parent.verticalCenter
                                color: bar.divider
                            }

                            BluetoothPill {
                                id: bluetoothPill
                                embedded: true
                                visible: root.showBluetoothPill
                                bar: bar
                                barBg: barBg
                            }
                        }
                    }

                    // ── divider ──
                    Rectangle {
                        visible: (root.showNetworkPill || root.showBluetoothPill) && root.showAudioPill
                        Layout.preferredWidth: bar.dividerThickness
                        Layout.preferredHeight: 18
                        Layout.alignment: Qt.AlignVCenter
                        color: bar.divider
                    }

                    // ─ Audio ─
                    AudioPill {
                        id: audioPill
                        visible: root.showAudioPill
                        bar: bar
                        barBg: barBg
                    }

                    // ── divider ──
                    Rectangle {
                        visible: root.showAudioPill && root.showClockPill
                        Layout.preferredWidth: bar.dividerThickness
                        Layout.preferredHeight: 18
                        Layout.alignment: Qt.AlignVCenter
                        color: bar.divider
                    }

                    // ─ Clock + Calendar ─
                    ClockPill {
                        id: clockPill
                        visible: root.showClockPill
                        bar: bar
                        barBg: barBg
                    }

                    // ── divider ──
                    Rectangle {
                        visible: root.showClockPill && root.showNotificationPill
                        Layout.preferredWidth: bar.dividerThickness
                        Layout.preferredHeight: 18
                        Layout.alignment: Qt.AlignVCenter
                        color: bar.divider
                    }

                    // ─ Notifications ─
                    NotificationBell {
                        id: notificationBell
                        visible: root.showNotificationPill
                        bar: bar
                        barBg: barBg
                    }

                    // ── divider ──
                    Rectangle {
                        visible: root.showNotificationPill && (root.showKillTargetPill || root.showPowerPill)
                        Layout.preferredWidth: bar.dividerThickness
                        Layout.preferredHeight: 18
                        Layout.alignment: Qt.AlignVCenter
                        color: bar.divider
                    }

                    // ─ Kill Target ─
                    KillTargetPill {
                        id: killTargetPill
                        visible: root.showKillTargetPill
                        bar: bar
                    }

                    // ── divider ──
                    Rectangle {
                        visible: root.showKillTargetPill && root.showPowerPill
                        Layout.preferredWidth: bar.dividerThickness
                        Layout.preferredHeight: 18
                        Layout.alignment: Qt.AlignVCenter
                        color: bar.divider
                    }

                    // ─ Power Menu ─
                    PowerMenu {
                        visible: root.showPowerPill
                        bar: bar
                        barBg: barBg
                    }
                }
            }

            // --- CENTER ZONE ---
            RowLayout {
                id: centerZone
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                spacing: bar.widgetSpacing

                // ─ Workspaces ─
                WorkspacesPill {
                    visible: root.showWorkspacesPill
                    bar: bar
                }
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
            target: "radar"
            function toggle() {
                if (radarPill && radarPill.toggle)
                    radarPill.toggle()
            }
            function refresh() {
                if (radarPill && radarPill.refresh)
                    radarPill.refresh()
            }
            function show() {
                if (radarPill && radarPill.show)
                    radarPill.show()
            }
            function hide() {
                if (radarPill && radarPill.hide)
                    radarPill.hide()
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
            root.showLauncherPill = enabled
        }
        function toggleShowLauncherPill(): void {
            root.showLauncherPill = !root.showLauncherPill
        }
        function setShowQuickLaunchPill(enabled: bool): void {
            root.showQuickLaunchPill = enabled
        }
        function toggleShowQuickLaunchPill(): void {
            root.showQuickLaunchPill = !root.showQuickLaunchPill
        }
        function setShowMediaWidget(enabled: bool): void {
            root.showMediaWidget = enabled
        }
        function toggleShowMediaWidget(): void {
            root.showMediaWidget = !root.showMediaWidget
        }
        function setShowWorkspacesPill(enabled: bool): void {
            root.showWorkspacesPill = enabled
        }
        function toggleShowWorkspacesPill(): void {
            root.showWorkspacesPill = !root.showWorkspacesPill
        }
        function setShowStatsWidget(enabled: bool): void {
            root.showStatsWidget = enabled
        }
        function toggleShowStatsWidget(): void {
            root.showStatsWidget = !root.showStatsWidget
        }
        function setShowTrayPill(enabled: bool): void {
            root.showTrayPill = enabled
        }
        function toggleShowTrayPill(): void {
            root.showTrayPill = !root.showTrayPill
        }
        function setShowNetworkPill(enabled: bool): void {
            root.showNetworkPill = enabled
        }
        function toggleShowNetworkPill(): void {
            root.showNetworkPill = !root.showNetworkPill
        }
        function setShowBluetoothPill(enabled: bool): void {
            root.showBluetoothPill = enabled
        }
        function toggleShowBluetoothPill(): void {
            root.showBluetoothPill = !root.showBluetoothPill
        }
        function setShowAudioPill(enabled: bool): void {
            root.showAudioPill = enabled
        }
        function toggleShowAudioPill(): void {
            root.showAudioPill = !root.showAudioPill
        }
        function setShowClockPill(enabled: bool): void {
            root.showClockPill = enabled
        }
        function toggleShowClockPill(): void {
            root.showClockPill = !root.showClockPill
        }
        function setShowNotificationPill(enabled: bool): void {
            root.showNotificationPill = enabled
        }
        function toggleShowNotificationPill(): void {
            root.showNotificationPill = !root.showNotificationPill
        }
        function setShowPowerPill(enabled: bool): void {
            root.showPowerPill = enabled
        }
        function toggleShowPowerPill(): void {
            root.showPowerPill = !root.showPowerPill
        }
        function setShowKillTargetPill(enabled: bool): void {
            root.showKillTargetPill = enabled
        }
        function setShowFreshRssPill(enabled: bool): void {
            root.showFreshRssPill = enabled
        }
        function toggleShowFreshRssPill(): void {
            root.showFreshRssPill = !root.showFreshRssPill
        }
        function setShowRadarPill(enabled: bool): void {
            root.showRadarPill = enabled
        }
        function toggleShowRadarPill(): void {
            root.showRadarPill = !root.showRadarPill
        }
        function toggleShowKillTargetPill(): void {
            root.showKillTargetPill = !root.showKillTargetPill
        }
        function setShowMagicWorkspacePill(enabled: bool): void {
            root.showMagicWorkspacePill = enabled
        }
        function toggleShowMagicWorkspacePill(): void {
            root.showMagicWorkspacePill = !root.showMagicWorkspacePill
        }
        function setWsMinimumShown(count: int): void {
            root.wsMinimumShown = Math.max(1, Math.min(10, count))
        }
        function setWsShowOnlyActive(enabled: bool): void {
            root.wsShowOnlyActive = enabled
        }
        function setWsStartupWorkspace(workspace: int): void {
            root.wsStartupWorkspace = Math.max(0, Math.min(10, workspace))
        }
        function setWsStartupCloseMagic(enabled: bool): void {
            root.wsStartupCloseMagic = enabled
        }
    }
}