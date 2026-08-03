#!/usr/bin/env bash
# keybinds-set.sh — surgically update key chord and/or --#Category# description
# on one line of keybindings.lua. Does not touch the dispatcher expression.
#
# Usage:
#   keybinds-set.sh <line> [--key "SUPER + T"] [--category Apps] [--description "text"] [--file path]
#   keybinds-set.sh reload   # hyprctl reload only
set -euo pipefail

DEFAULT_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/config/keybindings.lua"

if [[ "${1:-}" == "reload" ]]; then
    hyprctl reload >/dev/null
    echo '{"ok":true,"reloaded":true}'
    exit 0
fi

if [[ $# -lt 1 ]]; then
    echo "usage: keybinds-set.sh <line> [--key CHORD] [--category CAT] [--description DESC] [--file PATH]" >&2
    exit 2
fi

LINE_NO="$1"
shift

FILE="$DEFAULT_FILE"
NEW_KEY=""
NEW_CAT=""
NEW_DESC=""
HAVE_KEY=0
HAVE_CAT=0
HAVE_DESC=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --key)
            NEW_KEY="${2:-}"
            HAVE_KEY=1
            shift 2
            ;;
        --category)
            NEW_CAT="${2:-}"
            HAVE_CAT=1
            shift 2
            ;;
        --description)
            NEW_DESC="${2:-}"
            HAVE_DESC=1
            shift 2
            ;;
        --file)
            FILE="${2:-}"
            shift 2
            ;;
        *)
            echo "unknown arg: $1" >&2
            exit 2
            ;;
    esac
done

if [[ "$HAVE_KEY" -eq 0 && "$HAVE_CAT" -eq 0 && "$HAVE_DESC" -eq 0 ]]; then
    echo "nothing to change (pass --key and/or --category and/or --description)" >&2
    exit 2
fi

export KB_FILE="$FILE"
export KB_LINE="$LINE_NO"
export KB_HAVE_KEY="$HAVE_KEY"
export KB_HAVE_CAT="$HAVE_CAT"
export KB_HAVE_DESC="$HAVE_DESC"
export KB_NEW_KEY="$NEW_KEY"
export KB_NEW_CAT="$NEW_CAT"
export KB_NEW_DESC="$NEW_DESC"

python3 <<'PY'
import json, os, re, shutil, sys, time
from pathlib import Path

path = Path(os.environ["KB_FILE"]).expanduser()
line_no = int(os.environ["KB_LINE"])
have_key = os.environ.get("KB_HAVE_KEY") == "1"
have_cat = os.environ.get("KB_HAVE_CAT") == "1"
have_desc = os.environ.get("KB_HAVE_DESC") == "1"
new_key = os.environ.get("KB_NEW_KEY", "")
new_cat = os.environ.get("KB_NEW_CAT", "")
new_desc = os.environ.get("KB_NEW_DESC", "")

def fail(msg, code=1):
    print(json.dumps({"ok": False, "error": msg}), file=sys.stderr)
    sys.exit(code)

if not path.is_file():
    fail(f"file not found: {path}")

text = path.read_text(encoding="utf-8", errors="replace")
lines = text.splitlines(keepends=True)
if line_no < 1 or line_no > len(lines):
    fail(f"line out of range: {line_no}")

# Work with line without newline for editing; preserve ending
raw = lines[line_no - 1]
ending = ""
if raw.endswith("\r\n"):
    ending = "\r\n"
    body = raw[:-2]
elif raw.endswith("\n"):
    ending = "\n"
    body = raw[:-1]
else:
    body = raw

if "hl.bind(" not in body:
    fail("line does not contain hl.bind(")
if body.lstrip().startswith("--"):
    fail("line is commented out")

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

bind_idx = body.find("hl.bind(")
after_start = bind_idx + 8
after = body[after_start:]
key_end = find_key_end(after)
if key_end < 0:
    fail("could not parse key expression")

key_raw = after[:key_end]
rest_after_key = after[key_end:]  # starts with comma

def is_editable_key(raw: str) -> bool:
    raw = raw.strip()
    if (raw.startswith('"') and raw.endswith('"')) or (raw.startswith("'") and raw.endswith("'")):
        return True
    parts = [p.strip() for p in raw.split("..")]
    for p in parts:
        if not p or p == "mainMod":
            continue
        if (p.startswith('"') and p.endswith('"')) or (p.startswith("'") and p.endswith("'")):
            continue
        if re.fullmatch(r"[a-zA-Z_][a-zA-Z0-9_]*", p):
            return False
    return True

if have_key and not is_editable_key(key_raw):
    fail("key expression is not safely editable (dynamic/loop bind)")

