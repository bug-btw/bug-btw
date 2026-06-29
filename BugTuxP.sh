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

if [ ! -t 0 ] && [ ! -r /dev/tty ]; then
    echo "BugTuxP requires an interactive terminal (TTY). Run it directly in a terminal." >&2
    exit 1
fi

G=$'\033[0;32m'
Y=$'\033[1;33m'
C=$'\033[0;36m'
B=$'\033[1;34m'
R=$'\033[0;31m'
BLD=$'\033[1m'
DIM=$'\033[2m'
N=$'\033[0m'

trap 'tput cnorm 2>/dev/null; clear; exit 0' INT TERM
trap 'tput cnorm 2>/dev/null' EXIT
tput civis 2>/dev/null || true

__MENU_CURSOR=0

ok()   { echo -e "  ${G}[✓]${N} $*"; }
skip() { echo -e "  ${Y}[~]${N} $*"; }
warn() { echo -e "  ${Y}[!]${N} $*"; }
step() { echo -e "  ${C}[>]${N} $*"; }
fail() { echo -e "  ${R}[✗]${N} $*"; }
log()  { echo -e "  ${DIM}$*${N}"; }
hdr()  { echo -e "\n${C}${BLD}  ─── $* ───${N}"; }
sep()  { echo -e "  ${DIM}$(printf '%.0s─' {1..50})${N}"; }

_sys_cpu()    { grep -m1 "model name" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs | sed 's/(R)//g;s/(TM)//g;s/ CPU//g;s/ @ .*//g;s/  */ /g'; }
_sys_gpu()    {
    local raw cols avail
    raw=$(lspci 2>/dev/null | grep -iE "vga|3d controller" | head -1 \
          | sed 's/.*: //;s/ (rev.*//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    cols=$(tput cols 2>/dev/null || echo 80)
    avail=$(( cols - 4 ))
    [ ${#raw} -gt "$avail" ] && raw="${raw:0:$avail}…"
    echo "$raw"
}
_sys_distro() { . /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-${NAME:-Linux}}"; }
_sys_kernel() { uname -r; }
_sys_de() {
    if command -v plasmashell &>/dev/null; then
        local ver
        ver=$(plasmashell --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1)
        echo "KDE Plasma ${ver:-?}"
        return
    fi
    echo "${XDG_CURRENT_DESKTOP:-${DESKTOP_SESSION:-unknown}}"
}

_is_kde() {
    local de; de=$(_sys_de)
    [[ "${de,,}" == *"kde"* || "${de,,}" == *"plasma"* ]]
}

_require_kde() {
    if ! _is_kde; then
        local de; de=$(_sys_de)
        header
        warn "This function requires KDE Plasma."
        log  "Detected DE: ${de:-unknown}"
        log  "Operation aborted to protect your desktop environment."
        pause
        return 1
    fi
    return 0
}

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
    if [ "$pct" -eq 100 ]; then echo; fi
    return 0
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
        OK)      echo -e "${G}${BLD}[✓ Applied]${N}" ;;
        PARTIAL) echo -e "${Y}${BLD}[~ Parcial]${N}" ;;
        *)       echo -e "${R}${BLD}[✗ Pendente]${N}" ;;
    esac
}

# Conta o comprimento VISUAL de uma string, independente do locale ativo.
# Necessário porque "printf %-Ns" conta BYTES em locales não-UTF-8 (ex.: quando
# qualquer rótulo com acento (Á, ã, ç, õ...) — cada byte extra de um caractere
# multibyte "rouba" uma coluna de espaçamento. Aqui contamos bytes totais menos
# bytes de continuação UTF-8 (0x80-0xBF), sempre forçando LC_ALL=C só nesta
# operação, então o resultado é 100% determinístico em qualquer máquina.
_visual_len() {
    local s="$1" total cont
    total=$(printf '%s' "$s" | wc -c)
    cont=$(printf '%s' "$s" | LC_ALL=C tr -d -c '\200-\277' | wc -c)
    echo $(( total - cont ))
}

# Imprime "  <rótulo padded até width> <valor>" numa única chamada de printf,
# usando %*s (largura numérica pura, sem ambiguidade de bytes/caracteres) para
# gerar o preenchimento — garante alinhamento perfeito sempre, em qualquer locale.
_row() {
    local label="$1" width="$2" value="$3" len pad
    len=$(_visual_len "$label")
    pad=$(( width - len ))
    [ "$pad" -lt 0 ] && pad=0
    printf "  %s%*s %s\n" "$label" "$pad" "" "$value"
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

own_back() { chown -R "$REAL_USER":"$REAL_USER" "$@" 2>/dev/null || true; }

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
        *)       warn "Package manager not detected" ;;
    esac
}

rebuild_kde_cache() {
    command -v kbuildsycoca6 &>/dev/null && run_as_user kbuildsycoca6 --noincremental 2>/dev/null && return
    command -v kbuildsycoca5 &>/dev/null && run_as_user kbuildsycoca5 --noincremental 2>/dev/null || true
}

select_menu() {
    local prompt="$1"; shift
    local options=("$@")
    local choice=${__MENU_CURSOR:-0} total=${#options[@]} key="" seq=""
    [ "$choice" -ge "$total" ] && choice=0
    while true; do
        clear >&2
        echo -e "${B}${BLD}  $prompt${N}\n" >&2
        local i
        for i in "${!options[@]}"; do
            [ "$i" -eq "$choice" ] \
                && echo -e "  ${BLD}${G}╰┈▶ ${options[$i]}${N}" >&2 \
                || echo -e "  ${DIM}  ${options[$i]}${N}" >&2
        done
        echo -e "\n  ${DIM}↑↓/jk Navegar  │  1-9 Atalho  │  g/G Topo/Fim  │  ↵ Confirma  │  ⌫ Voltar  │  Ctrl+C Sair${N}" >&2
        IFS= read -rsn1 key </dev/tty 2>/dev/null || key=""
        if [[ "$key" == $'\x7f' || "$key" == $'\b' ]]; then
            echo "BACK"; return 0
        elif [[ "$key" == $'\x1b' ]]; then
            IFS= read -rsn2 -t 0.1 seq </dev/tty 2>/dev/null || seq=""
            case "$seq" in
                '[A') choice=$(( (choice - 1 + total) % total )) ;;
                '[B') choice=$(( (choice + 1) % total )) ;;
                '[H') choice=0 ;;
                '[F') choice=$(( total - 1 )) ;;
                '')   echo "BACK"; return 0 ;;
            esac
        elif [[ "$key" == "k" ]]; then
            choice=$(( (choice - 1 + total) % total ))
        elif [[ "$key" == "j" ]]; then
            choice=$(( (choice + 1) % total ))
        elif [[ "$key" == "g" ]]; then
            choice=0
        elif [[ "$key" == "G" ]]; then
            choice=$(( total - 1 ))
        elif [[ "$key" =~ ^[1-9]$ ]] && [ "$key" -le "$total" ]; then
            echo "$(( key - 1 ))"; return 0
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
            && echo -e "  ${BLD}${G}→ Yes ←${N}          ${DIM}No / ↩ Back${N}" >&2 \
            || echo -e "  ${DIM}  Yes${N}          ${BLD}${R}→ No / ↩ Back ←${N}" >&2
        echo -e "\n  ${DIM}←→/hl Toggle  │  Y/S Yes  │  N No  │  ↵ Confirm  │  ⌫ Back${N}" >&2
        IFS= read -rsn1 key </dev/tty 2>/dev/null || key=""
        if [[ "$key" == $'\x7f' || "$key" == $'\b' ]]; then
            echo "BACK"; return 0
        elif [[ "$key" == $'\x1b' ]]; then
            IFS= read -rsn2 -t 0.1 seq </dev/tty 2>/dev/null || seq=""
            case "$seq" in
                '[D') choice=0 ;;
                '[C') choice=1 ;;
                '')   echo "BACK"; return 0 ;;
            esac
        elif [[ "$key" == "h" ]]; then choice=0
        elif [[ "$key" == "l" ]]; then choice=1
        elif [[ "$key" == $'\t' ]]; then choice=$(( 1 - choice ))
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
        skip "CPU Governor — already applied"
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
vm.swappiness = 200
vm.vfs_cache_pressure = 40
vm.dirty_ratio = 15
vm.dirty_background_ratio = 3
vm.dirty_writeback_centisecs = 1500
vm.dirty_expire_centisecs = 3000
vm.max_map_count = 2147483642
vm.compaction_proactiveness = 0
vm.page-cluster = 0
vm.oom_dump_tasks = 0
vm.stat_interval = 10
vm.zone_reclaim_mode = 0
kernel.sched_autogroup_enabled = 1
kernel.sched_migration_cost_ns = 500000
kernel.nmi_watchdog = 0
kernel.unprivileged_userns_clone = 1
kernel.numa_balancing = 0
kernel.perf_event_paranoid = 1
kernel.pid_max = 4194304
kernel.timer_migration = 0
kernel.kptr_restrict = 0
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.rmem_default = 1048576
net.core.wmem_default = 1048576
net.ipv4.tcp_rmem = 4096 1048576 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.core.netdev_max_backlog = 16384
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_slow_start_after_idle = 0
net.core.somaxconn = 8192
net.ipv4.tcp_max_syn_backlog = 8192
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
        ok "Kernel sysctl → swappiness=200, BBR, zone_reclaim=0, NUMA=off"
    else
        skip "Kernel sysctl — already applied"
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
        fail "scx_lavd not found — install: sudo pacman -S scx-scheds"; return
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
        skip "scx_lavd — already configured (active: $cur)"
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
        skip "IO Scheduler — already applied"
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
        skip "GPU freq — already applied"
    fi
    local vendor; vendor=$(_detect_gpu_vendor)
    if [ "$vendor" = "intel" ]; then
        if write_if_changed "$I915_CONF" "$(i915_content)"; then
            ok "i915 → GuC=3, DC=0, FBC=0 (efeito no próximo boot)"
        else
            skip "i915 options — already applied"
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
        skip "THP — already applied"
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
        skip "System limits — already applied"
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
    local mem_kb; mem_kb=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}')
    local gb=$(( ${mem_kb:-0} / 1024 / 1024 ))
    if   [ "$gb" -le 4  ]; then echo "2G"
    elif [ "$gb" -le 8  ]; then echo "4G"
    elif [ "$gb" -le 16 ]; then echo "8G"
    else echo "12G"
    fi
}

