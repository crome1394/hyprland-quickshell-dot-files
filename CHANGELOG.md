# Changelog

Notable changes for people upgrading this config. Day-to-day usage is in [README.md](README.md) and [docs/](docs/).

## 2026-08 — Control bar & FreshRSS

- Control strip: Position, Wallpaper, Widgets, Options, Launch, Autostart, **Services**, Clock (toolbar on bottom).
- **Services** panel: systemd user/system units with filter + Start/Stop/Restart (reuses Inspector `ServicesView`).
- Widgets panel: A–Z list; row layout ✓/name · L/C/R · ↑↓; horizontal width scale.
- Options: UI scale, workspaces, sticky applets, Sys Stats gauges, FreshRSS server Test/Save.
- FreshRSS secrets moved to `~/.config/freshrss-quickshell/freshrss.env` (outside git).
- Autostart: XDG `~/.config/autostart` scripts with real `Exec=` and `X-systemd-skip`.
- Config menu bar pill (`controlBar`).

## Earlier

- NWS Radar pill removed from the default bar (code remains under `widgets/RadarPill.qml` / `scripts/radar-fetch.sh` if you re-enable it).
- Combined Network · Bluetooth · Audio connectivity pill option.
- Sticky nm-applet / Blueman autostart controls.
