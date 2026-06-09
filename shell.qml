// =============================================================================
// shell.qml — Main Quickshell entry point for the Hyprland status bar
// =============================================================================
//
// Widget logic lives in:
//   - widgets/*.qml      (self-contained pills and menus)
//   - components/*.qml   (reusable pieces like VolumeBar, CavaVisualizer)
//   - Theme.qml          (colors, spacing, and metrics)
//   - widgets/HelpMenu.qml (centered help overlay)
//
// IPC:
//   - qs ipc call help toggle
//   - qs ipc call shell setShowMediaWidget true
//   - qs ipc call shell setShowStatsWidget false
//   - qs ipc call shell toggleShowMediaWidget
//   - qs ipc call shell toggleShowStatsWidget
//   (Run `qs ipc show` to list all registered commands.)
//
// Bar position (Theme.qml):
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

        // --- Theme (single source of truth — see Theme.qml) ---
        Theme { id: theme }

        // --- Base palette
        property alias bg: theme.bg
        property alias surface: theme.surface
        property alias text: theme.text
        property alias subtext: theme.subtext
        property alias overlay: theme.overlay
        property alias accent: theme.accent
        property alias muted: theme.muted
        property alias todayBg: theme.todayBg
        property alias weekday: theme.weekday
        property alias clock: theme.clock
        readonly property alias statTempCool: theme.statTempCool
        readonly property alias statTempWarm: theme.statTempWarm
        readonly property alias statTempHot: theme.statTempHot
        readonly property alias statValueSeparator: theme.statValueSeparator

        // --- Glassmorphic tokens
        readonly property alias glassBg: theme.glassBg
        readonly property alias glassBorder: theme.glassBorder
        readonly property alias glassHighlight: theme.glassHighlight
        readonly property alias glassPillBg: theme.glassPillBg
        readonly property alias glassHover: theme.glassHover
        readonly property alias glassPopupBg: theme.glassPopupBg
        readonly property alias glassPopupBorder: theme.glassPopupBorder
        readonly property alias glassPopupHighlight: theme.glassPopupHighlight
        readonly property alias pillBg: theme.pillBg
        readonly property alias pillBorder: theme.pillBorder
        readonly property alias pillHover: theme.pillHover

        // --- State colors
        readonly property alias pillHoverBorder: theme.pillHoverBorder
        readonly property alias controlHoverBg: theme.controlHoverBg
        readonly property alias controlActiveBg: theme.controlActiveBg
        readonly property alias popupButtonHoverBg: theme.popupButtonHoverBg

        // --- Radii
        property alias barRadius: theme.barRadius
        property alias pillRadius: theme.pillRadius
        property alias popupRadius: theme.popupRadius
        property alias popupRadiusLarge: theme.popupRadiusLarge
        property alias buttonRadius: theme.buttonRadius
        property alias smallButtonRadius: theme.smallButtonRadius
        property alias sliderRadius: theme.sliderRadius
        property alias workspaceRadius: theme.workspaceRadius
        readonly property alias controlBorderWidth: theme.controlBorderWidth

        // --- Spacing & padding
        property alias sideMargin: theme.sideMargin
        readonly property alias barContentHMargin: theme.barContentHMargin
        readonly property alias barContentVMargin: theme.barContentVMargin
        readonly property alias pillHPadding: theme.pillHPadding
        readonly property alias popupPadding: theme.popupPadding
        readonly property alias popupPaddingSmall: theme.popupPaddingSmall
        readonly property alias popupHeaderHighlightHeight: theme.popupHeaderHighlightHeight
        readonly property alias popupTitleSize: theme.popupTitleSize
        readonly property alias popupSectionSize: theme.popupSectionSize
        readonly property alias popupHintSize: theme.popupHintSize
        readonly property alias popupSpacing: theme.popupSpacing
        readonly property alias popupSpacingTight: theme.popupSpacingTight
        readonly property alias popupSectionSpacing: theme.popupSectionSpacing
        readonly property alias widgetSpacing: theme.widgetSpacing
        readonly property alias iconTextGap: theme.iconTextGap
        readonly property alias dualAudioSidePadding: theme.dualAudioSidePadding

        // --- Sizing & bar position
        readonly property alias barPosition: theme.barPosition
        readonly property alias barEdgeMargin: theme.barEdgeMargin
        readonly property alias popupBarGap: theme.popupBarGap
        readonly property alias barHeight: theme.barHeight
        readonly property alias barTopMargin: theme.barTopMargin

        // Popup Y anchor — opens below the bar (top) or above it (bottom)
        function popupAnchorY(popupHeight, gap) {
            var spacing = (gap !== undefined) ? gap : popupBarGap
            return barPosition === "bottom" ? -popupHeight - spacing : implicitHeight + spacing
        }
        readonly property alias pillHeight: theme.pillHeight
        readonly property alias audioViewContentWidth: theme.audioViewContentWidth
        readonly property alias audioViewSidePadding: theme.audioViewSidePadding
        readonly property alias iconSizePill: theme.iconSizePill
        readonly property alias iconSizePillLarge: theme.iconSizePillLarge
        readonly property alias iconSizePopup: theme.iconSizePopup
        readonly property alias iconSizePower: theme.iconSizePower
        readonly property alias iconSizeMediaArt: theme.iconSizeMediaArt
        readonly property alias iconSizeTray: theme.iconSizeTray
        readonly property alias quickLaunchIcon: theme.quickLaunchIcon

        // --- Popup sizes
        readonly property alias popupAudioWidth: theme.popupAudioWidth
        readonly property alias popupAudioHeight: theme.popupAudioHeight
        readonly property alias popupMediaWidth: theme.popupMediaWidth
        readonly property alias popupMediaHeight: theme.popupMediaHeight
        readonly property alias popupPowerWidth: theme.popupPowerWidth
        readonly property alias popupPowerHeight: theme.popupPowerHeight
        readonly property alias popupCalendarWidth: theme.popupCalendarWidth
        readonly property alias popupCalendarHeight: theme.popupCalendarHeight
        readonly property alias popupHelpWidth: theme.popupHelpWidth
        readonly property alias popupHelpHeight: theme.popupHelpHeight

        // --- Fonts
        readonly property alias fontFamily: theme.fontFamily
        readonly property alias fontMono: theme.fontMono
        readonly property alias fontClock: theme.fontClock
        readonly property alias fontPillLabel: theme.fontPillLabel
        readonly property alias fontPopupTitle: theme.fontPopupTitle
        readonly property alias fontSection: theme.fontSection
        readonly property alias fontBody: theme.fontBody
        readonly property alias fontSmall: theme.fontSmall
        readonly property alias fontTiny: theme.fontTiny

        // --- Icon glyphs
        readonly property alias iconSpeaker: theme.iconSpeaker
        readonly property alias iconSpeakerMuted: theme.iconSpeakerMuted
        readonly property alias iconMic: theme.iconMic
        readonly property alias iconMicMuted: theme.iconMicMuted
        readonly property alias iconPower: theme.iconPower
        readonly property alias iconLock: theme.iconLock
        readonly property alias iconLogout: theme.iconLogout
        readonly property alias iconReboot: theme.iconReboot
        readonly property alias iconShutdown: theme.iconShutdown
        readonly property alias iconBios: theme.iconBios
        readonly property alias iconLauncher: theme.iconLauncher
        readonly property alias audioIcon: theme.audioIcon

        // --- Sliders
        readonly property alias sliderBarHeight: theme.sliderBarHeight
        readonly property alias sliderPopupHeight: theme.sliderPopupHeight
        readonly property alias sliderMiniHeight: theme.sliderMiniHeight
        readonly property alias sliderFill: theme.sliderFill
        readonly property alias sliderFillMuted: theme.sliderFillMuted
        readonly property alias sliderTrack: theme.sliderTrack

        // --- Workspaces
        readonly property alias wsHoverYellow: theme.wsHoverYellow
        readonly property alias wsActiveBg: theme.wsActiveBg
        readonly property alias wsActiveBorder: theme.wsActiveBorder
        readonly property alias wsActiveText: theme.wsActiveText
        readonly property alias wsInactiveText: theme.wsInactiveText
        readonly property alias wsButtonWidth: theme.wsButtonWidth
        readonly property alias wsButtonHeight: theme.wsButtonHeight
        readonly property alias wsIconSize: theme.wsIconSize
        readonly property alias wsNumberSize: theme.wsNumberSize
        readonly property alias wsSpacing: theme.wsSpacing
        readonly property alias wsText: theme.wsText

        // --- System stats gauges
        readonly property alias statGaugeWidth: theme.statGaugeWidth
        readonly property alias statGaugeHeight: theme.statGaugeHeight
        readonly property alias statGaugeRadius: theme.statGaugeRadius
        readonly property alias statTrack: theme.statTrack
        readonly property alias statUtilTier1: theme.statUtilTier1
        readonly property alias statUtilTier2: theme.statUtilTier2
        readonly property alias statUtilTier3: theme.statUtilTier3
        readonly property alias statUtilTier4: theme.statUtilTier4
        readonly property alias statUtilThreshold1: theme.statUtilThreshold1
        readonly property alias statUtilThreshold2: theme.statUtilThreshold2
        readonly property alias statUtilThreshold3: theme.statUtilThreshold3
        readonly property alias statTempWarmAt: theme.statTempWarmAt
        readonly property alias statTempHotAt: theme.statTempHotAt
        function statUtilColor(util) { return theme.statUtilColor(util) }
        function statTempColor(temp) { return theme.statTempColor(temp) }

        // --- Cava visualizer
        readonly property alias cavaBarCount: theme.cavaBarCount
        readonly property alias cavaBarGap: theme.cavaBarGap
        readonly property alias cavaInactive: theme.cavaInactive
        readonly property alias cavaActive: theme.cavaActive
        readonly property alias cavaAnimFast: theme.cavaAnimFast
        readonly property alias cavaAnimSlow: theme.cavaAnimSlow

        // --- Dividers
        readonly property alias divider: theme.divider
        readonly property alias dividerStrong: theme.dividerStrong
        readonly property alias dividerThickness: theme.dividerThickness
        readonly property alias dividerSubtle: theme.dividerSubtle

        // --- Animation & interaction
        readonly property alias animFast: theme.animFast
        readonly property alias animMedium: theme.animMedium
        readonly property alias animSlow: theme.animSlow
        readonly property alias tooltipDelay: theme.tooltipDelay

        // --- Tray menu
        readonly property alias menuCheckMark: theme.menuCheckMark
        readonly property alias menuUncheckedMark: theme.menuUncheckedMark
        readonly property alias menuCheckedRow: theme.menuCheckedRow
        readonly property alias menuBtnNone: theme.menuBtnNone
        readonly property alias menuBtnCheck: theme.menuBtnCheck
        readonly property alias menuBtnRadio: theme.menuBtnRadio

        // --- Z layers
        readonly property alias zMediaPill: theme.zMediaPill
        readonly property alias zSysStats: theme.zSysStats

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
                            text: bar.icMediaPillonLauncher
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

        HelpMenu { id: helpMenu; bar: bar }

        Io.IpcHandler {
            target: "help"
            function toggle() {
                if (helpMenu && helpMenu.toggle) helpMenu.toggle()
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
    }
}