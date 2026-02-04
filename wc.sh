#!/usr/bin/env bash

# Script: Desativar ou Ativar Webcam (automatico com force/kill se in use)

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
WHITE='\033[1;37m'
NC='\033[0m'
BOLD='\033[1m'

confirm() {
    local prompt="$1"
    local choice=0  # 0 = Sim (padrão), 1 = Não

    while true; do
        clear
        echo -e "${BLUE}>> $prompt${NC}"
        echo ""
        if [ $choice -eq 0 ]; then
            echo -e "  ${BOLD}${GREEN}→ SIM ←${NC}          ${WHITE}NÃO${NC}"
        else
            echo -e "    ${WHITE}SIM${NC}          ${BOLD}${RED}→ NÃO ←${NC}"
        fi
        echo ""
        echo -e "${YELLOW}← → navegar | Enter confirma | Ctrl+C sai${NC}"

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

clear
echo -e "${YELLOW}GERENCIAR WEBCAM (AUTOMATICO COM FORCE)${NC}"
echo ""

if confirm "Deseja DESATIVAR a webcam (bloqueia todos apps, force kill/unload)?"; then
    clear
    if confirm "TEM CERTEZA? Mata processos e desativa total."; then
        echo -e "${GREEN}DESATIVANDO AUTOMATICAMENTE...${NC}"
        sudo fuser -k /dev/video* 2>/dev/null || true
        sudo rmmod -f uvcvideo 2>/dev/null || true
        echo "blacklist uvcvideo" | sudo tee /etc/modprobe.d/disable-webcam.conf >/dev/null
        sudo update-initramfs -u 2>/dev/null || true
        if lsmod | grep -q uvcvideo; then
            echo -e "${RED}FALHA: Ainda carregado. Reboot necessário.${NC}"
        else
            echo -e "${GREEN}WEBCAM DESATIVADA TOTAL.${NC}"
        fi
        echo -e "${YELLOW}Reativar:${NC} sudo rm /etc/modprobe.d/disable-webcam.conf && sudo update-initramfs -u && sudo modprobe uvcvideo && reboot"
    else
        echo -e "${RED}CANCELADO${NC}"
    fi
else
    clear
    if confirm "Deseja ATIVAR a webcam (libera uso)?"; then
        echo -e "${GREEN}ATIVANDO AUTOMATICAMENTE...${NC}"
        sudo rm -f /etc/modprobe.d/disable-webcam.conf
        sudo update-initramfs -u 2>/dev/null || true
        sudo modprobe uvcvideo 2>/dev/null || true
        if lsmod | grep -q uvcvideo; then
            echo -e "${GREEN}WEBCAM ATIVADA.${NC}"
        else
            echo -e "${RED}FALHA: Não carregou. Reboot.${NC}"
        fi
        echo "Reboot se necessário."
    else
        echo -e "${RED}CANCELADO${NC}"
    fi
fi

echo ""
read -n1 -s -r -p "Pressione qualquer tecla para sair..."
