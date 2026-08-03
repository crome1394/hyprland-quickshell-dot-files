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

Session user apps only (not Hyprland core). Scripts: `autostart-list-json.sh`, `autostart-set.sh`, `autostart-add.sh`, `autostart-run.sh`, `xdg-autostart-run.sh`. Failures log to `~/.local/state/quickshell/autostart-run.log`.

### How entries are created

| Source | Behavior |
|--------|----------|
| **Installed app** (picker / `--desktop-id` / `--desktop-file`) | **Copy** the real `.desktop` from `/usr/share/applications` (or other XDG apps dirs) into `~/.config/autostart/`. Preserves the app’s `Exec=`, `TryExec=`, icons, and other keys. Only forces `Hidden=false`, `X-GNOME-Autostart-enabled=true`, and `X-systemd-skip=true`. |
| **Manual** (`--name` + `--exec`) | Synthesize a minimal entry with the given command. |

Do **not** rewrite `Exec=` to `gtk-launch …`. That breaks apps with `DBusActivatable=true` (e.g. Telegram): `gtk-launch` can exit 0 without starting the process. The working system file has a real command (`Exec=Telegram -- %U`); the autostart copy must keep that.

### How entries are run

`autostart-run.sh` (and the login helper) always run the entry’s **`Exec=`** line with FreeDesktop field codes (`%U`, `%f`, …) stripped. It does not call `gtk-launch`.

Login helper in Hyprland `autostarts.lua`:

```lua
hl.exec_cmd("/home/crome/.config/quickshell/scripts/xdg-autostart-run.sh")
```

`X-systemd-skip=true` tells the systemd user xdg-autostart generator to ignore these files so only this helper starts them (avoids double-start / D-Bus activation quirks).

### Repair a broken entry

If an older build left a synthetic file (e.g. `Exec=gtk-launch org.telegram`), re-add from the system desktop file:

```bash
~/.config/quickshell/scripts/autostart-add.sh --desktop-id org.telegram.desktop
# or: remove in the Autostart panel, then add again from the app list
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
