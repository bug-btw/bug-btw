#!/bin/bash

# Cores
GREEN="\033[1;32m"
CYAN="\033[1;36m"
YELLOW="\033[1;33m"
RESET="\033[0m"

echo -e "${CYAN}Clean Kernel v1.0 by brutush${RESET}"
echo -e "${CYAN}Limpador de kernels antigos + Pacotes Desnecessários + Cache${RESET}"
echo ""

# Verifica se tem um nigger para eliminar
HAS_WORK=false

OLD_KERNELS=$(dnf repoquery --installonly --latest-limit=-1 -q 2>/dev/null || echo "")
if [ -n "$OLD_KERNELS" ]; then
    HAS_WORK=true
    echo "Kernels antigos encontrados. Removendo..."
    sudo dnf remove $OLD_KERNELS
    echo ""
fi

echo "Verificando pacotes órfãos..."
ORPHANS=$(dnf repoquery --autoremove -q 2>/dev/null || echo "")
if [ -n "$ORPHANS" ]; then
    HAS_WORK=true
    echo "Pacotes órfãos encontrados. Removendo..."
    sudo dnf autoremove
    echo ""
else
    echo "Nenhum pacote órfão."
    echo ""
fi

echo "Limpando cache DNF..."
sudo dnf clean all
echo ""

if [ "$HAS_WORK" = false ]; then
    echo -e "${YELLOW}Nada para limpar.${RESET}"
else
    echo -e "${GREEN}Limpeza concluída.${RESET}"
fi
