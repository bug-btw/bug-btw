#!/usr/bin/env bash
set -euo pipefail

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
WHITE='\033[1;37m'
NC='\033[0m'
BOLD='\033[1m'

HAS_WORK=false
SPACE_BEFORE=0
SPACE_AFTER=0

get_disk_usage() {
    df -BM / | awk 'NR==2 {gsub("M","",$3); print $3}'
}

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

print_header() {
    clear
    echo -e "${BLUE}Clean Kernel - CachyOS 2026${NC}"
    echo -e "${WHITE}Kernels + Órfãos + Cache Pacman + Flatpaks + Plasma${NC}"
    echo ""
}

clean_old_kernels() {
    echo -e "${WHITE}Verificando kernels instalados...${NC}"
    local kernels=$(pacman -Qq | grep -E '^linux-cachyos' | grep -v headers || echo "")

    if [ -z "$kernels" ]; then
        echo -e "${WHITE}Nenhum kernel extra encontrado${NC}"
        return
    fi

    echo -e "${YELLOW}Kernels encontrados:${NC}"
    echo "$kernels"
    echo ""

    if ! confirm "Manter apenas linux-cachyos e remover o LTS?"; then
        echo -e "${RED}Operação cancelada${NC}"
        return
    fi

    if ! confirm "CONFIRMA remoção permanente dos kernels antigos?"; then
        echo -e "${RED}Operação cancelada${NC}"
        return
    fi

    echo -e "${WHITE}Removendo kernels antigos...${NC}"
    sudo pacman -Rns --noconfirm linux-cachyos-lts linux-cachyos-lts-headers 2>/dev/null || true
    HAS_WORK=true
    echo -e "${GREEN}✓ Kernels antigos removidos${NC}"
}

clean_orphan_packages() {
    echo -e "${WHITE}Verificando pacotes órfãos...${NC}"
    local orphans=$(pacman -Qdtq 2>/dev/null || echo "")

    if [ -z "$orphans" ]; then
        echo -e "${WHITE}Nenhum pacote órfão encontrado${NC}"
        return
    fi

    echo -e "${YELLOW}Órfãos encontrados:${NC}"
    echo "$orphans"
    echo ""

    if ! confirm "Remover pacotes órfãos?"; then
        echo -e "${RED}Operação cancelada${NC}"
        return
    fi

    echo -e "${WHITE}Removendo pacotes órfãos...${NC}"
    sudo pacman -Rns --noconfirm $orphans
    HAS_WORK=true
    echo -e "${GREEN}✓ Pacotes órfãos removidos${NC}"
}

clean_pacman_cache() {
    if ! confirm "Limpar cache Pacman? (mantém 2 versões de cada pacote)"; then
        echo -e "${RED}Operação cancelada${NC}"
        return
    fi

    echo -e "${WHITE}Limpando cache Pacman...${NC}"
    sudo paccache -rk2 2>/dev/null || true
    sudo find /var/cache/pacman/pkg/ -name "download-*" -delete 2>/dev/null || true
    sudo pacman -Scc --noconfirm 2>/dev/null || true
    HAS_WORK=true
    echo -e "${GREEN}✓ Cache Pacman limpo${NC}"
}

clean_flatpak_unused() {
    if ! command -v flatpak &>/dev/null; then
        echo -e "${WHITE}Flatpak não instalado. Pulando${NC}"
        return
    fi

    echo -e "${WHITE}Limpando Flatpaks não usados...${NC}"

    if flatpak uninstall --unused -y 2>/dev/null; then
        HAS_WORK=true
        echo -e "${GREEN}✓ Flatpaks não usados removidos${NC}"
    else
        echo -e "${YELLOW}Nenhum Flatpak não usado encontrado${NC}"
    fi
}

