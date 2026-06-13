#!/bin/bash

echo "==> Instalando dependências..."
sudo pacman -S --noconfirm fzf fd bat procs btop

echo "==> Fazendo backup do .zshrc atual..."
cp ~/.zshrc ~/.zshrc.bak 2>/dev/null

echo "==> Escrevendo novo .zshrc..."
cat > ~/.zshrc << 'EOF'

 typeset -g POWERLEVEL9K_INSTANT_PROMPT=quiet
 typeset -g POWERLEVEL9K_INSTANT_PROMPT=off

 # Enable Powerlevel10k instant prompt

if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then

  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"

fi


export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME="powerlevel10k/powerlevel10k"

plugins=(git zsh-autosuggestions zsh-syntax-highlighting)

source $ZSH/oh-my-zsh.sh

[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh


# ============================================================

# HISTORY

# ============================================================

HISTSIZE=10000

SAVEHIST=10000

HISTFILE=~/.zsh_history

setopt APPEND_HISTORY

setopt SHARE_HISTORY

setopt HIST_IGNORE_DUPS

setopt HIST_IGNORE_ALL_DUPS

setopt HIST_FIND_NO_DUPS

setopt HIST_IGNORE_SPACE

setopt HIST_SAVE_NO_DUPS

setopt INC_APPEND_HISTORY


# ============================================================

# VI MODE

# ============================================================

bindkey -v

export KEYTIMEOUT=1


function zle-keymap-select {

  if [[ ${KEYMAP} == vicmd ]] || [[ $1 = 'block' ]]; then

    echo -ne '\e[1 q'

  elif [[ ${KEYMAP} == main ]] || [[ $1 = 'beam' ]]; then

    echo -ne '\e[5 q'

  fi

}

zle -N zle-keymap-select


zle-line-init() {

    zle -K viins

    echo -ne "\e[5 q"

}

zle -N zle-line-init


# ============================================================

# KEYBOARD SHORTCUTS

# ============================================================

bindkey '^L' clear-screen

bindkey '^R' history-incremental-search-backward

bindkey '^A' beginning-of-line

bindkey '^E' end-of-line

bindkey '^K' kill-line

bindkey '^U' kill-whole-line

bindkey '^W' backward-kill-word

bindkey '^n' autosuggest-accept

bindkey '^j' autosuggest-accept

bindkey '^[^?' backward-kill-word


# ============================================================

# FZF

# ============================================================

if command -v fzf &> /dev/null; then

    source <(fzf --zsh)

    export FZF_DEFAULT_OPTS='--color=16,bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8 --color=fg:#cdd6f4,header:#f38ba8,info:#cba6f7,marker:#f5e0dc --color=fg+:#cdd6f4,preview-bg:#313244,prompt:#cba6f7,pointer:#f5e0dc'

fi


# ============================================================

# ALIASES

# ============================================================

alias ll='ls -lAhS'

alias la='ls -lah'

alias l='ls -CF'

alias cl='clear'

alias update='sudo pacman -Syu'

alias install='sudo pacman -S'

alias remove='sudo pacman -R'

alias search='pacman -Ss'

alias clean='sudo pacman -Sc'

alias autoremove='sudo pacman -Rs $(pacman -Qdtq)'

alias v='nvim'

alias vi='nvim'

alias vim='nvim'

alias ..='cd ..'

alias ...='cd ../..'

alias ....='cd ../../..'

alias mkdir='mkdir -pv'

alias cp='cp -iv'

alias mv='mv -iv'

alias rm='rm -iv'

alias grep='grep --color=auto'

alias diff='diff --color=auto'

alias du='du -h'

alias df='df -h'

alias free='free -h'

alias top='btop'

alias cat='bat'

alias find='fd'

alias ps='procs'

# ============================================================
# CUSTOM FASTFETCH FUNCTION & ALIASES
# ============================================================
bugfetch() {
    echo -e "\e[34m❯ Bug FastFetch Arch Linux\e[0m"
    echo ""
    fastfetch --logo arch2 --logo-color-1 "34" --logo-color-2 "34" --color-title "34" --color-keys "34"
    echo ""
}

alias fastfetch='bugfetch'

alias ff='bugfetch'

alias bug='cd ~'

alias desktop='cd ~/Desktop'

alias downloads='cd ~/Downloads'

alias documents='cd ~/Documents'

alias config='cd ~/.config'

alias dotfiles='cd ~/BugTheme-dotfiles'

alias gs='git status'

alias ga='git add'

alias gc='git commit -m'

alias gp='git push'

alias gl='git log --oneline -10'


# ============================================================

# FUNCTIONS

# ============================================================

extract() {

    if [ -f "$1" ]; then

        case "$1" in

            *.tar.bz2)   tar xjf "$1"    ;;

            *.tar.gz)    tar xzf "$1"    ;;

            *.bz2)       bunzip2 "$1"    ;;

            *.rar)       unrar x "$1"    ;;

            *.gz)        gunzip "$1"     ;;

            *.tar)       tar xf "$1"     ;;

            *.tbz2)      tar xjf "$1"    ;;

            *.tgz)       tar xzf "$1"    ;;

            *.zip)       unzip "$1"      ;;

            *.Z)         uncompress "$1" ;;

            *.7z)        7z x "$1"       ;;

            *.xz)        xz -d "$1"      ;;

            *)           echo "Cannot extract '$1'" ;;

        esac

    else

        echo "'$1' is not a file"

    fi

}


mkcd() {

    mkdir -p "$1"

    cd "$1"

}


f() {

    find . -iname "*$1*" 2>/dev/null

}


dush() {

    du -sh "$@" | sort -h

}


killp() {

    pkill -f "$1"

}


weather() {

    curl -s "wttr.in/${1:-Curitiba}?format=3"

}

# ============================================================
# INITIALIZATION COMMANDS (Executa ao abrir o terminal)
# ============================================================
ff

EOF

echo "==> Aplicando configuração..."
source ~/.zshrc 2>/dev/null

echo ""
echo "==> Concluído! Fecha e abre o Konsole para aplicar tudo."
echo "==> Backup do .zshrc anterior salvo em ~/.zshrc.bak"
