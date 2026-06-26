#!/usr/bin/env bash
# Query important systemd units and emit one JSON object.
set -euo pipefail

TS="$(date +%s)"

# scope:unit — curated desktop/Hyprland services
UNITS=(
    "user:wayland-wm@hyprland.service"
    "user:swaync.service"
    "user:pipewire.service"
    "user:pipewire-pulse.service"
    "user:wireplumber.service"
    "user:hypridle.service"
    "user:hyprpolkitagent.service"
    "user:xdg-desktop-portal-hyprland.service"
    "user:xdg-desktop-portal.service"
    "user:espanso.service"
    "user:hyprpaper.service"
    "system:NetworkManager.service"
    "system:bluetooth.service"
    "system:polkit.service"
    "system:systemd-resolved.service"
    "system:systemd-timesyncd.service"
    "system:sshd.service"
    "system:docker.service"
    "system:cups.service"
    "system:ufw.service"
)

show_unit() {
    local scope="$1"
    local unit="$2"
    local -a ctl=(systemctl)
    [[ "$scope" == "user" ]] && ctl+=(--user)

    local out=""
    out="$("${ctl[@]}" show "$unit" \
        --property=Id,Description,ActiveState,SubState,UnitFileState,ActiveEnterTimestamp,InactiveEnterTimestamp,LoadState \
        --no-pager 2>/dev/null)" || true

    local id="$unit" desc="" load_state="not-found" active_state="unknown" sub_state=""
    local unit_file_state="" active_ts="" inactive_ts="" loaded_since=""

    if [[ -n "$out" ]]; then
        while IFS='=' read -r key value; do
            [[ -z "$key" ]] && continue
            case "$key" in
                Id) id="$value" ;;
                Description) desc="$value" ;;
                LoadState) load_state="$value" ;;
                ActiveState) active_state="$value" ;;
                SubState) sub_state="$value" ;;
                UnitFileState) unit_file_state="$value" ;;
                ActiveEnterTimestamp) active_ts="$value" ;;
                InactiveEnterTimestamp) inactive_ts="$value" ;;
            esac
        done <<< "$out"
    fi

    if [[ -n "$active_ts" ]]; then
        loaded_since="$active_ts"
    else
        loaded_since="$inactive_ts"
    fi

    jq -n \
        --arg id "$id" \
        --arg scope "$scope" \
        --arg name "$id" \
        --arg description "$desc" \
        --arg load_state "$load_state" \
        --arg active_state "$active_state" \
        --arg sub_state "$sub_state" \
        --arg unit_file_state "$unit_file_state" \
        --arg loaded_since "$loaded_since" \
        '{
            id: $id,
            scope: $scope,
            name: $name,
            description: $description,
            load_state: $load_state,
            active_state: $active_state,
            sub_state: $sub_state,
            unit_file_state: $unit_file_state,
            loaded_since: $loaded_since
        }'
}

items=()
for entry in "${UNITS[@]}"; do
    scope="${entry%%:*}"
    unit="${entry#*:}"
    items+=("$(show_unit "$scope" "$unit")")
done

json_list=$(printf '%s\n' "${items[@]}" | jq -s '.')

jq -n \
    --argjson timestamp "$TS" \
    --argjson services "$json_list" \
    '{ timestamp: $timestamp, services: $services }'