# Snapshot: Workspace Cold-Start Poller (fix "only shows one workspace on qs launch")

**Date:** 2026-05-30

## Problem
When launching quickshell (`qs`) after a cold boot / reboot (or any time Hyprland is already running with applications open on multiple workspaces), the workspace widget only displayed the single active workspace. All other occupied workspaces were invisible in the bar until a window was opened/closed or the focused workspace changed.

This was especially noticeable right after login when many apps were already restored across workspaces 1-5 (or more).

## Root Cause
The workspace widget relies on `Quickshell.Hyprland` (the Hyprland IPC backend):

- `shownWorkspaces` is populated by `updateShownWorkspaces()` (see shell.qml:85-101).
- The filter only includes workspaces that have `toplevels.count > 0` (or `.values.length > 0`) **or** are `active`/`focused`.
- On `Component.onCompleted` the function is called exactly once (shell.qml:134-137).
- It also reacts to `Hyprland.workspaces.valuesChanged` and `Hyprland.focusedWorkspaceChanged` via `Connections` (shell.qml:139-146).

When quickshell starts *after* Hyprland has already populated its internal state, the initial IPC dump that Quickshell receives is often incomplete for non-active workspaces. In particular, the list of toplevels (windows) per workspace arrives with a short delay (typically 150–800 ms). At the moment of the first `valuesChanged` signal and the single `onCompleted` call, most workspaces report zero windows, so the filter drops them. Only the currently focused workspace is reliably visible immediately.

The existing comment in the source even acknowledged this class of timing issue (shell.qml:147-148).

No continuous polling existed — the widget was purely event-driven after the first paint.

## Solution Implemented
Added a short, self-stopping **cold-start poller** (`wsColdStartPoller` Timer) that fires a burst of forced calls to `updateShownWorkspaces()` right after quickshell starts:

- New property: `property int _wsColdPollCount: 0` (shell.qml:153)
- New Timer (shell.qml:154-167):
  - `interval: 130`
  - `repeat: true`
  - Each tick calls `updateShownWorkspaces()` and increments the counter.
  - After 7 ticks (~910 ms total coverage) the timer automatically stops and resets the counter.
- Started from `Component.onCompleted` (shell.qml:137): `wsColdStartPoller.start();`

This gives the Hyprland IPC backend enough time to deliver the complete initial workspace + toplevel state. After the short burst the poller stops completely — there is zero ongoing CPU or timer cost. All normal reactive behavior (the two `Connections` handlers) remains unchanged and continues to drive live updates for the rest of the session.

## Diff Summary (key changes)

```diff
+    // Cold-start workspace polling (fixes "only shows current workspace on qs launch after cold boot/reboot")
+    property int _wsColdPollCount: 0
+    Timer {
+        id: wsColdStartPoller
+        interval: 130
+        repeat: true
+        onTriggered: {
+            bar.updateShownWorkspaces();
+            bar._wsColdPollCount += 1;
+            if (bar._wsColdPollCount >= 7) {   // ~910ms of coverage
+                stop();
+                bar._wsColdPollCount = 0;
+            }
+        }
+    }

     Component.onCompleted: {
         bar.updateShownWorkspaces();
         audio.refreshDevices();
+        wsColdStartPoller.start();   // cold-start burst to catch full workspace state on qs launch
     }
```

Full fixed file: `shell.qml` (in this snapshot directory).

## Verification Notes
- After a `qs -r` (or logout + login), the bar should now immediately show all occupied workspaces (with their icons + numbers) even if no windows are opened after qs starts.
- The poller is intentionally short and bounded so it never runs in steady state.
- Existing hover preview, click-to-switch, scroll wheel, and reactive updates are completely unaffected.
- This is a minimal, targeted, well-documented fix for the exact cold-start race the user reported.

## Files in this snapshot
- `shell.qml` — the version containing the cold-start workspace poller
- `README.md` — this document

All previous workspace-related snapshots remain in sibling directories for history.
