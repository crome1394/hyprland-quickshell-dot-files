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
//   - qs ipc call shell setShowMediaWidget true
//   - qs ipc call shell setShowStatsWidget false
//   - qs ipc call shell toggleShowMediaWidget
//   - qs ipc call shell toggleShowStatsWidget
//   - qs ipc call shell setShowMagicWorkspacePill true
//   - qs ipc call shell toggleShowMagicWorkspacePill
//   (Run `qs ipc show` to list all registered commands.)
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
//   RIGHT:  System Stats, System Tray, Audio, Clock, Notifications, Power
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

    // --- Widget visibility (also toggled via IPC; see header) ---
    property bool showMediaWidget: false
    property bool showStatsWidget: true
    property bool showMagicWorkspacePill: true   // Initialized from cfg.wsShowSpecialPill in bar.onCompleted

    // On qs start, optionally close magic and focus wsStartupWorkspace (see Config.qml).
    // Polls a few times so Hyprland.activeToplevel is ready (Hyprland 0.55+ lua).
    property int _startupWsAttempts: 0
    Timer {
        id: startupWorkspaceTimer
        interval: 350
        running: true
        repeat: true
        onTriggered: {
            const targetWs = bar.wsStartupWorkspace
            if (targetWs <= 0) {
                stop()
                return
            }
            root._startupWsAttempts += 1
            if (bar.wsStartupCloseMagic) {
                const toplevel = Hyprland.activeToplevel
                if (toplevel && toplevel.workspace && bar.wsIsSpecialName(toplevel.workspace.name)) {
                    Hyprland.dispatch("hl.dsp.workspace.toggle_special('" + bar.wsSpecialName + "')")
                }
            }
            Hyprland.dispatch("hl.dsp.focus({ workspace = " + targetWs + " })")
            if (root._startupWsAttempts >= 4) {
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
            root.showMagicWorkspacePill = cfg.wsShowSpecialPill
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
        readonly property alias iconSizePill: cfg.iconSizePill
        readonly property alias iconSizePillLarge: cfg.iconSizePillLarge
        readonly property alias iconSizePopup: cfg.iconSizePopup
        readonly property alias iconSizePower: cfg.iconSizePower
        readonly property alias iconSizeMediaArt: cfg.iconSizeMediaArt
        readonly property alias iconSizeTray: cfg.iconSizeTray
        readonly property alias quickLaunchIcon: cfg.quickLaunchIcon

        // --- Popup sizes
        readonly property alias popupAudioWidth: cfg.popupAudioWidth
        readonly property alias popupAudioHeight: cfg.popupAudioHeight
        readonly property alias popupMediaWidth: cfg.popupMediaWidth
        readonly property alias popupMediaHeight: cfg.popupMediaHeight
        readonly property alias popupPowerWidth: cfg.popupPowerWidth
        readonly property alias popupPowerHeight: cfg.popupPowerHeight
        readonly property alias popupCalendarWidth: cfg.popupCalendarWidth
        readonly property alias popupCalendarHeight: cfg.popupCalendarHeight
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
        readonly property alias iconPower: cfg.iconPower
        readonly property alias iconLock: cfg.iconLock
        readonly property alias iconLogout: cfg.iconLogout
        readonly property alias iconReboot: cfg.iconReboot
        readonly property alias iconShutdown: cfg.iconShutdown
        readonly property alias iconBios: cfg.iconBios
        readonly property alias iconLauncher: cfg.iconLauncher
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
        readonly property alias wsMinimumShown: cfg.wsMinimumShown
        readonly property alias wsShowOnlyActive: cfg.wsShowOnlyActive
        readonly property alias wsStartupWorkspace: cfg.wsStartupWorkspace
        readonly property alias wsStartupCloseMagic: cfg.wsStartupCloseMagic
        property bool showMagicWorkspacePill: root.showMagicWorkspacePill
        function wsIconForId(id) { return cfg.wsIconForId(id) }
        function wsIsSpecialName(name) { return cfg.wsIsSpecialName(name) }

        // --- System stats gauges
        readonly property alias statGaugeWidth: cfg.statGaugeWidth
        readonly property alias statGaugeHeight: cfg.statGaugeHeight
        readonly property alias statGaugeRadius: cfg.statGaugeRadius
        readonly property alias statTrack: cfg.statTrack
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

        // --- Notification state (shared with NotificationBell)
        QtObject {
            id: notif
            property int count: 0
            property bool dnd: false
            property bool inhibited: false
            readonly property string icon: {
                if (dnd) return notif.count > 0 ? "󰂠" : "󰪓"
                return notif.count > 0 ? "󱅫" : "󰂜"
            }
        }

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

            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                height: 1
                color: Qt.rgba(0, 0, 0, 0.25)
                radius: parent.radius
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: bar.barContentHMargin
                anchors.rightMargin: bar.barContentHMargin
                spacing: 0

                // --- LEFT ZONE ---
                RowLayout {
                    id: leftZone
                    spacing: bar.widgetSpacing

                    // ─ App Launcher ─
                    Rectangle {
                        id: launcherPill
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
                            onClicked: Quickshell.execDetached(["sh", "-c", "~/.local/bin/rofi-app-drawer"])
                        }

                        ToolTip.text: "App Launcher"
                        ToolTip.visible: launcherMouse.containsMouse
                        ToolTip.delay: bar.tooltipDelay
                    }

                    // ── divider ──
                    Rectangle {
                        Layout.preferredWidth: bar.dividerThickness
                        Layout.preferredHeight: 18
                        Layout.alignment: Qt.AlignVCenter
                        color: bar.divider
                    }

                    // ─ Quick Launch ─
                    QuickLaunchPill { bar: bar }

                    // ── divider ──
                    Rectangle {
                        Layout.preferredWidth: bar.dividerThickness
                        Layout.preferredHeight: 18
                        Layout.alignment: Qt.AlignVCenter
                        color: bar.divider
                    }

                    // ─ Media Player ─
                    MediaPill {
                        id: mediaPill
                        visible: showMediaWidget
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
                        visible: showStatsWidget
                        bar: bar
                        mediaActive: mediaPill.hasMedia
                    }

                    // ── divider ──
                    Rectangle {
                        Layout.preferredWidth: bar.dividerThickness
                        Layout.preferredHeight: 18
                        Layout.alignment: Qt.AlignVCenter
                        color: bar.divider
                    }

                    // ─ System Tray ─
                    SystemTrayPill {
                        bar: bar
                        barBg: barBg
                    }

                    // ── divider ──
                    Rectangle {
                        Layout.preferredWidth: bar.dividerThickness
                        Layout.preferredHeight: 18
                        Layout.alignment: Qt.AlignVCenter
                        color: bar.divider
                    }

                    // ─ Audio ─
                    AudioPill {
                        bar: bar
                        barBg: barBg
                    }

                    // ── divider ──
                    Rectangle {
                        Layout.preferredWidth: bar.dividerThickness
                        Layout.preferredHeight: 18
                        Layout.alignment: Qt.AlignVCenter
                        color: bar.divider
                    }

                    // ─ Clock + Calendar ─
                    ClockPill {
                        bar: bar
                        barBg: barBg
                    }

                    // ── divider ──
                    Rectangle {
                        Layout.preferredWidth: bar.dividerThickness
                        Layout.preferredHeight: 18
                        Layout.alignment: Qt.AlignVCenter
                        color: bar.divider
                    }

                    // ─ Notifications ─
                    NotificationBell {
                        bar: bar
                        notif: notif
                    }

                    // ── divider ──
                    Rectangle {
                        Layout.preferredWidth: bar.dividerThickness
                        Layout.preferredHeight: 18
                        Layout.alignment: Qt.AlignVCenter
                        color: bar.divider
                    }

                    // ─ Power Menu ─
                    PowerMenu {
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
                WorkspacesPill { bar: bar }
            }
        }

        // --- Background services (do not move to zones) ---
        Io.Process {
            id: swayncSub
            running: true
            command: ["swaync-client", "-s", "-sw"]
            stdout: Io.SplitParser {
                splitMarker: "\n"
                onRead: (data) => {
                    const line = data.trim()
                    if (!line) return
                    try {
                        const j = JSON.parse(line)
                        if (typeof j.count === "number") notif.count = j.count
                        if (typeof j.dnd === "boolean") notif.dnd = j.dnd
                        if (typeof j.inhibited === "boolean") notif.inhibited = j.inhibited
                    } catch (e) {}
                }
            }
            onExited: (code) => console.log("swaync subscribe exited with code", code)
        }

        HyprConfigInsp { id: hyprConfigInsp; bar: bar }

        Io.IpcHandler {
            target: "hyprConfigInsp"
            function toggle() {
                if (hyprConfigInsp && hyprConfigInsp.toggle) hyprConfigInsp.toggle()
            }
        }

    }

    // IPC handlers must use explicit types (bool, string, etc.) — `var` is not supported
    Io.IpcHandler {
        target: "shell"
        function setShowMediaWidget(enabled: bool): void {
            root.showMediaWidget = enabled
        }
        function setShowStatsWidget(enabled: bool): void {
            root.showStatsWidget = enabled
        }
        function toggleShowMediaWidget(): void {
            root.showMediaWidget = !root.showMediaWidget
        }
        function toggleShowStatsWidget(): void {
            root.showStatsWidget = !root.showStatsWidget
        }
        function setShowMagicWorkspacePill(enabled: bool): void {
            root.showMagicWorkspacePill = enabled
        }
        function toggleShowMagicWorkspacePill(): void {
            root.showMagicWorkspacePill = !root.showMagicWorkspacePill
        }
    }
}