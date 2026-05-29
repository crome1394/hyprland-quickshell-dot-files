# Initial Quickshell Bar Snapshot - Before Workspaces Widget

Date: 2026-05-26
Purpose: Baseline before implementing the migrating workspace widget from eww.

## Current State
- Simple bar with "cachy" label left, spacer, clock (live updating) on what ends up right.
- Calendar popup on clock click.
- Theme: Catppuccin-inspired dark colors (#1e1e2e bg etc.)
- No workspace widget yet.
- Using eww bar in parallel (see hyprland.lua autostart).

## EWW Reference (reviewed)
- Workspace icons hardcoded by ID (1: code , 2: 🦁, 3: chat , 4: browser , 5: game 🕹, etc.)
- Only shows workspaces with windows OR the active one (from unified `scripts/workspaces` event listener on hypr socket).
- Active: .active class (dark bg)
- Hover: in working version used rgb(253, 249, 219) pale yellow bg + black text. (main eww.scss had blue, but user specified check for yellow)
- Click: hyprctl dispatch to focus workspace by id
- Scroll in older versions used relative +/-1 dispatch
- Efficient: single socat listener, no polling

## Requirements Mapping
- Icons + numbers per ws
- Only active (occupied + current)
- Highlight active
- Yellow hover from eww
- Scroll wheel to switch (advance next)
- Preview on highlight (hover) - to implement via popup list of windows if feasible
- Far left in top bar
- Efficient: leverage Quickshell.Hyprland reactive model (IPC backed, no manual poll)

Next versions will be snapshotted here as we iterate the implementation.
