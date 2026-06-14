#!/bin/bash

set -euo pipefail
trap 'clear; exit 0' INT

DOTFILES_DIR="$HOME/BugTheme-dotfiles"
BACKUP_DIR="$DOTFILES_DIR/files"
BASELINE_DIR="$DOTFILES_DIR/.baseline"
META_FILE="$BACKUP_DIR/.meta"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')

KDE_CONFIG_PATTERNS=("k*rc" "k*rc.*" "plasma*" "kde*" "kwin*" "kscreen*" "baloo*" "dolphin*" "konsole*" "okular*" "kate*" "spectacle*" "gwenview*" "elisa*" "discover*" "akonadi*" "kmail*" "korgac*" "krunner*" "khotkeys*" "kded*" "bluedevil*" "powerdevil*" "ksmserver*" "systemsettings*" "kcm*" "Trolltech.conf" "breezerc" "auroraerc" "fontconfig" "gtk-3.0" "gtk-4.0" "zsh*" ".zshrc" ".p10k.zsh" ".bashrc" ".bash_profile" ".profile")
KDE_LOCAL_PATHS=("$HOME/.local/share/plasma" "$HOME/.local/share/color-schemes" "$HOME/.local/share/icons" "$HOME/.local/share/konsole" "$HOME/.local/share/kwin" "$HOME/.local/share/aurorae" "$HOME/.local/share/wallpapers" "$HOME/.local/share/fonts" "$HOME/.local/share/kservices5" "$HOME/.local/share/kservices6" "$HOME/.local/share/plasmoids" "$HOME/.local/share/kpackage")
EXCLUDE_PATTERNS=("*.lock" "*.socket" "*.pid" "*.log" "*.tmp" "*.bak" "cache" "Cache" "cachedir" "CacheStorage" "crash*" "Crash*" "drkonqi*" "recently-used*" "recently_used*" "session*" "Session*" "kactivitymanagerd*" "*.sqlite-wal" "*.sqlite-shm" "gvfs*" "dconf")

G='\033[0;32m' Y='\033[1;33m' R='\033[0;31m' C='\033[0;36m' B='\033[1;34m' BLD='\033[1m' N='\033[0m'
_log()    { echo -e "  $*"; }
_ok()     { echo -e "  ${G}✓${N} $*"; }
_warn()   { echo -e "  ${Y}!${N} $*"; }
_header() { echo -e "\n${C}==> $*${N}"; }

# Barra de progresso inteligente (\r volta ao início, \033[K limpa a linha)
_progress() {
    local current=$1 total=$2 item=$3
    local pct=$(( current * 100 / total ))
    local short_item="${item:0:55}"
    printf "\r\033[K  ${C}[%3d%%]${N} %s" "$pct" "$short_item"
}

select_menu() {
    local prompt="$1"
    shift
    local options=("$@")
    local choice=0
    local key seq
    while true; do
        clear >&2
        echo -e "${B}${prompt}${N}\n" >&2
        for i in "${!options[@]}"; do
            if [ $i -eq $choice ]; then
                echo -e "  ${BLD}${G}→ ${options[$i]}${N}" >&2
            else
                echo -e "    ${options[$i]}" >&2
            fi
        done
        echo -e "\n${Y}↑ ↓ navegar  |  Enter confirma  |  Backspace voltar  |  Ctrl+C sair${N}" >&2
        read -rsn1 key
        if [[ "$key" == $'\x7f' || "$key" == $'\b' ]]; then
            echo "BACK"; return
        elif [ "$key" = $'\x1b' ]; then
            read -rsn2 -t 0.1 seq 2>/dev/null || true
            case $seq in
                '[A') ((choice > 0)) && ((choice--)) ;;
                '[B') ((choice < ${#options[@]} - 1)) && ((choice++)) ;;
            esac
        elif [ -z "$key" ]; then
            echo "$choice"; return
        fi
    done
}

confirm_dialog() {
    local prompt="$1"
    local choice=1
    local key seq
    while true; do
        clear >&2
        echo -e "${B}${prompt}${N}\n" >&2
        if [ $choice -eq 0 ]; then
            echo -e "  ${BLD}${G}→ Sim (Y/S) ←${N}          Não, Voltar (N)" >&2
        else
            echo -e "    Sim (Y/S)          ${BLD}${G}→ Não, Voltar (N) ←${N}" >&2
        fi
        echo -e "\n${Y}← → navegar  |  Y/S/N teclado  |  Enter confirma  |  Backspace voltar  |  Ctrl+C sair${N}" >&2
        read -rsn1 key
        if [[ "$key" == $'\x7f' || "$key" == $'\b' ]]; then
            echo "BACK"; return
        elif [ "$key" = $'\x1b' ]; then
            read -rsn2 -t 0.1 seq 2>/dev/null || true
            case $seq in '[D') choice=0 ;; '[C') choice=1 ;; esac
        elif [[ "$key" == "y" || "$key" == "Y" || "$key" == "s" || "$key" == "S" ]]; then
            echo 0; return
        elif [[ "$key" == "n" || "$key" == "N" ]]; then
            echo 1; return
        elif [ -z "$key" ]; then
            echo "$choice"; return
        fi
    done
}

