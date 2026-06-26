import Quickshell
import QtQuick

// sysmon — Standalone launcher for the side system monitor panel.
//
// Recommended command:
//   qs -p ~/.config/quickshell/sysmon.qml
//
// This is the clean way that matches how the main bar is launched.
// The config root becomes ~/.config/quickshell/, so:
// - import "widgets" works and registers SysmonPanel
// - The imports inside widgets/SysmonPanel.qml (import ".." and "../components")
//   resolve to paths inside the config folder.
// - Bare "Theme" and "SysMonService" types become available to the panel
//   document (same mechanism the main shell.qml + HyprConfigInsp rely on).
//
// Once loaded this way the panel calls show() immediately.
//
// You can also integrate it into your normal bar later by instantiating
// SysmonPanel inside shell.qml (after its `import "widgets"`).

import "widgets"

ShellRoot {
    SysmonPanel {
        Component.onCompleted: show()
    }
}
