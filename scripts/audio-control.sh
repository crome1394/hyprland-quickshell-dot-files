#!/usr/bin/env bash
# pactl audio control: defaults, ports, volume, mute, card profiles.
# Additive-only API: existing actions keep the same arguments and behaviour.
set -euo pipefail

ACTION="${1:-}"
TARGET="${2:-}"   # sink | source | card-name (for profile actions)
NAME="${3:-}"
ARG="${4:-}"      # port name, volume percent, or profile name
ARG2="${5:-}"     # optional second channel volume percent (set-channel-volume)

usage() {
    echo "usage: audio-control.sh <set-default|set-port|set-volume|set-channel-volume|toggle-mute> <sink|source> <name> [port|percent|L%] [R%]" >&2
    echo "       audio-control.sh list-card-profiles <card-name>" >&2
    echo "       audio-control.sh set-card-profile <card-name> <profile-name>" >&2
    echo "       audio-control.sh echo-cancel-status|echo-cancel-on|echo-cancel-off|echo-cancel-force-off|echo-cancel-apply" >&2
    echo "       audio-control.sh list-streams" >&2
    echo "       audio-control.sh restart-audio" >&2
    echo "       audio-control.sh bt-battery [mac|all]" >&2
}

# ---------------------------------------------------------------------------
# Echo cancellation (sticky preference + fully reversible runtime)
# ---------------------------------------------------------------------------
# Virtual devices created only while enabled:
#   qs_ec_source  — cleaned mic (apps that use the default source pick this up)
#   qs_ec_sink    — playback path used as AEC reference (default sink while on)
#
# Preference file (survives reboot; lives under config, not cache):
#   ~/.config/quickshell/echo-cancel.pref   →  {"preferred":true|false}
#
# Auto-start: systemd user unit quickshell-echo-cancel.service runs
# echo-cancel-apply after PipeWire/WirePlumber (and AudioPill also applies).
#
# Back-out levels (safest → nuclear):
#   1) UI / echo-cancel-off   — unload, restore hardware, preferred=false
#   2) echo-cancel-force-off  — same + preferred=false even if state is gone
#   3) systemctl --user disable --now quickshell-echo-cancel.service
#      + remove echo-cancel.pref if desired
#
# Meet / Telegram / Discord: follow PipeWire defaults (qs_ec_* when on).
# ---------------------------------------------------------------------------
EC_SOURCE_NAME="qs_ec_source"
EC_SINK_NAME="qs_ec_sink"
# Runtime state lives on tmpfs (RAM), never the HD:
#   XDG_RUNTIME_DIR is already a tmpfs (/run/user/$UID) on systemd systems.
# Stream polls do not write any files — only stdout over the process pipe.
EC_STATE_DIR="${XDG_RUNTIME_DIR:-/dev/shm}/quickshell-audio"
EC_STATE_FILE="${EC_STATE_DIR}/echo-cancel.state"
# Sticky preference is tiny and only rewritten on On/Off (not on stream poll).
EC_PREF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/quickshell"
EC_PREF_FILE="${EC_PREF_DIR}/echo-cancel.pref"

json_esc() {
    local s="${1:-}"
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    printf '%s' "$s"
}

ec_is_virtual() {
    local n="${1:-}"
    [[ "$n" == "$EC_SOURCE_NAME" || "$n" == "$EC_SINK_NAME" || "$n" == echo-cancel-* || "$n" == *echo-cancel* ]]
}

# Return first module id for module-echo-cancel, or empty.
ec_find_module_id() {
    pactl list modules short 2>/dev/null | awk '$2 == "module-echo-cancel" { print $1; exit }'
}

# True if our named virtual sink/source exist.
ec_nodes_present() {
    pactl list short sources 2>/dev/null | awk -v n="$EC_SOURCE_NAME" '$2 == n { found=1 } END { exit !found }' \
        && pactl list short sinks 2>/dev/null | awk -v n="$EC_SINK_NAME" '$2 == n { found=1 } END { exit !found }'
}

ec_read_state() {
    if [[ -f "$EC_STATE_FILE" ]]; then
        cat "$EC_STATE_FILE"
    else
        echo '{}'
    fi
}

ec_write_state() {
    mkdir -p "$EC_STATE_DIR"
    cat >"$EC_STATE_FILE"
}