_matches_exclude() {
    local file=$(basename "$1")
    for pat in "${EXCLUDE_PATTERNS[@]}"; do [[ "$file" == $pat ]] && return 0; done
    [[ "$1" == *"/cache/"* || "$1" == *"/Cache/"* || "$1" == *"/.cache/"* ]] && return 0
    return 1
}

_matches_kde_pattern() {
    local file=$(basename "$1")
    for pat in "${KDE_CONFIG_PATTERNS[@]}"; do [[ "$file" == $pat ]] && return 0; done
    return 1
}

_collect_config_files() {
    local results=()
    while IFS= read -r -d '' f; do
        _matches_exclude "$f" && continue
        _matches_kde_pattern "$f" && results+=("$f") && continue
    done < <(find "$HOME/.config" -maxdepth 3 -type f -print0 2>/dev/null)
    printf '%s\n' "${results[@]}"
}

_collect_local_dirs() {
    local results=()
    for path in "${KDE_LOCAL_PATHS[@]}"; do [[ -d "$path" ]] && results+=("$path"); done
    printf '%s\n' "${results[@]}"
}

_file_hash() { sha256sum "$1" 2>/dev/null | cut -d' ' -f1; }
_relative_to_home() { echo "${1/#$HOME\//}"; }
_baseline_path() { echo "$BASELINE_DIR/$(_relative_to_home "$1").sha256"; }

