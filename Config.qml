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
//   - QUICK LAUNCH (pinned app icons and launch commands)
//   - NOTIFICATION BELL (notification daemon CLI commands for the bell)
//   - POWER MENU (lock / logout / reboot / shutdown / BIOS commands)
//   - KILL TARGET PILL (click-to-kill window picker)
//   - Workspaces (pill behavior, colors, icons, special workspace name)
//   - SYS STATS PILL (CPU | Memory | GPU bar pill size, gauges, temp colors)
//   - SysStats metrics popups (right-click dropdown size/position per section)
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
    // BASE PALETTE (liquid glass — cool dark-blue slate + vivid teal accent)
    // =========================================================================
    // Pulled from the CachyOS / Ventoy desktop wallpaper: deep magenta→pink field,
    // cool blue ribbons, and the installer logo's teal→cyan gradient (pushed
    // brighter/more saturated). Glass chrome is cool blue-slate (not purple, not
    // washed mid-grey) so teal accents and wallpaper blues stay cohesive.
    //
    // Hierarchy:
    //   bg/surface  → solid blue-slate fallbacks (elevated UI, tracks)
    //   glass*      → translucent dark-blue glass (bar / pills / popups)
    //   accent      → bright teal-cyan (active, hover border, highlights)
    //   muted       → vivid magenta-pink (secondary accent + warnings / mute / DND)

    // Writable so the control-bar Colors panel can edit live and persist.
    // Factory defaults live in themeFactoryDefaults() / themeReset().
    property color bg:        "#0a0e16"   // Deep blue-charcoal (solid fallback)
    property color surface:   "#141a24"   // Elevated blue-slate panels / tracks
    property color text:      "#f0f4fc"   // Bright cool-white (high contrast on glass)
    property color subtext:   "#a8b4c8"   // Cool silver-blue secondary labels
    property color overlay:   "#6e7a90"   // Muted blue-grey (not flat mid-grey)

    property color accent:    "#00F0E0"   // Vivid teal-cyan (active / hover / highlights)
    property color muted:     "#FF3D8A"   // Magenta-pink secondary + warning / mute / DND

    // Semantic / status colors
    property color todayBg:   "#00FFE8"   // Calendar "today" (extra-bright cyan)
    property color weekday:   "#FF5C9A"   // Calendar weekday headers (pink secondary)
    property color clock:     "#ffffff"   // Clock text (max contrast)

    // =========================================================================
    // GLASSMORPHIC TOKENS (liquid glass — frosted dark-blue slate + teal edges)
    // =========================================================================
    // Semi-transparent fills so the wallpaper tint shows through. Soft teal rim
    // glow + white top-edge sheen sell the glossy glass look. Opacity order:
    //   glassBg (bar) < glassPill < glassPopup  (popups most opaque for readability)
    // Writable for Colors panel live editing.

    // Main bar — cool dark-blue glass, wallpaper peeks through
    property color glassBg:          Qt.rgba(0.04, 0.06, 0.10, 0.58)
    // Soft cool rim (desaturated — not a vivid teal neon edge)
    property color glassBorder:      Qt.rgba(0.55, 0.72, 0.82, 0.16)
    // Top-edge light catch — transparent so the bar has no thin highlight strip
    property color glassHighlight:   "transparent"

    // Pills — slightly denser glass so content stays sharp
    property color glassPillBg:      Qt.rgba(0.05, 0.07, 0.12, 0.72)
    property color glassHover:       Qt.rgba(0.0, 0.85, 0.80, 0.22)  // Teal glow on hover

    // Popups — more opaque for readability, still blue-slate glass
    property color glassPopupBg:         Qt.rgba(0.04, 0.06, 0.10, 0.90)
    property color glassPopupBorder:     Qt.rgba(0.55, 0.72, 0.82, 0.18)
    property color glassPopupHighlight:  Qt.rgba(1, 1, 1, 0.18)

    // Convenience aliases used by many pills (prevents drift)
    // pillBg / pillHover track glass* so one Colors control updates both.
    property color pillBg:     glassPillBg
    property color pillBorder: Qt.rgba(1, 1, 1, 0.10)  // Soft glass rim; hover uses accent
    property color pillHover:  glassHover

    // =========================================================================
    // STATE COLORS (hover, pressed, active, focus — single source of truth)
    // =========================================================================
    // These provide consistent interactive feedback across pills, buttons, and popups.
    // Use these instead of ad-hoc Qt.rgba or hex values for hover/pressed states.

    // Pill-level hover (used by almost every bar widget)
    property color pillHoverBorder: accent   // Border color on hover for all pills

    // Per-item hover chips — translucent teal glow (QuickLaunch, tray, workspaces, …)
    property color iconHoverBg: Qt.rgba(0.0, 0.85, 0.82, 0.28)

    // General control states (used inside popups and complex widgets)
    property color controlHoverBg:   glassHover
    property color controlActiveBg:  Qt.rgba(0.0, 0.70, 0.75, 0.35)  // Pressed / toggled teal

    // Specific popup button hover
    property color popupButtonHoverBg: Qt.rgba(0.08, 0.10, 0.16, 0.65)

    // =========================================================================
    // THEME EDITOR API (control-bar Colors panel — non-coder friendly)
    // =========================================================================
    // Keys exposed in the UI map 1:1 to properties above. Derived tokens
    // (sliderFill, wsActiveBorder, …) stay bound to accent/muted/etc.

    readonly property var themeEditableKeys: [
        "glassBg", "glassPillBg", "glassPopupBg",
        "glassBorder", "glassPopupBorder", "pillBorder",
        "glassHighlight", "glassPopupHighlight",
        "glassHover", "iconHoverBg",
        "accent", "muted",
        "text", "subtext", "overlay",
        "bg", "surface", "clock",
        "controlActiveBg", "popupButtonHoverBg"
    ]

    // Friendly rows shown in the Colors panel (label + property key + opacity?).
    readonly property var themeUiRows: [
        { key: "glassBg",     label: "Bar background",    opacity: true },
        { key: "glassPillBg", label: "Widget background", opacity: true },
        { key: "glassPopupBg",label: "Menu background",   opacity: true },
        { key: "glassBorder", label: "Border",            opacity: true },
        { key: "accent",      label: "Accent",            opacity: false },
        { key: "muted",       label: "Warning / pink",    opacity: false },
        { key: "text",        label: "Main text",         opacity: false },
        { key: "subtext",     label: "Secondary text",    opacity: false },
        { key: "glassHover",  label: "Hover glow",        opacity: true },
        { key: "glassHighlight", label: "Top edge shine", opacity: true }
    ]

    function _clamp01(n) {
        var x = Number(n)
        if (!(x >= 0)) x = 0
        if (x > 1) x = 1
        return x
    }

    function _byteHex(n) {
        var v = Math.round(_clamp01(n) * 255)
        if (v < 0) v = 0
        if (v > 255) v = 255
        var s = v.toString(16)
        return s.length < 2 ? ("0" + s) : s
    }

    function colorToHex(c) {
        if (!c) return "#000000"
        return "#" + _byteHex(c.r) + _byteHex(c.g) + _byteHex(c.b)
    }

    function parseHex(hex) {
        if (!hex) return null
        var s = ("" + hex).trim()
        if (s.charAt(0) === "#") s = s.substring(1)
        if (s.length === 3) {
            s = s.charAt(0) + s.charAt(0) + s.charAt(1) + s.charAt(1) + s.charAt(2) + s.charAt(2)
        }
        if (s.length !== 6) return null
        var r = parseInt(s.substring(0, 2), 16)
        var g = parseInt(s.substring(2, 4), 16)
        var b = parseInt(s.substring(4, 6), 16)
        if (isNaN(r) || isNaN(g) || isNaN(b)) return null
        return { r: r / 255, g: g / 255, b: b / 255 }
    }

    function colorWithAlpha(c, a) {
        if (!c) return Qt.rgba(0, 0, 0, _clamp01(a))
        return Qt.rgba(c.r, c.g, c.b, _clamp01(a))
    }

    function colorFromHexAlpha(hex, a) {
        var p = parseHex(hex)
        if (!p) return null
        return Qt.rgba(p.r, p.g, p.b, _clamp01(a === undefined ? 1 : a))
    }

    function colorToThemeEntry(c) {
        return { hex: colorToHex(c), alpha: c ? _clamp01(c.a) : 1 }
    }

    function themeEntryToColor(entry) {
        if (!entry) return null
        if (typeof entry === "string")
            return colorFromHexAlpha(entry, 1)
        var hex = entry.hex !== undefined ? entry.hex : entry.color
        var a = entry.alpha !== undefined ? entry.alpha : 1
        return colorFromHexAlpha(hex, a)
    }

    function getThemeColor(key) {
        switch (key) {
        case "bg": return bg
        case "surface": return surface
        case "text": return text
        case "subtext": return subtext
        case "overlay": return overlay
        case "accent": return accent
        case "muted": return muted
        case "todayBg": return todayBg
        case "weekday": return weekday
        case "clock": return clock
        case "glassBg": return glassBg
        case "glassBorder": return glassBorder
        case "glassHighlight": return glassHighlight
        case "glassPillBg": return glassPillBg
        case "glassHover": return glassHover
        case "glassPopupBg": return glassPopupBg
        case "glassPopupBorder": return glassPopupBorder
        case "glassPopupHighlight": return glassPopupHighlight
        case "pillBorder": return pillBorder
        case "iconHoverBg": return iconHoverBg
        case "controlActiveBg": return controlActiveBg
        case "popupButtonHoverBg": return popupButtonHoverBg
        default: return null
        }
    }

    function setThemeColor(key, c) {
        if (!c) return false
        switch (key) {
        case "bg": bg = c; break
        case "surface": surface = c; break
        case "text": text = c; break
        case "subtext": subtext = c; break
        case "overlay": overlay = c; break
        case "accent": accent = c; pillHoverBorder = c; break
        case "muted": muted = c; break
        case "todayBg": todayBg = c; break
        case "weekday": weekday = c; break
        case "clock": clock = c; break
        case "glassBg": glassBg = c; break
        case "glassBorder":
            glassBorder = c
            // Keep popup rim in sync for the simple "Border" control
            glassPopupBorder = colorWithAlpha(c, Math.max(c.a, 0.18))
            break
        case "glassHighlight": glassHighlight = c; break
        case "glassPillBg": glassPillBg = c; pillBg = c; break
        case "glassHover":
            glassHover = c
            pillHover = c
            controlHoverBg = c
            // Keep icon hover chips in the same family (slightly stronger)
            iconHoverBg = colorWithAlpha(c, Math.min(1, Math.max(0.15, c.a + 0.06)))
            break
        case "glassPopupBg": glassPopupBg = c; break
        case "glassPopupBorder": glassPopupBorder = c; break
        case "glassPopupHighlight": glassPopupHighlight = c; break
        case "pillBorder": pillBorder = c; break
        case "iconHoverBg": iconHoverBg = c; break
        case "controlActiveBg": controlActiveBg = c; break
        case "popupButtonHoverBg": popupButtonHoverBg = c; break
        default: return false
        }
        return true
    }

    function setThemeAlpha(key, a) {
        var cur = getThemeColor(key)
        if (!cur) return false
        // Top-edge shine defaults to transparent black — use white when turning on
        if ((key === "glassHighlight" || key === "glassPopupHighlight")
                && cur.a < 0.01 && a > 0.01
                && cur.r < 0.02 && cur.g < 0.02 && cur.b < 0.02) {
            return setThemeColor(key, Qt.rgba(1, 1, 1, _clamp01(a)))
        }
        return setThemeColor(key, colorWithAlpha(cur, a))
    }

    function themeExport(name) {
        var colors = {}
        var keys = themeEditableKeys
        for (var i = 0; i < keys.length; i++) {
            var k = keys[i]
            var c = getThemeColor(k)
            if (c)
                colors[k] = colorToThemeEntry(c)
        }
        return {
            name: name && ("" + name).length ? ("" + name) : "Custom",
            version: 1,
            colors: colors
        }
    }

    function themeApply(obj) {
        if (!obj) return false
        var colors = obj.colors !== undefined ? obj.colors : obj
        if (!colors || typeof colors !== "object") return false
        var keys = themeEditableKeys
        var any = false
        for (var i = 0; i < keys.length; i++) {
            var k = keys[i]
            if (colors[k] === undefined) continue
            var c = themeEntryToColor(colors[k])
            if (c && setThemeColor(k, c))
                any = true
        }
        // Re-sync alias-style props after bulk apply
        pillBg = glassPillBg
        pillHover = glassHover
        controlHoverBg = glassHover
        pillHoverBorder = accent
        return any
    }

    function themeFactoryDefaults() {
        return {
            name: "Liquid glass",
            version: 1,
            colors: {
                bg: { hex: "#0a0e16", alpha: 1 },
                surface: { hex: "#141a24", alpha: 1 },
                text: { hex: "#f0f4fc", alpha: 1 },
                subtext: { hex: "#a8b4c8", alpha: 1 },
                overlay: { hex: "#6e7a90", alpha: 1 },
                accent: { hex: "#00F0E0", alpha: 1 },
                muted: { hex: "#FF3D8A", alpha: 1 },
                todayBg: { hex: "#00FFE8", alpha: 1 },
                weekday: { hex: "#FF5C9A", alpha: 1 },
                clock: { hex: "#ffffff", alpha: 1 },
                glassBg: { hex: "#0a0f1a", alpha: 0.58 },
                glassBorder: { hex: "#8cb8d1", alpha: 0.16 },
                glassHighlight: { hex: "#000000", alpha: 0 },
                glassPillBg: { hex: "#0d121e", alpha: 0.72 },
                glassHover: { hex: "#00d9cc", alpha: 0.22 },
                glassPopupBg: { hex: "#0a0f1a", alpha: 0.90 },
                glassPopupBorder: { hex: "#8cb8d1", alpha: 0.18 },
                glassPopupHighlight: { hex: "#ffffff", alpha: 0.18 },
                pillBorder: { hex: "#ffffff", alpha: 0.10 },
                iconHoverBg: { hex: "#00d9d1", alpha: 0.28 },
                controlActiveBg: { hex: "#00b3bf", alpha: 0.35 },
                popupButtonHoverBg: { hex: "#141a29", alpha: 0.65 }
            }
        }
    }

    function themePresetSolidDark() {
        return {
            name: "Solid dark",
            version: 1,
            colors: {
                bg: { hex: "#000000", alpha: 1 },
                surface: { hex: "#121416", alpha: 1 },
                text: { hex: "#ececee", alpha: 1 },
                subtext: { hex: "#b0b0b2", alpha: 1 },
                overlay: { hex: "#5c5c60", alpha: 1 },
                accent: { hex: "#00c4f5", alpha: 1 },
                muted: { hex: "#e85d6f", alpha: 1 },
                todayBg: { hex: "#00d4ff", alpha: 1 },
                weekday: { hex: "#e85d6f", alpha: 1 },
                clock: { hex: "#ffffff", alpha: 1 },
                glassBg: { hex: "#000000", alpha: 1 },
                glassBorder: { hex: "#1e2024", alpha: 1 },
                glassHighlight: { hex: "#000000", alpha: 0 },
                glassPillBg: { hex: "#0a0c0e", alpha: 1 },
                glassHover: { hex: "#16181c", alpha: 1 },
                glassPopupBg: { hex: "#000000", alpha: 1 },
                glassPopupBorder: { hex: "#121416", alpha: 1 },
                glassPopupHighlight: { hex: "#000000", alpha: 0 },
                pillBorder: { hex: "#0a0c0e", alpha: 1 },
                iconHoverBg: { hex: "#0a3a48", alpha: 1 },
                controlActiveBg: { hex: "#16181c", alpha: 1 },
                popupButtonHoverBg: { hex: "#121416", alpha: 1 }
            }
        }
    }

    function themePresetSoftGrey() {
        return {
            name: "Soft grey",
            version: 1,
            colors: {
                bg: { hex: "#1a1b1e", alpha: 1 },
                surface: { hex: "#25262b", alpha: 1 },
                text: { hex: "#e8e8ec", alpha: 1 },
                subtext: { hex: "#a0a4b0", alpha: 1 },
                overlay: { hex: "#6c7080", alpha: 1 },
                accent: { hex: "#7ec8e3", alpha: 1 },
                muted: { hex: "#e88a9a", alpha: 1 },
                todayBg: { hex: "#8ad4f0", alpha: 1 },
                weekday: { hex: "#e88a9a", alpha: 1 },
                clock: { hex: "#ffffff", alpha: 1 },
                glassBg: { hex: "#1a1b1e", alpha: 0.72 },
                glassBorder: { hex: "#ffffff", alpha: 0.10 },
                glassHighlight: { hex: "#ffffff", alpha: 0.12 },
                glassPillBg: { hex: "#22242a", alpha: 0.80 },
                glassHover: { hex: "#7ec8e3", alpha: 0.18 },
                glassPopupBg: { hex: "#1a1b1e", alpha: 0.92 },
                glassPopupBorder: { hex: "#ffffff", alpha: 0.12 },
                glassPopupHighlight: { hex: "#ffffff", alpha: 0.14 },
                pillBorder: { hex: "#ffffff", alpha: 0.08 },
                iconHoverBg: { hex: "#7ec8e3", alpha: 0.22 },
                controlActiveBg: { hex: "#7ec8e3", alpha: 0.28 },
                popupButtonHoverBg: { hex: "#2a2c32", alpha: 0.70 }
            }
        }
    }

    function themeReset() {
        return themeApply(themeFactoryDefaults())
    }

    function themeBuiltinPresets() {
        return [
            themeFactoryDefaults(),
            themePresetSolidDark(),
            themePresetSoftGrey()
        ]
    }

    // =========================================================================
    // UI SCALE (auto from screen width + optional manual override)
    // =========================================================================
    // Base sizes below were designed around a wide desktop (~2560+ logical px).
    // shell.qml sets uiScale / screenWidth / screenHeight at runtime:
    //   • uiScaleManual == 0  → auto: clamp(screenWidth / uiDesignWidth, min, max)
    //   • uiScaleManual  > 0  → force that scale (e.g. 0.8), still clamped
    //
    // sp(n)     — scale a bar/pill pixel size
    // popupW/H  — scale a popup size and clamp to the current screen
    //
    // IPC: qs ipc call shell setUiScale 0.8 | setUiScaleManual 0 | setUiScaleAuto
    // =========================================================================

    // Runtime (written by shell.qml). Keep defaults sane before first apply.
    property real uiScale: 1.0
    property int screenWidth: 2560
    property int screenHeight: 1440

    // Full-size bar at this logical width and above; narrower screens scale down.
    readonly property int  uiDesignWidth: 2560
    readonly property real uiScaleMin:    0.65
    readonly property real uiScaleMax:    1.0
    // 0 = automatic from screen width; set e.g. 0.85 to force a scale on this machine.
    // Writable so shell IPC / state file can override without editing this file.
    property real uiScaleManual: 0

    function sp(base) {
        var b = Number(base)
        if (!(b > 0))
            return 0
        return Math.max(1, Math.round(b * uiScale))
    }

    function popupW(base) {
        var want = sp(base)
        var maxW = Math.max(160, screenWidth - 24)
        return Math.min(want, maxW)
    }

    function popupH(base) {
        var want = sp(base)
        var maxH = Math.max(120, screenHeight - sp(58) - 32)
        return Math.min(want, maxH)
    }

    function computeUiScale(widthPx) {
        var w = Number(widthPx)
        if (!(w > 0))
            w = uiDesignWidth
        var manual = Number(uiScaleManual)
        var s
        if (manual > 0)
            s = manual
        else
            s = w / uiDesignWidth
        if (s < uiScaleMin) s = uiScaleMin
        if (s > uiScaleMax) s = uiScaleMax
        return s
    }

    // =========================================================================
    // UI DENSITY / PRIORITY (what to hide on narrow screens)
    // =========================================================================
    // Priority (always kept if Config show* is true):
    //   workspaces · system tray · audio · clock/calendar · notifications · power
    //
    // Deprioritized (auto-hidden below width thresholds, widest first):
    //   1) Quick Launch
    //   2) Sys stats (CPU / Memory / GPU)
    //   3) Secondary: FreshRSS, media, kill-target
    //   4) Connectivity: Network + Bluetooth capsule
    //
    // Thresholds are logical screen width (px). Tune if a machine feels too aggressive.

    readonly property int uiDensityHideQuickLaunchBelow:   2300
    readonly property int uiDensityHideStatsBelow:         2000
    readonly property int uiDensityHideSecondaryBelow:     1680
    readonly property int uiDensityHideConnectivityBelow:  1480

    // Runtime flags written by shell.qml applyDensity()
    property bool densityHideQuickLaunch:   false
    property bool densityHideStats:         false
    property bool densityHideSecondary:     false
    property bool densityHideConnectivity:  false

    function computeDensity(widthPx) {
        var w = Number(widthPx)
        if (!(w > 0))
            w = screenWidth > 0 ? screenWidth : uiDesignWidth
        return {
            hideQuickLaunch:   w < uiDensityHideQuickLaunchBelow,
            hideStats:         w < uiDensityHideStatsBelow,
            hideSecondary:     w < uiDensityHideSecondaryBelow,
            hideConnectivity:  w < uiDensityHideConnectivityBelow
        }
    }

    // =========================================================================
    // RADII (corner rounding) — consistency is king  (scaled)
    // =========================================================================
    readonly property int barRadius:       sp(14)   // Main bar background rectangle
    readonly property int pillRadius:      sp(10)   // All pill containers (most common)
    readonly property int popupRadius:     sp(14)   // Default for most popups (audio, calendar, tray, media)
    readonly property int popupRadiusLarge:sp(16)   // Power menu, Help overlay
    readonly property int buttonRadius:       sp(6)   // Small buttons inside popups (mute, nav, close)
    readonly property int smallButtonRadius:  sp(4)   // Very tight buttons (some audio controls)
    readonly property int sliderRadius:       0   // 0 = auto (height/2). Set >0 to force specific rounding on volume bars
    readonly property int workspaceRadius:    sp(8)   // Individual workspace buttons

    // Border widths (not scaled — keep 1px crisp outlines)
    readonly property int controlBorderWidth: 1   // Default border for pills, buttons, popup cards

    // =========================================================================
    // SPACING & PADDING (scaled)
    // =========================================================================
    readonly property int sideMargin:           sp(10)   // Left/right margin of the whole bar (outside the glass rect)
    readonly property int barContentHMargin:    sp(20)   // Inner left/right padding inside the main bar row
    readonly property int barContentVMargin:     sp(4)   // Top/bottom breathing room for the glass rect inside the window
    readonly property int pillHPadding:         sp(18)   // Typical horizontal inner padding for pill content (AudioPill etc use this indirectly)
    readonly property int popupPadding:         sp(16)   // Generic content margin inside most popups (prefer popupSpacing for new code)
    readonly property int popupPaddingSmall:    sp(10)   // Tighter popups (device lists, tray menus) (prefer popupSpacingTight)
    readonly property int widgetSpacing:        sp(14)   // Spacing between major widgets in the bar row
    readonly property int iconTextGap:           sp(6)   // Gap between icon and volume bar or label inside audio pill
    readonly property int dualAudioSidePadding:  sp(3)   // Extra tight padding used only in AudioPill dual view

    // =========================================================================
    // SIZING — BAR, PILLS, POPUPS, ICONS (scaled; popups also screen-clamped)
    // =========================================================================
    // Bar position & size (consumed by shell.qml PanelWindow anchors)
    readonly property string barPosition:  "top"       // "top" | "bottom" — which screen edge the bar sits on
    readonly property int barEdgeMargin:      0     // Gap between the bar and the screen edge (top or bottom)
    readonly property int popupBarGap:        sp(4)     // Space between bar and pill popups (flips with barPosition)
    readonly property int barHeight:           sp(58)   // Bar thickness (height for top/bottom bars)
    readonly property int barTopMargin:  barEdgeMargin   // Legacy alias — prefer barEdgeMargin

    // Pills (uniform height gives the clean segmented look)
    readonly property int pillHeight:          sp(36)   // Standard height for every pill in the bar

    // Audio widget (very sensitive — changing these requires testing dual view alignment)
    // Audio pill content width. Dual view (default) needs room for:
    //   speaker icon + bar + vol% [+ bat%] | mic icon + bar + vol% [+ bat%]
    readonly property int audioViewContentWidth: sp(330)   // Inner width for dual-first layout (+ BT battery)
    readonly property int audioViewSidePadding:    sp(6)   // Dual view left/right micro-padding
    readonly property int audioDualBarWidth:      sp(68)   // Mini volume bar width in dual view
    readonly property int audioDualPercentWidth:  sp(34)   // "100%" label slot in dual view

    // Icon sizes (nerd font glyphs and tray icons)
    readonly property int iconSizeTray:        sp(18)   // System tray — reference size for bar icons
    readonly property int iconSizePill:        iconSizeTray   // Audio, bell, media glyphs in pills
    readonly property int iconSizePillLarge:   iconSizeTray   // Launcher, power menu icon
    readonly property int iconSizePopup:       sp(17)   // Icons inside popups (audio controls row)
    readonly property int iconSizePower:       sp(32)   // Big icons in the power menu grid
    readonly property int iconSizeMediaArt:    sp(42)   // Placeholder music note when no album art
    readonly property int quickLaunchIcon:     sp(20)   // Quick launch row icon size
    readonly property int quickLaunchSpacing:  sp(10)   // Gap between quick-launch icons
    readonly property int quickLaunchPaddingH: sp(10)   // Left/right padding inside the pill

    // =========================================================================
    // QUICK LAUNCH (widgets/QuickLaunchPill.qml — pinned app icon row)
    // =========================================================================
    // Add, remove, or reorder entries in quickLaunchApps. Each entry is one icon.
    //
    //   icon    — path to a PNG/SVG image file shown on the bar
    //   glyph   — optional nerd-font character instead of icon (leave icon "" to use)
    //   command — how to start the app when clicked:
    //               • list (recommended): ["gtk-launch", "firefox"] or ["/path/to/AppImage"]
    //               • string: "gtk-launch firefox" (runs through the shell)
    //             Note: Config list commands are QML lists, not JavaScript arrays.
    //   tooltip — hover label (optional)

    readonly property var quickLaunchApps: [
        {
            icon: "/home/crome/icons/vscodium.svg",
            glyph: "",
            command: ["gtk-launch", "vscodium"],
            tooltip: "VSCodium"
        },
        {
            icon: "/home/crome/icons/firefox.svg",
            glyph: "",
            command: ["env", "MOZ_ENABLE_WAYLAND=0", "firefox"],
            tooltip: "Firefox"
        },
        {
            icon: "/home/crome/icons/brave.svg",
            glyph: "",
            command: ["/usr/bin/brave-origin"],
            tooltip: "Brave Origin"
        },
        {
            icon: "/home/crome/icons/google-chrome.svg",
            glyph: "",
            command: ["/usr/bin/google-chrome-stable"],
            tooltip: "Google Chrome"
        },
        {
            icon: "/home/crome/icons/logseq-a.svg",
            glyph: "",
            command: ["gtk-launch", "logseq"],
            tooltip: "Logseq"
        },
        {
            icon: "/home/crome/icons/lmstudio-dark.png",
            glyph: "",
            command: ["/home/crome/applications/LM-Studio-0.4.13-1-x64.AppImage"],
            tooltip: "LM Studio"
        },
        {
            icon: "/home/crome/icons/steam.svg",
            glyph: "",
            command: ["/usr/bin/steam"],
            tooltip: "Steam"
        },   
        {
            icon: "/home/crome/icons/com.system76.CosmicFiles.svg",
            glyph: "",
            command: ["/usr/bin/cosmic-files"],
            tooltip: "Cosmic Files"
        },    
        {
            icon: "/home/crome/icons/kitty.svg",
            glyph: "",
            command: ["/usr/bin/kitty"],
            tooltip: "Kitty"
        },        
    ]

    // Popup window sizes (scaled + clamped to screen). Increase base if content feels cramped.
    // AudioPill: streams summary, device + profile, volume, L/R, VU, echo cancel, tools.
    readonly property int popupAudioWidth:     popupW(520)   // AudioPill device/volume popup
    readonly property int popupAudioHeight:    popupH(620)
    readonly property int popupMediaWidth:     popupW(520)   // MediaPill player controls popup
    readonly property int popupMediaHeight:    popupH(470)
    readonly property int popupPowerWidth:     popupW(560)   // PowerMenu full grid (left-click)
    readonly property int popupPowerHeight:    popupH(192)
    readonly property int popupContextMenuWidth:  popupW(220)   // Compact right-click menus (bell, power)
    readonly property int popupContextMenuRowHeight: sp(34)  // Height of one row in those menus
    readonly property int popupCalendarWidth:  popupW(310)   // ClockPill calendar popup
    readonly property int popupCalendarHeight: popupH(280)
    // --- BluetoothPill (adapter power, devices, profiles)
    readonly property int popupBluetoothWidth:  popupW(380)
    readonly property int popupBluetoothHeight: popupH(480)
    readonly property int bluetoothScanSeconds: 45   // Auto-stop discovery after this many seconds
    // --- NetworkPill (nm-applet replacement: wired/WiFi, radios, connection info)
    // Main column width; WiFi AP list opens as a second column of popupNetworkWifiWidth
    readonly property int popupNetworkWidth:      popupW(520)
    readonly property int popupNetworkWifiWidth:  popupW(340)   // right column when scanning / changing network
    readonly property int popupNetworkHeight:     popupH(580)
    // --- SysStatsPill metrics popups (left-click CPU / Memory / GPU on the bar pill)
    // These are the large dropdown panels with charts and process lists — not the
    // compact numbers shown on the pill itself. Each section has its own size.
    readonly property int popupStatsCpuWidth:  popupW(598)   // CPU popup width in pixels
    readonly property int popupStatsCpuHeight: popupH(850)   // CPU popup height in pixels
    readonly property int popupStatsMemWidth:  popupW(598)   // Memory popup width in pixels
    readonly property int popupStatsMemHeight: popupH(850)   // Memory popup height in pixels
    readonly property int popupStatsGpuWidth:  popupW(598)   // GPU popup width in pixels
    readonly property int popupStatsGpuHeight: popupH(850)   // GPU popup height in pixels

    // --- Where each metrics popup appears on screen (widgets/SysStatsPill.qml)
    // Right-click CPU, Memory, or GPU to open its popup. Position is tuned per section
    // so popups do not overlap each other or fall off the screen edge.
    //
    // Shared terms (same meaning for Cpu / Mem / Gpu):
    //   anchorX          — which part of the pill section to line up under:
    //                      0 = left edge, 0.5 = middle, 1 = right edge
    //   anchorWholePill  — false = anchor under that section only (CPU, Memory, or GPU)
    //                      true  = anchor under the entire stats pill as one block
    //   offsetX          — slide popup left (negative) or right (positive) in pixels
    //   offsetY          — slide popup up (negative) or down (positive) in pixels
    //   barGap           — space between the bar and the popup (larger = farther away)

    // CPU section (left third of the pill)
    readonly property real popupStatsCpuAnchorX: 0.5
    readonly property bool popupStatsCpuAnchorWholePill: false
    readonly property int popupStatsCpuOffsetX: sp(200)
    readonly property int popupStatsCpuOffsetY: sp(7)
    readonly property int popupStatsCpuBarGap: sp(2)

    // Memory section (middle third)
    readonly property real popupStatsMemAnchorX: 0.5
    readonly property bool popupStatsMemAnchorWholePill: false
    readonly property int popupStatsMemOffsetX: 0
    readonly property int popupStatsMemOffsetY: sp(7)
    readonly property int popupStatsMemBarGap: sp(2)

    // GPU section (right third)
    readonly property real popupStatsGpuAnchorX: 0.5
    readonly property bool popupStatsGpuAnchorWholePill: false
    readonly property int popupStatsGpuOffsetX: -sp(200)
    readonly property int popupStatsGpuOffsetY: sp(7)
    readonly property int popupStatsGpuBarGap: sp(2)

    // When you right-click and open a metrics popup, should charts update live?
    // true  = live graphs and numbers (uses a bit more CPU while open)
    // false = frozen snapshot until you close and reopen
    readonly property bool popupStatsLiveUpdates: true

    // Remember your Pause / Resume choice across reboots?
    // false = always use popupStatsLiveUpdates when you open a popup
    // true  = save per-section pause state to state/popup-stats.json
    readonly property bool popupStatsPersistPause: false
    readonly property int popupHelpWidth:     popupW(1060)  // Hypr Config Inspector default width
    readonly property int popupHelpHeight:    popupH(720)   // Hypr Config Inspector default height
    readonly property int popupTrayMaxHeight:  popupH(520)   // SystemTrayPill menu max height before scroll

    // Popup internal layout tokens (standardizes the repeated glass card patterns)
    readonly property real popupHeaderHighlightHeight: 1.5   // Top light edge on popup glass cards
    readonly property int popupTitleSize:             sp(16)    // "Audio Controls", "Power Menu", etc.
    readonly property int popupSectionSize:           sp(13)    // "Playback", "Recording", section headers
    readonly property int popupHintSize:              sp(11)    // "right-click pill or outside to close"
    readonly property int popupSpacing:               sp(16)    // Main content margin inside popups
    readonly property int popupSpacingTight:          sp(10)    // Tighter popups (device lists, tray menus)
    readonly property int popupSectionSpacing:         sp(6)    // Spacing between sections inside popups

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
    readonly property bool showNetworkPill:          true   // NetworkPill.qml (nm-applet replacement)
    readonly property bool showBluetoothPill:        true   // BluetoothPill.qml
    readonly property bool showAudioPill:           true   // AudioPill.qml
    readonly property bool showClockPill:           true   // ClockPill.qml
    readonly property bool showNotificationPill:     true   // NotificationBell.qml
    readonly property bool showPowerPill:           true   // PowerMenu.qml
    readonly property bool showKillTargetPill:    false  // KillTargetPill.qml (click-to-kill picker)
    readonly property bool showFreshRssPill:       true   // FreshRssPill.qml (FreshRSS reader)
    readonly property bool showRadarPill:          false  // RadarPill.qml (removed from bar; set true + re-add in shell.qml to restore)
    readonly property bool showHyprInspPill:       false  // Opens HyprConfigInsp from the bar (shell.qml)
    readonly property bool showControlBarPill:     true   // Opens BarControlBar (config strip) from the bar

    // Glyphs for bar position toggle in BarControlBar (right-click empty bar chrome)
    readonly property string barPositionIconTop:    "󰁝"  // shown when bar is on bottom (click → move to top)
    readonly property string barPositionIconBottom: "󰁅"  // shown when bar is on top (click → move to bottom)
    readonly property string iconHyprInsp:          "󰒓"  // Hyprland Config Inspector bar pill
    readonly property string iconControlBar:        "󰢻"  // Bar control / config menu pill

    // Display (BarControlBar → Display panel; hyprctl modes + bitdepth)
    // CLI/rofi: hypr-resolution (on PATH). Script: list/status/apply for the control strip.
    readonly property string hyprResolutionBin: "hypr-resolution"
    readonly property string monitorModeScript: "/home/crome/.config/quickshell/scripts/monitor-mode.sh"
    readonly property string monitorName: "DP-1"

    // Wallpaper (BarControlBar → Wallpaper panel; hyprpaper apply)
    readonly property string wallpaperDir: "/home/crome/Pictures/wallpapers"
    readonly property string wallpaperMonitor: "DP-1"
    readonly property string wallpaperFitMode: "cover"
    readonly property string wallpaperListScript:  "/home/crome/.config/quickshell/scripts/wallpaper-list-json.sh"
    readonly property string wallpaperApplyScript: "/home/crome/.config/quickshell/scripts/wallpaper-apply.sh"
    readonly property string wallpaperAddScript:   "/home/crome/.config/quickshell/scripts/wallpaper-add.sh"
    readonly property string wallpaperPickDirScript: "/home/crome/.config/quickshell/scripts/wallpaper-pick-dir.sh"

    // XDG Autostart (BarControlBar → Autostart panel; ~/.config/autostart)
    readonly property string autostartListScript: "/home/crome/.config/quickshell/scripts/autostart-list-json.sh"
    readonly property string autostartSetScript:  "/home/crome/.config/quickshell/scripts/autostart-set.sh"
    readonly property string autostartAddScript:  "/home/crome/.config/quickshell/scripts/autostart-add.sh"
    readonly property string autostartRunScript:  "/home/crome/.config/quickshell/scripts/autostart-run.sh"

    // Clock format (Qt.formatDateTime) — editable from BarControlBar; persisted in bar-layout.json
    readonly property string clockFormat: "dddd, MM·dd·yyyy | HH:mm:ss"
    // Presets shown in the control-bar Clock menu: { label, format, tip }
    readonly property var clockFormatPresets: [
        { label: "Full",   format: "dddd, MM·dd·yyyy | HH:mm:ss", tip: "Weekday, date, 24h with seconds" },
        { label: "Date",   format: "ddd MM·dd·yyyy  HH:mm",       tip: "Short weekday + date + time" },
        { label: "Time",   format: "HH:mm:ss",                    tip: "24-hour time with seconds" },
        { label: "Short",  format: "HH:mm",                       tip: "24-hour time only" },
        { label: "12h",    format: "h:mm AP",                     tip: "12-hour with AM/PM" },
        { label: "US",     format: "ddd M/d/yyyy  h:mm AP",       tip: "US-style date + 12h" }
    ]

    // Default widget order + zone for BarControlBar layout editor / runtime reparent.
    // zone: "left" | "center" | "right". Connectivity is Network+Bluetooth as one unit.
    readonly property var defaultWidgetLayout: [
        { id: "launcher",      zone: "left" },
        { id: "quickLaunch",   zone: "left" },
        { id: "freshRss",      zone: "left" },
        { id: "media",         zone: "left" },
        { id: "workspaces",    zone: "center" },
        { id: "stats",         zone: "right" },
        { id: "tray",          zone: "right" },
        { id: "connectivity",  zone: "right" },
        { id: "clock",         zone: "right" },
        { id: "notifications", zone: "right" },
        { id: "killTarget",    zone: "right" },
        { id: "hyprInsp",      zone: "right" },
        { id: "controlBar",    zone: "right" },
        { id: "power",         zone: "right" }
    ]

    // =========================================================================
    // NWS RADAR (widgets/RadarPill.qml + scripts/radar-fetch.sh)
    // =========================================================================
    // Native map window (not a browser). Radar from NOAA OpenGeo WMS; basemap
    // from Esri World Street Map. No background polling of new frames.
    //
    // Defaults match a radar.weather.gov bookmark centered on Ohio:
    //   center [-83.201, 40.326], zoom ~7.086, local mosaic view
    //
    // radarOverscan: each fetch loads this many viewport-widths of area so you
    // can pan a long distance before a reload. Scale is isotropic (same X/Y) so
    // the buffer matches the window aspect and does not stretch the map.
    // Auto-refresh runs after pan/zoom settles only when the view leaves that
    // buffer (or zoom changes a lot).
    //
    // IPC:
    //   qs ipc call radar toggle | refresh | show | hide
    //
    // product: "cref" (composite reflectivity) or "bref" (base reflectivity)

    readonly property real   radarDefaultLon:     -83.201
    readonly property real   radarDefaultLat:      40.326
    readonly property real   radarDefaultZoom:     7.086
    readonly property string radarDefaultProduct:  "cref"
    readonly property real   radarOverscan:        3.0    // 3× viewport coverage per fetch
    readonly property int    radarSettleMs:        420    // debounce before edge auto-reload
    readonly property int    radarWidth:           popupW(980)
    readonly property int    radarHeight:          popupH(680)
    readonly property int    radarMinWidth:        sp(560)
    readonly property int    radarMinHeight:       sp(400)

    // =========================================================================
    // FRESHRSS READER (widgets/FreshRssPill.qml + scripts/freshrss-api.sh)
    // =========================================================================
    // Server + credentials (outside git):
    //   ~/.config/freshrss-quickshell/freshrss.env
    //   FRESHRSS_BASE_URL / FRESHRSS_USER / FRESHRSS_API_PASSWORD
    // Without API password the client uses public RSS (anonymous, read-only).
    // API password = Profile → API password (not web form login).
    // Edit via control bar Options → FreshRSS, or the env file by hand.
    //
    // Reader defaults (in FreshRssPill.qml):
    //   readScope = "all", dateFilter = "all", categories start collapsed.
    //
    // IPC:
    //   qs ipc call freshRss toggle
    //   qs ipc call freshRss refresh

    readonly property int freshRssPollIntervalMs:  60000  // badge poll while bar is up
    readonly property int freshRssItemLimit:       80     // max unread/starred ids (when maxDays=0)
    // For All/Read scopes: recent articles pulled from *each* feed so quiet channels
    // still appear, not only high-volume feeds.
    // Ignored when freshRssMaxDays > 0 (day window is the primary limit).
    readonly property int freshRssPerFeedLimit:    12
    // Primary history window: only articles newer than this many days.
    // When > 0, overrides per-feed and item-count caps.
    // 0 = unlimited (use per-feed / item limits only).
    readonly property int freshRssMaxDays:         30
    // Filters panel (search / max days / per feed) open on reader start
    readonly property bool freshRssFiltersExpandedDefault: true
    readonly property int freshRssWidth:           popupW(980)
    readonly property int freshRssHeight:          popupH(640)
    readonly property int freshRssMinWidth:        sp(640)
    readonly property int freshRssMinHeight:       sp(420)
    readonly property int freshRssListWidth:       sp(320)   // default list pane width (SplitView)
    readonly property int freshRssListMinWidth:    sp(180)   // drag limit — list pane
    readonly property int freshRssListMaxWidth:    sp(720)
    readonly property int freshRssDetailMinWidth:  sp(260)   // drag limit — article pane
    // Scripts for Options panel credentials UI
    readonly property string freshRssSecretsReadScript:  "/home/crome/.config/quickshell/scripts/freshrss-secrets-read.sh"
    readonly property string freshRssSecretsWriteScript: "/home/crome/.config/quickshell/scripts/freshrss-secrets-write.sh"
    readonly property string freshRssConnectionTestScript: "/home/crome/.config/quickshell/scripts/freshrss-connection-test.sh"

    // =========================================================================
    // NOTIFICATION BELL (widgets/NotificationBell.qml)
    // =========================================================================
    // CLI commands for your notification daemon. Defaults below are for SwayNC.
    // To use a different daemon, replace these lists with that client's commands
    // (same argv-list style as Quick Launch). Leave [] to disable an action.
    //
    //   notificationSubscribe    — live badge/DND updates (SwayNC: swaync-client -s)
    //   notificationTogglePanel  — left-click on the bell (SwayNC: -t)
    //   notificationToggleDnd    — Do Not Disturb toggle in the right-click menu
    //   notificationClearAll     — clear all in the right-click menu
    //   notificationSync         — backup poll script; prints one JSON line per run:
    //                              {"count":N,"dnd":true|false}
    //   notificationDndAccent    — border/bell color when Do Not Disturb is on

    readonly property var notificationSubscribe:    ["swaync-client", "-s", "-sw"]  // Live JSON stream (optional)
    readonly property var notificationTogglePanel: ["swaync-client", "-t", "-sw"]   // Left-click bell
    readonly property var notificationToggleDnd:   ["swaync-client", "-d", "-sw"]   // Right-click menu
    readonly property var notificationClearAll:    ["swaync-client", "-C", "-sw"]   // Right-click menu
    // Timer poller — reliable badge/DND backup; script must print {"count":N,"dnd":true|false}
    readonly property var notificationSync: [
        "/home/crome/.config/quickshell/scripts/notification-sync.sh"
    ]
    readonly property int notificationSyncIntervalMs: 2500  // Ms between sync script runs
    readonly property color notificationDndAccent: muted  // Warning red pill border + bell when DND is on

    // =========================================================================
    // KILL TARGET PILL (widgets/KillTargetPill.qml — xkill-style window picker)
    // =========================================================================
    // Click the pill to arm pick mode, then click any window to close its app.
    // Sends SIGTERM to the window's process (same safety rules as the inspector
    // Processes tab). Escape, right-click, or clicking empty desktop cancels.

    readonly property string killTargetIcon: "🎯"   // 󰍣Crosshair / target icon on the bar pill
    readonly property string killTargetTooltip: "Click to pick a window and kill its app · Esc cancels"
    // Darkening applied to each monitor while pick mode is active (0 = invisible overlay).
    readonly property real killTargetOverlayDim: 0.12

    // =========================================================================
    // POWER MENU (widgets/PowerMenu.qml — session actions)
    // =========================================================================
    // Commands for lock, logout, reboot, shutdown, and Enter BIOS. Each is a list
    // (preferred): ["hyprlock"] or ["sh", "-c", "your shell pipeline"] — or a shell
    // string (runs via sh -c). Use [] to hide an action from both power menus.
    //
    // powerMenuActions — labels and icons shown in the grid + right-click menu.
    // Reorder or rename entries here; command lists below must match action ids.

    readonly property var powerLockCommand: ["hyprlock"]  // Lock screen (left-click grid + right-click menu)
    readonly property var powerLogoutCommand: [           // End Hyprland session; edit app list in the shell pipeline
        "sh", "-c",
        "systemctl --user stop psd.service & pkill -f 'steam|discord|flameshot|espanso|google-chrome-stable|brave|brave-origin' & sleep 1 & command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch 'hl.dsp.exit()'"
    ]
    readonly property var powerRebootCommand: [         // Reboot the machine
        "sh", "-c",
        "systemctl --user stop psd.service & pkill -f \"steam|discord|flameshot|espanso|google-chrome-stable|brave|brave-origin\" & sleep 1 & reboot"
    ]
    readonly property var powerShutdownCommand: [         // Power off the machine
        "sh", "-c",
        "systemctl --user stop psd.service & pkill -f \"steam|discord|flameshot|espanso|google-chrome-stable|brave|brave-origin\" & sleep 1 & shutdown now"
    ]
    readonly property var powerBiosCommand: ["systemctl", "reboot", "--firmware-setup"]  // UEFI/BIOS on next boot

    // =========================================================================
    // FONTS
    // =========================================================================
    readonly property string fontFamily: "Symbols Nerd Font, JetBrains Mono Nerd Font, monospace"
    readonly property string fontMono:   "JetBrains Mono Nerd Font, monospace"

    // Sizes (base designed for ~58px bar; scaled via uiScale, min 9px for readability)
    readonly property int fontClock:      Math.max(9, sp(15))   // Main clock text (bold)
    readonly property int fontPillLabel:  Math.max(9, sp(12))   // % labels next to volume bars, small text
    readonly property int fontPillLabelBold: Math.max(9, sp(12))   // Bold variant of pill labels
    readonly property int fontPopupTitle: Math.max(10, sp(16))   // "Audio Controls", "Power Menu", etc.
    readonly property int fontSection:    Math.max(9, sp(13))   // "Playback", "Recording", tab labels
    readonly property int fontBody:       Math.max(9, sp(12))   // Most body text in popups
    readonly property int fontSmall:      Math.max(9, sp(11))   // Hints, tray menu items
    readonly property int fontTiny:       Math.max(8, sp(10))   // Footer hints, help key pills
    readonly property int fontPowerLabel: Math.max(9, sp(12))   // Text under big power icons

    // =========================================================================
    // ICON GLYPHS (single place to change the entire icon language)
    // =========================================================================
    // Speaker / volume (MDI — matches mic/tray visual weight; FA glyphs render smaller at same px)
    readonly property string iconSpeaker:       "󰕾"
    readonly property string iconSpeakerMuted:  "󰖁"
    // Microphone
    readonly property string iconMic:           "󰍬"
    readonly property string iconMicMuted:      "󰍭"
    // Audio device transport / form (AudioPill device picker)
    readonly property string iconAudioBluetooth: "󰂯"   // Bluetooth headset/speakers
    readonly property string iconAudioUsb:       "󰕓"   // USB audio (DAC, webcam mic, etc.)
    readonly property string iconAudioHdmi:      "󰡁"   // HDMI / DisplayPort audio
    readonly property string iconAudioInternal:  "󰓃"   // Built-in / PCI analog
    readonly property string iconAudioHeadset:   "󰋋"   // Headset form factor
    readonly property string iconAudioBattery:   "󰁹"   // BT battery (generic full)
    // Bluetooth pill (adapter / connection state glyphs)
    readonly property string iconBluetooth:          "󰂯"   // Powered on, idle
    readonly property string iconBluetoothOff:       "󰂲"   // Powered off / no adapter
    readonly property string iconBluetoothConnected: "󰂱"   // At least one device connected
    readonly property string iconBluetoothScanning:  "󰂰"   // Discovery active
    // Network pill (wired / WiFi / radios)
    readonly property string iconNetworkWired:          "󰈀"   // Ethernet connected
    readonly property string iconNetworkWifi:           "󰤨"   // Strong WiFi signal
    readonly property string iconNetworkWifiFair:       "󰤥"   // Medium WiFi
    readonly property string iconNetworkWifiWeak:       "󰤢"   // Weak WiFi
    readonly property string iconNetworkWifiNone:       "󰤟"   // Very weak / no bars
    readonly property string iconNetworkWifiOff:        "󰤭"   // WiFi radio off
    readonly property string iconNetworkDisconnected:   "󰤮"   // No active connection
    readonly property string iconNetworkOff:            "󰲛"   // Networking disabled
    readonly property string iconNetworkPortal:         "󰖟"   // Captive portal
    // Power menu
    readonly property string iconPower:         "󰐥"
    readonly property string iconLock:          "󰌾"
    readonly property string iconLogout:        "󰍃"
    readonly property string iconReboot:        "󰑓"
    readonly property string iconShutdown:      "󰐥"
    readonly property string iconBios:          "󰛳"

    // Menu rows for PowerMenu.qml (grid + right-click). Reorder or rename freely.
    readonly property var powerMenuActions: [
        { icon: iconLock,     label: "Lock",       action: "lock" },
        { icon: iconLogout,   label: "Logout",     action: "logout" },
        { icon: iconReboot,   label: "Reboot",     action: "reboot" },
        { icon: iconShutdown, label: "Shutdown",   action: "shutdown" },
        { icon: iconBios,     label: "Enter BIOS", action: "bios" },
    ]

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
    readonly property int  sliderBarHeight: sp(6)     // Track thickness (VolumeBar default)
    readonly property int  sliderPopupHeight: sp(8)   // Taller version used in the audio popup row

    // Compact dual-view bars (inside AudioPill when both speaker+mic shown)
    readonly property int  sliderMiniHeight: sp(5)

    // Volume bar fallback fill (AudioPill overrides per-level via audioSpeaker/MicUtilColor)
    readonly property color sliderFill:       accent   // Vivid teal-cyan (#00F0E0)
    readonly property color sliderFillMuted:  muted     // Fill when device is muted (magenta)
    readonly property color sliderTrack:      surface  // Background track (blue-slate)

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
    // qs startup (shell.qml) — runs on every qs start AND reload (qs has no session vs reload distinction):
    //   wsStartupWorkspace 0 → do not change Hyprland workspace (recommended; preserves focus on qs reload)
    //   wsStartupWorkspace N → focus workspace N (after optional magic close). Prefer Hyprland exec-once
    //                          for true login-only focus instead of forcing from the bar.

    readonly property bool wsShowSpecialPill: true    // Magic pill default (toggle via qs ipc call shell setShowMagicWorkspacePill)
    readonly property int  wsMinimumShown: 3           // Default pills 1..N (IPC: qs ipc call shell setWsMinimumShown)
    readonly property bool wsShowOnlyActive: false    // IPC: qs ipc call shell setWsShowOnlyActive
    readonly property int  wsStartupWorkspace: 0       // 0 = preserve focus on start/reload. IPC: setWsStartupWorkspace
    readonly property bool wsStartupCloseMagic: false  // Close magic on qs start (only if wsStartupWorkspace > 0). IPC: setWsStartupCloseMagic

    // Legacy workspace hover (unused by WorkspacesPill — uses iconHoverBg now).
    readonly property color wsHoverYellow: "#b8fff8"           // Soft teal hover reference
    readonly property color wsActiveBg:    Qt.rgba(0.0, 0.85, 0.80, 0.28)  // Active workspace — teal glass
    readonly property color wsActiveBorder: accent     // Vivid teal-cyan
    readonly property color wsActiveText:  "#e6fffc"
    readonly property color wsInactiveText: clock   // Falls back to bar.clock in delegate

    // Legacy names some older code paths may still reference
    readonly property color wsText:        "#8a92b0"
    readonly property color wsActiveTextLegacy: wsActiveText   // (the alias in shell.qml maps wsActiveText → this)

    readonly property int  wsButtonWidth:   sp(42)   // Width of each workspace pill button
    readonly property int  wsButtonHeight:  sp(32)   // Height of each workspace pill button
    readonly property int  wsIconSize:      iconSizeTray  // Glyph size inside workspace pills
    readonly property int  wsNumberSize:    Math.max(9, sp(15))   // Font size for workspace numbers (when no icon)
    readonly property int  wsSpacing:        sp(4)   // Gap between workspace buttons

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
    // SYS STATS PILL (widgets/SysStatsPill.qml — CPU | Memory | GPU)
    // =========================================================================
    // The centered bar pill that shows live CPU, Memory, and GPU stats.
    // Left-click a section opens its metrics popup; right-click CPU/Memory launches
    // btop, right-click GPU launches nvtop (see popupStats* above for popup size).
    //
    // Layout notes (SysStatsPill.qml) — snug by default, still readable:
    //   - Sections hug label + gauge + values (Memory wider than CPU/GPU).
    //   - Pill width fits content + padding (no empty side ballast).
    //   - statPillWidth / statPillSectionWidth only expand if you raise them above 0.
    // If text ever clips, raise statPillPaddingH or statPillSpacing slightly.

    // Optional preferred pill width. 0 = fit content (default, no wasted side space).
    // Set e.g. sp(640) only if you want intentional extra width with centered content.
    readonly property int  statPillWidth: 0

    // Optional minimum column width. 0 = hug content (default). Raise to force equal
    // wider columns (e.g. sp(200)) if you prefer uniform section hit-targets.
    readonly property int  statPillSectionWidth: 0

    // Gap between columns (divider is centered in this slot — not double-spaced).
    readonly property int  statPillSpacing: sp(8)

    // Left and right padding inside the pill border so text is not flush to the edge.
    readonly property int  statPillPaddingH: sp(10)

    // Small horizontal utilization bars (the colored fill behind the % numbers).
    readonly property int  statGaugeWidth:   sp(56)
    readonly property int  statGaugeHeight:   sp(7)
    readonly property int  statGaugeRadius:   sp(3)
    readonly property color statTrack:       Qt.rgba(1, 1, 1, 0.10)  // Bar background track on glass

    // Utilization % bar and text color by load level (green → yellow → orange → magenta).
    readonly property color statUtilTier1: "#10B981"   // Low load (0% up to first threshold)
    readonly property color statUtilTier2: "#F59E0B"
    readonly property color statUtilTier3: "#F97316"
    readonly property color statUtilTier4: "#EF4444"   // High load (above third threshold)

    // At what utilization % each color tier starts (must be in ascending order).
    readonly property int statUtilThreshold1: 25
    readonly property int statUtilThreshold2: 50
    readonly property int statUtilThreshold3: 75

    // CPU/GPU temperature text colors (Memory shows used GiB instead — uses subtext color).
    readonly property color statTempCool: text        // Normal temperature (primary text)
    readonly property color statTempWarm: "#f0d060"   // Getting warm (bright gold)
    readonly property color statTempHot:  muted       // Hot (magenta-pink)

    // Temperatures in °C where the label switches cool → warm → hot.
    readonly property int statTempWarmAt: 70
    readonly property int statTempHotAt:  85

    // Color of the "|" between utilization % and temperature (or used GiB for Memory).
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
    // Animated bars behind the media pill when music is playing.
    readonly property int  cavaBarCount:     40   // Number of vertical bars
    readonly property int  cavaBarGap:        1   // Pixels between bars
    readonly property color cavaInactive:    Qt.rgba(1, 1, 1, 0.18)  // Bar color when silent
    readonly property color cavaActive:      Qt.rgba(0.0, 0.94, 0.88, 0.42)  // Vivid teal when audio plays
    readonly property int  cavaAnimFast:     95   // Animation speed (ms) when media is playing
    readonly property int  cavaAnimSlow:    420   // Animation speed (ms) when idle (saves CPU)

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
    readonly property color panelTabActiveBg:   Qt.rgba(0.0, 0.85, 0.80, 0.25)  // teal glass chip
    readonly property color panelTabActiveBorder: accent

    // Gauge color ramp for CircularGauge (CPU/GPU/memory/temp). <65% / 65–85% / >85%
    readonly property color gaugeLow:  "#2ee59a"
    readonly property color gaugeMid:  "#f0d060"
    readonly property color gaugeHigh: muted

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
    readonly property int inspMinWidth:  sp(560)
    readonly property int inspMinHeight: sp(400)
    readonly property int inspContentPadding: sp(18)      // inner margin around the whole layout
    readonly property int inspSectionSpacing: sp(12)      // vertical gap between header/tabs/content/footer

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
    readonly property color inspGradientBottom:   Qt.rgba(0.03, 0.04, 0.08, 0.96)  // deep blue-slate glass fade

    // --- Tab bar (wrapping Flow of chips + vertical scrollbar when many tabs)
    readonly property int inspTabBarMaxHeight:       sp(102)
    readonly property int inspTabHeight:       sp(30)
    readonly property int inspTabRadius:       sp(7)
    readonly property int inspTabHPadding:       sp(28)    // added to label width for chip width
    readonly property int inspTabSpacing:       sp(6)
    readonly property int inspTabFontSize:     Math.max(9, sp(13))
    // Active tab reuses panelTabActive* tokens (shared tab-chip style)
    readonly property color inspTabActiveBg:      panelTabActiveBg
    readonly property color inspTabActiveBorder:  panelTabActiveBorder
    readonly property color inspTabHoverBg:       surface

    // --- Global search field (right of tab bar)
    readonly property int inspSearchWidth:       sp(220)
    readonly property int inspSearchHeight:       sp(28)        
    readonly property int inspSearchRadius:       sp(6)
    readonly property int inspSearchPadding:       sp(4)
    readonly property int inspSearchFontSize:     Math.max(9, sp(12))          //14
    readonly property color inspSearchSelectionBg: Qt.rgba(0.0, 0.90, 0.85, 0.35)  // teal glass selection

    // --- Header (title row, version/distro, keyboard hints)
    readonly property int inspTitleFontSize:     Math.max(9, sp(18))
    readonly property int inspSubtitleFontSize:     Math.max(9, sp(13))
    readonly property int inspHeaderButtonHeight:       sp(28)
    readonly property int inspRefreshButtonWidth:       sp(78)
    readonly property int inspCloseButtonSize:       sp(28)
    readonly property color inspHeaderDivider: divider

    // --- Footer (status line + action chips: Copy, Refresh, Edit)
    readonly property int inspStatusFontSize:     Math.max(9, sp(12))
    readonly property int inspFooterButtonHeight:       sp(22)
    readonly property int inspFooterButtonRadius:       sp(5)
    readonly property int inspFooterButtonSpacing:       sp(6)

    // --- Scrollbars (tab bar + content Flickables)
    readonly property int inspScrollBarWidth:       sp(6)
    readonly property int inspScrollBarRadius:       sp(3)
    readonly property color inspScrollBarIdle: Qt.rgba(1, 1, 1, 0.2)

    // --- List/table row interaction (binds, env, system info rows)
    readonly property color inspRowHoverBg:       Qt.rgba(1, 1, 1, 0.03)
    readonly property color inspRowHoverBgStrong: Qt.rgba(1, 1, 1, 0.06)  // system info values
    readonly property int inspRowRadius:       sp(4)
    readonly property int inspBindRowHeight:       sp(26)
    readonly property int inspEnvRowHeight:       sp(28)
    readonly property int inspEnvHeaderHeight:       sp(28)

    // --- Environment variable table layout
    readonly property int inspEnvTableSideMargin:       sp(10)
    readonly property int inspEnvTableColSpacing:       sp(12)
    readonly property int inspEnvVarColMinWidth:       sp(180)
    readonly property int inspEnvVarColMaxWidth:       sp(260)
    readonly property real inspEnvVarColRatio:    0.22   // fraction of usable width for Variable column
    readonly property int inspEnvValueColMinWidth:       sp(180)
    readonly property int inspEnvValueColMaxWidth:       sp(340)
    readonly property real inspEnvValueColRatio:   0.28   // fraction of usable width for Value column
    readonly property int inspEnvDescColMinWidth:       sp(320)    // minimum width for Description column

    // --- Key binding modifier pills (liquid glass semantic colors)
    readonly property color inspKeyPillSuper:   "#00F0E0"  // Vivid teal-cyan
    readonly property color inspKeyPillShift:   "#f0a86a"
    readonly property color inspKeyPillCtrl:    "#c084fc"  // Soft violet (contrast against teal)
    readonly property color inspKeyPillAlt:     "#00D4C8"  // Teal sibling of brand accent
    readonly property color inspKeyPillDefault: overlay
    readonly property color inspKeyPillTextOnDark:  "#ffffff"
    readonly property color inspKeyPillTextOnLight: "#000000"
    readonly property int inspKeyPillHeight:       sp(20)
    readonly property int inspKeyPillRadius:       sp(5)
    readonly property int inspKeyPillHPadding:       sp(12)
    readonly property int inspKeyPillFontSize:     Math.max(9, sp(11))

    // --- Environment variable semantic colors (keys + values)
    readonly property color inspEnvKeyHighlight: "#00E8D0"   // graphics/wayland-related keys
    readonly property color inspEnvValueTrue:      "#2ee59a"   // 1, true, enabled
    readonly property color inspEnvValueFalse:     "#f0a86a"   // 0, false, disabled
    readonly property color inspEnvValueTech:      "#00F0E0"   // nvidia, wayland, opengl, direct
    readonly property color inspEnvValuePath:      subtext      // filesystem paths
    readonly property color inspEnvValueTheme:     "#c084fc"   // theme/platform strings (violet)
    readonly property color inspEnvValueTerminal:  "#60D0FF"   // TERMINAL, hyprland refs

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
    readonly property color divider:         Qt.rgba(1, 1, 1, 0.12)   // Soft glass divider
    readonly property color dividerSubtle:   Qt.rgba(1, 1, 1, 0.07)   // Fainter glass hairline
    readonly property color dividerStrong:   Qt.rgba(0.55, 0.72, 0.82, 0.14)  // Soft cool section lines
    readonly property int  dividerThickness: 1

    // =========================================================================
    // TRAY MENU (SystemTrayPill check/radio rows)
    // =========================================================================
    readonly property color menuCheckMark:     text    // ✓ / ● glyphs (not accent — avoids purple GTK clash)
    readonly property color menuUncheckedMark: overlay // ○ / empty radio ring
    readonly property color menuCheckedRow:  Qt.rgba(0.0, 0.90, 0.85, 0.18)  // teal glass highlight on checked items

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
    readonly property int popupY: barHeight + 2   // Legacy Y offset under the bar (prefer popupBarGap + popupAnchorY)

    // --- NotificationBell command resolver (used by shell.qml + NotificationBell.qml)
    function notificationCommand(action) {
        if (action === "subscribe") return notificationSubscribe
        if (action === "togglePanel") return notificationTogglePanel
        if (action === "toggleDnd") return notificationToggleDnd
        if (action === "clearAll") return notificationClearAll
        if (action === "sync") return notificationSync
        return []
    }

    function notificationCmdLength(cmd) {
        return cmd && cmd.length !== undefined && cmd.length > 0
    }

    function notificationUsesLiveSubscribe() {
        return notificationCmdLength(notificationSubscribe)
    }

    function notificationSyncEnabled() {
        return notificationCmdLength(notificationSync)
    }

    function notificationSupportsPanel() {
        var cmd = notificationCommand("togglePanel")
        return cmd && cmd.length !== undefined && cmd.length > 0
    }

    function notificationSupportsDnd() {
        var cmd = notificationCommand("toggleDnd")
        return cmd && cmd.length !== undefined && cmd.length > 0
    }

    function notificationSupportsClearAll() {
        var cmd = notificationCommand("clearAll")
        return cmd && cmd.length !== undefined && cmd.length > 0
    }

    // --- PowerMenu command resolver (used by shell.qml + PowerMenu.qml)
    function powerCommand(action) {
        if (action === "lock") return powerLockCommand
        if (action === "logout") return powerLogoutCommand
        if (action === "reboot") return powerRebootCommand
        if (action === "shutdown") return powerShutdownCommand
        if (action === "bios") return powerBiosCommand
        return []
    }

    function powerActionEnabled(action) {
        var cmd = powerCommand(action)
        if (typeof cmd === "string")
            return cmd.length > 0
        return cmd && cmd.length !== undefined && cmd.length > 0
    }

    function powerMenuItems() {
        var out = []
        var actions = powerMenuActions
        if (!actions || actions.length === undefined)
            return out
        for (var i = 0; i < actions.length; i++) {
            var entry = actions[i]
            if (entry && powerActionEnabled(entry.action))
                out.push(entry)
        }
        return out
    }

}