apply_zram_default() {
    [ "$(status_zram)" = "OK" ] && { skip "ZRAM — already active at $(current_zram_size)"; return; }
    local size; size=$(_zram_auto_size)
    write_if_changed "$ZRAM_SERVICE" "$(zram_content "$size")" || true
    systemctl daemon-reload
    systemctl enable --quiet bugtux-zram.service 2>/dev/null || true
    systemctl restart bugtux-zram.service 2>/dev/null || true
    ok "ZRAM → ${size} (auto, zstd, priority ${ZRAM_PRIO})"
}

apply_zram_interactive() {
    local cur idx
    cur=$(current_zram_size)
    idx=$(select_menu "ZRAM current: ${cur} — Select size:" \
        "4G" "6G" "8G (recomendado 12GB RAM)" "12G")
    __MENU_CURSOR=0
    [[ "$idx" == "BACK" ]] && return
    local sizes=("4G" "6G" "8G" "12G")
    local size="${sizes[$idx]}"
    write_if_changed "$ZRAM_SERVICE" "$(zram_content "$size")" || true
    systemctl daemon-reload
    systemctl enable --quiet bugtux-zram.service 2>/dev/null || true
    systemctl restart bugtux-zram.service 2>/dev/null || true
    ok "ZRAM → ${size} (zstd, priority ${ZRAM_PRIO})"
    sleep 1
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

current_swap_info() {
    local size
    size=$(swapon --show --noheadings --raw 2>/dev/null \
        | awk '{print $1}' | grep -v zram | head -1 \
        | xargs -I{} lsblk -dno SIZE {} 2>/dev/null | xargs)
    [ -n "$size" ] && echo "$size" || echo ""
}

current_dns_label() {
    [ -f "$DNS_CONF" ] || { echo ""; return; }
    local i
    for i in 0 1; do
        content_matches "$DNS_CONF" "$(dns_conf_content "$i")" && echo "${DNS_LABEL[$i]}" && return
    done
    echo ""
}

apply_swap_auto() {
    if [ "$(status_swap_ssd)" = "OK" ]; then
        skip "Swap SSD — already active"
        return
    fi

    local TARGET_DISK
    if ! TARGET_DISK=$(_detect_secondary_disk); then
        warn "Swap SSD — no secondary disk detected automatically"
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
        ok "Swap SSD — existing partition activated ($existing_swap)"
        return
    fi

    local ram_gb; ram_gb=$(( $(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024 / 1024 ))
    local swap_size=8
    [ "$ram_gb" -le 4  ] && swap_size=4
    [ "$ram_gb" -le 8  ] && swap_size=4
    [ "$ram_gb" -gt 16 ] && swap_size=16

    warn "Swap SSD — disco secundário sem swap: $TARGET_DISK ($model $size)"
    local conf
    conf=$(confirm_dialog "⚠ Criar Swap+Dados em $TARGET_DISK ($model $size)? ISSO APAGA TODOS OS DADOS do disco.")
    if [[ "$conf" != "0" ]]; then
        skip "Swap SSD — auto cancelled (use manual mode to select another disk)"
        return
    fi

    step "Swap auto: $TARGET_DISK ($model $size) → ${swap_size}GiB + dados XFS"

    local PART_SWAP="${TARGET_DISK}1" PART_DATA="${TARGET_DISK}2"
    if [[ "$TARGET_DISK" == *nvme* ]]; then
        PART_SWAP="${TARGET_DISK}p1"
        PART_DATA="${TARGET_DISK}p2"
    fi

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
        fail "Swap SSD — failed to create partition on $TARGET_DISK"; return
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

    ok "Swap SSD → ${swap_size}GiB active on $PART_SWAP (priority $SWAP_PRIO)"
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
    [ "${#DISKS_AVAILABLE[@]}" -eq 0 ] && { fail "No secondary SSD found."; return; }

    local DISK_IDX
    DISK_IDX=$(select_menu "Selecione o SSD para Swap:" "${DISKS_LABELS[@]}")
    [[ "$DISK_IDX" == "BACK" ]] && return
    local TARGET_DISK="${DISKS_AVAILABLE[$DISK_IDX]}"

    local SIZES=("4GiB" "8GiB" "12GiB" "16GiB" "24GiB" "32GiB" "48GiB" "64GiB")
    local SIZE_IDX
    SIZE_IDX=$(select_menu "Swap partition size on $TARGET_DISK:" "${SIZES[@]}")
    [[ "$SIZE_IDX" == "BACK" ]] && return
    local TARGET_SIZE="${SIZES[$SIZE_IDX]//GiB/}"

    local CONFIRM
    CONFIRM=$(confirm_dialog "⚠ APAGA TODOS OS DADOS em $TARGET_DISK. Confirmar?")
    [[ "$CONFIRM" != "0" ]] && { skip "Cancelled"; return; }

    header; hdr "PARTICIONANDO $TARGET_DISK — ${TARGET_SIZE}GiB Swap"

    local PART_SWAP="${TARGET_DISK}1" PART_DATA="${TARGET_DISK}2"
    if [[ "$TARGET_DISK" == *nvme* ]]; then
        PART_SWAP="${TARGET_DISK}p1"
        PART_DATA="${TARGET_DISK}p2"
    fi

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

    progress 100 "Done!"; echo
    ok "Swap ${TARGET_SIZE}GiB → $PART_SWAP (priority $SWAP_PRIO)"
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
    [ "$(status_dns)" = "OK" ] && { skip "DNS — already configured"; return; }
    local content; content="$(dns_conf_content "0")"
    mkdir -p "$(dirname "$DNS_CONF")"
    printf '%s\n' "$content" > "$DNS_CONF"
    local d4="${DNS4[0]}" d6="${DNS6[0]}"
    while IFS= read -r conn; do
        if [ -z "$conn" ] || [ "$conn" = "lo" ]; then continue; fi
        nmcli connection modify "$conn" ipv4.ignore-auto-dns yes ipv4.dns "$d4" \
            ipv6.ignore-auto-dns yes ipv6.dns "$d6" 2>/dev/null || true
    done < <(nmcli -g NAME connection show 2>/dev/null)
    systemctl restart NetworkManager 2>/dev/null || true
    ok "DNS → ${DNS_LABEL[0]} (automatic)"
}

apply_dns_interactive() {
    local idx
    idx=$(select_menu "Selecione o DNS:" \
        "${DNS_LABEL[0]}  (1.1.1.2 / 1.0.0.2)" \
        "${DNS_LABEL[1]}  (94.140.14.14 / 94.140.15.15)" \
        "Pular / ↩ Voltar")
    __MENU_CURSOR=0
    [[ "$idx" == "BACK" || "$idx" == "2" ]] && return
    local content; content="$(dns_conf_content "$idx")"
    if content_matches "$DNS_CONF" "$content"; then
        skip "DNS (${DNS_LABEL[$idx]}) — already applied"; sleep 1; return
    fi
    mkdir -p "$(dirname "$DNS_CONF")"
    printf '%s\n' "$content" > "$DNS_CONF"
    local d4="${DNS4[$idx]}" d6="${DNS6[$idx]}"
    while IFS= read -r conn; do
        if [ -z "$conn" ] || [ "$conn" = "lo" ]; then continue; fi
        nmcli connection modify "$conn" ipv4.ignore-auto-dns yes ipv4.dns "$d4" \
            ipv6.ignore-auto-dns yes ipv6.dns "$d6" 2>/dev/null || true
    done < <(nmcli -g NAME connection show 2>/dev/null)
    systemctl restart NetworkManager 2>/dev/null || true
    ok "DNS → ${DNS_LABEL[$idx]} (${d4// /,})"
    sleep 1
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
    _row "CPU Governor"    22 "$(tag "$(status_cpu)")"
    _row "Kernel sysctl"   22 "$(tag "$(status_sysctl)")"
    _row "SCX Scheduler"   22 "$(tag "$(status_scx)")"
    _row "IO Scheduler"    22 "$(tag "$(status_io)")"
    _row "GPU Performance" 22 "$(tag "$(status_gpu)")"
    _row "THP"             22 "$(tag "$(status_thp)")"
    _row "System Limits"   22 "$(tag "$(status_limits)")"
    _row "ZRAM"            22 "$(tag "$(status_zram)")  ($(current_zram_size))"
    _row "DNS"             22 "$(tag "$(status_dns)")"
    _row "Swap SSD"        22 "$(tag "$(status_swap_ssd)")"
    sep
    pause
}

show_performance_status() {
    header; hdr "STATUS DE PERFORMANCE"; sep
    _row "CPU Governor"    22 "$(tag "$(status_cpu)")"
    _row "Kernel sysctl"   22 "$(tag "$(status_sysctl)")"
    _row "SCX Scheduler"   22 "$(tag "$(status_scx)")"
    _row "IO Scheduler"    22 "$(tag "$(status_io)")"
    _row "GPU Performance" 22 "$(tag "$(status_gpu)")"
    _row "i915 Options"    22 "$(tag "$(status_gpu_opts)")"
    _row "THP"             22 "$(tag "$(status_thp)")"
    _row "System Limits"   22 "$(tag "$(status_limits)")"
    _row "ZRAM"            22 "$(tag "$(status_zram)") ($(current_zram_size))"
    _row "Swap SSD"        22 "$(tag "$(status_swap_ssd)")"
    _row "DNS"             22 "$(tag "$(status_dns)")"
    sep; hdr "SYSTEM INFO"
    _row "CPU"             22 "$(cpu_current_info)"
    _row "GPU"             22 "$(gpu_current_info)"
    _row "ZRAM"            22 "$(zram_current_stats)"
    _row "THP"             22 "$(thp_current)"
    _row "Kernel"          22 "$(uname -r)"
    local iosched
    iosched=$(cat /sys/block/sda/queue/scheduler 2>/dev/null | grep -oP '\[\K[^\]]+' \
           || cat /sys/block/nvme0n1/queue/scheduler 2>/dev/null | grep -oP '\[\K[^\]]+' || echo "?")
    _row "IO sched" 22 "$iosched"
    sep; pause
}

performance_menu() {
    local _last=0
    while true; do
        __MENU_CURSOR=$_last
        local choice
        choice=$(select_menu "🗲 Performance — CPU · Kernel · IO · GPU · THP · ZRAM · SWAP · DNS" \
            "🛈 Status de Performance" \
            "🗹 Aplicar TUDO" \
            "☷ ZRAM" \
            "🖴︎ Swap SSD" \
            "🖧︎ DNS" \
            "↩ Voltar")
        __MENU_CURSOR=0
        case "$choice" in
            "BACK"|5) return ;;
            0) show_performance_status;      _last=0 ;;
            1) apply_all_core;               _last=1 ;;
            2) apply_zram_interactive;       _last=2 ;;
            3) setup_swap_partition;         _last=3 ;;
            4) apply_dns_interactive;        _last=4 ;;
        esac
    done
}

