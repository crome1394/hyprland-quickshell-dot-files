#!/usr/bin/env bash
# One-shot notification badge state for daemons without a live subscribe stream.
# Usage: notification-state.sh <preset>
# Output: {"count":N,"dnd":true|false}

set -euo pipefail

PRESET="${1:-mako}"

case "$PRESET" in
mako)
    count=0
    dnd=false
    if command -v makoctl >/dev/null 2>&1; then
        count=$(makoctl count 2>/dev/null || echo 0)
        mode=$(makoctl mode 2>/dev/null || echo "")
        if [[ "$mode" == *"do-not-disturb"* ]]; then
            dnd=true
        fi
    fi
    if [[ "$dnd" == true ]]; then
        printf '{"count":%s,"dnd":true}\n' "$count"
    else
        printf '{"count":%s,"dnd":false}\n' "$count"
    fi
    ;;
*)
    printf '{"count":0,"dnd":false}\n'
    ;;
esac