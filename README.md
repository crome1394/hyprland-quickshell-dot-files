# Quickshell Status Bar & Hyprland Config Inspector

Personal Hyprland status bar built with [Quickshell](https://quickshell.org), plus a floating **Hyprland Config Inspector** overlay for browsing configuration, live system metrics, and desktop maintenance tasks from one window.

| Path | Role |
|------|------|
| `shell.qml` | Main bar entry point |
| `widgets/HyprConfigInsp.qml` | Config Inspector overlay |
| `widgets/SysMonService.qml` | Shared metrics polling service |
| `components/` | Inspector tab views and reusable UI pieces |
| `scripts/` | Shell pollers and control helpers |
| `Theme.qml` | Global colors, spacing, and inspector tokens |

---

## Hyprland Config Inspector

A resizable floating window (`Hyprland Config Inspector`) for reading Hyprland config, monitoring the system, and performing common admin tasks without leaving the desktop.

### Purpose

- Inspect split Hyprland configuration (Lua and related `.conf` files)
- View live Hyprland runtime options from `hyprctl`
- Monitor CPU, GPU, memory, temperature, network, processes, and audio
- Tail logs, manage systemd services, and review system information
- Search across the active tab, copy values, and open config files for editing

### Key features

- **14 tabs** covering config, metrics, logs, and services
- **Global search** (`Ctrl+F`) filters the active tab
- **Syntax-highlighted** config file viewer (bat-backed)
- **Live polling** for metric tabs while the inspector is open and visible (stops when closed or minimized)
- **Per-tab refresh** and **Refresh All** (`Ctrl+R`) for on-demand data
- **Edit in terminal** (`Ctrl+E`) opens the current config file in `$TERMINAL` with `nano`
- **Copy** buttons and click-to-copy on many values
- **Resizable** window with themed Catppuccin-style UI from `Theme.qml`

### Tabs

| Tab | Description |
|-----|-------------|
| **Key Bindings** | Parsed keybind table from `keybindings.lua` (key, action, comments) |
| **Environment** | Parsed environment variables from `environment-variables.lua` |
| **Runtime Options** | Live Hyprland options via `hyprctl getoption`, grouped by category with wiki links |
| **Config Files** | Dropdown of Hypr/Hypridle/Hyprlock/Hyprpaper configs with syntax highlighting |
| **CPU** | CPU usage gauge, history sparkline, load averages, and top CPU processes |
| **GPU** | GPU utilization, VRAM, temperature, and related stats (when available) |
| **Memory** | RAM and swap usage with history and breakdown |
| **Temperature** | CPU and GPU temperature monitoring with history |
| **Network** | Interfaces, routing, DNS, latency, firewall, active connections, per-process bandwidth, and live traffic graphs |
| **Processes** | Process list with CPU/memory usage; sort, filter, and send signals |
| **Audio** | PipeWire/PulseAudio sinks, sources, ports, volumes, and default devices |
| **Logs** | Tail Hyprland log, user/system journal, kernel, and common service logs |
| **Services** | systemd user and system units with status filters and start/stop/restart controls |
| **System Info** | `fastfetch` hardware/OS summary, Service Documentation links, and click-to-copy fields |

### Launch

**IPC (works from scripts, keybinds, or other Quickshell widgets):**

```bash
qs ipc call hyprConfigInsp toggle
```

**Hyprland keybind** (in `~/.config/hypr/config/keybindings.lua`):

```
SUPER + SLASH   →   qs ipc call hyprConfigInsp toggle
```

The inspector is registered in `shell.qml` as `hyprConfigInsp`. Run `qs ipc show` to list available IPC targets.

### Keyboard shortcuts

Shortcuts apply while the inspector window is focused (search field captures typing when active).

| Shortcut | Action |
|----------|--------|
| `Escape` | Close search or close the inspector |
| `Ctrl+F` | Focus global search |
| `Ctrl+R` | Refresh all data for the current context |
| `Ctrl+E` | Edit the current config file in a terminal (`nano`) |
| `Tab` / `Shift+Tab` | Next / previous tab |
| `PgUp` / `PgDown` | Page scroll in the active tab |
| `↑` / `↓` | Line scroll in the active tab |

### Important notes

**Config paths** — File-backed tabs read from `~/.config/hypr/config/` and `~/.config/hypr/` by default. Adjust paths in `widgets/HyprConfigInsp.qml` if your layout differs.

**Background polling** — `SysMonService` polls only while the inspector is open *and* not minimized. Closing or hiding the window stops metric polling to reduce idle CPU use.

**Network tab (privileged data)** — Routing, latency tests, firewall rules, and the full connection table are loaded on demand when you open the Network tab or press **Refresh** in those sections. Live interface stats, DNS, public IP, and socket counts still update from the fast poller. Some firewall or connection details may require elevated permissions on certain systems.

**Services tab** — User-scoped units use `systemctl --user`. System-scoped start/stop/restart may prompt for polkit authentication depending on your policy.

**Logs tab** — System journal and kernel sources may show limited output without appropriate permissions. Hyprland’s session log is read from `/run/user/<uid>/hypr/`.

**System Info** — Collected via `fastfetch --logo none` when the tab is opened. Includes links to System76 Thelio Mira R4 documentation.

**Terminal** — Edit and Network **Open Terminal** actions use the `$TERMINAL` environment variable (set in Hyprland from `my-programs.lua`; defaults to `kitty`).

---

## Theming

Visual tokens for the bar and inspector live in `Theme.qml`. `shell.qml` exposes them on the root `bar` object; the inspector uses the same theme via a local `Theme` instance. Edit `Theme.qml` to change colors, spacing, and inspector-specific sizes.

---

## License

Personal configuration. Feel free to take inspiration.