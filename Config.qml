// Config.qml — Quickshell configuration (theme colors + workspace behavior)
// =============================================================================
// SINGLE SOURCE OF TRUTH — edit this file for bar visuals and workspace defaults.
// (Named Config.qml for QML type registration; referred to as "config" in docs.)
// =============================================================================
//
// Visual properties (colors, sizes, spacing, radii, fonts, icons, slider
// styling, etc.) and workspace behavior defaults live here.
//
// How it works in this config:
//   - shell.qml instantiates Config once and re-exports **every** property as
//     aliases on the root `bar` object (e.g. bar.accent, bar.sliderFill,
//     bar.wsMinimumShown, bar.wsShowSpecialPill, etc.).
//   - Almost all widgets receive `required property var bar` and use `bar.xxx`.
//   - Low-level components (VolumeBar, MiniVolumeBar, CavaVisualizer) read
//     values from `bar` with safe fallbacks so they also stay in sync.
//
// You can also import it directly in new code if you prefer:
//     import "config.qml" as C
//     color: C.Config.accent
//
// (We deliberately avoided a heavy pragma Singleton + qmldir setup because
//  it caused loader conflicts with the existing `Config {}` + alias pattern
//  that the entire bar relies on.)
//
// All properties below are heavily commented with their purpose and consumers.
//
// Categories (search for the headers):
//   - Base palette
//   - Glassmorphic tokens (bar / pill / popup)
//   - State Colors (hover, pressed, active, focus states for consistent interaction feedback)
//   - Radii
//   - Spacing & padding
//   - Sizing (bar, pills, popups, icons)
//   - Fonts (families + sizes)
//   - Icons (glyphs for speaker/mic/power/etc — easy to swap entire icon set)
//   - Sliders & progress (VolumeBar, MiniVolumeBar, seek bars, stat gauges)
//   - Widget visibility (bar pill defaults)
//   - Workspaces (pill behavior, colors, icons, special workspace name)
//   - System stats (CPU/GPU bars + temp thresholds)
//   - Cava visualizer
//   - System monitoring (gauges, poll default, shared tab-chip colors)
//   - Hypr Config Inspector (overlay window, tabs, tables, key/env semantic colors)
//   - Dividers & borders
//   - Popups (generic metrics + internal layout tokens)
//   - Animation & Interaction (durations, easings, tooltip delays)
//   - Enums (menu button types)
//
// Keep this file extremely well commented. Every property must explain:
//   - What it controls
//   - Typical/used values
//   - Which widgets/components consume it
// =============================================================================

import QtQuick

