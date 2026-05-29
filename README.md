# Hyprland + Quickshell Dotfiles

Personal status bar configuration for Hyprland using Quickshell.

## Project Structure

- `shell.qml` — Thin main entry point (~300 lines). Delegates almost everything to widgets.
- `widgets/` — Self-contained, reusable UI components (pills, popups, menus).
- `components/` — Low-level reusable pieces (VolumeBar, CavaVisualizer, etc.).
- `Theme.qml` — Single source of truth for all colors, glassmorphic tokens, spacing, and metrics.
- `HelpMenu.qml` — Rich centered overlay showing keybindings (parsed from `hyprland.lua`), environment variables, and system info.

## Design Goals

- Clean modular architecture (extracted from a single ~3300 line file).
- Glassmorphic / frosted acrylic aesthetic (Catppuccin-inspired).
- Hardware security key authentication for the git repository.
- IPC-driven features (e.g. `qs ipc call help toggle`).

## Key Widgets

| Widget           | Main Interactions                  | Notes |
|------------------|------------------------------------|-------|
| Workspaces       | Click / Scroll wheel               | Shows only active + occupied |
| Media            | Left click (toggle), Scroll, Right click (popup) | MPRIS + live Cava visualizer |
| Audio            | Left (cycle view), Middle (mute), Right (device menu) | Speaker + Mic controls |
| Help Menu        | `qs ipc call help toggle`          | Parsed live from your Hyprland config |

## Theming

All visual tokens live in `Theme.qml`. Widgets receive them via the `bar` property (with many aliases for compatibility during the extraction).

## Development Notes

This configuration was refactored incrementally, one widget at a time. Old development snapshots have been removed for cleanliness.

For questions about a specific component, look inside the corresponding file under `widgets/`.

## License

Personal configuration. Feel free to take inspiration.
