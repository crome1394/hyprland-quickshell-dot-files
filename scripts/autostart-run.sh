#!/usr/bin/env bash
# autostart-run.sh — run one enabled entry now, or all enabled entries (login helper)
# Usage:
#   autostart-run.sh                 # run all enabled
#   autostart-run.sh Flameshot.desktop
#
# Always uses the entry's Exec= line (field codes stripped). Do not use
# gtk-launch here: DBusActivatable apps (e.g. Telegram) can exit 0 without
# starting when activated that way during login.
set -euo pipefail

DIR="${XDG_CONFIG_HOME:-$HOME/.config}/autostart"
ONLY="${1:-}"
LOG_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell"
LOG_FILE="$LOG_DIR/autostart-run.log"
mkdir -p "$LOG_DIR"

python3 - "$DIR" "$ONLY" "$LOG_FILE" <<'PY'
import os, re, subprocess, sys, time
from datetime import datetime
from pathlib import Path

root = Path(sys.argv[1]).expanduser()
only = sys.argv[2].strip() if len(sys.argv) > 2 else ""
log_file = Path(sys.argv[3]) if len(sys.argv) > 3 else None


def log(msg: str):
    if not log_file:
        return
    try:
        ts = datetime.now().strftime("%Y-%m-%dT%H:%M:%S")
        with log_file.open("a") as f:
            f.write(f"{ts} {msg}\n")
    except OSError:
        pass


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


def launch(data: dict, path: Path) -> bool:
    delay = data.get("X-GNOME-Autostart-Delay") or "0"
    try:
        d = int(delay)
    except ValueError:
        d = 0
    if d > 0:
        time.sleep(min(d, 120))

    exec_line = data.get("Exec") or ""
    # Strip FreeDesktop field codes (%u %U %f %F %i %c %k etc.)
    exec_clean = re.sub(r"\s+%[a-zA-Z@]", "", exec_line).strip()
    # Trailing " --" left after stripping %U is fine for most apps
    if not exec_clean:
        log(f"FAIL {path.name}: empty Exec")
        return False

    try:
        subprocess.Popen(
            exec_clean,
            shell=True,
            start_new_session=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            cwd=str(Path.home()),
            env=os.environ.copy(),
        )
        log(f"OK  {path.name}: {exec_clean}")
        return True
    except Exception as e:
        log(f"FAIL {path.name}: {exec_clean} ({e})")
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
        log(f"FAIL {only}: not found")
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
