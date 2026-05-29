# Workspace Hover Popup - Proper Content-Driven Sizing Fix

**Date**: 2026-05-27  
**Problem**: Even after adding top/bottom margins and spacers, the popup was still clipping the last items (Telegram visible, Discord cut off, etc.).

## Root Cause
The `implicitHeight` formula on `PopupWindow` was still under-calculating the actual space required once all the following were added together:
- Outer ColumnLayout margins (top 12 + bottom 14)
- Extra top spacer
- Header
- Multiple outer `spacing: 6`
- Each window row (IconImage + Text)
- Inner list spacing
- Generous bottom spacer
- Safety buffer

Additionally, `Layout.fillHeight: true` on the inner window list was causing the layout system to prioritize stretching over letting the popup grow naturally to fit its content.

## Changes in This Version
1. **Completely rewritten height calculation** with explicit line-by-line accounting of every visual element (topMargin, topSpacer, header, spacing, per-row height, inner spacing, bottomSpacer, bottomMargin + safety buffer).

2. **Raised the maximum height** from 240 → **380** so the popup can grow properly when a workspace has several windows.

3. **Removed `Layout.fillHeight: true`** from the window list ColumnLayout. This lets the list size naturally to its children, allowing the PopupWindow's `implicitHeight` to actually control the final size.

4. Increased `implicitWidth` slightly to 340 for comfort with the icons + text.

## Result
The popup should now expand to fully contain:
- The header
- All icon + title rows
- The generous top and bottom blank space you specifically requested

Example desired layout should finally render without clipping:

```
-------------------------
   (top breathing room)
Workspace 3 · 2 window(s)
<Icon> Telegram
<Icon> Discord
   (bottom breathing room)
-------------------------
```

## Snapshot
`~/.config/quickshell/snapshots/2026-05-27-popup-proper-sizing/`

This is the version that should finally solve the vertical clipping issue while preserving the margins you asked for.

If you still see any cutoff after reloading, please tell me the exact number of windows on that workspace and whether the popup is getting taller at all.