ec_clear_state() {
    rm -f "$EC_STATE_FILE"
}

# Sticky preference. Note: jq's `//` treats JSON false as empty — do NOT use
# `.preferred // true` or Off will still look preferred.
ec_pref_get() {
    if [[ ! -f "$EC_PREF_FILE" ]]; then
        # No pref file yet → not auto-enabled (safe default for fresh installs).
        return 1
    fi
    local v
    v="$(jq -r 'if has("preferred") then (if .preferred == true then "true" else "false" end) else "false" end' \
        "$EC_PREF_FILE" 2>/dev/null || echo false)"
    [[ "$v" == "true" ]]
}

ec_pref_set() {
    local want="$1"  # true | false
    mkdir -p "$EC_PREF_DIR"
    printf '{"preferred":%s}\n' "$want" >"$EC_PREF_FILE"
}

# Emit JSON status for the AudioPill toggle (always exit 0).
ec_status() {
    local mid prev_src prev_sink enabled=false err="" preferred=false
    mid="$(ec_find_module_id || true)"
    local def_src def_sink
    def_src="$(pactl get-default-source 2>/dev/null || true)"
    def_sink="$(pactl get-default-sink 2>/dev/null || true)"

    local state_json
    state_json="$(ec_read_state)"
    prev_src="$(printf '%s' "$state_json" | jq -r '.previous_source // empty' 2>/dev/null || true)"
    prev_sink="$(printf '%s' "$state_json" | jq -r '.previous_sink // empty' 2>/dev/null || true)"

    if ec_pref_get; then
        preferred=true
    fi

    if [[ -n "$mid" ]] && { [[ "$def_src" == "$EC_SOURCE_NAME" ]] || ec_nodes_present; }; then
        enabled=true
    elif [[ -n "$mid" ]]; then
        # Module loaded but not our clean state — still report enabled so Off can clean up.
        enabled=true
        err="echo-cancel module loaded (cleanup with Off if audio sounds wrong)"
    fi

    printf '{"enabled":%s,"preferred":%s,"module_id":"%s","ec_source":"%s","ec_sink":"%s","default_source":"%s","default_sink":"%s","previous_source":"%s","previous_sink":"%s","error":"%s","reversible":true,"permanent":%s}\n' \
        "$enabled" \
        "$preferred" \
        "$(json_esc "${mid:-}")" \
        "$(json_esc "$EC_SOURCE_NAME")" \
        "$(json_esc "$EC_SINK_NAME")" \
        "$(json_esc "$def_src")" \
        "$(json_esc "$def_sink")" \
        "$(json_esc "$prev_src")" \
        "$(json_esc "$prev_sink")" \
        "$(json_esc "$err")" \
        "$preferred"
}

# Unload every module-echo-cancel instance (idempotent).
ec_unload_all() {
    local ids id
    ids="$(pactl list modules short 2>/dev/null | awk '$2 == "module-echo-cancel" { print $1 }' || true)"
    for id in $ids; do
        pactl unload-module "$id" 2>/dev/null || true
    done
}

# Restore defaults from state file when those devices still exist.
ec_restore_defaults() {
    local state_json prev_src prev_sink
    state_json="$(ec_read_state)"
    prev_src="$(printf '%s' "$state_json" | jq -r '.previous_source // empty' 2>/dev/null || true)"
    prev_sink="$(printf '%s' "$state_json" | jq -r '.previous_sink // empty' 2>/dev/null || true)"

    if [[ -n "$prev_sink" ]] && ! ec_is_virtual "$prev_sink"; then
        if pactl list short sinks 2>/dev/null | awk -v n="$prev_sink" '$2 == n { found=1 } END { exit !found }'; then
            pactl set-default-sink "$prev_sink" 2>/dev/null || true
        fi
    fi
    if [[ -n "$prev_src" ]] && ! ec_is_virtual "$prev_src"; then
        if pactl list short sources 2>/dev/null | awk -v n="$prev_src" '$2 == n { found=1 } END { exit !found }'; then
            pactl set-default-source "$prev_src" 2>/dev/null || true
        fi
    fi
}

ec_off() {
    # Level 1 back-out: restore saved hardware defaults, unload, clear runtime state.
    # Also clears sticky preference so it stays off across reboots until turned On again.
    ec_pref_set false
    ec_restore_defaults
    ec_unload_all
    # If defaults still point at vanished virtual nodes, leave them; user can pick devices in UI.
    ec_clear_state
    ec_status
}

