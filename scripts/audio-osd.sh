#!/usr/bin/env bash
# Show swayosd volume feedback for inspector slider changes.
set -euo pipefail

KIND="${1:-sink}"   # sink | source
PCT="${2:-0}"
MUTED="${3:-0}"

if ! command -v swayosd-client >/dev/null 2>&1; then
    exit 0
fi

pct_int=$(printf '%d' "$PCT" 2>/dev/null || echo 0)
progress=$(awk -v p="$pct_int" 'BEGIN {
    if (p < 0) p = 0
    if (p > 100) p = 100
    printf "%.2f", p / 100
}')

if [[ "$MUTED" == "1" || "$MUTED" == "yes" || "$MUTED" == "true" ]]; then
    if [[ "$KIND" == "source" ]]; then
        icon="microphone-sensitivity-muted"
    else
        icon="audio-volume-muted"
    fi
    progress="0.0"
    text="Muted"
else
    if [[ "$KIND" == "source" ]]; then
        icon="audio-input-microphone"
    elif (( pct_int > 66 )); then
        icon="audio-volume-high"
    elif (( pct_int > 33 )); then
        icon="audio-volume-medium"
    else
        icon="audio-volume-low"
    fi
    text="${pct_int}%"
fi

swayosd-client --custom-icon "$icon" --custom-progress "$progress" --custom-progress-text "$text"