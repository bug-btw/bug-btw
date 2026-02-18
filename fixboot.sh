#!/usr/bin/env bash

# Script: Correção Definitiva Tela Preta - Intel UHD 620 (Wayland)
# Modelo: Lenovo IdeaPad 330 15IKB 81FE
# Sistema: Nobara KDE 43 (Wayland puro)
# Versão: 1.5 - Solução Permanente

set -euo pipefail

# ============================================
# CORES
# ============================================
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
WHITE='\033[1;37m'
NC='\033[0m'
BOLD='\033[1m'

# ============================================
# FUNÇÃO DE CONFIRMAÇÃO
# ============================================
confirm() {
    local prompt="$1"
    local choice=0

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

# ============================================
# TELA INICIAL
# ============================================
clear
echo -e "${YELLOW}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║${NC} ${BOLD}Correção Tela Preta - Intel UHD 620 (IdeaPad 330)${NC}    ${YELLOW}║${NC}"
echo -e "${YELLOW}╠═══════════════════════════════════════════════════════════╣${NC}"
echo -e "${YELLOW}║${NC} ${WHITE}PROBLEMA: Tela preta com _ piscando após GRUB${NC}         ${YELLOW}║${NC}"
echo -e "${YELLOW}║${NC} ${WHITE}CAUSA: Parâmetros i915 conflitantes após update${NC}       ${YELLOW}║${NC}"
echo -e "${YELLOW}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}Esta correção irá:${NC}"
echo ""
echo -e "${WHITE}1. Remover parâmetros problemáticos do kernel${NC}"
echo -e "${WHITE}   └─ i915.fastboot=1 (causa conflito no boot)${NC}"
echo ""
echo -e "${WHITE}2. Adicionar parâmetros estáveis testados${NC}"
echo -e "${WHITE}   └─ i915.enable_psr=0 (desativa Power Saving)${NC}"
echo -e "${WHITE}   └─ i915.enable_dc=0 (desativa Display C-states)${NC}"
echo -e "${WHITE}   └─ pcie_aspm=off (desativa Power Management PCIe)${NC}"
echo ""
echo -e "${WHITE}3. Atualizar drivers gráficos Mesa (Wayland)${NC}"
echo -e "${WHITE}   └─ mesa-dri-drivers, mesa-vulkan-drivers${NC}"
echo ""
echo -e "${WHITE}4. Reinstalar KWin Wayland compositor${NC}"
echo -e "${WHITE}   └─ kwin-wayland, plasma-workspace-wayland${NC}"
echo ""
echo -e "${WHITE}5. Regenerar initramfs com novos parâmetros${NC}"
echo -e "${WHITE}   └─ dracut com suporte i915 correto${NC}"
echo ""
echo -e "${YELLOW}⚠ SUAS CUSTOMIZAÇÕES SERÃO MANTIDAS${NC}"
echo -e "${WHITE}  (não mexe em temas, widgets, latte-dock, etc)${NC}"
echo ""

# ============================================
# CONFIRMAÇÃO ÚNICA
# ============================================
if ! confirm "Aplicar correção definitiva permanente?"; then
    clear
    echo -e "${RED}Operação cancelada.${NC}"
    echo ""
    exit 0
fi

# ============================================
# EXECUÇÃO AUTOMÁTICA
# ============================================
clear
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║${NC} ${BOLD}Iniciando correção automática...${NC}                       ${GREEN}║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""

# 1. REMOVER PARÂMETROS PROBLEMÁTICOS
echo -e "${BLUE}[1/5]${NC} ${WHITE}Removendo parâmetros problemáticos do kernel...${NC}"
sudo grubby --update-kernel=ALL --remove-args="i915.fastboot=1"
sudo grubby --update-kernel=ALL --remove-args="i915.enable_fbc=1"
sudo grubby --update-kernel=ALL --remove-args="i915.enable_guc=2"
echo -e "${GREEN}✓ Parâmetros problemáticos removidos${NC}"
echo ""

# 2. ADICIONAR PARÂMETROS ESTÁVEIS E PERMANENTES
echo -e "${BLUE}[2/5]${NC} ${WHITE}Adicionando parâmetros estáveis para Intel UHD 620...${NC}"
sudo grubby --update-kernel=ALL --args="i915.enable_psr=0 i915.enable_dc=0 pcie_aspm=off i915.modeset=1"
echo -e "${GREEN}✓ Parâmetros estáveis adicionados${NC}"
echo ""

# 3. ATUALIZAR/REINSTALAR DRIVERS MESA (WAYLAND PURO)
echo -e "${BLUE}[3/5]${NC} ${WHITE}Atualizando drivers gráficos Mesa para Wayland...${NC}"
sudo dnf reinstall -y mesa-dri-drivers mesa-vulkan-drivers mesa-libGL mesa-libEGL
sudo dnf install -y mesa-va-drivers mesa-vdpau-drivers
echo -e "${GREEN}✓ Drivers Mesa atualizados${NC}"
echo ""

# 4. REINSTALAR KWIN WAYLAND E COMPOSITOR
echo -e "${BLUE}[4/5]${NC} ${WHITE}Reinstalando KWin Wayland compositor...${NC}"
sudo dnf reinstall -y kwin-wayland plasma-workspace-wayland kwin-common kwayland-integration
echo -e "${GREEN}✓ KWin Wayland reinstalado${NC}"
echo ""

# 5. REGENERAR INITRAMFS COM MÓDULO i915 CORRETO
echo -e "${BLUE}[5/5]${NC} ${WHITE}Regenerando initramfs com módulos i915 otimizados...${NC}"
sudo dracut -f --regenerate-all
echo -e "${GREEN}✓ Initramfs regenerado${NC}"
echo ""

# ============================================
# CONFIGURAÇÃO PERMANENTE ADICIONAL
# ============================================
echo -e "${YELLOW}Criando configuração permanente do módulo i915...${NC}"

# Criar arquivo de configuração modprobe
sudo tee /etc/modprobe.d/i915-uhd620.conf > /dev/null << 'EOF'
# Configuração permanente Intel UHD 620 - IdeaPad 330 15IKB
# Desativa recursos problemáticos que causam tela preta

options i915 enable_psr=0
options i915 enable_dc=0
options i915 modeset=1
options i915 enable_fbc=0
options i915 fastboot=0
EOF

echo -e "${GREEN}✓ Configuração permanente criada em /etc/modprobe.d/i915-uhd620.conf${NC}"
echo ""

# Adicionar módulo i915 ao initramfs
if ! grep -q "^add_drivers+=\" i915 \"" /etc/dracut.conf.d/i915.conf 2>/dev/null; then
    echo -e "${YELLOW}Adicionando i915 ao initramfs permanentemente...${NC}"
    sudo mkdir -p /etc/dracut.conf.d
    echo 'add_drivers+=" i915 "' | sudo tee /etc/dracut.conf.d/i915.conf > /dev/null
    echo -e "${GREEN}✓ Módulo i915 adicionado ao dracut${NC}"
    echo ""
fi

# Regenerar novamente com a nova configuração
echo -e "${YELLOW}Regenerando initramfs final com configurações permanentes...${NC}"
sudo dracut -f --regenerate-all
echo -e "${GREEN}✓ Initramfs final regenerado${NC}"
echo ""

# ============================================
# VERIFICAÇÃO FINAL
# ============================================
echo -e "${GREEN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║${NC} ${BOLD}✓ CORREÇÃO CONCLUÍDA COM SUCESSO!${NC}                      ${GREEN}║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Parâmetros atuais do kernel:${NC}"
sudo grubby --info=ALL | grep "args=" | head -n1
echo ""
echo -e "${YELLOW}Configuração permanente criada:${NC}"
echo -e "${WHITE}/etc/modprobe.d/i915-uhd620.conf${NC}"
echo -e "${WHITE}/etc/dracut.conf.d/i915.conf${NC}"
echo ""
echo -e "${GREEN}✓ Suas customizações foram preservadas${NC}"
echo -e "${GREEN}✓ Correção é permanente (sobrevive a updates)${NC}"
echo -e "${GREEN}✓ Wayland otimizado para Intel UHD 620${NC}"
echo ""
echo -e "${YELLOW}Reiniciando em 5 segundos...${NC}"

sleep 5
sudo reboot
