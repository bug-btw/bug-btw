#!/usr/bin/env bash
set -euo pipefail
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
WHITE='\033[1;37m'
NC='\033[0m'
BOLD='\033[1m'
MODULE="uvcvideo"
BLACKLIST_FILE="/etc/modprobe.d/disable-webcam.conf"
confirm() {
    local prompt="$1"
    local choice=0
    while true; do
        clear
        echo -e "${BLUE}$prompt${NC}"
        echo ""
        if [ $choice -eq 0 ]; then
            echo -e "  ${BOLD}${GREEN}→ SIM ←${NC}          ${WHITE}NÃO${NC}"
        else
            echo -e "    ${WHITE}SIM${NC}          ${BOLD}${RED}→ NÃO ←${NC}"
        fi
        echo ""
        echo -e "${YELLOW}← → navegar | Enter confirma | Ctrl+C cancela${NC}"
        read -rsn1 key
        if [ "$key" = $'\x1b' ]; then
            read -rsn2 -t 0.1 key 2>/dev/null
            case $key in
                '[D') choice=0 ;;
                '[C') choice=1 ;;
            esac
        elif [ "$key" = "" ]; then
            [ $choice -eq 0 ] && return 0
            return 1
        fi
    done
}
get_webcam_status() {
    local is_loaded is_blacklisted
    is_loaded=$(lsmod | grep -q "^$MODULE " && echo 0 || echo 1)
    is_blacklisted=$([ -f "$BLACKLIST_FILE" ] && grep -q "blacklist $MODULE" "$BLACKLIST_FILE" && echo 0 || echo 1)
    if [ "$is_loaded" -ne 0 ] && [ "$is_blacklisted" -eq 0 ]; then
        echo "DESATIVADA"
    else
        echo "ATIVADA"
    fi
}
print_header() {
    local status
    status=$(get_webcam_status)
    clear
    echo -e "${BLUE}Webcam Controller - CachyOS 2026${NC}"
    echo -e "${WHITE}Status atual: ${YELLOW}$status${NC}"
    echo ""
}
disable_webcam() {
    local status
    status=$(get_webcam_status)
    if [ "$status" = "DESATIVADA" ]; then
        echo -e "${YELLOW}Webcam já está desativada${NC}"
        sleep 2
        return
    fi
    if ! confirm "Desativar webcam? (mata processos e bloqueia)"; then
        echo -e "${RED}Operação cancelada${NC}"
        sleep 1
        return
    fi
    clear
    echo -e "${WHITE}Desativando webcam...${NC}"
    echo -e "${WHITE}  → Encerrando processos com acesso à câmera...${NC}"
    for dev in /dev/video* /dev/media*; do
        [ -e "$dev" ] || continue
        local pids
        pids=$(sudo fuser "$dev" 2>/dev/null) || true
        for pid in $pids; do
            sudo kill -TERM "$pid" 2>/dev/null || true
        done
    done
    sleep 1
    for dev in /dev/video* /dev/media*; do
        [ -e "$dev" ] || continue
        local pids
        pids=$(sudo fuser "$dev" 2>/dev/null) || true
        for pid in $pids; do
            sudo kill -KILL "$pid" 2>/dev/null || true
        done
    done
    sleep 1
    echo -e "${WHITE}  → Descarregando módulos do kernel...${NC}"
    for dep in uvcvideo videobuf2_vmalloc videobuf2_memops videobuf2_v4l2 videobuf2_common videodev mc; do
        sudo rmmod "$dep" 2>/dev/null || true
    done
    echo -e "${WHITE}  → Aplicando blacklist...${NC}"
    echo "blacklist $MODULE" | sudo tee "$BLACKLIST_FILE" > /dev/null
    echo "install $MODULE /bin/false" | sudo tee -a "$BLACKLIST_FILE" > /dev/null
    sudo udevadm control --reload-rules 2>/dev/null || true
    sudo udevadm trigger 2>/dev/null || true
    sudo mkinitcpio -P 2>/dev/null || true
    if lsmod | grep -q "^$MODULE "; then
        echo -e "${YELLOW}⚠ Módulo ainda carregado. Blacklist aplicada: reinicie para desativar completamente.${NC}"
    else
        echo -e "${GREEN}✓ Webcam desativada com sucesso (persiste após reboot e update de kernel)${NC}"
    fi
}
enable_webcam() {
    local status
    status=$(get_webcam_status)
    if [ "$status" = "ATIVADA" ]; then
        echo -e "${YELLOW}Webcam já está ativada${NC}"
        sleep 2
        return
    fi
    if ! confirm "Ativar webcam? (libera uso)"; then
        echo -e "${RED}Operação cancelada${NC}"
        sleep 1
        return
    fi
    clear
    echo -e "${WHITE}Ativando webcam...${NC}"
    echo -e "${WHITE}  → Removendo blacklist...${NC}"
    sudo rm -f "$BLACKLIST_FILE"
    sudo udevadm control --reload-rules 2>/dev/null || true
    sudo udevadm trigger 2>/dev/null || true
    echo -e "${WHITE}  → Carregando módulo...${NC}"
    if sudo modprobe $MODULE; then
        echo -e "${GREEN}✓ Webcam ativada${NC}"
    else
        echo -e "${YELLOW}modprobe falhou, tentando insmod...${NC}"
        local ko_path
        ko_path=$(find /lib/modules/$(uname -r) -name "${MODULE}.ko*" 2>/dev/null | head -n1)
        if [ -n "$ko_path" ]; then
            sudo insmod "$ko_path" 2>/dev/null || true
        fi
        if lsmod | grep -q "^$MODULE "; then
            echo -e "${GREEN}✓ Webcam ativada via insmod${NC}"
        else
            echo -e "${RED}✗ Módulo não carregou.${NC}"
            echo -e "${YELLOW}Kernel: $(uname -r)${NC}"
            echo -e "${YELLOW}Módulo: $(find /lib/modules/$(uname -r) -name "${MODULE}.ko*" 2>/dev/null | head -n1 || echo 'NÃO ENCONTRADO')${NC}"
            sudo modprobe $MODULE 2>&1 | sed 's/^/  /' || true
        fi
    fi
}
main() {
    print_header
    if confirm "Desativar webcam? (NÃO = ativar)"; then
        disable_webcam
    else
        enable_webcam
    fi
    echo ""
    read -n1 -s -r -p "Pressione qualquer tecla para sair..."
    clear
}
trap 'echo -e "\n${RED}Erro detectado${NC}"; exit 1' ERR
main
