#!/usr/bin/env bash
exec timeout --kill-after=2 12 "$(dirname "${BASH_SOURCE[0]}")/sysmon-poller.sh"