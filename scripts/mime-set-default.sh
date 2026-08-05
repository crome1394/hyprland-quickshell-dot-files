#!/usr/bin/env bash
# mime-set-default.sh — set or clear the user default application for a MIME type
# Usage:
#   mime-set-default.sh set <mime-type> <app.desktop>
#   mime-set-default.sh unset <mime-type>
# Prints JSON: { "ok": true, "action": "set"|"unset", "mime": "...", "desktopId": "..." }
# On failure: { "ok": false, "error": "..." } and exit 1
set -euo pipefail

ACTION="${1:-}"
MIME="${2:-}"
DESKTOP="${3:-}"

python3 - "$ACTION" "$MIME" "$DESKTOP" <<'PY'
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

action = (sys.argv[1] if len(sys.argv) > 1 else "").strip().lower()
mime = (sys.argv[2] if len(sys.argv) > 2 else "").strip()
desktop = (sys.argv[3] if len(sys.argv) > 3 else "").strip()

def out(obj, code=0):
    print(json.dumps(obj, ensure_ascii=False))
    sys.exit(code)

def err(msg):
    out({"ok": False, "error": msg}, 1)

if action not in ("set", "unset"):
    err("Usage: mime-set-default.sh set|unset <mime> [app.desktop]")

if not mime or "/" not in mime:
    err("A valid file type id is required (e.g. application/pdf).")

if action == "set":
    if not desktop:
        err("Choose an application to set as default.")
    if not desktop.endswith(".desktop"):
        desktop = desktop + ".desktop"
    # Basic sanitize
    if "/" in desktop or ".." in desktop or not re.match(r"^[\w.+\-@]+\.desktop$", desktop):
        err("Invalid application id.")
    xdg = shutil.which("xdg-mime")
    if not xdg:
        err("xdg-mime not found on PATH.")
    try:
        r = subprocess.run(
            [xdg, "default", desktop, mime],
            capture_output=True, text=True, timeout=10,
        )
    except Exception as e:
        err(f"Could not set default: {e}")
    if r.returncode != 0:
        msg = (r.stderr or r.stdout or "").strip()
        err(msg or "Could not set default (app missing or permission).")
    out({
        "ok": True,
        "action": "set",
        "mime": mime,
        "desktopId": desktop,
    })

# unset: surgically remove from [Default Applications] in user mimeapps.list only
user_list = Path.home() / ".config" / "mimeapps.list"
if not user_list.is_file():
    # Nothing to clear
    out({
        "ok": True,
        "action": "unset",
        "mime": mime,
        "desktopId": "",
        "note": "No user mimeapps.list; nothing to clear.",
    })

try:
    text = user_list.read_text(errors="replace")
except OSError as e:
    err(f"Could not read mimeapps.list: {e}")

lines = text.splitlines(keepends=True)
if not lines and text:
    lines = [text]

new_lines = []
section = None
changed = False
for line in lines:
    stripped = line.strip()
    if stripped.startswith("[") and stripped.endswith("]"):
        section = stripped[1:-1].strip()
        new_lines.append(line)
        continue
    if (
        section == "Default Applications"
        and stripped
        and not stripped.startswith("#")
        and "=" in stripped
    ):
        key = stripped.split("=", 1)[0].strip()
        if key == mime:
            changed = True
            continue  # drop every Default Applications line for this type
    new_lines.append(line)

if not changed:
    out({
        "ok": True,
        "action": "unset",
        "mime": mime,
        "desktopId": "",
        "note": "No user default was set for this type.",
    })

# Atomic rewrite
try:
    user_list.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(
        prefix=".mimeapps.",
        suffix=".tmp",
        dir=str(user_list.parent),
    )
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write("".join(new_lines))
            if new_lines and not new_lines[-1].endswith("\n"):
                f.write("\n")
        os.replace(tmp_name, user_list)
    except Exception:
        try:
            os.unlink(tmp_name)
        except OSError:
            pass
        raise
except OSError as e:
    err(f"Could not update mimeapps.list: {e}")

out({
    "ok": True,
    "action": "unset",
    "mime": mime,
    "desktopId": "",
})
PY
