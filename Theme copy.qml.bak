// Theme.qml
// Single source of truth for all bar + popup colors, glassmorphic tokens,
// workspace styling, pill metrics, and audio widget sizing.
//
// This was extracted from the original monolithic shell.qml during the
// incremental modularization (see plan.md).
//
// Usage in shell.qml (during transition):
//     Theme { id: theme }
//     property alias accent: theme.accent   // etc. for full backward compat
//
// In newly extracted widgets you can do either:
//     required property var bar
//     ... use bar.accent ...          (works via the aliases on bar)
// or pass the theme explicitly and use theme.accent directly.
//
// Keeping the values here prevents drift (e.g. HelpMenu.qml had its own copy).

import QtQuick

QtObject {
    // ===== Theme (Catppuccin-inspired dark) =====
    property color bg: "#3B3B3F"
    property color surface: "#313244"
    property color text: "#cdd6f4"
    property color subtext: "#a6adc8"
    property color overlay: "#6c7086"
    property color accent: "#89b4fa"
    property color todayBg: "#89b4fa"
    property color weekday: "#ff5c5c"
    property color clock: "#ffffff"
    property color muted: "#f38ba8"
    property int barRadius: 14
    property int sideMargin: 10

    // ===== Glassmorphic Theme =====
    // Frosted glass / acrylic style for a more premium, modern look
    readonly property color glassBg: Qt.rgba(0.08, 0.08, 0.10, 0.82)
    readonly property color glassBorder: Qt.rgba(1, 1, 1, 0.10)
    readonly property color glassHighlight: Qt.rgba(1, 1, 1, 0.22)
    readonly property color glassPillBg: Qt.rgba(0.06, 0.06, 0.08, 0.75)
    readonly property color glassHover: Qt.rgba(0.15, 0.15, 0.18, 0.65)

    // Dedicated glassmorphic popup styling (slightly more opaque than the bar for readability)
    readonly property color glassPopupBg: Qt.rgba(0.07, 0.07, 0.09, 0.90)
    readonly property color glassPopupBorder: Qt.rgba(1, 1, 1, 0.13)
    readonly property color glassPopupHighlight: Qt.rgba(1, 1, 1, 0.18)

    // Tray menu button type enums (safe local mirrors of QsMenuButtonType)
    readonly property int menuBtnNone: 0
    readonly property int menuBtnCheck: 1
    readonly property int menuBtnRadio: 2

    // ===== Workspaces (eww migration) =====
    // Yellow hover shade taken from eww working scss (rgb(253, 249, 219))
    readonly property color wsHoverYellow: "#fdf9db"
    readonly property color wsActiveBg: "#1e1e1e"
    readonly property color wsText: "#64748b"
    readonly property color wsActiveText: "#e2e8f0"

    // Glassmorphic pill defaults (translucent backgrounds + light borders)
    readonly property color pillBg: glassPillBg
    readonly property color pillBorder: Qt.rgba(1, 1, 1, 0.08)
    readonly property int pillRadius: 10

    // Fixed content width for audio widget (speaker/mic/dual all produce identical pill size).
    // Dual view speaker icon is positioned to line up exactly with speaker view.
    // Dual uses left+right anchoring + side padding so it truly spans the full inner width.
    readonly property int audioViewContentWidth: 172
    readonly property int audioViewSidePadding: 3
}
