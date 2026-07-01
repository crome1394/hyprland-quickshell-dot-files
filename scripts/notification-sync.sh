#!/usr/bin/env bash
# One-shot SwayNC badge state for the notification bell.
# Output: {"count":N,"dnd":true|false}

set -euo pipefail

if ! command -v swaync-client >/dev/null 2>&1; then
    printf '{"count":0,"dnd":false}\n'
    exit 0
fi

count=$(swaync-client -c -sw 2>/dev/null || echo 0)
dnd_raw=$(swaync-client -D -sw 2>/dev/null || echo false)
dnd=false
if [[ "$dnd_raw" =~ ^[Tt]rue$ ]]; then
    dnd=true
fi

count=${count//[^0-9]/}
count=${count:-0}

if [[ "$dnd" == true ]]; then
    printf '{"count":%s,"dnd":true}\n' "$count"
else
    printf '{"count":%s,"dnd":false}\n' "$count"
fi