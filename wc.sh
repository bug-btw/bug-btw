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
    local is_loaded=$(lsmod | grep -q "^$MODULE " && echo 0 || echo 1)
    local is_blacklisted=$([ -f "$BLACKLIST_FILE" ] && grep -q "blacklist $MODULE" "$BLACKLIST_FILE" && echo 0 || echo 1)
    
    if [ $is_loaded -ne 0 ] && [ $is_blacklisted -eq 0 ]; then
        echo "DESATIVADA"
    else
        echo "ATIVADA"
    fi
}

print_header() {
    local status=$(get_webcam_status)
    clear
    echo -e "${BLUE}Webcam Controller - Nobara 2026${NC}"
    echo -e "${WHITE}Status atual: ${YELLOW}$status${NC}"
    echo ""
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}Execute com sudo: sudo ./wc.sh${NC}"
        exit 1
    fi
}

disable_webcam() {
    local status=$(get_webcam_status)
    
    if [ "$status" = "DESATIVADA" ]; then
        echo -e "${YELLOW}Webcam já está desativada${NC}"
        return
    fi
    
    if ! confirm "Desativar webcam? (mata processos e bloqueia)"; then
        echo -e "${RED}Operação cancelada${NC}"
        return
    fi
    
    clear
    echo -e "${WHITE}Desativando webcam...${NC}"
    
    fuser -k /dev/video* 2>/dev/null || true
    rmmod -f $MODULE 2>/dev/null || true
    echo "blacklist $MODULE" > $BLACKLIST_FILE
    dracut -f 2>/dev/null || update-initramfs -u 2>/dev/null || true
    
    if lsmod | grep -q $MODULE; then
        echo -e "${RED}✗ Módulo ainda carregado. Reinicie o sistema${NC}"
    else
        echo -e "${GREEN}✓ Webcam desativada${NC}"
    fi
}

enable_webcam() {
    local status=$(get_webcam_status)
    
    if [ "$status" = "ATIVADA" ]; then
        echo -e "${YELLOW}Webcam já está ativada${NC}"
        return
    fi
    
    if ! confirm "Ativar webcam? (libera uso)"; then
        echo -e "${RED}Operação cancelada${NC}"
        return
    fi
    
    clear
    echo -e "${WHITE}Ativando webcam...${NC}"
    
    rm -f $BLACKLIST_FILE
    dracut -f 2>/dev/null || update-initramfs -u 2>/dev/null || true
    modprobe $MODULE 2>/dev/null || true
    
    if lsmod | grep -q $MODULE; then
        echo -e "${GREEN}✓ Webcam ativada${NC}"
    else
        echo -e "${RED}✗ Módulo não carregou. Reinicie o sistema${NC}"
    fi
}

main() {
    check_root
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
