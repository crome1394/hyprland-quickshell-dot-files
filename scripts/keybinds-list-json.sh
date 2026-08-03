#!/usr/bin/env bash
# keybinds-list-json.sh — parse Hyprland keybindings.lua for the control strip.
# Emits one JSON object: { "path", "binds": [ { line, key, keyRaw, category,
# description, editable, reason } ] }
set -euo pipefail

FILE="${1:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr/config/keybindings.lua}"

python3 - "$FILE" <<'PY'
import json, re, sys
from pathlib import Path

path = Path(sys.argv[1]).expanduser()
if not path.is_file():
    print(json.dumps({"path": str(path), "error": "file not found", "binds": []}))
    sys.exit(0)

text = path.read_text(encoding="utf-8", errors="replace")
lines = text.splitlines()

def find_key_end(after_open: str) -> int:
    depth = 0
    for j, ch in enumerate(after_open):
        if ch in "({[":
            depth += 1
        elif ch in ")}]":
            depth -= 1
        elif ch == "," and depth == 0:
            return j
    return -1

def normalize_key(key_expr: str) -> str:
    """Normalize Lua key expression to display chord (e.g. SUPER + T)."""
    k = key_expr.strip()
    # mainMod .. " + REST" or mainMod .. "REST"
    m = re.match(r'^mainMod\s*\.\.\s*["\']\s*(\+\s*)?(.+?)["\']\s*$', k)
    if m:
        rest = m.group(2).strip().lstrip("+").strip()
        return ("SUPER + " + rest) if rest else "SUPER"
    # mainMod .. " + " .. key  (loop / dynamic)
    if "mainMod" in k and ".." in k:
        k = re.sub(r'mainMod\s*\.\.\s*', "", k)
        k = k.replace('"', "").replace("'", "")
        k = re.sub(r"\s*\.\.\s*", " + ", k)
        k = re.sub(r"\s*\+\s*", " + ", k)
        k = re.sub(r"(?:\s*\+\s*)+", " + ", k)
        k = re.sub(r"\s+", " ", k).strip(" +")
        return ("SUPER + " + k) if k else "SUPER"
    # Pure quoted string
    k = k.replace('"', "").replace("'", "")
    k = re.sub(r"\s*\+\s*", " + ", k)
    k = re.sub(r"\s+", " ", k).strip()
    return k

def is_editable(key_raw: str) -> tuple[bool, str]:
    """Return (editable, reason). Loop / non-literal keys are read-only."""
    raw = key_raw.strip()
    # Concat with a bare identifier that is not mainMod (e.g. .. key)
    # Allow mainMod .. " + X" pattern only.
    if re.search(r"\.\.\s*[a-zA-Z_][a-zA-Z0-9_]*\s*$", raw) and "mainMod" not in raw.split("..")[-1]:
        return False, "dynamic key expression"
    if re.search(r"\.\.\s*[a-zA-Z_][a-zA-Z0-9_]*\s*\.\.", raw):
        return False, "dynamic key expression"
    # mainMod .. " + " .. key  or  mainMod .. " + " .. something
    parts = [p.strip() for p in raw.split("..")]
    for p in parts:
        if not p:
            continue
        if p == "mainMod":
            continue
        # string literal
        if (p.startswith('"') and p.endswith('"')) or (p.startswith("'") and p.endswith("'")):
            continue
        # bare identifier used in loop (key, i, etc.)
        if re.fullmatch(r"[a-zA-Z_][a-zA-Z0-9_]*", p):
            return False, "dynamic key expression"
        # allow nothing else complex
        if not ((p.startswith('"') or p.startswith("'"))):
            # might be mainMod only already handled
            if p != "mainMod":
                return False, "unsupported key expression"
    # Pure quoted string is always editable
    if (raw.startswith('"') and raw.endswith('"')) or (raw.startswith("'") and raw.endswith("'")):
        return True, ""
    # mainMod .. " + KEY" form
    if "mainMod" in raw:
        return True, ""
    # Fallback: if no bare vars, ok
    if re.search(r"[a-zA-Z_][a-zA-Z0-9_]*", raw.replace("mainMod", "")):
        # strip string contents and check remaining idents
        stripped = re.sub(r'"[^"]*"', "", raw)
        stripped = re.sub(r"'[^']*'", "", stripped)
        stripped = stripped.replace("mainMod", "").replace("..", "").replace("+", "")
        if re.search(r"[a-zA-Z_][a-zA-Z0-9_]*", stripped):
            return False, "dynamic key expression"
    return True, ""

binds = []
for i, original in enumerate(lines, start=1):
    line = original.strip()
    if "hl.bind(" not in line:
        continue
    if line.startswith("--hl.bind") or line.startswith("----hl.bind"):
        continue
    if "--#" not in original:
        continue

    bind_idx = line.find("hl.bind(")
    if bind_idx < 0:
        continue
    after = line[bind_idx + 8 :]
    key_end = find_key_end(after)
    if key_end < 0:
        continue
    key_raw = after[:key_end].strip()
    key_display = normalize_key(key_raw)

    category = ""
    description = ""
    cat_m = re.search(r"--#([^#\n]+)#\s*(.*)$", original)
    if cat_m:
        category = cat_m.group(1).strip()
        description = (cat_m.group(2) or "").strip()
    else:
        desc_m = re.search(r"--#\s*(.+)$", original)
        if desc_m:
            description = desc_m.group(1).strip()

    editable, reason = is_editable(key_raw)

    # Dispatcher preview (everything after key comma, before --#)
    rest = after[key_end + 1 :]
    rest = re.sub(r"\s*--#.*$", "", rest).strip()
    # strip trailing ) of hl.bind if simple
    preview = rest
    if len(preview) > 80:
        preview = preview[:77] + "..."

    binds.append({
        "line": i,
        "key": key_display,
        "keyRaw": key_raw,
        "category": category,
        "description": description,
        "editable": editable,
        "reason": reason,
        "preview": preview,
    })

print(json.dumps({"path": str(path), "binds": binds}, ensure_ascii=False))
PY
