#!/usr/bin/env bash
# desktop-apps-json.sh — list installed .desktop apps as JSON for Quick Launch picker
# Usage: desktop-apps-json.sh [query]
# Query is split on whitespace; every token must match (name/id/exec/keywords).
# Prints a JSON array: [{ id, name, exec, icon, command, tooltip }, ...]
set -euo pipefail

QUERY="${1:-}"

python3 - "$QUERY" <<'PY'
import json, os, sys, re
from pathlib import Path

query_raw = (sys.argv[1] if len(sys.argv) > 1 else "").strip().lower()
tokens = [t for t in re.split(r"\s+", query_raw) if t]

dirs = [
    Path.home() / ".local/share/applications",
    Path("/usr/share/applications"),
    Path("/usr/local/share/applications"),
    Path.home() / ".local/share/flatpak/exports/share/applications",
    Path("/var/lib/flatpak/exports/share/applications"),
]

icon_theme_roots = [
    Path.home() / ".local/share/icons",
    Path("/usr/share/icons"),
    Path("/usr/share/pixmaps"),
]

def parse_desktop(path: Path):
    try:
        text = path.read_text(errors="replace")
    except OSError:
        return None
    if "[Desktop Entry]" not in text:
        return None
    data = {}
    in_entry = False
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("["):
            in_entry = line == "[Desktop Entry]"
            continue
        if not in_entry or not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        # Keep first occurrence (locale-less Name= before Name[xx]= usually first)
        data.setdefault(k.strip(), v.strip())
    if data.get("Type", "Application") != "Application":
        return None
    if data.get("NoDisplay", "").lower() in ("true", "1"):
        return None
    if data.get("Hidden", "").lower() in ("true", "1"):
        return None
    # Skip pure settings/system entries that often clutter pickers (still allow Office)
    name = data.get("Name") or path.stem
    exec_line = data.get("Exec") or ""
    exec_clean = re.sub(r"\s+%[a-zA-Z@]", "", exec_line).strip()
    if not exec_clean:
        return None
    icon = data.get("Icon") or ""
    desktop_id = path.name
    keywords = data.get("Keywords") or ""
    generic = data.get("GenericName") or ""
    comment = data.get("Comment") or ""
    return {
        "id": desktop_id,
        "name": name,
        "exec": exec_clean,
        "iconName": icon,
        "keywords": keywords,
        "generic": generic,
        "comment": comment,
        "desktop": str(path),
    }

def resolve_icon(name: str) -> str:
    if not name:
        return ""
    p = Path(name)
    if p.is_file():
        return str(p)
    if name.startswith("/") and p.suffix:
        return name
    candidates = []
    for root in icon_theme_roots:
        if not root.is_dir():
            continue
        if root.name == "pixmaps":
            for ext in (".svg", ".png", ".xpm"):
                f = root / f"{name}{ext}"
                if f.is_file():
                    return str(f)
            continue
        for pattern in (
            f"**/apps/{name}.svg",
            f"**/apps/{name}.png",
            f"**/{name}.svg",
            f"**/{name}.png",
        ):
            for hit in root.glob(pattern):
                if hit.is_file():
                    candidates.append(hit)
                    break
            if candidates:
                break
        if candidates:
            break
    if not candidates:
        return ""
    candidates.sort(key=lambda x: (0 if x.suffix == ".svg" else 1, -len(str(x))))
    return str(candidates[0])

def matches(app: dict) -> bool:
    if not tokens:
        return True
    blob = " ".join([
        app.get("name") or "",
        app.get("id") or "",
        app.get("exec") or "",
        app.get("keywords") or "",
        app.get("generic") or "",
        app.get("comment") or "",
        app.get("iconName") or "",
    ]).lower()
    # Every whitespace-separated token must appear somewhere
    return all(t in blob for t in tokens)

def rank(app: dict) -> tuple:
    """Lower is better — prefer name prefix / name token hits."""
    name = (app.get("name") or "").lower()
    app_id = (app.get("id") or "").lower()
    if not tokens:
        return (1, name)
    # All tokens in name
    if all(t in name for t in tokens):
        if name.startswith(tokens[0]):
            return (0, name)
        return (1, name)
    if all(t in app_id for t in tokens):
        return (2, name)
    return (3, name)

seen = set()
apps = []
for d in dirs:
    if not d.is_dir():
        continue
    for path in sorted(d.glob("*.desktop")):
        key = path.name
        if key in seen:
            continue
        seen.add(key)
        app = parse_desktop(path)
        if not app or not matches(app):
            continue
        desk = app["id"]
        if desk.endswith(".desktop"):
            command = ["gtk-launch", desk[:-8]]
        else:
            command = ["sh", "-c", app["exec"]]
        apps.append({
            "id": app["id"],
            "name": app["name"],
            "exec": app["exec"],
            "icon": resolve_icon(app.get("iconName") or ""),
            "iconName": app.get("iconName") or "",
            "command": command,
            "tooltip": app["name"],
            "_rank": rank(app),
        })

apps.sort(key=lambda a: a["_rank"])
for a in apps:
    a.pop("_rank", None)

# Cap after ranking so best matches always surface
print(json.dumps(apps[:250], ensure_ascii=False))
PY