generate_baseline() {
    clear
    _header "Escaneando arquivos para gerar Baseline..."
    mkdir -p "$BASELINE_DIR"

    mapfile -t config_files < <(_collect_config_files)
    local total_configs=${#config_files[@]}
    local count=0

    for f in "${config_files[@]}"; do
        (( count++ )) || true
        _progress "$count" "$total_configs" "Analisando: $(basename "$f")"

        local bpath=$(_baseline_path "$f")
        mkdir -p "$(dirname "$bpath")"
        _file_hash "$f" > "$bpath"
    done
    echo ""

    echo "$TIMESTAMP" > "$BASELINE_DIR/.generated"
    _ok "Baseline gerado com $count arquivos em $TIMESTAMP"
}

_is_modified_from_baseline() {
    local f="$1" bpath=$(_baseline_path "$1")
    [[ ! -f "$bpath" ]] && return 0
    [[ "$(_file_hash "$f")" != "$(cat "$bpath")" ]] && return 0
    return 1
}

backup() {
    clear
    _header "Iniciando backup inteligente..."
    local has_baseline=true
    [[ ! -d "$BASELINE_DIR" ]] && has_baseline=false
    if [[ "$has_baseline" == false ]]; then _warn "Nenhum baseline detectado. Salvando tudo..."; fi

    mkdir -p "$BACKUP_DIR/config" "$BACKUP_DIR/local"
    local saved=0 skipped=0

    _log "Coletando arquivos de configuração..."
    mapfile -t config_files < <(_collect_config_files)
    local total_configs=${#config_files[@]}
    local current_config=0

    for f in "${config_files[@]}"; do
        (( current_config++ )) || true
        local rel=$(_relative_to_home "$f")
        _progress "$current_config" "$total_configs" "Lendo: $rel"

        if [[ "$has_baseline" == true ]] && ! _is_modified_from_baseline "$f"; then
            (( skipped++ )) || true
            continue
        fi

        local dst="$BACKUP_DIR/$rel"
        mkdir -p "$(dirname "$dst")"

        # A MÁGICA DE VOLTA AQUI: Checa se é diferente. Se for, limpa a barra, avisa na tela e copia!
        if [[ ! -f "$dst" ]] || ! cmp -s "$f" "$dst"; then
            printf "\r\033[K" # Limpa a linha da barra de progresso
            _ok "Atualizado/Novo: $rel"
            cp "$f" "$dst"
            (( saved++ )) || true
        else
            (( skipped++ )) || true
        fi
    done
    echo "" # Pula linha após a primeira barra terminar

    _log "Sincronizando diretórios locais de temas/ícones..."
    mapfile -t local_dirs < <(_collect_local_dirs)
    local total_dirs=${#local_dirs[@]}
    local current_dir=0

    for dir in "${local_dirs[@]}"; do
        (( current_dir++ )) || true
        # Correção do bug do "Sync: /" da sua print, agora mostra a pasta exata!
        local folder_name=$(basename "$dir")
        _progress "$current_dir" "$total_dirs" "Sync: $folder_name/"

        local rel=$(_relative_to_home "$dir")
        local dst="$BACKUP_DIR/$rel"
        mkdir -p "$dst"

        # Rsync roda rápido e já copia só as novidades nativamente
        rsync -a --delete "$dir/" "$dst/" 2>/dev/null || true
    done
    echo "" # Pula linha após a segunda barra terminar

    # Verificação final para arquivos de shell (.bashrc, .zshrc, etc)
    local shell_files=("$HOME/.zshrc" "$HOME/.p10k.zsh" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile")
    for sf in "${shell_files[@]}"; do
        [[ ! -f "$sf" ]] && continue
        local rel=$(_relative_to_home "$sf"); local dst="$BACKUP_DIR/$rel"

        if [[ ! -f "$dst" ]] || ! cmp -s "$sf" "$dst"; then
            printf "\r\033[K"
            _ok "Atualizado/Novo: $rel"
            cp "$sf" "$dst"; (( saved++ )) || true
        fi
    done

    echo -e "timestamp=$TIMESTAMP\nsaved=$saved\nskipped=$skipped\nbaseline=$has_baseline" > "$META_FILE"
    _header "Backup concluído (Salvos/Atualizados: $saved | Pulados/Intactos: $skipped)"
    echo ""; read -n 1 -s -r -p "Pressione qualquer tecla para voltar..."
}

restore() {
    if [ ! -d "$BACKUP_DIR" ]; then clear; _warn "Nenhum backup encontrado."; echo ""; read -n 1 -s -r -p "Voltar..."; return; fi

    local step=1
    while true; do
        if [ $step -eq 1 ]; then
            conf1=$(confirm_dialog "Quer mesmo continuar e fazer a restauração completa do seu KDE Plasma de acordo com seu arquivo Backup salvo?")
            [[ "$conf1" == "BACK" || "$conf1" -eq 1 ]] && return
            step=2
        elif [ $step -eq 2 ]; then
            conf2=$(confirm_dialog "Tem certeza absoluta? (O Plasma será reiniciado)")
            [[ "$conf2" == "BACK" ]] && { step=1; continue; }
            [[ "$conf2" -eq 1 ]] && return
            break
        fi
    done

    clear
    _header "Restaurando configurações..."
    [[ -f "$META_FILE" ]] && _log "Backup Data: $(grep '^timestamp=' "$META_FILE" | cut -d= -f2-)"

    _log "Restaurando ~/.config..."
    _progress 50 100 "Extraindo configurações base..."
    [[ -d "$BACKUP_DIR/.config" ]] && rsync -a "$BACKUP_DIR/.config/" "$HOME/.config/" 2>/dev/null || true

    _progress 100 100 "Extraindo arquivos de sistema..."
    echo ""

    _log "Restaurando ~/.local/share..."
    [[ -d "$BACKUP_DIR/.local" ]] && rsync -a "$BACKUP_DIR/.local/" "$HOME/.local/" 2>/dev/null || true

    for sf in ".zshrc" ".p10k.zsh" ".bashrc" ".bash_profile" ".profile"; do
        [[ -f "$BACKUP_DIR/$sf" ]] && cp "$BACKUP_DIR/$sf" "$HOME/$sf" && _ok "~/$sf"
    done

    _header "Aplicando ao Plasma..."
    kbuildsycoca6 --noincremental 2>/dev/null || kbuildsycoca5 --noincremental 2>/dev/null || true
    plasmashell --replace &>/dev/null &
    disown
    _ok "Restauração concluída. Pressione qualquer tecla..."
    read -n 1 -s -r
}

status() {
    clear
    _header "Status do BugBackup"
    if [[ -f "$BASELINE_DIR/.generated" ]]; then _log "Baseline     : $(cat "$BASELINE_DIR/.generated")"; else _warn "Baseline     : Inativo"; fi
    if [[ -f "$META_FILE" ]]; then
        while IFS='=' read -r key val; do
            case "$key" in
                timestamp) _log "Data Backup  : $val" ;;
                saved)     _log "Arq. Salvos  : $val" ;;
                baseline)  _log "Base Ativa   : $val" ;;
            esac
        done < "$META_FILE"
        _log "Tamanho      : $(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1)"
    else _warn "Backup       : Nenhum realizado"; fi
    echo ""
    read -n 1 -s -r -p "Pressione qualquer tecla para voltar..."
}

MENU_OPTS=("Backup (Salvar Modificações)" "Restore (Aplicar Backup)" "Status e Detalhes" "Gerar Baseline Limpa" "Sair")
while true; do
    IDX=$(select_menu "BugBackup — Smart KDE Backup" "${MENU_OPTS[@]}")
    case $IDX in
        0) backup ;;
        1) restore ;;
        2) status ;;
        3) generate_baseline; echo ""; read -n 1 -s -r -p "Pressione qualquer tecla para voltar..." ;;
        4|BACK) clear; exit 0 ;;
    esac
done