DOTFILES_DIR="$REAL_HOME/BugTheme-dotfiles"
BACKUP_DIR="$DOTFILES_DIR/files"
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
    "$REAL_HOME/.local/share/plasma"      "$REAL_HOME/.local/share/color-schemes"
    "$REAL_HOME/.local/share/icons"       "$REAL_HOME/.local/share/konsole"
    "$REAL_HOME/.local/share/kwin"        "$REAL_HOME/.local/share/aurorae"
    "$REAL_HOME/.local/share/wallpapers"  "$REAL_HOME/.local/share/fonts"
    "$REAL_HOME/.local/share/kservices5"  "$REAL_HOME/.local/share/kservices6"
    "$REAL_HOME/.local/share/plasmoids"   "$REAL_HOME/.local/share/kpackage"
)
AUDIO_CONFIG_PATHS=(
    "$REAL_HOME/.config/pipewire"
    "$REAL_HOME/.config/wireplumber"
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
    local pat
    for pat in "${EXCLUDE_PATTERNS[@]}"; do
        [[ "$file" == $pat ]] && return 0
    done
    [[ "$1" == *"/cache/"* || "$1" == *"/Cache/"* || "$1" == *"/.cache/"* ]] && return 0
    return 1
}

_matches_kde_pattern() {
    local file; file=$(basename "$1")
    local pat
    for pat in "${KDE_CONFIG_PATTERNS[@]}"; do
        [[ "$file" == $pat ]] && return 0
    done
    return 1
}

_is_audio_path() {
    local f="$1" ap
    for ap in "${AUDIO_CONFIG_PATHS[@]}"; do
        [[ "$f" == "$ap"* ]] && return 0
    done
    return 1
}

_collect_config_files() {
    local f
    while IFS= read -r -d '' f; do
        _matches_exclude "$f" && continue
        _is_audio_path "$f" && continue
        _matches_kde_pattern "$f" && printf '%s\n' "$f"
    done < <(find "$REAL_HOME/.config" -maxdepth 3 -type f -print0 2>/dev/null)
}