QtObject {
    id: theme

    // =========================================================================
    // BASE PALETTE (Catppuccin Mocha inspired + personal tweaks)
    // =========================================================================
    // These are the fundamental semantic colors. Most other colors derive from
    // or reference these. Avoid using raw hex in widgets — use these or the
    // glass* tokens below.

    readonly property color bg:        "#3B3B3F"   // Main bar background base (rarely used directly due to glass)
    readonly property color surface:   "#313244"   // Slightly lighter panels, buttons, input fields
    readonly property color text:      "#cdd6f4"   // Primary readable text (clock, titles, active labels)
    readonly property color subtext:   "#a6adc8"   // Secondary text (labels, inactive icons)
    readonly property color overlay:   "#6c7086"   // Muted / placeholder / disabled text, help hints

    readonly property color accent:    '#00d3f8'   // Interactive highlights (hover borders, section titles, checkmarks)
    readonly property color muted:     "#f38ba8"   // Muted / warning / error state (volume mute, high temp, DND badge)

    // Semantic / status colors
    readonly property color todayBg:   '#00f7ff'   // Calendar "today" highlight circle
    readonly property color weekday:   "#ff5c5c"   // Calendar weekday headers (M T W ...)
    readonly property color clock:     "#ffffff"   // Clock text (stronger than normal text for readability)

    // =========================================================================
    // GLASSMORPHIC TOKENS (frosted acrylic / mica style)
    // =========================================================================
    // All the translucent layers that give the modern "glass" look.
    // Order of opacity: glassPopup > glassPill > glass (bar background)

    // Main bar background
    readonly property color glassBg:          Qt.rgba(0.08, 0.08, 0.10, 0.52)
    readonly property color glassBorder:      Qt.rgba(1, 1, 1, 0.10)
    readonly property color glassHighlight:   Qt.rgba(1, 0, 0, 0)           // Top edge light (set to low alpha white for classic glass)

    // Pill-style containers (Workspaces, Audio, Clock, Tray, QuickLaunch, SysStats, Media when no media)
    readonly property color glassPillBg:      Qt.rgba(0.06, 0.06, 0.08, 0.75)
    readonly property color glassHover:       Qt.rgba(0.15, 0.15, 0.18, 0.65)  // Hover state for all pills

    // Popups (audio controls, media player, power menu, calendar, tray menus, help)
    // Slightly more opaque + stronger highlight for readability over content
    readonly property color glassPopupBg:         Qt.rgba(0.07, 0.07, 0.09, 0.90)
    readonly property color glassPopupBorder:     Qt.rgba(1, 1, 1, 0.13)
    readonly property color glassPopupHighlight:  Qt.rgba(1, 1, 1, 0.18)

    // Convenience aliases used by many pills (prevents drift)
    readonly property color pillBg:     glassPillBg
    readonly property color pillBorder: Qt.rgba(1, 1, 1, 0.08)
    readonly property color pillHover:  glassHover

    // =========================================================================
    // STATE COLORS (hover, pressed, active, focus — single source of truth)
    // =========================================================================
    // These provide consistent interactive feedback across pills, buttons, and popups.
    // Use these instead of ad-hoc Qt.rgba or hex values for hover/pressed states.

    // Pill-level hover (used by almost every bar widget)
    readonly property color pillHoverBorder: accent   // Border color on hover for all pills

    // General control states (used inside popups and complex widgets)
    readonly property color controlHoverBg:   glassHover                     // Hover background for buttons/controls
    readonly property color controlActiveBg:  Qt.rgba(0.12, 0.12, 0.15, 0.70) // Pressed / toggled / active state

    // Specific popup button hover (replaces previous hardcoded Qt.rgba values in AudioPill/PowerMenu)
    readonly property color popupButtonHoverBg: Qt.rgba(0.10, 0.10, 0.12, 0.55)

    // =========================================================================
    // RADII (corner rounding) — consistency is king
    // =========================================================================
    readonly property int barRadius:       14   // Main bar background rectangle
    readonly property int pillRadius:      10   // All pill containers (most common)
    readonly property int popupRadius:     14   // Default for most popups (audio, calendar, tray, media)
    readonly property int popupRadiusLarge:16   // Power menu, Help overlay
    readonly property int buttonRadius:       6   // Small buttons inside popups (mute, nav, close)
    readonly property int smallButtonRadius:  4   // Very tight buttons (some audio controls)
    readonly property int sliderRadius:       0   // 0 = auto (height/2). Set >0 to force specific rounding on volume bars
    readonly property int workspaceRadius:    8   // Individual workspace buttons

    // Border widths (centralized so we can vary them later if desired)
    readonly property int controlBorderWidth: 1   // Default border for pills, buttons, popup cards

    // =========================================================================
    // SPACING & PADDING
    // =========================================================================
    readonly property int sideMargin:           10   // Left/right margin of the whole bar (outside the glass rect)
    readonly property int barContentHMargin:    20   // Inner left/right padding inside the main bar row
    readonly property int barContentVMargin:     4   // Top/bottom breathing room for the glass rect inside the window
    readonly property int pillHPadding:         18   // Typical horizontal inner padding for pill content (AudioPill etc use this indirectly)
    readonly property int popupPadding:         16   // Generic content margin inside most popups (prefer popupSpacing for new code)
    readonly property int popupPaddingSmall:    10   // Tighter popups (device lists, tray menus) (prefer popupSpacingTight)
    readonly property int widgetSpacing:        14   // Spacing between major widgets in the bar row
    readonly property int iconTextGap:           6   // Gap between icon and volume bar or label inside audio pill
    readonly property int dualAudioSidePadding:  3   // Extra tight padding used only in AudioPill dual view

    // =========================================================================
    // SIZING — BAR, PILLS, POPUPS, ICONS
    // =========================================================================
    // Bar position & size (consumed by shell.qml PanelWindow anchors)
    readonly property string barPosition:  "bottom"    // "top" | "bottom" — which screen edge the bar sits on
    readonly property int barEdgeMargin:      0     // Gap between the bar and the screen edge (top or bottom)
    readonly property int popupBarGap:        4     // Space between bar and pill popups (flips with barPosition)
    readonly property int barHeight:           58   // Bar thickness (height for top/bottom bars)
    readonly property int barTopMargin:  barEdgeMargin   // Legacy alias — prefer barEdgeMargin

    // Pills (uniform height gives the clean segmented look)
    readonly property int pillHeight:          36   // Standard height for every pill in the bar

    // Audio widget (very sensitive — changing these requires testing dual view alignment)
    readonly property int audioViewContentWidth: 172   // Total inner width that speaker+mic+dual views must fit
    readonly property int audioViewSidePadding:    3   // Used only in dual view for left/right micro-padding

    // Icon sizes (nerd font glyphs and tray icons)
    readonly property int iconSizeTray:        18   // System tray — reference size for bar icons
    readonly property int iconSizePill:        iconSizeTray   // Audio, bell, media glyphs in pills
    readonly property int iconSizePillLarge:   iconSizeTray   // Launcher, power menu icon
    readonly property int iconSizePopup:       17   // Icons inside popups (audio controls row)
    readonly property int iconSizePower:       32   // Big icons in the power menu grid
    readonly property int iconSizeMediaArt:    42   // Placeholder music note when no album art
    readonly property int quickLaunchIcon:     20   // Quick launch row icon size

    // Popup implicit sizes (centralized so you can scale the whole UI feel)
    readonly property int popupAudioWidth:     420
    readonly property int popupAudioHeight:    260
    readonly property int popupMediaWidth:     520
    readonly property int popupMediaHeight:    470
    readonly property int popupPowerWidth:     560
    readonly property int popupPowerHeight:    192
    readonly property int popupCalendarWidth:  310
    readonly property int popupCalendarHeight: 280
    readonly property int popupStatsCpuWidth:  598   // SysStatsPill CPU metrics popup width
    readonly property int popupStatsCpuHeight: 700   // SysStatsPill CPU metrics popup height
    readonly property int popupStatsGpuWidth:  598   // SysStatsPill GPU metrics popup width
    readonly property int popupStatsGpuHeight: 700   // SysStatsPill GPU metrics popup height
    // --- SysStatsPill metrics popup position (widgets/SysStatsPill.qml showMetricsPopup)
    // CPU and GPU right-click menus are positioned independently. For each:
    //   anchorX     — horizontal point on the target: 0 = left, 0.5 = center, 1 = right
    //                 (popup is centered on that point, then offset/clamped to the screen)
    //   anchorWholePill — when true, anchor to the full SysStatsPill instead of that half
    //   offsetX/Y   — pixel nudge after anchor math (negative offsetX = left)
    //   barGap      — gap between bar edge and popup (popupAnchorY; flips with barPosition)
    readonly property real popupStatsCpuAnchorX: 0.5
    readonly property bool popupStatsCpuAnchorWholePill: false
    readonly property int popupStatsCpuOffsetX: 100
    readonly property int popupStatsCpuOffsetY: 0
    readonly property int popupStatsCpuBarGap: 2
    readonly property real popupStatsGpuAnchorX: 0.5
    readonly property bool popupStatsGpuAnchorWholePill: false
    readonly property int popupStatsGpuOffsetX: -130
    readonly property int popupStatsGpuOffsetY: 0
    readonly property int popupStatsGpuBarGap: 2
    // Default live polling when a metrics popup opens (persists across reboot via this file).
    readonly property bool popupStatsLiveUpdates: true
    // When true, Pause/Resume choices are saved to state/popup-stats.json and restored after reboot.
    readonly property bool popupStatsPersistPause: false
    readonly property int popupHelpWidth:     1060
    readonly property int popupHelpHeight:     720
    readonly property int popupTrayMaxHeight:  520

    // Popup internal layout tokens (standardizes the repeated glass card patterns)
    readonly property real popupHeaderHighlightHeight: 1.5   // Top light edge on popup glass cards
    readonly property int popupTitleSize:             16    // "Audio Controls", "Power Menu", etc.
    readonly property int popupSectionSize:           13    // "Playback", "Recording", section headers
    readonly property int popupHintSize:              11    // "right-click pill or outside to close"
    readonly property int popupSpacing:               16    // Main content margin inside popups
    readonly property int popupSpacingTight:          10    // Tighter popups (device lists, tray menus)
    readonly property int popupSectionSpacing:         6    // Spacing between sections inside popups

    // =========================================================================
    // WIDGET VISIBILITY (bar pill defaults — IPC can override until qs restart)
    // =========================================================================
    // Consumed by shell.qml on startup; toggled at runtime via qs ipc call shell …
    // Magic pill visibility is separate (wsShowSpecialPill + setShowMagicWorkspacePill).

    readonly property bool showLauncherPill:        true   // Inline app launcher (shell.qml)
    // Shell command run when the launcher pill is clicked (shell.qml passes this to sh -c).
    readonly property string launcherCommand: "~/.local/bin/rofi-app-drawer"
    readonly property string launcherTooltip: "App Launcher"
    readonly property bool showQuickLaunchPill:     true   // QuickLaunchPill.qml
    readonly property bool showMediaPill:           false  // MediaPill.qml (hidden by default)
    readonly property bool showWorkspacesPill:      true   // WorkspacesPill.qml (numbered pills)
    readonly property bool showStatsPill:           true   // SysStatsPill.qml
    readonly property bool showTrayPill:             true   // SystemTrayPill.qml
    readonly property bool showAudioPill:           true   // AudioPill.qml
    readonly property bool showClockPill:           true   // ClockPill.qml
    readonly property bool showNotificationPill:     true   // NotificationBell.qml
    readonly property bool showPowerPill:           true   // PowerMenu.qml

    // =========================================================================
    // FONTS
    // =========================================================================
    readonly property string fontFamily: "Symbols Nerd Font, JetBrains Mono Nerd Font, monospace"
    readonly property string fontMono:   "JetBrains Mono Nerd Font, monospace"

    // Sizes (chosen for ultrawide readability at 58px bar)
    readonly property int fontClock:      15   // Main clock text (bold)
    readonly property int fontPillLabel:  12   // % labels next to volume bars, small text
    readonly property int fontPillLabelBold: 12
    readonly property int fontPopupTitle: 16   // "Audio Controls", "Power Menu", etc. (prefer popupTitleSize for new popup code)
    readonly property int fontSection:    13   // "Playback", "Recording", tab labels (prefer popupSectionSize)
    readonly property int fontBody:       12   // Most body text in popups
    readonly property int fontSmall:      11   // Hints, "click outside to close", tray menu items (prefer popupHintSize)
    readonly property int fontTiny:       10   // Footer hints, help key pills
    readonly property int fontPowerLabel: 12   // Text under big power icons

    // =========================================================================
    // ICON GLYPHS (single place to change the entire icon language)
    // =========================================================================
    // Speaker / volume (MDI — matches mic/tray visual weight; FA glyphs render smaller at same px)
    readonly property string iconSpeaker:       "󰕾"
    readonly property string iconSpeakerMuted:  "󰖁"
    // Microphone
    readonly property string iconMic:           "󰍬"
    readonly property string iconMicMuted:      "󰍭"
    // Power menu
    readonly property string iconPower:         "󰐥"
    readonly property string iconLock:          "󰌾"
    readonly property string iconLogout:        "󰍃"
    readonly property string iconReboot:        "󰑓"
    readonly property string iconShutdown:      "󰐥"
    readonly property string iconBios:          "󰛳"
    // Misc common
    readonly property string iconLauncher:      "󰀻"   // Launcher pill glyph (shell.qml)
    readonly property string iconBell:          "󱅫"
    readonly property string iconBellDnd:       "󰂠"
    readonly property string iconBellEmpty:     "󰂜"

    // =========================================================================
    // SLIDERS & VOLUME BARS (the key user request)
    // =========================================================================
    // These are consumed by VolumeBar.qml and MiniVolumeBar.qml.
    // The components now read these as defaults when you pass `bar` (via the
    // aliases in shell.qml) or when they import the singleton directly.

    // Normal (full) volume bar — used in speaker/mic single views + audio popup
    readonly property int  sliderBarHeight: 6     // Track thickness (VolumeBar default)
    readonly property int  sliderPopupHeight: 8   // Taller version used in the audio popup row

    // Compact dual-view bars (inside AudioPill when both speaker+mic shown)
    readonly property int  sliderMiniHeight: 5

    // Volume bar fallback fill (AudioPill overrides per-level via audioSpeaker/MicUtilColor)
    readonly property color sliderFill:       '#00d3f8' // Default when no threshold binding is set
    readonly property color sliderFillMuted:  muted     // Fill when device is muted
    readonly property color sliderTrack:      surface  // Background track (slightly lighter than glass)

    // AudioPill volume color ramps (25% tiers — speaker and mic tuned independently)
    readonly property int audioUtilThreshold1: 25
    readonly property int audioUtilThreshold2: 50
    readonly property int audioUtilThreshold3: 75

    readonly property color audioSpeakerTier1: "#10B981"   // 0–audioUtilThreshold1%
    readonly property color audioSpeakerTier2: "#F59E0B"   // audioUtilThreshold1+1–audioUtilThreshold2%
    readonly property color audioSpeakerTier3: "#F97316"   // audioUtilThreshold2+1–audioUtilThreshold3%
    readonly property color audioSpeakerTier4: "#EF4444"   // audioUtilThreshold3+1–100%

    readonly property color audioMicTier1: "#10B981"
    readonly property color audioMicTier2: "#F59E0B"
    readonly property color audioMicTier3: "#F97316"
    readonly property color audioMicTier4: "#EF4444"

    // AudioPill speaker/mic glyphs (independent from volume bar + % threshold colors)
    readonly property color audioSpeakerIcon: "#ffffff"   // Unmuted speaker icon (pill + popup)
    readonly property color audioMicIcon:     "#ffffff"   // Unmuted mic icon (pill + popup)
    readonly property color audioSpeakerIconMuted: sliderFillMuted
    readonly property color audioMicIconMuted:     sliderFillMuted

    function audioSpeakerUtilColor(percent) {
        var p = Math.max(0, Math.min(100, percent))
        if (p <= audioUtilThreshold1) return audioSpeakerTier1
        if (p <= audioUtilThreshold2) return audioSpeakerTier2
        if (p <= audioUtilThreshold3) return audioSpeakerTier3
        return audioSpeakerTier4
    }

    function audioMicUtilColor(percent) {
        var p = Math.max(0, Math.min(100, percent))
        if (p <= audioUtilThreshold1) return audioMicTier1
        if (p <= audioUtilThreshold2) return audioMicTier2
        if (p <= audioUtilThreshold3) return audioMicTier3
        return audioMicTier4
    }

    // (sliderRadius is defined in the Radii section above for consistency)

    // =========================================================================
    // WORKSPACES (Hyprland filtered active/occupied pills)
    // =========================================================================
    // Consumed by WorkspacesPill.qml + shell.qml startup via bar.* aliases.
    //
    // Pill display:
    //   wsShowOnlyActive false → always show numbered pills 1..wsMinimumShown
    //   wsShowOnlyActive true  → only occupied/active numbered pills (+ extras)
    //   wsShowSpecialPill      → config default for magic pill (IPC can override at runtime)
    //
    // qs startup (shell.qml):
    //   wsStartupWorkspace 0 → do not change Hyprland workspace on qs start
    //   wsStartupWorkspace N → focus workspace N (after optional magic close)

    readonly property bool wsShowSpecialPill: true    // Magic pill default (toggle via qs ipc call shell setShowMagicWorkspacePill)
    readonly property int  wsMinimumShown: 3           // Default pills 1..N (IPC: qs ipc call shell setWsMinimumShown)
    readonly property bool wsShowOnlyActive: false    // IPC: qs ipc call shell setWsShowOnlyActive
    readonly property int  wsStartupWorkspace: 1       // qs-start focus (0 = unchanged). IPC: setWsStartupWorkspace
    readonly property bool wsStartupCloseMagic: true   // Close magic on qs start. IPC: setWsStartupCloseMagic

    readonly property color wsHoverYellow: "#fdf9db"           // Hover from original eww migration
    readonly property color wsActiveBg:    Qt.rgba(0.53, 0.69, 0.96, 0.22)  // Active workspace glass
    readonly property color wsActiveBorder: Qt.rgba(0.53, 0.69, 0.96, 0.6)
    readonly property color wsActiveText:  "#e0e7ff"
    readonly property color wsInactiveText: clock   // Falls back to bar.clock in delegate

    // Legacy names some older code paths may still reference
    readonly property color wsText:        "#64748b"
    readonly property color wsActiveTextLegacy: wsActiveText   // (the alias in shell.qml maps wsActiveText → this)

    readonly property int  wsButtonWidth:   42
    readonly property int  wsButtonHeight:  32
    readonly property int  wsIconSize:      iconSizeTray
    readonly property int  wsNumberSize:    15
    readonly property int  wsSpacing:        4     // Between workspace buttons

    // --- Per-workspace pill icons (edit here to remap without touching widget logic)
    // Nerd Font glyphs for most slots; Unicode emoji where noted for color/readability.
    readonly property string wsIcon1:        ""     // Code / dev
    readonly property string wsIcon2:        ""     // Browser
    readonly property string wsIcon3:        "🕹"     // Game (color emoji)
    readonly property string wsIcon4:        ""     // Misc
    readonly property string wsIcon5:        ""     // Misc
    readonly property string wsIcon6:        ""     // Misc
    readonly property string wsIcon7:        ""     // Misc
    readonly property string wsIcon8:        "󰈸"     // Misc
    readonly property string wsIcon9:        "󰈸"     // Misc
    readonly property string wsIcon10:       "󰈸"     // Misc
    readonly property string wsIconDefault:  "󰈸"     // Fallback for unmapped workspace ids

    // Icon picker reference — copy any glyph into wsIcon1…wsIcon10 or wsIconSpecial:
    //   Coding / dev:     💻 🖥️ ⌨️ 🧑‍💻 📟 🛠️ ⚙️ 🔧 🐛 🧪
    //   Browsers:         🌐 🦁 🔍 🦊 🌍 📡
    //   Editors / IDE:   󰨞 📝 ✏️ 📋 📄 🗒️ 💾
    //   Terminal:         ⌨️ 📟
    //   Chat / social:    💬 📱 📧 🗨️
    //   Media:           🎵 🎧 🎬 📺 🎮 🕹
    //   Files / misc:    📁 🗂️  󰈹 󰈸 🔥 ⭐ ✨ 🪄

    // --- Hyprland special workspace (negative id; toggled via Super+S in keybindings.lua)
    // wsSpecialName must match hl.dsp.workspace.toggle_special('<name>') and special:<name> moves.
    readonly property string wsSpecialName:  "magic"
    readonly property string wsIconSpecial:  "🪄"     // Magic space — colorful emoji, icon-only pill

    // Resolve the icon glyph/emoji for a numbered Hyprland workspace id.
    function wsIconForId(id) {
        switch (id) {
            case 1:  return wsIcon1;
            case 2:  return wsIcon2;
            case 3:  return wsIcon3;
            case 4:  return wsIcon4;
            case 5:  return wsIcon5;
            case 6:  return wsIcon6;
            case 7:  return wsIcon7;
            case 8:  return wsIcon8;
            case 9:  return wsIcon9;
            case 10: return wsIcon10;
            default: return wsIconDefault;
        }
    }

    // True when a Hyprland workspace name refers to the configured special workspace.
    function wsIsSpecialName(name) {
        if (!name || name.length === 0) return false;
        return name === wsSpecialName || name === ("special:" + wsSpecialName);
    }

    // =========================================================================
    // SYSTEM STATS GAUGES (CPU / GPU utilization bars + temp labels)
    // =========================================================================
    readonly property int  statGaugeWidth:   73     // Visual bar width inside SysStatsPill
    readonly property int  statGaugeHeight:   8
    readonly property int  statGaugeRadius:   4
    readonly property color statTrack:       Qt.rgba(1, 1, 1, 0.09)  // Very subtle track

    // Utilization bar color ramp (25% tiers — edit colors and thresholds together)
    readonly property color statUtilTier1: "#10B981"   // 0–statUtilThreshold1%
    readonly property color statUtilTier2: "#F59E0B"   // statUtilThreshold1+1–statUtilThreshold2%
    readonly property color statUtilTier3: "#F97316"   // statUtilThreshold2+1–statUtilThreshold3%
    readonly property color statUtilTier4: "#EF4444"   // statUtilThreshold3+1–100%

    readonly property int statUtilThreshold1: 25
    readonly property int statUtilThreshold2: 50
    readonly property int statUtilThreshold3: 75

    // Temperature text colors (independent from utilization ramp)
    readonly property color statTempCool: "#cdd6f4"   // Below statTempWarmAt
    readonly property color statTempWarm: "#f9e2af"   // statTempWarmAt–statTempHotAt
    readonly property color statTempHot:  "#f38ba8"   // Above statTempHotAt

    // Temperature label thresholds (°C)
    readonly property int statTempWarmAt: 70
    readonly property int statTempHotAt:  85

    // "|" between utilization % and temperature in SysStatsPill
    readonly property color statValueSeparator: overlay

    function statUtilColor(util) {
        var u = Math.max(0, Math.min(100, util))
        if (u <= statUtilThreshold1) return statUtilTier1
        if (u <= statUtilThreshold2) return statUtilTier2
        if (u <= statUtilThreshold3) return statUtilTier3
        return statUtilTier4
    }

    function statTempColor(temp) {
        var t = Math.round(temp)
        if (t > statTempHotAt)  return statTempHot
        if (t > statTempWarmAt) return statTempWarm
        return statTempCool
    }

    // =========================================================================
    // CAVA VISUALIZER (MediaPill background waveform)
    // =========================================================================
    readonly property int  cavaBarCount:     40
    readonly property int  cavaBarGap:        1
    readonly property color cavaInactive:    Qt.rgba(1, 1, 1, 0.18)
    readonly property color cavaActive:      Qt.rgba(0.55, 0.71, 0.98, 0.35)
    readonly property int  cavaAnimFast:     95   // ms when media playing
    readonly property int  cavaAnimSlow:    420   // ms when idle (saves CPU)

    // =========================================================================
    // SYSTEM MONITORING (SysMonService + HyprConfigInsp sysmon tabs)
    // =========================================================================
    // Shared tokens for live metrics in HyprConfigInsp (CPU/GPU/Memory/Temperature tabs)
    // and reusable gauge/sparkline components.
    //
    // Consumed by:
    //   - widgets/SysMonService.qml (pollInterval default kept in sync by convention)
    //   - widgets/HyprConfigInsp.qml + components/*MonitorView.qml
    //   - components/CircularGauge.qml, Sparkline.qml
    //
    // Notes:
    //   - pollInterval is owned by SysMonService at runtime (default 1500 ms).
    //   - panelTabActive* is reused by HyprConfigInsp tab chips (inspTabActive* aliases).
    // =========================================================================

    // Poll rate default (ms). SysMonService hardcodes 1500 to match; change both if tuning.
    readonly property int sysmonDefaultPollInterval: 1500

    // Shared active-tab chip style (HyprConfigInsp tab bar)
    readonly property color panelTabActiveBg:   Qt.rgba(0.55, 0.70, 0.96, 0.18)
    readonly property color panelTabActiveBorder: accent

    // Gauge color ramp for CircularGauge (CPU/GPU/memory/temp). <65% / 65–85% / >85%
    readonly property color gaugeLow:  "#a6e3a1"
    readonly property color gaugeMid:  "#f9e2af"
    readonly property color gaugeHigh: "#f38ba8"

    // =========================================================================
    // HYPR CONFIG INSPECTOR (HyprConfigInsp.qml floating overlay)
    // =========================================================================
    // Visual tokens for the tabbed Hyprland config / sysmon inspector window.
    // Reuses popupHelpWidth/Height for default size; panelTabActive* for tab chips.
    //
    // Consumed by:
    //   - widgets/HyprConfigInsp.qml (primary)
    //
    // How to extend:
    //   - Add a property here, alias it in HyprConfigInsp via `th.xxx`, use in UI.
    //   - Semantic color helpers (envValueColor) live in config so other tools can reuse.
    // =========================================================================

    // --- Window geometry (FloatingWindow defaults + resize limits)
    // popupHelpWidth/Height are the default inspector size (1060×720).
    readonly property int inspMinWidth:  560
    readonly property int inspMinHeight: 400
    readonly property int inspContentPadding: 18      // inner margin around the whole layout
    readonly property int inspSectionSpacing: 12      // vertical gap between header/tabs/content/footer

    // --- Window background (inspector-only — does NOT affect audio/power/calendar popups)
    // Defaults mirror glassPopup* so the out-of-box look is unchanged.
    //
    // Solid mode (default):
    //   inspUseGradient = false  →  contentPanel uses inspWindowBg
    //
    // Gradient mode:
    //   inspUseGradient = true   →  vertical fade inspGradientTop → inspGradientBottom
    //   (inspWindowBg is ignored while gradient is active)
    //
    // Example — subtle dark vertical fade:
    //   inspUseGradient: true
    //   inspGradientTop: Qt.rgba(0.10, 0.10, 0.14, 0.93)
    //   inspGradientBottom: Qt.rgba(0.05, 0.05, 0.08, 0.96)
    readonly property color inspWindowBg:         glassPopupBg
    readonly property color inspWindowBorder:     glassPopupBorder
    readonly property color inspWindowHighlight:  glassPopupHighlight
    readonly property bool  inspUseGradient:      false
    readonly property color inspGradientTop:      glassPopupBg
    readonly property color inspGradientBottom:   Qt.rgba(0.05, 0.05, 0.08, 0.94)

    // --- Tab bar (wrapping Flow of chips + vertical scrollbar when many tabs)
    readonly property int inspTabBarMaxHeight: 102
    readonly property int inspTabHeight:       30
    readonly property int inspTabRadius:        7
    readonly property int inspTabHPadding:     28    // added to label width for chip width
    readonly property int inspTabSpacing:         6
    readonly property int inspTabFontSize:     13
    // Active tab reuses panelTabActive* tokens (shared tab-chip style)
    readonly property color inspTabActiveBg:      panelTabActiveBg
    readonly property color inspTabActiveBorder:  panelTabActiveBorder
    readonly property color inspTabHoverBg:       surface

    // --- Global search field (right of tab bar)
    readonly property int inspSearchWidth:   220
    readonly property int inspSearchHeight:   28        
    readonly property int inspSearchRadius:    6
    readonly property int inspSearchPadding:   4
    readonly property int inspSearchFontSize:   12          //14
    readonly property color inspSearchSelectionBg: Qt.rgba(0.55, 0.70, 0.96, 0.35)

    // --- Header (title row, version/distro, keyboard hints)
    readonly property int inspTitleFontSize:    18
    readonly property int inspSubtitleFontSize: 13
    readonly property int inspHeaderButtonHeight: 28
    readonly property int inspRefreshButtonWidth: 78
    readonly property int inspCloseButtonSize:    28
    readonly property color inspHeaderDivider: divider

    // --- Footer (status line + action chips: Copy, Refresh, Edit)
    readonly property int inspStatusFontSize: 12
    readonly property int inspFooterButtonHeight: 22
    readonly property int inspFooterButtonRadius:  5
    readonly property int inspFooterButtonSpacing: 6

    // --- Scrollbars (tab bar + content Flickables)
    readonly property int inspScrollBarWidth:  6
    readonly property int inspScrollBarRadius: 3
    readonly property color inspScrollBarIdle: Qt.rgba(1, 1, 1, 0.2)

    // --- List/table row interaction (binds, env, system info rows)
    readonly property color inspRowHoverBg:       Qt.rgba(1, 1, 1, 0.03)
    readonly property color inspRowHoverBgStrong: Qt.rgba(1, 1, 1, 0.06)  // system info values
    readonly property int inspRowRadius: 4
    readonly property int inspBindRowHeight: 26
    readonly property int inspEnvRowHeight:  28
    readonly property int inspEnvHeaderHeight: 28

    // --- Environment variable table layout
    readonly property int inspEnvTableSideMargin: 10
    readonly property int inspEnvTableColSpacing: 12
    readonly property int inspEnvVarColMinWidth:  180
    readonly property int inspEnvVarColMaxWidth:  260
    readonly property real inspEnvVarColRatio:    0.22   // fraction of usable width for Variable column
    readonly property int inspEnvValueColMinWidth: 180
    readonly property int inspEnvValueColMaxWidth: 340
    readonly property real inspEnvValueColRatio:   0.28   // fraction of usable width for Value column
    readonly property int inspEnvDescColMinWidth:  320    // minimum width for Description column

    // --- Key binding modifier pills (Catppuccin semantic colors)
    readonly property color inspKeyPillSuper:   "#89b4fa"
    readonly property color inspKeyPillShift:   "#fab387"
    readonly property color inspKeyPillCtrl:    "#cba6f7"
    readonly property color inspKeyPillAlt:    "#94e2d5"
    readonly property color inspKeyPillDefault: overlay
    readonly property color inspKeyPillTextOnDark:  "#ffffff"
    readonly property color inspKeyPillTextOnLight: "#000000"
    readonly property int inspKeyPillHeight: 20
    readonly property int inspKeyPillRadius:  5
    readonly property int inspKeyPillHPadding: 12
    readonly property int inspKeyPillFontSize: 11

    // --- Environment variable semantic colors (keys + values)
    readonly property color inspEnvKeyHighlight: "#94e2d5"   // graphics/wayland-related keys
    readonly property color inspEnvValueTrue:      "#a6e3a1"   // 1, true, enabled
    readonly property color inspEnvValueFalse:     "#fab387"   // 0, false, disabled
    readonly property color inspEnvValueTech:      "#89dceb"   // nvidia, wayland, opengl, direct
    readonly property color inspEnvValuePath:      subtext      // filesystem paths
    readonly property color inspEnvValueTheme:     "#cba6f7"   // theme/platform strings
    readonly property color inspEnvValueTerminal:  "#89b4fa"   // TERMINAL, hyprland refs

    // Prefixes that mark an env *key* as graphics/wayland-related (highlighted in Variable column)
    readonly property var inspEnvHighlightPrefixes: [
        "__GL", "__NV", "__VK", "GBM_", "NVD_", "LIBVA_", "AQ_", "GDK_", "QT_",
        "SDL_", "XDG_", "MOZ_", "ELECTRON_", "CLUTTER_", "HYPRCURSOR", "XCURSOR"
    ]

    function inspKeyPillColor(key) {
        var k = (key || "").toUpperCase().trim()
        if (k.indexOf("SUPER") !== -1 || k.indexOf("WIN") !== -1 || k.indexOf("META") !== -1) return inspKeyPillSuper
        if (k.indexOf("SHIFT") !== -1) return inspKeyPillShift
        if (k.indexOf("CTRL") !== -1 || k.indexOf("CONTROL") !== -1) return inspKeyPillCtrl
        if (k.indexOf("ALT") !== -1) return inspKeyPillAlt
        return inspKeyPillDefault
    }

    function inspKeyPillTextColor(key) {
        return inspKeyPillColor(key) === inspKeyPillDefault ? inspKeyPillTextOnDark : inspKeyPillTextOnLight
    }

    function inspEnvKeyIsHighlight(key) {
        var k = (key || "").toUpperCase()
        if (!k) return false
        for (var i = 0; i < inspEnvHighlightPrefixes.length; i++) {
            if (k.indexOf(inspEnvHighlightPrefixes[i]) === 0) return true
        }
        return k.indexOf("WAYLAND") !== -1
    }

    function inspEnvKeyColor(key) {
        return inspEnvKeyIsHighlight(key) ? inspEnvKeyHighlight : accent
    }

    function inspEnvValueColor(key, value) {
        var v = (value || "").trim()
        var lower = v.toLowerCase()
        var k = (key || "").toUpperCase()

        if (lower === "1" || lower === "true" || lower === "enabled") return inspEnvValueTrue
        if (lower === "0" || lower === "false" || lower === "disabled") return inspEnvValueFalse

        if (inspEnvKeyIsHighlight(key) || lower.indexOf("nvidia") !== -1 || lower.indexOf("wayland") !== -1
                || lower.indexOf("opengl") !== -1 || lower === "direct" || lower.indexOf("nvidia_only") !== -1) {
            return inspEnvValueTech
        }

        if (v.indexOf("/") === 0 || v.indexOf("~") === 0 || v.indexOf("/dev/") !== -1) {
            return inspEnvValuePath
        }

        if (k.indexOf("THEME") !== -1 || k.indexOf("PLATFORMTHEME") !== -1
                || lower.indexOf("bibata") !== -1 || lower === "qt6ct" || lower === "auto"
                || lower === "arch-") {
            return inspEnvValueTheme
        }

        if (k === "TERMINAL" || lower.indexOf("hyprland") !== -1) return inspEnvValueTerminal

        return text
    }

    // =========================================================================
    // DIVIDERS & SUBTLE LINES
    // =========================================================================
    readonly property color divider:         Qt.rgba(1, 1, 1, 0.12)   // Standard subtle divider
    readonly property color dividerSubtle:   Qt.rgba(1, 1, 1, 0.06)   // Very faint divider (e.g. between minor elements)
    readonly property color dividerStrong:   "#45475a"                // Used in popups for section lines
    readonly property int  dividerThickness: 1

    // =========================================================================
    // TRAY MENU (SystemTrayPill check/radio rows)
    // =========================================================================
    readonly property color menuCheckMark:     text    // ✓ / ● glyphs (not accent — avoids purple GTK clash)
    readonly property color menuUncheckedMark: overlay // ○ / empty radio ring
    readonly property color menuCheckedRow:  Qt.rgba(0, 0.83, 0.97, 0.10)  // subtle highlight on checked items

    // =========================================================================
    // TRAY MENU BUTTON TYPE ENUMS (mirror of QsMenuButtonType for safety)
    // =========================================================================
    readonly property int menuBtnNone:  0
    readonly property int menuBtnCheck: 1
    readonly property int menuBtnRadio: 2

    // =========================================================================
    // ANIMATION & INTERACTION TOKENS
    // =========================================================================
    // Centralized durations and delays for consistent feel across the bar.
    // Recommended easing for most UI motion: Easing.OutQuad (used in existing Behaviors).

    readonly property int animFast:   90    // Quick feedback (Cava bars, small state changes)
    readonly property int animMedium: 140   // Standard hover / color transitions (WorkspacesPill)
    readonly property int animSlow:   220   // Slower, more noticeable motion

    // Interaction delays
    readonly property int tooltipDelay: 1550   // ms before showing tooltips (used by ToolTip components)

    // =========================================================================
    // Z-LAYERS (only the global ones that matter across components)
    // =========================================================================
    readonly property int zMediaPill:  5
    readonly property int zSysStats:   5
    // Most other z usage is local (z: -1 for click-eaters)

    // =========================================================================
    // CONVENIENCE / DERIVED (rarely need editing)
    // =========================================================================
    readonly property int popupY: barHeight + 2   // Standard y offset under the bar for popups
}
