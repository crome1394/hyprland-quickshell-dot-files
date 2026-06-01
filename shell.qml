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
// =============================================================================
// shell.qml — Main Quickshell entry point for the Hyprland status bar
// =============================================================================
//
// This file is intentionally kept small. All widget logic lives in:
//   - widgets/*.qml     (self-contained pills and menus)
//   - components/*.qml  (reusable low-level pieces like VolumeBar, CavaVisualizer)
//   - Theme.qml         (single source of truth for colors and metrics)
//   - widgets/HelpMenu.qml (the rich centered help overlay)
//
// The bar uses a glassmorphic / frosted acrylic aesthetic with Catppuccin-inspired colors.
//
// IPC integration:
//   - `qs ipc call help toggle` opens the HelpMenu (bound in hyprland.lua)
//
// See the git history for the incremental extraction process (one widget at a time).
// =============================================================================
ShellRoot {
    // The main bar window. All visual widgets live inside or as siblings under this.
    PanelWindow {
        id: bar
        anchors.top: true
        anchors.left: true
        anchors.right: true
        implicitHeight: bar.barHeight
        color: "transparent"
        margins.top: bar.barTopMargin
        // ===== THEME (single source of truth — see Theme.qml) =====
        // This is the ONLY place visual properties should live.
        // Theme.qml is a pragma Singleton + qmldir registered module.
        //
        // We instantiate it here (harmless with singleton) and then alias
        // EVERY property onto this PanelWindow as `bar.xxx`. This gives us:
        //   - Perfect backward compatibility for all existing widgets
        //   - One place to edit → instant global effect
        //   - Widgets stay clean: they just do `required property var bar`
        //
        // New code can also do: import "Theme.qml" as T;  T.Theme.accent
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
        property alias tempOk: theme.tempOk
        property alias tempWarm: theme.tempWarm
        property alias tempHot: theme.tempHot

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

        // --- State Colors (new in this refactor)
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
        // New popup internal tokens (preferred for new code)
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

        // --- Sizing
        readonly property alias barHeight: theme.barHeight
        readonly property alias barTopMargin: theme.barTopMargin
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

        // Popup sizes
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

        // --- Icon glyphs (change the icon language in one place)
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

        // --- Sliders (VolumeBar + MiniVolumeBar) — this is the main user request
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

        // --- System stats gauges
        readonly property alias statGaugeWidth: theme.statGaugeWidth
        readonly property alias statGaugeHeight: theme.statGaugeHeight
        readonly property alias statGaugeRadius: theme.statGaugeRadius
        readonly property alias statTrack: theme.statTrack
        readonly property alias statOk: theme.statOk
        readonly property alias statWarm: theme.statWarm
        readonly property alias statHot: theme.statHot

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

        // --- Animation & Interaction (new in this refactor)
        readonly property alias animFast: theme.animFast
        readonly property alias animMedium: theme.animMedium
        readonly property alias animSlow: theme.animSlow
        readonly property alias tooltipDelay: theme.tooltipDelay

        // --- Enums (menu button types)
        readonly property alias menuBtnNone: theme.menuBtnNone
        readonly property alias menuBtnCheck: theme.menuBtnCheck
        readonly property alias menuBtnRadio: theme.menuBtnRadio

        // --- Z layers
        readonly property alias zMediaPill: theme.zMediaPill
        readonly property alias zSysStats: theme.zSysStats

        // Legacy ws* aliases (some very old references in comments or forks)
        readonly property alias wsText: theme.wsText
        // ===== GLOBAL NOTIFICATION STATE =====
        // Shared state for the NotificationBell widget. Updated by the swaync subscribe process below.
        // Kept as a small QtObject here so it can be passed into the widget.
        QtObject {
            id: notif
            property int count: 0
            property bool dnd: false
            property bool inhibited: false
            // icon computed from state (using common nerd font bell glyphs)
            readonly property string icon: {
                if (dnd) return notif.count > 0 ? "󰂠" : "󰪓";  // dnd variants
                return notif.count > 0 ? "󱅫" : "󰂜";            // normal bell
            }
        }
        Component.onCompleted: {
            // audio.refreshDevices() moved into AudioPill.qml (self-contained now)
            // Media initialization also lives inside widgets/MediaPill.qml
        }
        // (Media logic + its 1.5s rescan Timer have been moved into widgets/MediaPill.qml)

        // ===== Bar Content =====
        // Glassmorphic styling throughout bar + all popups (frosted acrylic style)
        // (Easy to revert - the glass* properties control most of it)
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

            // Stronger top light edge for classic glassmorphism
            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: bar.popupHeaderHighlightHeight
                color: bar.glassHighlight
                radius: parent.radius
            }

            // Very subtle bottom inner shadow for depth
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
                spacing: bar.widgetSpacing

                // Left side - Workspaces (from eww migration: icons+num, only active/occupied,
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
                        onClicked: {
                            Quickshell.execDetached(["sh", "-c", "~/.local/bin/rofi-app-drawer"])
                        }
                    }

                    ToolTip.text: "App Launcher"
                    ToolTip.visible: launcherMouse.containsMouse
                    ToolTip.delay: 1750
                }

                // Subtle modern vertical divider
                Rectangle {
                    Layout.preferredWidth: bar.dividerThickness
                    Layout.preferredHeight: 18
                    Layout.alignment: Qt.AlignVCenter
                    color: bar.divider
                }

                WorkspacesPill {
                    bar: bar
                }

                Item { Layout.fillWidth: true }

                // ===== QUICK LAUNCH APPS (encapsulated pill, left of system tray) =====
                QuickLaunchPill {
                    bar: bar
                }

                // Subtle modern vertical divider
                Rectangle {
                    Layout.preferredWidth: bar.dividerThickness
                    Layout.preferredHeight: 18
                    Layout.alignment: Qt.AlignVCenter
                    color: bar.divider
                }

                // ===== SYSTEM TRAY (right side, left of volume widget, pill style, comfortable spacing, efficient reactive) =====
                SystemTrayPill {
                    bar: bar
                    barBg: barBg
                }

                // Subtle modern vertical divider
                Rectangle {
                    Layout.preferredWidth: bar.dividerThickness
                    Layout.preferredHeight: 18
                    Layout.alignment: Qt.AlignVCenter
                    color: bar.divider
                }

                AudioPill {
                    bar: bar
                    barBg: barBg
                }

                // Subtle modern vertical divider
                Rectangle {
                    Layout.preferredWidth: bar.dividerThickness
                    Layout.preferredHeight: 18
                    Layout.alignment: Qt.AlignVCenter
                    color: bar.divider
                }

                // ===== CLOCK + CALENDAR (coupled pair) =====
                ClockPill {
                    bar: bar
                    barBg: barBg
                }

                // Subtle modern vertical divider
                Rectangle {
                    Layout.preferredWidth: bar.dividerThickness
                    Layout.preferredHeight: 18
                    Layout.alignment: Qt.AlignVCenter
                    color: bar.divider
                }

                // ===== NOTIFICATION BELL (right of clock, swaync backed) =====
                NotificationBell {
                    
                    bar: bar
                    notif: notif
                }

                // Subtle modern vertical divider (between notifications and power menu)
                Rectangle {
                    Layout.preferredWidth: bar.dividerThickness
                    Layout.preferredHeight: 18
                    Layout.alignment: Qt.AlignVCenter
                    color: bar.divider
                }

                // ===== POWER / SESSION MENU (right of notification bell) =====
                PowerMenu {
                    bar: bar
                    barBg: barBg
                }
        }
    }
    MediaPill {
        id: mediaPill
        bar: bar
        barBg: barBg
    }
    SysStatsPill {
        bar: bar
        barBg: barBg
        mediaActive: mediaPill.hasMedia
    }
    // ===== SWAYNC SUBSCRIBE (event-driven state for bell) =====
    // Long-lived process. swaync-client pushes a JSON line only on relevant changes
    // (new notif, close, dnd toggle, etc.). No timers, no polling, very cheap.
    // Parses simple output from `swaync-client -s -sw`:
    //   { "count": N, "dnd": bool, "visible": bool, "inhibited": bool }
    Io.Process {
        id: swayncSub
        running: true
        command: ["swaync-client", "-s", "-sw"]
        stdout: Io.SplitParser {
            splitMarker: "\n"
            onRead: (data) => {
                // SplitParser emits one chunk per splitMarker (we still trim + guard for safety)
                const line = data.trim();
                if (!line) return;
                try {
                    const j = JSON.parse(line);
                    if (typeof j.count === 'number') {
                        notif.count = j.count;
                    }
                    if (typeof j.dnd === 'boolean') {
                        notif.dnd = j.dnd;
                    }
                    if (typeof j.inhibited === 'boolean') {
                        notif.inhibited = j.inhibited;
                    }
                } catch (e) {
                    // ignore malformed lines (initial handshake or noise)
                }
            }
        }
        onExited: (code) => {
            // If swaync isn't running or client dies, keep trying (Quickshell will restart component on reload)
            // For robustness you could add a short restart Timer here if desired.
            console.log("swaync subscribe exited with code", code);
        }
    }

    // ===== Hyprland Help Menu (polished version from ~/.config/quickshell-help) =====
    // Centered floating panel with colored key pills, env vars, and rich System Info
    // (fastfetch + clickable copy-to-clipboard + logo).
    // Toggled via IPC:  qs ipc call help toggle   (wire to a key in hyprland.lua)
    HelpMenu { id: helpMenu; bar: bar }

    Io.IpcHandler {
        target: "help"
        function toggle() {
            if (helpMenu && helpMenu.toggle) {
                helpMenu.toggle()
            }
        }
    }
}

// End of ShellRoot
// All top-level items (PanelWindow bar + floating components like HelpMenu) live inside this.
}
