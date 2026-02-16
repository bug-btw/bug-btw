#!/usr/bin/env bash

# Script: Correção Definitiva i915 UHD 620 - Nobara 43
# Versão: 2.0 - Automatizado e Moderno

set -euo pipefail

# ============================================
# CORES E ESTILOS
# ============================================
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
WHITE='\033[1;37m'
NC='\033[0m'
BOLD='\033[1m'

# ============================================
# VARIÁVEIS GLOBAIS
# ============================================
HAS_WORK=false
SCRIPT_VERSION="2.0"
SCRIPT_NAME="i915 UHD 620 Fix"

# ============================================
# FUNÇÕES DE INTERFACE
# ============================================

# Função de confirmação interativa com navegação por setas
confirm() {
    local prompt="$1"
    local choice=0  # 0 = Sim (padrão), 1 = Não

    while true; do
        clear
        echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║${NC} ${BOLD}$prompt${NC}"
        echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
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
                '[D') choice=0 ;;  # Seta esquerda
                '[C') choice=1 ;;  # Seta direita
            esac
        elif [ "$key" = "" ]; then
            [ $choice -eq 0 ] && return 0
            return 1
        fi
    done
}

# Exibe título do script
show_title() {
    clear
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}  ${YELLOW}${BOLD}${SCRIPT_NAME} v${SCRIPT_VERSION}${NC}                      ${BLUE}║${NC}"
    echo -e "${BLUE}╠════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BLUE}║${NC}  ${WHITE}Remove fastboot + Parâmetros corretos + Reinstala${NC}  ${BLUE}║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Exibe mensagem de sucesso
show_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

# Exibe mensagem de erro
show_error() {
    echo -e "${RED}✗ $1${NC}"
}

# Exibe mensagem de aviso
show_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# Exibe mensagem de informação
show_info() {
    echo -e "${WHITE}ℹ $1${NC}"
}

# Barra de progresso simulada
show_progress() {
    local msg="$1"
    echo -ne "${BLUE}${msg}${NC}"
    for i in {1..3}; do
        sleep 0.3
        echo -n "."
    done
    echo ""
}

# Pausa com mensagem
pause_with_message() {
    local msg="${1:-Pressione qualquer tecla para continuar...}"
    echo ""
    read -n1 -s -r -p "$msg"
    echo ""
}

# ============================================
# FUNÇÕES DE VERIFICAÇÃO
# ============================================

# Verifica se está rodando como root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        show_error "Este script precisa ser executado como root (sudo)"
        exit 1
    fi
}

# Verifica parâmetros atuais do kernel
check_current_params() {
    echo -e "${BLUE}Parâmetros atuais do kernel:${NC}"
    grubby --info=ALL | grep -E "args=.*i915" || show_info "Nenhum parâmetro i915 encontrado"
    echo ""
}

# ============================================
# FUNÇÕES PRINCIPAIS
# ============================================

# Remove parâmetro problemático
remove_fastboot() {
    if confirm "Remover i915.fastboot=1 (causa tela preta após updates)?"; then
        show_progress "Removendo fastboot"

        if grubby --update-kernel=ALL --remove-args="i915.fastboot=1" 2>/dev/null; then
            show_success "Parâmetro i915.fastboot=1 removido com sucesso"
            HAS_WORK=true
        else
            show_warning "Parâmetro não encontrado ou já removido"
        fi
    else
        show_error "Operação cancelada"
    fi
    echo ""
}

# Adiciona parâmetros corretos
add_stable_params() {
    if confirm "Adicionar i915.enable_psr=0 i915.enable_dc=0 pcie_aspm=off?"; then
        show_progress "Adicionando parâmetros estáveis"

        if grubby --update-kernel=ALL --args="i915.enable_psr=0 i915.enable_dc=0 pcie_aspm=off" 2>/dev/null; then
            show_success "Parâmetros estáveis adicionados com sucesso"
            HAS_WORK=true
        else
            show_error "Erro ao adicionar parâmetros"
        fi
    else
        show_error "Operação cancelada"
    fi
    echo ""
}

# Atualiza o sistema
update_system() {
    if confirm "Atualizar todo o sistema (dnf update)?"; then
        show_progress "Atualizando sistema (pode demorar)"

        if dnf update --refresh -y; then
            show_success "Sistema atualizado com sucesso"
            HAS_WORK=true
        else
            show_error "Erro durante atualização do sistema"
        fi
    else
        show_error "Operação cancelada"
    fi
    echo ""
}

# Reinstala pacotes críticos
reinstall_graphics() {
    if confirm "Reinstalar mesa, kwin-wayland, sddm e plasma-desktop?"; then
        show_progress "Reinstalando pacotes gráficos (pode demorar)"

        local packages="mesa-dri-drivers kwin-wayland sddm plasma-desktop xorg-x11-drv-intel"

        if dnf reinstall --refresh -y $packages; then
            show_success "Pacotes gráficos reinstalados com sucesso"
            HAS_WORK=true
        else
            show_error "Erro ao reinstalar pacotes gráficos"
        fi
    else
        show_error "Operação cancelada"
    fi
    echo ""
}

# Regenera initramfs
regenerate_initramfs() {
    if confirm "Regenerar initramfs (dracut)?"; then
        show_progress "Regenerando initramfs (pode demorar)"

        if dracut -f --regenerate-all; then
            show_success "Initramfs regenerado com sucesso"
            HAS_WORK=true
        else
            show_error "Erro ao regenerar initramfs"
        fi
    else
        show_error "Operação cancelada"
    fi
    echo ""
}

# Finalização com opção de reboot
finalize() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"

    if [ "$HAS_WORK" = true ]; then
        echo -e "${BLUE}║${NC}  ${GREEN}${BOLD}✓ Correção concluída com sucesso!${NC}                  ${BLUE}║${NC}"
        echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
        echo ""

        if confirm "Deseja reiniciar o sistema agora?"; then
            show_warning "Reiniciando em 5 segundos..."
            for i in {5..1}; do
                echo -ne "\r${YELLOW}Reiniciando em ${i} segundos... ${NC}"
                sleep 1
            done
            echo ""
            reboot
        else
            show_info "Lembre-se de reiniciar o sistema para aplicar as mudanças"
        fi
    else
        echo -e "${BLUE}║${NC}  ${YELLOW}${BOLD}⚠ Nenhuma alteração foi realizada${NC}                ${BLUE}║${NC}"
        echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    fi

    echo ""
    pause_with_message "Pressione qualquer tecla para sair..."
    clear
}

# ============================================
# FLUXO PRINCIPAL
# ============================================

main() {
    check_root
    show_title
    check_current_params

    pause_with_message "Pressione qualquer tecla para iniciar..."

    remove_fastboot
    add_stable_params
    update_system
    reinstall_graphics
    regenerate_initramfs

    finalize
}

# ============================================
# EXECUÇÃO
# ============================================

main
