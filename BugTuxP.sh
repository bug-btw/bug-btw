#!/bin/bash

set -o pipefail

if [ "$EUID" -ne 0 ]; then
    REAL_USER="$(whoami)"
    REAL_HOME="$HOME"
    export REAL_USER REAL_HOME
    exec sudo --preserve-env=REAL_USER,REAL_HOME bash "$0" "$@"
fi

: "${REAL_USER:=${SUDO_USER:-root}}"
if [ -z "${REAL_HOME:-}" ]; then
    REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6 2>/dev/null || echo "/root")
fi
: "${REAL_HOME:=/root}"
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

G=$'\033[0;32m'
Y=$'\033[1;33m'
C=$'\033[0;36m'
B=$'\033[1;34m'
R=$'\033[0;31m'
BLD=$'\033[1m'
DIM=$'\033[2m'
N=$'\033[0m'

trap 'clear; exit 0' INT TERM

ok()   { echo -e "  ${G}[✓]${N} $*"; }
skip() { echo -e "  ${Y}[~]${N} $*"; }
warn() { echo -e "  ${Y}[!]${N} $*"; }
step() { echo -e "  ${C}[>]${N} $*"; }
fail() { echo -e "  ${R}[✗]${N} $*"; }
log()  { echo -e "  ${DIM}$*${N}"; }
hdr()  { echo -e "\n${C}${BLD}  ─── $* ───${N}"; }
sep()  { echo -e "  ${DIM}$(printf '%.0s─' {1..50})${N}"; }

_sys_cpu()    { grep -m1 "model name" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs | sed 's/(R)//g;s/(TM)//g;s/ CPU//g;s/ @ .*//g;s/  */ /g'; }
_sys_gpu()    { lspci 2>/dev/null | grep -iE "vga|3d controller" | head -1 | sed 's/.*: //;s/ (rev.*//' | cut -c1-45; }
_sys_distro() { . /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-${NAME:-Linux}}"; }
_sys_kernel() { uname -r; }
_sys_de()     { echo "${XDG_CURRENT_DESKTOP:-${DESKTOP_SESSION:-unknown}}"; }

header() {
    clear
    local cpu gpu distro kernel de
    cpu=$(_sys_cpu)
    gpu=$(_sys_gpu)
    distro=$(_sys_distro)
    kernel=$(_sys_kernel)
    de=$(_sys_de)
    echo -e "${C}${BLD}"
    echo -e "  ╔══════════════════════════════════════════╗"
    echo -e "  ║                  BugTuxP                 ║"
    echo -e "  ║         </> github.com/bug-btw/ </>      ║"
    echo -e "  ╚══════════════════════════════════════════╝${N}"
    echo -e "  ${DIM}${distro} · ${de}${N}"
    echo -e "  ${DIM}${cpu}${N}"
    echo -e "  ${DIM}${gpu}${N}"
    echo -e "  ${DIM}Kernel: ${kernel}${N}"
    echo
}

progress() {
    local pct=$1 label="${2:-}" width=38
    local filled=$(( pct * width / 100 ))
    local bar="" i
    for (( i=0; i<filled; i++ )); do bar+="█"; done
    for (( i=filled; i<width; i++ )); do bar+="░"; done
    printf "\r  ${C}[%s]${N} ${BLD}%3d%%${N} %s" "$bar" "$pct" "${label:0:45}"
    [ "$pct" -eq 100 ] && echo
}

progress_item() {
    local current=$1 total=$2 label="${3:-}" width=38
    local pct=0; [ "$total" -gt 0 ] && pct=$(( current * 100 / total ))
    local filled=$(( pct * width / 100 ))
    local bar="" i
    for (( i=0; i<filled; i++ )); do bar+="█"; done
    for (( i=filled; i<width; i++ )); do bar+="░"; done
    printf "\r\033[K  ${C}[%s]${N} ${BLD}%3d%%${N} %s" "$bar" "$pct" "${label:0:45}"
}

progress_done() { echo; }

tag() {
    case "$1" in
        OK)      echo -e "${G}${BLD}[✓ Aplicado]${N}" ;;
        PARTIAL) echo -e "${Y}${BLD}[~ Parcial ]${N}" ;;
        *)       echo -e "${R}${BLD}[✗ Pendente]${N}" ;;
    esac
}

content_matches() {
    [ -f "$1" ] && [ "$(cat "$1" 2>/dev/null)" = "$2" ]
}

write_if_changed() {
    local file="$1" content="$2"
    content_matches "$file" "$content" && return 1
    mkdir -p "$(dirname "$file")"
    printf '%s\n' "$content" > "$file"
    return 0
}

run_as_user() {
    local uid; uid=$(id -u "$REAL_USER" 2>/dev/null) || uid=1000
    runuser -u "$REAL_USER" -- env \
        XDG_RUNTIME_DIR="/run/user/$uid" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus" "$@"
}

own_back()   { chown -R "$REAL_USER":"$REAL_USER" "$@" 2>/dev/null || true; }

pause() {
    echo
    printf "  ${DIM}Pressione qualquer tecla para continuar...${N}"
    IFS= read -rsn1 </dev/tty 2>/dev/null || true
    echo
}

detect_pkg_manager() {
    command -v pacman &>/dev/null && echo pacman && return
    command -v apt    &>/dev/null && echo apt    && return
    command -v dnf    &>/dev/null && echo dnf    && return
    command -v zypper &>/dev/null && echo zypper && return
    echo unknown
}

install_pkgs() {
    local pm; pm=$(detect_pkg_manager)
    case "$pm" in
        pacman)  pacman -S --noconfirm --needed "$@" 2>/dev/null || true ;;
        apt)     apt-get install -y "$@" 2>/dev/null || true ;;
        dnf)     dnf install -y "$@" 2>/dev/null || true ;;
        zypper)  zypper install -y "$@" 2>/dev/null || true ;;
        *)       warn "🗂 Gerenciador de pacotes não detectado" ;;
    esac
}

rebuild_kde_cache() {
    command -v kbuildsycoca6 &>/dev/null && run_as_user kbuildsycoca6 --noincremental 2>/dev/null && return
    command -v kbuildsycoca5 &>/dev/null && run_as_user kbuildsycoca5 --noincremental 2>/dev/null || true
}

