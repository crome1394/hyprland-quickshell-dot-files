# Hyprland + Quickshell Dotfiles

Personal status bar configuration for Hyprland using Quickshell.

## Project Structure

- `shell.qml` — Thin main entry point (~300 lines). Delegates almost everything to widgets.
- `widgets/` — Self-contained, reusable UI components (pills, popups, menus).
- `components/` — Low-level reusable pieces (VolumeBar, CavaVisualizer, etc.).
- `Theme.qml` — Single source of truth for all colors, glassmorphic tokens, spacing, and metrics.
- `widgets/HyprConfigInsp.qml` — Hyprland Config Inspector overlay (keybindings, env, runtime options, config files, sysmon tabs, logs, services).

## Design Goals

- Clean modular architecture (extracted from a single ~3300 line file).
- Glassmorphic / frosted acrylic aesthetic (Catppuccin-inspired).
- IPC-driven features (e.g. `qs ipc call help toggle`).

## Key Widgets

| Widget           | Main Interactions                  | Notes |
|------------------|------------------------------------|-------|
| Workspaces       | Click / Scroll wheel               | Shows only active + occupied |
| Media            | Left click (toggle), Scroll, Right click (popup) | MPRIS + live Cava visualizer |
| Audio            | Left (cycle view), Middle (mute), Right (device menu) | Speaker + Mic controls |
| Config Inspector | `qs ipc call hyprConfigInsp toggle` | Parsed live from your Hyprland config + sysmon |

## Theming (Fully Centralized)

**All** visual properties live in a single `Theme.qml`.

- Edit **only** `Theme.qml` — changes apply globally and instantly.
- `shell.qml` instantiates it once and exposes every single property as an alias on the root `bar` object.
- Widgets just use `bar.accent`, `bar.sliderFill`, `bar.iconSpeakerMuted`, `bar.popupRadiusLarge`, `bar.wsButtonWidth`, `bar.fontClock`, etc.
- Low-level components (VolumeBar, MiniVolumeBar, CavaVisualizer) have safe fallbacks to the theme values.
- Direct import also works: `import "Theme.qml" as T; T.Theme.muted`

See the big comment header at the top of `Theme.qml` for the complete categorized list + usage guidance.

## Development Notes

This configuration was refactored incrementally, one widget at a time. Old development snapshots have been removed for cleanliness.

For questions about a specific component, look inside the corresponding file under `widgets/`.

## Refactoring Complete (2026-06-01)

The full project is now wrapped up:

- Per-widget refactoring completed and verified incrementally (see `QUICKSHELL_REFACTOR_STATUS.md` for history).
- Conservative Global Consistency Pass (STAGE Final) completed: outer borders (`controlBorderWidth`), dividers (`divider*` tokens), colors (raw `Qt.rgba`/hex centralized), fonts (`bar.fontFamily`/`bar.fontMono` on headers/labels), sizes (`bar.pillHeight`), and spacing in outer/simple elements only.
- `shell.qml` outer bar structure cleaned (launcher area, vertical dividers, shadows/highlights where tokens applied).
- All work followed the strict gated process (audit → user approval → backup commit → apply → clean-load verification). Scope remained conservative (outer pill/card + simple text/labels; no dense inners touched).

See `QUICKSHELL_REFACTOR_STATUS.md` (especially the "Global Consistency Pass – Wrap-up" section) for the complete history, progress table, and details. Quickshell loads cleanly with no regressions.

## License

Personal configuration. Feel free to take inspiration.
