# Quickshell Status Bar & Hyprland Config Inspector

Personal Hyprland status bar built with [Quickshell](https://quickshell.org), plus a floating **Hyprland Config Inspector** overlay for browsing configuration, live system metrics, and desktop maintenance tasks from one window.

| Path | Role |
|------|------|
| `shell.qml` | Main bar entry point |
| `widgets/HyprConfigInsp.qml` | Config Inspector overlay |
| `widgets/SysMonService.qml` | Shared metrics polling service |
| `components/` | Inspector tab views and reusable UI pieces |
| `scripts/` | Shell pollers and control helpers |
| `Config.qml` | Global colors, spacing, workspace behavior, and inspector tokens |
| `widgets/*.qml` | Status bar pills and popups |

---

## Status bar

The top (or bottom) Hyprland panel is a glassmorphic Quickshell `PanelWindow` defined in `shell.qml`. Widgets are grouped into **left**, **center**, and **right** zones. Each pill is a self-contained file under `widgets/` and reads colors, spacing, and behavior defaults from `Config.qml` via the shared `bar` object.

Bar position and edge gap are set in `Config.qml` (`barPosition`: `"top"` or `"bottom"`, `barHeight`, `barEdgeMargin`). To rearrange widgets, cut and paste the marked blocks in `shell.qml` between the left, center, and right zones — no changes inside the widget files are required.

### Layout (default)

| Zone | Widgets (left → right) |
|------|-------------------------|
| **Left** | App Launcher, Quick Launch, Media Player |
| **Center** | Workspaces |
| **Right** | System Stats, System Tray, Audio, Clock, Notifications, Power |

### Bar widgets

| Widget | File | Description |
|--------|------|-------------|
| **App Launcher** | `shell.qml` (inline) | Opens the Rofi app drawer (`~/.local/bin/rofi-app-drawer`) |
| **Quick Launch** | `QuickLaunchPill.qml` | Icon row for pinned apps (VSCodium, Firefox, Logseq, LM Studio) |
| **Media Player** | `MediaPill.qml` | MPRIS media controls with Cava visualizer and rich popup (play/pause, seek, player picker). Hidden by default — see visibility IPC below |
| **Workspaces** | `WorkspacesPill.qml` | Hyprland workspace pills (optional magic-space pill, configurable count); click to switch, scroll wheel to cycle |
| **System Stats** | `SysStatsPill.qml` | CPU and GPU utilization + temperature gauges. Left-click CPU opens `btop` in a terminal; left-click GPU opens `nvtop`. Hides automatically while media is playing |
| **System Tray** | `SystemTrayPill.qml` | Tray icons with themed popup menus (avoids clashing native GTK/Qt menus) |
| **Audio** | `AudioPill.qml` | Speaker and microphone volume, mute, scroll-wheel adjustment, and device selection popup (PipeWire) |
| **Clock** | `ClockPill.qml` | Live date/time; click opens a calendar popup |
| **Notifications** | `NotificationBell.qml` | SwayNC notification bell with unread badge. Left-click toggles the notification center; right-click toggles Do Not Disturb |
| **Power** | `PowerMenu.qml` | Session menu — lock, logout, reboot, shutdown, and enter BIOS |

The **Hyprland Config Inspector** is also loaded from `shell.qml` but is not a bar pill; it opens as a separate floating window (see below).

### Bar widget visibility (IPC)

Some widgets can be shown or hidden at runtime:

```bash
qs ipc call shell setShowMediaWidget true
qs ipc call shell setShowStatsWidget false
qs ipc call shell toggleShowMediaWidget
qs ipc call shell toggleShowStatsWidget
qs ipc call shell setShowMagicWorkspacePill true
qs ipc call shell toggleShowMagicWorkspacePill
```

By default, **Media Player** is off, **System Stats** is on, and the **magic workspace pill** follows `wsShowSpecialPill` in `Config.qml`. Run `qs ipc show` for the full IPC list.

### Workspaces (`WorkspacesPill.qml` + `Config.qml`)

Workspace pill behavior is configured in `Config.qml` and applied by `widgets/WorkspacesPill.qml`.

| Setting | Default | Description |
|---------|---------|-------------|
| `wsShowSpecialPill` | `true` | Show the magic-space pill (🪄) before workspace 1. Overridable at runtime via IPC until `qs` restarts |
| `wsMinimumShown` | `5` | When `wsShowOnlyActive` is `false`, always show numbered pills `1` … `N` (even if empty) |
| `wsShowOnlyActive` | `false` | When `true`, only show numbered workspaces that are occupied or active (plus any extras above `wsMinimumShown` that qualify) |
| `wsStartupWorkspace` | `1` | Hyprland workspace to focus when `qs` starts (`0` = leave workspace unchanged) |
| `wsStartupCloseMagic` | `true` | Close the magic overlay on `qs` start before applying `wsStartupWorkspace` |
| `wsSpecialName` | `"magic"` | Hyprland special workspace name (must match `keybindings.lua`) |
| `wsIcon1` … `wsIcon10` | — | Per-workspace pill icons; see icon picker comment in `Config.qml` |

**Examples**

```qml
// Always show 7 numbered pills, magic pill on
wsShowOnlyActive: false
wsMinimumShown: 7
wsShowSpecialPill: true

// Only occupied/active numbered pills (no empty placeholders)
wsShowOnlyActive: true

// Do not change workspace when qs restarts
wsStartupWorkspace: 0
```

**Keyboard cycling (Hyprland)** — `SUPER + CTRL + Left/Right` uses `~/.config/hypr/scripts/cycle-workspace.sh` so magic space is included in the cycle (e.g. left from workspace 1 opens magic). Configured in `~/.config/hypr/config/keybindings.lua`.

---

## Hyprland Config Inspector

A resizable floating window (`Hyprland Config Inspector`) for reading Hyprland config, monitoring the system, and performing common admin tasks without leaving the desktop.

### Purpose

- Inspect split Hyprland configuration (Lua and related `.conf` files)
- View live Hyprland runtime options from `hyprctl`
- Monitor CPU, GPU, memory, temperature, network, processes, and audio
- Tail logs, manage systemd services, and review system information
- Search across the active tab, copy values, and open config files for editing

### Split Hyprland configuration

Hyprland is **not** configured in a single `hyprland.conf` here. Settings are split across multiple **Lua** modules under `~/.config/hypr/config/`, with the main entry point at `~/.config/hypr/hyprland.lua`. Related tools (Hypridle, Hyprlock, Hyprpaper) keep their own `.conf` files in `~/.config/hypr/`.

Typical layout:

| File | Topics |
|------|--------|
| `keybindings.lua` | Keybinds and mouse bindings |
| `environment-variables.lua` | `exec-once`, environment variables |
| `monitors.lua` | Monitor and workspace layout |
| `input.lua` | Keyboard, mouse, touchpad |
| `look-and-feel.lua` | Gaps, borders, animations, decoration |
| `windows-and-workspaces.lua` | Window rules, layer rules, workspaces |
| `my-programs.lua` | Default apps (`terminal`, `fileManager`, etc.) |
| `autostarts.lua` | Startup commands |
| `permissions.lua` | Window permission rules |
| `misc.lua` | Miscellaneous options |

#### How the inspector uses the split config

- **Config Files** tab — Primary file browser. Pick any registered config from the dropdown to view it with syntax highlighting (`bat`), filter lines with global search, copy the full file, or press **Ctrl+E** / **Edit** to open it in `$TERMINAL` with `nano`.
- **Key Bindings** and **Environment** tabs — Read `keybindings.lua` and `environment-variables.lua` directly and show parsed tables (easier to scan than raw source). See [Custom description comments](#custom-description-comments) below.
- **Runtime Options** tab — Shows values Hyprland is running with now via `hyprctl getoption` (useful after editing; reload Hyprland to apply file changes).

The file list is defined in `widgets/HyprConfigInsp.qml` (`configFileEntries`). Add an entry there if you create a new config module.

#### Custom description comments

In `keybindings.lua` and `environment-variables.lua`, inline comments use the `--#` prefix to attach a **human-readable description** on the same line as the config entry. The inspector parses these and surfaces them in the **Key Bindings** and **Environment** tabs — they are not Hyprland syntax; they are a local convention for documentation.

```lua
hl.bind(mainMod .. " + T", hl.dsp.exec_cmd(terminal)) --# Opens the default terminal
hl.env("TERMINAL", terminal)                         --# Default terminal for keybinds and CLI tools
```

| File | What `--#` becomes in the inspector |
|------|-------------------------------------|
| `keybindings.lua` | **Action** column (the bind’s description). Only `hl.bind(...)` lines that include `--#` are listed. |
| `environment-variables.lua` | **Comment** shown under the variable name. Plain `--` comments are also recognized as a fallback. |

Use `--#` to keep Hyprland directives on the left and your notes on the right. Commented-out binds (`--hl.bind(...)`) are ignored. If you adopt this layout in your own config, match the parser expectations in `widgets/HyprConfigInsp.qml` (`parseKeybinds`, `parseEnvVars`).

#### New to split configs?

If you are used to one monolithic `hyprland.conf`, think of `hyprland.lua` as a thin loader and each file in `config/` as a chapter (bindings, monitors, input, etc.). Edit the file that matches what you want to change, then reload Hyprland (`hyprctl reload` or your usual method). Use the **Config Files** tab to jump between modules without hunting paths in a file manager.

### Key features

- **14 tabs** covering config, metrics, logs, and services
- **Global search** (`Ctrl+F`) filters the active tab
- **Syntax-highlighted** config file viewer (bat-backed)
- **Live polling** for metric tabs while the inspector is open and visible (stops when closed or minimized)
- **Per-tab refresh** and **Refresh All** (`Ctrl+R`) for on-demand data
- **Edit in terminal** (`Ctrl+E`) opens the current config file in `$TERMINAL` with `nano`
- **Copy** buttons and click-to-copy on many values
- **Resizable** window with themed Catppuccin-style UI from `Config.qml`

### Tabs

| Tab | Description |
|-----|-------------|
| **Key Bindings** | Parsed `hl.bind` entries from `keybindings.lua` (key + `--#` description as action) |
| **Environment** | Parsed `hl.env` entries from `environment-variables.lua` (variable, value, `--#` comment) |
| **Runtime Options** | Live Hyprland options via `hyprctl getoption`, grouped by category with wiki links |
| **Config Files** | Browse all split `config/*.lua` modules plus Hypridle/Hyprlock/Hyprpaper configs; syntax highlighting, search, copy, and edit |
| **CPU** | CPU usage gauge, history sparkline, load averages, and top CPU processes |
| **GPU** | GPU utilization, VRAM, temperature, and related stats (when available) |
| **Memory** | RAM and swap usage with history and breakdown |
| **Temperature** | CPU and GPU temperature monitoring with history |
| **Network** | Interfaces, routing, DNS, latency, firewall, active connections, per-process bandwidth, and live traffic graphs |
| **Processes** | Process list with CPU/memory usage, PR/NI columns, sort, filter, and signal controls |
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

### Recommended window rule

Add this to `~/.config/hypr/config/windows-and-workspaces.lua` (or your window-rules module) so the inspector opens centered and floating at a comfortable default size. Adjust `size` to taste — the window remains user-resizable.

```lua
-- Hyprland Config Inspector
hl.window_rule({
    name     = "Hyprland Config Inspector",
    match    = { title = "^(Hyprland Config Inspector)$" },
    float    = true,
    center   = true,
    fullscreen = false,
    immediate  = false,
    pin  = false,
    size   = { 1231, 1029 },
})
```

The rule matches the window title set in `widgets/HyprConfigInsp.qml`. If you change the title there, update `match` accordingly.

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

**Config paths** — See [Split Hyprland configuration](#split-hyprland-configuration) above. Paths are hard-coded in `widgets/HyprConfigInsp.qml`; change `configDir`, `hyprDir`, or `configFileEntries` if your install differs.

**`--#` descriptions** — Key Bindings and Environment tabs depend on the `--#` comment convention in `keybindings.lua` and `environment-variables.lua`. Entries without `--#` (for binds) or without a recognized comment (for env) may not appear as expected in those parsed views.

**Background polling** — `SysMonService` polls only while the inspector is open *and* not minimized. Closing or hiding the window stops metric polling to reduce idle CPU use.

**Network tab (privileged data)** — Routing, latency tests, firewall rules, and the full connection table are loaded on demand when you open the Network tab or press **Refresh** in those sections. Live interface stats, DNS, public IP, and socket counts still update from the fast poller. Some firewall or connection details may require elevated permissions on certain systems.

**Services tab** — User-scoped units use `systemctl --user`. System-scoped start/stop/restart may prompt for polkit authentication depending on your policy.

**Logs tab** — System journal and kernel sources may show limited output without appropriate permissions. Hyprland’s session log is read from `/run/user/<uid>/hypr/`.

**System Info** — Collected via `fastfetch --logo none` when the tab is opened. Includes links to System76 Thelio Mira R4 documentation.

**Terminal** — Edit and Network **Open Terminal** actions use the `$TERMINAL` environment variable (set in Hyprland from `my-programs.lua`; defaults to `kitty`).

---

## Configuration (`Config.qml`)

`Config.qml` is the single source of truth for bar visuals and workspace behavior. `shell.qml` re-exports its properties on the root `bar` object (e.g. `bar.accent`, `bar.wsMinimumShown`). The inspector loads a local `Config` instance for overlay-specific tokens.

Edit `Config.qml` to change:

- Colors, fonts, spacing, radii, and icon glyphs
- Workspace pill count, active-only mode, magic pill default, and startup focus
- Inspector sizing and semantic colors (search for `insp*` properties)

The file is named `Config.qml` (capital **C**) because QML requires that naming for reliable type registration across subdirectories.

---

## License

Personal configuration. Feel free to take inspiration.