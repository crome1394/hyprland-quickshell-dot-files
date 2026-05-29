#!/usr/bin/env bash
# sysmon poller.sh
# Efficient single-invocation data collector for the sysmon dashboard.
# Outputs one line of JSON. Designed to be fast and safe when called frequently.
#
# State for rate calculations lives in /tmp/sysmon-state.json.

set -u pipefail   # removed -e so we can always produce some JSON even if individual sensors fail

STATE_FILE="/tmp/sysmon-state.json"
NOW=$(date +%s%3N)

# ---------- Helpers ----------
json_escape() { printf '%s' "$1" | jq -R -s .; }

if [[ -f "$STATE_FILE" ]]; then
    PREV=$(cat "$STATE_FILE" 2>/dev/null || echo '{}')
else
    PREV='{}'
fi

prev_ts=$(jq -r '.ts // 0' <<<"$PREV")
prev_net_rx=$(jq -r '.net_rx // 0' <<<"$PREV")
prev_net_tx=$(jq -r '.net_tx // 0' <<<"$PREV")
prev_disk_read=$(jq -r '.disk_read // 0' <<<"$PREV")
prev_disk_write=$(jq -r '.disk_write // 0' <<<"$PREV")

delta_ms=$(( NOW - prev_ts ))
(( delta_ms <= 0 )) && delta_ms=1
delta_s=$(awk "BEGIN { printf \"%.3f\", $delta_ms / 1000 }")

# ---------- CPU Utilization (accurate short sample) ----------
read_cpu() { awk '/^cpu / { print $2+$3+$4+$5+$6+$7+$8, $5 }' /proc/stat; }

cpu1=$(read_cpu)
sleep 0.07
cpu2=$(read_cpu)

cpu1_total=$(cut -d' ' -f1 <<<"$cpu1")
cpu1_idle=$(cut -d' ' -f2 <<<"$cpu1")
cpu2_total=$(cut -d' ' -f1 <<<"$cpu2")
cpu2_idle=$(cut -d' ' -f2 <<<"$cpu2")

total_diff=$(( cpu2_total - cpu1_total ))
idle_diff=$(( cpu2_idle - cpu1_idle ))
if (( total_diff > 0 )); then
    cpu_util=$(awk "BEGIN { printf \"%.1f\", ($total_diff - $idle_diff) * 100 / $total_diff }")
else
    cpu_util="0.0"
fi

# ---------- Memory & Swap ----------
mem_total=$(awk '/MemTotal:/ {print $2}' /proc/meminfo)
mem_available=$(awk '/MemAvailable:/ {print $2}' /proc/meminfo)
swap_total=$(awk '/SwapTotal:/ {print $2}' /proc/meminfo)
swap_free=$(awk '/SwapFree:/ {print $2}' /proc/meminfo)

ram_used=$(( mem_total - mem_available ))
swap_used=$(( swap_total - swap_free ))

ram_total_mib=$(( mem_total / 1024 ))
ram_used_mib=$(( ram_used / 1024 ))
swap_total_mib=$(( swap_total / 1024 ))
swap_used_mib=$(( swap_used / 1024 ))

ram_pct=$(awk "BEGIN { printf \"%.1f\", ($ram_used_mib * 100.0) / $ram_total_mib }")
swap_pct=$(awk "BEGIN { if ($swap_total_mib > 0) printf \"%.1f\", ($swap_used_mib * 100.0) / $swap_total_mib; else print \"0.0\" }")

# ---------- Load Average + Uptime ----------
load_avg=$(awk '{print $1","$2","$3}' /proc/loadavg)
uptime_s=$(awk '{print int($1)}' /proc/uptime)

# ---------- NVIDIA GPU (RTX 5080) ----------
nvidia_raw=$(nvidia-smi --query-gpu=\
utilization.gpu,\
utilization.memory,\
memory.used,\
memory.total,\
temperature.gpu,\
power.draw,\
power.limit,\
fan.speed \
--format=csv,noheader,nounits 2>/dev/null || echo "0,0,0,0,0,0,0,0")

