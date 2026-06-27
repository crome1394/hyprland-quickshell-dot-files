# Shared helpers for quickshell pollers (source, do not execute).
run_timeout() {
    local secs="$1"
    shift
    if command -v timeout >/dev/null 2>&1; then
        timeout --kill-after=1 "$secs" "$@" 2>/dev/null
    else
        "$@" 2>/dev/null
    fi
}

# With pipefail, "cmd | head -N | jq" makes jq exit 141 (SIGPIPE) and "|| echo '[]'"
# can append junk. Always return a valid JSON array string.
ensure_json_array() {
    local raw="${1:-}"
    if [[ -z "$raw" ]]; then
        echo '[]'
        return
    fi
    if jq -e 'type == "array"' <<<"$raw" >/dev/null 2>&1; then
        jq -c '.' <<<"$raw"
    else
        echo '[]'
    fi
}