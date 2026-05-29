# Snapshot: Compact Bar — Reduced Vertical Space (~40-50% thinner)

**Date:** 2026-05-29

## What changed
After adding the System Tray and Audio widget (and previous ultrawide readability increases), the top bar had grown quite tall (`implicitHeight: 54` + tall pills at 36-40px).

This snapshot significantly reduces the vertical footprint:

### Bar height
- `implicitHeight`: 54 → **32** (much more compact)
- `barBg` top/bottom margins: 3 → **2**

### Pill heights (right side + workspaces)
- Workspaces pill: 40 → **28**
- Tray, Audio, Clock pills: 36 → **26**

### Internal content scaled down to match
- Workspace buttons: height 32→24, width 42→36, fonts 17/15 → **14/12**, radius 8→6
- Tray icons: 18px → **16px**, container 20→18, row spacing 8→6
- Clock text: 15px → **12px**
- Audio pill (in-bar):
  - Icons: 16px → **14px**
  - Slider wrapper areas reduced (92x16 → 80x14, dual minis 44x14 → 40x12)
- RowLayout internal spacing: 14 → **10**, side margins 20 → **16**

### Result
The entire top bar is now substantially shorter vertically while remaining fully functional and readable. All widgets (workspaces, tray, audio cycle views, clock) still fit nicely with good touch/hover targets.

Popups and the audio widget internals were left at their previous (larger) sizes since the request was about the bar "vertical rows".

## Files
- `shell.qml`
- `README.md`

All previous audio widget snapshots remain in sibling directories.

This should give you back a lot of vertical screen real estate.
