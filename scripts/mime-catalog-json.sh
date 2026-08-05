#!/usr/bin/env bash
# mime-catalog-json.sh — list MIME types + defaults + handlers as JSON
# Usage: mime-catalog-json.sh
# Prints: { "types": [ { id, comment, globs, defaultId, defaultName, handlers, isScheme, handlerCount }, ... ] }
set -euo pipefail

python3 - <<'PY'
import json
import os
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
    """Return (defaults: mime->desktop, added: mime->[desktop,...]). First file wins for defaults."""
    defaults = {}
    added = {}
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
                # Defaults also count as associations for the handlers list
                lst = added.setdefault(mime, [])
                for a in apps:
                    if a not in lst:
                        lst.append(a)
            elif section == "Added Associations":
                lst = added.setdefault(mime, [])
                for a in apps:
                    if a not in lst:
                        lst.append(a)
    return defaults, added


def parse_desktop_apps() -> dict:
    """desktop-id -> { id, name, mimes[] }. First path wins per id.
    Includes apps with no MimeType= (needed for names when only in mimeapps.list).
    """
    apps = {}
    for d in APP_DIRS:
        if not d.is_dir():
            continue
        try:
            paths = sorted(d.glob("*.desktop"))
        except OSError:
            continue
        for path in paths:
            desk_id = path.name
            if desk_id in apps:
                continue
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
            apps[desk_id] = {
                "id": desk_id,
                "name": name,
                "mimes": mimes,
            }
    return apps


def build_handlers_map(apps: dict, added: dict) -> dict:
    """mime -> [desktop-id, ...] from desktop MimeType= plus mimeapps associations."""
    by_mime = {}
    for desk_id, app in apps.items():
        for mime in app["mimes"]:
            by_mime.setdefault(mime, []).append(desk_id)
    for mime, ids in added.items():
        lst = by_mime.setdefault(mime, [])
        for desk_id in ids:
            if desk_id not in lst:
                lst.append(desk_id)
    for mime, ids in by_mime.items():
        ids.sort(key=lambda i: (
            (apps[i]["name"] if i in apps else i).lower(),
            i.lower(),
        ))
    return by_mime


def parse_globs() -> dict:
    """mime -> [glob patterns] from globs2 / globs (user first, then system)."""
    result = {}
    # globs2: weight:mime:pattern
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
                if not mime or not pattern:
                    continue
                lst = result.setdefault(mime, [])
                if pattern not in lst:
                    lst.append(pattern)
    return result


def parse_types_list() -> set:
    types = set()
    for base in MIME_DIRS:
        path = base / "types"
        if not path.is_file():
            continue
        for line in read_text(path).splitlines():
            t = line.strip()
            if t and not t.startswith("#"):
                types.add(t)
    return types


def parse_aliases() -> dict:
    """alias -> canonical"""
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
    return aliases


_comment_re = re.compile(
    r'<comment(?:\s[^>]*)?>([^<]+)</comment>',
    re.IGNORECASE,
)


def resolve_canonical(mime: str, aliases: dict, depth: int = 0) -> str:
    """Follow alias chain to a type that has an XML description when possible."""
    if depth > 4 or mime not in aliases:
        return mime
    return resolve_canonical(aliases[mime], aliases, depth + 1)


def comment_from_xml(mime: str) -> str:
    if "/" not in mime:
        return ""
    media, rest = mime.split("/", 1)
    for base in MIME_DIRS:
        path = base / media / f"{rest}.xml"
        if not path.is_file():
            continue
        text = read_text(path)
        bare = re.search(
            r"<comment>([^<]+)</comment>",
            text,
            re.IGNORECASE,
        )
        if bare:
            return bare.group(1).strip()
        m = _comment_re.search(text)
        if m:
            return m.group(1).strip()
    return ""


def comment_for(mime: str, aliases: dict) -> str:
    """Read English-ish comment from shared-mime XML; fall back to friendly id."""
    c = comment_from_xml(mime)
    if c:
        return c
    canon = resolve_canonical(mime, aliases)
    if canon != mime:
        c = comment_from_xml(canon)
        if c:
            return c
    return friendly_scheme_or_id(mime)


def friendly_scheme_or_id(mime: str) -> str:
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
            "tg": "Telegram links",
            "terminal": "Terminal links",
        }
        return known.get(scheme, f"{scheme} links")
    return mime


def main():
    defaults, added = parse_mimeapps()
    apps = parse_desktop_apps()
    handlers_map = build_handlers_map(apps, added)
    globs = parse_globs()
    aliases = parse_aliases()

    types = parse_types_list()
    # Include everything that has a default, handlers, or globs (covers schemes not in types)
    types.update(defaults.keys())
    types.update(handlers_map.keys())
    types.update(added.keys())
    types.update(globs.keys())
    # Resolve aliases into catalog as separate rows only if something references them;
    # also ensure canonical targets exist.
    types.update(aliases.keys())
    types.update(aliases.values())

    # Drop empty / invalid
    types = {t for t in types if t and "/" in t}

    out = []
    for mime in sorted(types, key=lambda s: s.lower()):
        is_scheme = mime.startswith("x-scheme-handler/")
        handler_ids = handlers_map.get(mime, [])
        explicit_id = defaults.get(mime, "")
        # Effective default: explicit mimeapps entry, else first supporting app
        # (matches typical xdg-mime query default fallback).
        default_id = explicit_id
        default_is_explicit = bool(explicit_id)
        if not default_id and handler_ids:
            default_id = handler_ids[0]
            default_is_explicit = False

        # If default not in handlers, still show it first
        ordered = []
        seen = set()
        if default_id:
            ordered.append(default_id)
            seen.add(default_id)
        for hid in handler_ids:
            if hid not in seen:
                ordered.append(hid)
                seen.add(hid)

        handlers = []
        for hid in ordered:
            app = apps.get(hid)
            name = app["name"] if app else hid.replace(".desktop", "")
            handlers.append({
                "id": hid,
                "name": name,
                "isDefault": bool(default_id) and hid == default_id,
            })

        default_name = ""
        if default_id:
            if default_id in apps:
                default_name = apps[default_id]["name"]
            else:
                default_name = default_id.replace(".desktop", "")

        g = list(globs.get(mime, []))
        canon = resolve_canonical(mime, aliases)
        if canon != mime:
            for pat in globs.get(canon, []):
                if pat not in g:
                    g.append(pat)
        # Prefer short extension-like globs first for display
        g_sorted = sorted(g, key=lambda p: (0 if p.startswith("*.") else 1, len(p), p.lower()))

        out.append({
            "id": mime,
            "comment": comment_for(mime, aliases),
            "globs": g_sorted[:12],
            "defaultId": default_id,
            "defaultName": default_name,
            "defaultIsExplicit": default_is_explicit,
            "handlers": handlers,
            "handlerCount": len(handlers),
            "isScheme": is_scheme,
        })

    # Sort: explicit user/system defaults first, then any effective default, files before links
    out.sort(key=lambda t: (
        0 if t.get("defaultIsExplicit") else 1,
        0 if t["defaultId"] else 1,
        0 if not t["isScheme"] else 1,
        (t["comment"] or t["id"]).lower(),
        t["id"].lower(),
    ))

    print(json.dumps({"types": out}, ensure_ascii=False))


if __name__ == "__main__":
    main()
PY
