# Workspace Hover Popup - Application Icons Added

**Date**: 2026-05-27  
**Change**: Added app icons to the workspace hover preview popup

## Summary
You liked the current lightweight approach (no expensive pixel workspace thumbnails on hover).  
The only request was to show **application icons** in the popup instead of plain text.

### What Changed
- The `wsPreviewPopup` (shown when hovering any workspace button) now displays a small icon next to each window.
- Icons are resolved using `Quickshell.iconPath(className, fallback)`.
- It uses the window's class from `HyprlandToplevel.lastIpcObject["class"]` (the same source Hyprland provides).
- Layout upgraded from simple bullet text to a proper `RowLayout` with `IconImage` + title.
- Popup width increased slightly (280 → 320) and per-item height calculation adjusted to give icons room.
- Added `import Quickshell.Widgets` to support `IconImage`.

### Visual Result
When you hover a workspace button, the popup now shows:

```
Workspace 3  ·  4 window(s)
[icon]  Telegram (TelegramDesktop)
[icon]  Discord (discord)
[icon]  kitty - zsh
[icon]  ...
```

Icons fall back gracefully to `application-x-executable` when no perfect match exists in your icon theme.

### Why This Approach
- Still extremely lightweight (no screencopy, no polling, no heavy image buffers).
- Matches the "efficient" requirement from the original migration.
- Gives the "at a glance" feeling you wanted without the cost of real graphical workspace thumbnails.

## Snapshot Location
`~/.config/quickshell/snapshots/2026-05-27-workspace-popup-icons/`

Full `shell.qml` + this README preserved.

Previous snapshots remain available if you ever want to compare or revert the icon feature.

## Notes
- Icon quality depends on your system's icon theme having good entries for the app classes (most common apps are well covered).
- If some apps show a generic icon, that's normal and expected.
- We can later add a small "AppSearch" style guesser (like the illogical-impulse dots use) if you want smarter icon resolution for stubborn apps.

Enjoy the improved popup!
