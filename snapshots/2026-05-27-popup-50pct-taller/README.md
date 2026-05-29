# Popups - 50% Taller Vertically (Ultrawide Readability)

**Date**: 2026-05-27

## Changes
All major popups had their vertical size increased by approximately 50%:

### Workspace Preview Popup (`wsPreviewPopup`)
- Per-row height increased from 26 → 38
- Top/bottom margins and spacers increased ~50%
- Max height raised from 760 → 1140
- Added extra breathing room throughout the calculation

### Calendar Popup
- `implicitHeight`: 355 → **530**

### Audio Popup
- `implicitHeight`: 315 → **470**

### Audio Device List Popup
- Dynamic calculation scaled up ~50% (per-item 26→39, buffers increased)

This addresses the user's request for larger popups on an ultrawide monitor so content is easier to read without squinting.

## Snapshot
`~/.config/quickshell/snapshots/2026-05-27-popup-50pct-taller/`

## Note on Click Functionality
The user also reported that the "click to jump to specific app + switch workspace" from the popup is still not working. This snapshot focuses on the size request. The click issue is being tracked separately (see previous snapshots for the latest attempts using `Qt.callLater`, explicit workspace dispatch, etc.).

Next steps for the click bug (if still broken) could include:
- Using `Quickshell.exec` + `hyprctl` with a small sleep
- Trying class-based `focuswindow` as fallback
- Adding debug logging of the address being used

## Files Changed
- `.config/quickshell/shell.qml` (popup height values and calculations)