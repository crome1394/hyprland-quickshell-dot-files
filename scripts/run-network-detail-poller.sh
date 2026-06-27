#!/usr/bin/env bash
exec timeout --kill-after=3 15 "$(dirname "${BASH_SOURCE[0]}")/network-detail-poller.sh"