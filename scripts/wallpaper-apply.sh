#!/usr/bin/env bash
# wallpaper-apply.sh — set wallpaper via hyprpaper (immediate) + persist hyprpaper.conf
# Usage: wallpaper-apply.sh <image-path> [monitor]
set -euo pipefail

PATH_IMG="${1:-}"
MONITOR="${2:-${HYPR_WALLPAPER_MONITOR:-DP-1}}"
FIT="${HYPR_WALLPAPER_FIT:-cover}"
CONF="${HYPR_WALLPAPER_CONF:-$HOME/.config/hypr/hyprpaper.conf}"

if [[ -z "$PATH_IMG" || ! -f "$PATH_IMG" ]]; then
  echo "error: file not found: $PATH_IMG" >&2
  exit 1
fi

# Absolute path
PATH_IMG="$(readlink -f "$PATH_IMG" 2>/dev/null || realpath "$PATH_IMG" 2>/dev/null || echo "$PATH_IMG")"

# Apply now (hyprpaper IPC)
if ! hyprctl hyprpaper wallpaper "${MONITOR},${PATH_IMG},${FIT}" >/dev/null 2>&1; then
  # Older syntax without fit mode
  if ! hyprctl hyprpaper wallpaper "${MONITOR},${PATH_IMG}" >/dev/null 2>&1; then
    echo "error: hyprctl hyprpaper wallpaper failed" >&2
    exit 1
  fi
fi

# Persist for next hyprpaper start (rewrite minimal conf, keep splash/ipc if present)
splash=false
ipc=true
if [[ -f "$CONF" ]]; then
  grep -q '^splash' "$CONF" && splash="$(grep -E '^splash\s*=' "$CONF" | head -1 | cut -d= -f2- | tr -d '[:space:]' || echo false)"
  grep -q '^ipc' "$CONF" && ipc="$(grep -E '^ipc\s*=' "$CONF" | head -1 | cut -d= -f2- | tr -d '[:space:]' || echo true)"
fi

mkdir -p "$(dirname "$CONF")"
cat >"$CONF" <<EOF
# Managed by quickshell wallpaper-apply.sh — last applied $(date -Iseconds)
preload = ${PATH_IMG}
wallpaper = ${MONITOR},${PATH_IMG}
splash = ${splash:-false}
ipc = ${ipc:-true}

wallpaper {
	monitor = ${MONITOR}
	path = ${PATH_IMG}
	fit_mode = ${FIT}
}
EOF

# State for the control bar
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/hypr-wallpaper"
mkdir -p "$STATE_DIR"
printf '%s\n' "$PATH_IMG" >"$STATE_DIR/current"
printf '%s\n' "$MONITOR" >"$STATE_DIR/monitor"

echo "ok ${MONITOR} ${PATH_IMG}"
