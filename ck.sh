#!/usr/bin/env bash

# Script: Clean Kernel + Limpeza SO (com opções interativas)
# Adicionado flatpak uninstall --unused puro no final com cores

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
WHITE='\033[1;37m'
NC='\033[0m'
BOLD='\033[1m'

HAS_WORK=false

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
echo -e "${YELLOW}Clean Kernel v2.2 by brutush${NC}"
echo -e "${YELLOW}Limpador Inteligente: Kernels + Orfãos + Cache + Flatpaks Não Usados${NC}"
echo ""

# Kernels antigos
OLD_KERNELS=$(dnf repoquery --installonly --latest-limit=-1 -q 2>/dev/null || echo "")
if [ -n "$OLD_KERNELS" ]; then
    if confirm "Deseja remover kernels antigos (deixa pelo menos o atual)?"; then
        clear
        if confirm "Manter SÓ o atual? (Sim: deleta todos antigos; Não: mantém atual + anterior)"; then
            LIMIT=-1  # Só atual
        else
            LIMIT=-2  # Atual + anterior
        fi
        clear
        if confirm "TEM CERTEZA? Kernels antigos serão deletados permanentemente."; then
            echo -e "${GREEN}Removendo kernels antigos (mantendo $((LIMIT * -1)) mais recente(s))...${NC}"
            OLD_KERNELS=$(dnf repoquery --installonly --latest-limit="$LIMIT" -q 2>/dev/null || echo "")
            if [ -n "$OLD_KERNELS" ]; then
                sudo dnf remove $OLD_KERNELS
                HAS_WORK=true
            fi
            echo ""
        else
            echo -e "${RED}Cancelado remoção de kernels.${NC}"
            echo ""
        fi
    else
        echo -e "${RED}Cancelado remoção de kernels.${NC}"
        echo ""
    fi
else
    echo -e "${WHITE}Nenhum kernel antigo encontrado.${NC}"
    echo ""
fi

# Pacotes orfãos
echo -e "${WHITE}Verificando pacotes órfãos...${NC}"
ORPHANS=$(sudo dnf autoremove -y --assumeno | grep -A 999 "Removing:" | grep -v "Removing:" | awk '{print $1}' | grep -v '^$' || echo "")
if [ -n "$ORPHANS" ]; then
    if confirm "Deseja remover pacotes órfãos?"; then
        echo -e "${GREEN}Removendo pacotes órfãos...${NC}"
        sudo dnf autoremove -y
        HAS_WORK=true
        echo ""
    else
        echo -e "${RED}Cancelado remoção de órfãos.${NC}"
        echo ""
    fi
else
    echo -e "${WHITE}Nenhum pacote órfão.${NC}"
    echo ""
fi

# Limpar cache DNF
if confirm "Deseja limpar cache DNF?"; then
    echo -e "${GREEN}Limpando cache DNF...${NC}"
    sudo dnf clean all
    HAS_WORK=true
    echo ""
else
    echo -e "${RED}Cancelado limpeza cache DNF.${NC}"
    echo ""
fi

# Flatpaks não usados (puro no final com cores)
if command -v flatpak >/dev/null; then
    echo -e "${WHITE}Limpando Flatpaks não usados...${NC}"
    flatpak uninstall --unused -y
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Flatpaks não usados removidos com sucesso.${NC}"
        HAS_WORK=true
    else
        echo -e "${RED}Erro ao remover Flatpaks não usados.${NC}"
    fi
    echo ""
else
    echo -e "${WHITE}Flatpak não instalado. Pulando.${NC}"
    echo ""
fi

if [ "$HAS_WORK" = true ]; then
    echo -e "${GREEN}Limpeza concluída.${NC}"
else
    echo -e "${YELLOW}Nada para limpar.${NC}"
fi

echo ""
read -n1 -s -r -p "Pressione qualquer tecla para sair..."
clear
