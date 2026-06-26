#!/usr/bin/env bash
# Fetch the last N lines from a configured log source (stdout only).
set -euo pipefail

SOURCE="${1:-hyprland}"
LINES="${2:-100}"

if ! [[ "$LINES" =~ ^[0-9]+$ ]] || (( LINES < 1 || LINES > 5000 )); then
    echo "Invalid line count: $LINES" >&2
    exit 1
fi

UID_NUM="$(id -u)"
HYPR_LOG="$(ls -t "/run/user/${UID_NUM}"/hypr/*/hyprland.log 2>/dev/null | head -1 || true)"

fetch_tail() {
    local file="$1"
    if [[ -z "$file" || ! -f "$file" ]]; then
        echo "(log file not found)"
        return 0
    fi
    tail -n "$LINES" "$file"
}

fetch_journal() {
    local scope="$1"
    shift
    if [[ "$scope" == "user" ]]; then
        journalctl --user "$@" -n "$LINES" --no-pager -o short-iso 2>/dev/null \
            || echo "(no journal entries)"
    else
        journalctl "$@" -n "$LINES" --no-pager -o short-iso 2>/dev/null \
            || echo "(no journal entries)"
    fi
}

case "$SOURCE" in
    hyprland)
        fetch_tail "$HYPR_LOG"
        ;;
    journal-user)
        fetch_journal user
        ;;
    journal-system)
        fetch_journal system
        ;;
    kernel)
        fetch_journal system -k
        ;;
    swaync)
        fetch_journal user -u swaync
        ;;
    hypridle)
        fetch_journal user -u hypridle
        ;;
    hyprpolkitagent)
        fetch_journal user -u hyprpolkitagent
        ;;
    pipewire)
        fetch_journal user -u pipewire
        ;;
    portal-hyprland)
        fetch_journal user -u xdg-desktop-portal-hyprland
        ;;
    hyprland-wm)
        fetch_journal user -u "wayland-wm@hyprland"
        ;;
    quickshell)
        fetch_journal user -u quickshell
        ;;
    *)
        echo "Unknown log source: $SOURCE" >&2
        exit 1
        ;;
esac