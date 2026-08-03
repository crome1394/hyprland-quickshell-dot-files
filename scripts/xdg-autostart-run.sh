#!/usr/bin/env bash
# xdg-autostart-run.sh — login helper: run all enabled ~/.config/autostart apps
# Called once from Hyprland autostarts.lua so the control-bar Autostart panel is effective.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/autostart-run.sh"
