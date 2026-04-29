#!/bin/bash
# =============================================================
#  Arch Linux Custom Installer
#  Профили: server (VMware) / desktop (Hyprland + Gaming)
#  Автор: сгенерировано под твой стек
# =============================================================

set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

LOG="/tmp/arch-install.log"
> "$LOG"

log()  { echo -e "$1" | tee -a "$LOG"; }
ok()   { log "${GREEN}[✓]${NC} $1"; }
info() { log "${CYAN}[→]${NC} $1"; }
warn() { log "${YELLOW}[!]${NC} $1"; }
die()  { log "${RED}[✗] ОШИБКА: $1${NC}"; exit 1; }

step() {
    log ""
    log "${BOLD}${BLUE}━━━ $1 ━━━${NC}"
}

[[ $EUID -ne 0 ]] && die "Запусти от root (sudo bash install.sh)"
[[ ! -d /sys/firmware/efi ]] && die "Только UEFI режим. Проверь настройки BIOS."

clear
cat << 'BANNER'
  ╔══════════════════════════════════════════════╗
  ║         ARCH LINUX CUSTOM INSTALLER          ║
  ║    server (VMware dev) | desktop (Hyprland)  ║
  ╚══════════════════════════════════════════════╝
BANNER
echo ""

# ─── PROFILE ──────────────────────────────────────────────
echo -e "${BOLD}Выбери профиль:${NC}"
echo "  1) Server  — VMware, cmake/vcpkg/rsync, без GUI"
echo "  2) Desktop — Hyprland, Steam, Nvidia, полный стек"
read -rp "Профиль [1/2]: " PROFILE_CHOICE
case $PROFILE_CHOICE in
    1) PROFILE="server"  ;;
    2) PROFILE="desktop" ;;
    *) die "Неверный выбор профиля" ;;
esac

# ─── MIRROR ───────────────────────────────────────────────
echo ""
echo -e "${BOLD}Зеркало для загрузки пакетов:${NC}"
echo "  1) Россия — Yandex [по умолчанию]"
echo "  2) Германия"
echo "  3) США"
read -rp "Зеркало [1]: " MIRROR_CHOICE
MIRROR_CHOICE=${MIRROR_CHOICE:-1}

# ─── DISK ─────────────────────────────────────────────────
echo ""
echo -e "${BOLD}Доступные диски:${NC}"
lsblk -d -o NAME,SIZE,MODEL --noheadings | grep -v loop | grep -v sr | \
    awk '{printf "  /dev/%-10s %s  %s\n", $1, $2, $3}'
echo ""
read -rp "Диск для установки (например: sda, nvme0n1, vda): " DISK_NAME
DISK="/dev/$DISK_NAME"
[[ ! -b "$DISK" ]] && die "Диск $DISK не найден"

# ─── USER CREDENTIALS ─────────────────────────────────────
echo ""
read -rp "Имя пользователя: " USERNAME
[[ -z "$USERNAME" ]] && die "Имя пользователя не может быть пустым"

read -rsp "Пароль пользователя: " USER_PASS; echo
read -rsp "Пароль root:         " ROOT_PASS; echo

# ─── SWAP ─────────────────────────────────────────────────
echo ""
read -rp "Размер swap (например: 4G, 8G, или 0 — отключить) [4G]: " SWAP_SIZE
SWAP_SIZE=${SWAP_SIZE:-4G}

# ─── LUKS ─────────────────────────────────────────────────
echo ""
read -rp "Шифровать диск LUKS? [y/N]: " LUKS_CHOICE
USE_LUKS=false
if [[ "$LUKS_CHOICE" =~ ^[Yy]$ ]]; then
    USE_LUKS=true
    read -rsp "Пароль LUKS (запомни его — без него не загрузишься!): " LUKS_PASS; echo
    read -rsp "Повтори пароль LUKS: " LUKS_PASS2; echo
    [[ "$LUKS_PASS" != "$LUKS_PASS2" ]] && die "Пароли LUKS не совпадают"
fi

# ─── HOSTNAME ─────────────────────────────────────────────
echo ""
DEFAULT_HOST="arch-${PROFILE}"
read -rp "Имя хоста [$DEFAULT_HOST]: " HOSTNAME
HOSTNAME=${HOSTNAME:-$DEFAULT_HOST}

# ─── DOTFILES REPO ────────────────────────────────────────
echo ""
DEFAULT_DOTFILES="https://github.com/ТВОЙ_ЮЗЕРНЕЙМ/arch-dotfiles"
echo -e "${YELLOW}Репозиторий с конфигами (твой GitHub):${NC}"
read -rp "URL [$DEFAULT_DOTFILES]: " DOTFILES_REPO
DOTFILES_REPO=${DOTFILES_REPO:-$DEFAULT_DOTFILES}