select_menu() {
    local prompt="$1"; shift
    local options=("$@") choice=0 total=${#options[@]} key="" seq=""
    while true; do
        clear >&2
        echo -e "${B}${BLD}  $prompt${N}\n" >&2
        local i
        for i in "${!options[@]}"; do
            [ "$i" -eq "$choice" ] \
                && echo -e "  ${BLD}${G}→ ${options[$i]}${N}" >&2 \
                || echo -e "  ${DIM}  ${options[$i]}${N}" >&2
        done
        echo -e "\n  ${DIM}↑↓ Navegar  │  ↵ Enter Confirma  │  ⌫ Backspace Voltar  │  Ctrl+C Sair${N}" >&2
        IFS= read -rsn1 key </dev/tty 2>/dev/null || key=""
        if [[ "$key" == $'\x7f' || "$key" == $'\b' ]]; then
            echo "BACK"; return 0
        elif [[ "$key" == $'\x1b' ]]; then
            IFS= read -rsn2 -t 0.1 seq </dev/tty 2>/dev/null || seq=""
            [[ "$seq" == '[A' ]] && [ "$choice" -gt 0 ]              && choice=$(( choice - 1 ))
            [[ "$seq" == '[B' ]] && [ "$choice" -lt $(( total - 1 )) ] && choice=$(( choice + 1 ))
        elif [ -z "$key" ]; then
            echo "$choice"; return 0
        fi
    done
}

confirm_dialog() {
    local prompt="$1" choice=1 key="" seq=""
    while true; do
        clear >&2
        echo -e "${B}${BLD}  $prompt${N}\n" >&2
        [ "$choice" -eq 0 ] \
            && echo -e "  ${BLD}${G}→ Sim ←${N}          ${DIM}Não / Voltar${N}" >&2 \
            || echo -e "  ${DIM}  Sim${N}          ${BLD}${R}→ Não / Voltar ←${N}" >&2
        echo -e "\n  ${DIM}←→  │  Y/S = Sim  │  N = Não  │  ↵ Enter Confirma${N}" >&2
        IFS= read -rsn1 key </dev/tty 2>/dev/null || key=""
        if [[ "$key" == $'\x7f' || "$key" == $'\b' ]]; then
            echo "BACK"; return 0
        elif [[ "$key" == $'\x1b' ]]; then
            IFS= read -rsn2 -t 0.1 seq </dev/tty 2>/dev/null || seq=""
            [[ "$seq" == '[D' ]] && choice=0; [[ "$seq" == '[C' ]] && choice=1
        elif [[ "$key" == "y" || "$key" == "Y" || "$key" == "s" || "$key" == "S" ]]; then
            echo "0"; return 0
        elif [[ "$key" == "n" || "$key" == "N" ]]; then
            echo "1"; return 0
        elif [ -z "$key" ]; then
            echo "$choice"; return 0
        fi
    done
}

CPU_SERVICE="/etc/systemd/system/bugtux-cpu.service"
IO_SERVICE="/etc/systemd/system/bugtux-io.service"
GPU_SERVICE="/etc/systemd/system/bugtux-gpu.service"
THP_SERVICE="/etc/systemd/system/bugtux-thp.service"
ZRAM_SERVICE="/etc/systemd/system/bugtux-zram.service"
SYSCTL_FILE="/etc/sysctl.d/99-bugtux-perf.conf"
LIMITS_FILE="/etc/security/limits.d/99-bugtux-gaming.conf"
DNS_CONF="/etc/NetworkManager/conf.d/99-bugtux-dns.conf"
SCX_DROP="/etc/systemd/system/scx_loader.service.d/bugtux-lavd.conf"
I915_CONF="/etc/modprobe.d/bugtux-i915.conf"
MNT_DIR="/mnt/BugData"
SWAP_PRIO=5
ZRAM_PRIO=100

declare -A DNS_LABEL=( [0]="Cloudflare Malware Block" [1]="AdGuard" )
declare -A DNS4=(      [0]="1.1.1.2 1.0.0.2"          [1]="94.140.14.14 94.140.15.15" )
declare -A DNS6=(      [0]="2606:4700:4700::1112 2606:4700:4700::1002" [1]="2a10:50c0::ad1:ff 2a10:50c0::ad2:ff" )

cpu_content() {
    cat << 'EOF'
[Unit]
Description=BugTux CPU Performance Governor
After=multi-user.target
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c 'echo performance | tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor > /dev/null'
ExecStart=/bin/sh -c 'echo 0 | tee /sys/devices/system/cpu/cpu*/power/energy_perf_bias > /dev/null 2>&1 || true'
ExecStart=/bin/sh -c 'for f in /sys/devices/system/cpu/cpu*/power/pm_qos_resume_latency_us; do [ -f "$f" ] && echo 30 > "$f" 2>/dev/null || true; done'
[Install]
WantedBy=multi-user.target
EOF
}

status_cpu() {
    content_matches "$CPU_SERVICE" "$(cpu_content)" \
        && systemctl is-enabled --quiet bugtux-cpu.service 2>/dev/null \
        && echo OK || echo NO
}

apply_cpu() {
    systemctl mask --quiet power-profiles-daemon.service tlp.service 2>/dev/null || true
    if write_if_changed "$CPU_SERVICE" "$(cpu_content)"; then
        systemctl daemon-reload
        systemctl enable --now --quiet bugtux-cpu.service
        ok "CPU → performance + energy_perf_bias=0 + latência C-state=30µs"
    else
        systemctl enable --now --quiet bugtux-cpu.service 2>/dev/null || true
        skip "CPU Governor — já aplicado"
    fi
}

cpu_current_info() {
    local freq gov
    freq=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq 2>/dev/null || echo "")
    gov=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null || echo "?")
    [ -n "$freq" ] && echo "${gov} @ $(( freq / 1000 ))MHz" || echo "$gov"
}

sysctl_content() {
    cat << 'EOF'
vm.swappiness = 180
vm.vfs_cache_pressure = 50
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5
vm.max_map_count = 2147483642
vm.compaction_proactiveness = 0
vm.page-cluster = 0
vm.oom_dump_tasks = 0
kernel.sched_autogroup_enabled = 1
kernel.sched_migration_cost_ns = 500000
kernel.nmi_watchdog = 0
kernel.unprivileged_userns_clone = 1
kernel.numa_balancing = 0
kernel.perf_event_paranoid = 1
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
}

status_sysctl() {
    content_matches "$SYSCTL_FILE" "$(sysctl_content)" && echo OK || echo NO
}

apply_sysctl() {
    if write_if_changed "$SYSCTL_FILE" "$(sysctl_content)"; then
        sysctl --system -q 2>/dev/null || true
        ok "Kernel sysctl → swappiness=180, BBR, NUMA=off, compaction=0"
    else
        skip "Kernel sysctl — já aplicado"
    fi
}

scx_content() {
    cat << 'EOF'
[Service]
Environment="SCX_SCHEDULER=scx_lavd"
Environment="SCX_FLAGS=--performance"
EOF
}

status_scx() {
    if ! command -v scx_lavd &>/dev/null && ! [ -f /usr/lib/scx/scx_lavd ]; then echo NO; return; fi
    content_matches "$SCX_DROP" "$(scx_content)" && echo OK || echo NO
}

apply_scx() {
    if ! command -v scx_lavd &>/dev/null && ! [ -f /usr/lib/scx/scx_lavd ]; then
        fail "scx_lavd não encontrado — instale: sudo pacman -S scx-scheds"; return
    fi
    mkdir -p "$(dirname "$SCX_DROP")"
    if write_if_changed "$SCX_DROP" "$(scx_content)"; then
        systemctl daemon-reload
        systemctl restart scx_loader 2>/dev/null || true
        ok "scx_lavd → --performance via scx_loader"
    else
        local cur
        cur=$(busctl get-property org.scx.Loader /org/scx/Loader org.scx.Loader CurrentScheduler 2>/dev/null \
            | awk '{print $2}' | tr -d '"' || echo "?")
        skip "scx_lavd — já configurado (ativo: $cur)"
    fi
}

io_content() {
    cat << 'EOF'
[Unit]
Description=BugTux IO Scheduler
After=multi-user.target
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c 'for d in /sys/block/sd*; do rot=$(cat "$d/queue/rotational" 2>/dev/null||echo 1); [ "$rot" = "0" ] && echo mq-deadline>"$d/queue/scheduler" 2>/dev/null||true && echo 0>"$d/queue/add_random" 2>/dev/null||true && echo 2>"$d/queue/nomerges" 2>/dev/null||true; done; for d in /sys/block/nvme*; do echo none>"$d/queue/scheduler" 2>/dev/null||true; done'
[Install]
WantedBy=multi-user.target
EOF
}

status_io() {
    content_matches "$IO_SERVICE" "$(io_content)" \
        && systemctl is-enabled --quiet bugtux-io.service 2>/dev/null \
        && echo OK || echo NO
}

apply_io() {
    if write_if_changed "$IO_SERVICE" "$(io_content)"; then
        systemctl daemon-reload
        systemctl enable --now --quiet bugtux-io.service
        ok "IO Scheduler → mq-deadline (SSD SATA) / none (NVMe)"
    else
        systemctl enable --now --quiet bugtux-io.service 2>/dev/null || true
        skip "IO Scheduler — já aplicado"
    fi
}

_detect_gpu_vendor() {
    lspci 2>/dev/null | grep -iE "vga|3d controller" | head -1 | grep -io "intel\|amd\|nvidia" | head -1 | tr '[:upper:]' '[:lower:]'
}

gpu_content() {
    cat << 'EOF'
[Unit]
Description=BugTux GPU Performance
After=multi-user.target
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c 'for c in /sys/class/drm/card*/; do max=$(cat "${c}gt_RP0_freq_mhz" 2>/dev/null||echo ""); [ -z "$max" ] && continue; echo "$max">"${c}gt_min_freq_mhz" 2>/dev/null||true; echo "$max">"${c}gt_boost_freq_mhz" 2>/dev/null||true; echo on>"${c}../power/control" 2>/dev/null||true; done'
[Install]
WantedBy=multi-user.target
EOF
}

i915_content() {
    cat << 'EOF'
options i915 enable_guc=3 enable_dc=0 enable_fbc=0
EOF
}

