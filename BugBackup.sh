#!/bin/bash

DOTFILES_DIR="$HOME/BugTheme-dotfiles"
BACKUP_DIR="$DOTFILES_DIR/files"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
CHANGED=0

backup() {
    mkdir -p "$BACKUP_DIR/config"
    mkdir -p "$BACKUP_DIR/local/plasma"
    mkdir -p "$BACKUP_DIR/local/color-schemes"
    mkdir -p "$BACKUP_DIR/local/icons"

    copy_if_changed() {
        local src="$1"
        local dst="$2"

        if [ ! -f "$src" ]; then
            return
        fi

        if [ ! -f "$dst" ] || ! cmp -s "$src" "$dst"; then
            cp "$src" "$dst"
            echo "  atualizado: $(basename $src)"
            CHANGED=1
        fi
    }

    copy_dir_if_changed() {
        local src="$1"
        local dst="$2"

        if [ ! -d "$src" ]; then
            return
        fi

        rsync -a --checksum "$src" "$dst" 2>/dev/null && CHANGED=1
    }

    echo "==> Verificando arquivos..."

    copy_if_changed ~/.config/plasma-org.kde.plasma.desktop-appletsrc "$BACKUP_DIR/config/plasma-org.kde.plasma.desktop-appletsrc"
    copy_if_changed ~/.config/plasmarc "$BACKUP_DIR/config/plasmarc"
    copy_if_changed ~/.config/kdeglobals "$BACKUP_DIR/config/kdeglobals"
    copy_if_changed ~/.config/kwinrc "$BACKUP_DIR/config/kwinrc"
    copy_if_changed ~/.config/kglobalshortcutsrc "$BACKUP_DIR/config/kglobalshortcutsrc"
    copy_if_changed ~/.config/kcminputrc "$BACKUP_DIR/config/kcminputrc"
    copy_if_changed ~/.config/kscreenlockerrc "$BACKUP_DIR/config/kscreenlockerrc"
    copy_if_changed ~/.zshrc "$BACKUP_DIR/config/zshrc"
    copy_if_changed ~/.p10k.zsh "$BACKUP_DIR/config/p10k.zsh"

    copy_dir_if_changed ~/.local/share/plasma/look-and-feel/BugTheme "$BACKUP_DIR/local/plasma/"
    copy_dir_if_changed ~/.local/share/color-schemes/. "$BACKUP_DIR/local/color-schemes/"
    copy_dir_if_changed ~/.local/share/icons/. "$BACKUP_DIR/local/icons/"

    echo "$TIMESTAMP" > "$BACKUP_DIR/.last_backup"

    if [ $CHANGED -eq 1 ]; then
        echo "==> Backup atualizado em $TIMESTAMP"
    else
        echo "==> Nada mudou desde o último backup"
    fi
}

restore() {
    if [ ! -d "$BACKUP_DIR" ]; then
        echo "==> Erro: nenhum backup encontrado em $BACKUP_DIR"
        exit 1
    fi

    if [ -f "$BACKUP_DIR/.last_backup" ]; then
        echo "==> Restaurando backup de $(cat $BACKUP_DIR/.last_backup)..."
    fi

    cp "$BACKUP_DIR/config/plasma-org.kde.plasma.desktop-appletsrc" ~/.config/ 2>/dev/null
    cp "$BACKUP_DIR/config/plasmarc" ~/.config/ 2>/dev/null
    cp "$BACKUP_DIR/config/kdeglobals" ~/.config/ 2>/dev/null
    cp "$BACKUP_DIR/config/kwinrc" ~/.config/ 2>/dev/null
    cp "$BACKUP_DIR/config/kglobalshortcutsrc" ~/.config/ 2>/dev/null
    cp "$BACKUP_DIR/config/kcminputrc" ~/.config/ 2>/dev/null
    cp "$BACKUP_DIR/config/kscreenlockerrc" ~/.config/ 2>/dev/null
    cp "$BACKUP_DIR/config/zshrc" ~/.zshrc 2>/dev/null
    cp "$BACKUP_DIR/config/p10k.zsh" ~/.p10k.zsh 2>/dev/null

    mkdir -p ~/.local/share/plasma/look-and-feel/
    rsync -a "$BACKUP_DIR/local/plasma/BugTheme" ~/.local/share/plasma/look-and-feel/ 2>/dev/null
    rsync -a "$BACKUP_DIR/local/color-schemes/." ~/.local/share/color-schemes/ 2>/dev/null
    rsync -a "$BACKUP_DIR/local/icons/." ~/.local/share/icons/ 2>/dev/null

    echo "==> Arquivos restaurados"
    echo "==> Reiniciando Plasma..."
    plasmashell --replace &>/dev/null &
    echo "==> Concluído"
}

status() {
    if [ ! -f "$BACKUP_DIR/.last_backup" ]; then
        echo "==> Nenhum backup realizado ainda"
        exit 0
    fi

    echo "==> Último backup: $(cat $BACKUP_DIR/.last_backup)"
    echo "==> Tamanho total: $(du -sh $BACKUP_DIR | cut -f1)"
}

case "$1" in
    backup)  backup  ;;
    restore) restore ;;
    status)  status  ;;
    *)
        echo "Uso: $0 [backup|restore|status]"
        echo ""
        echo "  backup   Salva ou atualiza os arquivos de configuração"
        echo "  restore  Restaura os arquivos em uma nova máquina"
        echo "  status   Mostra data do último backup e tamanho"
        ;;
esac
