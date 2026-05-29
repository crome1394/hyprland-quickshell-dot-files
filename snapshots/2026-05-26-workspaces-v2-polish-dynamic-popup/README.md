# Quickshell Workspaces Widget v2 - Polish (Dynamic Preview Popup)

**Date**: 2026-05-26  
**Version**: v2 (minor polish on v1)  
**Based on**: v1-core+preview

## Changes in This Version
- Made `wsPreviewPopup.implicitHeight` reactive: scales with actual window count on the hovered workspace (min 60 / max 200, ~16px per entry). Prevents wasted space on empty ws and clipping on busy ones.
- Verified launch: quickshell loads the config cleanly (no QML parse errors on Hyprland import, Repeater, WheelHandler, PopupWindow, Connections, or JS helpers).
- Runtime: Hyprland IPC model drives everything. No user-level polling, timers only for hover-dismiss UX.

## Snapshot of All Versions So Far (in ~/.config/quickshell/snapshots/)
- 2026-05-26-initial-bar-before-workspaces/ : Original simple bar (cachy label + clock + calendar).
- 2026-05-26-workspaces-v1-core+preview/ : First full implementation (all reqs: icons, only-active filter, yellow hover #fdf9db, scroll, click, active highlight, efficient reactive, text preview popup on hover).
- 2026-05-26-workspaces-v2-polish-dynamic-popup/ : This one (height polish + launch validation).

See each README.md for detailed requirements mapping, eww reference, limitations, and test steps.

## Next Possible (Not in This Task)
- Extract pure widget logic + UI into standalone Workspaces.qml (with internal state) for reusability.
- Optional: app icons in the ws buttons (using Quickshell.iconPath + biggest toplevel class like in illogical-impulse examples).
- Optional graphical thumbnails: would use screencopy plugin + Hyprland surface, but deliberately avoided per "efficient / no unnecessary polling" requirement.

All code versions preserved exactly as requested.
