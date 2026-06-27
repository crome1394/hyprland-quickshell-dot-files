#!/usr/bin/env bash
# Kill or restart a user-owned process (Processes tab actions).
set -euo pipefail

ACTION="${1:-}"
PID="${2:-}"
USER_NAME="${USER:-$(whoami)}"

if [[ -z "$ACTION" || -z "$PID" || ! "$PID" =~ ^[0-9]+$ ]]; then
    echo "usage: process-control.sh <kill|restart> <pid>" >&2
    exit 2
fi

if [[ ! -r "/proc/$PID/status" ]]; then
    echo "process $PID not found" >&2
    exit 3
fi

owner=$(ps -o user= -p "$PID" 2>/dev/null | xargs || true)
if [[ -z "$owner" ]]; then
    echo "process $PID not found" >&2
    exit 3
fi

if [[ "$owner" != "$USER_NAME" && "$USER_NAME" != "root" ]]; then
    echo "cannot control process owned by $owner" >&2
    exit 4
fi

case "$ACTION" in
kill)
    if ! kill -TERM "$PID" 2>/dev/null; then
        echo "failed to send SIGTERM to $PID" >&2
        exit 5
    fi
    ;;
restart)
    mapfile -d '' -t cmd_parts < "/proc/$PID/cmdline" 2>/dev/null || true
    if [[ ${#cmd_parts[@]} -eq 0 || -z "${cmd_parts[0]}" ]]; then
        echo "no cmdline available for $PID" >&2
        exit 6
    fi

    kill -TERM "$PID" 2>/dev/null || true
    for _ in 1 2 3 4 5; do
        kill -0 "$PID" 2>/dev/null || break
        sleep 0.1
    done
    if kill -0 "$PID" 2>/dev/null; then
        kill -KILL "$PID" 2>/dev/null || true
        sleep 0.15
    fi

    nohup "${cmd_parts[@]}" >/dev/null 2>&1 &
    ;;
*)
    echo "unknown action: $ACTION" >&2
    exit 2
    ;;
esac