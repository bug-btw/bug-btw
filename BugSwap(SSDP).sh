#!/usr/bin/env bash

if [ "$EUID" -ne 0 ]; then exec sudo bash "$0" "$@"; fi
trap 'clear; exit 0' INT

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

G='\033[0;32m' Y='\033[1;33m' R='\033[0;31m' C='\033[0;36m' B='\033[1;34m' BLD='\033[1m' N='\033[0m'
ok()   { echo -e "  ${G}[✓]${N}  $*"; }
warn() { echo -e "  ${Y}[!]${N}  $*"; }
die()  { echo -e "  ${R}[✗]${N}  $*"; exit 1; }
hdr()  { echo -e "\n${C}${BLD}── $* ${N}"; }

MNT_DIR="/mnt/KingstonSSD"
PRIO_SWAP=5
SWAPPINESS=150
VFS_CACHE_PRESSURE=10
ZRAM_SIZE="8G"

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

ROOT_DEV=$(findmnt -n -o SOURCE /)
ROOT_DISK=$(lsblk -no PKNAME "$ROOT_DEV" 2>/dev/null)
[ -z "$ROOT_DISK" ] && ROOT_DISK=$(echo "$ROOT_DEV" | sed 's/[0-9]*//g' | sed 's/p$//')
[[ "$ROOT_DISK" != /dev/* ]] && ROOT_DISK="/dev/$ROOT_DISK"

mapfile -t RAW_DISKS < <(lsblk -dno NAME,TYPE | awk '$2=="disk" {print "/dev/"$1}')
DISKS_AVAILABLE=()
DISKS_LABELS=()

for disk in "${RAW_DISKS[@]}"; do
    if [[ "$disk" != "$ROOT_DISK" ]]; then
        model=$(lsblk -dno MODEL "$disk" 2>/dev/null | xargs)
        size=$(lsblk -dno SIZE "$disk" 2>/dev/null | xargs)
        DISKS_AVAILABLE+=("$disk")
        DISKS_LABELS+=("$disk ($model - $size)")
    fi
done

[ ${#DISKS_AVAILABLE[@]} -eq 0 ] && die "Nenhum SSD secundário encontrado."

while true; do
    DISK_IDX=$(select_menu "Selecione o SSD Secundário para aplicar o Swap:" "${DISKS_LABELS[@]}")
    [[ "$DISK_IDX" == "BACK" ]] && { clear; exit 0; }

    TARGET_DISK="${DISKS_AVAILABLE[$DISK_IDX]}"
    SIZES=("8GiB" "12GiB" "16GiB" "24GiB" "32GiB" "46GiB" "48GiB" "56GiB" "64GiB")

    while true; do
        SIZE_IDX=$(select_menu "Selecione o tamanho da Partição Swap no $TARGET_DISK:" "${SIZES[@]}")
        [[ "$SIZE_IDX" == "BACK" ]] && break

        TARGET_SIZE="${SIZES[$SIZE_IDX]//GiB/}"

        clear
        hdr "INICIANDO OTIMIZAÇÃO E PARTICIONAMENTO"
        ok "Disco Alvo   : $TARGET_DISK"
        ok "Tamanho Swap : ${TARGET_SIZE}GiB"

        PART_SWAP="${TARGET_DISK}1"
        PART_DATA="${TARGET_DISK}2"
        [[ "$TARGET_DISK" == *nvme* ]] && PART_SWAP="${TARGET_DISK}p1" && PART_DATA="${TARGET_DISK}p2"

        hdr "LIMPEZA DE SWAPS"
        while read -r active; do
            [ -n "$active" ] || continue
            swapoff "$active" 2>/dev/null && warn "Swap desativado: $active"
        done < <(swapon --show --noheadings --raw 2>/dev/null | awk '{print $1}')

        for f in /swapfile /swapfile_adata /swapfile_kingston /.swapfile /.swapfile_swap-adata //.swapfile; do
            if [ -f "$f" ]; then rm -f "$f" && ok "Arquivo deletado: $f"; fi
        done

        umount -fl "${TARGET_DISK}"* 2>/dev/null || true

        hdr "PARTICIONAMENTO"
        wipefs -a "$TARGET_DISK" 2>/dev/null || true
        sgdisk --zap-all "$TARGET_DISK" &>/dev/null || true

        parted -a optimal -s "$TARGET_DISK" mklabel gpt 2>/dev/null
        parted -a optimal -s "$TARGET_DISK" mkpart primary linux-swap 0% ${TARGET_SIZE}GiB 2>/dev/null
        parted -a optimal -s "$TARGET_DISK" mkpart primary xfs ${TARGET_SIZE}GiB 100% 2>/dev/null

        udevadm settle; partprobe "$TARGET_DISK" 2>/dev/null; sleep 3; udevadm settle
        [ -b "$PART_SWAP" ] && [ -b "$PART_DATA" ] || die "Erro ao registrar partições."

        hdr "FORMATANDO E ATIVANDO"
        mkswap -f -L "KingstonSwap" "$PART_SWAP" > /dev/null || die "Falha mkswap"
        swapon -p "$PRIO_SWAP" "$PART_SWAP" || die "Falha swapon"
        ok "Swap de ${TARGET_SIZE}GiB Ativado!"

        mkfs.xfs -f -L "KingstonSSD" "$PART_DATA" > /dev/null || die "Falha mkfs.xfs"
        [ -d "$MNT_DIR" ] || mkdir -p "$MNT_DIR"
        mount -t xfs "$PART_DATA" "$MNT_DIR" || die "Falha mount"
        ok "Dados formatados em XFS."

        hdr "CONFIGURANDO FSTAB"
        cp /etc/fstab /etc/fstab.bak
        grep -v -E '^[^#].*[[:space:]]swap[[:space:]]' /etc/fstab | grep -v "$MNT_DIR" > /tmp/fstab_clean
        mv /tmp/fstab_clean /etc/fstab

        UUID_SWAP=$(blkid -s UUID -o value "$PART_SWAP")
        UUID_DATA=$(blkid -s UUID -o value "$PART_DATA")
        echo "UUID=$UUID_SWAP none swap defaults,pri=$PRIO_SWAP 0 0" >> /etc/fstab
        echo "UUID=$UUID_DATA $MNT_DIR xfs defaults,noatime,rw,user,nofail 0 2" >> /etc/fstab
        ok "fstab configurado com persistência estável."

        hdr "PERSISTÊNCIA DO ZRAM"
        cat << EOF > /etc/systemd/system/zram-swap.service
[Unit]
Description=ZRAM Swap (8GiB)
After=local-fs.target
[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/bash -c 'modprobe zram num_devices=1 2>/dev/null || true && echo 1 > /sys/block/zram0/reset 2>/dev/null || true && zramctl --size $ZRAM_SIZE --algorithm zstd /dev/zram0 && mkswap /dev/zram0 && swapon -p 100 /dev/zram0'
ExecStop=/usr/bin/bash -c 'swapoff /dev/zram0 && echo 1 > /sys/block/zram0/reset'
[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable --now zram-swap.service >/dev/null 2>&1
        systemctl restart zram-swap.service 2>/dev/null || true

        chmod 777 "$MNT_DIR"
        REAL_USER=$(who am i | awk '{print $1}')
        [ -z "$REAL_USER" ] && REAL_USER=$(logname 2>/dev/null)
        if [ -n "$REAL_USER" ]; then chown -R "$REAL_USER":"$REAL_USER" "$MNT_DIR" 2>/dev/null || true; fi

        hdr "APLICANDO CONTROLE AGRESSIVO DE MEMÓRIA"
        declare -A KP=([vm.swappiness]=$SWAPPINESS [vm.vfs_cache_pressure]=$VFS_CACHE_PRESSURE [vm.dirty_ratio]=15 [vm.dirty_background_ratio]=5)
        for k in "${!KP[@]}"; do
            sysctl -w "$k=${KP[$k]}" > /dev/null
            grep -q "^${k}" /etc/sysctl.conf 2>/dev/null && sed -i "s|^${k}[[:space:]]*=.*|${k}=${KP[$k]}|" /etc/sysctl.conf || echo "${k}=${KP[$k]}" >> /etc/sysctl.conf
        done

        echo -e "\n${G}══ SUCESSO ══${N}\n"
        swapon --show
        exit 0
    done
done
