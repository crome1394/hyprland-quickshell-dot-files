#!/usr/bin/env bash
# mime-apps-json.sh — applications that claim MIME types + which they own as default
# Usage: mime-apps-json.sh
# Prints: { "apps": [ { id, name, mimes: [ { id, comment, isDefault, globs } ] }, ... ] }
set -euo pipefail

python3 - <<'PY'
import json
import re
from pathlib import Path

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

MIMEAPPS_CANDIDATES = [
    HOME / ".config/mimeapps.list",
    HOME / ".local/share/applications/mimeapps.list",
    Path("/etc/xdg/mimeapps.list"),
    Path("/usr/share/applications/mimeapps.list"),
]


def read_text(path: Path) -> str:
    try:
        return path.read_text(errors="replace")
    except OSError:
        return ""


def parse_mimeapps() -> tuple:
    """defaults: mime->desktop; added_by_app: desktop -> set(mimes) from mimeapps.list."""
    defaults = {}
    added_by_app = {}
    for path in MIMEAPPS_CANDIDATES:
        if not path.is_file():
            continue
        section = None
        for raw in read_text(path).splitlines():
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("[") and line.endswith("]"):
                section = line[1:-1].strip()
                continue
            if "=" not in line:
                continue
            key, val = line.split("=", 1)
            mime = key.strip()
            apps = [a.strip() for a in val.split(";") if a.strip()]
            if not mime or not apps:
                continue
            if section == "Default Applications":
                if mime not in defaults:
                    defaults[mime] = apps[0]
                for a in apps:
                    added_by_app.setdefault(a, set()).add(mime)
            elif section == "Added Associations":
                for a in apps:
                    added_by_app.setdefault(a, set()).add(mime)
    return defaults, added_by_app


def parse_globs() -> dict:
    result = {}
    for base in MIME_DIRS:
        for name in ("globs2", "globs"):
            path = base / name
            if not path.is_file():
                continue
            for line in read_text(path).splitlines():
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if name == "globs2":
                    parts = line.split(":", 2)
                    if len(parts) < 3:
                        continue
                    mime, pattern = parts[1], parts[2]
                else:
                    parts = line.split(":", 1)
                    if len(parts) < 2:
                        continue
                    mime, pattern = parts[0], parts[1]
                lst = result.setdefault(mime, [])
                if pattern not in lst:
                    lst.append(pattern)
    return result


_comment_cache = {}
_aliases = None


def load_aliases() -> dict:
    global _aliases
    if _aliases is not None:
        return _aliases
    aliases = {}
    for base in MIME_DIRS:
        path = base / "aliases"
        if not path.is_file():
            continue
        for line in read_text(path).splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split()
            if len(parts) >= 2:
                aliases[parts[0]] = parts[1]
    _aliases = aliases
    return aliases


def comment_for(mime: str) -> str:
    if mime in _comment_cache:
        return _comment_cache[mime]
    if mime.startswith("x-scheme-handler/"):
        scheme = mime.split("/", 1)[1]
        known = {
            "http": "Web links (http)",
            "https": "Web links (https)",
            "mailto": "Email links (mailto)",
            "about": "About links",
            "unknown": "Unknown links",
            "steam": "Steam links",
            "discord": "Discord links",
        }
        c = known.get(scheme, f"{scheme} links")
        _comment_cache[mime] = c
        return c

    def from_xml(m: str) -> str:
        if "/" not in m:
            return ""
        media, rest = m.split("/", 1)
        for base in MIME_DIRS:
            path = base / media / f"{rest}.xml"
            if not path.is_file():
                continue
            text = read_text(path)
            bare = re.search(r"<comment>([^<]+)</comment>", text, re.IGNORECASE)
            if bare:
                return bare.group(1).strip()
            hit = re.search(r"<comment(?:\s[^>]*)?>([^<]+)</comment>", text, re.IGNORECASE)
            if hit:
                return hit.group(1).strip()
        return ""

    c = from_xml(mime)
    if not c:
        aliases = load_aliases()
        cur = mime
        for _ in range(4):
            if cur not in aliases:
                break
            cur = aliases[cur]
            c = from_xml(cur)
            if c:
                break
    if not c:
        c = mime
    _comment_cache[mime] = c
    return c


def parse_desktop_apps():
    """All applications (even without MimeType=) so user associations still appear."""
    apps = []
    seen = set()
    for d in APP_DIRS:
        if not d.is_dir():
            continue
        try:
            paths = sorted(d.glob("*.desktop"))
        except OSError:
            continue
        for path in paths:
            desk_id = path.name
            if desk_id in seen:
                continue
            seen.add(desk_id)
            text = read_text(path)
            if "[Desktop Entry]" not in text:
                continue
            data = {}
            in_entry = False
            for line in text.splitlines():
                s = line.strip()
                if s.startswith("["):
                    in_entry = s == "[Desktop Entry]"
                    continue
                if not in_entry or not s or s.startswith("#") or "=" not in s:
                    continue
                k, v = s.split("=", 1)
                data.setdefault(k.strip(), v.strip())
            if data.get("Type", "Application") not in ("Application", ""):
                continue
            if data.get("Hidden", "").lower() in ("true", "1"):
                continue
            mime_raw = data.get("MimeType") or ""
            mimes = [m.strip() for m in mime_raw.split(";") if m.strip()]
            name = data.get("Name") or path.stem
            apps.append({
                "id": desk_id,
                "name": name,
                "mimes": mimes,
            })
    return apps


def main():
    defaults, added_by_app = parse_mimeapps()
    globs = parse_globs()
    raw_apps = parse_desktop_apps()

    out = []
    for app in raw_apps:
        mime_set = list(app["mimes"])
        for m in sorted(added_by_app.get(app["id"], set())):
            if m not in mime_set:
                mime_set.append(m)
        if not mime_set:
            continue
        mime_rows = []
        owned = 0
        for mime in mime_set:
            is_def = defaults.get(mime) == app["id"]
            if is_def:
                owned += 1
            g = globs.get(mime, [])
            g_sorted = sorted(g, key=lambda p: (0 if p.startswith("*.") else 1, len(p), p.lower()))
            advertised = mime in app["mimes"]
            mime_rows.append({
                "id": mime,
                "comment": comment_for(mime),
                "isDefault": is_def,
                "globs": g_sorted[:8],
                "isScheme": mime.startswith("x-scheme-handler/"),
                "userAdded": (not advertised) and (mime in added_by_app.get(app["id"], set())),
            })
        mime_rows.sort(key=lambda r: (
            0 if r["isDefault"] else 1,
            (r["comment"] or r["id"]).lower(),
        ))
        out.append({
            "id": app["id"],
            "name": app["name"],
            "mimes": mime_rows,
            "mimeCount": len(mime_rows),
            "ownedCount": owned,
        })

    out.sort(key=lambda a: (
        0 if a["ownedCount"] else 1,
        a["name"].lower(),
        a["id"].lower(),
    ))
    print(json.dumps({"apps": out}, ensure_ascii=False))


if __name__ == "__main__":
    main()
PY
