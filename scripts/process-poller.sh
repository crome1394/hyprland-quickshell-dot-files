#!/usr/bin/env bash
# Async process list collector for the Processes tab. Kept separate from
# sysmon-poller.sh so the main metrics poll stays fast.
set -uo pipefail

# shellcheck source=lib/poll-common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/poll-common.sh"

NOW=$(date +%s%3N)
load_avg=$(awk '{print $1","$2","$3}' /proc/loadavg 2>/dev/null || echo "0,0,0")
proc_running=$(awk '{split($4,a,"/"); print a[1]+0}' /proc/loadavg 2>/dev/null || echo 0)
proc_total=$(awk '{split($4,a,"/"); print a[2]+0}' /proc/loadavg 2>/dev/null || echo 0)

processes=$(ensure_json_array "$(ps -eo pid,user,stat,ni,pri,%cpu,%mem,rss,vsz,time,nlwp,start,comm --no-headers --sort=-%cpu 2>/dev/null | head -100 | awk '
  {
    pid = $1
    user = $2
    state = $3
    nice = $4
    pri = $5
    cpu = $6
    mem = $7
    rss = $8
    vsz = $9
    ptime = $10
    threads = $11
    pstart = $12
    comm = $13
    for (i = 14; i <= NF; i++)
      comm = comm " " $i

    shr_kb = 0
    statm = "/proc/" pid "/statm"
    if ((getline sm < statm) > 0) {
      split(sm, parts, " ")
      shr_kb = int(parts[3]) * 4
      close(statm)
    }

    if (nice == "-") nice_val = "null"
    else nice_val = nice + 0

    gsub(/\\/, "\\\\", user)
    gsub(/"/, "\\\"", user)
    gsub(/\\/, "\\\\", comm)
    gsub(/"/, "\\\"", comm)
    gsub(/\\/, "\\\\", ptime)
    gsub(/"/, "\\\"", ptime)
    gsub(/\\/, "\\\\", pstart)
    gsub(/"/, "\\\"", pstart)

    if (nice_val == "null")
      printf "{\"pid\":%d,\"user\":\"%s\",\"name\":\"%s\",\"cmd\":\"%s\",\"state\":\"%s\",\"nice\":null,\"pri\":%d,\"cpu\":%.1f,\"mem\":%.1f,\"rss\":%d,\"vsz\":%d,\"shr\":%d,\"time\":\"%s\",\"start\":\"%s\",\"threads\":%d}\n",
        pid, user, comm, comm, state, pri, cpu, mem, rss, vsz, shr_kb, ptime, pstart, threads
    else
      printf "{\"pid\":%d,\"user\":\"%s\",\"name\":\"%s\",\"cmd\":\"%s\",\"state\":\"%s\",\"nice\":%d,\"pri\":%d,\"cpu\":%.1f,\"mem\":%.1f,\"rss\":%d,\"vsz\":%d,\"shr\":%d,\"time\":\"%s\",\"start\":\"%s\",\"threads\":%d}\n",
        pid, user, comm, comm, state, nice_val, pri, cpu, mem, rss, vsz, shr_kb, ptime, pstart, threads
  }
' | jq -s 'map(select(.pid != null))' 2>/dev/null)")

jq -cn \
  --argjson ts "$NOW" \
  --argjson running "$proc_running" \
  --argjson total "$proc_total" \
  --arg load_str "$load_avg" \
  --argjson processes "$processes" \
  '{
    timestamp: $ts,
    running: $running,
    total: $total,
    load: ($load_str | split(",") | map(tonumber)),
    processes: $processes
  }'