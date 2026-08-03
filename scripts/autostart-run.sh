#!/usr/bin/env bash
# autostart-run.sh — run one enabled entry now, or all enabled entries (login helper)
# Usage:
#   autostart-run.sh                 # run all enabled
#   autostart-run.sh Flameshot.desktop
set -euo pipefail

DIR="${XDG_CONFIG_HOME:-$HOME/.config}/autostart"
ONLY="${1:-}"

python3 - "$DIR" "$ONLY" <<'PY'
import os, re, subprocess, sys, time
from pathlib import Path

root = Path(sys.argv[1]).expanduser()
only = sys.argv[2].strip() if len(sys.argv) > 2 else ""

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

def is_enabled(data: dict) -> bool:
    if data.get("Type", "Application") not in ("Application", ""):
        return False
    if data.get("Hidden", "").lower() in ("true", "1"):
        return False
    if data.get("X-GNOME-Autostart-enabled", "true").lower() in ("false", "0", "no"):
        return False
    # OnlyShowIn / NotShowIn — be lenient on Hyprland/wlroots
    return True

def launch(data: dict, path: Path):
    delay = data.get("X-GNOME-Autostart-Delay") or "0"
    try:
        d = int(delay)
    except ValueError:
        d = 0
    if d > 0:
        time.sleep(min(d, 120))

    # Prefer gtk-launch by desktop basename when available
    name = path.name
    if name.endswith(".desktop"):
        try:
            subprocess.Popen(
                ["gtk-launch", name[:-8]],
                start_new_session=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            return True
        except Exception:
            pass

    exec_line = data.get("Exec") or ""
    exec_clean = re.sub(r"\s+%[a-zA-Z@]", "", exec_line).strip()
    if not exec_clean:
        return False
    # Shell form for complex Exec
    try:
        subprocess.Popen(
            exec_clean,
            shell=True,
            start_new_session=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            cwd=str(Path.home()),
        )
        return True
    except Exception:
        return False

if not root.is_dir():
    print("ok 0")
    sys.exit(0)

files = []
if only:
    only = Path(only).name
    if not only.endswith(".desktop"):
        only += ".desktop"
    p = root / only
    if p.is_file():
        files = [p]
else:
    files = sorted(root.glob("*.desktop"))

n = 0
for p in files:
    data = parse(p)
    if only:
        # run even if disabled when explicitly requested
        if launch(data, p):
            n += 1
    else:
        if is_enabled(data) and launch(data, p):
            n += 1

print(f"ok {n}")
PY