ec_force_off() {
    # Level 2 back-out: same as off, but always unloads even with corrupt/missing state.
    ec_pref_set false
    ec_restore_defaults
    ec_unload_all
    # Best-effort: if default still is a virtual EC name, switch to first non-virtual device.
    local def_src def_sink first_src first_sink
    def_src="$(pactl get-default-source 2>/dev/null || true)"
    def_sink="$(pactl get-default-sink 2>/dev/null || true)"
    if ec_is_virtual "$def_sink"; then
        first_sink="$(pactl list short sinks 2>/dev/null | awk -v ec="$EC_SINK_NAME" '$2 != ec && $2 !~ /echo-cancel/ { print $2; exit }' || true)"
        [[ -n "$first_sink" ]] && pactl set-default-sink "$first_sink" 2>/dev/null || true
    fi
    if ec_is_virtual "$def_src"; then
        first_src="$(pactl list short sources 2>/dev/null | awk -v ec="$EC_SOURCE_NAME" '$2 != ec && $2 !~ /echo-cancel/ && $2 !~ /\.monitor$/ { print $2; exit }' || true)"
        [[ -n "$first_src" ]] && pactl set-default-source "$first_src" 2>/dev/null || true
    fi
    ec_clear_state
    ec_status
}

# Apply sticky preference at login (used by systemd + AudioPill). Idempotent.
ec_apply() {
    # Wait for PipeWire/Pulse to answer (login races are common).
    local i
    for i in $(seq 1 30); do
        if pactl info >/dev/null 2>&1; then
            break
        fi
        sleep 0.5
    done
    if ! pactl info >/dev/null 2>&1; then
        printf '{"enabled":false,"preferred":false,"error":"PipeWire/Pulse not ready","reversible":true,"permanent":false}\n'
        return 1
    fi

    if ec_pref_get; then
        # apply=1 → do not rewrite preference (avoids racing a concurrent Off).
        ec_on apply
        return $?
    fi
    ec_status
    return 0
}

