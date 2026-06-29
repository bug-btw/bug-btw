#!/bin/bash
set -euo pipefail

[ "$EUID" -ne 0 ] && exec sudo bash "$0" "$@"
trap 'clear; exit 0' INT

CPU_SERVICE="/etc/systemd/system/bugtux-cpu.service"
SYSCTL_FILE="/etc/sysctl.d/99-bugtux-perf.conf"
LIMITS_FILE="/etc/security/limits.d/99-bugtux-gaming.conf"
IO_SERVICE="/etc/systemd/system/bugtux-io.service"
GPU_SERVICE="/etc/systemd/system/bugtux-gpu.service"
DNS_CONF="/etc/NetworkManager/conf.d/99-bugtux-dns.conf"
SCX_DROP="/etc/systemd/system/scx_loader.service.d/bugtux-lavd.conf"

declare -A DNS_LABEL=( [0]="Cloudflare Malware Block" [1]="AdGuard" )
declare -A DNS4=(      [0]="1.1.1.2 1.0.0.2"          [1]="94.140.14.14 94.140.15.15" )
declare -A DNS6=(      [0]="2606:4700:4700::1112 2606:4700:4700::1002" [1]="2a10:50c0::ad1:ff 2a10:50c0::ad2:ff" )

G='\033[0;32m'; Y='\033[1;33m'; C='\033[0;36m'
B='\033[1;34m'; R='\033[0;31m'; BLD='\033[1m'; N='\033[0m'

ok()   { echo -e "${G}[✓]${N} $*"; }
skip() { echo -e "${Y}[~]${N} $* — já aplicado."; }
step() { echo -e "${C}[>]${N} $*"; }
fail() { echo -e "${R}[✗]${N} $*"; }

header() {
    echo -e "\n${C}══════════════════════════════════════════${N}"
    echo -e "${C}   BugTux — CachyOS Performance Elite v2   ${N}"
    echo -e "${C}══════════════════════════════════════════${N}\n"
}

content_matches() { [ -f "$1" ] && [ "$(cat "$1")" = "$2" ]; }

write_if_changed() {
    local file="$1" content="$2"
    if content_matches "$file" "$content"; then return 1; fi
    mkdir -p "$(dirname "$file")"
    printf '%s\n' "$content" > "$file"
    return 0
}

apply_cpu() {
    local content
    content=$(cat << 'EOF'
[Unit]
Description=BugTux CPU Performance Governor
After=multi-user.target
[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo performance | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor > /dev/null'
ExecStart=/bin/sh -c 'echo 0 | tee /sys/devices/system/cpu/cpu*/power/energy_perf_bias > /dev/null 2>&1 || true'
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
EOF
)
    systemctl mask --quiet power-profiles-daemon.service tlp.service 2>/dev/null || true
    if write_if_changed "$CPU_SERVICE" "$content"; then
        systemctl daemon-reload
        systemctl enable --now --quiet bugtux-cpu.service
        CPU_MSG="$(ok "CPU Governor → performance + energy_perf_bias=0")"
    else
        CPU_MSG="$(skip "CPU Governor")"
    fi
}

apply_sysctl() {
    local content
    content=$(cat << 'EOF'
vm.swappiness = 1
vm.vfs_cache_pressure = 50
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5
vm.max_map_count = 2147483642
kernel.sched_autogroup_enabled = 1
kernel.sched_migration_cost_ns = 500000
kernel.nmi_watchdog = 0
kernel.unprivileged_userns_clone = 1
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.core.netdev_max_backlog = 16384
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_mtu_probing = 1
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 1024
fs.file-max = 2097152
EOF
)
    if write_if_changed "$SYSCTL_FILE" "$content"; then
        sysctl --system -q
        SYSCTL_MSG="$(ok "Kernel sysctl aplicado (gaming + network + memory)")"
    else
        SYSCTL_MSG="$(skip "Kernel sysctl")"
    fi
}

apply_scx() {
    local content
    content=$(cat << 'EOF'
[Service]
Environment="SCX_SCHEDULER=scx_lavd"
Environment="SCX_FLAGS=--performance"
EOF
)
    if ! command -v scx_lavd &>/dev/null && ! [ -f /usr/lib/scx/scx_lavd ]; then
        SCX_MSG="$(fail "scx_lavd não encontrado — instale: sudo pacman -S scx-scheds")"; return
    fi

    local changed=0
    write_if_changed "$SCX_DROP" "$content" && changed=1

    if [ $changed -eq 1 ]; then
        systemctl daemon-reload
        systemctl restart scx_loader 2>/dev/null || true
        SCX_MSG="$(ok "scx_lavd configurado (--performance) via scx_loader")"
    else
        local current=$(busctl get-property org.scx.Loader /org/scx/Loader org.scx.Loader CurrentScheduler 2>/dev/null | awk '{print $2}' | tr -d '"' || echo "unknown")
        SCX_MSG="$(skip "scx_lavd (ativo: $current)")"
    fi
}

apply_io() {
    local content
    content=$(cat << 'EOF'
[Unit]
Description=BugTux IO Scheduler
After=multi-user.target
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c 'for dev in /sys/block/sd*; do rot=$(cat $dev/queue/rotational 2>/dev/null || echo 1); if [ "$rot" = "0" ]; then echo mq-deadline > $dev/queue/scheduler 2>/dev/null || true; echo 0 > $dev/queue/add_random 2>/dev/null || true; echo 2 > $dev/queue/nomerges 2>/dev/null || true; fi; done; for dev in /sys/block/nvme*; do echo none > $dev/queue/scheduler 2>/dev/null || true; done'
[Install]
WantedBy=multi-user.target
EOF
)
    if write_if_changed "$IO_SERVICE" "$content"; then
        systemctl daemon-reload
        systemctl enable --now --quiet bugtux-io.service
        IO_MSG="$(ok "IO Scheduler → mq-deadline (SSD) / none (NVMe)")"
    else
        IO_MSG="$(skip "IO Scheduler")"
    fi
}

apply_gpu() {
    local content
    content=$(cat << 'EOF'
[Unit]
Description=BugTux Intel GPU Performance
After=multi-user.target
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c 'for card in /sys/class/drm/card*/; do max=$(cat ${card}gt_RP0_freq_mhz 2>/dev/null || echo ""); [ -z "$max" ] && continue; echo $max > ${card}gt_min_freq_mhz 2>/dev/null || true; echo $max > ${card}gt_boost_freq_mhz 2>/dev/null || true; done'
[Install]
WantedBy=multi-user.target
EOF
)
    if write_if_changed "$GPU_SERVICE" "$content"; then
        systemctl daemon-reload
        systemctl enable --now --quiet bugtux-gpu.service
        GPU_MSG="$(ok "Intel UHD 620 → freq mínima elevada ao boost máximo")"
    else
        GPU_MSG="$(skip "Intel GPU freq")"
    fi
}

apply_limits() {
    local content
    content=$(cat << 'EOF'
* soft nofile 1048576
* hard nofile 1048576
* soft memlock unlimited
* hard memlock unlimited
* soft stack unlimited
* hard stack unlimited
@audio - rtprio 98
@audio - memlock unlimited
@audio - nice -20
EOF
)
    if write_if_changed "$LIMITS_FILE" "$content"; then
        LIMITS_MSG="$(ok "System limits → nofile/memlock/rtprio configurados")"
    else
        LIMITS_MSG="$(skip "System limits")"
    fi
}

select_dns() {
    local choice=0 key seq
    while true; do
        clear >&2
        echo -e "${B}Selecione o provedor de DNS:${N}\n" >&2
        if [ $choice -eq 0 ]; then
            echo -e "  ${BLD}${G}→ ${DNS_LABEL[0]} ←${N}          ${DNS_LABEL[1]}" >&2
        else
            echo -e "    ${DNS_LABEL[0]}          ${BLD}${G}→ ${DNS_LABEL[1]} ←${N}" >&2
        fi
        echo -e "\n${Y}← → navegar  |  Enter confirma  |  Backspace pular  |  Ctrl+C sair${N}" >&2
        read -rsn1 key
        if [[ "$key" == $'\x7f' || "$key" == $'\b' ]]; then
            echo "BACK"; return
        elif [ "$key" = $'\x1b' ]; then
            read -rsn2 -t 0.1 seq 2>/dev/null || true
            case $seq in '[D') choice=0 ;; '[C') choice=1 ;; esac
        elif [ -z "$key" ]; then
            echo "$choice"; return
        fi
    done
}

