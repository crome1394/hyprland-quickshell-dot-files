#!/usr/bin/env bash
# pactl default sink/source and port switching.
set -euo pipefail

ACTION="${1:-}"
TARGET="${2:-}"   # sink | source
NAME="${3:-}"
PORT="${4:-}"

if [[ -z "$ACTION" || -z "$TARGET" ]]; then
    echo "usage: audio-control.sh <set-default|set-port> <sink|source> <name> [port]" >&2
    exit 2
fi

if ! command -v pactl >/dev/null 2>&1; then
    echo "pactl not found" >&2
    exit 1
fi

case "$ACTION" in
    set-default)
        if [[ -z "$NAME" ]]; then
            echo "device name required" >&2
            exit 2
        fi
        case "$TARGET" in
            sink)   pactl set-default-sink "$NAME" ;;
            source) pactl set-default-source "$NAME" ;;
            *) echo "invalid target: $TARGET" >&2; exit 2 ;;
        esac
        ;;
    set-port)
        if [[ -z "$NAME" || -z "$PORT" ]]; then
            echo "device name and port required" >&2
            exit 2
        fi
        case "$TARGET" in
            sink)   pactl set-sink-port "$NAME" "$PORT" ;;
            source) pactl set-source-port "$NAME" "$PORT" ;;
            *) echo "invalid target: $TARGET" >&2; exit 2 ;;
        esac
        ;;
    *)
        echo "invalid action: $ACTION" >&2
        exit 2
        ;;
esac

echo "ok"