IFS=',' read -r gpu_util gpu_mem_util gpu_vram_used gpu_vram_total gpu_temp gpu_power gpu_power_limit gpu_fan <<<"$nvidia_raw"

gpu_util=$(echo "$gpu_util" | xargs)
gpu_vram_used=$(echo "$gpu_vram_used" | xargs)
gpu_vram_total=$(echo "$gpu_vram_total" | xargs)
gpu_temp=$(echo "$gpu_temp" | xargs)
gpu_power=$(echo "$gpu_power" | xargs)
gpu_power_limit=$(echo "$gpu_power_limit" | xargs)
gpu_fan=$(echo "$gpu_fan" | xargs)

: "${gpu_util:=0}"
: "${gpu_vram_used:=0}"
: "${gpu_vram_total:=16384}"
: "${gpu_temp:=0}"
: "${gpu_power:=0}"
: "${gpu_power_limit:=360}"
: "${gpu_fan:=0}"

gpu_vram_pct=$(awk "BEGIN { if ($gpu_vram_total > 0) printf \"%.1f\", ($gpu_vram_used * 100.0) / $gpu_vram_total; else print 0 }")

# ---------- Sensors via lm-sensors ----------
sensors_json=$(sensors -j 2>/dev/null || echo '{}')

# AMD 9950X3D temps (k10temp)
cpu_tctl=$(jq -r '."k10temp-pci-00c3" // {} | .Tctl // {} | .temp1_input // 0' <<<"$sensors_json" 2>/dev/null || echo 0)
cpu_tccd1=$(jq -r '."k10temp-pci-00c3" // {} | .Tccd1 // {} | .temp3_input // 0' <<<"$sensors_json" 2>/dev/null || echo 0)
cpu_tccd2=$(jq -r '."k10temp-pci-00c3" // {} | .Tccd2 // {} | .temp4_input // 0' <<<"$sensors_json" 2>/dev/null || echo 0)

