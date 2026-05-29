# Workspace Hover Popup - Vertical Spacing / Margin Fix

**Date**: 2026-05-27  
**Issue**: Popup content was being cut off at the bottom when multiple windows were present (e.g. Telegram visible but Discord hidden on workspace 3).

## Changes Made
- Increased top and bottom margins on the main content ColumnLayout:
  - `topMargin: 12`
  - `bottomMargin: 14`
- Added an explicit small top spacer (`Item` height 4) above the header for visible breathing room right after the top border.
- Increased the bottom spacer from 8px to **14px** so there is clear blank space below the last icon + title before the rounded bottom border.
- Improved the `implicitHeight` calculation to be more accurate and generous:
  - Better accounting for header + per-item height + extra top/bottom padding.
  - Raised minimum and maximum bounds slightly to prevent cutoff.
- Inner window list spacing kept at 4 (icons + text rows still feel tight but balanced).

### Visual Result (as requested)
```
-------------------------
<-- extra blank space (top spacer + increased topMargin)
Workspace 3  ·  2 window(s)
<Icon> Telegram
<Icon> Discord
<-- generous blank space (increased bottomMargin + 14px spacer)
-------------------------
```

This matches the layout you described.

## Snapshot
`~/.config/quickshell/snapshots/2026-05-27-popup-vertical-spacing-fix/`

Full `shell.qml` + this README.

## Notes
- The popup now has noticeably more vertical "air" while still remaining compact.
- If you want even more space (or less), we can adjust the topMargin/bottomMargin values or the final spacer height.
- No change was made to the bar itself or the workspace buttons.

Reload quickshell and test hovering workspace 3 (or any workspace with 2+ windows). The bottom item should no longer be clipped.