clean_plasma_cache() {
    if ! confirm "Limpar cache Plasma? (plasmashell + kactivitymanagerd)"; then
        echo -e "${RED}Operação cancelada${NC}"
        return
    fi

    echo -e "${WHITE}Limpando cache Plasma...${NC}"

    local cache_dirs=(
        "$HOME/.cache/plasmashell"
        "$HOME/.cache/kactivitymanagerd"
        "$HOME/.cache/ksycoca6"
        "$HOME/.cache/kwinrules"
    )

    for cache_dir in "${cache_dirs[@]}"; do
        if [ -d "$cache_dir" ]; then
            rm -rf "$cache_dir"
        fi
    done

    HAS_WORK=true
    echo -e "${GREEN}✓ Cache Plasma limpo${NC}"
}

clean_paru_cache() {
    if ! confirm "Limpar cache AUR (paru)?"; then
        echo -e "${RED}Operação cancelada${NC}"
        return
    fi

    echo -e "${WHITE}Limpando cache AUR...${NC}"
    rm -rf "$HOME/.cache/paru" 2>/dev/null || true
    HAS_WORK=true
    echo -e "${GREEN}✓ Cache AUR limpo${NC}"
}

clean_systemd_logs() {
    local log_size=$(journalctl --disk-usage 2>/dev/null | awk '{print $7, $8}' || echo "desconhecido")
    echo -e "${WHITE}Logs do systemd ocupam: ${YELLOW}$log_size${NC}"
    echo ""

    if ! confirm "Limpar logs do systemd? (manter apenas últimos 7 dias)"; then
        echo -e "${RED}Operação cancelada${NC}"
        return
    fi

    echo -e "${WHITE}Limpando logs antigos...${NC}"
    sudo journalctl --vacuum-time=7d
    HAS_WORK=true
    echo -e "${GREEN}✓ Logs antigos removidos${NC}"
}

check_pacnew() {
    echo -e "${WHITE}Verificando arquivos .pacnew pendentes...${NC}"
    local pacnew=$(find /etc -name "*.pacnew" 2>/dev/null || echo "")

    if [ -z "$pacnew" ]; then
        echo -e "${GREEN}✓ Nenhum arquivo .pacnew pendente${NC}"
        return
    fi

    echo -e "${YELLOW}Arquivos .pacnew encontrados (requerem atenção manual):${NC}"
    echo "$pacnew"
    echo ""
    echo -e "${YELLOW}⚠ Compare e mescle manualmente com pacdiff ou meld${NC}"
}

print_space_report() {
    SPACE_AFTER=$(get_disk_usage)
    local freed=$((SPACE_BEFORE - SPACE_AFTER))
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${WHITE}Espaço antes : ${YELLOW}${SPACE_BEFORE}MB${NC}"
    echo -e "${WHITE}Espaço depois: ${YELLOW}${SPACE_AFTER}MB${NC}"
    if [ $freed -gt 0 ]; then
        echo -e "${WHITE}Liberado     : ${GREEN}${freed}MB${NC}"
    else
        echo -e "${WHITE}Liberado     : ${WHITE}0MB${NC}"
    fi
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

main() {
    print_header
    SPACE_BEFORE=$(get_disk_usage)

    clean_old_kernels
    echo ""

    clean_orphan_packages
    echo ""

    clean_pacman_cache
    echo ""

    clean_flatpak_unused
    echo ""

    clean_plasma_cache
    echo ""

    clean_paru_cache
    echo ""

    clean_systemd_logs
    echo ""

    check_pacnew
    echo ""

    if [ "$HAS_WORK" = true ]; then
        echo -e "${GREEN}✓ Limpeza concluída com sucesso${NC}"
    else
        echo -e "${YELLOW}Nenhuma limpeza realizada${NC}"
    fi

    print_space_report

    echo ""
    read -n1 -s -r -p "Pressione qualquer tecla para sair..."
    clear
    fastfetch
}

trap 'echo -e "\n${RED}Erro detectado${NC}"; exit 1' ERR

main