# NVMe drives
nvme_sensors=$(jq -r '
  to_entries
  | map(select(.key | startswith("nvme-pci-")))
  | map({
      key: .key,
      composite: (.value.Composite // {} | .temp1_input // 0),
      sensor1: (.value."Sensor 1" // {} | .temp2_input // 0),
      sensor2: (.value."Sensor 2" // {} | .temp3_input // 0),
      sensor3: (.value."Sensor 3" // {} | .temp4_input // 0)
    })
' <<<"$sensors_json" 2>/dev/null || echo '[]')

# Any fan speeds reported by sensors
fan_speeds=$(jq -r '
  [ .. | objects | to_entries[] | select(.key | test("fan[0-9]+_input")) | {key: .key, rpm: .value} ]
  | map("\(.key):\(.rpm)")
  | join(",")
' <<<"$sensors_json" 2>/dev/null || echo '')

# ---------- Power Consumption (best effort) ----------
# Try common RAPL / powercap paths (works on many AMD + Intel systems)
package_power_w=0
for rapl_path in /sys/class/powercap/intel-rapl:0 /sys/class/powercap/intel-rapl:1 /sys/class/powercap/amd-rapl; do
    if [[ -f "$rapl_path/energy_uj" && -f "$rapl_path/max_energy_range_uj" ]]; then
        # Very rough instantaneous reading (not perfect but better than nothing)
        cur=$(cat "$rapl_path/energy_uj" 2>/dev/null || echo 0)
        maxr=$(cat "$rapl_path/max_energy_range_uj" 2>/dev/null || echo 1)
        if (( cur > 0 && maxr > 0 )); then
            # We can't do proper delta here without previous state, so we skip for now
            # For a future improvement we can track previous energy.
            :
        fi
    fi
done

# Fallback: try sensors for power1_average on relevant chips
power_from_sensors=$(jq -r '
  .. | objects | select(.power1_average) | .power1_average // empty
' <<<"$sensors_json" 2>/dev/null | head -1 || echo 0)

if [[ "$power_from_sensors" != "0" && "$power_from_sensors" != "" ]]; then
    package_power_w=$power_from_sensors
fi

# ---------- ccache stats (current size + max size + hit rate) ----------
ccache_hit_rate=0
ccache_size_gb=0
ccache_max_gb=0
if command -v ccache >/dev/null 2>&1; then
    ccache_out=$(ccache -s 2>/dev/null || echo "")

    # Hit rate
    hit_rate=$(echo "$ccache_out" | grep -i "hit rate" | awk '{print $3}' | tr -d '%' || echo 0)
    [[ -n "$hit_rate" ]] && ccache_hit_rate=$hit_rate

    # Current cache size (e.g. "1.23 GB" or "456 MB")
    cur_size=$(echo "$ccache_out" | grep -i "cache size" | awk '{print $3}')
    cur_unit=$(echo "$ccache_out" | grep -i "cache size" | awk '{print $4}')
    if [[ "$cur_unit" =~ G ]]; then
        ccache_size_gb=$cur_size
    elif [[ "$cur_unit" =~ M ]]; then
        ccache_size_gb=$(awk "BEGIN { printf \"%.2f\", $cur_size / 1024 }")
    fi

    # Max cache size (if configured)
    max_size=$(echo "$ccache_out" | grep -i "max cache size" | awk '{print $4}')
    max_unit=$(echo "$ccache_out" | grep -i "max cache size" | awk '{print $5}')
    if [[ "$max_unit" =~ G ]]; then
        ccache_max_gb=$max_size
    elif [[ "$max_unit" =~ M ]]; then
        ccache_max_gb=$(awk "BEGIN { printf \"%.2f\", $max_size / 1024 }")
    fi
fi

# Sanitize
ccache_hit_rate=$(printf "%.1f" "${ccache_hit_rate:-0}" 2>/dev/null || echo 0)
ccache_size_gb=$(printf "%.2f" "${ccache_size_gb:-0}" 2>/dev/null || echo 0)
ccache_max_gb=$(printf "%.2f" "${ccache_max_gb:-10}" 2>/dev/null || echo 10)

# ---------- Network rates (first non-lo interface) ----------
net_data=$(awk '
  $1 ~ /^[^ ]+:/ && $1 !~ /^lo:/ {
    gsub(/:/,"",$1)
    rx = $2; tx = $10
    print $1, rx, tx
    exit
  }
' /proc/net/dev)

net_iface=$(awk '{print $1}' <<<"$net_data")
net_rx=$(awk '{print $2}' <<<"$net_data")
net_tx=$(awk '{print $3}' <<<"$net_data")

net_rx_rate=0
net_tx_rate=0
if (( prev_ts > 0 && net_rx > prev_net_rx )); then
    net_rx_rate=$(awk "BEGIN { printf \"%.0f\", ($net_rx - $prev_net_rx) / $delta_s }")
fi
if (( prev_ts > 0 && net_tx > prev_net_tx )); then
    net_tx_rate=$(awk "BEGIN { printf \"%.0f\", ($net_tx - $prev_net_tx) / $delta_s }")
fi

# ---------- Disk I/O + Root filesystem ----------
disk_stats=$(awk '
  $3 ~ /^(nvme[0-9]+n[0-9]+|sd[a-z])$/ {
    read += $6
    write += $10
  }
  END { printf "%d %d", read, write }
' /proc/diskstats 2>/dev/null || echo "0 0")

disk_read=$(awk '{print $1}' <<<"$disk_stats")
disk_write=$(awk '{print $2}' <<<"$disk_stats")

disk_read_rate=0
disk_write_rate=0
if (( prev_ts > 0 && disk_read > prev_disk_read )); then
    disk_read_rate=$(awk "BEGIN { printf \"%.0f\", ($disk_read - $prev_disk_read) * 512 / $delta_s }")
fi
if (( prev_ts > 0 && disk_write > prev_disk_write )); then
    disk_write_rate=$(awk "BEGIN { printf \"%.0f\", ($disk_write - $prev_disk_write) * 512 / $delta_s }")
fi

root_usage=$(df -k / 2>/dev/null | awk 'NR==2 { printf "%.1f %.1f %.1f", $3/1024/1024, $2/1024/1024, ($3*100.0)/$2 }' || echo "0 0 0")
root_used=$(awk '{print $1}' <<<"$root_usage")
root_total=$(awk '{print $2}' <<<"$root_usage")
root_pct=$(awk '{print $3}' <<<"$root_usage")

# ---------- Detailed disk info for NVMe + key mounts (robust, always produces array) ----------
# Collects root, the /data media mount, and any other mounted nvme partitions with usage + model.
disks=$(
  declare -A seen_mounts
  out="[]"

  # Primary mounts we always want if present
  for m in / /run/media/crome/data; do
    if mountpoint -q "$m" 2>/dev/null; then
      src=$(findmnt -rn -o SOURCE --target "$m" 2>/dev/null || echo "")
      # Resolve backing disk for accurate MODEL (handles partitions + btrfs subvol paths like /dev/nvme0n1p2[/@])
      diskdev=$(lsblk -no PKNAME "$src" 2>/dev/null | head -1 | xargs 2>/dev/null || echo "$src")
      [[ -z "$diskdev" || "$diskdev" == "$src" ]] && diskdev="$src"
      model=$(lsblk -no MODEL "/dev/$diskdev" 2>/dev/null | head -1 | xargs 2>/dev/null || lsblk -no MODEL "$src" 2>/dev/null | head -1 | xargs 2>/dev/null || echo "NVMe")
      [[ -z "$model" || "$model" == "null" || "$model" == "Unknown" ]] && model="NVMe"
      read used total pct < <(df -k "$m" 2>/dev/null | awk 'NR==2 { printf "%.1f %.1f %.1f\n", $3/1024/1024, $2/1024/1024, ($3*100.0)/$2 }' || echo "0 0 0")
      # Best-effort temp: prefer nvme sensors, fallback to first available
      temp=$(jq -r '
        [ .. | objects | select(.Composite? or .temp1_input?) | (.Composite.temp1_input // .temp1_input // 0) ] | .[0] // 0
      ' <<<"$sensors_json" 2>/dev/null || echo 0)
      entry=$(jq -n \
        --arg mount "$m" \
        --arg device "${src:-unknown}" \
        --arg model "$model" \
        --argjson used "${used:-0}" \
        --argjson total "${total:-0}" \
        --argjson pct "${pct:-0}" \
        --argjson temp "${temp:-0}" \
        '{mount:$mount, device:$device, model:$model, used_gb:$used, total_gb:$total, pct:$pct, temp_c:$temp}')
      out=$(jq -n --argjson a "$out" --argjson e "$entry" '$a + [$e]')
      seen_mounts["$m"]=1
    fi
  done

  # Discover any other mounted NVMe partitions (e.g. additional drives) not already seen
  while read -r dev mnt; do
    [[ -z "$mnt" || "$mnt" == "null" ]] && continue
    [[ -n "${seen_mounts[$mnt]:-}" ]] && continue
    if [[ "$dev" == *nvme* ]]; then
      diskdev=$(lsblk -no PKNAME "$dev" 2>/dev/null | head -1 | xargs 2>/dev/null || echo "$(basename "$dev")")
      model=$(lsblk -no MODEL "/dev/$diskdev" 2>/dev/null | head -1 | xargs 2>/dev/null || lsblk -no MODEL "$dev" 2>/dev/null | head -1 | xargs 2>/dev/null || echo "NVMe")
      [[ -z "$model" || "$model" == "null" ]] && model="NVMe"
      read used total pct < <(df -k "$mnt" 2>/dev/null | awk 'NR==2 { printf "%.1f %.1f %.1f\n", $3/1024/1024, $2/1024/1024, ($3*100.0)/$2 }' || echo "0 0 0")
      temp=$(jq -r '
        [ .. | objects | select(.Composite? or .temp1_input?) | (.Composite.temp1_input // .temp1_input // 0) ] | .[0] // 0
      ' <<<"$sensors_json" 2>/dev/null || echo 0)
      entry=$(jq -n \
        --arg mount "$mnt" \
        --arg device "$dev" \
        --arg model "$model" \
        --argjson used "${used:-0}" \
        --argjson total "${total:-0}" \
        --argjson pct "${pct:-0}" \
        --argjson temp "${temp:-0}" \
        '{mount:$mount, device:$device, model:$model, used_gb:$used, total_gb:$total, pct:$pct, temp_c:$temp}')
      out=$(jq -n --argjson a "$out" --argjson e "$entry" '$a + [$e]')
      seen_mounts["$mnt"]=1
    fi
  done < <(lsblk -nr -o NAME,MOUNTPOINT 2>/dev/null | awk '$2 ~ /^\// { print "/dev/"$1, $2 }')

  echo "$out"
) 2>/dev/null || echo '[]'

# PSD (profile-sync-daemon) - parse `psd p` output for real profile + overlayfs usage
psd_profile_total_mb=0
psd_overlay_used_mb=0
psd_profiles_list=()

if command -v psd >/dev/null 2>&1; then
    psd_out=$(psd p 2>/dev/null || echo "")

    # Sum "profile size:" (what psd is keeping in the tmpfs/overlay)
    psd_profile_total_mb=$(echo "$psd_out" | awk '
        /profile size:/ {
            val = $3
            unit = $4
            if (unit ~ /^[0-9]/) { unit = $4; val = $3 }   # handle "102M" vs "102 M"
            if (unit ~ /G/) val *= 1024
            total += val
        }
        END { printf "%.0f", total }
    ')

    # Sum "overlayfs size:" (actual dirty space used in the upper layer)
    psd_overlay_used_mb=$(echo "$psd_out" | awk '
        /overlayfs size:/ {
            val = $3
            unit = $4
            if (unit ~ /^[0-9]/) { unit = $4; val = $3 }
            if (unit ~ /G/) val *= 1024
            total += val
        }
        END { printf "%.0f", total }
    ')

    # Extract unique browser names (firefox, google-chrome, brave, etc.)
    psd_profiles_list=$(echo "$psd_out" | awk '
        /browser\/psname:/ {
            split($2, a, "/")
            print a[1]
        }' | sort -u | jq -R -s 'split("\n") | map(select(. != ""))' 2>/dev/null || echo '[]')
fi

# Total capacity of the tmpfs backing psd (user reports 5.5G via df -h on the psd tmpfs)
psd_overlay_total_gb=$(df -h /run/user/1000/psd 2>/dev/null | awk 'NR==2 { gsub(/G/,"",$2); print $2 }' || echo "5.5")

# Build clean object for the dashboard
psd_json=$(jq -cn \
    --argjson prof_mb "${psd_profile_total_mb:-0}" \
    --argjson ov_used_mb "${psd_overlay_used_mb:-0}" \
    --argjson ov_total_gb "${psd_overlay_total_gb:-5.5}" \
    --argjson profs "${psd_profiles_list:-[]}" \
    '{
        profile_total_mb: $prof_mb,
        overlay_used_mb: $ov_used_mb,
        overlay_total_gb: $ov_total_gb,
        profiles: $profs
    }' 2>/dev/null || echo '{"profile_total_mb":0,"overlay_used_mb":0,"overlay_total_gb":5.5,"profiles":[]}')

# ---------- Top Processes (CPU) ----------
top_procs=$(ps -eo pid,comm,%cpu,%mem --sort=-%cpu 2>/dev/null | awk '
  NR>1 && $3 > 0.2 {
    printf "{\"pid\":%d,\"name\":\"%s\",\"cpu\":%.1f,\"mem\":%.1f}\n", $1, $2, $3, $4
  }
' | head -8 | jq -s 'map(select(.name != ""))' 2>/dev/null || echo '[]')

# ---------- Top Processes (by Memory) ----------
top_mem=$(ps -eo pid,comm,%cpu,%mem --sort=-%mem 2>/dev/null | awk '
  NR>1 && $4 > 0.1 {
    printf "{\"pid\":%d,\"name\":\"%s\",\"cpu\":%.1f,\"mem\":%.1f}\n", $1, $2, $3, $4
  }
' | head -8 | jq -s 'map(select(.name != ""))' 2>/dev/null || echo '[]')

# ---------- Assemble final JSON ----------
TMP_JSON=$(mktemp /tmp/sysmon-out.XXXXXX.json)

jq -cn \
  --argjson ts "$NOW" \
  --argjson cpu_util "$cpu_util" \
  --argjson cpu_temp "${cpu_tctl:-0}" \
  --argjson cpu_tccd1 "${cpu_tccd1:-0}" \
  --argjson cpu_tccd2 "${cpu_tccd2:-0}" \
  --argjson gpu_util "${gpu_util:-0}" \
  --argjson gpu_vram_used "${gpu_vram_used:-0}" \
  --argjson gpu_vram_total "${gpu_vram_total:-16384}" \
  --argjson gpu_temp "${gpu_temp:-0}" \
  --argjson gpu_power "${gpu_power:-0}" \
  --argjson gpu_power_limit "${gpu_power_limit:-360}" \
  --argjson gpu_fan "${gpu_fan:-0}" \
  --argjson gpu_vram_pct "${gpu_vram_pct:-0}" \
  --argjson ram_used_mib "$ram_used_mib" \
  --argjson ram_total_mib "$ram_total_mib" \
  --argjson ram_pct "$ram_pct" \
  --argjson swap_used_mib "$swap_used_mib" \
  --argjson swap_total_mib "$swap_total_mib" \
  --argjson swap_pct "$swap_pct" \
  --arg load_str "$load_avg" \
  --argjson uptime "$uptime_s" \
  --arg net_iface "${net_iface:-unknown}" \
  --argjson net_rx_rate "$net_rx_rate" \
  --argjson net_tx_rate "$net_tx_rate" \
  --argjson disk_read_rate "$disk_read_rate" \
  --argjson disk_write_rate "$disk_write_rate" \
  --argjson root_used "${root_used:-0}" \
  --argjson root_total "${root_total:-0}" \
  --argjson root_pct "${root_pct:-0}" \
  --argjson nvme_sensors "$nvme_sensors" \
  --arg fans_str "${fan_speeds:-}" \
  --argjson top_procs "$top_procs" \
  --argjson top_mem "$top_mem" \
  --argjson ccache_hit "${ccache_hit_rate:-0}" \
  --argjson ccache_size "${ccache_size_gb:-0}" \
  --argjson ccache_max "${ccache_max_gb:-10}" \
  --argjson disks "$disks" \
  --argjson psd "$psd_json" \
  '{
    timestamp: $ts,
    cpu: { util: $cpu_util, temp: $cpu_temp, tccd1: $cpu_tccd1, tccd2: $cpu_tccd2 },
    gpu: {
      util: $gpu_util, vram_used: $gpu_vram_used, vram_total: $gpu_vram_total,
      vram_pct: $gpu_vram_pct, temp: $gpu_temp, power: $gpu_power,
      power_limit: $gpu_power_limit, fan: $gpu_fan
    },
    memory: {
      ram_used: $ram_used_mib, ram_total: $ram_total_mib, ram_pct: $ram_pct,
      swap_used: $swap_used_mib, swap_total: $swap_total_mib, swap_pct: $swap_pct
    },
    load: ($load_str | split(",") | map(tonumber)),
    uptime: $uptime,
    network: { iface: $net_iface, rx_rate: $net_rx_rate, tx_rate: $net_tx_rate },
    disk: {
      read_rate: $disk_read_rate, write_rate: $disk_write_rate,
      root_used: $root_used, root_total: $root_total, root_pct: $root_pct
    },
    sensors: { nvme: $nvme_sensors, fans: $fans_str },
    top_processes: $top_procs,
    top_memory: $top_mem,
    ccache: { hit_rate: $ccache_hit, size_gb: $ccache_size, max_gb: $ccache_max },
    disks: $disks,
    psd: $psd
  }' > "$TMP_JSON" 2>/dev/null

if [[ -s "$TMP_JSON" ]]; then
    cat "$TMP_JSON"
else
    echo '{"error":"failed to assemble json"}'
fi
rm -f "$TMP_JSON" 2>/dev/null || true

# Update delta state
cat > "$STATE_FILE" <<EOF
{
  "ts": $NOW,
  "net_rx": ${net_rx:-0},
  "net_tx": ${net_tx:-0},
  "disk_read": ${disk_read:-0},
  "disk_write": ${disk_write:-0}
}
EOF