ec_on() {
    # Optional first arg: "apply" means login/auto apply (do not force preferred=true).
    # Explicit user On (UI/IPC) sets sticky preferred=true.
    local mode="${1:-}"
    if [[ "$mode" != "apply" ]]; then
        ec_pref_set true
    fi

    # Idempotent: if already cleanly enabled, just report status.
    local mid
    mid="$(ec_find_module_id || true)"
    local def_src def_sink
    def_src="$(pactl get-default-source 2>/dev/null || true)"
    def_sink="$(pactl get-default-sink 2>/dev/null || true)"

    if [[ -n "$mid" && "$def_src" == "$EC_SOURCE_NAME" && "$def_sink" == "$EC_SINK_NAME" ]]; then
        ec_status
        return 0
    fi

    # Start from a clean slate so we never stack two AEC modules.
    if [[ -n "$mid" ]]; then
        ec_restore_defaults
        ec_unload_all
        sleep 0.2
        def_src="$(pactl get-default-source 2>/dev/null || true)"
        def_sink="$(pactl get-default-sink 2>/dev/null || true)"
    fi

    # Masters must be real hardware (or at least non-virtual) devices.
    local source_master sink_master
    source_master="$def_src"
    sink_master="$def_sink"
    if ec_is_virtual "$source_master" || [[ -z "$source_master" ]]; then
        source_master="$(pactl list short sources 2>/dev/null | awk '$2 !~ /echo-cancel/ && $2 !~ /\.monitor$/ && $2 != "'"$EC_SOURCE_NAME"'" { print $2; exit }' || true)"
    fi
    if ec_is_virtual "$sink_master" || [[ -z "$sink_master" ]]; then
        sink_master="$(pactl list short sinks 2>/dev/null | awk '$2 !~ /echo-cancel/ && $2 != "'"$EC_SINK_NAME"'" { print $2; exit }' || true)"
    fi

    if [[ -z "$source_master" || -z "$sink_master" ]]; then
        printf '{"enabled":false,"error":"no usable mic/speaker for echo cancel","reversible":true}\n'
        return 1
    fi

    # Persist previous defaults BEFORE load so Off can always restore.
    ec_write_state <<EOF
{"enabled":false,"module_id":"","ec_source":"$(json_esc "$EC_SOURCE_NAME")","ec_sink":"$(json_esc "$EC_SINK_NAME")","previous_source":"$(json_esc "$source_master")","previous_sink":"$(json_esc "$sink_master")","source_master":"$(json_esc "$source_master")","sink_master":"$(json_esc "$sink_master")"}
EOF

    local load_out
    set +e
    load_out="$(pactl load-module module-echo-cancel \
        aec_method=webrtc \
        source_master="$source_master" \
        sink_master="$sink_master" \
        source_name="$EC_SOURCE_NAME" \
        sink_name="$EC_SINK_NAME" \
        source_properties=device.description="Echo Cancelled Mic (Quickshell)" \
        sink_properties=device.description="Echo Cancelled Speakers (Quickshell)" 2>&1)"
    local load_rc=$?
    set -e

    if [[ $load_rc -ne 0 || -z "$load_out" || ! "$load_out" =~ ^[0-9]+$ ]]; then
        ec_clear_state
        printf '{"enabled":false,"error":"failed to load module-echo-cancel: %s","reversible":true}\n' \
            "$(json_esc "$load_out")"
        return 1
    fi

    # Brief wait for virtual nodes to appear (PipeWire is async).
    local i
    for i in 1 2 3 4 5 6 7 8 9 10; do
        if pactl list short sources 2>/dev/null | awk -v n="$EC_SOURCE_NAME" '$2 == n { found=1 } END { exit !found }' \
            && pactl list short sinks 2>/dev/null | awk -v n="$EC_SINK_NAME" '$2 == n { found=1 } END { exit !found }'; then
            break
        fi
        sleep 0.1
    done

    # Point defaults at virtual devices so Meet/Telegram/Discord/browsers pick them up.
    # Apps keep their own AEC; if double-AEC sounds bad, user toggles Off (fully reversible).
    if ! pactl set-default-source "$EC_SOURCE_NAME" 2>/dev/null; then
        ec_unload_all
        pactl set-default-source "$source_master" 2>/dev/null || true
        pactl set-default-sink "$sink_master" 2>/dev/null || true
        ec_clear_state
        printf '{"enabled":false,"error":"loaded module but could not set default source; restored hardware","reversible":true}\n'
        return 1
    fi
    if ! pactl set-default-sink "$EC_SINK_NAME" 2>/dev/null; then
        # Partial failure: restore source + unload so we never leave a half-on state.
        pactl set-default-source "$source_master" 2>/dev/null || true
        ec_unload_all
        pactl set-default-sink "$sink_master" 2>/dev/null || true
        ec_clear_state
        printf '{"enabled":false,"error":"loaded module but could not set default sink; restored hardware","reversible":true}\n'
        return 1
    fi

    # If the user turned Off while we were loading (UI/IPC race), honor Off.
    if ! ec_pref_get; then
        pactl set-default-source "$source_master" 2>/dev/null || true
        pactl set-default-sink "$sink_master" 2>/dev/null || true
        ec_unload_all
        ec_clear_state
        ec_status
        return 0
    fi

    ec_write_state <<EOF
{"enabled":true,"module_id":"$(json_esc "$load_out")","ec_source":"$(json_esc "$EC_SOURCE_NAME")","ec_sink":"$(json_esc "$EC_SINK_NAME")","previous_source":"$(json_esc "$source_master")","previous_sink":"$(json_esc "$sink_master")","source_master":"$(json_esc "$source_master")","sink_master":"$(json_esc "$sink_master")"}
EOF
    ec_status
}

