# Quickshell Status Bar & Hyprland Config Inspector

Personal [Hyprland](https://hyprland.org) status bar and floating **Config Inspector**, built with [Quickshell](https://quickshell.org).

| Path | Role |
|------|------|
| `shell.qml` | Bar entry point |
| `Config.qml` | Theme, visibility defaults, workspace tokens |
| `widgets/` | Pills, popups, control strip, inspector |
| `scripts/` | Pollers, network/audio/FreshRSS helpers |
| `docs/` | Full reference (IPC, per-widget guides) |
| `state/` | Runtime layout prefs (gitignored) |

## Features

- Glassmorphic bar (top or bottom) with left / center / right zones
- **Control strip** — right-click empty chrome or **Config menu** gear: layout, wallpaper, Options, Quick Launch, XDG Autostart, clock formats
- Network, Bluetooth, Audio (optional combined pill), workspaces (incl. magic space), sys stats, tray, notifications, power
- FreshRSS reader pill (external secrets file)
- Floating Hyprland Config Inspector (metrics, logs, services, split Lua configs)

## Requirements

- [Quickshell](https://quickshell.org) (`qs`)
- Hyprland (or compatible compositor for layer-shell)
- Typical helpers used by scripts: `jq`, `nmcli`, `pactl` / PipeWire, `curl` (FreshRSS), optional `yt-dlp`, `btop`, `nvtop`

## Install

```bash
# Example: clone into the XDG config path Quickshell loads by default
git clone git@github.com:crome1394/quickshell-dot-files.git ~/.config/quickshell
cd ~/.config/quickshell

# Optional: FreshRSS credentials (outside this repo — never commit)
mkdir -p ~/.config/freshrss-quickshell
cp secrets/freshrss.env.example ~/.config/freshrss-quickshell/freshrss.env
chmod 600 ~/.config/freshrss-quickshell/freshrss.env
# edit FRESHRSS_BASE_URL, FRESHRSS_USER, FRESHRSS_API_PASSWORD

# Run (or start from Hyprland autostart)
qs --daemonize -n
```

Layout and many prefs persist under `state/bar-layout.json` (created at runtime).

## Default bar layout

| Zone | Widgets |
|------|---------|
| **Left** | App Launcher, Quick Launch, FreshRSS, Media |
| **Center** | Workspaces |
| **Right** | Sys Stats, Tray, Net·BT·Audio, Clock, Notifications, Config menu, Power |

Reorder / show-hide at runtime: **Config menu → Widgets**. Defaults and catalog live in `Config.qml` / `shell.qml`.

## Control strip

| Panel | Purpose |
|-------|---------|
| **Position** | Bar top / bottom |
| **Wallpaper** | hyprpaper apply / folder |
| **Widgets** | A–Z list: ✓ · name · L/C/R · ↑↓ · width % |
| **Options** | Behavior prefs (scale, workspaces, applets, stats gauges, FreshRSS server) |
| **Launch** | Quick Launch pins |
| **Autostart** | XDG `~/.config/autostart` |
| **Clock** | Date/time format |

Details: [docs/control-bar.md](docs/control-bar.md)

## IPC (quick start)

List all targets: `qs ipc show`

```bash
# Bar / control strip
qs ipc call shell toggleBarControlBar
qs ipc call shell setBarPosition bottom
qs ipc call shell setShowAudioPill false
qs ipc call shell setShowControlBarPill true
qs ipc call shell setUiScale 0.85
qs ipc call shell setUiScaleAuto

# Common widget actions
qs ipc call clockPill showCalendar
qs ipc call notificationBell toggleDoNotDisturb
qs ipc call networkPill togglePopup
qs ipc call bluetoothPill togglePopup
qs ipc call audioPill toggleEchoCancel
qs ipc call freshRss toggle
qs ipc call hyprConfigInsp toggle
qs ipc call sysStatsPill toggleMetricsLiveUpdates
qs ipc call killTargetPill activatePickMode
```

Full tables: [docs/ipc.md](docs/ipc.md)

## Configuration

- **Theme & defaults:** `Config.qml` (search section headers, e.g. **WIDGET VISIBILITY**, **FRESHRSS**, **POWER MENU**)
- **Runtime layout / Options:** `state/bar-layout.json` (via control strip)
- **FreshRSS secrets:** `~/.config/freshrss-quickshell/freshrss.env` (not in git)

Token reference: [docs/config.md](docs/config.md)

## Documentation

| Guide | Contents |
|-------|----------|
| [Control bar](docs/control-bar.md) | Widgets, Options, Autostart |
| [FreshRSS](docs/freshrss.md) | Reader UI, secrets, setup |
| [IPC](docs/ipc.md) | Visibility + action commands |
| [Network](docs/network.md) | Network pill |
| [Bluetooth](docs/bluetooth.md) | Bluetooth pill |
| [Audio](docs/audio.md) | Audio pill, echo cancel |
| [Workspaces](docs/workspaces.md) | Magic pill, min shown, startup |
| [Inspector](docs/inspector.md) | Hyprland Config Inspector |
| [Config tokens](docs/config.md) | `Config.qml` deep dive |
| [Changelog](CHANGELOG.md) | Notable upgrades |

## License

Personal configuration. Feel free to take inspiration.
