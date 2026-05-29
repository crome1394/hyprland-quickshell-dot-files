# Workspace Popup Click Bugfix - Reliable Workspace + Window Focus

**Date**: 2026-05-27

## Bug
When hovering a workspace popup from a different workspace and clicking a window entry (e.g. hovering ws3 from ws1 and clicking Discord), the workspace would not switch.

## Root Cause
The previous click handler did two separate dispatches in quick succession:

1. `workspace.activate()` → dispatches "workspace <name>"
2. `focuswindow address:0x...`

Because these were sent back-to-back, Hyprland sometimes processed the `focuswindow` command before the workspace switch had fully taken effect. Since `focuswindow` only works on windows that are on the current workspace, the second command would silently fail (or be ignored), leaving the user on the original workspace.

## Fix
Changed the logic to primarily use:

```qml
Hyprland.dispatch(`focuswindow address:0x${addr}`);
```

**Why this works better:**
- In Hyprland, `focuswindow` by address is designed to both focus the window **and** automatically switch to its workspace if needed.
- It is a single, atomic-style action from the client's perspective.
- We now only fall back to explicit `workspace.activate()` if we don't have a window address.

The new handler is:

```qml
onClicked: {
    const addr = modelData && modelData.addressStr ? modelData.addressStr() : "";

    if (addr) {
        // Preferred method - handles both workspace switch and window focus
        Hyprland.dispatch(`focuswindow address:0x${addr}`);
    } else if (bar.hoveredWorkspace && bar.hoveredWorkspace.activate) {
        bar.hoveredWorkspace.activate();
    }

    bar.hoveredWorkspace = null;
}
```

This is the standard pattern used in many Hyprland + Quickshell configurations for "jump to window" functionality.

## Snapshot
`~/.config/quickshell/snapshots/2026-05-27-popup-click-fix/`

Contains the corrected `shell.qml`.

## Testing
After reloading, try the exact scenario:
- Be on workspace 1
- Hover the button for workspace 3
- Click on an app row in the popup

It should now correctly switch to workspace 3 and focus the chosen application.
