#!/usr/bin/env bash
exec timeout --kill-after=2 8 "$(dirname "${BASH_SOURCE[0]}")/process-poller.sh"