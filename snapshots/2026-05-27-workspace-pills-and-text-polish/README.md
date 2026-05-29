# Quickshell Bar Updates - Pills + Text Polish (Workspace + Clock)

**Date**: 2026-05-27  
**Version**: Post-v2 iteration (pills & text refinements)  
**Snapshot of**: shell.qml

## Changes Requested & Implemented
1. **Workspace text: white + bold like the date/time**
   - Icon and number now use `bar.clock` (#ffffff) for inactive state.
   - Both Text items: `font.bold: true` (always, matching the clockLabel style).
   - Hover (yellow) keeps dark text for contrast; active keeps the light active color.

2. **Text a little bigger**
   - Workspace icon: 14px (was 12)
   - Workspace number: 12px (was 11), always bold.
   - Buttons remain compact; pill provides outer breathing room.

3. **Extra bottom space in workspace hover popup**
   - Added `Item { Layout.preferredHeight: 8 }` spacer at the end of the preview ColumnLayout.
   - Ensures the last listed app/window has visible separation from the popup's bottom rounded border.

4. **Encapsulate widgets in their own pill (matching eww)**
   - Added pill theme properties (after reviewing eww.scss "Shared module pill style"):
     - `pillBg: "#1a1a1a"` (exact match to eww .uptime/.clock/.monitor-pill etc.)
     - `pillBorder: "#45475a"`, `pillRadius: 10`
   - **Workspaces group**: Now wrapped in `Rectangle` "workspacesPill" with the pill background, radius, and subtle border. The individual workspace buttons (with their active/hover states) sit inside the pill container. Provides the "encapsulated" look similar to your eww right-modules.
   - **Date/time (clock)**: Updated `clockButton` Rectangle to use `pillBg` by default (instead of transparent). Always has the 1px border (subtle pillBorder when idle, accent on hover). Hover still brightens to `surface` + accent border for feedback. Radius uses the shared pillRadius.

5. **Other polish**
   - Clock hover behavior preserved/enhanced for consistency with the new pill aesthetic.
   - All changes keep the efficient reactive (no polling) nature of the original workspace widget.
   - Layout spacing and sizes tweaked slightly so pills feel intentional without crowding the bar.

## Visual Result
- Left: Dark pill container holding the row of workspace icons+nums (white/bold text, yellow hover, dark active highlight).
- Right (after spacer): Matching dark pill around the full date/time string (white bold monospace).
- Hover popup for workspaces: extra 8px bottom padding for breathing room.
- Matches the eww pill aesthetic you liked (#1a1a1a + radius 10 + borders) while staying in the quickshell catppuccin-ish theme.

## Snapshot History (in ~/.config/quickshell/snapshots/)
- 2026-05-26-initial-bar-before-workspaces/
- 2026-05-26-workspaces-v1-core+preview/
- 2026-05-26-workspaces-v2-polish-dynamic-popup/
- **2026-05-27-workspace-pills-and-text-polish/** ← this one (pills for workspaces + clock, text white/bold/larger, popup bottom space)

Each has full shell.qml + explanatory README.

## Testing Notes
- Launch quickshell (after stopping eww if running in parallel).
- Verify left workspaces live inside a dark rounded pill.
- Clock on right is now also a consistent pill.
- Workspace text is bolder/larger/white by default.
- Hover any ws → preview popup has extra space below the last line.
- Scroll, click, active states all unchanged in behavior.

If you add more widgets later (e.g. music, sysinfo), wrap them the same way using `bar.pillBg` + radius for a uniform "all widgets in pills" look.

Thanks for the clear feedback — these small tweaks make it feel even closer to your eww setup while keeping the modern quickshell advantages!
