<!-- Extracted from README for reference. See ../README.md for overview. -->

# Bar control strip (`BarControlBar.qml`)

Open via the **Config menu** gear or **right-click empty bar chrome**. Toolbar on the **bottom**; content expands above and resizes to fit (scroll only for tall panels: Wallpaper, Widgets, Options, Launch, Autostart).

| Panel | What it does |
|-------|----------------|
| **Position** | Pin bar top/bottom → `state/bar-layout.json` |
| **Wallpaper** | hyprpaper thumbs, apply, pick folder, add images |
| **Widgets** | **A–Z list**; each row is three columns: **✓/✕ + full name** · **L C R** · **↑ ↓**; width slider 80–180%. Names use flexible width (Notifications, Hypr Inspector, etc. not clipped). Net·BT·Audio is one pill. **Reset layout** / **Reset sizes** |
| **Options** | Behavior prefs (not layout) — table below |
| **Launch** | Quick Launch pins (installed apps or custom) |
| **Autostart** | XDG `~/.config/autostart` (see Autostart subsection) |
| **Services** | systemd user/system units — filter, select, **Start / Stop / Restart** (reuses Inspector `ServicesView`) |
| **Keybinds** | Browse `keybindings.lua` by category; **edit key chord, category, description** (not the action) |
| **Clock** | Clock format presets |

## Options panel

| Section | Controls | Persistence |
|---------|----------|-------------|
| **Bar / UI** | UI scale auto/manual · Config menu icon on bar | `bar-layout.json` |
| **Workspaces** | Magic pill · only-active · min pills · startup workspace · close magic on start | `bar-layout.json` |
| **Audio** | Echo cancel AEC · show AEC in audio popup | AEC scripts; visibility → `bar-layout.json` |
| **Network** | nm-applet sticky login autostart | XDG / applet control |
| **Bluetooth** | Blueman sticky login autostart | XDG / applet control |
| **System stats** | Show CPU / Memory / GPU · metrics live updates | gauges → `bar-layout.json` |
| **FreshRSS** | Filters expanded on open · HTTPS/HTTP · host · user · API password · **Test** / **Save server** | filters → `bar-layout.json`; credentials → `~/.config/freshrss-quickshell/freshrss.env` (never git) |

Editable text fields use a slightly lifted background so they read as inputs. Toggle/number columns share a fixed right-hand control slot for alignment.

## XDG Autostart panel

Session user apps only (not Hyprland core). Scripts: `autostart-list-json.sh`, `autostart-set.sh`, `autostart-add.sh`, `autostart-run.sh`, `xdg-autostart-run.sh`. Desktop entries use real `Exec=` lines and `X-systemd-skip=true`. Failures log to `~/.local/state/quickshell/autostart-run.log`.

Login helper in Hyprland `autostarts.lua`:

```lua
hl.exec_cmd("/home/crome/.config/quickshell/scripts/xdg-autostart-run.sh")
```

Put Telegram/Discord workspace placement in **window rules** (e.g. `special:magic silent`), not in Autostart `exec` workspace options.

## Services panel

Quick recovery for systemd units without opening the full Config Inspector. Embeds `components/ServicesView.qml` (same UI as the Inspector **Services** tab):

- Filter chips: **All / Running / Failed**, plus a text search field
- Table: service name, status, state, loaded-since, description
- Actions on the selected row: **Start**, **Stop**, **Restart**, **Refresh**
- Scripts: `scripts/services-poller.sh`, `scripts/services-control.sh`
- Polls only while the panel is open (`active` binding)
- User units: `systemctl --user`. System units may prompt for polkit (same as [inspector.md](inspector.md))

Full metrics/logs/config browsing remains in the Hyprland Config Inspector (`qs ipc call hyprConfigInsp toggle`).

## Keybinds panel

Browse and lightly edit Hyprland binds without opening the full Inspector. Source of truth: `~/.config/hypr/config/keybindings.lua`.

- Same **categories** and **descriptions** as the Inspector (`--#Category# description` convention — see [inspector.md](inspector.md))
- Rows show key pills + description; **Edit** opens a form for:
  - **Key** chord (e.g. `SUPER + T`)
  - **Category**
  - **Description**
- The Lua **action / dispatcher** (`hl.dsp.*`, plugins, options tables) is **not** editable here — use Config Files / your editor for that
- Loop / dynamic keys (e.g. workspace `for` loop with `.. key`) are listed as **read-only**
- Scripts: `scripts/keybinds-list-json.sh`, `scripts/keybinds-set.sh`
- **Save** writes the file in place (timestamped `.bak.*` backup first). **Reload Hypr** runs `hyprctl reload` when you want the change live
