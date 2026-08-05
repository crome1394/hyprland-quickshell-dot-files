#!/usr/bin/env bash
# mime-file-probe.sh — detect MIME type for a file path and current default handler
# Usage: mime-file-probe.sh <path>
# Prints JSON: { mime, comment, defaultId, defaultName, exists, error? }
set -euo pipefail

PATH_ARG="${1:-}"

python3 - "$PATH_ARG" <<'PY'
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

path_arg = (sys.argv[1] if len(sys.argv) > 1 else "").strip()
HOME = Path.home()

MIME_DIRS = [
    HOME / ".local/share/mime",
    Path("/usr/local/share/mime"),
    Path("/usr/share/mime"),
]

APP_DIRS = [
    HOME / ".local/share/applications",
    Path("/usr/local/share/applications"),
    Path("/usr/share/applications"),
    HOME / ".local/share/flatpak/exports/share/applications",
    Path("/var/lib/flatpak/exports/share/applications"),
]


def fail(msg, **extra):
    print(json.dumps({"error": msg, "exists": False, **extra}, ensure_ascii=False))
    sys.exit(0)


if not path_arg:
    fail("Paste a file path first.")

# Expand ~ and make absolute when possible
p = Path(path_arg).expanduser()
try:
    p = p.resolve(strict=False)
except Exception:
    pass

if not p.exists():
    fail("File not found or unreadable.", path=str(p), mime="")
if not p.is_file():
    fail("Path is not a regular file.", path=str(p), mime="")

mime = ""
# Prefer xdg-mime, then gio, then python mimetypes
xdg = shutil.which("xdg-mime")
if xdg:
    try:
        r = subprocess.run(
            [xdg, "query", "filetype", str(p)],
            capture_output=True, text=True, timeout=5,
        )
        if r.returncode == 0:
            mime = (r.stdout or "").strip()
    except Exception:
        pass

if not mime:
    gio = shutil.which("gio")
    if gio:
        try:
            r = subprocess.run(
                [gio, "info", "-a", "standard::content-type", str(p)],
                capture_output=True, text=True, timeout=5,
            )
            if r.returncode == 0:
                for line in (r.stdout or "").splitlines():
                    if "standard::content-type" in line and ":" in line:
                        mime = line.split(":", 1)[1].strip()
                        break
        except Exception:
            pass

if not mime:
    import mimetypes
    mimetypes.init()
    guess, _ = mimetypes.guess_type(str(p))
    mime = guess or "application/octet-stream"


def read_text(path: Path) -> str:
    try:
        return path.read_text(errors="replace")
    except OSError:
        return ""


def comment_for(m: str) -> str:
    if m.startswith("x-scheme-handler/"):
        return m.split("/", 1)[1] + " links"
    if "/" not in m:
        return m
    media, rest = m.split("/", 1)
    for base in MIME_DIRS:
        path = base / media / f"{rest}.xml"
        if not path.is_file():
            continue
        text = read_text(path)
        bare = re.search(r"<comment>([^<]+)</comment>", text, re.IGNORECASE)
        if bare:
            return bare.group(1).strip()
    return m


def app_name(desk_id: str) -> str:
    if not desk_id:
        return ""
    for d in APP_DIRS:
        path = d / desk_id
        if not path.is_file():
            continue
        text = read_text(path)
        in_entry = False
        for line in text.splitlines():
            s = line.strip()
            if s.startswith("["):
                in_entry = s == "[Desktop Entry]"
                continue
            if in_entry and s.startswith("Name=") and "Name[" not in s.split("=")[0]:
                return s.split("=", 1)[1].strip()
    return desk_id.replace(".desktop", "")


default_id = ""
xdg = shutil.which("xdg-mime")
if xdg and mime:
    try:
        r = subprocess.run(
            [xdg, "query", "default", mime],
            capture_output=True, text=True, timeout=5,
        )
        if r.returncode == 0:
            default_id = (r.stdout or "").strip()
    except Exception:
        pass

default_name = app_name(default_id) if default_id else ""

print(json.dumps({
    "path": str(p),
    "exists": True,
    "mime": mime,
    "comment": comment_for(mime),
    "defaultId": default_id,
    "defaultName": default_name,
}, ensure_ascii=False))
PY
