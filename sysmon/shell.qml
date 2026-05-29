import Quickshell
import QtQuick

// sysmon - Standalone floating dashboard
// Launch with: qs -p ~/.config/quickshell/sysmon
//
// Uses FloatingWindow (a Quickshell toplevel) so it is visible to `hyprctl clients`
// and can be targeted by Hyprland window rules / special workspaces ("magic space").

ShellRoot {
    Dashboard {
        autoPoll: false

        Component.onCompleted: {
            show()
            // Perform one initial data refresh on startup (manual mode by default)
            Qt.callLater(function() { refresh() })
        }
    }
}
