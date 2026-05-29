#!/usr/bin/env bash
# bar-stats.sh
# Ultra-lightweight poller for the centered CPU+GPU pill in the top bar.
# Outputs a single line of JSON with current util + temp for AMD 9950X3D + RTX 5080.
# Designed to be called every ~1.5-1.8s. Completes in <120ms.

set -u

# ---------- CPU Utilization (double sample over ~60ms for responsiveness) ----------
read_cpu() {
    awk '/^cpu / { print $2+$3+$4+$5+$6+$7+$8, $5 }' /proc/stat
}

c1=$(read_cpu)
sleep 0.06
c2=$(read_cpu)

c1_total=$(cut -d' ' -f1 <<<"$c1")
c1_idle=$(cut -d' ' -f2 <<<"$c1")
c2_total=$(cut -d' ' -f1 <<<"$c2")
c2_idle=$(cut -d' ' -f2 <<<"$c2")

total_diff=$(( c2_total - c1_total ))
idle_diff=$(( c2_idle - c1_idle ))

if (( total_diff > 0 )); then
    cpu_util=$(awk "BEGIN { printf \"%.1f\", ($total_diff - $idle_diff) * 100 / $total_diff }")
else
    cpu_util="0.0"
fi

# ---------- CPU Temperature (k10temp Tctl - the package temp) ----------
# hwmon2 is reliably k10temp on this 9950X3D system (see hwmon inspection)
cpu_temp_raw=$(cat /sys/class/hwmon/hwmon2/temp1_input 2>/dev/null || echo 0)
cpu_temp=$(( cpu_temp_raw / 1000 ))

# ---------- NVIDIA RTX 5080 (minimal fast query) ----------
nvg_raw=$(nvidia-smi --query-gpu=utilization.gpu,temperature.gpu \
    --format=csv,noheader,nounits 2>/dev/null || echo "0, 0")

gpu_util=$(echo "$nvg_raw" | cut -d, -f1 | xargs)
gpu_temp=$(echo "$nvg_raw" | cut -d, -f2 | xargs)

: "${gpu_util:=0}"
: "${gpu_temp:=0}"

# Emit clean single-line JSON (no whitespace bloat)
printf '{"cpu":{"util":%s,"temp":%s},"gpu":{"util":%s,"temp":%s}}\n' \
    "$cpu_util" "$cpu_temp" "$gpu_util" "$gpu_temp"
