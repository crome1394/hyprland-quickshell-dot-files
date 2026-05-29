# sysmon — Quickshell System Monitor Dashboard

**Current status**: Uses `FloatingWindow` so it is a normal client visible to `hyprctl clients`. You must use Hyprland window rules to float it and place it on your special "magic" workspace (see bottom of this file).

This version now uses the **exact same architecture** as your working `~/.config/quickshell-help/HelpMenu.qml`:

- `shell.qml` is a tiny `ShellRoot` wrapper
- All logic lives in `Dashboard.qml` (an `Item` containing a nested `PanelWindow`)
- `show()` uses the defensive `if (typeof window.x === "number")` check before positioning
- Explicit `visible` control

This pattern is what finally makes the floating window appear reliably on your system.

## Launch

```bash
qs -p ~/.config/quickshell/sysmon
```

Recommended Hyprland bind (manual only, no autostart):

```ini
bind = $mainMod, M, exec, qs -p ~/.config/quickshell/sysmon
```

## Hyprland magic/special workspace integration

The dashboard now uses a regular `Window` (not a layer-shell PanelWindow), so it is visible in `hyprctl clients`:

- class: `quickshell`
- title: `sysmon-dashboard`

Example window rules for a "magic" special workspace:

```ini
windowrulev2 = float, title:^(sysmon-dashboard)$
windowrulev2 = workspace special:magic silent, title:^(sysmon-dashboard)$
windowrulev2 = size 1020 780, title:^(sysmon-dashboard)$
# optional: keep it from stealing focus etc.
# windowrulev2 = noinitialfocus, title:^(sysmon-dashboard)$
```

Launch it, move it to the special workspace once, then toggle with your normal special workspace key.

## Current Status

**New two-column grouped layout** (experiment based on your feedback).

Current organization:
- Left column: CPU (big) + Memory + Top Processes (grouped together as requested)
- Right column: GPU (big) + Storage + Network
- Bottom bar: Load, Uptime, ccache, status

This should eliminate overlap and make related data easier to scan. Let me know how it feels and what to tweak next.

Current coverage:
- CPU (gauge + sparkline + detailed temps)
- GPU (gauge + sparkline + VRAM, power, fan)
- Memory (RAM visual bar + Swap)
- Network (visualized with RX + TX sparklines + rates)
- Disk (visualized with Read + Write sparklines + root usage + I/O rates)
- Load Average + Uptime
- NVMe Sensors (top 3)
- Top Processes (top 5 by CPU)

Still missing / to polish later:
- Click-to-launch actions (btop, nvtop, nmtui)
- More sensor detail / power if possible
- Full theming + spacing polish

Run it and let me know how the new visualized Network and Disk sections feel, and what to tackle next (more sensors? better Top Processes table? click handlers?).

## Files

- `shell.qml` — minimal ShellRoot wrapper (do not edit)
- `Dashboard.qml` — the actual floating window (this is where we'll build the UI)
- `scripts/poller.sh` — data collector
- `components/` — CircularGauge.qml and Sparkline.qml (ready for when we restore the pretty version)

## Next Steps

Run it and tell me:

1. Does the window appear?
2. Can you move/resize it using your normal Hyprland mouse/key bindings once it is floated?
3. Does Refresh populate live numbers?

If yes → we delete the debug visuals and build the real dashboard in the next step.
