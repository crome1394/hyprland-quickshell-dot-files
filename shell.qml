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
//   - HelpMenu.qml      (the rich centered help overlay)
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
        implicitHeight: 54   // Increased for ultrawide readability (was 46)
        color: "transparent"

        // ===== Theme (centralized — see Theme.qml) =====
        // Single source of truth. All values (including glassmorphic tokens,
        // workspace colors, pill metrics, and audio widget sizing) live in Theme.qml.
        // The aliases below provide 100% backward compatibility so widgets can keep
        // using `bar.accent`, `bar.pillRadius`, etc. without changes.
        Theme { id: theme }

        property alias bg: theme.bg
        property alias surface: theme.surface
        property alias text: theme.text
        property alias subtext: theme.subtext
        property alias overlay: theme.overlay
        property alias accent: theme.accent
        property alias todayBg: theme.todayBg
        property alias weekday: theme.weekday
        property alias clock: theme.clock
        property alias muted: theme.muted
        property alias barRadius: theme.barRadius
        property alias sideMargin: theme.sideMargin

        readonly property alias glassBg: theme.glassBg
        readonly property alias glassBorder: theme.glassBorder
        readonly property alias glassHighlight: theme.glassHighlight
        readonly property alias glassPillBg: theme.glassPillBg
        readonly property alias glassHover: theme.glassHover
        readonly property alias glassPopupBg: theme.glassPopupBg
        readonly property alias glassPopupBorder: theme.glassPopupBorder
        readonly property alias glassPopupHighlight: theme.glassPopupHighlight

        readonly property alias menuBtnNone: theme.menuBtnNone
        readonly property alias menuBtnCheck: theme.menuBtnCheck
        readonly property alias menuBtnRadio: theme.menuBtnRadio

        readonly property alias wsHoverYellow: theme.wsHoverYellow
        readonly property alias wsActiveBg: theme.wsActiveBg
        readonly property alias wsText: theme.wsText
        readonly property alias wsActiveText: theme.wsActiveText

        readonly property alias pillBg: theme.pillBg
        readonly property alias pillBorder: theme.pillBorder
        readonly property alias pillRadius: theme.pillRadius

        readonly property alias audioViewContentWidth: theme.audioViewContentWidth
        readonly property alias audioViewSidePadding: theme.audioViewSidePadding


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
        audio.refreshDevices();
        // Media initialization (refreshPlayers + browser nodes) now lives inside
        // widgets/MediaPill.qml so the component is fully self-contained.
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
        anchors.topMargin: 4
        anchors.bottomMargin: 4
        radius: bar.barRadius
        color: bar.glassBg
        border.width: 1
        border.color: bar.glassBorder

        // Stronger top light edge for classic glassmorphism
        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1.5
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
            anchors.leftMargin: 20   // Slightly more breathing room for ultrawide
            anchors.rightMargin: 20
            spacing: 14

            // Left side - Workspaces (from eww migration: icons+num, only active/occupied,

            Rectangle {
                id: launcherPill
                Layout.preferredWidth: 42
                Layout.preferredHeight: 36
                radius: bar.pillRadius
                color: launcherMouse.containsMouse ? bar.glassHover : bar.pillBg
                border.width: 1
                border.color: launcherMouse.containsMouse ? bar.accent : bar.pillBorder

                Text {
                    anchors.centerIn: parent
                    text: "󰀻"   // Change this icon if you want (see note below)
                    font.pixelSize: 18
                    font.family: "Symbols Nerd Font, JetBrains Mono Nerd Font, monospace"
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
                ToolTip.delay: 500
            }

            // Subtle modern vertical divider
            Rectangle {
                Layout.preferredWidth: 1
                Layout.preferredHeight: 18
                Layout.alignment: Qt.AlignVCenter
                color: Qt.rgba(1, 1, 1, 0.12)
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
                Layout.preferredWidth: 1
                Layout.preferredHeight: 18
                Layout.alignment: Qt.AlignVCenter
                color: Qt.rgba(1, 1, 1, 0.12)
            }

            // ===== SYSTEM TRAY (right side, left of volume widget, pill style, comfortable spacing, efficient reactive) =====
            SystemTrayPill {
                bar: bar
                barBg: barBg
            }

            // Subtle modern vertical divider
            Rectangle {
                Layout.preferredWidth: 1
                Layout.preferredHeight: 18
                Layout.alignment: Qt.AlignVCenter
                color: Qt.rgba(1, 1, 1, 0.12)
            }

            AudioPill {
                bar: bar
                barBg: barBg
            }

            // Subtle modern vertical divider
            Rectangle {
                Layout.preferredWidth: 1
                Layout.preferredHeight: 18
                Layout.alignment: Qt.AlignVCenter
                color: Qt.rgba(1, 1, 1, 0.12)
            }

            // ===== CLOCK + CALENDAR (coupled pair) =====
            ClockPill {
                bar: bar
                barBg: barBg
            }

            // ===== NOTIFICATION BELL (right of clock, swaync backed) =====
            NotificationBell {
                bar: bar
                notif: notif
            }

            // Subtle modern vertical divider (between notifications and power menu)
            Rectangle {
                Layout.preferredWidth: 1
                Layout.preferredHeight: 18
                Layout.alignment: Qt.AlignVCenter
                color: Qt.rgba(1, 1, 1, 0.12)
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
}

// ===== Hyprland Help Menu (polished version from ~/.config/quickshell-help) =====
// Centered floating panel with colored key pills, env vars, and rich System Info
// (fastfetch + clickable copy-to-clipboard + logo).
// Toggled via IPC:  qs ipc call help toggle   (wire to a key in hyprland.lua)
HelpMenu { id: helpMenu }

Io.IpcHandler {
    target: "help"

    function toggle() {
        if (helpMenu && helpMenu.toggle) {
            helpMenu.toggle()
        }
    }
}
}