status_gpu() {
    content_matches "$GPU_SERVICE" "$(gpu_content)" \
        && systemctl is-enabled --quiet bugtux-gpu.service 2>/dev/null \
        && echo OK || echo NO
}

status_gpu_opts() {
    local vendor; vendor=$(_detect_gpu_vendor)
    [ "$vendor" != "intel" ] && echo OK && return
    content_matches "$I915_CONF" "$(i915_content)" && echo OK || echo NO
}

apply_gpu() {
    if write_if_changed "$GPU_SERVICE" "$(gpu_content)"; then
        systemctl daemon-reload
        systemctl enable --now --quiet bugtux-gpu.service
        ok "GPU → freq fixada no máximo (RP0), runtime PM=on"
    else
        systemctl enable --now --quiet bugtux-gpu.service 2>/dev/null || true
        skip "GPU freq — já aplicado"
    fi
    local vendor; vendor=$(_detect_gpu_vendor)
    if [ "$vendor" = "intel" ]; then
        if write_if_changed "$I915_CONF" "$(i915_content)"; then
            ok "i915 → GuC=3, DC=0, FBC=0 (efeito no próximo boot)"
        else
            skip "i915 opções — já aplicado"
        fi
    fi
}

gpu_current_info() {
    local card cur max
    for card in /sys/class/drm/card*/; do
        cur=$(cat "${card}gt_cur_freq_mhz" 2>/dev/null || cat "${card}gt_act_freq_mhz" 2>/dev/null || echo "")
        max=$(cat "${card}gt_RP0_freq_mhz" 2>/dev/null || echo "")
        if [ -n "$cur" ]; then echo "${cur}MHz (máx ${max:-?}MHz)"; return; fi
    done
    echo "N/D"
}

thp_content() {
    cat << 'EOF'
[Unit]
Description=BugTux Transparent Hugepages
After=multi-user.target
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c 'echo madvise>/sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null||true'
ExecStart=/bin/sh -c 'echo defer+madvise>/sys/kernel/mm/transparent_hugepage/defrag 2>/dev/null||true'
ExecStart=/bin/sh -c 'echo 1>/sys/kernel/mm/transparent_hugepage/khugepaged/defrag 2>/dev/null||true'
[Install]
WantedBy=multi-user.target
EOF
}

status_thp() {
    content_matches "$THP_SERVICE" "$(thp_content)" \
        && systemctl is-enabled --quiet bugtux-thp.service 2>/dev/null \
        && echo OK || echo NO
}

thp_current() {
    cat /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null | grep -oP '\[\K[^\]]+' || echo "?"
}

apply_thp() {
    if write_if_changed "$THP_SERVICE" "$(thp_content)"; then
        systemctl daemon-reload
        systemctl enable --now --quiet bugtux-thp.service
        ok "THP → madvise + defrag=defer+madvise"
    else
        systemctl enable --now --quiet bugtux-thp.service 2>/dev/null || true
        skip "THP — já aplicado"
    fi
}

limits_content() {
    cat << 'EOF'
* soft nofile 1048576
* hard nofile 1048576
* soft memlock unlimited
* hard memlock unlimited
* soft stack unlimited
* hard stack unlimited
@audio - rtprio 98
@audio - memlock unlimited
@audio - nice -20
@realtime - rtprio 98
@realtime - memlock unlimited
EOF
}

status_limits() {
    content_matches "$LIMITS_FILE" "$(limits_content)" && echo OK || echo NO
}

apply_limits() {
    if write_if_changed "$LIMITS_FILE" "$(limits_content)"; then
        ok "System limits → nofile=1M, memlock=unlimited, rtprio=98"
    else
        skip "System limits — já aplicado"
    fi
}

zram_content() {
    local size="$1"
    cat << EOF
[Unit]
Description=BugTux ZRAM (${size})
After=local-fs.target
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/bash -c 'modprobe zram num_devices=1 2>/dev/null||true && echo 1>/sys/block/zram0/reset 2>/dev/null||true && zramctl --size ${size} --algorithm zstd /dev/zram0 && mkswap /dev/zram0 && swapon -p ${ZRAM_PRIO} /dev/zram0'
ExecStop=/usr/bin/bash -c 'swapoff /dev/zram0 2>/dev/null||true; echo 1>/sys/block/zram0/reset 2>/dev/null||true'
[Install]
WantedBy=multi-user.target
EOF
}

current_zram_size() {
    [ -f "$ZRAM_SERVICE" ] && grep -oP '(?<=--size )\S+' "$ZRAM_SERVICE" 2>/dev/null | head -1 || echo "—"
}

zram_current_stats() {
    swapon --show --noheadings --raw 2>/dev/null | grep -q zram0 \
        && echo "ativo · $(zramctl --output NAME,DATA /dev/zram0 2>/dev/null | tail -1 | awk '{print "dados="$2}')" \
        || echo "inativo"
}

status_zram() {
    [ -f "$ZRAM_SERVICE" ] || { echo NO; return; }
    systemctl is-enabled --quiet bugtux-zram.service 2>/dev/null || { echo NO; return; }
    swapon --show --noheadings --raw 2>/dev/null | grep -q zram0 && echo OK || echo PARTIAL
}

