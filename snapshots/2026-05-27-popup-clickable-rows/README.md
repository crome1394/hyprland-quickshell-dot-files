# Workspace Hover Popup - Clickable Window Rows + Doubled Max Height

**Date**: 2026-05-27

## Changes

### 1. Doubled Maximum Popup Height
- The hard cap on `implicitHeight` was raised from 380px → **760px** (as requested).
- This allows workspaces with many windows to fully display without clipping, while still respecting the generous top and bottom margins/spacers.

### 2. Clickable Window Entries
Each row in the popup (icon + title) is now fully interactive:

- **Hover effect**: Subtle light background highlight (`Qt.rgba(1,1,1,0.07)`) appears when mousing over a row.
- **Click behavior**:
  1. Switches to the workspace the popup belongs to (using `workspace.activate()`).
  2. Focuses the specific application/window you clicked on (using `Hyprland.dispatch("focuswindow address:0x...")` with the window's Hyprland address).
  3. Closes the popup automatically.

**Example**:
- Hover workspace 3 → see Telegram and Discord.
- Click the Discord row → jumps to workspace 3 and focuses Discord directly.

This is implemented using a `MouseArea` inside a `Rectangle` container for each delegate (with `hoverEnabled: true`).

The entire row (not just the icon) is clickable for better usability.

## Technical Notes
- Window focusing uses the `address` property exposed by `HyprlandToplevel` (`modelData.addressStr()`).
- Workspace activation uses the existing `HyprlandWorkspace.activate()` method we already had.
- No external scripts or polling were added — everything stays reactive and efficient.

## Snapshot
`~/.config/quickshell/snapshots/2026-05-27-popup-clickable-rows/`

Contains the full `shell.qml` at this point in time plus this README.

---

This gives you both the taller popup you asked for and the convenient "click to jump + focus" behavior on the icons/titles.

Test it by hovering a workspace with multiple apps and clicking one of the rows. Let me know how it feels!