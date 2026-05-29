# 2026-05-30 — Media Widget (MPRIS + Cava-style Visualizer)

## What was added
A complete, polished, centered media player widget for the top bar, built on Quickshell's native MPRIS service (`Quickshell.Services.Mpris`).

### Top Bar Widget (centered)
- **Perfectly centered** on the bar (overlay anchors.centerIn inside the glass barBg).
- **Only visible** when at least one media stream is active (playing or paused with a title). Multiple browser tabs with paused media are handled gracefully.
- **Prominent title** (elided, bold, larger font) with a beautiful **pure-QML "cava-like" animated waveform** behind it.
  - 12 thin vertical bars with organic sine motion (different phases + frequencies).
  - Amplitude and color boost when the current stream is actively playing.
  - No external `cava` binary required — works out of the box.
- **Left click**: toggle play/pause on the current stream.
- **Right click**: opens the rich popup menu (see below).
- **Mouse wheel**: cycles between active media streams (perfect for multiple browser tabs or apps).
- Glassmorphic pill styling that perfectly matches the existing audio/clock/tray/power pills.

### Rich Right-Click Popup
- Large glassmorphic card (matches the style of the audio popup and power menu).
- **Large album art** (with graceful fallback icon when no art is provided).
- Full metadata: **Title** (big), **Artist**, **Album**.
- **Application name** that is currently playing the media (identity or desktopEntry).
- Transport controls:
  - Previous / Play-Pause / Next
  - Buttons are disabled (dimmed) when the current player does not support the action (`canGoPrevious`, `canTogglePlaying`, `canGoNext`).
- **Seek bar** (click anywhere to jump) + live time labels.
  - Only shown when the player reports `canSeek` and `lengthSupported`.
  - Dragging not implemented in v1 (click-to-seek is reliable across players).
- **Player / Stream selector** (appears automatically when 2+ streams are active):
  - Horizontal scrollable row of "chips".
  - Each chip shows the app name + short title.
  - Current stream is highlighted with accent border.
  - Click any chip to switch the bar widget + popup to that stream instantly.

## Technical notes
- Pure QML implementation (no external processes for the visualizer).
- Fully reactive: `Mpris.players` changes (new tab starts playing, a player quits, etc.) automatically update the bar and popup.
- Smart filtering: prefers actively playing streams; falls back to paused ones that still have titles (handles the "multiple paused browser tabs" case you mentioned).
- All existing widgets (workspaces, tray, audio volume, clock, notifications, power) are completely untouched.
- Uses the exact same glassmorphic color tokens, pill radius, and popup positioning patterns as the rest of the bar.

## How to reload
```bash
qs -r
# or killall -USR1 quickshell (depending on your setup)
```

## Future polish ideas (not implemented here)
- Drag on the seek bar for continuous seeking.
- Keyboard navigation inside the popup (arrow keys + Enter).
- Optional small "app icon" next to the title in the bar pill.
- Optional cava binary integration (via Quickshell.Io.Process + fifo) for real audio-reactive bars instead of the synthetic sine version.

This matches every requirement you listed:
- Centered top-bar pill ✓
- Hidden when no media ✓
- Shows title (prominent) ✓
- Play/pause ✓
- Cava-like bars in background ✓
- Right-click rich popup ✓
- Scroll wheel cycles streams ✓
- Full controls + art + seek + player selector in popup ✓
