#!/usr/bin/env bash
# autostart-add.sh — add an app to ~/.config/autostart
# Usage:
#   autostart-add.sh --desktop-id firefox.desktop
#   autostart-add.sh --desktop-file /usr/share/applications/foo.desktop
#   autostart-add.sh --name Name --exec "cmd" [--icon path] [--id name.desktop]
set -euo pipefail

DIR="${XDG_CONFIG_HOME:-$HOME/.config}/autostart"
mkdir -p "$DIR"

DESKTOP_ID=""
DESKTOP_FILE=""
NAME=""
EXEC=""
ICON=""
OUT_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --desktop-id) DESKTOP_ID="${2:-}"; shift 2 ;;
    --desktop-file) DESKTOP_FILE="${2:-}"; shift 2 ;;
    --name) NAME="${2:-}"; shift 2 ;;
    --exec) EXEC="${2:-}"; shift 2 ;;
    --icon) ICON="${2:-}"; shift 2 ;;
    --id) OUT_ID="${2:-}"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

# Resolve from system desktop id
if [[ -n "$DESKTOP_ID" ]]; then
  DESKTOP_ID="$(basename "$DESKTOP_ID")"
  [[ "$DESKTOP_ID" == *.desktop ]] || DESKTOP_ID="${DESKTOP_ID}.desktop"
  for d in \
    "$HOME/.local/share/applications" \
    /usr/share/applications \
    /usr/local/share/applications \
    "$HOME/.local/share/flatpak/exports/share/applications" \
    /var/lib/flatpak/exports/share/applications
  do
    if [[ -f "$d/$DESKTOP_ID" ]]; then
      DESKTOP_FILE="$d/$DESKTOP_ID"
      break
    fi
  done
  if [[ -z "$DESKTOP_FILE" ]]; then
    echo "error: desktop id not found: $DESKTOP_ID" >&2
    exit 1
  fi
fi

python3 - "$DIR" "${DESKTOP_FILE:-}" "${NAME:-}" "${EXEC:-}" "${ICON:-}" "${OUT_ID:-}" "${DESKTOP_ID:-}" <<'PY'
import re, sys
from pathlib import Path

out_dir = Path(sys.argv[1])
desktop_file = sys.argv[2] or ""
name = sys.argv[3] or ""
exec_cmd = sys.argv[4] or ""
icon = sys.argv[5] or ""
out_id = sys.argv[6] or ""
desktop_id = sys.argv[7] or ""

def parse(path: Path):
    data = {}
    in_entry = False
    for line in path.read_text(errors="replace").splitlines():
        s = line.strip()
        if s.startswith("["):
            in_entry = s == "[Desktop Entry]"
            continue
        if not in_entry or not s or s.startswith("#") or "=" not in s:
            continue
        k, v = s.split("=", 1)
        data.setdefault(k.strip(), v.strip())
    return data

if desktop_file:
    src = Path(desktop_file)
    if not src.is_file():
        print(f"error: not a file: {src}", file=sys.stderr)
        sys.exit(1)
    data = parse(src)
    name = name or data.get("Name") or src.stem
    icon = icon or data.get("Icon") or ""
    exec_raw = data.get("Exec") or ""
    exec_clean = re.sub(r"\s+%[a-zA-Z@]", "", exec_raw).strip()
    # Prefer gtk-launch for reliability
    did = desktop_id or src.name
    if did.endswith(".desktop"):
        exec_cmd = exec_cmd or f"gtk-launch {did[:-8]}"
    else:
        exec_cmd = exec_cmd or exec_clean
    out_id = out_id or src.name
else:
    if not name or not exec_cmd:
        print("error: need --name and --exec, or --desktop-id/--desktop-file", file=sys.stderr)
        sys.exit(1)
    if not out_id:
        safe = re.sub(r"[^A-Za-z0-9._-]+", "-", name).strip("-").lower() or "app"
        out_id = safe if safe.endswith(".desktop") else f"{safe}.desktop"

out_id = Path(out_id).name
if not out_id.endswith(".desktop"):
    out_id += ".desktop"

# Only write inside autostart dir
dest = out_dir / out_id
content = f"""[Desktop Entry]
Type=Application
Name={name}
Exec={exec_cmd}
Icon={icon}
Terminal=false
StartupNotify=false
Hidden=false
X-GNOME-Autostart-enabled=true
"""
dest.write_text(content)
print(f"ok {dest}")
PY
