#!/usr/bin/env bash
# Privileged network data — may require elevated access on some systems.
# Includes routing, latency, firewall rules, and connection table.
# Run on demand only — avoids repeated auth prompts from fast polling.
set -u pipefail

NOW=$(date +%s)

gateway=$(ip route show default 2>/dev/null | awk '{for (i = 1; i <= NF; i++) if ($i == "via") { print $(i + 1); exit }}')
[[ -z "${gateway:-}" ]] && gateway=""

# ---------- Latency + packet loss (3 pings, 1s timeout each) ----------
ping_stats() {
    local host="$1"
    local label="$2"
    if [[ -z "$host" ]]; then
        jq -n --arg host "" --arg label "$label" \
            '{host: $host, label: $label, ms: -1, loss_pct: -1, ok: false}'
        return
    fi
    local out avg loss sent recv
    out=$(ping -c 3 -W 1 "$host" 2>/dev/null || true)
    avg=$(sed -n 's/.*rtt min\/avg\/max\/mdev = [0-9.]*\/\([0-9.]*\)\/.*/\1/p' <<<"$out" | head -1)
    loss=$(sed -n 's/.*, \([0-9]*\)% packet loss.*/\1/p' <<<"$out" | head -1)
    sent=$(sed -n 's/^\([0-9]*\) packets transmitted.*/\1/p' <<<"$out" | head -1)
    recv=$(sed -n 's/^\([0-9]*\) packets transmitted, \([0-9]*\) received.*/\2/p' <<<"$out" | head -1)
    [[ -z "$avg" ]] && avg="-1"
    [[ -z "$loss" ]] && loss="-1"
    [[ -z "$sent" ]] && sent="0"
    [[ -z "$recv" ]] && recv="0"
    jq -n \
        --arg host "$host" \
        --arg label "$label" \
        --argjson ms "$avg" \
        --argjson loss_pct "$loss" \
        --argjson sent "$sent" \
        --argjson recv "$recv" \
        '{
            host: $host, label: $label,
            ms: ($ms | tonumber), loss_pct: ($loss_pct | tonumber),
            sent: $sent, recv: $recv,
            ok: (($ms | tonumber) >= 0)
        }'
}

latency_json=$(jq -cn \
    --argjson gateway "$(ping_stats "$gateway" "Gateway")" \
    --argjson google_dns "$(ping_stats "8.8.8.8" "Google DNS")" \
    --argjson cloudflare_dns "$(ping_stats "1.1.1.1" "Cloudflare DNS")" \
    '{gateway: $gateway, google_dns: $google_dns, cloudflare_dns: $cloudflare_dns}')

