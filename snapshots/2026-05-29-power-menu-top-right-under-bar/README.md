# Power Menu - Top Right Under Bar (repositioned)

## Change from previous version
- Moved from screen-center floating window → standard "under the bar" popup anchored near the power pill (top-right of screen).
- Positioning now matches calendar, audio controls, tray menus, etc.:
  - Uses powerPill.mapToItem(barBg, ...)
  - y = bar.implicitHeight + 4
  - Horizontal bias toward the right + clamping
- Slightly narrowed the card (560px) for better right-side aesthetics while keeping all 5 buttons comfortable.
- Toggle behavior improved (clicking the pill while open now closes it, like other widgets).
- Header comment and docs updated.

All other behavior (icons, actions, glass styling, Esc/close, hyprlock + systemctl commands, etc.) unchanged.

## How to reload
pkill qs && qs &

## Files
- shell.qml : the full current config with the widget
