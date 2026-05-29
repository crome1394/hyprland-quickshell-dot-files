# Snapshot: Audio Volume Widget (Cycle + Popup)

**Date:** 2026-05-28  
**Description:** Full-featured sound management widget added to the right side of the top bar (immediately left of the date/time clock pill).

## Features Implemented

### Bar Widget (Pill, right of workspaces, left of clock)
- **3-cycle view** toggled by **left-click** on the pill:
  1. **Speaker view**: Icon (/) + clickable slider + percentage (e.g. "42%")
  2. **Microphone view**: Icon (󰍬/󰍭) + clickable slider + percentage
  3. **Dual view**: Speaker icon + small bar + Mic icon + small bar (compact side-by-side)

- **Slider interaction**:
  - Click anywhere on the bar to set exact volume level (0-100%).
  - Hover + mouse wheel: ±5% increments (0.05 steps).

- **Middle mouse button** (anywhere on the audio pill):
  - Speaker view → toggle speaker mute
  - Mic view → toggle mic mute
  - Dual view → toggle speaker mute (primary)

- **Right mouse button** on pill → opens the rich popup menu (see below). Clicking the pill while popup is open also closes it.

- Visuals match existing pill style (dark #1a1a1a bg, rounded, subtle border, accent highlights on hover). Muted state uses red (#f38ba8) for icon/text/fill.

### Popup Menu (right-click)
- Two sections: **Playback** and **Recording**.
- **Device dropdowns** (click the selector row with ▼):
  - Separate popups listing available hardware devices (filtered: !isStream).
  - Click a device to set it as the system default (Pipewire.preferredDefaultAudioSink / Source).
  - Current default is marked with ✓.
- **Full-size clickable sliders** with live percentage.
- **Mouse wheel** over the slider areas also adjusts ±5%.
- **Mute / Unmute buttons** per section (toggle + color feedback).
- Icons update to reflect mute state.
- Click outside popups or right-click the bar pill again to close.

### Technical
- Uses `Quickshell.Services.Pipewire`
- `PwObjectTracker` keeps default sink/source alive for reactive volume/mute.
- `Pipewire.nodes` scanned for device lists (refreshed on changes).
- Pure QML, no external scripts or polling.
- All changes are live and propagate immediately to Pipewire.

## How to Use
1. Left-click the audio pill (between workspaces and clock) repeatedly to cycle Speaker → Mic → Dual → Speaker...
2. Hover the relevant slider area + scroll wheel to fine-tune in 5% steps.
3. Click the slider bar directly for coarse jumps.
4. Middle-click the pill to mute the active device (speaker in dual).
5. Right-click the pill → choose devices from the dropdown rows, adjust big sliders, or hit the Mute buttons.
6. Changes affect the system defaults and are reflected everywhere (including other apps and the bar itself).

## Files in This Snapshot
- `shell.qml` — full bar configuration containing the audio widget + popups + helpers
- `README.md` — this document

## Previous Snapshots (for reference)
See sibling directories for workspaces, popup, and bar polish iterations.

## Notes / Future Polish Ideas
- Could extract AudioWidget.qml + subcomponents for cleanliness.
- Add per-device volume memory if needed (advanced).
- Tooltip on hover showing full device name.
- Keyboard support (e.g. when focused).
- Visual "peak" meters if Pipewire provides peak data easily.

This fulfills all requested requirements for the sound widget.
