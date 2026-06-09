#!/bin/bash
set -euo pipefail

[ "$EUID" -ne 0 ] && exec sudo bash "$0" "$@"

CPU_SERVICE="/etc/systemd/system/bugtux-cpu.service"
SYSCTL_FILE="/etc/sysctl.d/99-bugtux-perf.conf"
DNS_CONF="/etc/NetworkManager/conf.d/99-bugtux-global-dns.conf"

G='\033[0;32m'
Y='\033[1;33m'
C='\033[0;36m'
N='\033[0m'
ok()   { echo -e "${G}[✓]${N} $*"; }
skip() { echo -e "${Y}[~]${N} $* — já aplicado, pulando."; }
step() { echo -e "${C}[>]${N} $*"; }

echo -e "\n${C}══════════════════════════════════════${N}"
echo -e "${C}   BugTux — CachyOS Performance Elite  ${N}"
echo -e "${C}══════════════════════════════════════${N}\n"

if systemctl is-enabled --quiet bugtux-cpu.service 2>/dev/null; then
    skip "CPU Governor"
else
    step "Cravando CPU em performance máxima..."
    systemctl mask --quiet power-profiles-daemon.service tlp.service 2>/dev/null || true
    cat > "$CPU_SERVICE" <<'EOF'
[Unit]
Description=BugTux CPU Performance Enforcer
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo performance | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now --quiet bugtux-cpu.service
    ok "CPU Governor → performance"
fi

if [ -f "$SYSCTL_FILE" ]; then
    skip "Parâmetros de kernel"
else
    step "Aplicando parâmetros de kernel (latência + rede)..."
    cat > "$SYSCTL_FILE" <<'EOF'
vm.swappiness = 10
vm.vfs_cache_pressure = 50
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
EOF
    sysctl --system -q
    ok "Kernel sysctl aplicado"
fi

if [ -f "$DNS_CONF" ]; then
    skip "DNS AdGuard"
else
    step "Injetando DNS AdGuard em todas as conexões..."
    mkdir -p "$(dirname "$DNS_CONF")"
    cat > "$DNS_CONF" <<'EOF'
[global-dns-domain-*]
servers=94.140.14.14,94.140.15.15,2a10:50c0::ad1:ff,2a10:50c0::ad2:ff
EOF
    while IFS= read -r conn; do
        [ -z "$conn" ] || [ "$conn" = "lo" ] && continue
        nmcli connection modify "$conn" \
            ipv4.ignore-auto-dns yes \
            ipv4.dns "94.140.14.14 94.140.15.15" \
            ipv6.ignore-auto-dns yes \
            ipv6.dns "2a10:50c0::ad1:ff 2a10:50c0::ad2:ff" 2>/dev/null || true
    done < <(nmcli -g NAME connection show)
    systemctl restart NetworkManager
    ok "DNS AdGuard injetado"
fi

echo -e "\n${G}══ Sistema no pico de desempenho. ══${N}\n"
read -n 1 -s -r -p "Pressione qualquer tecla para sair..." && clear
