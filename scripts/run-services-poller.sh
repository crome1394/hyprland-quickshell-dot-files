#!/usr/bin/env bash
exec timeout --kill-after=2 10 "$(dirname "${BASH_SOURCE[0]}")/services-poller.sh"