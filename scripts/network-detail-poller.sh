#!/usr/bin/env bash
# On-demand network detail collector (latency/loss, public IP, firewall, routes, DNS).
# Designed for infrequent calls when the Network tab is opened or refreshed.
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

# ---------- Public IP (short external lookup) ----------
public_ip=""
public_ip_error=""
for url in "https://api.ipify.org" "https://ifconfig.me/ip"; do
    if command -v curl >/dev/null 2>&1; then
        public_ip=$(curl -fsS --max-time 2 "$url" 2>/dev/null | tr -d '[:space:]')
        if [[ -n "$public_ip" && "$public_ip" =~ ^[0-9a-fA-F:.]+$ ]]; then
            break
        fi
        public_ip=""
    fi
done
[[ -z "$public_ip" ]] && public_ip_error="lookup failed or offline"

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

# ---------- DNS resolution + cache ----------
dns_servers_json='[]'
dns_current=""
dns_link=""
dns_domain=""
dns_cache_json='{"cache_size":0,"cache_hits":0,"cache_misses":0,"transactions":0}'
if command -v resolvectl >/dev/null 2>&1; then
    dns_servers=()
    while IFS= read -r line; do
        case "$line" in
            Link\ *' ('*')')
                cur_link="${line#Link * (}"
                cur_link="${cur_link%)}"
                ;;
            *"Current DNS Server:"*)
                dns_current="${line#*Current DNS Server: }"
                dns_current="${dns_current%%#*}"
                dns_link="${cur_link:-}"
                ;;
            *"DNS Domain:"*)
                dns_domain="${line#*DNS Domain: }"
                ;;
            *"DNS Servers:"*)
                rest="${line#*DNS Servers: }"
                while read -r srv; do
                    srv="${srv%%#*}"
                    [[ -n "$srv" ]] && dns_servers+=("$srv")
                done < <(tr ' ' '\n' <<<"$rest")
                ;;
            "Fallback DNS Servers:"*)
                rest="${line#Fallback DNS Servers: }"
                while read -r srv; do
                    srv="${srv%%#*}"
                    [[ -n "$srv" ]] && dns_servers+=("$srv")
                done < <(tr ' ' '\n' <<<"$rest")
                ;;
        esac
    done < <(resolvectl status 2>/dev/null || true)
    while read -r ip; do
        [[ -n "$ip" ]] && dns_servers+=("$ip")
    done < <(resolvectl status 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | awk '!seen[$0]++')
    if ((${#dns_servers[@]} > 0)); then
        dns_servers_json=$(printf '%s\n' "${dns_servers[@]}" | awk '!seen[$0]++' | head -16 \
            | jq -R -s 'split("\n") | map(select(length > 0))' 2>/dev/null || echo '[]')
    fi
    stats_out=$(resolvectl statistics 2>/dev/null || true)
    if [[ -n "$stats_out" ]]; then
        cache_size=$(sed -n 's/^[[:space:]]*Current Cache Size:[[:space:]]*\([0-9]*\).*/\1/p' <<<"$stats_out" | head -1)
        cache_hits=$(sed -n 's/^[[:space:]]*Cache Hits:[[:space:]]*\([0-9]*\).*/\1/p' <<<"$stats_out" | head -1)
        cache_misses=$(sed -n 's/^[[:space:]]*Cache Misses:[[:space:]]*\([0-9]*\).*/\1/p' <<<"$stats_out" | head -1)
        transactions=$(sed -n 's/^[[:space:]]*Total Transactions:[[:space:]]*\([0-9]*\).*/\1/p' <<<"$stats_out" | head -1)
        dns_cache_json=$(jq -cn \
            --argjson cache_size "${cache_size:-0}" \
            --argjson cache_hits "${cache_hits:-0}" \
            --argjson cache_misses "${cache_misses:-0}" \
            --argjson transactions "${transactions:-0}" \
            '{cache_size: $cache_size, cache_hits: $cache_hits, cache_misses: $cache_misses, transactions: $transactions}')
    fi
fi
if [[ -z "$dns_servers_json" || "$dns_servers_json" == "[]" ]]; then
    dns_servers_json=$(grep -E '^nameserver ' /etc/resolv.conf 2>/dev/null | awk '{print $2}' | head -16 \
        | jq -R -s 'split("\n") | map(select(length > 0))' 2>/dev/null || echo '[]')
fi

dns_json=$(jq -cn \
    --argjson servers "$dns_servers_json" \
    --arg current "${dns_current:-}" \
    --arg link "${dns_link:-}" \
    --arg domain "${dns_domain:-}" \
    --argjson cache "$dns_cache_json" \
    '{servers: $servers, current: $current, link: $link, domain: $domain, cache: $cache}')

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

jq -cn \
    --argjson ts "$NOW" \
    --arg public_ip "$public_ip" \
    --arg public_ip_error "$public_ip_error" \
    --argjson latency "$latency_json" \
    --argjson routes "$routes_json" \
    --argjson dns "$dns_json" \
    --argjson firewall "$firewall_json" \
    '{
        timestamp: $ts,
        public_ip: $public_ip,
        public_ip_error: $public_ip_error,
        latency: $latency,
        routes: $routes,
        dns: $dns,
        firewall: $firewall
    }'