def chord_to_lua(chord: str) -> str:
    """Convert display chord to a Lua key expression matching file style."""
    c = chord.strip()
    c = re.sub(r"\s*\+\s*", " + ", c)
    c = re.sub(r"\s+", " ", c).strip()
    if not c:
        fail("empty key chord")
    # Reject characters that would break Lua strings
    if '"' in c or "'" in c or "\n" in c:
        fail("key chord contains invalid characters")
    upper = c.upper()
    # SUPER / mainMod prefix → mainMod .. " + rest"
    m = re.match(r"^(SUPER|SUPER_L|SUPER_R)\s*\+\s*(.+)$", c, re.IGNORECASE)
    if m:
        rest = m.group(2).strip()
        return f'mainMod .. " + {rest}"'
    if re.fullmatch(r"SUPER|SUPER_L|SUPER_R", c, re.IGNORECASE):
        return "mainMod"
    # Otherwise single quoted string (preserve user casing for XF86 etc.)
    return f'"{c}"'

def replace_annotation(line, category, description):
    """Replace or insert --#Category# desc / --# desc at end of line."""
    # Strip existing --# annotation
    base = re.sub(r"\s*--#.*$", "", line).rstrip()
    # Current values if not provided
    cur_cat = ""
    cur_desc = ""
    cat_m = re.search(r"--#([^#\n]+)#\s*(.*)$", line)
    if cat_m:
        cur_cat = cat_m.group(1).strip()
        cur_desc = (cat_m.group(2) or "").strip()
    else:
        desc_m = re.search(r"--#\s*(.+)$", line)
        if desc_m:
            cur_desc = desc_m.group(1).strip()

    if category is None:
        category = cur_cat
    if description is None:
        description = cur_desc

    # Sanitize: no newlines; # in category breaks convention
    category = (category or "").replace("\n", " ").replace("#", "").strip()
    description = (description or "").replace("\n", " ").strip()

    if category:
        ann = f"--#{category}# {description}".rstrip()
    else:
        ann = f"--# {description}".rstrip() if description else "--#"
    return f"{base} {ann}"

new_body = body

if have_key:
    lua_key = chord_to_lua(new_key)
    # Preserve spacing style: original key_raw may have spaces
    new_after = lua_key + rest_after_key
    new_body = body[:after_start] + new_after

if have_cat or have_desc:
    cat_arg = new_cat if have_cat else None
    desc_arg = new_desc if have_desc else None
    new_body = replace_annotation(new_body, cat_arg, desc_arg)
elif have_key:
    # keep existing annotation as-is (already in new_body via rest)
    pass

if "hl.bind(" not in new_body:
    fail("internal error: bind lost after edit")

# Collision check on display keys among active annotated binds
def normalize_key(key_expr):
    k = key_expr.strip()
    m = re.match(r'^mainMod\s*\.\.\s*["\']\s*(\+\s*)?(.+?)["\']\s*$', k)
    if m:
        rest = m.group(2).strip().lstrip("+").strip()
        return ("SUPER + " + rest) if rest else "SUPER"
    if "mainMod" in k and ".." in k:
        k = re.sub(r'mainMod\s*\.\.\s*', "", k)
        k = k.replace('"', "").replace("'", "")
        k = re.sub(r"\s*\.\.\s*", " + ", k)
        k = re.sub(r"\s*\+\s*", " + ", k)
        k = re.sub(r"(?:\s*\+\s*)+", " + ", k)
        k = re.sub(r"\s+", " ", k).strip(" +")
        return ("SUPER + " + k) if k else "SUPER"
    k = k.replace('"', "").replace("'", "")
    k = re.sub(r"\s*\+\s*", " + ", k)
    k = re.sub(r"\s+", " ", k).strip()
    return k

if have_key:
    a = new_body[new_body.find("hl.bind(") + 8 :]
    ke = find_key_end(a)
    new_display = normalize_key(a[:ke])
    for idx, ln in enumerate(lines, start=1):
        if idx == line_no:
            continue
        s = ln.strip()
        if "hl.bind(" not in s or s.startswith("--"):
            continue
        if "--#" not in ln:
            continue
        bi = s.find("hl.bind(")
        af = s[bi + 8 :]
        ke2 = find_key_end(af)
        if ke2 < 0:
            continue
        other = normalize_key(af[:ke2])
        if other.lower() == new_display.lower():
            fail(f"key chord collides with line {idx}: {other}")

# Backup then atomic write
ts = time.strftime("%Y%m%d-%H%M%S")
backup = path.with_name(path.name + f".bak.{ts}")
shutil.copy2(path, backup)

lines[line_no - 1] = new_body + ending
tmp = path.with_suffix(path.suffix + f".tmp.{os.getpid()}")
tmp.write_text("".join(lines), encoding="utf-8")
tmp.replace(path)

print(json.dumps({
    "ok": True,
    "path": str(path),
    "line": line_no,
    "backup": str(backup),
    "key": new_key if have_key else None,
    "category": new_cat if have_cat else None,
    "description": new_desc if have_desc else None,
}))
PY
