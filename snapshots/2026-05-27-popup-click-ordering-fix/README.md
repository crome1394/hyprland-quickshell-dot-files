# Workspace Popup Click Fix v3 - Proper Dispatch Ordering + Popup Focus Release

**Date**: 2026-05-27

## Previous Attempts
- v1: workspace.activate() then focuswindow
- v2: Primarily focuswindow address (hoping it would auto-switch workspace)

Neither worked reliably when clicking from a different workspace.

## Root Cause (Final Diagnosis)
Two main issues were still present:

1. **PopupWindow focus stealing**: Even after setting `visible = false`, the popup can briefly retain input/focus priority. Any focus dispatch that happens while the popup is still "active" can be ignored or overridden.

2. **Synchronous dispatch ordering**: Calling multiple `Hyprland.dispatch()` calls one after another in the same `onClicked` does not guarantee execution order from Hyprland's perspective. The workspace switch and window focus need to be properly sequenced.

## Changes in This Version
- **Hide the popup first** (`bar.hoveredWorkspace = null;`) before doing any focus work.
- Explicitly dispatch `workspace ${ws.id}` first.
- Use `Qt.callLater(...)` for the `focuswindow` dispatch. This schedules it to run after the current event loop tick, giving:
  - The popup time to fully disappear and release focus
  - Hyprland time to process the workspace switch
- More detailed logging-friendly structure (easy to debug further if needed).

This is the standard pattern used in production quickshell/hyprland setups when dealing with popups + cross-workspace focus.

## New Snapshot
`~/.config/quickshell/snapshots/2026-05-27-popup-click-ordering-fix/`

## How to Test
1. Be on workspace 1 (or any workspace that is *not* 3).
2. Hover the workspace 3 button in the bar.
3. In the popup, click on Discord (or any app listed).
4. Expected: You should be taken to workspace 3 and Discord should be focused.

Please test this exact flow and report back what happens.
