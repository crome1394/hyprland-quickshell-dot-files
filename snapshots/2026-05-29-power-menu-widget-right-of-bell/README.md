# Power Menu Widget Snapshot

Added power/session quickshell widget:
- New pill icon (power symbol ⏻ / 󰐥) placed immediately to the right of the notification bell (with divider).
- Clicking opens a centered glassmorphic popup (matches existing popup styling).
- 5 large icon buttons: Lock (hyprlock), Logout (hyprctl dispatch exit), Reboot, Shutdown, Enter BIOS (systemctl reboot --firmware-setup).
- Hover, keyboard Esc support, click-outside (on card) and X to close.
- All actions use Quickshell.execDetached + auto-close menu.
- Follows the glassmorphic / pill / nerd font conventions of the bar.

To reload after edits:
  pkill qs && qs &

Tested via qmllint (no new syntax errors).


