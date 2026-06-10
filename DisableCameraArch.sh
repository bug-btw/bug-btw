#!/usr/bin/env bash
set -euo pipefail

[ "$EUID" -ne 0 ] && exec sudo bash "$0" "$@"

MODULE="uvcvideo"
BLACKLIST_FILE="/etc/modprobe.d/disable-webcam.conf"
DEPS=(uvcvideo videobuf2_vmalloc videobuf2_memops videobuf2_v4l2 videobuf2_common videodev mc)

R='\033[1;31m' G='\033[1;32m' Y='\033[1;33m' B='\033[1;34m' W='\033[1;37m' N='\033[0m' BLD='\033[1m'

is_disabled() { ! lsmod | grep -q "^${MODULE} " && [ -f "$BLACKLIST_FILE" ]; }
status_label() { is_disabled && echo "DESATIVADA" || echo "ATIVADA"; }

confirm() {
    local prompt="$1" choice=0 key seq
    while true; do
        clear
        echo -e "${B}$prompt${N}\n"
        [ $choice -eq 0 ] \
            && echo -e "  ${BLD}${G}→ SIM ←${N}          ${W}NÃO${N}" \
            || echo -e "    ${W}SIM${N}          ${BLD}${R}→ NÃO ←${N}"
        echo -e "\n${Y}← → navegar  |  Enter confirma  |  Ctrl+C cancela${N}"
        read -rsn1 key
        if [ "$key" = $'\x1b' ]; then
            read -rsn2 -t 0.1 seq 2>/dev/null || true
            case $seq in '[D') choice=0 ;; '[C') choice=1 ;; esac
        elif [ -z "$key" ]; then
            return $choice
        fi
    done
}

kill_webcam_procs() {
    local dev pids
    for dev in /dev/video* /dev/media*; do
        [ -e "$dev" ] || continue
        pids=$(fuser "$dev" 2>/dev/null) || true
        [ -z "$pids" ] && continue
        kill -TERM $pids 2>/dev/null || true
    done
    sleep 1
    for dev in /dev/video* /dev/media*; do
        [ -e "$dev" ] || continue
        pids=$(fuser "$dev" 2>/dev/null) || true
        [ -z "$pids" ] && continue
        kill -KILL $pids 2>/dev/null || true
    done
}

rebuild_initramfs() {
    echo -e "${W}[>] Reconstruindo initramfs...${N}"
    mkinitcpio -P >/dev/null 2>&1 || true
}

reload_udev() {
    udevadm control --reload-rules 2>/dev/null || true
    udevadm trigger 2>/dev/null || true
}

disable_webcam() {
    if is_disabled; then
        echo -e "${Y}Webcam já está desativada.${N}"; sleep 2; return
    fi
    confirm "Desativar webcam? (mata processos e bloqueia no boot)" \
        || { echo -e "${R}Cancelado.${N}"; sleep 1; return; }
    clear
    echo -e "${W}[>] Encerrando processos com acesso à câmera...${N}"
    kill_webcam_procs
    echo -e "${W}[>] Descarregando módulos do kernel...${N}"
    for dep in "${DEPS[@]}"; do rmmod "$dep" 2>/dev/null || true; done
    echo -e "${W}[>] Aplicando blacklist persistente...${N}"
    { echo "blacklist $MODULE"; echo "install $MODULE /bin/false"; } > "$BLACKLIST_FILE"
    reload_udev
    rebuild_initramfs
    if lsmod | grep -q "^${MODULE} "; then
        echo -e "${Y}⚠ Módulo ainda carregado — reinicie para efeito total.${N}"
    else
        echo -e "${G}✓ Webcam desativada (persiste após reboot e atualização de kernel).${N}"
    fi
}

enable_webcam() {
    if ! is_disabled; then
        echo -e "${Y}Webcam já está ativada.${N}"; sleep 2; return
    fi
    confirm "Ativar webcam?" \
        || { echo -e "${R}Cancelado.${N}"; sleep 1; return; }
    clear
    echo -e "${W}[>] Removendo blacklist...${N}"
    rm -f "$BLACKLIST_FILE"
    reload_udev
    rebuild_initramfs
    echo -e "${W}[>] Carregando módulo...${N}"
    if modprobe "$MODULE" 2>/dev/null; then
        echo -e "${G}✓ Webcam ativada.${N}"
        return
    fi
    local ko_path
    ko_path=$(find "/lib/modules/$(uname -r)" -name "${MODULE}.ko*" 2>/dev/null | head -n1)
    if [ -n "$ko_path" ] && insmod "$ko_path" 2>/dev/null; then
        echo -e "${G}✓ Webcam ativada via insmod.${N}"
    else
        echo -e "${R}✗ Falha ao carregar módulo.${N}"
        echo -e "${Y}Kernel : $(uname -r)${N}"
        echo -e "${Y}Módulo : ${ko_path:-NÃO ENCONTRADO}${N}"
    fi
}

main() {
    clear
    echo -e "${B}Webcam Controller — CachyOS 2026${N}"
    echo -e "${W}Status: ${Y}$(status_label)${N}\n"
    if confirm "Desativar webcam? (NÃO = ativar)"; then
        disable_webcam
    else
        enable_webcam
    fi
    echo
    read -n1 -s -r -p "Pressione qualquer tecla para sair..." && clear
}

trap 'echo -e "\n${R}Erro inesperado. Abortando.${N}"; exit 1' ERR
main