_relative_to_home() { echo "${1/#$REAL_HOME\//}"; }

backup() {
    _require_kde || return

    header; hdr "Full KDE Plasma + Audio Backup"
    echo

    if [ -d "$DOTFILES_DIR" ]; then
        warn "Previous backup found at:"
        log  "$DOTFILES_DIR"
        log  "Current size: $(du -sh "$DOTFILES_DIR" 2>/dev/null | cut -f1)"
        echo
        local conf; conf=$(confirm_dialog "DELETAR tudo e criar Backup 100% completo?")
        [[ "$conf" != "0" ]] && { skip "Backup cancelled."; pause; return; }
    fi

    local timestamp; timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local saved_files=0 synced_dirs=0

    step "Wiping previous backup entirely..."
    rm -rf "$DOTFILES_DIR"
    mkdir -p "$BACKUP_DIR"
    ok "Directory wiped and recreated at $DOTFILES_DIR"

    echo
    hdr "FASE 1 — Configurações KDE (~/.config)"
    mapfile -t _cfg_files < <(_collect_config_files)
    local total_cf=${#_cfg_files[@]} cur_cf=0 f rel dst
    if [ "$total_cf" -eq 0 ]; then
        warn "No KDE files found in ~/.config"
    else
        for f in "${_cfg_files[@]}"; do
            cur_cf=$(( cur_cf + 1 ))
            rel=$(_relative_to_home "$f")
            progress_item "$cur_cf" "$total_cf" "$rel"
            dst="$BACKUP_DIR/$rel"
            mkdir -p "$(dirname "$dst")"
            cp "$f" "$dst"
            saved_files=$(( saved_files + 1 ))
        done
        progress_done
        ok "$total_cf arquivo(s) copiado(s) de ~/.config"
    fi

    echo
    hdr "PHASE 2 — Themes, Icons and Plasma (~/.local/share)"
    local total_kd=${#KDE_LOCAL_PATHS[@]} cur_kd=0 kpath
    for kpath in "${KDE_LOCAL_PATHS[@]}"; do
        cur_kd=$(( cur_kd + 1 ))
        if [ ! -d "$kpath" ]; then continue; fi
        progress_item "$cur_kd" "$total_kd" "$(basename "$kpath")/"
        dst="$BACKUP_DIR/$(_relative_to_home "$kpath")"
        mkdir -p "$dst"
        rsync -a --delete "$kpath/" "$dst/" 2>/dev/null || true
        synced_dirs=$(( synced_dirs + 1 ))
    done
    progress_done
    ok "$synced_dirs directory(s) synced"

    echo
    hdr "PHASE 3 — Audio (PipeWire / WirePlumber)"
    local apath found_audio=0
    for apath in "${AUDIO_CONFIG_PATHS[@]}"; do
        if [ ! -d "$apath" ]; then continue; fi
        local aname; aname=$(basename "$apath")
        step "Sincronizando $aname/..."
        dst="$BACKUP_DIR/$(_relative_to_home "$apath")"
        mkdir -p "$dst"
        rsync -a --delete "$apath/" "$dst/" 2>/dev/null || true
        ok "$aname — OK"
        found_audio=$(( found_audio + 1 ))
    done
    [ "$found_audio" -eq 0 ] && warn "No audio config found (PipeWire/WirePlumber)"

    echo
    hdr "FASE 4 — Arquivos de Shell"
    local sf
    for sf in "${SHELL_FILES[@]}"; do
        local full="$REAL_HOME/$sf"
        if [ ! -f "$full" ]; then continue; fi
        cp "$full" "$BACKUP_DIR/$sf"
        ok "$sf"
        saved_files=$(( saved_files + 1 ))
    done

    printf 'timestamp=%s\nsaved=%d\nsynced=%d\naudio=%d\n' \
        "$timestamp" "$saved_files" "$synced_dirs" "$found_audio" > "$META_FILE"
    own_back "$DOTFILES_DIR"

    echo
    sep
    ok "Backup 100% completo!"
    log "Arquivos copiados   : $saved_files"
    log "Dirs synced       : $synced_dirs"
    log "Audio (config dirs): $found_audio"
    log "Data                : $timestamp"
    log "Destino             : $DOTFILES_DIR"
    pause
}

restore_kde() {
    _require_kde || return

    if [ ! -d "$BACKUP_DIR" ]; then
        header
        warn "No backup found at:"
        log  "$BACKUP_DIR"
        log  "Execute um Backup primeiro."
        pause; return
    fi

    local backup_date="desconhecida"
    [ -f "$META_FILE" ] && backup_date=$(grep '^timestamp=' "$META_FILE" 2>/dev/null | cut -d= -f2-)

    local step_n=1
    while true; do
        if [ "$step_n" -eq 1 ]; then
            local c1; c1=$(confirm_dialog "Restaurar KDE Plasma do backup de $backup_date?")
            [[ "$c1" == "BACK" || "$c1" == "1" ]] && return
            step_n=2
        else
            local c2; c2=$(confirm_dialog "Confirmar? O Plasma será reiniciado após a restauração.")
            [[ "$c2" == "BACK" ]] && { step_n=1; continue; }
            [[ "$c2" == "1" ]] && return
            break
        fi
    done

    header; hdr "Restoring KDE Plasma + Audio"
    log "Backup de: $backup_date"
    echo

    hdr "FASE 1 — Configurações KDE (~/.config)"
    local restored_cf=0 bf rel_to_bkp dst
    while IFS= read -r -d '' bf; do
        rel_to_bkp="${bf#"$BACKUP_DIR"/}"
        _is_audio_path "$REAL_HOME/$rel_to_bkp" && continue
        dst="$REAL_HOME/$rel_to_bkp"
        mkdir -p "$(dirname "$dst")"
        cp "$bf" "$dst"
        restored_cf=$(( restored_cf + 1 ))
    done < <(find "$BACKUP_DIR/.config" -type f -print0 2>/dev/null)
    ok "~/.config: $restored_cf arquivo(s) restaurado(s)"

    echo
    hdr "PHASE 2 — Themes, Icons and Plasma (~/.local/share)"
    local kpath
    for kpath in "${KDE_LOCAL_PATHS[@]}"; do
        local krel; krel=$(_relative_to_home "$kpath")
        if [ ! -d "$BACKUP_DIR/$krel" ]; then continue; fi
        mkdir -p "$kpath"
        rsync -a --delete "$BACKUP_DIR/$krel/" "$kpath/" 2>/dev/null || true
        ok "$(basename "$kpath")"
    done

    echo
    hdr "PHASE 3 — Audio (PipeWire / WirePlumber)"
    local ap
    for ap in "${AUDIO_CONFIG_PATHS[@]}"; do
        local arel; arel=$(_relative_to_home "$ap")
        if [ ! -d "$BACKUP_DIR/$arel" ]; then continue; fi
        mkdir -p "$ap"
        rsync -a --delete "$BACKUP_DIR/$arel/" "$ap/" 2>/dev/null || true
        ok "$(basename "$ap")"
    done

    echo
    hdr "FASE 4 — Arquivos de Shell"
    local sf
    for sf in "${SHELL_FILES[@]}"; do
        if [ ! -f "$BACKUP_DIR/$sf" ]; then continue; fi
        cp "$BACKUP_DIR/$sf" "$REAL_HOME/$sf"
        ok "~/$sf"
    done

    echo
    hdr "FASE 5 — Permissões e Cache KDE"
    step "Corrigindo permissões..."
    own_back "$REAL_HOME/.config" "$REAL_HOME/.local/share"
    for ap in "${AUDIO_CONFIG_PATHS[@]}"; do
        [ -d "$ap" ] && own_back "$ap"
    done
    for sf in "${SHELL_FILES[@]}"; do
        [ -f "$REAL_HOME/$sf" ] && own_back "$REAL_HOME/$sf" 2>/dev/null || true
    done
    ok "Permissões ajustadas"

    step "Reconstruindo cache KDE..."
    rebuild_kde_cache
    step "Reiniciando Plasma..."
    run_as_user plasmashell --replace &>/dev/null &
    disown

    echo
    sep
    ok "KDE Plasma restaurado com sucesso!"
    log "O Plasma está reiniciando em segundo plano."
    pause
}

backup_status() {
    _require_kde || return

    header; hdr "🛈 KDE + Audio Backup Status"; sep

    if [ ! -d "$DOTFILES_DIR" ]; then
        warn "No backup found at $DOTFILES_DIR"
        sep; pause; return
    fi

    if [ -f "$META_FILE" ]; then
        local key val
        while IFS='=' read -r key val; do
            case "$key" in
                timestamp) ok  "Data do backup     : $val" ;;
                saved)     log "Arquivos copiados  : $val" ;;
                synced)    log "Dirs synced       : $val" ;;
                audio)     log "Audio dirs        : $val" ;;
            esac
        done < "$META_FILE"
        log "Total size        : $(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)"
    else
        warn "Meta file missing — backup may be incomplete."
    fi

    sep
    hdr "CONTEÚDO DO BACKUP"
    [ -d "$BACKUP_DIR/.config" ]               && ok  "~/.config KDE     — present" || warn "~/.config KDE     — missing"
    [ -d "$BACKUP_DIR/.local/share/plasma" ]   && ok  "Plasma theme      — present" || warn "Plasma theme      — missing"
    [ -d "$BACKUP_DIR/.local/share/aurorae" ]  && ok  "Aurorae deco      — present" || warn "Aurorae deco      — missing"
    [ -d "$BACKUP_DIR/.local/share/icons" ]    && ok  "Icons             — present" || warn "Icons             — missing"
    [ -d "$BACKUP_DIR/.local/share/konsole" ]  && ok  "Konsole profiles  — present" || warn "Konsole profiles  — missing"
    [ -d "$BACKUP_DIR/.config/pipewire" ]      && ok  "PipeWire / Dolby  — present" || warn "PipeWire / Dolby  — missing"
    [ -d "$BACKUP_DIR/.config/wireplumber" ]   && ok  "WirePlumber       — present" || warn "WirePlumber       — missing"
    local sf
    for sf in .zshrc .p10k.zsh; do
        [ -f "$BACKUP_DIR/$sf" ] && ok "$sf — present" || warn "$sf — missing"
    done

    sep; pause
}

