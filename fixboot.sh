#!/usr/bin/env bash

set -euo pipefail

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
WHITE='\033[1;37m'
NC='\033[0m'
BOLD='\033[1m'

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
    echo -e "${BLUE}Fix Boot Intel UHD 620 - Correção Completa Nobara${NC}"
    echo -e "${WHITE}Lenovo IdeaPad 330 15IKB${NC}"
    echo ""
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}Execute com sudo: sudo ./fixboot.sh${NC}"
        exit 1
    fi
}

check_disk_space() {
    echo -e "${WHITE}Verificando espaço em disco...${NC}"
    
    local root_usage=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
    local inode_usage=$(df -i / | awk 'NR==2 {print $5}' | sed 's/%//')
    
    if [ "$root_usage" -gt 95 ]; then
        echo -e "${RED}✗ Disco quase cheio: ${root_usage}%${NC}"
        echo -e "${YELLOW}Execute limpeza antes de continuar${NC}"
        exit 1
    fi
    
    if [ "$inode_usage" -gt 95 ]; then
        echo -e "${RED}✗ Inodes quase cheios: ${inode_usage}%${NC}"
        echo -e "${YELLOW}Muitos arquivos pequenos no sistema${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ Espaço: ${root_usage}% usado, Inodes: ${inode_usage}% usados${NC}"
}

fix_config_permissions() {
    echo -e "${WHITE}Corrigindo permissões de configuração...${NC}"
    
    chown -R $SUDO_USER:$SUDO_USER /home/$SUDO_USER/.config 2>/dev/null || true
    chmod -R u+rw /home/$SUDO_USER/.config 2>/dev/null || true
    
    echo -e "${GREEN}✓ Permissões corrigidas${NC}"
}

clean_problematic_configs() {
    echo -e "${WHITE}Removendo arquivos de configuração problemáticos...${NC}"
    
    local config_files=(
        "/home/$SUDO_USER/.config/ksplashrc"
        "/home/$SUDO_USER/.config/kwinoutputconfig.json"
        "/home/$SUDO_USER/.config/plasma-org.kde.plasma.desktop-appletsrc"
    )
    
    for file in "${config_files[@]}"; do
        if [ -f "$file" ]; then
            rm -f "$file"
        fi
    done
    
    echo -e "${GREEN}✓ Configs problemáticos removidos${NC}"
}

disable_abrt_applet() {
    echo -e "${WHITE}Desativando abrt-applet...${NC}"
    
    sudo -u $SUDO_USER systemctl --user mask abrt-applet 2>/dev/null || true
    systemctl mask abrt-oops.service 2>/dev/null || true
    
    echo -e "${GREEN}✓ ABRT desativado${NC}"
}

clean_cache() {
    echo -e "${WHITE}Limpando cache do usuário...${NC}"
    
    rm -rf /home/$SUDO_USER/.cache/* 2>/dev/null || true
    rm -rf /home/$SUDO_USER/backup-config 2>/dev/null || true
    
    echo -e "${GREEN}✓ Cache limpo${NC}"
}

reinstall_nobara_plasma() {
    echo -e "${WHITE}Reinstalando KDE Plasma oficial do Nobara...${NC}"
    
    dnf clean all
    rpm --rebuilddb
    
    if dnf group list installed | grep -q "KDE Plasma Workspaces"; then
        dnf group reinstall -y "KDE Plasma Workspaces" --skip-broken
    else
        dnf group install -y "KDE Plasma Workspaces" --skip-broken
    fi
    
    dnf reinstall --refresh -y \
        kwin-wayland \
        sddm \
        plasma-desktop \
        plasma-workspace \
        plasma-workspace-wayland \
        kwayland-integration \
        mesa-dri-drivers \
        mesa-vulkan-drivers
    
    echo -e "${GREEN}✓ KDE Plasma Nobara reinstalado${NC}"
}

apply_kernel_params() {
    echo -e "${WHITE}Aplicando parâmetros do kernel...${NC}"
    
    grubby --update-kernel=ALL --remove-args="i915.fastboot=1" 2>/dev/null || true
    grubby --update-kernel=ALL --remove-args="i915.enable_fbc=1" 2>/dev/null || true
    grubby --update-kernel=ALL --args="i915.enable_psr=0 i915.enable_dc=0 pcie_aspm=off"
    
    echo -e "${GREEN}✓ Parâmetros aplicados${NC}"
}

create_permanent_config() {
    echo -e "${WHITE}Criando configuração permanente...${NC}"
    
    mkdir -p /etc/modprobe.d
    
    cat > /etc/modprobe.d/i915-uhd620.conf << 'EOF'
options i915 enable_psr=0
options i915 enable_dc=0
options i915 modeset=1
options i915 enable_fbc=0
options i915 fastboot=0
EOF
    
    mkdir -p /etc/dracut.conf.d
    echo 'add_drivers+=" i915 "' > /etc/dracut.conf.d/i915.conf
    echo 'force_drivers+=" i915 "' >> /etc/dracut.conf.d/i915.conf
    
    echo -e "${GREEN}✓ Configuração permanente criada${NC}"
}

regenerate_initramfs() {
    echo -e "${WHITE}Regenerando initramfs...${NC}"
    
    dracut -f --regenerate-all
    
    echo -e "${GREEN}✓ Initramfs regenerado${NC}"
}

main() {
    print_header
    
    if ! confirm "Aplicar correção completa do KDE Plasma Nobara?"; then
        clear
        echo -e "${RED}Operação cancelada${NC}"
        exit 0
    fi
    
    check_root
    
    clear
    echo -e "${YELLOW}Iniciando correção completa...${NC}"
    echo ""
    
    check_disk_space
    echo ""
    
    fix_config_permissions
    echo ""
    
    clean_problematic_configs
    echo ""
    
    disable_abrt_applet
    echo ""
    
    clean_cache
    echo ""
    
    reinstall_nobara_plasma
    echo ""
    
    apply_kernel_params
    echo ""
    
    create_permanent_config
    echo ""
    
    regenerate_initramfs
    echo ""
    
    echo -e "${GREEN}Correção completa finalizada${NC}"
    echo ""
    
    reboot
}

trap 'echo -e "\n${RED}Erro detectado${NC}"; exit 1' ERR

main
