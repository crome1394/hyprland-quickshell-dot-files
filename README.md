# Quickshell Status Bar & Hyprland Config Inspector

Personal Hyprland status bar built with [Quickshell](https://quickshell.org), plus a floating **Hyprland Config Inspector** overlay for browsing configuration, live system metrics, and desktop maintenance tasks from one window.

| Path | Role |
|------|------|
| `shell.qml` | Main bar entry point |
| `widgets/HyprConfigInsp.qml` | Config Inspector overlay |
| `widgets/SysMonService.qml` | Shared metrics polling service |
| `components/` | Inspector tab views and reusable UI pieces |
| `scripts/` | Shell pollers and control helpers |
| `Config.qml` | Global colors, spacing, widget visibility defaults, workspace behavior, and inspector tokens |
| `widgets/*.qml` | Status bar pills and popups |

---

## Status bar

The top Hyprland panel is a solid Quickshell `PanelWindow` defined in `shell.qml` (default `barPosition: "top"`). Widgets are grouped into **left**, **center**, and **right** zones. Each pill is a self-contained file under `widgets/` and reads colors, spacing, and behavior defaults from `Config.qml` via the shared `bar` object.

Bar position and edge gap are set in `Config.qml` (`barPosition`: `"top"` or `"bottom"`, `barHeight`, `barEdgeMargin`). **Right-click empty bar chrome** (not on a pill) opens a short centered control strip (`BarControlBar.qml`) with the top/bottom toggle and display family × Hz chips (wired to `hypr-resolution`). Bar edge is saved to `state/bar-layout.json`. To rearrange widgets, cut and paste the marked blocks in `shell.qml` between the left, center, and right zones — no changes inside the widget files are required.

**UI scale (multi-resolution):** Bar/pill/popup sizes scale with the monitor width. Full size at `uiDesignWidth` (default **2560** logical px) and above; narrower screens scale down to `uiScaleMin` (**0.65**). Popups are also clamped so they stay on-screen.

| Control | How |
|---------|-----|
| Auto (default) | `uiScaleManual: 0` in `Config.qml` (or `state/bar-layout.json`) |
| Force scale | Set `uiScaleManual: 0.85` in Config, or `qs ipc call shell setUiScale 0.85` |
| Back to auto | `qs ipc call shell setUiScaleAuto` or `setUiScale 0` |

**Priority on narrow screens:** Core pills stay visible; bulkier ones auto-hide by width (logical px). Thresholds in `Config.qml` (`uiDensityHide*Below`).

| Priority | Widgets |
|----------|---------|
| **Always keep** (if enabled) | Workspaces · System tray · Audio · Clock/calendar · Notifications · Power |
| Hide first (`< 2300`) | Quick Launch |
| Then (`< 2000`) | Sys stats (CPU / Memory / GPU) |
| Then (`< 1680`) | FreshRSS · Media · Kill target |
| Then (`< 1480`) | Network + Bluetooth |

IPC `setShow*` still sets your preference; density only gates visibility until the screen is wide enough again.

### Layout (default)

| Zone | Widgets (left → right) |
|------|-------------------------|
| **Left** | App Launcher, Quick Launch, FreshRSS, Media Player |
| **Center** | Workspaces |
| **Right** | System Stats, System Tray, Network, Bluetooth, Audio, Clock, Notifications, Power |

### Bar widgets

| Widget | File | Description |
|--------|------|-------------|
| **App Launcher** | `shell.qml` (inline) | Opens the Rofi app drawer (`~/.local/bin/rofi-app-drawer`) |
| **Quick Launch** | `QuickLaunchPill.qml` | Icon row for pinned apps. Manage from control bar **Launch** panel (add from installed apps or custom, remove, reorder) or edit defaults in `Config.qml` (`quickLaunchApps`). Runtime pins persist in `state/bar-layout.json`. |
| **FreshRSS** | `FreshRssPill.qml` | Local FreshRSS reader window (list + article body, open browser / play in `mpv`). See [FreshRSS reader](#freshrss-reader) below |
| **Media Player** | `MediaPill.qml` | MPRIS media controls with Cava visualizer and rich popup (play/pause, seek, player picker). Hidden by default — see visibility IPC below |
| **Workspaces** | `WorkspacesPill.qml` | Hyprland workspace pills (optional magic-space pill, configurable count); click to switch, scroll wheel to cycle |
| **System Stats** | `SysStatsPill.qml` | CPU, Memory, and GPU gauges (lightweight bar polling; always live). CPU/GPU show utilization + temperature; Memory shows utilization + used GiB. **Left-click** each third opens a metrics dropdown (inspector CPU/Memory/GPU tabs; `sysmon-poller.sh`). **Right-click** CPU or Memory opens `btop`; right-click GPU opens `nvtop`. Pill width and column layout in `Config.qml` (search **SYS STATS PILL**): `statPillWidth` (total border — tune this first), `statPillSectionWidth`, `statPillSpacing`, `statPillPaddingH`. Popup size and position are set per section in `Config.qml` — CPU: `popupStatsCpu*`; Memory: `popupStatsMem*`; GPU: `popupStatsGpu*`. **Pause updates** / **Resume updates** on each popup, or `sysStatsPill` IPC, suspends metrics-popup polling only. `popupStatsLiveUpdates` sets the default on open (persists across reboot). `popupStatsPersistPause: true` also saves Pause/Resume (and IPC) choices to `state/popup-stats.json`. Click outside or focus another window to dismiss. Hides automatically while media is playing |
| **System Tray** | `SystemTrayPill.qml` | Tray icons with themed popup menus (avoids clashing native GTK/Qt menus) |
| **Network** | `NetworkPill.qml` | NetworkManager manager (nm-applet replacement): two-column popup (Adapters + Connections \| WiFi), traffic graph, radio toggles, connection info, optional nm-applet tray. Left-click opens the popup (use the header WiFi toggle or IPC for radio power). See [Network pill](#network-pill-networkpillqml) |
| **Bluetooth** | `BluetoothPill.qml` | Adapter power, scan/pair, connect/disconnect, trust/block/remove, rename, battery, device info, BlueZ **audio profiles**, and Blueman tray control (session + sticky autostart). Left-click opens the popup; right-click toggles adapter power. See [Bluetooth pill](#bluetooth-pill-bluetoothpillqml) |
| **Audio** | `AudioPill.qml` | Speaker and microphone volume, mute, scroll-wheel, device + card **profile** pickers, collapsible L/R balance, real-time VU meters, BT battery, and optional **echo cancel** (PipeWire AEC). **Left-click** opens the full popup; right-click cycles speaker / mic / dual. See [Audio pill](#audio-pill-audiopillqml) |
| **Clock** | `ClockPill.qml` | Live date/time; click opens a calendar popup. IPC: `qs ipc call clockPill showCalendar` |
| **Notifications** | `NotificationBell.qml` | Bell with count badge and red DND styling. Polls your daemon's CLI from `Config.qml` (defaults: SwayNC / `swaync-client`) via timer sync + optional live subscribe — state and `Io.Process` polling live in this widget, not `shell.qml`. Left-click toggles panel; right-click opens menu (DND, clear all). IPC: `qs ipc call notificationBell toggleDoNotDisturb` |
<<<<<<< HEAD
| **Bar control** | `BarControlBar.qml` | Temporary mini-bar opened by **right-clicking empty bar chrome**. Toolbar: **Position** · **Wallpaper** · **Widgets** · **Sizes** · **Launch** · **Clock**. Wallpaper: thumbnail grid + apply via hyprpaper. Widgets: show/zone/order (Net·BT·Audio is one pill). **Sizes**: per-widget pill scale (block slider + typed %). Launch: Quick Launch pins. Persists in `state/bar-layout.json`. |
=======
| **Bar control** | `BarControlBar.qml` | Temporary mini-bar opened by **right-clicking empty bar chrome**. Toolbar: **Position** · **Wallpaper** · **Widgets** · **Sizes** · **Launch** · **Autostart** · **Clock**. Wallpaper: hyprpaper thumbs. Widgets: show/zone/order (Net·BT·Audio one pill). **Sizes**: horizontal width %. Launch: Quick Launch pins. **Autostart**: XDG `~/.config/autostart` enable/disable/add/remove/run (session apps; Hyprland core stays in `autostarts.lua`). |
>>>>>>> 147e5ec (Add bar control strip: layout, wallpaper, sizes, Launch, and XDG Autostart.)
| **Kill Target** | `KillTargetPill.qml` | xkill-style window picker (hidden by default). Click the pill to arm pick mode (crosshair on all monitors), then click a window to send **SIGTERM** to its process. Escape, right-click, empty click, or a second pill click cancels. Uses `window-at-point.sh` + `process-control.sh` (user-owned processes only). IPC: `qs ipc call killTargetPill activatePickMode` |
| **Power** | `PowerMenu.qml` | Left-click opens the full session menu; right-click opens a compact quick menu. Actions and commands are configured in `Config.qml` (search **POWER MENU**) |

The **Hyprland Config Inspector** is also loaded from `shell.qml` but is not a bar pill; it opens as a separate floating window (see below).

<<<<<<< HEAD
### NWS Radar (removed from bar)

=======
### Bar control strip (`BarControlBar.qml`)

**Right-click empty bar chrome** (not on a pill) opens a temporary centered mini-bar. Click a toolbar button to expand a panel; click the same button again (or outside the popup) to close.

| Panel | What it does |
|-------|----------------|
| **Position** | Pin bar **top** or **bottom**; edge is written to `state/bar-layout.json` |
| **Wallpaper** | Browse / apply wallpapers via hyprpaper (`scripts/wallpaper-*.sh`); pick folder, add images |
| **Widgets** | Show/hide pills (✓ green / ✕ red), zone (left/center/right), reorder; Network·Bluetooth·Audio can share one combined AV pill |
| **Sizes** | Per-widget **horizontal width** scale (about 80–180%); persists with bar layout |
| **Launch** | Manage **Quick Launch** pins: search installed `.desktop` apps, add custom command, remove, reorder |
| **Autostart** | Manage **XDG** login apps in `~/.config/autostart` (see below) |
| **Clock** | Pick clock date/time format presets |

Layout, widget visibility, scales, Quick Launch pins, wallpaper folder, and related prefs persist in `state/bar-layout.json` (guarded writes). UI scale and density hide thresholds stay in `Config.qml` / IPC as documented above.

#### XDG Autostart panel

Session **user apps** (Flameshot, Discord, Logseq, …) are managed here — not Hyprland core services.

| Piece | Path |
|-------|------|
| Control panel | `widgets/BarControlBar.qml` → **Autostart** |
| List / enable / disable / remove | `scripts/autostart-list-json.sh`, `autostart-set.sh` |
| Add from `.desktop` or custom | `scripts/autostart-add.sh` |
| Run one or all enabled now | `scripts/autostart-run.sh` |
| Login helper (Hyprland) | `scripts/xdg-autostart-run.sh` |
| Desktop files | `~/.config/autostart/*.desktop` |

**At login:** call the helper once from Hyprland, e.g. in `~/.config/hypr/config/autostarts.lua`:

```lua
hl.exec_cmd("/home/crome/.config/quickshell/scripts/xdg-autostart-run.sh")
```

Keep **hyprpaper, hypridle, qs, swaync**, etc. in `autostarts.lua`. Put optional session apps in XDG so the control bar can toggle them without editing Lua.

**Workspace on open (e.g. magic space):** Autostart only starts the process. Place windows with **Hyprland window rules** in `windows-and-workspaces.lua` (preferred), for example Telegram/Discord → `special:magic silent`. Then you can remove `hl.exec_cmd("Telegram", { workspace = "…" })` from `autostarts.lua` and add those apps from the Autostart panel instead.

**Panel UX:** Current entries list with enable ✓/✕, run now, remove; searchable installed-app list with its own scroll area; **Open folder** / **Run enabled now** / **Refresh**.

### NWS Radar (removed from bar)

>>>>>>> 147e5ec (Add bar control strip: layout, wallpaper, sizes, Launch, and XDG Autostart.)
The Radar pill is no longer loaded in `shell.qml`. Implementation remains under `widgets/RadarPill.qml`, `scripts/radar-fetch.sh`, and **NWS RADAR** tokens in `Config.qml` if you want to re-add it later.

### FreshRSS reader

Floating reader for a local FreshRSS server (default `http://10.74.10.8`). Opens from a bar pill or IPC.

| Piece | Path |
|-------|------|
| Bar pill + window | `widgets/FreshRssPill.qml` |
| API client | `scripts/freshrss-api.sh` |
| Secrets (gitignored) | `secrets/freshrss.env` |
| Example secrets | `secrets/freshrss.env.example` |
| Theme / limits | `Config.qml` (search **FRESHRSS**) |

**How auth works**

- FreshRSS **Authentication** (form login, anonymous reading, allow API) is *server policy* — it does **not** hold the API password.
- The **API password** is under **Login → Profile** after signing in as your user. It is separate from the web form password.
- Anonymous IP browsing can show articles without Profile controls; that is expected.

**Data backends**

| Scope chip | Backend | Notes |
|------------|---------|--------|
| **All** / **Read** | Google Reader API, **per feed** (parallel) | Every subscription is represented (quiet channels included). Read+unread for All; read-only for Read. |
| **Unread** / **Starred** | Fever API id lists | True unread/starred sets from the server. |
| (no API password) | Public RSS ` /i/?a=rss` | Read-only fallback. |

**Counters (match FreshRSS)**

| Location | Source | What you see |
|----------|--------|----------------|
| **Bar pill badge** | GReader `unread-count` → `max` | Same total as FreshRSS’s `(N)` title |
| **Status line** in the window | Same global unread + in-view filter stats | e.g. `all · all dates · 21 unread · 40 shown · 5u/35r in view` |
| **Feed headers** | GReader per-feed unread (`titles` / `feeds` maps) | Accent number = unread (sidebar-style); `·N` = articles currently loaded for that feed |
| **Date sub-rows** | Loaded list `is_read` flags | `unread` or `unread/total` for that day in the window |

`freshrss-api.sh status` returns `{ unread, feeds, titles, labels, source }` for debugging. The bar badge only uses `unread`; in-window feed numbers use `titles` (feed name → count).

**Setup**

1. Enable **Allow API access** and set **Profile → API password**.
2. Create secrets (gitignored):

```bash
cp ~/.config/quickshell/secrets/freshrss.env.example \
   ~/.config/quickshell/secrets/freshrss.env
# edit: FRESHRSS_BASE_URL, FRESHRSS_USER, FRESHRSS_API_PASSWORD
chmod 600 ~/.config/quickshell/secrets/freshrss.env
```

3. Smoke test:

```bash
~/.config/quickshell/scripts/freshrss-api.sh status
# expect: "unread":N matching FreshRSS, "source":"greader"
#         .titles."Alex Jones Live" etc. match the FreshRSS sidebar
~/.config/quickshell/scripts/freshrss-api.sh items 80 all 12 | jq '{count,feeds,ms,workers}'
```

**Defaults (reader window)**

| Setting | Default |
|---------|---------|
| Scope | **All** (read + unread) |
| Date filter | **All dates** |
| Categories | **Collapsed** (expand feeds you care about) |
| Category order | **A–Z** |
| Inside a feed | Grouped by **date** (Today / Yesterday / full date), newest first |

**Reader UI**

- Expand a feed → **date sub-groups** (collapsible); articles under each day.
- Scope: Unread · **All** · Read · Starred.
- Date chips: All dates · Today · 7 days.
- Type: Any type · Video.
- **Per feed / max items** steppers + presets (reloads from server).
- Search (`/` or `Ctrl+F`) over title, feed, author, summary (not full HTML).
- **Play in mpv** only on **video** articles (YouTube, `.m4v`/`.mp4`, etc.); body video links also open in mpv. Needs `yt-dlp` on `PATH` (e.g. `~/.local/bin/yt-dlp`).
- Mark item read / star when API password is configured.
- **Mark whole feed** read/unread (detail buttons + shortcuts) via GReader/Fever.
- Feed header numbers track FreshRSS unread; `·N` is articles loaded in the window.

**Keyboard shortcuts** (window focused; not while typing in search)

| Keys | Action |
|------|--------|
| `w` / `s` or `↑` / `↓` | Move list cursor (feeds, dates, articles) |
| `Space` / `←` | Expand or collapse feed or date under cursor |
| `Enter` | Open article in detail pane (or expand feed/date if cursor is on a header) |
| `→` | **On an article:** open it (same as Enter). **On a feed/date:** expand/collapse |
| `j` / `k` | Next / previous **article** only |
| `/` or `Ctrl+F` | Focus search |
| `b` | Open selected article in browser |
| `v` | Play in mpv (**video items only**) |
| `r` / `Ctrl+R` | Refresh |
| `Esc` | Close window |
| `m` | Mark **item** read (writable) |
| `Shift+S` | Star / unstar item |
| `Shift+R` | Mark **feed** (category) read |
| `Shift+U` | Mark **feed** unread |

Double-click a row: video → mpv, otherwise browser.

**IPC / keybind**

```bash
qs ipc call freshRss toggle
qs ipc call freshRss refresh
qs ipc call freshRss show
qs ipc call shell setShowFreshRssPill false
```

Optional Hyprland: `bind = SUPER, R, exec, qs ipc call freshRss toggle`

**Config tokens** (`Config.qml`)

| Token | Default | Role |
|-------|---------|------|
| `showFreshRssPill` | `true` | Bar pill visibility |
| `freshRssPollIntervalMs` | `60000` | Unread badge poll |
| `freshRssItemLimit` | `80` | Max Unread/Starred ids |
| `freshRssPerFeedLimit` | `12` | Articles per feed for All/Read |
| `freshRssWidth` / `Height` | `980` / `640` | Floating window size |

**Performance (implementation notes)**

- All/Read fetch streams **in parallel** (thread pool); GReader auth cached under `~/.cache/quickshell/freshrss-greader.auth` (~25 min).
- List JSON **truncates** HTML/text so QML does not parse multi‑MB bodies for hundreds of rows.
- Categories **start collapsed** so the list paints feed headers only until expanded.
- Search avoids scanning full article HTML.

### Bar widget visibility (`Config.qml` + IPC)

Every bar pill can be hidden or shown. Defaults live in `Config.qml` (search for **WIDGET VISIBILITY**). `shell.qml` applies them on startup; **IPC overrides last until `qs` restarts**.

| Config property | Default | IPC `set` / `toggle` | Widget |
|-----------------|---------|----------------------|--------|
| `showLauncherPill` | `true` | `setShowLauncherPill` / `toggleShowLauncherPill` | App Launcher (inline) |
| `showQuickLaunchPill` | `true` | `setShowQuickLaunchPill` / `toggleShowQuickLaunchPill` | Quick Launch |
| `showFreshRssPill` | `true` | `setShowFreshRssPill` / `toggleShowFreshRssPill` | FreshRSS |
| `showMediaPill` | `false` | `setShowMediaWidget` / `toggleShowMediaWidget` | Media Player |
| `showWorkspacesPill` | `true` | `setShowWorkspacesPill` / `toggleShowWorkspacesPill` | Workspaces strip |
| `showStatsPill` | `true` | `setShowStatsWidget` / `toggleShowStatsWidget` | System Stats |
| `showTrayPill` | `true` | `setShowTrayPill` / `toggleShowTrayPill` | System Tray |
| `showNetworkPill` | `true` | `setShowNetworkPill` / `toggleShowNetworkPill` | Network |
| `showBluetoothPill` | `true` | `setShowBluetoothPill` / `toggleShowBluetoothPill` | Bluetooth |
| `showAudioPill` | `true` | `setShowAudioPill` / `toggleShowAudioPill` | Audio |
| `showClockPill` | `true` | `setShowClockPill` / `toggleShowClockPill` | Clock |
| `showNotificationPill` | `true` | `setShowNotificationPill` / `toggleShowNotificationPill` | Notifications |
| `showKillTargetPill` | `false` | `setShowKillTargetPill` / `toggleShowKillTargetPill` | Kill Target |
| `showPowerPill` | `true` | `setShowPowerPill` / `toggleShowPowerPill` | Power |

The **magic workspace pill** (🪄 inside the workspaces strip) is separate: `wsShowSpecialPill` in config, plus `setShowMagicWorkspacePill` / `toggleShowMagicWorkspacePill` via IPC.

**Examples**

```bash
# Runtime (until qs restarts)
qs ipc call shell setShowAudioPill false
qs ipc call shell toggleShowPowerPill
qs ipc call shell setShowWorkspacesPill true

# Permanent default in Config.qml
showAudioPill: false
showMediaPill: true
```

Zone dividers hide automatically when a neighboring pill is off. Run `qs ipc show` for the full command list.

### Widget actions (IPC)

Some bar widgets expose actions beyond show/hide. These work from scripts, Hyprland keybinds, or other Quickshell widgets.

| Target | Command | Action |
|--------|---------|--------|
| `clockPill` | `showCalendar` | Open the ClockPill calendar popup |
| `audioPill` | `setEchoCancel` | Enable (`true`) or disable (`false`) system echo cancel (sticky preference) |
| `audioPill` | `enableEchoCancel` / `disableEchoCancel` | Same as `setEchoCancel true` / `false` |
| `audioPill` | `toggleEchoCancel` | Toggle system echo cancel on/off |
| `networkPill` | `showPopup` / `hidePopup` / `togglePopup` | Open, close, or toggle the Network menu |
| `networkPill` | `setWifi` / `toggleWifi` / `enableWifi` / `disableWifi` | WiFi radio on/off |
| `networkPill` | `setNetworking` / `toggleNetworking` | Global NetworkManager networking on/off |
| `networkPill` | `startScan` / `stopScan` | WiFi network scan |
| `networkPill` | `connectSsid` / `forgetSsid` / `disconnectDevice` | Connect (SSID), forget SSID, disconnect iface |
| `networkPill` | `startApplet` / `stopApplet` / `toggleApplet` | nm-applet tray (session only) |
| `networkPill` | `enableApplet` / `disableApplet` / `setAppletAutostart` | nm-applet autostart (survives reboot) |
| `networkPill` | `openEditor` | Launch `nm-connection-editor` |
| `networkPill` | `refreshIp` / `refreshDns` | Reapply IP / flush DNS |
| `networkPill` | `activateConnection` / `deactivateConnection` | `uuid` or connection name |
| `bluetoothPill` | `showPopup` / `hidePopup` / `togglePopup` | Open, close, or toggle the Bluetooth menu |
| `bluetoothPill` | `setPower` / `togglePower` / `enable` / `disable` | Adapter radio power on/off |
| `bluetoothPill` | `startScan` / `stopScan` / `toggleScan` | Device discovery |
| `bluetoothPill` | `setDiscoverable` / `toggleDiscoverable` | Make this PC discoverable |
| `bluetoothPill` | `startApplet` / `stopApplet` / `toggleApplet` | Blueman tray (this session only) |
| `bluetoothPill` | `disableApplet` / `enableApplet` | Blueman tray sticky autostart (survives reboot) |
| `bluetoothPill` | `setAppletAutostart` | `true`/`false` — same sticky enable/disable |
| `bluetoothPill` | `connectDevice` / `disconnectDevice` | Connect or disconnect a MAC address |
| `bluetoothPill` | `pairDevice` / `cancelPair` / `forgetDevice` | Pairing lifecycle for a MAC |
| `bluetoothPill` | `setTrusted` / `setBlocked` | Trust or block a MAC (`address` + `bool`) |
| `bluetoothPill` | `renameDevice` | Set BlueZ alias (`address` + `name`) |
| `bluetoothPill` | `setCardProfile` | Set PipeWire profile for a MAC (`address` + profile name) |
| `notificationBell` | `toggleDoNotDisturb` | Toggle Do Not Disturb for the configured notification daemon |
| `killTargetPill` | `activatePickMode` / `cancelPickMode` | Arm or cancel the click-to-kill picker (same as clicking the pill) |
| `sysStatsPill` | `setMetricsLiveUpdates` | Pause (`false`) or resume (`true`) metrics-popup polling for all CPU/Memory/GPU sections |
| `sysStatsPill` | `setCpuLiveUpdates` / `setMemLiveUpdates` / `setGpuLiveUpdates` | Pause or resume metrics-popup polling for one section |
| `sysStatsPill` | `toggleMetricsLiveUpdates` | Toggle metrics-popup polling for all sections |
| `sysStatsPill` | `toggleCpuLiveUpdates` / `toggleMemLiveUpdates` / `toggleGpuLiveUpdates` | Toggle metrics-popup polling for one section |

**Examples**

```bash
qs ipc call clockPill showCalendar
qs ipc call audioPill setEchoCancel true
qs ipc call audioPill disableEchoCancel
qs ipc call audioPill toggleEchoCancel
qs ipc call networkPill togglePopup
qs ipc call networkPill toggleWifi
qs ipc call networkPill openEditor
qs ipc call networkPill toggleApplet
qs ipc call bluetoothPill togglePopup
qs ipc call bluetoothPill togglePower
qs ipc call bluetoothPill startScan
qs ipc call bluetoothPill connectDevice "A0:0C:E2:66:FB:7D"
qs ipc call bluetoothPill renameDevice "A0:0C:E2:66:FB:7D" "Shokz Dark"
qs ipc call bluetoothPill setCardProfile "A0:0C:E2:66:FB:7D" "a2dp-sink"
qs ipc call bluetoothPill toggleApplet
qs ipc call notificationBell toggleDoNotDisturb
qs ipc call sysStatsPill setMetricsLiveUpdates false
qs ipc call sysStatsPill toggleMetricsLiveUpdates
qs ipc call sysStatsPill setCpuLiveUpdates false
qs ipc call shell setShowKillTargetPill true
qs ipc call killTargetPill activatePickMode
```

Metrics-popup IPC pauses sparklines, gauges, and process lists in the right-click dropdowns — not the compact CPU/Memory/GPU stats on the bar pill. Takes effect immediately while a popup is open; otherwise the paused state applies the next time you open that section. When `popupStatsPersistPause` is `true` in `Config.qml`, the choice is saved to `state/popup-stats.json`.

**Hyprland keybind examples** (in `~/.config/hypr/config/keybindings.lua`):

```
SUPER + C   →   qs ipc call clockPill showCalendar
SUPER + N   →   qs ipc call notificationBell toggleDoNotDisturb
SUPER + M   →   qs ipc call sysStatsPill toggleMetricsLiveUpdates
SUPER + X   →   qs ipc call killTargetPill activatePickMode
# Optional: bind echo cancel / Bluetooth / Network
# SUPER + ALT + E   →   qs ipc call audioPill toggleEchoCancel
# SUPER + ALT + B   →   qs ipc call bluetoothPill togglePopup
# SUPER + ALT + W   →   qs ipc call networkPill togglePopup
```

### Network pill (`NetworkPill.qml`)

Glassmorphic bar pill for day-to-day NetworkManager control via **Quickshell.Networking** plus `scripts/network-control.sh`. Intended as a replacement for the **nm-applet** menu while still allowing the tray applet to run when you want it (header **Applet on/off**).

| Input | Action |
|-------|--------|
| **Left-click** | Open / close the Network popup |
| **Right-click** | Disabled (use header **WiFi on/off** or `qs ipc call networkPill toggleWifi`) |

#### Layout

| Pane | Contents |
|------|----------|
| **Header** (full width) | WiFi / Net / Applet toggles, connectivity, ↻ IP / ↻ DNS, dual traffic graph |
| **Left** | **Adapters** (per-device status + actions) and **Connections** dropdown + **Editor** |
| **Right** | **WiFi** networks (scan, connect / disconnect / forget, PSK prompt) |
| **Details** | Single-column connection info (click any value to copy) |

#### Popup features

| Feature | Details |
|---------|---------|
| **WiFi radio** | Header **WiFi on/off** — software rfkill for all wireless devices |
| **Networking** | Header **Net on/off** — `nmcli networking` global switch (green when on) |
| **nm-applet** | Footer **Applet on/off**: left-click = session start/stop; right-click = sticky disable/enable (survives reboot via XDG autostart mask + `systemctl --user disable`). Amber border when sticky-disabled. IPC: `disableApplet` / `enableApplet` / `setAppletAutostart` |
| **Adapters** | Wired and WiFi devices with state, active connection name, IPv4, link speed; Disconnect / Connect / Details / Edit / Autoconnect |
| **Connections** | Dropdown of saved NM profiles (activate by selection); **Editor** opens `nm-connection-editor` for the selected profile |
| **Connection info** | Details panel (nm-applet *Connection Information* style): interface, MAC, cable/link, IPv4/IPv6, gateway, DNS, routes; click row to copy |
| **WiFi networks** | Right column: scan while popup is open; signal bars, security, saved flag; Connect (PSK prompt when needed), Disconnect, Forget |
| **Traffic graph** | Downstream (blue) + upstream (green) sparklines with live rates |

Config tokens (search **NETWORK** / `popupNetwork*` in `Config.qml`): `showNetworkPill`, `popupNetworkWidth`, `popupNetworkWifiWidth`, `popupNetworkHeight`, `iconNetwork*`.

#### Implementation notes

- **Backend:** `Quickshell.Networking` for devices, WiFi scan/connect/forget, wifi radio; `scripts/network-control.sh` for live IP/DNS/routes, connection list, global networking, and nm-applet control.
- **Scanner:** WiFi `scannerEnabled` is on only while the popup is open and WiFi is enabled.
- **Safety:** Devices and SSIDs are string-keyed (no long-lived NM object pointers). Password field uses `HyprlandFocusGrab` under Hyprland. Fail handlers disconnect when the popup closes.
- **Coexistence:** nm-applet may remain enabled for migration; use header session toggle or IPC `disableApplet` for permanent off. Advanced edits stay in `nm-connection-editor`.

#### Performance

- **One-pass device snapshot** for bar glyph, primary connection, WiFi connected SSID, and (when open) sorted AP list — no multi-walk of `Networking.devices` per frame.
- **Status poll:** ~12s while the popup is closed (bar only); ~1.5s while open (graph + adapters). Overlapping `nmcli` status runs are skipped.
- **Popup-gated work:** connection ComboBox model rebuild, rate history arrays, and WiFi SSID list materialization only while open; history cleared on close.
- **Connection model fingerprint:** dropdown is not rebuilt if UUID/active set is unchanged.
- **Sparse epoch timer** (3s while open) for weak NM notifies; no separate applet poll loop (status JSON carries `applet_running`).

#### IPC (`networkPill`)

Visibility (show/hide the pill itself) stays on the `shell` target. Actions below are on `networkPill`:

| Command | Arguments | Description |
|---------|-----------|-------------|
| `showPopup` / `hidePopup` / `togglePopup` | — | Open or close the Network menu |
| `setWifi` | `true`\|`false` | WiFi radio on/off |
| `toggleWifi` / `enableWifi` / `disableWifi` | — | Same radio control |
| `setNetworking` | `true`\|`false` | Global networking |
| `toggleNetworking` | — | Flip networking |
| `startScan` / `stopScan` | — | WiFi scanner |
| `connectSsid` | `ssid` | Connect (known/open; PSK via UI) |
| `disconnectDevice` | `iface` | e.g. `enp10s0` |
| `forgetSsid` | `ssid` | Forget saved WiFi |
| `startApplet` / `stopApplet` / `toggleApplet` | — | nm-applet for this session only |
| `enableApplet` | — | Enable unit + start (survives reboot) |
| `disableApplet` | — | Stop + disable unit (stays off after reboot) |
| `setAppletAutostart` | `true`\|`false` | Same as enable / disable |
| `openEditor` | — | `nm-connection-editor` |
| `refreshIp` / `refreshDns` | — | Reapply / renew IP; flush DNS caches |
| `activateConnection` | `uuid` or `name` | Bring a saved profile up |
| `deactivateConnection` | `uuid` or `name` | Bring a profile down |

**Applet note (same pattern as Bluetooth / Blueman):**

| Action | Session only? | Survives reboot? |
|--------|---------------|------------------|
| Footer left-click / `startApplet` / `stopApplet` / `toggleApplet` | Yes | No (if still enabled at login) |
| Footer right-click / `disableApplet` / `setAppletAutostart false` | Stops now | **Yes — stays off** |
| Footer right-click (when sticky-off) / `enableApplet` | Starts now | **Yes — starts at login** |

Sticky disable writes `~/.config/autostart/nm-applet.desktop` (`Hidden=true`) to mask `/etc/xdg/autostart/nm-applet.desktop`, and runs `systemctl --user disable nm-applet.service`.

```bash
# Keep off after reboot (recommended when using the Network pill)
qs ipc call networkPill disableApplet
# equivalent:
qs ipc call networkPill setAppletAutostart false

# Bring login autostart back
qs ipc call networkPill enableApplet
qs ipc call networkPill setAppletAutostart true

# Check
~/.config/quickshell/scripts/network-control.sh applet status
systemctl --user is-enabled nm-applet.service
```

```bash
# Pill visibility (shell target)
qs ipc call shell setShowNetworkPill false
qs ipc call shell toggleShowNetworkPill

# Widget actions
qs ipc call networkPill togglePopup
qs ipc call networkPill toggleWifi
qs ipc call networkPill disconnectDevice "enp10s0"
qs ipc call networkPill openEditor
qs ipc call networkPill refreshIp
qs ipc call networkPill refreshDns
qs ipc call networkPill activateConnection "Wired connection 1"

# nm-applet — session only (does not change login enablement)
qs ipc call networkPill toggleApplet
qs ipc call networkPill stopApplet

# nm-applet — keep off / on after reboot
qs ipc call networkPill disableApplet
qs ipc call networkPill enableApplet
qs ipc call networkPill setAppletAutostart false
```

### Bluetooth pill (`BluetoothPill.qml`)

Glassmorphic bar pill for day-to-day Bluetooth management via **Quickshell.Bluetooth** (BlueZ). Intended as a refined replacement for the Blueman tray applet while **keeping Blueman running** as a pairing-agent fallback for PIN/passkey dialogs.

| Input | Action |
|-------|--------|
| **Left-click** | Open / close the Bluetooth popup |
| **Right-click** | Toggle adapter radio power (`BluetoothAdapter.enabled`) |

#### Popup features

| Feature | Details |
|---------|---------|
| **Adapter power** | On/off for the default adapter (radio power — not `systemctl bluetooth.service`) |
| **Scan / pair** | Start discovery (auto-stops after `bluetoothScanSeconds`, default 45s); pair nearby devices (`device.pair()`). Passkey UI may open via Blueman/agent |
| **Discoverable** | Toggle so other devices can find this computer |
| **Device list** | Connected, Paired, and Available sections with connection status and battery % when reported |
| **Connect / disconnect** | For previously paired devices |
| **Rename** | Set the BlueZ alias (`device.name`) for paired devices — **Rename** chip + Save / Enter |
| **Trust / block** | Writable BlueZ flags per device |
| **Remove** | `device.forget()` with a confirm step |
| **Blueman applet** | Header **Applet on/off**: left-click = session start/stop; right-click = permanent disable/enable (XDG autostart). IPC: `disableApplet` / `enableApplet` / `setAppletAutostart` |
| **Audio profile** | For connected audio devices: PipeWire `bluez_card.*` profiles (A2DP / HFP / codecs) via `scripts/audio-control.sh` |
| **Device info** | Name, address, paired/bonded/trusted/blocked, battery, adapter, D-Bus path; optional launch of `blueman-manager` |

Config tokens (search **BLUETOOTH** / `popupBluetooth*` in `Config.qml`): `showBluetoothPill`, `popupBluetoothWidth`, `popupBluetoothHeight`, `bluetoothScanSeconds`, `iconBluetooth*`.

#### Implementation notes

- **Backend:** `Quickshell.Bluetooth` for adapter/devices; `scripts/audio-control.sh` for `bluez_card.*` profiles; Blueman via `scripts/blueman-applet-control.sh` (session start/stop + sticky XDG autostart override for reboot).
- **Perf:** One-pass device snapshot for bar metrics and (when the popup is open) section address lists; no multi-walk of the device model. Popup closed → empty section lists (bar still tracks connected count + primary battery via BlueZ property notifies). While open, a modest timer refreshes sparse notifies (faster during scan). Blueman status is polled slowly and on open/toggle only.
- **Safety:** Device selection is address-keyed (no long-lived BlueZ object pointers). Rename uses `HyprlandFocusGrab` so the `TextField` receives keys under Hyprland.
- **Close behavior:** Closing the popup stops discovery and clears expand/rename/profile UI state.

#### IPC (`bluetoothPill`)

Visibility (show/hide the pill itself) stays on the `shell` target. All actions below are on `bluetoothPill`:

| Command | Arguments | Description |
|---------|-----------|-------------|
| `showPopup` / `hidePopup` / `togglePopup` | — | Open or close the Bluetooth menu |
| `setPower` | `true`\|`false` | Adapter radio on/off |
| `togglePower` / `enable` / `disable` | — | Same power control |
| `startScan` / `stopScan` / `toggleScan` | — | Discovery (auto-stops after `bluetoothScanSeconds`) |
| `setDiscoverable` | `true`\|`false` | Advertise this PC |
| `toggleDiscoverable` | — | Flip discoverable |
| `startApplet` / `stopApplet` / `toggleApplet` | — | Blueman tray **this session only** (returns after reboot if autostart still on) |
| `disableApplet` | — | Stop now **and** mask login autostart (`~/.config/autostart/blueman.desktop` with `Hidden=true`) so it **stays off after reboot** |
| `enableApplet` | — | Remove that mask and start the applet again |
| `setAppletAutostart` | `true`\|`false` | Same as enable / disable |
| `connectDevice` / `disconnectDevice` | `address` | Connect or disconnect |
| `pairDevice` / `cancelPair` / `forgetDevice` | `address` | Pairing lifecycle |
| `setTrusted` | `address` `true`\|`false` | Trust flag |
| `setBlocked` | `address` `true`\|`false` | Block flag |
| `renameDevice` | `address` `name` | BlueZ alias |
| `setCardProfile` | `address` `profileName` | e.g. `a2dp-sink`, `headset-head-unit` |

```bash
# Pill visibility (shell target)
qs ipc call shell setShowBluetoothPill false
qs ipc call shell toggleShowBluetoothPill

# Widget actions
qs ipc call bluetoothPill togglePopup
qs ipc call bluetoothPill setPower true
qs ipc call bluetoothPill startScan
qs ipc call bluetoothPill connectDevice "A0:0C:E2:66:FB:7D"
qs ipc call bluetoothPill setTrusted "A0:0C:E2:66:FB:7D" true
qs ipc call bluetoothPill renameDevice "A0:0C:E2:66:FB:7D" "Shokz Dark"
qs ipc call bluetoothPill setCardProfile "A0:0C:E2:66:FB:7D" "a2dp-sink-sbc_xq"
qs ipc call bluetoothPill toggleApplet
# Permanent (survives reboot) — stop tray and prevent login autostart
qs ipc call bluetoothPill disableApplet
# Undo permanent disable
qs ipc call bluetoothPill enableApplet
# Or boolean form
qs ipc call bluetoothPill setAppletAutostart false
qs ipc call bluetoothPill setAppletAutostart true
```

#### Blueman tray persistence (session vs reboot)

| Action | Effect now | After reboot |
|--------|------------|--------------|
| Header left-click / `stopApplet` / `startApplet` / `toggleApplet` | Start or stop tray for **this session** | Autostart may bring Blueman back |
| Header right-click / `disableApplet` / `setAppletAutostart false` | Stop tray **and** mask login autostart | **Stays off** |
| Header right-click (when masked) / `enableApplet` / `setAppletAutostart true` | Remove mask and start tray | Starts at login again |

Sticky disable writes `~/.config/autostart/blueman.desktop` (`Hidden=true`), which overrides `/etc/xdg/autostart/blueman.desktop` for your user. Generated `app-blueman@autostart.service` cannot be `systemctl disable`'d reliably, so the desktop override is the durable mechanism (implemented in `scripts/blueman-applet-control.sh`).

```bash
# CLI (same as IPC)
~/.config/quickshell/scripts/blueman-applet-control.sh status
~/.config/quickshell/scripts/blueman-applet-control.sh disable   # permanent off
~/.config/quickshell/scripts/blueman-applet-control.sh enable    # permanent on
~/.config/quickshell/scripts/blueman-applet-control.sh stop      # session only
```

The Applet button border turns amber when login autostart is masked.

### Audio pill (`AudioPill.qml`)

Bar pill for speaker + mic control (default view is **dual**: both bars with percent labels).

| Input | Action |
|-------|--------|
| **Left-click** | Open / close the full **Audio Controls** popup |
| **Right-click** | Cycle pill layout: speaker only → mic only → dual |
| **Middle-click** | Mute (speaker in dual/speaker view; mic in mic-only view) |
| **Scroll on a bar** | Step that device’s volume (swayosd-style feedback via `audio-osd.sh`) |

Pill volume bars are display + wheel only (no click-drag). Volume % and mute state are **cached** and refreshed on a short timer so the bar never holds a live binding into a dying PipeWire node.

#### Popup controls

| Area | Controls |
|------|----------|
| **Header** | Active app streams summary, **pw-top**, **Restart audio** |
| **Playback** | Device picker (transport icon + optional BT battery), card **Profile**, master **Volume** + mute, collapsible **L/R**, **Level** VU meter |
| **Recording** | Same pattern; headset **Profile** when the input device exposes card profiles; collapsible **Echo cancel** |

- **Device** — selecting a device makes it the **live system default** (PipeWire preferred default + routing). Device and profile flyouts anchor to the row you clicked (over Playback / Recording), not the bottom of the screen.
- **Profile** — PipeWire/Pulse card profiles via `audio-control.sh list-card-profiles` / `set-card-profile`. Playback profiles show for cards with sinks; recording profiles show for headset-style inputs. Hidden when no card/profiles exist.
- **Volume / Level** — slightly extra vertical gap under Device/Profile so the bars don’t feel cramped. Level uses `PwNodePeakMonitor` + `components/AudioLevelMeter.qml`; sampling runs only while the popup is open and the section Level switch is On.
- **L/R** — stereo balance only (`PwNodeAudio.volumes` + `pactl` multi-channel write). **Collapsed by default**; click `▸ L/R` (summary shows `L% / R%`) to expand dual sliders, or `▾` to collapse again. Hidden for mono devices.
- **Echo cancel** — **Collapsed by default**; header shows On/Off status. Expand for the toggle + sticky-preference hint.
- **BT battery** — polled via `audio-control.sh bt-battery` (BlueZ Battery1), shown on the pill and in the popup when available. Name/MAC based — no live BlueZ property bindings in the UI path.
- Popup size: `popupAudioWidth` / `popupAudioHeight` in `Config.qml`.

#### Stability (Bluetooth disconnect)

BT headsets (e.g. OpenRun Pro 2) destroy their PipeWire nodes and the default sink on disconnect. A live QML binding to `Pipewire.defaultAudioSink` during that teardown used to segfault Quickshell (`Default configured sink destroyed`).

Hardening approach:

| Practice | Detail |
|----------|--------|
| **Name-based selection** | Popup selection is stored as sink/source **names**, re-resolved from the current device list |
| **No live default bindings** | Bar `speaker` / `mic` are plain properties assigned only after a debounced device refresh from the safe list — never a continuous binding to `Pipewire.defaultAudio*` |
| **Immediate drop on default change** | On default sink/source change, clear held `PwNode` refs and device arrays, then resync after settle (`deviceRefreshDebounce` + `pwResyncTimer`) |
| **Volume cache** | Pill % / mute / popup master volume read from cache, not from a dying node mid-notification |
| **Peak monitors gated** | `PwNodePeakMonitor.node` is null unless the popup is open, Level is On, and a resolved node exists |
| **Battery by name** | BT battery display uses node **names** / MACs only (process-isolated `bt-battery`), not live D-Bus bindings on the node |

If `qs` ever crashes on disconnect again, check `~/.cache/quickshell/crashes/*/report.txt` and the log tail for `Default configured sink destroyed`.

#### Echo cancel (system AEC)

Optional **WebRTC acoustic echo cancellation** for speaker bleed into the mic (e.g. YouTube on speakers while the mic is open). Uses PipeWire `module-echo-cancel` and temporary virtual devices:

| Node | Role |
|------|------|
| `qs_ec_source` | Cleaned default microphone |
| `qs_ec_sink` | Default playback path used as the AEC reference |

Meet, Telegram, and Discord follow system defaults, so they pick up `qs_ec_*` while echo cancel is **On**, and hardware again when **Off**. App-built-in AEC is left alone; if a call sounds odd, turn Off.

| Mechanism | Purpose |
|-----------|---------|
| `echo-cancel.pref` | Sticky preference `{"preferred":true\|false}` under this config dir (not committed; per-machine) |
| `scripts/audio-control.sh` | `echo-cancel-status` / `on` / `off` / `force-off` / `apply` |
| `quickshell-echo-cancel.service` | User systemd unit (under `~/.config/systemd/user/`) runs `echo-cancel-apply` after PipeWire at login |
| AudioPill + IPC | Collapsible UI toggle and `qs ipc call audioPill …` (same sticky on/off) |

**Enable / disable**

```bash
# UI: left-click audio pill → expand Echo cancel → On/Off

# IPC (sticky across reboot when On)
qs ipc call audioPill enableEchoCancel
qs ipc call audioPill disableEchoCancel
qs ipc call audioPill setEchoCancel true
qs ipc call audioPill toggleEchoCancel

# CLI
~/.config/quickshell/scripts/audio-control.sh echo-cancel-on
~/.config/quickshell/scripts/audio-control.sh echo-cancel-off
~/.config/quickshell/scripts/audio-control.sh echo-cancel-force-off   # hard cleanup
~/.config/quickshell/scripts/audio-control.sh echo-cancel-status      # JSON
```

**Login autostart** (already used if you enabled permanence):

```bash
systemctl --user enable --now quickshell-echo-cancel.service
systemctl --user disable --now quickshell-echo-cancel.service   # stop autostart
```

**Back-out ladder**

1. UI / IPC / `echo-cancel-off` — unload module, restore previous hardware defaults, `preferred=false`
2. `echo-cancel-force-off` — same even if state is missing/corrupt
3. Disable the user unit (and optionally delete `echo-cancel.pref`)

No permanent PipeWire `conf.d` is written; everything is reversible.

#### Related files

| Path | Role |
|------|------|
| `widgets/AudioPill.qml` | Bar pill + popup + IPC |
| `components/AudioLevelMeter.qml` | VU / peak meter visuals |
| `components/VolumeBar.qml` / `MiniVolumeBar.qml` | Volume sliders |
| `scripts/audio-control.sh` | Profiles, channel volume, echo cancel, BT battery |
| `scripts/audio-osd.sh` | Volume OSD helper for wheel steps |
| `Config.qml` | `popupAudioWidth`, `popupAudioHeight`, volume color tiers |

### Workspaces (`WorkspacesPill.qml` + `Config.qml`)

Workspace pill behavior is configured in `Config.qml` and applied by `widgets/WorkspacesPill.qml`.

| Setting | Default | IPC (`shell` target) | Description |
|---------|---------|----------------------|-------------|
| `wsShowSpecialPill` | `true` | `setShowMagicWorkspacePill` / `toggleShowMagicWorkspacePill` | Show the magic-space pill (🪄) before workspace 1 |
| `wsMinimumShown` | `3` | `setWsMinimumShown` | When `wsShowOnlyActive` is `false`, always show numbered pills `1` … `N` (even if empty). Clamped to 1–10 |
| `wsShowOnlyActive` | `false` | `setWsShowOnlyActive` | When `true`, only show numbered workspaces that are occupied or active (plus extras above `wsMinimumShown` that qualify) |
| `wsStartupWorkspace` | `1` | `setWsStartupWorkspace` | Hyprland workspace to focus when `qs` starts (`0` = leave unchanged). Clamped to 0–10; applies on next `qs` start |
| `wsStartupCloseMagic` | `true` | `setWsStartupCloseMagic` | Close the magic overlay on `qs` start before applying `wsStartupWorkspace`. Applies on next `qs` start |
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

**IPC examples** (runtime until `qs` restarts; `wsMinimumShown` / `wsShowOnlyActive` update the pill immediately):

```bash
qs ipc call shell setWsMinimumShown 7
qs ipc call shell setWsShowOnlyActive true
qs ipc call shell setWsStartupWorkspace 1
qs ipc call shell setWsStartupCloseMagic false
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
| **Memory** | System memory and swap usage with history and breakdown |
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

`Config.qml` is the single source of truth for bar visuals, widget visibility defaults, and workspace behavior. `shell.qml` re-exports theme properties on the root `bar` object (e.g. `bar.accent`, `bar.wsMinimumShown`). The inspector loads a local `Config` instance for overlay-specific tokens.

Edit `Config.qml` to change:

- Colors, fonts, spacing, radii, and icon glyphs
- Bar position and size (`barPosition`, `barHeight`, `barEdgeMargin`)
- Bar pill visibility defaults (`showLauncherPill`, `showAudioPill`, etc.) and launcher command (`launcherCommand`)
- **Quick Launch** apps (`quickLaunchApps`)
- **Notification bell** daemon commands (`notification*`)
- **Power menu** session commands (`power*Command`, `powerMenuActions`)
- **Kill Target** pill (`killTargetIcon`, `showKillTargetPill`, etc.)
- Workspace pill count, active-only mode, magic pill default, and startup focus (search **WORKSPACES**; IPC: `setWsMinimumShown`, `setWsShowOnlyActive`, `setWsStartupWorkspace`, `setWsStartupCloseMagic`)
- System Stats pill and metrics popups (search **SYS STATS PILL** and `popupStats*`)
- Inspector sizing and semantic colors (search `insp*` properties)

Every property in `Config.qml` has an inline or section comment explaining what it does and which widget uses it. Search for the section headers in the file (e.g. **POWER MENU**, **NOTIFICATION BELL**, **WIDGET VISIBILITY**).

The file is named `Config.qml` (capital **C**) because QML requires that naming for reliable type registration across subdirectories.

### System Stats pill (`Config.qml`)

Search for **SYS STATS PILL** for the compact bar widget (CPU | Memory | GPU), and **popupStats** for the large right-click dropdowns.

**Bar pill size** — if the glass border is too narrow or numbers stick out past the edges:

| Property | What it does | Default |
|----------|--------------|---------|
| `statPillWidth` | Total width of the pill border in pixels. **Change this first.** | `640` |
| `statPillSectionWidth` | Width of each column (CPU, Memory, GPU) | `190` |
| `statPillSpacing` | Gap between columns | `10` |
| `statPillPaddingH` | Left/right padding inside the border | `12` |

**Bar pill colors** — utilization bar tiers (`statUtilTier1`–`4`, `statUtilThreshold1`–`3`) and CPU/GPU temperature label colors (`statTempCool` / `Warm` / `Hot`, `statTempWarmAt` / `HotAt`).

**Metrics popups** (right-click a section) — each section has its own size and screen position:

| Prefix | Section |
|--------|---------|
| `popupStatsCpu*` | CPU (left) |
| `popupStatsMem*` | Memory (middle) |
| `popupStatsGpu*` | GPU (right) |

- `*Width` / `*Height` — popup panel size in pixels
- `*AnchorX` — `0` = align to left of section, `0.5` = center, `1` = right
- `*AnchorWholePill` — `true` = anchor to the full pill instead of that section
- `*OffsetX` / `*OffsetY` — nudge popup left/right or up/down in pixels
- `*BarGap` — distance between the bar and the popup

**Live updates** — `popupStatsLiveUpdates` sets whether charts refresh while a popup is open. `popupStatsPersistPause: true` saves Pause/Resume choices to `state/popup-stats.json`.

### Notification bell (`Config.qml` + `NotificationBell.qml`)

Search for **NOTIFICATION BELL** in `Config.qml`. Defaults are SwayNC (`swaync-client`). To use another daemon, replace the command lists. `NotificationBell.qml` reads these lists, builds proper argv arrays, and polls internally (same pattern as `SysStatsPill.qml`).

| Property | SwayNC default | Purpose |
|----------|----------------|---------|
| `notificationSubscribe` | `["swaync-client", "-s", "-sw"]` | Optional live stream for badge / DND updates |
| `notificationTogglePanel` | `["swaync-client", "-t", "-sw"]` | Left-click on bell |
| `notificationToggleDnd` | `["swaync-client", "-d", "-sw"]` | Right-click menu |
| `notificationClearAll` | `["swaync-client", "-C", "-sw"]` | Right-click menu |
| `notificationSync` | `["…/scripts/notification-sync.sh"]` | Timer poller; prints `{"count":N,"dnd":true\|false}` |
| `notificationSyncIntervalMs` | `2500` | How often the sync script runs |
| `notificationDndAccent` | `#e85d5d` | Pill border, bell, and badge tint when DND is on |

Use `[]` to disable subscribe, sync, or any action. Keep `notificationSync` enabled for reliable badge/DND state; subscribe is optional live updates on top. Config command lists are QML lists — the bell copies them to JS arrays before starting `Io.Process` (do not bind lists directly).

**SwayNC tip:** run only one instance (e.g. `swaync.service` via systemd, not also `hl.exec_cmd("swaync")` in Hyprland autostart). If `notify-send` shows nothing, check DND: `swaync-client -D -sw` — use `swaync-client -df -sw` to turn off.

### Power menu (`Config.qml`)

Search for **POWER MENU**. Each session action has its own command list (or shell string). Use `[]` to hide an action from both the grid and right-click menu.

| Property | Default | Purpose |
|----------|---------|---------|
| `powerLockCommand` | `["hyprlock"]` | Lock screen |
| `powerLogoutCommand` | `["sh", "-c", "…"]` | Log out of Hyprland (stops apps, then `hyprshutdown` or `hl.dsp.exit`) |
| `powerRebootCommand` | `["sh", "-c", "…"]` | Reboot |
| `powerShutdownCommand` | `["sh", "-c", "…"]` | Shutdown |
| `powerBiosCommand` | `["systemctl", "reboot", "--firmware-setup"]` | Firmware setup on next boot |
| `powerMenuActions` | Lock / Logout / … rows | Icons (`iconLock`, etc.), labels, and `action` ids — reorder or rename here |

Logout/reboot/shutdown defaults stop `psd.service` and several user apps before the system action. Edit those pipelines to match your setup.

### Quick Launch (`Config.qml`)

Search for **QUICK LAUNCH**. Edit the `quickLaunchApps` list — one object per icon. Reorder, add, or remove entries; Quickshell reloads automatically.

| Field | Purpose |
|-------|---------|
| `icon` | Path to PNG/SVG image |
| `glyph` | Optional nerd-font character (use instead of `icon` if `icon` is empty) |
| `command` | Launch command as a **list** `["gtk-launch", "firefox"]` (preferred) or shell string `"gtk-launch firefox"`. Use the list form for `gtk-launch` and full paths. |
| `tooltip` | Hover label |

Also tune `quickLaunchIcon` (size), `quickLaunchSpacing`, and `quickLaunchPaddingH`.

### Kill Target pill (`Config.qml`)

Search for **KILL TARGET PILL**. Set `showKillTargetPill: true` to show the bar icon (default is hidden). Tune `killTargetIcon`, `killTargetTooltip`, and `killTargetOverlayDim` (screen dimming while picking). Kills use SIGTERM via `process-control.sh` — only processes owned by your user; root-owned apps are rejected with an error message.

---

## License

Personal configuration. Feel free to take inspiration.