status_backup_tag() { [ -f "$META_FILE" ] && echo OK || echo NO; }

backup_menu() {
    local _last=0
    while true; do
        __MENU_CURSOR=$_last
        local choice
        choice=$(select_menu "🗐 Backup & Restore — KDE Plasma + Audio PipeWire" \
            "⎙ Realizar Backup  (wipe + cópia 100% fresca)" \
            "↺ Restaurar Backup" \
            "🛈 Status e Conteúdo do Backup" \
            "↩ Voltar")
        __MENU_CURSOR=0
        case "$choice" in
            "BACK"|3) return ;;
            0) backup;          _last=0 ;;
            1) restore_kde;     _last=1 ;;
            2) backup_status;   _last=2 ;;
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
    [ -f "$1" ] || { echo "'$1' is not a file"; return 1; }
    case "$1" in
        *.tar.bz2) tar xjf "$1" ;; *.tar.gz) tar xzf "$1" ;; *.bz2) bunzip2 "$1" ;;
        *.rar) unrar x "$1" ;; *.gz) gunzip "$1" ;; *.tar) tar xf "$1" ;;
        *.tbz2) tar xjf "$1" ;; *.tgz) tar xzf "$1" ;; *.zip) unzip "$1" ;;
        *.Z) uncompress "$1" ;; *.7z) 7z x "$1" ;; *.xz) xz -d "$1" ;;
        *) echo "Cannot extract '$1'" ;;
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

_detect_terminals() {
    local found=()
    command -v konsole   &>/dev/null && found+=("konsole")
    command -v kitty     &>/dev/null && found+=("kitty")
    command -v alacritty &>/dev/null && found+=("alacritty")
    printf '%s\n' "${found[@]}"
}

_bugtheme_colorscheme_content() {
    cat << 'EOF'
[Background]
Color=30,30,46

[BackgroundFaint]
Color=17,17,27

[BackgroundIntense]
Color=24,24,37

[Color0]
Color=88,91,112

[Color0Faint]
Color=69,71,90

[Color0Intense]
Color=108,112,134

[Color1]
Color=243,139,168

[Color1Faint]
Color=210,100,130

[Color1Intense]
Color=255,100,150

[Color2]
Color=166,227,161

[Color2Faint]
Color=110,185,110

[Color2Intense]
Color=180,245,175

[Color3]
Color=249,226,175

[Color3Faint]
Color=210,185,130

[Color3Intense]
Color=250,179,135

[Color4]
Color=137,180,250

[Color4Faint]
Color=90,130,210

[Color4Intense]
Color=180,190,254

[Color5]
Color=203,166,247

[Color5Faint]
Color=150,110,210

[Color5Intense]
Color=215,120,255

[Color6]
Color=148,226,213

[Color6Faint]
Color=94,180,170

[Color6Intense]
Color=165,240,228

[Color7]
Color=205,214,244

[Color7Faint]
Color=166,173,200

[Color7Intense]
Color=255,255,255

[Foreground]
Color=205,214,244

[ForegroundFaint]
Color=166,173,200

[ForegroundIntense]
Color=255,255,255

[General]
Anchor=0.5,0.5
Blur=true
ColorRandomization=false
Description=BugTerminalTheme
FillStyle=Tile
Opacity=0.85
Wallpaper=
WallpaperFlipType=NoFlip
WallpaperOpacity=1
EOF
}

_bugprofile_content() {
    cat << 'EOF'
[Appearance]
ColorScheme=BugTheme
Font=JetBrains Mono,11,-1,5,700,0,0,0,0,0,0,0,0,0,0,1,Bold,0,0
LineSpacing=2

[Cursor Options]
CursorShape=1
CustomCursorColor=203,166,247
CustomCursorTextColor=17,17,27
UseCustomCursorColor=true

[General]
Command=/bin/zsh
DimWhenInactive=false
Icon=tux
Name=bug
Parent=FALLBACK/
TerminalCenter=true
TerminalColumns=120
TerminalRows=30

[Interaction Options]
AutoCopySelectedText=true
MouseWheelZoomEnabled=true
TrimLeadingWhitespaceInSelectedText=true
TrimTrailingWhitespaceInSelectedText=true

[Keyboard]
KeyBindings=linux

[Scrolling]
HistoryMode=2
ScrollBarPosition=2

[Terminal Features]
AnimatingCursorEnabled=true
BidiRenderingEnabled=false
BlinkingCursorEnabled=true
BlinkingTextEnabled=true
FlowControlEnabled=false
UrlHintsModifiers=67108864
EOF
}

