#!/usr/bin/env bash
# autostart-add.sh — add an app to ~/.config/autostart
# Usage:
#   autostart-add.sh --desktop-id firefox.desktop
#   autostart-add.sh --desktop-file /usr/share/applications/foo.desktop
#   autostart-add.sh --name Name --exec "cmd" [--icon path] [--id name.desktop]
#
# When given a real .desktop file, copy it into autostart (preserving Exec= and
# other keys). Synthesizing minimal entries with gtk-launch is unreliable
# (e.g. DBusActivatable apps like Telegram silently no-op under gtk-launch).
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

python3 - "$DIR" "${DESKTOP_FILE:-}" "${NAME:-}" "${EXEC:-}" "${ICON:-}" "${OUT_ID:-}" <<'PY'
import re, sys
from pathlib import Path

out_dir = Path(sys.argv[1])
desktop_file = sys.argv[2] or ""
name = sys.argv[3] or ""
exec_cmd = sys.argv[4] or ""
icon = sys.argv[5] or ""
out_id = sys.argv[6] or ""

# Keys we always force for login autostart
FORCE_KEYS = {
    "Hidden": "false",
    "X-GNOME-Autostart-enabled": "true",
    "X-systemd-skip": "true",  # our login helper runs these; skip systemd generator
}


def set_keys(content: str, pairs: dict) -> str:
    """Update or append keys inside the [Desktop Entry] section only."""
    lines = content.splitlines(keepends=True)
    if not lines:
        lines = ["[Desktop Entry]\n"]

    has_entry = any(l.strip() == "[Desktop Entry]" for l in lines)
    if not has_entry:
        lines.insert(0, "[Desktop Entry]\n")

    found = {k: False for k in pairs}
    out = []
    in_entry = False
    for line in lines:
        s = line.strip()
        if s.startswith("["):
            if in_entry:
                for k, v in pairs.items():
                    if not found[k]:
                        out.append(f"{k}={v}\n")
                        found[k] = True
            in_entry = s == "[Desktop Entry]"
            out.append(line)
            continue
        if in_entry and s and not s.startswith("#") and "=" in s:
            k = s.split("=", 1)[0].strip()
            if k in pairs:
                out.append(f"{k}={pairs[k]}\n")
                found[k] = True
                continue
        out.append(line)
    if in_entry:
        for k, v in pairs.items():
            if not found[k]:
                out.append(f"{k}={v}\n")
    return "".join(out)


def safe_out_id(candidate: str, fallback_name: str) -> str:
    oid = Path(candidate).name if candidate else ""
    if not oid:
        safe = re.sub(r"[^A-Za-z0-9._-]+", "-", fallback_name).strip("-").lower() or "app"
        oid = safe
    if not oid.endswith(".desktop"):
        oid += ".desktop"
    return oid


if desktop_file:
    src = Path(desktop_file)
    if not src.is_file():
        print(f"error: not a file: {src}", file=sys.stderr)
        sys.exit(1)
    # Copy the real desktop entry so Exec=/TryExec/DBus keys stay correct.
    out_id = safe_out_id(out_id or src.name, src.stem)
    dest = out_dir / out_id
    content = set_keys(src.read_text(errors="replace"), FORCE_KEYS)
    dest.write_text(content)
    print(f"ok {dest}")
else:
    if not name or not exec_cmd:
        print("error: need --name and --exec, or --desktop-id/--desktop-file", file=sys.stderr)
        sys.exit(1)
    out_id = safe_out_id(out_id, name)
    dest = out_dir / out_id
    # Manual entry only (no system .desktop to copy)
    icon_line = f"Icon={icon}\n" if icon else ""
    content = (
        "[Desktop Entry]\n"
        "Type=Application\n"
        f"Name={name}\n"
        f"Exec={exec_cmd}\n"
        f"{icon_line}"
        "Terminal=false\n"
        "StartupNotify=false\n"
        "Hidden=false\n"
        "X-GNOME-Autostart-enabled=true\n"
        "X-systemd-skip=true\n"
    )
    dest.write_text(content)
    print(f"ok {dest}")
PY
