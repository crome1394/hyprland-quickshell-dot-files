#!/usr/bin/env bash
# wallpaper-add.sh — pick image files (zenity) and copy into wallpaper directory
# Usage: wallpaper-add.sh [target-directory]
# Prints JSON: { "dir": "...", "added": ["path", ...], "count": N }
set -euo pipefail

DIR="${1:-$HOME/Pictures/wallpapers}"
DIR="${DIR/#\~/$HOME}"
mkdir -p "$DIR"

if ! command -v zenity >/dev/null 2>&1; then
  echo '{"error":"zenity not found","added":[],"count":0}' 
  exit 1
fi

# Multi-select image files
mapfile -t FILES < <(zenity --file-selection --multiple --separator=$'\n' \
  --title="Add wallpapers" \
  --file-filter='Images | *.jpg *.jpeg *.png *.webp *.gif *.bmp *.JPG *.JPEG *.PNG *.WEBP' \
  --file-filter='All files | *' 2>/dev/null || true)

added=()
for f in "${FILES[@]:-}"; do
  [[ -z "$f" || ! -f "$f" ]] && continue
  base="$(basename "$f")"
  dest="$DIR/$base"
  # Avoid overwrite: append numeric suffix
  if [[ -e "$dest" ]]; then
    stem="${base%.*}"
    ext="${base##*.}"
    n=2
    while [[ -e "$DIR/${stem}-${n}.${ext}" ]]; do
      n=$((n + 1))
    done
    dest="$DIR/${stem}-${n}.${ext}"
  fi
  cp -n -- "$f" "$dest" 2>/dev/null || cp -- "$f" "$dest"
  added+=("$(readlink -f "$dest" 2>/dev/null || echo "$dest")")
done

python3 - "$DIR" "${added[@]+${added[@]}}" <<'PY'
import json, sys
from pathlib import Path
d = sys.argv[1]
added = sys.argv[2:]
print(json.dumps({"dir": str(Path(d).resolve()), "added": added, "count": len(added)}, ensure_ascii=False))
PY