_apply_zsh_to_konsole() {
    local profile_dir="$REAL_HOME/.local/share/konsole"
    local color_dir="$REAL_HOME/.local/share/konsole"
    mkdir -p "$profile_dir"

    # Instala o colorscheme BugTheme (Catppuccin Mocha vivido)
    local colorscheme_file="$color_dir/BugTheme.colorscheme"
    if ! content_matches "$colorscheme_file" "$(_bugtheme_colorscheme_content)"; then
        _bugtheme_colorscheme_content > "$colorscheme_file"
        ok "Konsole → BugTheme.colorscheme instalado (Catppuccin Mocha)"
    else
        skip "Konsole → BugTheme.colorscheme já instalado"
    fi

    # Instala o profile bug.profile aprimorado
    local profile_file="$profile_dir/bug.profile"
    if ! content_matches "$profile_file" "$(_bugprofile_content)"; then
        _bugprofile_content > "$profile_file"
        ok "Konsole → bug.profile instalado (JetBrains Mono 11, cursor Ibeam Mauve)"
    else
        skip "Konsole → bug.profile já instalado"
    fi

    # Define bug.profile como default no konsolerc
    local konsole_rc="$REAL_HOME/.config/konsolerc"
    if [ -f "$konsole_rc" ]; then
        grep -q "DefaultProfile" "$konsole_rc" \
            && sed -i 's/^DefaultProfile=.*/DefaultProfile=bug.profile/' "$konsole_rc" \
            || printf '\n[Desktop Entry]\nDefaultProfile=bug.profile\n' >> "$konsole_rc"
    else
        printf '[Desktop Entry]\nDefaultProfile=bug.profile\n' > "$konsole_rc"
    fi

    own_back "$profile_dir" "$konsole_rc"
    ok "Konsole → bug.profile definido como padrão"
}

_apply_zsh_to_kitty() {
    local kitty_conf_dir="$REAL_HOME/.config/kitty"
    local kitty_conf="$kitty_conf_dir/kitty.conf"
    mkdir -p "$kitty_conf_dir"
    if [ -f "$kitty_conf" ]; then
        grep -q "^shell " "$kitty_conf" \
            && sed -i 's|^shell .*|shell /bin/zsh|' "$kitty_conf" \
            || echo "shell /bin/zsh" >> "$kitty_conf"
    else
        echo "shell /bin/zsh" > "$kitty_conf"
    fi
    own_back "$kitty_conf_dir"
    ok "Kitty → zsh configured"
}

_apply_zsh_to_alacritty() {
    local alac_dir="$REAL_HOME/.config/alacritty"
    local alac_toml="$alac_dir/alacritty.toml"
    local alac_yml="$alac_dir/alacritty.yml"
    mkdir -p "$alac_dir"
    if [ -f "$alac_toml" ]; then
        if grep -q '^\[shell\]' "$alac_toml" 2>/dev/null; then
            sed -i '/^\[shell\]/,/^\[/{s|^program = .*|program = "/bin/zsh"|}' "$alac_toml"
        elif grep -q '^program' "$alac_toml" 2>/dev/null; then
            sed -i 's|^program = .*|program = "/bin/zsh"|' "$alac_toml"
        else
            printf '\n[shell]\nprogram = "/bin/zsh"\n' >> "$alac_toml"
        fi
        own_back "$alac_toml"
    elif [ -f "$alac_yml" ]; then
        if grep -q "^shell:" "$alac_yml" 2>/dev/null; then
            sed -i '/^shell:/,/^[^ ]/{s|^  program:.*|  program: /bin/zsh|}' "$alac_yml"
        else
            printf '\nshell:\n  program: /bin/zsh\n' >> "$alac_yml"
        fi
        own_back "$alac_yml"
    else
        printf '[shell]\nprogram = "/bin/zsh"\n' > "$alac_toml"
        own_back "$alac_toml"
    fi
    ok "Alacritty → zsh configured"
}

_ensure_zsh_default_shell() {
    local current_shell; current_shell=$(getent passwd "$REAL_USER" | cut -d: -f7)
    if [ "$current_shell" != "/bin/zsh" ]; then
        chsh -s /bin/zsh "$REAL_USER" 2>/dev/null && ok "Default shell → /bin/zsh" || warn "Could not change default shell — run: chsh -s /bin/zsh"
    else
        skip "Default shell is already zsh"
    fi
}

apply_zsh() {
    header; hdr "Terminal Zsh Customizado"

    if ! command -v zsh &>/dev/null; then
        step "Installing zsh..."; install_pkgs zsh
    fi

    if [ ! -d "$REAL_HOME/.oh-my-zsh" ]; then
        warn "oh-my-zsh not found."
        log  "Instale com: sh -c \"\$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)\""
        pause; return
    fi

    local zsh_ok=false
    if [ "$(status_zsh)" = "OK" ]; then
        zsh_ok=true
        skip ".zshrc already applied."
    else
        local conf; conf=$(confirm_dialog "Sobrescrever ~/.zshrc? (backup em .zshrc.bugtuxp.bak)")
        [[ "$conf" != "0" ]] && { skip "Cancelled"; pause; return; }
        step "Installing dependencies..."; install_pkgs "${ZSH_DEPS[@]}"
        [ -f "$ZSHRC_PATH" ] && cp "$ZSHRC_PATH" "$ZSHRC_BACKUP_PATH" && ok "Backup → ~/.zshrc.bugtuxp.bak"
        zshrc_content > "$ZSHRC_PATH"
        own_back "$ZSHRC_PATH" "$ZSHRC_BACKUP_PATH" 2>/dev/null || true
        ok ".zshrc custom applied"
        zsh_ok=true
    fi

    $zsh_ok || { pause; return; }

    echo
    hdr "Configuração nos Terminais"

    mapfile -t detected < <(_detect_terminals)
    if [ "${#detected[@]}" -eq 0 ]; then
        warn "No supported terminal found (konsole, kitty, alacritty)"
        _ensure_zsh_default_shell
        pause; return
    fi

    local term_labels=()
    for t in "${detected[@]}"; do term_labels+=("$t"); done
    term_labels+=("All installed terminals")
    term_labels+=("Somente shell padrão (chsh)")
    term_labels+=("Cancelar")

    local idx last_cancel=$(( ${#term_labels[@]} - 1 )) last_chsh=$(( ${#term_labels[@]} - 2 )) last_all=$(( ${#detected[@]} ))
    idx=$(select_menu "Onde aplicar o zsh customizado?" "${term_labels[@]}")
    [[ "$idx" == "BACK" || "$idx" == "$last_cancel" ]] && { skip "Configuração de terminais cancelada"; pause; return; }

    if [ "$idx" -eq "$last_all" ]; then
        for t in "${detected[@]}"; do
            case "$t" in
                konsole)   _apply_zsh_to_konsole ;;
                kitty)     _apply_zsh_to_kitty ;;
                alacritty) _apply_zsh_to_alacritty ;;
            esac
        done
        _ensure_zsh_default_shell
    elif [ "$idx" -eq "$last_chsh" ]; then
        _ensure_zsh_default_shell
    else
        case "${detected[$idx]}" in
            konsole)   _apply_zsh_to_konsole ;;
            kitty)     _apply_zsh_to_kitty ;;
            alacritty) _apply_zsh_to_alacritty ;;
        esac
        _ensure_zsh_default_shell
    fi

    echo
    ok "Zsh configured. Close and reopen your terminal to activate."
    pause
}

restore_zsh_backup() {
    [ ! -f "$ZSHRC_BACKUP_PATH" ] && { warn "Sem backup (~/.zshrc.bugtuxp.bak)."; pause; return; }
    local conf; conf=$(confirm_dialog "Restaurar .zshrc do backup?")
    [[ "$conf" != "0" ]] && { skip "Cancelled"; pause; return; }
    cp "$ZSHRC_BACKUP_PATH" "$ZSHRC_PATH"; own_back "$ZSHRC_PATH"
    ok "~/.zshrc restaurado."; pause
}

