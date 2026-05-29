# Power Menu - Cleanup Logic Matched to hyprland.lua

## Summary of this change
Updated the three destructive actions in the Quickshell power widget to exactly match the behavior of the keyboard bindings in ~/.config/hypr/hyprland.lua (lines ~358-360):

- powerLogout, powerReboot, and powerShutdown now run:
  `systemctl --user stop psd.service`
  `pkill -f "steam|discord|flameshot|espanso|google-chrome-stable"`
  `sleep 1`
  then the final action (with the same quoting and hyprshutdown fallback as the lua version for logout).

- Lock and "Enter BIOS" remain simple one-liners (no app killing needed).

This ensures that using the bar power menu produces identical cleanup behavior as the keybindings (CTRL+SUPER+ALT+R, CTRL+SUPER+ALT+P, Super+M).

## Files in snapshot
- shell.qml (current state with the matched cleanup commands)
- This README

## Reload
pkill qs && qs &
