# Larger Top Bar + Widget Text for Ultrawide (5120x1440)

**Date**: 2026-05-27  
**Change type**: Readability polish for large ultrawide monitor  
**File**: shell.qml

## What Was Changed
User requested: taller top bar + bigger text on widgets so everything is easily readable "at a glance" without squinting on a 5120x1440 ultrawide.

### Exact Increases Applied
- **PanelWindow** `implicitHeight`: 46 → **54** (+8px). This is the overall reserved height for the bar.
- **Internal RowLayout**:
  - left/rightMargin: 16 → **20**
  - spacing: 12 → **14**
- **Workspaces pill** (`workspacesPill`):
  - `preferredHeight`: 34 → **40**
  - Inner buttons (`wsBtn`): 38×28 → **42×32** (wider + taller)
  - Icon text: 14px → **17px**
  - Number text: 12px → **15px**
  - Both remain bold + white (like clock)
- **Clock / Date-time pill** (`clockButton`):
  - `preferredHeight`: 30 → **36**
  - Text: 13px → **15px** (monospace, bold, white)
- **barBg margins** (top/bottom 3) left unchanged for now — the extra overall height gives natural padding.
- **Popups** (calendar + workspace preview): No manual changes needed. Both use `bar.implicitHeight + N` for y-positioning, so they automatically sit correctly below the taller bar.

All other behavior (reactive workspaces, scroll, hover yellow #fdf9db, pills, preview popup with bottom breathing room, etc.) remains exactly the same.

## Visual Impact on Ultrawide
- Bar is noticeably more substantial and easier to read from a normal sitting distance.
- Workspace icons/numbers and the full date+time string are larger and bolder.
- Still compact enough that it doesn't eat too much vertical real-estate on 1440p.
- Pills and hover states scale cleanly with the new sizes.

## Snapshot History
This is the latest in the series:
- .../2026-05-26-initial-bar-before-workspaces/
- .../2026-05-26-workspaces-v1-core+preview/
- .../2026-05-26-workspaces-v2-polish-dynamic-popup/
- .../2026-05-27-workspace-pills-and-text-polish/
- **2026-05-27-larger-bar-ultrawide/** ← current (taller bar + bigger widget text)

Each directory contains the exact `shell.qml` at that point in time plus a README.

## How to Use / Revert
Just keep using the current `.config/quickshell/shell.qml`.  
If you ever want to go back to the previous (smaller) sizes, copy the shell.qml from the 2026-05-27-workspace-pills-and-text-polish snapshot back into place.

## Future Tweaks (if desired)
- If 54px still feels small, we can go to 58–60.
- Calendar popup could be made a bit larger proportionally.
- We could expose the sizes as theme properties (e.g. `barHeight`, `widgetTextSize`) for easier experimentation later.

Everything is still 100% efficient (no polling) and matches the previous eww-to-quickshell migration requirements.

Enjoy the easier-to-read bar on the big ultrawide!
