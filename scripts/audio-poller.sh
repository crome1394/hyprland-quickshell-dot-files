#!/usr/bin/env bash
# Query PulseAudio/PipeWire sinks and sources via pactl; emit one JSON object.
set -u pipefail

TS="$(date +%s)"

if ! command -v pactl >/dev/null 2>&1; then
    jq -n --argjson ts "$TS" '{timestamp: $ts, error: "pactl not found", sinks: [], sources: []}'
    exit 0
fi

default_sink="$(pactl get-default-sink 2>/dev/null || echo "")"
default_source="$(pactl get-default-source 2>/dev/null || echo "")"

# Parse pactl list sinks|sources blocks into JSON array via jq --slurpfile chunks.
parse_kind() {
    local kind="$1"       # Sink | Source
    local plural="$2"     # sinks | sources
    local default_name="$3"

    awk -v kind="$kind" -v default_name="$default_name" '
BEGIN {
    idx = ""
    delete port_name
    delete port_desc
    delete port_type
    delete port_avail
    port_n = 0
    in_ports = 0
}
$0 ~ "^" kind " #" {
    if (idx != "") print_record()
    idx = $2
    sub(/^#/, "", idx)
    name = ""
    desc = ""
    state = ""
    mute = "false"
    vol_pct = 0
    active_port = ""
    port_n = 0
    in_ports = 0
    next
}
/^[\t ]*Name: / {
    name = $2
    for (i = 3; i <= NF; i++) name = name " " $i
    next
}
/^[\t ]*Description: / {
    desc = substr($0, index($0, ":") + 2)
    sub(/^[ \t]+/, "", desc)
    desc = json_str(desc)
    next
}
/^[\t ]*State: / { state = $2; next }
/^[\t ]*Mute: / { mute = ($2 == "yes" ? "true" : "false"); next }
/^[\t ]*Volume:/ {
    if (match($0, /[[:space:]]([0-9]+)%/, m)) vol_pct = m[1] + 0
    next
}
/^[\t ]*Ports:/ { in_ports = 1; next }
in_ports && /^[\t ]*Active Port: / { active_port = $3; next }
in_ports && /^[\t ]*Formats:/ { in_ports = 0; next }
in_ports && /^[\t ]+[a-z][a-z0-9._-]*: / {
    line = $0
    n = index(line, ":")
    if (n == 0) next
    pname = substr(line, 1, n - 1)
    sub(/^[\t ]+/, "", pname)
    rest = substr(line, n + 2)
    pdesc = rest
    sub(/ \(type:.*/, "", pdesc)
    pdesc = json_str(pdesc)
    ptype = ""
    if (match(rest, /type: ([^,]+)/, tm)) {
        ptype = json_str(tm[1])
    }
    pavail = "unknown"
    if (rest ~ /not available/) pavail = "no"
    else if (rest ~ /available/) pavail = "yes"
    port_n++
    port_name[port_n] = pname
    port_desc[port_n] = pdesc
    port_type[port_n] = ptype
    port_avail[port_n] = pavail
    next
}
END { if (idx != "") print_record() }

function json_str(s) {
    gsub(/\\/, "\\\\", s)
    gsub(/"/, "\\\"", s)
    gsub(/\t/, "\\t", s)
    gsub(/\r/, "\\r", s)
    gsub(/\n/, "\\n", s)
    return s
}

function ports_json(   i, s) {
    s = "["
    for (i = 1; i <= port_n; i++) {
        if (i > 1) s = s ","
        act = (port_name[i] == active_port ? "true" : "false")
        s = s sprintf("{\"name\":\"%s\",\"description\":\"%s\",\"type\":\"%s\",\"available\":\"%s\",\"active\":%s}",
            port_name[i], port_desc[i], port_type[i], port_avail[i], act)
    }
    s = s "]"
    return s
}

function print_record(   gsub_tmp) {
    gsub_tmp = json_str(name)
    is_def = (name == default_name ? "true" : "false")
    printf "{\"index\":%s,\"name\":\"%s\",\"description\":\"%s\",\"state\":\"%s\",\"mute\":%s,\"volume_pct\":%d,\"active_port\":\"%s\",\"is_default\":%s,\"ports\":%s}\n",
        idx, gsub_tmp, desc, state, mute, vol_pct, active_port, is_def, ports_json()
}
' <<< "$(pactl list "$plural" 2>/dev/null || true)" | jq -s '.'
}

sinks_json="$(parse_kind Sink sinks "$default_sink")"
sources_json="$(parse_kind Source sources "$default_source" | jq '[.[] | select(.name | test("\\.monitor$") | not)]')"

# sink-inputs (playback) and source-outputs (recording) for active app streams.
parse_stream_blocks() {
    local header="$1"
    local device_field="$2"
    local device_key="$3"

    awk -v header="$header" -v device_field="$device_field" -v device_key="$device_key" '
BEGIN { idx = "" }
$0 ~ "^" header " #" {
    if (idx != "") print_record()
    idx = $3
    sub(/^#/, "", idx)
    app = ""
    binary = ""
    media = ""
    mute = "false"
    vol_pct = 0
    corked = "false"
    device_idx = ""
    next
}
/^[\t ]*application.name = / {
    app = substr($0, index($0, "=") + 2)
    sub(/^[ \t]+/, "", app)
    app = json_str(app)
    next
}
/^[\t ]*application.process.binary = / {
    binary = substr($0, index($0, "=") + 2)
    sub(/^[ \t]+/, "", binary)
    binary = json_str(binary)
    next
}
/^[\t ]*media.name = / {
    media = substr($0, index($0, "=") + 2)
    sub(/^[ \t]+/, "", media)
    media = json_str(media)
    next
}
/^[\t ]*Mute: / { mute = ($2 == "yes" ? "true" : "false"); next }
/^[\t ]*Volume:/ {
    if (match($0, /[[:space:]]([0-9]+)%/, m)) vol_pct = m[1] + 0
    next
}
/^[\t ]*Corked: / { corked = ($2 == "yes" ? "true" : "false"); next }
$0 ~ ("^[\t ]*" device_field ": ") {
    device_idx = $2
    next
}
END { if (idx != "") print_record() }

function strip_quotes(s) {
    sub(/^"/, "", s)
    sub(/"$/, "", s)
    return s
}

function json_str(s) {
    s = strip_quotes(s)
    gsub(/\\/, "\\\\", s)
    gsub(/"/, "\\\"", s)
    gsub(/\t/, "\\t", s)
    gsub(/\r/, "\\r", s)
    gsub(/\n/, "\\n", s)
    return s
}

function print_record() {
    if (app == "" && binary != "") app = binary
    if (app == "") app = "Unknown"
    if (binary == "") binary = app
    if (media == "") media = ""
    printf "{\"index\":%s,\"app\":\"%s\",\"binary\":\"%s\",\"media\":\"%s\",\"mute\":%s,\"volume_pct\":%d,\"corked\":%s,\"device_index\":\"%s\",\"device_key\":\"%s\"}\n",
        idx, app, binary, media, mute, vol_pct, corked, device_idx, device_key
}
' <<< "$(pactl list "$4" 2>/dev/null || true)" | jq -s '.'
}

playback_json="$(parse_stream_blocks "Sink Input" "Sink" "sink" "sink-inputs")"
recording_json="$(parse_stream_blocks "Source Output" "Source" "source" "source-outputs")"

# Resolve device_index -> device_name using sinks/sources index maps.
streams_json="$(jq -n \
    --argjson playback "$playback_json" \
    --argjson recording "$recording_json" \
    --argjson sinks "$sinks_json" \
    --argjson sources "$sources_json" '
    def idx_name($list):
        reduce $list[] as $d ({}; . + { ($d.index | tostring): ($d.description // $d.name) });
    def enrich($list; $map):
        [$list[] | . + {device_name: ($map[.device_index] // .device_index // "")}];
    (idx_name($sinks)) as $sink_map
    | (idx_name($sources)) as $source_map
    | {
        playback: enrich($playback; $sink_map),
        recording: enrich($recording; $source_map)
      }
')"

jq -n \
    --argjson ts "$TS" \
    --arg default_sink "$default_sink" \
    --arg default_source "$default_source" \
    --argjson sinks "$sinks_json" \
    --argjson sources "$sources_json" \
    --argjson streams "$streams_json" \
    '{
        timestamp: $ts,
        default_sink: $default_sink,
        default_source: $default_source,
        sinks: $sinks,
        sources: $sources,
        streams: $streams
    }'