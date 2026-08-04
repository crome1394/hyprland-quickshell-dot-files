# Changelog

Notable changes for people upgrading this config. Day-to-day usage is in [README.md](README.md) and [docs/](docs/).

## 2026-08 — Control bar & FreshRSS

- **Colors panel** (control strip → **Colors**):
  - Live theme editor for bar/widgets: Colors column + **Opacity & Text** column; picker opens on the **opposite** side.
  - Mouse SV square + hue strip, hex / RGB fields, opacity sliders; compact layout so the panel Flickable does not steal drag.
  - Built-in presets (Liquid glass, Solid dark, Soft grey — not removable); **Save as preset** / remove for user themes in `themes/`.
  - Active look in `state/theme-colors.json`; helper `scripts/theme-io.sh` (list / export / import / delete).
  - Liquid-glass default palette (cool blue-slate glass, vivid teal accent, magenta secondary).
- **Audio panel** (control strip → **Audio**):
  - Multi-device manager via Inspector `AudioMonitorView` (ports, set-default, volume/mute, profiles under Output/Input).
  - Overview pill: **Summary → Active streams → Levels**; tools (**Refresh**, **pw-top**, **Restart audio**); sticky **echo cancel** at bottom.
  - Options: show AEC section / Summary / profiles / Level meters; keep Summary & Active streams expanded. AEC on/off is only in the Audio panel/pill.
  - Idle when closed: no peak sampling, poll, or profile processes (`stopAllWork`). Peak-detect streams filtered from app lists.
  - AudioPill popup scrolls when tall so Echo cancel no longer overlaps the border.
- **Display panel** (control strip → **Display**):
  - Live monitor indicator (res, Hz, bit depth, make/model/serial, scale, physical size).
  - Adapter card (DRM + NVIDIA util/temp/power/VRAM); soft-poll **only while the panel is open**.
  - **NVIDIA** button (Nerd Font icon) → `nvidia-settings`.
  - Resolution block slider + refresh dropdown + bit-depth dropdown; linked by hyprctl modes / Hz families.
  - **Apply** at scale 1.0 via `scripts/monitor-mode.sh` (pending until Apply).
- **SysStats pill layout:** center CPU/Memory/GPU; sections hug content (Memory no longer clips); snug fit with no empty side ballast; single separator slots between visible gauges.
- Control strip: Position, **Display**, Wallpaper, Widgets, Options, **Colors**, Launch, Autostart, **Services**, **Audio**, **Keybinds**, Clock (toolbar on bottom).
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
