#!/usr/bin/env bash
clear
set -euo pipefail

declare -a SSIDS SIGNALS SECURITIES
IFACE=""
CHOSEN=0
PASS=""

_cleanup() {
    tput cnorm 2>/dev/null || true
    tput rmcup 2>/dev/null || true
    stty sane 2>/dev/null || true
    echo ""
}
trap '_cleanup' EXIT
trap '_cleanup; exit 130' INT TERM

_deps() {
    for cmd in nmcli tput stty; do
        command -v "$cmd" &>/dev/null || { printf 'Erro: %s não encontrado.\n' "$cmd"; exit 1; }
    done
}

_ensure_services() {
    if ! systemctl is-active --quiet NetworkManager 2>/dev/null; then
        printf '\033[33mNetworkManager inativo. Iniciando...\033[0m\n'
        systemctl start NetworkManager 2>/dev/null || {
            printf '\033[31mFalha ao iniciar NetworkManager. Tente: sudo systemctl start NetworkManager\033[0m\n'
            exit 1
        }
        sleep 2
    fi

    if ! systemctl is-active --quiet wpa_supplicant 2>/dev/null; then
        printf '\033[33mwpa_supplicant inativo. Iniciando...\033[0m\n'
        systemctl start wpa_supplicant 2>/dev/null || true
        sleep 1
    fi
}

_wifi_on() {
    local state
    state=$(nmcli radio wifi 2>/dev/null || echo "disabled")
    if [[ "$state" != "enabled" ]]; then
        printf '\033[33mWiFi desativado. Ativando...\033[0m\n'
        nmcli radio wifi on
        sleep 3
    fi
}

_detect_iface() {
    local iface
    iface=$(nmcli -t -f DEVICE,TYPE,STATE dev 2>/dev/null \
        | awk -F: '$2=="wifi"{print $1; exit}')
    if [[ -z "$iface" ]]; then
        iface=$(ip link show 2>/dev/null \
            | awk -F: '$2~/wl/{gsub(/ /,"",$2); print $2; exit}')
    fi
    printf '%s' "$iface"
}

_scan() {
    local iface=$1
    nmcli -t -f SSID,SIGNAL,SECURITY dev wifi list ifname "$iface" --rescan yes 2>/dev/null \
        | awk -F: '$1!="" && $1!="--" && NF>=2' \
        | sort -t: -k2 -rn \
        | awk -F: '!seen[$1]++' \
        | head -30
}

_bar() {
    local s=$1
    if   (( s >= 80 )); then printf "▰▰▰▰▰  %3d%%" "$s"
    elif (( s >= 60 )); then printf "▰▰▰▰▱  %3d%%" "$s"
    elif (( s >= 40 )); then printf "▰▰▰▱▱  %3d%%" "$s"
    elif (( s >= 20 )); then printf "▰▰▱▱▱  %3d%%" "$s"
    else                     printf "▰▱▱▱▱  %3d%%" "$s"
    fi
}

_color() {
    local s=$1
    if   (( s >= 70 )); then printf '\033[32m'
    elif (( s >= 40 )); then printf '\033[33m'
    else                     printf '\033[31m'
    fi
}

