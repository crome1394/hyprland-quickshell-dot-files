# Snapshot: Reverted Bar to Previous Tall / Ultrawide State

**Date:** 2026-05-29

## What happened
The previous compaction (2026-05-29-compact-bar-50pct-vertical) successfully made the top bar much shorter (54px → 32px + smaller pills and fonts).

However, the user preferred the previous taller bar height and sizing that existed before the compaction (the "ultrawide readability" version with taller pills).

## Action taken
- Fully reverted the bar height, pill heights, internal element sizes, fonts, icons, and spacing back to the pre-compaction state.
- The sound popup widget and all its internals (larger icons/text, taller popup) were untouched throughout and remain exactly as they were.

## Current state restored
- Bar `implicitHeight`: **54**
- Workspaces pill: **40**
- Tray / Audio / Clock pills: **36**
- All inner fonts, icon sizes, button dimensions, and spacing restored to the larger ultrawide versions.

The audio widget (cycle views + full popup with device selectors, sliders, mute buttons, wheel support, etc.) is completely unaffected and remains in its final polished state.

## Files
- `shell.qml` (restored taller bar)
- `README.md` (this note)

All previous snapshots (including the compact one and all audio widget versions) are preserved in sibling directories.
