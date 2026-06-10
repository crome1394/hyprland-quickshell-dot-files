// Theme.qml
// =============================================================================
// SINGLE SOURCE OF TRUTH — Quickshell Visual Theme (CachyOS + Hyprland)
// =============================================================================
//
// All visual properties (colors, sizes, spacing, radii, fonts, icons, slider
// styling, etc.) live here. This is the ONLY file you should edit for theming.
//
// How it works in this config:
//   - shell.qml instantiates Theme once and re-exports **every** property as
//     aliases on the root `bar` object (e.g. bar.accent, bar.sliderFill,
//     bar.iconSpeaker, bar.popupRadius, bar.fontClock, etc.).
//   - Almost all widgets receive `required property var bar` and use `bar.xxx`.
//     This gives perfect global theming with zero prop-drilling pain.
//   - Low-level components (VolumeBar, MiniVolumeBar, CavaVisualizer) read
//     values from `bar` with safe fallbacks so they also stay in sync.
//
// You can also import it directly in new code if you prefer:
//     import "Theme.qml" as T
//     color: T.Theme.accent
//
// (We deliberately avoided a heavy pragma Singleton + qmldir setup because
//  it caused loader conflicts with the existing `Theme {}` + alias pattern
//  that the entire bar relies on. The "instantiated once at the root +
//  massive alias list" approach gives the same practical benefit.)
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
//   - Workspaces
//   - System stats (CPU/GPU bars + temp thresholds)
//   - Cava visualizer
//   - Sysmon Panel (side panel geometry, radii, poll options, colors)
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
    readonly property string iconLauncher:      "󰀻"
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
    // SYSMON PANEL (side-mounted System Monitor / System Info panel for Hyprland)
    // =========================================================================
    // Everything visual for SysmonPanel.qml and its cards must come from here.
    // PanelWindow is positioned via anchors driven by panelPosition (edit here or extend
    // for runtime switch). Rounded corners ONLY on inner (non-border) edges.
    //
    // Consumed by:
    //   - widgets/SysmonPanel.qml (size, radius, position, margins, colors, poll options)
    //   - widgets/SysMonService.qml (reads default poll interval)
    //
    // Notes:
    //   - panelPosition affects adaptive margins + which radii are zeroed (flat on monitor edge).
    //   - pollInterval is owned by the *service* at runtime; these are only defaults + UI options.
    //   - Keep additions here organized; extend this section for any new panel visuals.
    // =========================================================================

    // --- Panel geometry (width/height for the side panel; height may be constrained by screen + margins)
    readonly property int panelWidth:  560   // total window width for right/left panels 460
    readonly property int panelHeight: 720   // preferred; actual may use screen height - margins 720

    // Corner radius applied only to the "inner" corners (e.g. left corners for a right panel)
    readonly property int panelRadius: 12

    // Supported positions (string). "right" is the primary for this rice.
    // The panel code adapts anchors + radii + margins based on this value.
    readonly property string panelPosition: "right"   // "left" | "right" | "bottom"

    // Generous breathing-room from screen edges. Applied as PanelWindow margins
    // (top/bottom for vertical side panels; left/right for bottom panels).
    readonly property int panelMargin:        8
    readonly property int panelMarginTop:    300    //36
    readonly property int panelMarginBottom: 36   //36
    readonly property int panelMarginSide:   12   // extra side inset if desired for bottom pos

    // Poll rate (ms). Default 1500. SysMonService owns the live value (hardcoded to match
    // this default for simplicity; UI only reads + assigns on user change). The service
    // does not read this at runtime to keep its imports self-contained.
    readonly property int sysmonDefaultPollInterval: 1500

    // Discrete poll speed options shown in the Monitor view control (kept small & simple).
    // Order is as presented in the UI chips.
    readonly property var sysmonPollOptions: [500, 1000, 1500, 2000, 3000, 5000]

    // --- Panel colors (reuse glass tokens where possible; add panel-specific here for isolation)
    readonly property color panelBg:        glassPopupBg          // main panel container background
    readonly property color panelBorder:    glassPopupBorder
    readonly property color panelHighlight: glassPopupHighlight   // top light edge

    // Inner cards (CPU/GPU/Memory/etc boxes) - slightly different from popup glass for density
    readonly property color panelCardBg:     Qt.rgba(0.10, 0.10, 0.12, 0.92)
    readonly property color panelCardBorder: Qt.rgba(1, 1, 1, 0.06)

    // Tab / header controls inside panel
    readonly property color panelTabActiveBg:   Qt.rgba(0.55, 0.70, 0.96, 0.18)
    readonly property color panelTabActiveBorder: accent

    // Status text colors (errors vs normal)
    readonly property color panelStatusText: text
    readonly property color panelErrorText:  muted

    // Gauge color ramp for CircularGauge (CPU/GPU/disk etc). Centralized here so
    // all dashboards and future gauges stay consistent. (Used as defaults in component.)
    readonly property color gaugeLow:  "#a6e3a1"   // <65%
    readonly property color gaugeMid:  "#f9e2af"   // 65-85%
    readonly property color gaugeHigh: "#f38ba8"   // >85%

    // Sysmon tab content area (fixed to prevent layout shift when switching tabs)
    readonly property int sysmonTabContentHeight: 650
    readonly property int sysmonPillMargin: 8
    readonly property int sysmonPillRadius: 8

    // --- Panel card / inner element sizing (kept modest to avoid over-theming a first cut)
    readonly property int panelCardRadius: 8
    readonly property int panelCardHeaderSize: 12
    readonly property int panelCardBodySize: 18
    readonly property int panelCardSmallSize: 10
    readonly property int panelCardTinySize: 8
    readonly property int panelCardLabelSize: 9

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