# ─── NVIDIA AUTO-DETECT ───────────────────────────────────
NVIDIA=false
if lspci 2>/dev/null | grep -qi "NVIDIA"; then
    NVIDIA=true
    warn "Обнаружена Nvidia GPU! Будут установлены nvidia + lib32-nvidia-utils"
fi

# ─── SUMMARY ──────────────────────────────────────────────
echo ""
echo -e "${BOLD}╔═══════════════════════════════╗${NC}"
echo -e "${BOLD}║       ПАРАМЕТРЫ УСТАНОВКИ     ║${NC}"
echo -e "${BOLD}╚═══════════════════════════════╝${NC}"
echo -e "  Профиль:      ${GREEN}$PROFILE${NC}"
echo -e "  Диск:         ${RED}$DISK${NC} (будет ПОЛНОСТЬЮ СТЁРТ)"
echo -e "  Пользователь: $USERNAME"
echo -e "  Hostname:     $HOSTNAME"
echo -e "  Swap:         $SWAP_SIZE"
echo -e "  LUKS:         $USE_LUKS"
echo -e "  Nvidia:       $NVIDIA"
echo -e "  Dotfiles:     $DOTFILES_REPO"
echo ""
read -rp "⚠  Продолжить? Все данные на $DISK будут уничтожены! [y/N]: " CONFIRM
[[ ! "$CONFIRM" =~ ^[Yy]$ ]] && { echo "Отменено."; exit 0; }

# ═══════════════════════════════════════════════════════════
#  STEP 1 — MIRRORS
# ═══════════════════════════════════════════════════════════
step "1/9 | Настройка зеркал"
case $MIRROR_CHOICE in
    1)
        info "Использую Yandex Mirror (Россия)"
        cat > /etc/pacman.d/mirrorlist << 'EOF'
Server = https://mirror.yandex.ru/archlinux/$repo/os/$arch
Server = https://mirrors.nxtgen.com/archlinux/$repo/os/$arch
Server = https://mirror.surf/archlinux/$repo/os/$arch
EOF
        ;;
    2)
        info "Использую немецкие зеркала"
        reflector --country Germany --latest 5 --protocol https \
            --sort rate --save /etc/pacman.d/mirrorlist 2>>"$LOG" || true
        ;;
    3)
        info "Использую американские зеркала"
        reflector --country "United States" --latest 5 --protocol https \
            --sort rate --save /etc/pacman.d/mirrorlist 2>>"$LOG" || true
        ;;
esac

# Синхронизируем базы пакетов
pacman -Sy --noconfirm >> "$LOG" 2>&1
ok "Зеркала настроены"

# ═══════════════════════════════════════════════════════════
#  STEP 2 — PARTITIONING
# ═══════════════════════════════════════════════════════════
step "2/9 | Разметка диска $DISK"

info "Очистка диска..."
wipefs -af "$DISK" >> "$LOG" 2>&1
sgdisk -Z "$DISK" >> "$LOG" 2>&1

info "Создание разделов (EFI 512M + Root)..."
sgdisk -n 1:0:+512M -t 1:ef00 -c 1:"EFI System" "$DISK" >> "$LOG" 2>&1
sgdisk -n 2:0:0    -t 2:8300 -c 2:"Linux Root"  "$DISK" >> "$LOG" 2>&1
partprobe "$DISK" 2>/dev/null || true
sleep 1

# Определяем имена разделов (nvme → p1/p2, остальные → 1/2)
if [[ "$DISK" == *"nvme"* ]] || [[ "$DISK" == *"mmcblk"* ]]; then
    EFI_PART="${DISK}p1"
    ROOT_PART="${DISK}p2"
else
    EFI_PART="${DISK}1"
    ROOT_PART="${DISK}2"
fi

info "Форматирование EFI раздела..."
mkfs.fat -F32 -n "ARCH_EFI" "$EFI_PART" >> "$LOG" 2>&1

# ─── LUKS setup ───────────────────────────────────────────
if $USE_LUKS; then
    info "Настройка шифрования LUKS2..."
    echo -n "$LUKS_PASS" | cryptsetup luksFormat --type luks2 \
        --cipher aes-xts-plain64 --key-size 512 --hash sha512 \
        "$ROOT_PART" - >> "$LOG" 2>&1
    echo -n "$LUKS_PASS" | cryptsetup open "$ROOT_PART" cryptroot - >> "$LOG" 2>&1
    MOUNT_ROOT="/dev/mapper/cryptroot"
    ok "LUKS открыт как /dev/mapper/cryptroot"
else
    MOUNT_ROOT="$ROOT_PART"
fi