_draw() {
    local sel=$1 total=${#SSIDS[@]}
    local vis=14 start=0
    (( sel >= vis )) && start=$(( sel - vis + 1 ))

    tput cup 0 0
    tput ed

    printf '\033[1;36m WiFi Connect\033[0m   \033[90m[↑↓] mover   [Enter] conectar   [Ctrl+C] sair\033[0m\n'
    printf '\033[90m ─────────────────────────────────────────────────────\033[0m\n'

    local shown=0
    for (( i=start; i<total && shown<vis; i++, shown++ )); do
        local ssid="${SSIDS[$i]}"
        local sig="${SIGNALS[$i]}"
        local sec="${SECURITIES[$i]}"
        local col lock bar

        col=$(_color "$sig")
        bar=$(_bar "$sig")
        [[ "$sec" != "--" && -n "$sec" ]] && lock=" 🔒" || lock="   "

        if (( i == sel )); then
            printf '\033[1;7m ▶ %-30s  %s%s\033[0m%s\033[0m\n' \
                "${ssid:0:30}" "$col" "$bar" "$lock"
        else
            printf '\033[2m   %-30s\033[0m  %s%s\033[0m%s\n' \
                "${ssid:0:30}" "$col" "$bar" "$lock"
        fi
    done

    printf '\033[90m ─────────────────────────────────────────────────────\033[0m\n'
    printf '\033[90m %d/%d redes\033[0m\n' "$(( sel+1 ))" "$total"
}

_readkey() {
    local k1 k2 k3
    IFS= read -r -s -n1 k1
    if [[ "$k1" == $'\x1b' ]]; then
        IFS= read -r -s -n1 -t 0.1 k2 || { printf 'ESC'; return; }
        if [[ "$k2" == '[' ]]; then
            IFS= read -r -s -n1 -t 0.1 k3 || { printf 'ESC'; return; }
            printf 'ESC_%s' "$k3"
        else
            printf 'ESC'
        fi
    else
        printf '%s' "$k1"
    fi
}

_menu() {
    local sel=0 total=${#SSIDS[@]}

    tput smcup
    tput civis
    tput clear

    while true; do
        _draw "$sel"

        local key
        key=$(_readkey)

        case "$key" in
            ESC_A)
                (( sel > 0 )) && sel=$(( sel - 1 ))
                ;;
            ESC_B)
                (( sel < total - 1 )) && sel=$(( sel + 1 ))
                ;;
            ''|$'\n'|$'\r')
                break
                ;;
        esac
    done

    tput rmcup
    tput cnorm
    CHOSEN="$sel"
}

_password() {
    local ssid=$1 sec=$2

    printf '\n\033[1;36m %s\033[0m\n' "$ssid"

    if [[ "$sec" == "--" || -z "$sec" ]]; then
        printf '\033[90m Rede aberta, conectando sem senha...\033[0m\n'
        PASS=""
        return
    fi

    printf '\033[1m Senha: \033[0m'
    PASS=""
    local ch
    stty -echo -icanon min 1 time 0
    while IFS= read -r -s -n1 ch; do
        case "$ch" in
            $'\n'|$'\r'|'') break ;;
            $'\x7f'|$'\x08')
                if (( ${#PASS} > 0 )); then
                    PASS="${PASS%?}"
                    printf '\b \b'
                fi
                ;;
            *) PASS+="$ch"; printf '•' ;;
        esac
    done
    stty sane
    printf '\n'
}

_connect() {
    local ssid=$1 pass=$2
    printf '\033[90m Conectando...\033[0m\n'

    local out="" rc=0
    if [[ -z "$pass" ]]; then
        out=$(nmcli dev wifi connect "$ssid" 2>&1) || rc=$?
    else
        out=$(nmcli dev wifi connect "$ssid" password "$pass" 2>&1) || rc=$?
    fi

    if (( rc == 0 )); then
        printf '\033[1;32m ✔ Conectado!\033[0m\n'
        local ip
        ip=$(nmcli -g IP4.ADDRESS dev show "$IFACE" 2>/dev/null | head -1 | cut -d/ -f1 || true)
        [[ -n "$ip" ]] && printf '\033[90m IP: %s\033[0m\n' "$ip"
    else
        printf '\033[1;31m ✘ Falha ao conectar:\033[0m\n %s\n' "$out"
        exit 1
    fi
}

main() {
    _deps
    _ensure_services
    _wifi_on

    IFACE=$(_detect_iface)
    [[ -z "$IFACE" ]] && { printf '\033[31mNenhuma interface WiFi encontrada.\033[0m\n'; exit 1; }

    printf '\033[90m Escaneando redes em %s...\033[0m\r' "$IFACE"
    local raw=""
    raw=$(_scan "$IFACE")
    printf '\033[2K\r'

    [[ -z "$raw" ]] && { printf '\033[31m Nenhuma rede encontrada. Tente novamente.\033[0m\n'; exit 1; }

    while IFS=: read -r ssid sig sec _rest; do
        SSIDS+=("$ssid")
        SIGNALS+=("${sig:-0}")
        SECURITIES+=("${sec:---}")
    done <<< "$raw"

    (( ${#SSIDS[@]} == 0 )) && { printf '\033[31m Nenhuma rede.\033[0m\n'; exit 1; }

    _menu

    _password "${SSIDS[$CHOSEN]}" "${SECURITIES[$CHOSEN]}"
    _connect "${SSIDS[$CHOSEN]}" "$PASS"
}

main "$@"
clear
