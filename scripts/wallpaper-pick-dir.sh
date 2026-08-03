#!/usr/bin/env bash
# wallpaper-pick-dir.sh — zenity directory picker for wallpaper folder
# Prints absolute path on stdout, empty if cancelled
set -euo pipefail

START="${1:-$HOME/Pictures/wallpapers}"
START="${START/#\~/$HOME}"

if ! command -v zenity >/dev/null 2>&1; then
  echo ""
  exit 1
fi

out="$(zenity --file-selection --directory \
  --title="Wallpaper directory" \
  --filename="${START}/" 2>/dev/null || true)"

if [[ -n "${out:-}" && -d "$out" ]]; then
  readlink -f "$out" 2>/dev/null || echo "$out"
else
  echo ""
fi
