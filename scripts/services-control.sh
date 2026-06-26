#!/usr/bin/env bash
# systemctl start|stop|restart for user or system scope.
set -euo pipefail

ACTION="${1:-}"
SCOPE="${2:-}"
UNIT="${3:-}"

if [[ -z "$ACTION" || -z "$SCOPE" || -z "$UNIT" ]]; then
    echo "usage: services-control.sh <start|stop|restart> <user|system> <unit>" >&2
    exit 2
fi

case "$ACTION" in
    start|stop|restart) ;;
    *)
        echo "invalid action: $ACTION" >&2
        exit 2
        ;;
esac

case "$SCOPE" in
    user|system) ;;
    *)
        echo "invalid scope: $SCOPE" >&2
        exit 2
        ;;
esac

ctl=(systemctl)
[[ "$SCOPE" == "user" ]] && ctl+=(--user)

if ! "${ctl[@]}" "$ACTION" "$UNIT"; then
    echo "systemctl $ACTION failed for $UNIT ($SCOPE)" >&2
    exit 1
fi

echo "ok"