zsh_menu() {
    local _last=0
    while true; do
        __MENU_CURSOR=$_last
        local choice
        choice=$(select_menu ">_ Terminal Zsh Customizado" \
            "🛈 Ver Status" "🗹 Aplicar Configuração Customizada" "↺ Restaurar Backup" "↩ Voltar")
        __MENU_CURSOR=0
        case "$choice" in
            "BACK"|3) return ;;
            0)
                header; hdr "STATUS DO ZSH"
                printf "  %-26s %s\n" ".zshrc Customizado" "$(tag "$(status_zsh)")"
                [ -d "$REAL_HOME/.oh-my-zsh" ] && ok "oh-my-zsh installed" || warn "oh-my-zsh not found"
                [ -f "$ZSHRC_BACKUP_PATH" ] && log "Backup: ~/.zshrc.bugtuxp.bak"
                echo
                hdr "TERMINAIS DETECTADOS"
                mapfile -t _terms < <(_detect_terminals)
                if [ "${#_terms[@]}" -eq 0 ]; then
                    warn "No supported terminal found"
                else
                    for t in "${_terms[@]}"; do ok "$t installed"; done
                fi
                local cur_shell; cur_shell=$(getent passwd "$REAL_USER" | cut -d: -f7)
                printf "  %-26s %s\n" "Shell padrão" "$cur_shell"
                pause; _last=0 ;;
            1) apply_zsh;             _last=1 ;;
            2) header; restore_zsh_backup; _last=2 ;;
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

webcam_status_label() { webcam_is_disabled && echo "● DISABLED" || echo "● ENABLED"; }
webcam_status_tag()   { webcam_is_disabled && echo -e "${R}${BLD}[● DISABLED]${N}" || echo -e "${G}${BLD}[● ENABLED]${N}"; }

disable_webcam() {
    webcam_is_disabled && { skip "Webcam already disabled."; pause; return; }
    local conf; conf=$(confirm_dialog "Desativar webcam permanentemente?")
    [[ "$conf" != "0" ]] && { skip "Cancelled."; pause; return; }
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
    step "Unloading modules..."
    local dep; for dep in "${WC_DEPS[@]}"; do rmmod "$dep" 2>/dev/null || true; done
    step "Aplicando blacklist..."
    { echo "blacklist $WC_MODULE"; echo "install $WC_MODULE /bin/false"; } > "$WC_BLACKLIST_FILE"
    udevadm control --reload-rules 2>/dev/null || true
    udevadm trigger 2>/dev/null || true
    lsmod | grep -q "^${WC_MODULE} " && warn "Module still loaded — reboot required." || ok "Webcam disabled."
    pause
}

enable_webcam() {
    ! webcam_is_disabled && { skip "Webcam already enabled."; pause; return; }
    local conf; conf=$(confirm_dialog "Ativar webcam?")
    [[ "$conf" != "0" ]] && { skip "Cancelled."; pause; return; }
    header; hdr "Ativando Webcam..."
    step "Removendo blacklist..."
    rm -f "$WC_BLACKLIST_FILE"
    step "Recarregando udev..."
    udevadm control --reload-rules 2>/dev/null || true
    udevadm trigger 2>/dev/null || true
    step "Loading module..."
    if modprobe "$WC_MODULE" 2>/dev/null; then
        ok "Webcam enabled."; pause; return
    fi
    local ko_path
    ko_path=$(find "/lib/modules/$(uname -r)" -name "${WC_MODULE}.ko*" 2>/dev/null | head -n1)
    if [ -n "$ko_path" ] && insmod "$ko_path" 2>/dev/null; then
        ok "Webcam enabled via insmod."
    else
        fail "Failed to load module. Kernel: $(uname -r)"
        [ -z "$ko_path" ] && warn "Module not found — check linux-headers."
    fi
    pause
}

webcam_menu() {
    local _last=0
    while true; do
        local lbl; lbl=$(webcam_status_label)
        __MENU_CURSOR=$_last
        local choice
        choice=$(select_menu "🅾 Controle de Webcam  [${lbl}]" \
            "🗹 Ativar Webcam" "✖ Desativar Webcam" "↩ Voltar")
        __MENU_CURSOR=0
        case "$choice" in
            "BACK"|2) return ;;
            0) enable_webcam;   _last=0 ;;
            1) disable_webcam;  _last=1 ;;
        esac
    done
}

# ╔══════════════════════════════════════════════════════════════════╗
# ╚══════════════════════════════════════════════════════════════════╝

_sb_board_vendor() {
    cat /sys/class/dmi/id/board_vendor 2>/dev/null | tr '[:upper:]' '[:lower:]' | xargs
}

_sb_board_name() {
    local v n
    v=$(cat /sys/class/dmi/id/board_vendor 2>/dev/null | xargs)
    n=$(cat /sys/class/dmi/id/board_name   2>/dev/null | xargs)
    echo "${v} ${n}"
}

_sb_in_setup_mode() {
    local mode
    mode=$(cat /sys/firmware/efi/efivars/SetupMode-* 2>/dev/null | xxd 2>/dev/null | tail -1 | awk '{print $NF}')
    [[ "$mode" == *"01"* ]] && return 0
    sbctl status 2>/dev/null | grep -qi "setup mode.*enabled\|setup mode.*true\|setup mode:.*yes" && return 0
    return 1
}

_sb_keys_created() {
    sbctl status 2>/dev/null | grep -qi "installed.*true\|signing keys.*created\|keys.*created" && return 0
    [ -f "/usr/share/secureboot/keys/db/db.key" ] && return 0
    return 1
}

_sb_active() {
    sbctl status 2>/dev/null | grep -qi "secure boot.*enabled\|secure boot:.*yes"
}

status_secureboot() {
    command -v sbctl &>/dev/null || { echo NO; return; }
    if _sb_active; then echo OK; return; fi
    _sb_keys_created && echo PARTIAL || echo NO
}

_sb_show_status() {
    header; hdr "🛈 Secure Boot — Status Detalhado"; sep
    if ! command -v sbctl &>/dev/null; then
        warn "sbctl not installed."
        log  "Use a opção 'Configurar Secure Boot' para instalar."
        sep; pause; return
    fi
    echo
    sbctl status 2>/dev/null || true
    echo
    sep
    local sv; sv=$(status_secureboot)
    printf "  %-24s %s\n" "Estado geral" "$(tag "$sv")"
    printf "  %-24s %s\n" "Placa-mãe" "$(_sb_board_name)"
    if _sb_keys_created; then
        ok "Chaves criadas"
    else
        warn "Keys NOT created"
    fi
    if _sb_in_setup_mode; then
        warn "Setup Mode ATIVO — BIOS aguarda enrollment"
    else
        log "Setup Mode inativo"
    fi
    if command -v limine-update &>/dev/null; then
        ok "Limine detectado"
    else
        log "Limine not detected"
    fi
    sep; pause
}

