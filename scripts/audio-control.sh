#!/usr/bin/env bash
# pactl audio control: defaults, ports, volume, mute.
set -euo pipefail

ACTION="${1:-}"
TARGET="${2:-}"   # sink | source
NAME="${3:-}"
ARG="${4:-}"      # port name or volume percent

if [[ -z "$ACTION" || -z "$TARGET" ]]; then
    echo "usage: audio-control.sh <set-default|set-port|set-volume|toggle-mute> <sink|source> <name> [port|percent]" >&2
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
        if [[ -z "$NAME" || -z "$ARG" ]]; then
            echo "device name and port required" >&2
            exit 2
        fi
        case "$TARGET" in
            sink)   pactl set-sink-port "$NAME" "$ARG" ;;
            source) pactl set-source-port "$NAME" "$ARG" ;;
            *) echo "invalid target: $TARGET" >&2; exit 2 ;;
        esac
        ;;
    set-volume)
        if [[ -z "$NAME" || -z "$ARG" ]]; then
            echo "device name and volume percent required" >&2
            exit 2
        fi
        if ! [[ "$ARG" =~ ^[0-9]+$ ]]; then
            echo "volume must be an integer percent (0-100+)" >&2
            exit 2
        fi
        case "$TARGET" in
            sink)   pactl set-sink-volume "$NAME" "${ARG}%" ;;
            source) pactl set-source-volume "$NAME" "${ARG}%" ;;
            *) echo "invalid target: $TARGET" >&2; exit 2 ;;
        esac
        ;;
    toggle-mute)
        if [[ -z "$NAME" ]]; then
            echo "device name required" >&2
            exit 2
        fi
        case "$TARGET" in
            sink)   pactl set-sink-mute "$NAME" toggle ;;
            source) pactl set-source-mute "$NAME" toggle ;;
            *) echo "invalid target: $TARGET" >&2; exit 2 ;;
        esac
        ;;
    *)
        echo "invalid action: $ACTION" >&2
        exit 2
        ;;
esac

echo "ok"