# ---------- Routing table ----------
routes_json='[]'
if command -v ip >/dev/null 2>&1; then
    routes_json=$(ip -j route show table main 2>/dev/null | jq '
        [.[] | {
            dst: (.dst // "default"),
            gateway: (.gateway // ""),
            dev: (.dev // ""),
            protocol: (.protocol // ""),
            metric: (.metric // 0),
            scope: (.scope // "")
        }] | .[0:16]
    ' 2>/dev/null || echo '[]')
fi
if [[ -z "$routes_json" || "$routes_json" == "null" ]]; then
    routes_json=$(ip route show table main 2>/dev/null | head -16 \
        | jq -R -s 'split("\n") | map(select(length > 0))' 2>/dev/null || echo '[]')
fi

# ---------- Firewall summary ----------
fw_backend="none"
fw_active=false
fw_summary=""
rules_json='[]'

ufw_enabled=""
if [[ -f /etc/ufw/ufw.conf ]]; then
    ufw_enabled=$(grep -E '^ENABLED=' /etc/ufw/ufw.conf 2>/dev/null | cut -d= -f2 | tr -d ' ')
fi
ufw_service="inactive"
if command -v systemctl >/dev/null 2>&1; then
    ufw_service=$(systemctl is-active ufw 2>/dev/null || echo "inactive")
fi

parse_ufw_rules() {
    local file="$1"
    [[ -r "$file" ]] || return 0
    awk '
        /^### RULES ###/ { in_rules = 1; next }
        /^### END RULES ###/ { in_rules = 0; next }
        in_rules && /^-A / { print }
    ' "$file" 2>/dev/null | head -32
}

if [[ "$ufw_service" == "active" || "$ufw_enabled" == "yes" ]]; then
    fw_backend="ufw"
    fw_active=true
    live_status=$(ufw status 2>/dev/null | head -1 || true)
    if [[ "$live_status" == ERROR:* ]]; then
        fw_summary="UFW active (live rules require root)"
    else
        fw_summary="${live_status:-UFW active}"
    fi
    rules_lines=""
    rules_lines+=$(parse_ufw_rules /etc/ufw/user.rules)
    rules_lines+=$'\n'
    rules_lines+=$(parse_ufw_rules /etc/ufw/user6.rules)
    if [[ -n "$(echo "$rules_lines" | sed '/^$/d')" ]]; then
        rules_json=$(printf '%s\n' "$rules_lines" | sed '/^$/d' \
            | jq -R -s 'split("\n") | map(select(length > 0))' 2>/dev/null || echo '[]')
    else
        rules_json='["(no user rules in /etc/ufw/user.rules)"]'
    fi
elif command -v nft >/dev/null 2>&1; then
    nft_out=$(nft list ruleset 2>/dev/null || true)
    if [[ -n "$nft_out" ]]; then
        fw_backend="nftables"
        fw_active=true
        fw_summary="nftables ruleset"
        rules_json=$(printf '%s\n' "$nft_out" | head -32 \
            | jq -R -s 'split("\n") | map(select(length > 0))' 2>/dev/null || echo '[]')
    elif [[ -r /etc/nftables.conf ]]; then
        fw_backend="nftables"
        fw_summary="nftables configured (live rules require root)"
        rules_json=$(head -32 /etc/nftables.conf 2>/dev/null \
            | jq -R -s 'split("\n") | map(select(length > 0))' 2>/dev/null || echo '[]')
    fi
fi

if [[ "$fw_backend" == "none" ]] && command -v iptables >/dev/null 2>&1; then
    ipt_out=$(iptables -L -n --line-numbers 2>/dev/null || true)
    if [[ -n "$ipt_out" ]]; then
        fw_backend="iptables"
        fw_active=true
        fw_summary="iptables rules"
        rules_json=$(printf '%s\n' "$ipt_out" | head -32 \
            | jq -R -s 'split("\n") | map(select(length > 0))' 2>/dev/null || echo '[]')
    fi
fi

[[ -z "$fw_summary" ]] && fw_summary="No firewall detected"

firewall_json=$(jq -cn \
    --arg backend "$fw_backend" \
    --argjson active "$([[ "$fw_active" == true ]] && echo true || echo false)" \
    --arg summary "$fw_summary" \
    --argjson rules "$rules_json" \
    '{backend: $backend, active: $active, summary: $summary, rules: $rules}')

# ---------- Active connections (ss with process info) ----------
connections_json='[]'
if command -v ss >/dev/null 2>&1; then
    connections_json=$(
        { ss -H -tanpi 2>/dev/null; ss -H -uanpi 2>/dev/null; } | awk '
          function flush() {
            if (state != "" && local != "") {
              disp = state
              if (disp == "ESTAB") disp = "ESTABLISHED"
              gsub(/\\/, "\\\\", proc)
              gsub(/"/, "\\\"", proc)
              printf "{\"proto\":\"%s\",\"state\":\"%s\",\"local\":\"%s\",\"remote\":\"%s\",\"process\":\"%s\",\"bytes_sent\":%d,\"bytes_received\":%d}\n",
                proto, disp, local, remote, proc, tx + 0, rx + 0
            }
            state = ""; local = ""; remote = ""; proc = ""; tx = 0; rx = 0
          }
          /bytes_sent:/ {
            if (match($0, /bytes_sent:[0-9]+/)) {
              v = substr($0, RSTART, RLENGTH); sub(/bytes_sent:/, "", v); tx = v + 0
            }
            if (match($0, /bytes_received:[0-9]+/)) {
              v = substr($0, RSTART, RLENGTH); sub(/bytes_received:/, "", v); rx = v + 0
            }
            next
          }
          $1 ~ /^(ESTAB|LISTEN|TIME-WAIT|SYN-SENT|SYN-RECV|FIN-WAIT|CLOSE-WAIT|LAST-ACK|CLOSING|UNCONN)$/ {
            flush()
            state = $1
            local = $4
            remote = $5
            proto = (state == "UNCONN" ? "udp" : "tcp")
            p = index($0, "users:((\"")
            if (p > 0) {
              rest = substr($0, p + 9)
              q = index(rest, "\"")
              if (q > 0) proc = substr(rest, 1, q - 1)
            }
            next
          }
          END { flush() }
        ' | jq -s '
          map(select(.local != ""))
          | sort_by(
              if .state == "ESTABLISHED" then 0
              elif .state == "LISTEN" then 1
              else 2 end,
              -(.bytes_sent + .bytes_received)
            )
          | .[0:20]
        ' 2>/dev/null || echo '[]'
    )
fi

jq -cn \
    --argjson ts "$NOW" \
    --argjson latency "$latency_json" \
    --argjson routes "$routes_json" \
    --argjson firewall "$firewall_json" \
    --argjson connections "$connections_json" \
    '{
        timestamp: $ts,
        latency: $latency,
        routes: $routes,
        firewall: $firewall,
        connections: $connections
    }'