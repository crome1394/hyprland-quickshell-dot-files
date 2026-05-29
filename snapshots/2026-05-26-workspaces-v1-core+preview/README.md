# Quickshell Workspaces Widget v1 - Core + Hover Preview

**Date**: 2026-05-26  
**Version**: v1 (initial implementation)  
**File**: shell.qml (integrated)

## Features Implemented (matching requirements)
- **Icons + numbers**: Exact same mapping as eww.yuck (1: code, 2:🦁, 3: chat, 4: browser, 5:🕹 game, 6-10 symbols, fallback).
- **Only active workspaces**: Filters to ws with toplevels (windows) OR (active || focused). Sorted by id. Matches eww unified listener logic.
- **Active highlighted**: Dark #1e1e1e bg + light text + subtle border (inspired by eww .active).
- **Mouseover highlight**: Uses exact shade from eww working scss: #fdf9db (pale yellow) bg + dark text. Smooth ColorAnimation.
- **Scroll wheel**: WheelHandler on the workspaces area. Scroll wheel *up* (positive angleDelta.y) advances +1 in the *shown list* (next in current active/occupied). Down goes previous. Uses switchToRelative + target.activate(). Efficient, no polling.
- **Click to switch**: MouseArea on each, calls ws.activate() (Quickshell convenience, dispatches focus).
- **Preview on highlight**: When hovering any ws button, a PopupWindow appears below the bar (left-aligned) showing:
  - "Workspace N · X window(s)"
  - Bullet list of window titles (truncated) + (class) from lastIpcObject if present.
  - "(empty workspace - only active)" note if no windows.
  - Popup stays open if mouse enters the preview itself; graceful hide timer (280ms) on leave.
- **Far left in top bar**: Replaces the "cachy" placeholder text. Compact (38px wide buttons, 28px tall).
- **Efficient / no unnecessary polling**: 
  - Fully reactive: uses Quickshell.Hyprland.workspaces model + toplevels (backed by Hyprland IPC socket events).
  - updateShownWorkspaces() called on valuesChanged + focusedWorkspaceChanged (light JS filter/sort, <10 items).
  - No Timers for polling, no deflisten scripts, no socat in user code. Matches spirit of eww's unified listener but native and cheaper.
  - Hover/animations only on interaction.

## Theme Integration
- Matches shell.qml Catppuccin-ish palette.
- Added ws* color properties for easy theming.
- Font fallback includes "JetBrains Mono Nerd Font" for icons (same as eww).

## Files Changed
- shell.qml: added import, state/funcs (getWsIcon, updateShown..., switchToRelative), UI Row+Repeater in left Layout, preview PopupWindow + timer + positioning.

## How to Test
1. Ensure quickshell is your bar (temporarily kill eww or comment in hyprland.lua).
2. `quickshell` (or reload).
3. Open/close apps on different workspaces (1-6+ per your hypr rules).
4. Observe only relevant ws appear.
5. Hover, scroll, click.
6. Active one has dark highlight.

## Limitations / Future (v2+)
- Popup height fixed (120px); many windows will clip (rare on bar use).
- No graphical (pixel) workspace thumbnail (would require Quickshell screencopy + Hyprland surface capture = more resources + complexity; against "efficient, no unnecessary polling" req. Text title preview is lightweight and useful).
- If some window open/close not instantly reflected: can add a refresh() button calling Hyprland.refreshWorkspaces() if exposed.
- Scroll "next" is within currently *shown* (stable UX); if you want pure hypr "e+1" including creating new, easy one-line change.
- Multi-monitor: currently uses global Hyprland (focused etc); can scope to Hyprland.monitorFor(...) like examples if needed.

## Snapshot Purpose
This captures the first complete, self-contained implementation. Later iterations (styling polish, separate component extraction, better dynamic popup sizing, optional app icons via Quickshell.iconPath) will be snapshotted in sibling dirs.

See parent snapshots/ for eww reference and other versions.
