#!/usr/bin/env bash
# Blueman tray applet control for BluetoothPill.
#
# Session-only:
#   blueman-applet-control.sh start|stop|toggle|status
#
# Survives reboot (XDG autostart override — generated app-blueman@autostart
# units cannot be systemctl-disable'd reliably):
#   blueman-applet-control.sh enable|disable|set-autostart true|false
#
# Disable writes ~/.config/autostart/blueman.desktop with Hidden=true so the
# system /etc/xdg/autostart/blueman.desktop entry is masked for this user.
# Enable removes that override (or clears Hidden) and starts the applet.
set -euo pipefail

ACTION="${1:-}"
ARG2="${2:-}"

UNIT_AUTOSTART="app-blueman@autostart.service"
UNIT_STATIC="blueman-applet.service"
AUTOSTART_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/autostart"
OVERRIDE_DESKTOP="${AUTOSTART_DIR}/blueman.desktop"
SYSTEM_DESKTOP="/etc/xdg/autostart/blueman.desktop"

json_esc() {
    local s="${1:-}"
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    s=${s//$'\n'/\\n}
    printf '%s' "$s"
}

ok_json() {
    local msg="${1:-}"
    if [[ -n "$msg" ]]; then
        printf '{"ok":true,"message":"%s"}\n' "$(json_esc "$msg")"
    else
        printf '{"ok":true}\n'
    fi
}

err_json() {
    printf '{"ok":false,"error":"%s"}\n' "$(json_esc "${1:-error}")"
    exit 1
}

applet_running() {
    # Match the real binary only — never "blueman-applet-control.sh" (pkill -f trap).
    pgrep -f '/usr/bin/blueman-applet' >/dev/null 2>&1 \
        || pgrep -f '/usr/bin/python[^ ]* /usr/bin/blueman-applet' >/dev/null 2>&1
}

# true if user has not masked autostart (will start at login)
applet_autostart_enabled() {
    if [[ -f "$OVERRIDE_DESKTOP" ]]; then
        # Hidden=true or Autostart-enabled=false → disabled
        if grep -qiE '^[[:space:]]*Hidden[[:space:]]*=[[:space:]]*true' "$OVERRIDE_DESKTOP" 2>/dev/null; then
            return 1
        fi
        if grep -qiE '^[[:space:]]*X-GNOME-Autostart-enabled[[:space:]]*=[[:space:]]*false' "$OVERRIDE_DESKTOP" 2>/dev/null; then
            return 1
        fi
    fi
    # No override, or override still allows start
    return 0
}

applet_start() {
    # --no-block avoids hanging if the user bus is slow
    systemctl --user start --no-block "$UNIT_AUTOSTART" 2>/dev/null || true
    systemctl --user start --no-block "$UNIT_STATIC" 2>/dev/null || true
    sleep 0.35
    if applet_running; then
        return 0
    fi
    if command -v blueman-applet >/dev/null 2>&1; then
        nohup blueman-applet >/dev/null 2>&1 &
        disown || true
        sleep 0.35
        applet_running && return 0
    fi
    return 1
}

applet_stop() {
    # Kill first (fast), then ask systemd to clean up units without blocking long.
    # IMPORTANT: patterns must not match this script's path (*blueman-applet-control*).
    if applet_running; then
        pkill -f '/usr/bin/blueman-applet' 2>/dev/null || true
        pkill -f '/usr/bin/blueman-tray' 2>/dev/null || true
        sleep 0.15
    fi
    systemctl --user stop --no-block "$UNIT_AUTOSTART" 2>/dev/null || true
    systemctl --user stop --no-block "$UNIT_STATIC" 2>/dev/null || true
    sleep 0.15
    if applet_running; then
        pkill -9 -f '/usr/bin/blueman-applet' 2>/dev/null || true
        pkill -9 -f '/usr/bin/blueman-tray' 2>/dev/null || true
        sleep 0.1
    fi
    ! applet_running
}

# Sticky enable: remove user override so system XDG autostart applies again
applet_enable() {
    mkdir -p "$AUTOSTART_DIR"
    if [[ -f "$OVERRIDE_DESKTOP" ]]; then
        # If our override only exists to hide, remove it entirely
        rm -f "$OVERRIDE_DESKTOP"
    fi
    applet_start || true
    if applet_autostart_enabled; then
        ok_json "Blueman applet enabled (starts at login)"
    else
        err_json "failed to enable Blueman autostart"
    fi
}

# Sticky disable: user autostart override with Hidden=true + stop now
applet_disable() {
    mkdir -p "$AUTOSTART_DIR"
    cat >"$OVERRIDE_DESKTOP" <<'EOF'
[Desktop Entry]
Type=Application
Name=Blueman Applet
Comment=Blueman Bluetooth Manager (disabled by Quickshell BluetoothPill)
Exec=blueman-applet
Icon=blueman
Terminal=false
Categories=
Hidden=true
X-GNOME-Autostart-enabled=false
EOF
    applet_stop || true
    if applet_running; then
        err_json "stopped autostart but process still running"
    fi
    if applet_autostart_enabled; then
        err_json "autostart override not applied"
    fi
    ok_json "Blueman applet disabled (stays off after reboot)"
}

cmd_status() {
    local running="false" enabled="false"
    applet_running && running="true"
    applet_autostart_enabled && enabled="true"
    printf '{"ok":true,"running":%s,"autostart_enabled":%s}\n' "$running" "$enabled"
}

usage() {
    cat >&2 <<'EOF'
usage: blueman-applet-control.sh status|start|stop|toggle|enable|disable
       blueman-applet-control.sh set-autostart true|false
EOF
}

case "$ACTION" in
    status)
        cmd_status
        ;;
    start)
        if applet_start; then
            ok_json "started"
        else
            err_json "failed to start blueman-applet"
        fi
        ;;
    stop)
        if applet_stop; then
            ok_json "stopped"
        else
            err_json "failed to stop blueman-applet"
        fi
        ;;
    toggle)
        if applet_running; then
            applet_stop && ok_json "stopped" || err_json "failed to stop"
        else
            applet_start && ok_json "started" || err_json "failed to start"
        fi
        ;;
    enable)
        applet_enable
        ;;
    disable)
        applet_disable
        ;;
    set-autostart)
        case "${ARG2,,}" in
            true|1|on|yes)  applet_enable ;;
            false|0|off|no) applet_disable ;;
            *)
                usage
                exit 2
                ;;
        esac
        ;;
    *)
        usage
        exit 2
        ;;
esac
