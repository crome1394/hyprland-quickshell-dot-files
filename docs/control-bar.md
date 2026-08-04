<!-- Extracted from README for reference. See ../README.md for overview. -->

# Bar control strip (`BarControlBar.qml`)

Open via the **Config menu** gear or **right-click empty bar chrome**. Toolbar on the **bottom**; content expands above and resizes to fit (scroll only for tall panels: Display, Wallpaper, Widgets, Options, Launch, Autostart).

| Panel | What it does |
|-------|----------------|
| **Position** | Pin bar top/bottom → `state/bar-layout.json` |
| **Display** | Monitor resolution / refresh / bit depth + adapter stats from `hyprctl` (see Display subsection) |
| **Wallpaper** | hyprpaper thumbs, apply, pick folder, add images |
| **Widgets** | **A–Z list**; each row is three columns: **✓/✕ + full name** · **L C R** · **↑ ↓**; width slider 80–180%. Names use flexible width (Notifications, Hypr Inspector, etc. not clipped). Net·BT·Audio is one pill. **Reset layout** / **Reset sizes** |
| **Options** | Behavior prefs (not layout) — table below |
| **Launch** | Quick Launch pins (installed apps or custom) |
| **Autostart** | XDG `~/.config/autostart` (see Autostart subsection) |
| **Services** | systemd user/system units — filter, select, **Start / Stop / Restart** (reuses Inspector `ServicesView`) |
| **Audio** | Sound manager: overview (summary / streams / levels), dual device columns + profiles, echo cancel; **pw-top** / **Restart audio** (reuses Inspector `AudioMonitorView`) |
| **Keybinds** | Browse `keybindings.lua` by category; **edit key chord, category, description** (not the action) |
| **Clock** | Clock format presets |

## Display panel

Runtime mode switcher for the focused (or configured) Hyprland monitor. Modes come live from `hyprctl monitors -j` → `availableModes` via `scripts/monitor-mode.sh` — not a hardcoded list.

Layout (top → bottom): status · adapter · **Resolution | Refresh | Bit depth** row · Apply.

| Control | Behavior |
|---------|----------|
| **Indicator** | Current resolution, refresh, bit depth, make/model/serial, connector + format + scale, physical size, position |
| **NVIDIA** | Button with Nerd Font `md-nvidia` glyph + label; opens `nvidia-settings` |
| **Adapter** | DRM connector + NVIDIA name/driver; util, temp, P-state, power, VRAM, clocks. Mini GPU/VRAM bars. |
| **Resolution** | Stepped block slider over `WxH` in the selected refresh **family**, sorted **width then height descending** |
| **Refresh rate** | Dropdown of **exact** rates for the selected resolution only (hyprctl). Changing rate refilters the resolution list by Hz **family** (e.g. 239.76 / 239.90 / 239.97 → ~240) |
| **Bit depth** | Dropdown: **8-bit** / **10-bit** (pending until Apply) |
| **Apply** | Commits pending mode + bitdepth at **scale 1.0** |

**Linked filtering**

- Pick a **resolution** → refresh dropdown lists only rates hyprctl reports for that `WxH`.
- Pick a **refresh rate** → resolution slider lists only `WxH` values that advertise a rate in the same family (~60 / ~75 / ~120 / ~240).
- Moving the slider snaps the pending rate to that panel’s exact EDID value in the same family so Apply always uses a real mode string.

**Polling / resources**

- GPU/status soft-poll runs **only** while the Display panel is open (default **3s**).
- Poll **pauses** while dragging the resolution slider; no background work when Display is closed.
- Selection changes do **not** bump global layout ticks (keeps the slider responsive).

Pending changes do **not** take effect until **Apply**. Apply uses:

```bash
hyprctl eval 'hl.monitor({ output="…", mode="WxH@rate", position="0x0", scale=1, bitdepth=N })'
```

`hyprctl reload` re-applies `monitors.lua` and can snap back to the config default.

Related CLI (outside this repo, on PATH): `hypr-resolution` — rofi menu over the same EDID modes (default 10-bit, scale 1).

## Options panel

| Section | Controls | Persistence |
|---------|----------|-------------|
| **Bar / UI** | UI scale auto/manual · Config menu icon on bar | `bar-layout.json` |
| **Workspaces** | Magic pill · only-active · min pills · startup workspace · close magic on start | `bar-layout.json` |
| **Audio** | Show AEC section · show Summary / device profiles / Level meters · keep Summary / Active streams expanded (AEC on/off is only in the Audio panel) | visibility/expand → `bar-layout.json` |
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

## Audio panel

Sound manager without opening the full Config Inspector or the bar audio pill. Embeds `components/AudioMonitorView.qml` (same engine as the Inspector **Audio** tab), plus tools from the AudioPill.

Layout (top → bottom):

| Area | Controls |
|------|----------|
| **Tools** | **Refresh**, **pw-top** (kitty), **Restart audio** (`audio-control.sh restart-audio`) |
| **Filter** | Text field filters devices and stream names |
| **Overview** (one pill) | **Audio Summary** → **Active streams** → **Levels** (no inter-card dead space) |
| **Devices** | Dual columns: sinks / sources — volume, mute, **Set Default**, **ports**; **Profile** under each column |
| **Echo cancel** | Sticky On/Off at the **bottom** (AEC preference; same scripts as the pill) |

**Overview details**

- **Summary** — default output/input labels, sink/source counts (collapsible; Options: show / keep expanded)
- **Active streams** — real app playback (▶) and recording (● REC); internal **Peak Detect** monitors are filtered out (collapsible; Options: keep expanded)
- **Levels** — Playback + Recording VU meters via name-resolved `PwNodePeakMonitor` (Options: show Level meters)

**Options → Audio** (persisted in `bar-layout.json`)

| Toggle | Effect |
|--------|--------|
| Show echo cancel in audio menu | Show/hide AEC section on **pill popup** and **this panel** (does **not** turn AEC on/off) |
| Show Audio Summary | Hide/show summary block in overview |
| Show device profiles | Profile dropdowns under Output / Input columns |
| Show Level meters | VU meters in overview |
| Keep Audio Summary expanded | Expand summary when the panel opens |
| Keep Active streams expanded | Expand streams when the panel opens |

**Sampling / resources** (idle when closed)

- `active` is true only while the Audio panel is open (and the control strip popup is visible)
- Soft re-poll ~3s **only while open**; peak monitors, profile fetches, and poller processes stop on close (`stopAllWork`)
- Card profiles re-fetch when the default sink/source **changes**, not on every soft-poll
- Scripts: `scripts/audio-poller.sh`, `scripts/audio-control.sh`, `scripts/audio-osd.sh`

The **AudioPill** remains the glance + wheel volume control on the bar; this panel is the multi-device manager. See [audio.md](audio.md) for pill details and the echo-cancel back-out ladder.

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