info "Форматирование root раздела (ext4)..."
mkfs.ext4 -F -L "ARCH_ROOT" "$MOUNT_ROOT" >> "$LOG" 2>&1

# ─── MOUNT ────────────────────────────────────────────────
info "Монтирование..."
mount "$MOUNT_ROOT" /mnt
mkdir -p /mnt/boot
mount "$EFI_PART" /mnt/boot

ok "Диск размечен и примонтирован"

# ═══════════════════════════════════════════════════════════
#  STEP 3 — SWAP
# ═══════════════════════════════════════════════════════════
step "3/9 | Создание swap"
if [[ "$SWAP_SIZE" != "0" ]]; then
    info "Создаю swapfile ($SWAP_SIZE)..."
    # Для btrfs нужно иначе, но у нас ext4 — ок
    dd if=/dev/zero of=/mnt/swapfile bs=1M count=$(echo "$SWAP_SIZE" | \
        sed 's/G//' | awk '{print $1*1024}') status=progress 2>>"$LOG"
    chmod 600 /mnt/swapfile
    mkswap /mnt/swapfile >> "$LOG" 2>&1
    swapon /mnt/swapfile
    ok "Swap создан: $SWAP_SIZE"
else
    info "Swap отключён"
fi

# ═══════════════════════════════════════════════════════════
#  STEP 4 — PACSTRAP
# ═══════════════════════════════════════════════════════════
step "4/9 | Установка пакетов (это займёт время...)"

# Общие пакеты для обоих профилей
COMMON_PKGS=(
    base linux linux-firmware base-devel
    cmake git rsync ninja wget curl
    networkmanager openssh
    zsh vim tmux
    man-db man-pages
    sudo bash-completion
)

SERVER_PKGS=(
    open-vm-tools
    htop iotop
    python
    archinstall
)

DESKTOP_PKGS=(
    # DE
    hyprland hyprpaper waybar
    rofi-wayland
    alacritty
    sddm
    # Звук
    pipewire pipewire-pulse pipewire-alsa wireplumber
    # Gaming
    steam gamemode lib32-gamemode mangohud lib32-mangohud
    # Apps
    telegram-desktop
    code
    firefox
    # Утилиты Wayland
    grim slurp wl-clipboard
    xdg-user-dirs xdg-utils xdg-desktop-portal-hyprland
    polkit-kde-agent qt5-wayland qt6-wayland
    # Шрифты
    noto-fonts noto-fonts-emoji noto-fonts-cjk
    ttf-dejavu ttf-liberation
    # Темы / иконки
    papirus-icon-theme
    # Системное
    bluez bluez-utils
    upower
    brightnessctl
    playerctl
    dunst
)

NVIDIA_PKGS=(
    nvidia nvidia-utils lib32-nvidia-utils
    nvidia-settings libva-nvidia-driver
)

info "Собираю список пакетов для профиля: $PROFILE"

ALL_PKGS=("${COMMON_PKGS[@]}")
if [[ "$PROFILE" == "server" ]]; then
    ALL_PKGS+=("${SERVER_PKGS[@]}")
else
    ALL_PKGS+=("${DESKTOP_PKGS[@]}")
    if $NVIDIA; then
        ALL_PKGS+=("${NVIDIA_PKGS[@]}")
    fi
fi

info "Запускаю pacstrap..."
pacstrap -K /mnt "${ALL_PKGS[@]}" 2>&1 | tee -a "$LOG" | \
    grep -E "^(installing|error|warning)" || true

ok "Пакеты установлены"

# ═══════════════════════════════════════════════════════════
#  STEP 5 — FSTAB
# ═══════════════════════════════════════════════════════════
step "5/9 | Генерация fstab"
genfstab -U /mnt >> /mnt/etc/fstab
if [[ "$SWAP_SIZE" != "0" ]]; then
    echo "/swapfile  none  swap  defaults  0 0" >> /mnt/etc/fstab
fi
ok "fstab готов"
cat /mnt/etc/fstab | tee -a "$LOG"

# ═══════════════════════════════════════════════════════════
#  STEP 6 — CHROOT CONFIGURATION
# ═══════════════════════════════════════════════════════════
step "6/9 | Настройка системы (chroot)"

# Записываем переменные в файл для chroot-скрипта
cat > /mnt/root/install-vars.sh << EOF
USERNAME="$USERNAME"
USER_PASS="$USER_PASS"
ROOT_PASS="$ROOT_PASS"
HOSTNAME="$HOSTNAME"
PROFILE="$PROFILE"
USE_LUKS=$USE_LUKS
NVIDIA=$NVIDIA
ROOT_PART="$ROOT_PART"
MOUNT_ROOT="$MOUNT_ROOT"
SWAP_SIZE="$SWAP_SIZE"
DOTFILES_REPO="$DOTFILES_REPO"
EOF