apply_dns() {
    local idx="$1"
    local d4="${DNS4[$idx]}" d6="${DNS6[$idx]}"
    local d4csv="${d4// /,}" d6csv="${d6// /,}"
    local conf_content="[global-dns-domain-*]\nservers=${d4csv},${d6csv}"

    if content_matches "$DNS_CONF" "$conf_content"; then
        DNS_MSG="$(skip "DNS (${DNS_LABEL[$idx]})")"
        return
    fi
    mkdir -p "$(dirname "$DNS_CONF")"
    printf '%b\n' "$conf_content" > "$DNS_CONF"
    while IFS= read -r conn; do
        [ -z "$conn" ] || [ "$conn" = "lo" ] && continue
        nmcli connection modify "$conn" ipv4.ignore-auto-dns yes ipv4.dns "$d4" ipv6.ignore-auto-dns yes ipv6.dns "$d6" 2>/dev/null || true
    done < <(nmcli -g NAME connection show)
    systemctl restart NetworkManager
    DNS_MSG="$(ok "DNS ${DNS_LABEL[$idx]} → ${d4csv}")"
}

# ── Execução Principal ──

CPU_MSG="" SYSCTL_MSG="" SCX_MSG="" IO_MSG="" GPU_MSG="" LIMITS_MSG="" DNS_MSG=""

step "Aplicando CPU governor..."
apply_cpu
step "Aplicando sysctl..."
apply_sysctl
step "Configurando scx_lavd..."
apply_scx
step "Configurando IO scheduler..."
apply_io
step "Configurando Intel GPU..."
apply_gpu
step "Aplicando system limits..."
apply_limits

dns_idx=$(select_dns)
if [[ "$dns_idx" == "BACK" ]]; then
    DNS_MSG="$(skip "DNS (Pulado pelo usuário)")"
else
    apply_dns "$dns_idx"
fi

clear
header
echo -e "$CPU_MSG"
echo -e "$SYSCTL_MSG"
echo -e "$SCX_MSG"
echo -e "$IO_MSG"
echo -e "$GPU_MSG"
echo -e "$LIMITS_MSG"
echo -e "$DNS_MSG"
echo -e "\n${G}══ Sistema no pico absoluto de desempenho. ══${N}\n"
read -n 1 -s -r -p "Pressione qualquer tecla para sair..." && clear
