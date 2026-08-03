# Changelog

Notable changes for people upgrading this config. Day-to-day usage is in [README.md](README.md) and [docs/](docs/).

## 2026-08 — Control bar & FreshRSS

- **SysStats pill layout:** center CPU/Memory/GPU; sections hug content (Memory no longer clips); snug fit with no empty side ballast; single separator slots between visible gauges.
- Control strip: Position, Wallpaper, Widgets, Options, Launch, Autostart, **Services**, **Keybinds**, Clock (toolbar on bottom).
- **Keybinds** panel: browse `keybindings.lua` by category; edit key chord / category / description (in-place write + backup; Reload Hypr separate).
- **Services** panel: systemd user/system units with filter + Start/Stop/Restart (reuses Inspector `ServicesView`).
- Widgets panel: A–Z list; row layout ✓/name · L/C/R · ↑↓; horizontal width scale.
- Options: UI scale, workspaces, sticky applets, Sys Stats gauges, FreshRSS server Test/Save.
- FreshRSS secrets moved to `~/.config/freshrss-quickshell/freshrss.env` (outside git).
- **Autostart fix:** add copies the system `.desktop` (keeps real `Exec=`) instead of synthesizing `gtk-launch` entries; run uses `Exec=` only (not `gtk-launch`). Fixes Telegram and other `DBusActivatable` apps that silently failed under `gtk-launch`. Still sets `X-systemd-skip=true`; logs to `~/.local/state/quickshell/autostart-run.log`.
- Config menu bar pill (`controlBar`).

## Earlier

- NWS Radar pill removed from the default bar (code remains under `widgets/RadarPill.qml` / `scripts/radar-fetch.sh` if you re-enable it).
- Combined Network · Bluetooth · Audio connectivity pill option.
- Sticky nm-applet / Blueman autostart controls.