apply_secureboot() {
    header; hdr "Configurar Secure Boot (sbctl)"
    echo

    if ! command -v sbctl &>/dev/null; then
        step "sbctl not found — installing..."
        install_pkgs sbctl
        if ! command -v sbctl &>/dev/null; then
            fail "Falha ao instalar sbctl. Verifique sua conexão e tente:"; log "sudo pacman -S sbctl"
            pause; return
        fi
        ok "sbctl installed successfully"
    else
        ok "sbctl already installed  ($(sbctl version 2>/dev/null | head -1 || echo "unknown version"))"
    fi

    echo
    hdr "STATUS ATUAL"
    sbctl status 2>/dev/null || true
    echo

    if _sb_active; then
        ok "Secure Boot is already ACTIVE and configured."
        sep; pause; return
    fi

    if ! _sb_in_setup_mode; then
        sep
        warn "Not in Setup Mode!"
        log  "Para ativar o Setup Mode, acesse a BIOS/UEFI:"
        log  "  → Security › Secure Boot › Clear Keys  (ou Reset to Setup Mode)"
        log  "  → Salve, reinicie e execute este script novamente."
        sep; pause; return
    fi

    ok "Setup Mode ativo — pronto para enrollment"
    echo

    if ! _sb_keys_created; then
        step "Criando chaves Secure Boot..."
        if ! sbctl create-keys; then
            fail "Falha ao criar chaves."; pause; return
        fi
        ok "Chaves criadas com sucesso"
    else
        skip "Keys already exist — skipping creation"
    fi
    echo

    local vendor; vendor=$(_sb_board_vendor)
    local enroll_args="--microsoft --firmware-builtin"
    local vendor_note="padrão (Microsoft + firmware builtin)"

    if [[ "$vendor" == *"gigabyte"* ]]; then
        enroll_args="--microsoft"
        vendor_note="Gigabyte detectado → apenas --microsoft (sem --firmware-builtin)"
    elif [[ "$vendor" == *"asus"* || "$vendor" == *"asustek"* ]]; then
        enroll_args="--microsoft"
        vendor_note="ASUS detectado → apenas --microsoft (sem --firmware-builtin)"
    fi

    step "Placa-mãe : $(_sb_board_name)"
    log  "Modo      : $vendor_note"
    echo

    local conf; conf=$(confirm_dialog "Gravar chaves na NVRAM UEFI? (sbctl enroll-keys $enroll_args)")
    [[ "$conf" != "0" ]] && { skip "Enrollment cancelled."; pause; return; }

    step "Gravando chaves na NVRAM..."
    # shellcheck disable=SC2086
    if ! sbctl enroll-keys $enroll_args; then
        fail "Falha ao gravar chaves."
        log  "Verifique se o Setup Mode está ativo na BIOS."
        pause; return
    fi
    ok "Chaves gravadas na NVRAM com sucesso"
    echo

    local limine_done=false
    if command -v limine-enroll-config &>/dev/null || command -v limine-update &>/dev/null; then
        hdr "Limine Bootloader"
        if command -v limine-enroll-config &>/dev/null; then
            step "Registrando configuração do Limine..."
            limine-enroll-config 2>/dev/null \
                && ok "limine-enroll-config — OK" \
                || warn "limine-enroll-config failed — check manually"
        fi
        if command -v limine-update &>/dev/null; then
            step "Atualizando Limine..."
            limine-update 2>/dev/null \
                && ok "limine-update — OK" \
                || warn "limine-update failed — check manually"
        fi
        limine_done=true
        echo
    else
        log "Limine not detected — bootloader step skipped"
        echo
    fi

    hdr "STATUS FINAL"
    sbctl status 2>/dev/null || true
    echo
    sep

    warn "⚠  REBOOT NECESSÁRIO"
    log  "Após reiniciar, acesse a BIOS/UEFI e ATIVE o Secure Boot."
    log  "O sistema irá iniciar com Secure Boot habilitado."
    $limine_done && log "Limine already updated and signed." || true
    sep
    ok "Configuração concluída."
    pause
}

secureboot_menu() {
    local _last=0
    while true; do
        local st; st=$(status_secureboot)
        __MENU_CURSOR=$_last
        local choice
        choice=$(select_menu "🛡 Secure Boot — sbctl · Limine  $(tag "$st")" \
            "🛈 Status Detalhado" \
            "⚙ Configurar Secure Boot" \
            "↩ Voltar")
        __MENU_CURSOR=0
        case "$choice" in
            "BACK"|2) return ;;
            0) _sb_show_status;    _last=0 ;;
            1) apply_secureboot;   _last=1 ;;
        esac
    done
}

show_dashboard() {
    header; hdr "SYSTEM STATUS"; sep
    local _swap_info _dns_label _zram_sz _swap_tag _dns_tag _zram_tag
    _zram_sz=$(current_zram_size)
    _swap_info=$(current_swap_info)
    _dns_label=$(current_dns_label)
    _zram_tag=$(tag "$(status_zram)")
    _swap_tag=$(tag "$(status_swap_ssd)")
    _dns_tag=$(tag "$(status_dns)")
    printf "  %-24s %s\n" "CPU Governor"    "$(tag "$(status_cpu)")"
    printf "  %-24s %s\n" "Kernel sysctl"   "$(tag "$(status_sysctl)")"
    printf "  %-24s %s\n" "SCX Scheduler"   "$(tag "$(status_scx)")"
    printf "  %-24s %s\n" "IO Scheduler"    "$(tag "$(status_io)")"
    printf "  %-24s %s\n" "GPU Performance" "$(tag "$(status_gpu)")"
    printf "  %-24s %s\n" "i915 Options"    "$(tag "$(status_gpu_opts)")"
    printf "  %-24s %s\n" "THP"             "$(tag "$(status_thp)")"
    printf "  %-24s %s\n" "System Limits"   "$(tag "$(status_limits)")"
    if [ -n "$_zram_sz" ] && [ "$_zram_sz" != "—" ]; then
        printf "  %-24s %s  (%s)\n" "ZRAM" "$_zram_tag" "$_zram_sz"
    else
        printf "  %-24s %s\n" "ZRAM" "$_zram_tag"
    fi
    if [ -n "$_swap_info" ]; then
        printf "  %-24s %s  (%s)\n" "Swap SSD" "$_swap_tag" "$_swap_info"
    else
        printf "  %-24s %s\n" "Swap SSD" "$_swap_tag"
    fi
    if [ -n "$_dns_label" ]; then
        printf "  %-24s %s  (%s)\n" "DNS" "$_dns_tag" "$_dns_label"
    else
        printf "  %-24s %s\n" "DNS" "$_dns_tag"
    fi
    printf "  %-24s %s\n" "KDE+Audio Backup" "$(tag "$(status_backup_tag)")"
    printf "  %-24s %s\n" "Zsh Terminal"     "$(tag "$(status_zsh)")"
    printf "  %-24s %s\n" "Secure Boot"      "$(tag "$(status_secureboot)")"
    printf "  %-24s %s\n" "Webcam"           "$(webcam_status_tag)"
    sep; hdr "SYSTEM INFO"
    printf "  %-24s %s\n" "CPU"              "$(cpu_current_info)"
    printf "  %-24s %s\n" "GPU"              "$(gpu_current_info)"
    printf "  %-24s %s\n" "ZRAM"             "$(zram_current_stats)"
    printf "  %-24s %s\n" "THP"              "$(thp_current)"
    printf "  %-24s %s\n" "Distro"           "$(_sys_distro)"
    printf "  %-24s %s\n" "Kernel"           "$(uname -r)"
    sep; pause
}

main_menu() {
    local _last=0
    while true; do
        __MENU_CURSOR=$_last
        local choice
        choice=$(select_menu "🛠 BugTuxP • [ ⴵ $(LANG=C date '+%d/%m/%Y %H:%M')] • 🖳  $REAL_USER" \
            "🛈 System Status" \
            "🗲 Performance  (CPU · Kernel · IO · GPU · THP · ZRAM · SWAP · DNS)" \
            "🗐 Backup & Restore  (KDE Plasma + Audio PipeWire)" \
            ">_ Terminal  (Zsh · Oh-My-Zsh · P10k · Konsole · Kitty · Alacritty)" \
            "🛡 Secure Boot  (sbctl · Limine)" \
            "🅾 Webcam  (Ativar / Desativar)" \
            "⏻ Sair")
        __MENU_CURSOR=0
        case "$choice" in
            "BACK"|6) clear; exit 0 ;;
            0) show_dashboard;      _last=0 ;;
            1) performance_menu;    _last=1 ;;
            2) backup_menu;         _last=2 ;;
            3) zsh_menu;            _last=3 ;;
            4) secureboot_menu;     _last=4 ;;
            5) webcam_menu;         _last=5 ;;
        esac
    done
}

printf "  ${DIM}Verificando atualizações do KDE Plasma...${N}"
_plasma_refresh_check
printf "\r\033[K"

main_menu