_zram_auto_size() {
    local gb=$(( $(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}') / 1024 / 1024 ))
    [ "$gb" -le 4 ] && echo "2G" && return
    [ "$gb" -le 8 ] && echo "4G" && return
    [ "$gb" -le 16 ] && echo "8G" && return
    echo "12G"
}

apply_zram_default() {
    [ "$(status_zram)" = "OK" ] && { skip "ZRAM — já ativo em $(current_zram_size)"; return; }
    local size; size=$(_zram_auto_size)
    write_if_changed "$ZRAM_SERVICE" "$(zram_content "$size")"
    systemctl daemon-reload
    systemctl enable --quiet bugtux-zram.service 2>/dev/null || true
    systemctl restart bugtux-zram.service 2>/dev/null || true
    ok "ZRAM → ${size} (auto, zstd, prioridade ${ZRAM_PRIO})"
}

apply_zram_interactive() {
    local cur idx
    cur=$(current_zram_size)
    idx=$(select_menu "ZRAM atual: ${cur} — Selecione o tamanho:" \
        "4G" "6G" "8G (recomendado 12GB RAM)" "12G")
    [[ "$idx" == "BACK" ]] && { skip "ZRAM — cancelado"; return; }
    local sizes=("4G" "6G" "8G" "12G")
    local size="${sizes[$idx]}"
    write_if_changed "$ZRAM_SERVICE" "$(zram_content "$size")"
    systemctl daemon-reload
    systemctl enable --quiet bugtux-zram.service 2>/dev/null || true
    systemctl restart bugtux-zram.service 2>/dev/null || true
    ok "ZRAM → ${size} (zstd, prioridade ${ZRAM_PRIO})"
}

_detect_root_disk() {
    local dev
    dev=$(findmnt -n -o SOURCE / 2>/dev/null || echo "")
    local disk
    disk=$(lsblk -no PKNAME "$dev" 2>/dev/null || echo "")
    [ -z "$disk" ] && disk=$(echo "$dev" | sed 's/[0-9]*$//;s/p$//')
    [[ "$disk" != /dev/* ]] && disk="/dev/$disk"
    echo "$disk"
}

_detect_secondary_disk() {
    local root_disk
    root_disk=$(_detect_root_disk)
    local disk
    while IFS= read -r disk; do
        [[ "$disk" == "$root_disk" ]] && continue
        echo "$disk"; return 0
    done < <(lsblk -dno NAME,TYPE 2>/dev/null | awk '$2=="disk"{print "/dev/"$1}')
    return 1
}

status_swap_ssd() {
    if swapon --show --noheadings --raw 2>/dev/null | awk '{print $1}' | grep -qv zram; then
        echo OK; return
    fi
    grep -qE '^UUID.*none.*swap' /etc/fstab 2>/dev/null && echo PARTIAL || echo NO
}

apply_swap_auto() {
    if [ "$(status_swap_ssd)" = "OK" ]; then
        skip "Swap SSD 🖴 — já ativo"
        return
    fi

    local TARGET_DISK
    if ! TARGET_DISK=$(_detect_secondary_disk); then
        warn "Swap SSD 🖴 — nenhum disco secundário detectado automaticamente"
        return
    fi

    local model size
    model=$(lsblk -dno MODEL "$TARGET_DISK" 2>/dev/null | xargs || echo "SSD")
    size=$(lsblk  -dno SIZE  "$TARGET_DISK" 2>/dev/null | xargs || echo "?")

    local existing_swap
    existing_swap=$(lsblk -no NAME,TYPE "$TARGET_DISK" 2>/dev/null \
        | awk '$2=="part"{print "/dev/"$1}' | while read -r p; do
            [ "$(blkid -s TYPE -o value "$p" 2>/dev/null)" = "swap" ] && echo "$p" && break
        done)

    if [ -n "$existing_swap" ]; then
        swapon -p "$SWAP_PRIO" "$existing_swap" 2>/dev/null || true
        local uuid
        uuid=$(blkid -s UUID -o value "$existing_swap" 2>/dev/null || echo "")
        if [ -n "$uuid" ] && ! grep -q "$uuid" /etc/fstab 2>/dev/null; then
            echo "UUID=$uuid none swap defaults,pri=$SWAP_PRIO 0 0" >> /etc/fstab
        fi
        ok "Swap SSD 🖴 — partição existente ativada ($existing_swap)"
        return
    fi

    local ram_gb; ram_gb=$(( $(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024 / 1024 ))
    local swap_size=8
    [ "$ram_gb" -le 4  ] && swap_size=4
    [ "$ram_gb" -le 8  ] && swap_size=4
    [ "$ram_gb" -gt 16 ] && swap_size=16

    step "Swap auto: $TARGET_DISK ($model $size) → ${swap_size}GiB + dados XFS"

    local PART_SWAP="${TARGET_DISK}1" PART_DATA="${TARGET_DISK}2"
    [[ "$TARGET_DISK" == *nvme* ]] && PART_SWAP="${TARGET_DISK}p1" && PART_DATA="${TARGET_DISK}p2"

    while IFS= read -r active; do
        [ -n "$active" ] && swapoff "$active" 2>/dev/null || true
    done < <(swapon --show --noheadings --raw 2>/dev/null | awk '{print $1}')
    umount -fl "${TARGET_DISK}"* 2>/dev/null || true
    wipefs -a "$TARGET_DISK" 2>/dev/null || true
    sgdisk --zap-all "$TARGET_DISK" &>/dev/null || true
    parted -a optimal -s "$TARGET_DISK" mklabel gpt 2>/dev/null
    parted -a optimal -s "$TARGET_DISK" mkpart primary linux-swap 0% "${swap_size}GiB" 2>/dev/null
    parted -a optimal -s "$TARGET_DISK" mkpart primary xfs "${swap_size}GiB" 100% 2>/dev/null
    udevadm settle; partprobe "$TARGET_DISK" 2>/dev/null || true; sleep 2; udevadm settle

    if ! [ -b "$PART_SWAP" ]; then
        fail "Swap SSD 🖴 — falha ao criar partição em $TARGET_DISK"; return
    fi

    mkswap -f -L "BugSwap" "$PART_SWAP" >/dev/null 2>&1 || { fail "Falha mkswap"; return; }
    swapon -p "$SWAP_PRIO" "$PART_SWAP" 2>/dev/null || { fail "Falha swapon"; return; }

    if [ -b "$PART_DATA" ]; then
        mkfs.xfs -f -L "BugData" "$PART_DATA" >/dev/null 2>&1 || true
        mkdir -p "$MNT_DIR"
        mount -t xfs "$PART_DATA" "$MNT_DIR" 2>/dev/null || true
    fi

    cp /etc/fstab /etc/fstab.bak.bugtux 2>/dev/null || true
    grep -v -E '^[^#].*[[:space:]]swap[[:space:]]' /etc/fstab | grep -v "$MNT_DIR" > /tmp/_fstab_bug
    mv /tmp/_fstab_bug /etc/fstab
    local UUID_SWAP UUID_DATA
    UUID_SWAP=$(blkid -s UUID -o value "$PART_SWAP" 2>/dev/null || echo "")
    UUID_DATA=$(blkid -s UUID -o value "$PART_DATA" 2>/dev/null || echo "")
    [ -n "$UUID_SWAP" ] && echo "UUID=$UUID_SWAP none swap defaults,pri=$SWAP_PRIO 0 0" >> /etc/fstab
    [ -n "$UUID_DATA" ] && [ -b "$PART_DATA" ] && \
        echo "UUID=$UUID_DATA $MNT_DIR xfs defaults,noatime,rw,user,nofail 0 2" >> /etc/fstab
    chmod 775 "$MNT_DIR" 2>/dev/null || true; own_back "$MNT_DIR"

    ok "Swap SSD 🖴 → ${swap_size}GiB ativo em $PART_SWAP (prioridade $SWAP_PRIO)"
}

setup_swap_partition() {
    local ROOT_DISK; ROOT_DISK=$(_detect_root_disk)
    mapfile -t RAW_DISKS < <(lsblk -dno NAME,TYPE 2>/dev/null | awk '$2=="disk"{print "/dev/"$1}')
    local DISKS_AVAILABLE=() DISKS_LABELS=()
    for disk in "${RAW_DISKS[@]}"; do
        [[ "$disk" == "$ROOT_DISK" ]] && continue
        local m s
        m=$(lsblk -dno MODEL "$disk" 2>/dev/null | xargs); s=$(lsblk -dno SIZE "$disk" 2>/dev/null | xargs)
        DISKS_AVAILABLE+=("$disk"); DISKS_LABELS+=("$disk — ${m:-SSD} ($s)")
    done
    [ "${#DISKS_AVAILABLE[@]}" -eq 0 ] && { fail "Nenhum SSD 🖴 secundário encontrado."; return; }

    local DISK_IDX
    DISK_IDX=$(select_menu "Selecione o SSD 🖴 para Swap:" "${DISKS_LABELS[@]}")
    [[ "$DISK_IDX" == "BACK" ]] && return
    local TARGET_DISK="${DISKS_AVAILABLE[$DISK_IDX]}"

    local SIZES=("4GiB" "8GiB" "12GiB" "16GiB" "24GiB" "32GiB" "48GiB" "64GiB")
    local SIZE_IDX
    SIZE_IDX=$(select_menu "Tamanho da partição Swap em $TARGET_DISK:" "${SIZES[@]}")
    [[ "$SIZE_IDX" == "BACK" ]] && return
    local TARGET_SIZE="${SIZES[$SIZE_IDX]//GiB/}"

    local CONFIRM
    CONFIRM=$(confirm_dialog "⚠ APAGA TODOS OS DADOS em $TARGET_DISK. Confirmar?")
    [[ "$CONFIRM" != "0" ]] && { skip "Cancelado"; return; }

    header; hdr "PARTICIONANDO $TARGET_DISK — ${TARGET_SIZE}GiB Swap"

    local PART_SWAP="${TARGET_DISK}1" PART_DATA="${TARGET_DISK}2"
    [[ "$TARGET_DISK" == *nvme* ]] && PART_SWAP="${TARGET_DISK}p1" && PART_DATA="${TARGET_DISK}p2"

    progress 15 "Preparando disco..."; echo
    while IFS= read -r active; do
        [ -n "$active" ] && swapoff "$active" 2>/dev/null || true
    done < <(swapon --show --noheadings --raw 2>/dev/null | awk '{print $1}')
    umount -fl "${TARGET_DISK}"* 2>/dev/null || true
    wipefs -a "$TARGET_DISK" 2>/dev/null || true
    sgdisk --zap-all "$TARGET_DISK" &>/dev/null || true

    progress 30 "Particionando..."; echo
    parted -a optimal -s "$TARGET_DISK" mklabel gpt 2>/dev/null
    parted -a optimal -s "$TARGET_DISK" mkpart primary linux-swap 0% "${TARGET_SIZE}GiB" 2>/dev/null
    parted -a optimal -s "$TARGET_DISK" mkpart primary xfs "${TARGET_SIZE}GiB" 100% 2>/dev/null
    udevadm settle; partprobe "$TARGET_DISK" 2>/dev/null || true; sleep 3; udevadm settle

    ! [ -b "$PART_SWAP" ] && { fail "Erro ao criar partições."; return; }

    progress 60 "Formatando swap..."; echo
    mkswap -f -L "BugSwap" "$PART_SWAP" >/dev/null || { fail "Falha mkswap"; return; }
    swapon -p "$SWAP_PRIO" "$PART_SWAP" || { fail "Falha swapon"; return; }

    progress 75 "Formatando dados (XFS)..."; echo
    mkfs.xfs -f -L "BugData" "$PART_DATA" >/dev/null 2>&1 || true
    mkdir -p "$MNT_DIR"; mount -t xfs "$PART_DATA" "$MNT_DIR" 2>/dev/null || true

    progress 90 "Atualizando fstab..."; echo
    cp /etc/fstab /etc/fstab.bak.bugtux 2>/dev/null || true
    grep -v -E '^[^#].*[[:space:]]swap[[:space:]]' /etc/fstab | grep -v "$MNT_DIR" > /tmp/_fstab_bug
    mv /tmp/_fstab_bug /etc/fstab
    local UUID_SWAP UUID_DATA
    UUID_SWAP=$(blkid -s UUID -o value "$PART_SWAP" 2>/dev/null || echo "")
    UUID_DATA=$(blkid -s UUID -o value "$PART_DATA" 2>/dev/null || echo "")
    [ -n "$UUID_SWAP" ] && echo "UUID=$UUID_SWAP none swap defaults,pri=$SWAP_PRIO 0 0" >> /etc/fstab
    [ -n "$UUID_DATA" ] && echo "UUID=$UUID_DATA $MNT_DIR xfs defaults,noatime,rw,user,nofail 0 2" >> /etc/fstab
    chmod 775 "$MNT_DIR"; own_back "$MNT_DIR"

    progress 100 "Concluído!"; echo
    ok "Swap ${TARGET_SIZE}GiB → $PART_SWAP (prioridade $SWAP_PRIO)"
    ok "Dados → $MNT_DIR (XFS)"
    echo; swapon --show
    pause
}

dns_conf_content() {
    printf '[global-dns-domain-*]\nservers=%s,%s' "${DNS4[$1]// /,}" "${DNS6[$1]// /,}"
}

status_dns() {
    [ -f "$DNS_CONF" ] || { echo NO; return; }
    local i; for i in 0 1; do content_matches "$DNS_CONF" "$(dns_conf_content "$i")" && echo OK && return; done
    echo NO
}

apply_dns_default() {
    [ "$(status_dns)" = "OK" ] && { skip "DNS — já configurado"; return; }
    local content; content="$(dns_conf_content "0")"
    mkdir -p "$(dirname "$DNS_CONF")"
    printf '%s\n' "$content" > "$DNS_CONF"
    local d4="${DNS4[0]}" d6="${DNS6[0]}"
    while IFS= read -r conn; do
        [ -z "$conn" ] || [ "$conn" = "lo" ] && continue
        nmcli connection modify "$conn" ipv4.ignore-auto-dns yes ipv4.dns "$d4" \
            ipv6.ignore-auto-dns yes ipv6.dns "$d6" 2>/dev/null || true
    done < <(nmcli -g NAME connection show 2>/dev/null)
    systemctl restart NetworkManager 2>/dev/null || true
    ok "DNS → ${DNS_LABEL[0]} (automático)"
}

apply_dns_interactive() {
    local idx
    idx=$(select_menu "Selecione o DNS:" \
        "${DNS_LABEL[0]}  (1.1.1.2 / 1.0.0.2)" \
        "${DNS_LABEL[1]}  (94.140.14.14 / 94.140.15.15)" \
        "Pular / Voltar")
    [[ "$idx" == "BACK" || "$idx" == "2" ]] && { skip "DNS — pulado"; return; }
    local content; content="$(dns_conf_content "$idx")"
    content_matches "$DNS_CONF" "$content" && { skip "DNS (${DNS_LABEL[$idx]}) — já aplicado"; return; }
    mkdir -p "$(dirname "$DNS_CONF")"
    printf '%s\n' "$content" > "$DNS_CONF"
    local d4="${DNS4[$idx]}" d6="${DNS6[$idx]}"
    while IFS= read -r conn; do
        [ -z "$conn" ] || [ "$conn" = "lo" ] && continue
        nmcli connection modify "$conn" ipv4.ignore-auto-dns yes ipv4.dns "$d4" \
            ipv6.ignore-auto-dns yes ipv6.dns "$d6" 2>/dev/null || true
    done < <(nmcli -g NAME connection show 2>/dev/null)
    systemctl restart NetworkManager 2>/dev/null || true
    ok "DNS → ${DNS_LABEL[$idx]} (${d4// /,})"
}

apply_all_core() {
    header
    hdr "APLICANDO TODAS AS OTIMIZAÇÕES"
    echo

    local -a STEPS=( apply_cpu apply_sysctl apply_scx apply_io apply_gpu apply_thp apply_limits apply_zram_default apply_dns_default apply_swap_auto )
    local -a LABELS=( "CPU Governor" "Kernel sysctl" "SCX Scheduler" "IO Scheduler" "GPU Performance" "Hugepages (THP)" "System Limits" "ZRAM" "DNS" "Swap SSD" )
    local total=${#STEPS[@]} i=0 fn label

    for fn in "${STEPS[@]}"; do
        label="${LABELS[$i]}"
        i=$(( i + 1 ))
        progress "$(( i * 100 / total ))" "$label"
        echo
        "$fn"
    done

    echo
    sep
    hdr "RESUMO"
    printf "  %-22s %s\n" "CPU Governor"   "$(tag "$(status_cpu)")"
    printf "  %-22s %s\n" "Kernel sysctl"  "$(tag "$(status_sysctl)")"
    printf "  %-22s %s\n" "SCX Scheduler"  "$(tag "$(status_scx)")"
    printf "  %-22s %s\n" "IO Scheduler"   "$(tag "$(status_io)")"
    printf "  %-22s %s\n" "GPU Performance" "$(tag "$(status_gpu)")"
    printf "  %-22s %s\n" "THP"            "$(tag "$(status_thp)")"
    printf "  %-22s %s\n" "System Limits"  "$(tag "$(status_limits)")"
    printf "  %-22s %s  (%s)\n" "ZRAM" "$(tag "$(status_zram)")" "$(current_zram_size)"
    printf "  %-22s %s\n" "DNS"            "$(tag "$(status_dns)")"
    printf "  %-22s %s\n" "Swap SSD"       "$(tag "$(status_swap_ssd)")"
    sep
    pause
}

show_performance_status() {
    header; hdr "STATUS DE PERFORMANCE"; sep
    printf "  %-22s %s\n" "CPU Governor"   "$(tag "$(status_cpu)")"
    printf "  %-22s %s\n" "Kernel sysctl"  "$(tag "$(status_sysctl)")"
    printf "  %-22s %s\n" "SCX Scheduler"  "$(tag "$(status_scx)")"
    printf "  %-22s %s\n" "IO Scheduler"   "$(tag "$(status_io)")"
    printf "  %-22s %s\n" "GPU Performance" "$(tag "$(status_gpu)")"
    printf "  %-22s %s\n" "i915 opções"    "$(tag "$(status_gpu_opts)")"
    printf "  %-22s %s\n" "THP"            "$(tag "$(status_thp)")"
    printf "  %-22s %s\n" "System Limits"  "$(tag "$(status_limits)")"
    printf "  %-22s %s  (%s)\n" "ZRAM" "$(tag "$(status_zram)")" "$(current_zram_size)"
    printf "  %-22s %s\n" "Swap SSD"       "$(tag "$(status_swap_ssd)")"
    printf "  %-22s %s\n" "DNS"            "$(tag "$(status_dns)")"
    sep; hdr "TEMPO REAL"
    printf "  %-22s %s\n" "CPU"      "$(cpu_current_info)"
    printf "  %-22s %s\n" "GPU"      "$(gpu_current_info)"
    printf "  %-22s %s\n" "ZRAM"     "$(zram_current_stats)"
    printf "  %-22s %s\n" "THP modo" "$(thp_current)"
    printf "  %-22s %s\n" "Kernel"   "$(uname -r)"
    local iosched
    iosched=$(cat /sys/block/sda/queue/scheduler 2>/dev/null | grep -oP '\[\K[^\]]+' \
           || cat /sys/block/nvme0n1/queue/scheduler 2>/dev/null | grep -oP '\[\K[^\]]+' || echo "?")
    printf "  %-22s %s\n" "IO sched" "$iosched"
    sep; pause
}

performance_menu() {
    while true; do
        local choice
        choice=$(select_menu "Performance — CPU/Kernel/IO/GPU/THP/ZRAM/SWAP/DNS" \
            "Status de Performance (tempo real)" \
            "Aplicar TUDO Elite" \
            "ZRAM (manual)" \
            "Swap SSD (manual)" \
            "DNS (manual)" \
            "Voltar")
        case "$choice" in
            "BACK"|5) return ;;
            0) show_performance_status ;;
            1) apply_all_core ;;
            2) apply_zram_interactive; pause ;;
            3) setup_swap_partition ;;
            4) apply_dns_interactive; pause ;;
        esac
    done
}

DOTFILES_DIR="$REAL_HOME/BugTheme-dotfiles"
BACKUP_DIR="$DOTFILES_DIR/files"
BASELINE_DIR="$DOTFILES_DIR/.baseline"
META_FILE="$BACKUP_DIR/.meta"

KDE_CONFIG_PATTERNS=(
    "k*rc" "k*rc.*" "plasma*" "kde*" "kwin*" "kscreen*" "baloo*"
    "dolphin*" "konsole*" "okular*" "kate*" "spectacle*" "gwenview*"
    "elisa*" "discover*" "akonadi*" "kmail*" "korgac*" "krunner*"
    "khotkeys*" "kded*" "bluedevil*" "powerdevil*" "ksmserver*"
    "systemsettings*" "kcm*" "Trolltech.conf" "breezerc" "auroraerc"
    "fontconfig" "gtk-3.0" "gtk-4.0"
)
KDE_LOCAL_PATHS=(
    "$REAL_HOME/.local/share/plasma"     "$REAL_HOME/.local/share/color-schemes"
    "$REAL_HOME/.local/share/icons"      "$REAL_HOME/.local/share/konsole"
    "$REAL_HOME/.local/share/kwin"       "$REAL_HOME/.local/share/aurorae"
    "$REAL_HOME/.local/share/wallpapers" "$REAL_HOME/.local/share/fonts"
    "$REAL_HOME/.local/share/kservices5" "$REAL_HOME/.local/share/kservices6"
    "$REAL_HOME/.local/share/plasmoids"  "$REAL_HOME/.local/share/kpackage"
)
EXCLUDE_PATTERNS=(
    "*.lock" "*.socket" "*.pid" "*.log" "*.tmp" "*.bak"
    "cache" "Cache" "cachedir" "CacheStorage"
    "crash*" "Crash*" "drkonqi*" "recently-used*" "recently_used*"
    "session*" "Session*" "kactivitymanagerd*" "*.sqlite-wal" "*.sqlite-shm"
    "gvfs*" "dconf"
)
SHELL_FILES=(".zshrc" ".p10k.zsh" ".bashrc" ".bash_profile" ".profile")

_matches_exclude() {
    local file; file=$(basename "$1")
    local pat; for pat in "${EXCLUDE_PATTERNS[@]}"; do [[ "$file" == $pat ]] && return 0; done
    [[ "$1" == *"/cache/"* || "$1" == *"/Cache/"* || "$1" == *"/.cache/"* ]] && return 0
    return 1
}

_matches_kde_pattern() {
    local file; file=$(basename "$1")
    local pat; for pat in "${KDE_CONFIG_PATTERNS[@]}"; do [[ "$file" == $pat ]] && return 0; done
    return 1
}

_collect_config_files() {
    local results=() f
    while IFS= read -r -d '' f; do
        _matches_exclude "$f" && continue
        _matches_kde_pattern "$f" && results+=("$f")
    done < <(find "$REAL_HOME/.config" -maxdepth 3 -type f -print0 2>/dev/null)
    [ "${#results[@]}" -gt 0 ] && printf '%s\n' "${results[@]}"
}

_collect_local_dirs() {
    local results=() path
    for path in "${KDE_LOCAL_PATHS[@]}"; do
        [[ -d "$path" ]] && results+=("$path")
    done
    [ "${#results[@]}" -gt 0 ] && printf '%s\n' "${results[@]}"
}

_file_hash()        { sha256sum "$1" 2>/dev/null | cut -d' ' -f1; }
_relative_to_home() { echo "${1/#$REAL_HOME\//}"; }
_baseline_path()    { echo "$BASELINE_DIR/$(_relative_to_home "$1").sha256"; }

_is_modified() {
    local bpath; bpath=$(_baseline_path "$1")
    [ ! -f "$bpath" ] && return 0
    [ "$(_file_hash "$1")" != "$(cat "$bpath")" ] && return 0
    return 1
}

generate_baseline() {
    header; hdr "Gerando Baseline..."
    mkdir -p "$BASELINE_DIR"
    mapfile -t config_files < <(_collect_config_files)
    local total=${#config_files[@]} count=0 f bpath
    for f in "${config_files[@]}"; do
        count=$(( count + 1 ))
        progress_item "$count" "$total" "Analisando: $(basename "$f")"
        bpath=$(_baseline_path "$f")
        mkdir -p "$(dirname "$bpath")"
        _file_hash "$f" > "$bpath"
    done
    progress_done
    date '+%Y-%m-%d %H:%M:%S' > "$BASELINE_DIR/.generated"
    own_back "$DOTFILES_DIR"
    ok "Baseline gerado — $count arquivos"
}

backup() {
    header; hdr "Backup Inteligente KDE"
    local has_baseline=true
    [ ! -d "$BASELINE_DIR" ] && has_baseline=false && warn "Sem baseline — salvando tudo..."
    mkdir -p "$BACKUP_DIR"
    local saved=0 skipped=0 timestamp; timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    mapfile -t config_files < <(_collect_config_files)
    local total=${#config_files[@]} current=0 f rel dst
    for f in "${config_files[@]}"; do
        current=$(( current + 1 ))
        rel=$(_relative_to_home "$f")
        progress_item "$current" "$total" "Lendo: $rel"
        if [[ "$has_baseline" == true ]] && ! _is_modified "$f"; then
            skipped=$(( skipped + 1 )); continue
        fi
        dst="$BACKUP_DIR/$rel"; mkdir -p "$(dirname "$dst")"
        if [ ! -f "$dst" ] || ! cmp -s "$f" "$dst"; then
            printf "\r\033[K"; ok "Atualizado: $rel"
            cp "$f" "$dst"; saved=$(( saved + 1 ))
        else
            skipped=$(( skipped + 1 ))
        fi
    done
    progress_done

    mapfile -t local_dirs < <(_collect_local_dirs)
    local total_dirs=${#local_dirs[@]} cur_dir=0 dir
    for dir in "${local_dirs[@]}"; do
        cur_dir=$(( cur_dir + 1 ))
        progress_item "$cur_dir" "$total_dirs" "Sync: $(basename "$dir")/"
        dst="$BACKUP_DIR/$(_relative_to_home "$dir")"; mkdir -p "$dst"
        rsync -a --delete "$dir/" "$dst/" 2>/dev/null || true
    done
    progress_done

    local sf full
    for sf in "${SHELL_FILES[@]}"; do
        full="$REAL_HOME/$sf"; [ ! -f "$full" ] && continue
        dst="$BACKUP_DIR/$sf"
        if [ ! -f "$dst" ] || ! cmp -s "$full" "$dst"; then
            ok "Shell: $sf"; cp "$full" "$dst"; saved=$(( saved + 1 ))
        fi
    done

    printf 'timestamp=%s\nsaved=%d\nskipped=%d\nbaseline=%s\n' \
        "$timestamp" "$saved" "$skipped" "$has_baseline" > "$META_FILE"
    own_back "$DOTFILES_DIR"
    sep; ok "Backup concluído — Salvos: ${saved}  |  Intactos: ${skipped}"
    pause
}

restore_kde() {
    if [ ! -d "$BACKUP_DIR" ]; then header; warn "Nenhum backup em $BACKUP_DIR"; pause; return; fi
    local step=1
    while true; do
        if [ "$step" -eq 1 ]; then
            local c1; c1=$(confirm_dialog "Restaurar configurações completas do KDE?")
            [[ "$c1" == "BACK" || "$c1" == "1" ]] && return; step=2
        else
            local c2; c2=$(confirm_dialog "Tem certeza? O Plasma será reiniciado.")
            [[ "$c2" == "BACK" ]] && { step=1; continue; }; [[ "$c2" == "1" ]] && return; break
        fi
    done
    header; hdr "Restaurando KDE..."
    [ -f "$META_FILE" ] && log "Backup: $(grep '^timestamp=' "$META_FILE" 2>/dev/null | cut -d= -f2-)"
    progress 20 "Restaurando .config..."; echo
    [ -d "$BACKUP_DIR/.config" ] && rsync -a "$BACKUP_DIR/.config/" "$REAL_HOME/.config/" 2>/dev/null || true
    progress 55 "Restaurando .local/share..."; echo
    [ -d "$BACKUP_DIR/.local" ] && rsync -a "$BACKUP_DIR/.local/" "$REAL_HOME/.local/" 2>/dev/null || true
    progress 80 "Shell files..."; echo
    for sf in "${SHELL_FILES[@]}"; do
        [ -f "$BACKUP_DIR/$sf" ] && cp "$BACKUP_DIR/$sf" "$REAL_HOME/$sf" && ok "~/$sf"
    done
    progress 95 "Permissões..."; echo
    own_back "$REAL_HOME/.config" "$REAL_HOME/.local/share" \
        "$REAL_HOME/.zshrc" "$REAL_HOME/.p10k.zsh" \
        "$REAL_HOME/.bashrc" "$REAL_HOME/.bash_profile" "$REAL_HOME/.profile" 2>/dev/null || true
    progress 100 "Aplicando ao Plasma..."; echo
    rebuild_kde_cache
    run_as_user plasmashell --replace &>/dev/null & disown
    ok "Restauração concluída. Plasma reiniciando..."
    pause
}

backup_status() {
    header; hdr "Status do Backup KDE"; sep
    [ -f "$BASELINE_DIR/.generated" ] && ok "Baseline: $(cat "$BASELINE_DIR/.generated")" || warn "Baseline: não gerado"
    if [ -f "$META_FILE" ]; then
        local key val
        while IFS='=' read -r key val; do
            case "$key" in timestamp) log "Último backup : $val" ;; saved) log "Salvos : $val" ;; esac
        done < "$META_FILE"
        log "Tamanho: $(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)"
    else
        warn "Nenhum backup realizado."
    fi
    sep; pause
}

status_backup_tag() { [ -f "$META_FILE" ] && echo OK || echo NO; }

backup_menu() {
    while true; do
        local choice
        choice=$(select_menu "Backup & Restore KDE Plasma" \
            "Realizar Backup" "Restaurar Backup" "Status e Detalhes" "Gerar Baseline" "Voltar")
        case "$choice" in
            "BACK"|4) return ;;
            0) backup ;; 1) restore_kde ;; 2) backup_status ;; 3) generate_baseline; pause ;;
        esac
    done
}

ZSHRC_PATH="$REAL_HOME/.zshrc"
ZSHRC_BACKUP_PATH="$REAL_HOME/.zshrc.bugtuxp.bak"
ZSH_DEPS=(fzf fd bat procs btop)

zshrc_content() {
    cat << 'EOF'
typeset -g POWERLEVEL9K_INSTANT_PROMPT=off

if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"
plugins=(git zsh-autosuggestions zsh-syntax-highlighting)
source "$ZSH/oh-my-zsh.sh"
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

HISTSIZE=10000; SAVEHIST=10000; HISTFILE=~/.zsh_history
setopt APPEND_HISTORY SHARE_HISTORY HIST_IGNORE_DUPS HIST_IGNORE_ALL_DUPS
setopt HIST_FIND_NO_DUPS HIST_IGNORE_SPACE HIST_SAVE_NO_DUPS INC_APPEND_HISTORY

bindkey -v; export KEYTIMEOUT=1

function zle-keymap-select {
  [[ ${KEYMAP} == vicmd ]] || [[ $1 = 'block' ]] && echo -ne '\e[1 q' || echo -ne '\e[5 q'
}
zle -N zle-keymap-select
zle-line-init() { zle -K viins; echo -ne "\e[5 q"; }
zle -N zle-line-init

bindkey '^L' clear-screen; bindkey '^R' history-incremental-search-backward
bindkey '^A' beginning-of-line; bindkey '^E' end-of-line; bindkey '^K' kill-line
bindkey '^U' kill-whole-line; bindkey '^W' backward-kill-word
bindkey '^n' autosuggest-accept; bindkey '^j' autosuggest-accept
bindkey '^[^?' backward-kill-word

if command -v fzf &>/dev/null; then
    source <(fzf --zsh)
    export FZF_DEFAULT_OPTS='--color=16,bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8 --color=fg:#cdd6f4,header:#f38ba8,info:#cba6f7,marker:#f5e0dc --color=fg+:#cdd6f4,preview-bg:#313244,prompt:#cba6f7,pointer:#f5e0dc'
fi

alias ll='ls -lAhS'; alias la='ls -lah'; alias l='ls -CF'; alias cl='clear'
alias update='sudo pacman -Syu'; alias install='sudo pacman -S'; alias remove='sudo pacman -R'
alias search='pacman -Ss'; alias clean='sudo pacman -Sc'
alias autoremove='sudo pacman -Rs $(pacman -Qdtq)'
alias v='nvim'; alias vi='nvim'; alias vim='nvim'
alias ..='cd ..'; alias ...='cd ../..'; alias ....='cd ../../..'
alias mkdir='mkdir -pv'; alias cp='cp -iv'; alias mv='mv -iv'; alias rm='rm -iv'
alias grep='grep --color=auto'; alias diff='diff --color=auto'
alias du='du -h'; alias df='df -h'; alias free='free -h'
alias top='btop'; alias cat='bat'; alias find='fd'; alias ps='procs'
alias bug='cd ~'; alias desktop='cd ~/Desktop'; alias downloads='cd ~/Downloads'
alias documents='cd ~/Documents'; alias config='cd ~/.config'
alias dotfiles='cd ~/BugTheme-dotfiles'
alias gs='git status'; alias ga='git add'; alias gc='git commit -m'
alias gp='git push'; alias gl='git log --oneline -10'

extract() {
    [ -f "$1" ] || { echo "'$1' não é um arquivo"; return 1; }
    case "$1" in
        *.tar.bz2) tar xjf "$1" ;; *.tar.gz) tar xzf "$1" ;; *.bz2) bunzip2 "$1" ;;
        *.rar) unrar x "$1" ;; *.gz) gunzip "$1" ;; *.tar) tar xf "$1" ;;
        *.tbz2) tar xjf "$1" ;; *.tgz) tar xzf "$1" ;; *.zip) unzip "$1" ;;
        *.Z) uncompress "$1" ;; *.7z) 7z x "$1" ;; *.xz) xz -d "$1" ;;
        *) echo "Não sei extrair '$1'" ;;
    esac
}
mkcd()   { mkdir -p "$1" && cd "$1"; }
f()      { fd -i "*$1*" . 2>/dev/null; }
dush()   { du -sh "$@" | sort -h; }
killp()  { pkill -f "$1"; }
weather(){ curl -s "wttr.in/${1:-Curitiba}?format=3"; }

bugfetch() {
    echo -e "\e[34m❯ Bug FastFetch\e[0m"; echo
    fastfetch --logo arch2 --logo-color-1 "34" --logo-color-2 "34" --color-title "34" --color-keys "34"
    echo
}
alias fastfetch='bugfetch'; alias ff='bugfetch'
ff
EOF
}

status_zsh() {
    [ ! -f "$ZSHRC_PATH" ] && { echo NO; return; }
    [ "$(cat "$ZSHRC_PATH" 2>/dev/null)" = "$(zshrc_content)" ] && echo OK || echo PARTIAL
}

apply_zsh() {
    header; hdr "Terminal Zsh Elite"
    [ ! -d "$REAL_HOME/.oh-my-zsh" ] && warn "oh-my-zsh não encontrado — instale antes."
    [ "$(status_zsh)" = "OK" ] && { skip ".zshrc já aplicado."; pause; return; }
    local conf; conf=$(confirm_dialog "Sobrescrever ~/.zshrc? (backup em .zshrc.bugtuxp.bak)")
    [[ "$conf" != "0" ]] && { skip "Cancelado"; pause; return; }
    step "Instalando dependências..."; install_pkgs "${ZSH_DEPS[@]}"
    [ -f "$ZSHRC_PATH" ] && cp "$ZSHRC_PATH" "$ZSHRC_BACKUP_PATH" && ok "Backup → ~/.zshrc.bugtuxp.bak"
    zshrc_content > "$ZSHRC_PATH"
    own_back "$ZSHRC_PATH" "$ZSHRC_BACKUP_PATH"
    ok ".zshrc elite aplicado. Feche e abra o Konsole."; pause
}

restore_zsh_backup() {
    [ ! -f "$ZSHRC_BACKUP_PATH" ] && { warn "Sem backup (~/.zshrc.bugtuxp.bak)."; pause; return; }
    local conf; conf=$(confirm_dialog "Restaurar .zshrc do backup?")
    [[ "$conf" != "0" ]] && { skip "Cancelado"; pause; return; }
    cp "$ZSHRC_BACKUP_PATH" "$ZSHRC_PATH"; own_back "$ZSHRC_PATH"
    ok "~/.zshrc restaurado."; pause
}

zsh_menu() {
    while true; do
        local choice
        choice=$(select_menu "Terminal Zsh Elite" \
            "Ver Status" "Aplicar Configuração Elite" "Restaurar Backup" "Voltar")
        case "$choice" in
            "BACK"|3) return ;;
            0)
                header; hdr "STATUS DO ZSH"
                printf "  %-20s %s\n" ".zshrc Elite" "$(tag "$(status_zsh)")"
                [ -d "$REAL_HOME/.oh-my-zsh" ] && ok "oh-my-zsh instalado" || warn "oh-my-zsh não encontrado"
                [ -f "$ZSHRC_BACKUP_PATH" ] && log "Backup: ~/.zshrc.bugtuxp.bak"
                pause ;;
            1) apply_zsh ;;
            2) header; restore_zsh_backup ;;
        esac
    done
}

WC_MODULE="uvcvideo"
WC_BLACKLIST_FILE="/etc/modprobe.d/disable-webcam.conf"
WC_DEPS=(uvcvideo videobuf2_vmalloc videobuf2_memops videobuf2_v4l2 videobuf2_common videodev mc)

webcam_is_disabled() {
    lsmod | grep -q "^${WC_MODULE} " && return 1
    [ -f "$WC_BLACKLIST_FILE" ] && return 0
    return 1
}

webcam_status_label() { webcam_is_disabled && echo "DESATIVADA" || echo "ATIVADA"; }
webcam_status_tag()   { webcam_is_disabled && echo -e "${R}${BLD}[● DESATIVADA]${N}" || echo -e "${G}${BLD}[● ATIVADA   ]${N}"; }

disable_webcam() {
    webcam_is_disabled && { skip "Webcam já desativada."; pause; return; }
    local conf; conf=$(confirm_dialog "Desativar webcam permanentemente?")
    [[ "$conf" != "0" ]] && { skip "Cancelado."; pause; return; }
    header; hdr "Desativando Webcam..."
    step "Encerrando processos..."
    local dev pids
    for dev in /dev/video* /dev/media*; do
        [ -e "$dev" ] || continue
        pids=$(fuser "$dev" 2>/dev/null) || true
        [ -n "$pids" ] && kill -TERM $pids 2>/dev/null || true
    done
    sleep 1
    for dev in /dev/video* /dev/media*; do
        [ -e "$dev" ] || continue
        pids=$(fuser "$dev" 2>/dev/null) || true
        [ -n "$pids" ] && kill -KILL $pids 2>/dev/null || true
    done
    step "Descarregando módulos..."
    local dep; for dep in "${WC_DEPS[@]}"; do rmmod "$dep" 2>/dev/null || true; done
    step "Aplicando blacklist..."
    { echo "blacklist $WC_MODULE"; echo "install $WC_MODULE /bin/false"; } > "$WC_BLACKLIST_FILE"
    udevadm control --reload-rules 2>/dev/null || true
    udevadm trigger 2>/dev/null || true
    lsmod | grep -q "^${WC_MODULE} " && warn "Módulo ainda carregado — reinicie." || ok "Webcam desativada."
    pause
}

enable_webcam() {
    ! webcam_is_disabled && { skip "Webcam já ativada."; pause; return; }
    local conf; conf=$(confirm_dialog "Ativar webcam?")
    [[ "$conf" != "0" ]] && { skip "Cancelado."; pause; return; }
    header; hdr "Ativando Webcam..."
    step "Removendo blacklist..."
    rm -f "$WC_BLACKLIST_FILE"
    step "Recarregando udev..."
    udevadm control --reload-rules 2>/dev/null || true
    udevadm trigger 2>/dev/null || true
    step "Carregando módulo..."
    if modprobe "$WC_MODULE" 2>/dev/null; then
        ok "Webcam ativada."; pause; return
    fi
    local ko_path
    ko_path=$(find "/lib/modules/$(uname -r)" -name "${WC_MODULE}.ko*" 2>/dev/null | head -n1)
    if [ -n "$ko_path" ] && insmod "$ko_path" 2>/dev/null; then
        ok "Webcam ativada via insmod."
    else
        fail "Falha ao carregar módulo. Kernel: $(uname -r)"
        [ -z "$ko_path" ] && warn "Módulo não encontrado — verifique linux-headers."
    fi
    pause
}

webcam_menu() {
    while true; do
        local lbl; lbl=$(webcam_status_label)
        local choice
        choice=$(select_menu "Controle de Webcam  [${lbl}]" \
            "Ativar Webcam" "Desativar Webcam" "Voltar")
        case "$choice" in
            "BACK"|2) return ;;
            0) enable_webcam ;;
            1) disable_webcam ;;
        esac
    done
}

show_dashboard() {
    header; hdr "STATUS GERAL DO SISTEMA"; sep
    printf "  %-22s %s\n" "CPU Governor"    "$(tag "$(status_cpu)")"
    printf "  %-22s %s\n" "Kernel sysctl"   "$(tag "$(status_sysctl)")"
    printf "  %-22s %s\n" "SCX Scheduler"   "$(tag "$(status_scx)")"
    printf "  %-22s %s\n" "IO Scheduler"    "$(tag "$(status_io)")"
    printf "  %-22s %s\n" "GPU Performance" "$(tag "$(status_gpu)")"
    printf "  %-22s %s\n" "i915 opções"     "$(tag "$(status_gpu_opts)")"
    printf "  %-22s %s\n" "THP"             "$(tag "$(status_thp)")"
    printf "  %-22s %s\n" "System Limits"   "$(tag "$(status_limits)")"
    printf "  %-22s %s  (%s)\n" "ZRAM" "$(tag "$(status_zram)")" "$(current_zram_size)"
    printf "  %-22s %s\n" "Swap SSD"        "$(tag "$(status_swap_ssd)")"
    printf "  %-22s %s\n" "DNS"             "$(tag "$(status_dns)")"
    printf "  %-22s %s\n" "Backup KDE"      "$(tag "$(status_backup_tag)")"
    printf "  %-22s %s\n" "Terminal Zsh"    "$(tag "$(status_zsh)")"
    printf "  %-22s %s\n" "Webcam"          "$(webcam_status_tag)"
    sep; hdr "SISTEMA VIVO"
    printf "  %-22s %s\n" "CPU"      "$(cpu_current_info)"
    printf "  %-22s %s\n" "GPU"      "$(gpu_current_info)"
    printf "  %-22s %s\n" "ZRAM"     "$(zram_current_stats)"
    printf "  %-22s %s\n" "THP modo" "$(thp_current)"
    printf "  %-22s %s\n" "Distro"   "$(_sys_distro)"
    printf "  %-22s %s\n" "Kernel"   "$(uname -r)"
    sep; pause
}

main_menu() {
    while true; do
        local choice
        choice=$(select_menu "BugTuxP  [$(LANG=C date '+%d/%m/%Y %H:%M')]  usuário: $REAL_USER" \
            "Status Geral do Sistema" \
            "Performance  (CPU/Kernel/IO/GPU/THP/ZRAM/SWAP/DNS)" \
            "Backup & Restore KDE" \
            "Terminal Zsh Elite" \
            "Controle de Webcam" \
            "Sair")
        case "$choice" in
            "BACK"|5) clear; exit 0 ;;
            0) show_dashboard ;;
            1) performance_menu ;;
            2) backup_menu ;;
            3) zsh_menu ;;
            4) webcam_menu ;;
        esac
    done
}

main_menu
