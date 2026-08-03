<!-- Extracted from README for reference. See ../README.md for overview. -->

# Workspaces (`WorkspacesPill.qml` + `Config.qml`)

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
