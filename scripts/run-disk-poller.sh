#!/usr/bin/env bash
exec timeout --kill-after=2 18 "$(dirname "${BASH_SOURCE[0]}")/disk-poller.sh"