# ---------------------------------------------------------------------------
# Active app streams (sink-inputs / source-outputs) for AudioPill summary
# ---------------------------------------------------------------------------
# Emits one JSON object:
#   { "playback": [ {app, media, device, mute, volume_pct, corked}, ... ],
#     "recording": [ ... ] }
list_streams() {
    # Build index→description maps as JSON objects (gawk only — avoids fragile jq -R).
    device_map_json() {
        local kind="$1"  # Sink | Source
        local plural="$2"
        pactl list "$plural" 2>/dev/null | gawk -v kind="$kind" '
        function jesc(s) {
            gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); return s
        }
        BEGIN { idx=""; n=0 }
        $0 ~ ("^" kind " #") {
            idx=$2; sub(/^#/,"",idx); desc=""; name=""; next
        }
        /^[\t ]*Name: / {
            name=$2; for (i=3;i<=NF;i++) name=name" "$i; next
        }
        /^[\t ]*Description: / {
            desc=substr($0, index($0,":")+2); sub(/^[ \t]+/,"",desc)
            if (idx!="") {
                n++
                k[n]=idx
                v[n]=(desc!=""?desc:name)
            }
            next
        }
        END {
            printf "{"
            for (i=1;i<=n;i++) {
                if (i>1) printf ","
                printf "\"%s\":\"%s\"", jesc(k[i]), jesc(v[i])
            }
            printf "}"
        }
        '
    }

    parse_streams() {
        local header="$1"  # Sink Input | Source Output
        local plural="$2"  # sink-inputs | source-outputs
        local dev_field="$3"  # Sink | Source
        pactl list "$plural" 2>/dev/null | gawk -v header="$header" -v dev_field="$dev_field" '
        function jesc(s) {
            gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s)
            gsub(/\t/, "\\t", s); gsub(/\r/, "", s); gsub(/\n/, "\\n", s)
            return s
        }
        function strip_q(s) {
            sub(/^"/, "", s); sub(/"$/, "", s); return s
        }
        BEGIN { idx=""; n=0 }
        $0 ~ ("^" header " #") {
            if (idx != "") flush()
            idx = $3; sub(/^#/, "", idx)
            app=""; binary=""; media=""; mute="false"; vol=0; corked="false"; dev=""
            next
        }
        /^[\t ]*application\.name = / {
            app = strip_q(substr($0, index($0,"=")+2)); sub(/^[ \t]+/, "", app); next
        }
        /^[\t ]*application\.process\.binary = / {
            binary = strip_q(substr($0, index($0,"=")+2)); sub(/^[ \t]+/, "", binary); next
        }
        /^[\t ]*media\.name = / {
            media = strip_q(substr($0, index($0,"=")+2)); sub(/^[ \t]+/, "", media); next
        }
        /^[\t ]*Mute: / { mute = ($2=="yes"?"true":"false"); next }
        /^[\t ]*Corked: / { corked = ($2=="yes"?"true":"false"); next }
        /^[\t ]*Volume:/ {
            if (match($0, /[[:space:]]([0-9]+)%/, m)) vol = m[1]+0
            next
        }
        $0 ~ ("^[\t ]*" dev_field ": ") { dev = $2; next }
        END { if (idx != "") flush() }
        function flush() {
            if (app=="" && binary!="") app=binary
            if (app=="") app="Unknown"
            if (media=="") media="-"
            # Hide internal peak meters (PwNodePeakMonitor → "Quickshell Peak Detect")
            low = tolower(app " " binary " " media)
            if (low ~ /peak detect/) return
            if (low ~ /quickshell peak/) return
            printf "{\"index\":%s,\"app\":\"%s\",\"media\":\"%s\",\"device_index\":\"%s\",\"mute\":%s,\"volume_pct\":%d,\"corked\":%s}\n",
                idx, jesc(app), jesc(media), jesc(dev), mute, vol, corked
        }
        ' | jq -s '.'
    }

    local sink_map source_map playback recording
    sink_map="$(device_map_json Sink sinks)"
    source_map="$(device_map_json Source sources)"
    [[ -n "$sink_map" ]] || sink_map='{}'
    [[ -n "$source_map" ]] || source_map='{}'

    playback="$(parse_streams "Sink Input" "sink-inputs" "Sink")"
    recording="$(parse_streams "Source Output" "source-outputs" "Source")"
    [[ -n "$playback" ]] || playback='[]'
    [[ -n "$recording" ]] || recording='[]'

    # Filter noise that is not real app media:
    #  - Quickshell Peak Detect (VU meters while popup Level is On)
    #  - corked/paused streams (browser tab paused, etc.)
    #  - empty placeholders
    # -c: one compact line so QML/collectors never only see a trailing "}"
    jq -nc \
        --argjson playback "$playback" \
        --argjson recording "$recording" \
        --argjson sinks "$sink_map" \
        --argjson sources "$source_map" '
        def is_internal:
            # Hide graph plumbing that is not real app media:
            #  - Quickshell Peak Detect (VU meters while Level is On)
            #  - Echo-cancel capture/playback legs (qs_ec_* filter)
            ((.app // "") | test("peak detect|Peak Detect|Quickshell Peak|echo-?cancel"; "i"))
            or ((.media // "") | test("peak detect|Peak Detect|echo-?cancel"; "i"));
        def is_active:
            # corked = paused/stopped by the app (e.g. YouTube pause); hide those.
            # Keep muted streams visible so users can still see who holds the device.
            (.corked != true) and (is_internal | not);
        def enrich($list; $map):
            [ $list[]
              | select(is_active)
              | . as $s
              | ($map[$s.device_index] // ("#" + ($s.device_index // "?"))) as $dev
              | $s + {
                  device: $dev,
                  label: (
                      $s.app
                      + (if ($s.media != null and $s.media != "" and $s.media != "-")
                         then " · " + $s.media else "" end)
                      + " → " + $dev
                  )
              }
            ];
        {
            playback: enrich($playback; $sinks),
            recording: enrich($recording; $sources)
        }
        '
}

# ---------------------------------------------------------------------------
# Bluetooth battery via bluetoothctl (process-isolated — never touches BlueZ
# from QML during device disconnect, which caused qs segfaults).
# ---------------------------------------------------------------------------
# Output (one line JSON):
#   all:  {"devices":{"A0:0C:E2:66:FB:7D":80,...}}
#   mac:  {"mac":"A0:…","percent":80,"connected":true}
# Missing/unknown battery → percent -1 or omitted from map.
bt_battery() {
    local want="${1:-all}"
    if ! command -v bluetoothctl >/dev/null 2>&1; then
        if [[ "$want" == "all" ]]; then
            echo '{"devices":{}}'
        else
            printf '{"mac":"%s","percent":-1,"connected":false}\n' "$(json_esc "$want")"
        fi
        return 0
    fi

    # Parse `bluetoothctl devices` + `info` for connected devices with Battery Percentage.
    # Runs entirely in a subprocess so BlueZ D-Bus teardown cannot crash qs.
    local out
    out="$(
        bluetoothctl devices 2>/dev/null | awk '{print $2}' | while read -r mac; do
            [[ -z "$mac" ]] && continue
            info="$(bluetoothctl info "$mac" 2>/dev/null || true)"
            connected="$(printf '%s\n' "$info" | awk -F': ' '/Connected:/{print $2; exit}')"
            [[ "$connected" != "yes" ]] && continue
            # "Battery Percentage: 0x50 (80)" or "Battery Percentage: 80"
            pct="$(printf '%s\n' "$info" | awk '
                /Battery Percentage:/ {
                    if (match($0, /\(([0-9]+)\)/, m)) { print m[1]; next }
                    if (match($0, /Battery Percentage:[[:space:]]*(0x[0-9a-fA-F]+|[[:digit:]]+)/, m)) {
                        v = m[1]
                        if (v ~ /^0x/) { print strtonum(v); next }
                        print v+0
                    }
                }')"
            [[ -z "$pct" ]] && pct="-1"
            # Normalize MAC to uppercase colon form
            mac_u="$(printf '%s' "$mac" | tr 'a-f' 'A-F')"
            printf '%s\t%s\n' "$mac_u" "$pct"
        done
    )"

    if [[ "$want" == "all" ]]; then
        printf '%s\n' "$out" | gawk -F'\t' '
        BEGIN { printf "{\"devices\":{" }
        NF >= 2 {
            if (n++) printf ","
            mac = $1; pct = $2 + 0
            printf "\"%s\":%d", mac, pct
        }
        END { printf "}}\n" }
        '
        return 0
    fi

    # Single MAC lookup (accept colon or underscore form)
    local want_u
    want_u="$(printf '%s' "$want" | tr '_' ':' | tr 'a-f' 'A-F')"
    local hit
    hit="$(printf '%s\n' "$out" | awk -F'\t' -v w="$want_u" 'toupper($1)==w { print $2; exit }')"
    if [[ -n "$hit" ]]; then
        printf '{"mac":"%s","percent":%d,"connected":true}\n' "$(json_esc "$want_u")" "$hit"
    else
        printf '{"mac":"%s","percent":-1,"connected":false}\n' "$(json_esc "$want_u")"
    fi
}

# Full PipeWire stack restart (user session). Re-applies sticky echo cancel after.
restart_audio() {
    # Keep errors soft so we always return a parseable JSON line for the UI.
    set +e

    # Restart the user audio stack in a safe order. Sockets stay up; services recycle.
    systemctl --user restart pipewire.service 2>/dev/null
    systemctl --user restart pipewire-pulse.service 2>/dev/null
    systemctl --user restart wireplumber.service 2>/dev/null

    local ok=0 i
    for i in $(seq 1 50); do
        if pactl info >/dev/null 2>&1; then
            ok=1
            break
        fi
        sleep 0.2
    done

    if [[ $ok -ne 1 ]]; then
        printf '{"ok":false,"error":"PipeWire did not come back after restart"}\n'
        set -e
        return 1
    fi

    # Stale module ids from before the restart are invalid — clear runtime state.
    ec_clear_state

    # Give nodes a moment to re-enumerate before reloading echo cancel.
    sleep 0.4

    local ec_enabled=false
    if ec_pref_get; then
        # apply mode: do not flip preferred; rebuild qs_ec_* if wanted.
        # Capture only the last JSON line in case anything else leaks to stdout.
        local ec_out
        ec_out="$(ec_on apply 2>/dev/null)"
        if [[ -z "$ec_out" ]]; then
            ec_out="$(ec_status 2>/dev/null)"
        fi
        if printf '%s' "$ec_out" | jq -e '.enabled == true' >/dev/null 2>&1; then
            ec_enabled=true
        fi
    fi

    # Simple response — avoid nested --argjson (was failing under some shells/values).
    printf '{"ok":true,"error":"","echo_cancel_enabled":%s}\n' "$ec_enabled"
    set -e
    return 0
}

if [[ -z "$ACTION" ]]; then
    usage
    exit 2
fi

if ! command -v pactl >/dev/null 2>&1; then
    echo "pactl not found" >&2
    exit 1
fi

# Emit one JSON object describing profiles for a PipeWire/Pulse card.
# Used by AudioPill profile dropdowns. Safe when card is missing (empty list).
list_card_profiles() {
    local want="$1"
    if [[ -z "$want" ]]; then
        echo '{"card":"","active":"","profiles":[]}'
        return 0
    fi
    # gawk is reliable for the multi-colon profile name format:
    #   name: description (sinks: N, sources: N, priority: N, available: yes|no)
    pactl list cards 2>/dev/null | gawk -v want="$want" '
    function json_esc(s) {
        gsub(/\\/, "\\\\", s)
        gsub(/"/, "\\\"", s)
        return s
    }
    BEGIN { found=0; in_prof=0; active=""; card=""; n=0 }
    /^Card / {
        if (found) exit
        found=0; in_prof=0
        next
    }
    /^[\t ]*Name: / {
        name=$2
        for (i = 3; i <= NF; i++) name = name " " $i
        if (name == want) { found=1; card=name }
        next
    }
    found && /^[\t ]*Active Profile: / {
        active=$3
        for (i = 4; i <= NF; i++) active = active " " $i
        next
    }
    found && /^[\t ]*Profiles:/ { in_prof=1; next }
    found && in_prof && /^[\t ]*Ports:/ { in_prof=0; next }
    found && in_prof {
        line = $0
        sub(/^[\t ]+/, "", line)
        if (match(line, /^(.+): (.+) \(sinks: ([0-9]+), sources: ([0-9]+), priority: ([0-9]+), available: (yes|no)\)/, m)) {
            n++
            pname[n] = m[1]
            pdesc[n] = m[2]
            pavail[n] = (m[6] == "yes" ? "true" : "false")
            psinks[n] = m[3] + 0
            psources[n] = m[4] + 0
            prio[n] = m[5] + 0
        }
        next
    }
    END {
        printf "{\"card\":\"%s\",\"active\":\"%s\",\"profiles\":[", json_esc(card), json_esc(active)
        for (i = 1; i <= n; i++) {
            if (i > 1) printf ","
            printf "{\"name\":\"%s\",\"description\":\"%s\",\"available\":%s,\"sinks\":%d,\"sources\":%d,\"priority\":%d}",
                json_esc(pname[i]), json_esc(pdesc[i]), pavail[i], psinks[i], psources[i], prio[i]
        }
        printf "]}\n"
    }
    ' || echo '{"card":"","active":"","profiles":[]}'
}

case "$ACTION" in
    set-default)
        if [[ -z "$TARGET" || -z "$NAME" ]]; then
            echo "device name required" >&2
            exit 2
        fi
        case "$TARGET" in
            sink)   pactl set-default-sink "$NAME" ;;
            source) pactl set-default-source "$NAME" ;;
            *) echo "invalid target: $TARGET" >&2; exit 2 ;;
        esac
        ;;
    set-port)
        if [[ -z "$TARGET" || -z "$NAME" || -z "$ARG" ]]; then
            echo "device name and port required" >&2
            exit 2
        fi
        case "$TARGET" in
            sink)   pactl set-sink-port "$NAME" "$ARG" ;;
            source) pactl set-source-port "$NAME" "$ARG" ;;
            *) echo "invalid target: $TARGET" >&2; exit 2 ;;
        esac
        ;;
    set-volume)
        if [[ -z "$TARGET" || -z "$NAME" || -z "$ARG" ]]; then
            echo "device name and volume percent required" >&2
            exit 2
        fi
        if ! [[ "$ARG" =~ ^[0-9]+$ ]]; then
            echo "volume must be an integer percent (0-100+)" >&2
            exit 2
        fi
        case "$TARGET" in
            sink)   pactl set-sink-volume "$NAME" "${ARG}%" ;;
            source) pactl set-source-volume "$NAME" "${ARG}%" ;;
            *) echo "invalid target: $TARGET" >&2; exit 2 ;;
        esac
        ;;
    # Per-channel L/R volume. ARG = left %, ARG2 = right % (both 0-100+ integers).
    # Mirrors pactl multi-VOLUME syntax used by pavucontrol for balance.
    set-channel-volume)
        if [[ -z "$TARGET" || -z "$NAME" || -z "$ARG" || -z "$ARG2" ]]; then
            echo "device name, left percent, and right percent required" >&2
            exit 2
        fi
        if ! [[ "$ARG" =~ ^[0-9]+$ && "$ARG2" =~ ^[0-9]+$ ]]; then
            echo "channel volumes must be integer percents" >&2
            exit 2
        fi
        case "$TARGET" in
            sink)   pactl set-sink-volume "$NAME" "${ARG}%" "${ARG2}%" ;;
            source) pactl set-source-volume "$NAME" "${ARG}%" "${ARG2}%" ;;
            *) echo "invalid target: $TARGET" >&2; exit 2 ;;
        esac
        ;;
    toggle-mute)
        if [[ -z "$TARGET" || -z "$NAME" ]]; then
            echo "device name required" >&2
            exit 2
        fi
        case "$TARGET" in
            sink)   pactl set-sink-mute "$NAME" toggle ;;
            source) pactl set-source-mute "$NAME" toggle ;;
            *) echo "invalid target: $TARGET" >&2; exit 2 ;;
        esac
        ;;
    # --- Card profile support (AudioPill playback/recording profile dropdowns) ---
    list-card-profiles)
        # TARGET is the card name (e.g. alsa_card.usb-...)
        list_card_profiles "${TARGET:-}"
        exit 0
        ;;
    set-card-profile)
        # TARGET = card name, NAME = profile name
        if [[ -z "$TARGET" || -z "$NAME" ]]; then
            echo "card name and profile name required" >&2
            exit 2
        fi
        pactl set-card-profile "$TARGET" "$NAME"
        ;;
    # --- Echo cancel (AudioPill Recording toggle; fully reversible) ---
    echo-cancel-status)
        ec_status
        exit 0
        ;;
    echo-cancel-on)
        ec_on
        exit $?
        ;;
    echo-cancel-off)
        ec_off
        exit 0
        ;;
    echo-cancel-force-off)
        ec_force_off
        exit 0
        ;;
    echo-cancel-apply)
        # Login / shell start: enable only if sticky preference is true.
        ec_apply
        exit $?
        ;;
    list-streams)
        list_streams
        exit 0
        ;;
    restart-audio)
        restart_audio
        exit $?
        ;;
    bt-battery)
        # TARGET optional: MAC or "all" (default all)
        bt_battery "${TARGET:-all}"
        exit 0
        ;;
    *)
        echo "invalid action: $ACTION" >&2
        usage
        exit 2
        ;;
esac

echo "ok"