# Копируем chroot-скрипт
cp "$(dirname "$0")/chroot-setup.sh" /mnt/root/chroot-setup.sh
chmod +x /mnt/root/chroot-setup.sh

info "Запускаю chroot-setup.sh..."
arch-chroot /mnt bash /root/chroot-setup.sh 2>&1 | tee -a "$LOG"
ok "Система настроена"

# ═══════════════════════════════════════════════════════════
#  STEP 7 — DOTFILES / AUR
# ═══════════════════════════════════════════════════════════
step "7/9 | Установка AUR helper + dotfiles"

arch-chroot /mnt /bin/bash -c "
    set -e
    # Устанавливаем yay
    cd /tmp
    git clone https://aur.archlinux.org/yay-bin.git --depth=1
    chown -R nobody:nobody /tmp/yay-bin
    cd /tmp/yay-bin
    sudo -u nobody makepkg -si --noconfirm --needed
    rm -rf /tmp/yay-bin

    # AUR пакеты
    AUR_PKGS='vcpkg'
    if [[ '$PROFILE' == 'desktop' ]]; then
        AUR_PKGS=\"\$AUR_PKGS joplin-desktop\"
    fi
    sudo -u nobody yay -S --noconfirm --needed \$AUR_PKGS || \
        echo 'Некоторые AUR пакеты не установились, доустановишь потом'
" 2>&1 | tee -a "$LOG" || warn "AUR: часть пакетов не установилась, доустановишь после перезагрузки"

# Клонируем dotfiles
arch-chroot /mnt /bin/bash -c "
    if git ls-remote '$DOTFILES_REPO' &>/dev/null; then
        sudo -u $USERNAME git clone '$DOTFILES_REPO' /home/$USERNAME/.dotfiles
        cd /home/$USERNAME/.dotfiles

        if [[ '$PROFILE' == 'desktop' ]] && [[ -f install-desktop.sh ]]; then
            sudo -u $USERNAME bash install-desktop.sh
        elif [[ '$PROFILE' == 'server' ]] && [[ -f install-server.sh ]]; then
            sudo -u $USERNAME bash install-server.sh
        fi
    else
        echo 'Репо недоступно или не существует, dotfiles пропущены'
    fi
" 2>&1 | tee -a "$LOG" || warn "Dotfiles: клонирование не удалось (проверь URL)"

ok "AUR и dotfiles готовы"

# ═══════════════════════════════════════════════════════════
#  STEP 8 — LUKS AUTO-CLOSE SERVICE
# ═══════════════════════════════════════════════════════════
if $USE_LUKS; then
    step "8/9 | Настройка авто-закрытия LUKS"
    # systemd закрывает LUKS при shutdown автоматически через cryptsetup.target
    # Дополнительный сервис для надёжности:
    cat > /mnt/etc/systemd/system/cryptroot-close.service << 'SVC'
[Unit]
Description=Close LUKS cryptroot before shutdown
DefaultDependencies=no
Before=shutdown.target reboot.target halt.target poweroff.target
After=umount.target dev-mapper-cryptroot.device

[Service]
Type=oneshot
ExecStart=/usr/bin/cryptsetup close cryptroot
RemainAfterExit=yes

[Install]
WantedBy=shutdown.target reboot.target halt.target poweroff.target
SVC
    arch-chroot /mnt systemctl enable cryptroot-close.service >> "$LOG" 2>&1
    ok "LUKS авто-закрытие настроено"
else
    step "8/9 | LUKS пропущен"
    info "Шифрование не использовалось"
fi

# ═══════════════════════════════════════════════════════════
#  STEP 9 — CLEANUP
# ═══════════════════════════════════════════════════════════
step "9/9 | Финализация"

# Копируем лог в установленную систему
mkdir -p /mnt/var/log
cp "$LOG" /mnt/var/log/arch-install.log

# Чистим временные файлы
rm -f /mnt/root/install-vars.sh /mnt/root/chroot-setup.sh

info "Размонтирование..."
umount -R /mnt 2>/dev/null || true
if $USE_LUKS; then
    cryptsetup close cryptroot 2>/dev/null || true
fi

echo ""
echo -e "${GREEN}${BOLD}"
cat << 'DONE'
  ╔══════════════════════════════════════════╗
  ║   ✓ УСТАНОВКА ЗАВЕРШЕНА УСПЕШНО!        ║
  ║                                          ║
  ║   Извлеки флешку и перезагрузись:        ║
  ║     reboot                               ║
  ╚══════════════════════════════════════════╝
DONE
echo -e "${NC}"
echo -e "  Лог установки: /var/log/arch-install.log"
echo ""
