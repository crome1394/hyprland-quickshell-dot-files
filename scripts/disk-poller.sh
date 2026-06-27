#!/usr/bin/env bash
# Async slow disk collector (top directories). Runs separately from sysmon-poller.sh
# so the main UI poll never blocks on du. Outputs one JSON line + writes cache file.
#
# Cache: /tmp/sysmon-disk-cache.json

set -uo pipefail

# shellcheck source=lib/poll-common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/poll-common.sh"

CACHE_FILE="/tmp/sysmon-disk-cache.json"
TMP_CACHE="${CACHE_FILE}.tmp.$$"
NOW=$(date +%s%3N)
DU_TIMEOUT=4

out="[]"
declare -A seen

add_mount() {
    local m="$1"
    [[ -z "$m" || -n "${seen[$m]:-}" ]] && return
    seen["$m"]=1

    local dirs
    dirs=$(
        run_timeout "$DU_TIMEOUT" du -x --max-depth=1 -BM "$m" 2>/dev/null \
            | sort -rn \
            | awk -v root="$m" '
                NR > 9 { exit }
                {
                    path = $2
                    if (path == root) next
                    gsub(/M$/, "", $1)
                    printf "%s\t%s\n", path, $1
                }
            ' \
            | awk 'NR <= 6'
    )
    [[ -z "$dirs" ]] && return

    local entry
    entry=$(echo "$dirs" | jq -R -s --arg mount "$m" '
        split("\n")[:-1]
        | map(split("\t"))
        | map(select(length == 2) | { path: .[0], size_mb: (.[1] | tonumber) })
        | { mount: $mount, dirs: . }
    ' 2>/dev/null || echo "")
    [[ -z "$entry" || "$entry" == "null" ]] && return
    out=$(jq -n --argjson a "$out" --argjson e "$entry" '$a + [$e]')
}

for m in / /home; do
    mountpoint -q "$m" 2>/dev/null && add_mount "$m"
done

while IFS= read -r m; do
    add_mount "$m"
done < <(run_timeout 2 df -PT 2>/dev/null | awk 'NR > 1 { print $7 }' | awk '$1 ~ /^\/run\/media\// { print $1 }' | sort -u)

pending=false
[[ "$out" == "[]" ]] && pending=true

jq -cn \
    --argjson ts "$NOW" \
    --argjson top_dirs "$out" \
    --argjson pending "$([[ "$pending" == true ]] && echo true || echo false)" \
    '{
        timestamp: $ts,
        top_dirs: $top_dirs,
        pending: $pending
    }' > "$TMP_CACHE" 2>/dev/null || echo '{"timestamp":0,"top_dirs":[],"pending":true}' > "$TMP_CACHE"

mv -f "$TMP_CACHE" "$CACHE_FILE" 2>/dev/null || cp -f "$TMP_CACHE" "$CACHE_FILE" 2>/dev/null || true
rm -f "$TMP_CACHE" 2>/dev/null || true
cat "$CACHE_FILE"