#!/bin/bash
# chroot-setup.sh

set -e
source /root/install-vars.sh

LOG="/tmp/chroot-setup.log"
info() { echo -e "\033[0;36m[→]\033[0m $1" | tee -a "$LOG"; }
ok()   { echo -e "\033[0;32m[✓]\033[0m $1" | tee -a "$LOG"; }
warn() { echo -e "\033[1;33m[!]\033[0m $1" | tee -a "$LOG"; }
die()  { echo -e "\033[0;31m[✗] ОШИБКА: $1\033[0m" | tee -a "$LOG"; exit 1; }

# ─── TIMEZONE ─────────────────────────────────────────────
info "Настройка часового пояса"
ln -sf /usr/share/zoneinfo/Asia/Yekaterinburg /etc/localtime
hwclock --systohc

# ─── LOCALE ───────────────────────────────────────────────
info "Настройка локали"
grep -qxF 'en_US.UTF-8 UTF-8' /etc/locale.gen || echo 'en_US.UTF-8 UTF-8' >> /etc/locale.gen
grep -qxF 'ru_RU.UTF-8 UTF-8' /etc/locale.gen || echo 'ru_RU.UTF-8 UTF-8' >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# ─── CONSOLE ──────────────────────────────────────────────
info "Настройка консоли"
cat > /etc/vconsole.conf << 'EOF'
KEYMAP=ru
FONT=cyr-sun16
EOF

# ─── HOSTNAME ─────────────────────────────────────────────
info "Настройка hostname: $HOSTNAME"
echo "$HOSTNAME" > /etc/hostname
cat > /etc/hosts << EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
EOF

# ─── PACMAN ───────────────────────────────────────────────
info "Включение multilib + Yandex зеркало"
sed -i '/^#\[multilib\]/,/^#Include/{s/^#//}' /etc/pacman.conf
cat > /etc/pacman.d/mirrorlist << 'EOF'
Server = https://mirror.yandex.ru/archlinux/$repo/os/$arch
EOF
pacman -Sy --noconfirm >> "$LOG" 2>&1 || warn "pacman -Sy завершился с ошибкой, продолжаем"

# ─── PASSWORDS ────────────────────────────────────────────
info "Установка паролей"
echo "root:${ROOT_PASS}" | chpasswd

# ─── USER ─────────────────────────────────────────────────
info "Создание пользователя: $USERNAME"
useradd -m -G wheel,audio,video,storage,optical,input -s /bin/zsh "$USERNAME"
echo "${USERNAME}:${USER_PASS}" | chpasswd

# Добавляем в дополнительные группы если они существуют
for grp in gamemode bluetooth; do
    if getent group "$grp" &>/dev/null; then
        usermod -aG "$grp" "$USERNAME"
    fi
done

sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# ─── SERVICES ─────────────────────────────────────────────
info "Включение сервисов"
systemctl enable NetworkManager
systemctl enable sshd

if [[ "$PROFILE" == "server" ]]; then
    systemctl enable vmtoolsd          2>/dev/null || true
    systemctl enable vmware-vmblock-fuse 2>/dev/null || true
fi

if [[ "$PROFILE" == "desktop" ]]; then
    systemctl enable sddm      2>/dev/null || true
    systemctl enable bluetooth 2>/dev/null || true
fi

# ─── NVIDIA ───────────────────────────────────────────────
if $NVIDIA && [[ "$PROFILE" == "desktop" ]]; then
    info "Настройка Nvidia"
    cat > /etc/modprobe.d/nvidia.conf << 'EOF'
options nvidia-drm modeset=1
options nvidia NVreg_PreserveVideoMemoryAllocations=1
EOF
    cat > /etc/modprobe.d/blacklist-nouveau.conf << 'EOF'
blacklist nouveau
options nouveau modeset=0
EOF
    sed -i 's/^MODULES=.*/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' \
        /etc/mkinitcpio.conf
fi

# ─── MKINITCPIO ───────────────────────────────────────────
info "Настройка mkinitcpio"
if $USE_LUKS; then
    sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect modconf kms keyboard keymap consolefont block encrypt filesystems fsck)/' \
        /etc/mkinitcpio.conf
else
    sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect modconf kms keyboard keymap consolefont block filesystems fsck)/' \
        /etc/mkinitcpio.conf
fi
mkinitcpio -P >> "$LOG" 2>&1
ok "initramfs пересобран"

# ─── BOOTLOADER ───────────────────────────────────────────
info "Установка bootloader (systemd-boot)"

# ── 1. Монтируем efivarfs — без него bootctl не пишет EFI-переменные ──
EFIVARFS_MOUNTED=false
if ! mountpoint -q /sys/firmware/efi/efivars 2>/dev/null; then
    info "Монтируем efivarfs..."
    if mount -t efivarfs efivarfs /sys/firmware/efi/efivars >> "$LOG" 2>&1; then
        EFIVARFS_MOUNTED=true
        info "efivarfs смонтирован"
    else
        warn "Не удалось смонтировать efivarfs — попробуем efibootmgr как fallback"
    fi
else
    # Перемонтируем rw на случай read-only
    mount -o remount,rw /sys/firmware/efi/efivars >> "$LOG" 2>&1 || true
    EFIVARFS_MOUNTED=true
fi

# ── 2. Ставим bootloader ──────────────────────────────────
if bootctl install >> "$LOG" 2>&1; then
    ok "bootctl install успешен (EFI-переменная записана)"
else
    warn "bootctl install упал — пробую efibootmgr как fallback..."

    # Убеждаемся что efibootmgr установлен
    pacman -S --noconfirm --needed efibootmgr >> "$LOG" 2>&1 || true

    # Файлы загрузчика всё равно нужны — ставим без EFI-переменных
    bootctl install --no-variables >> "$LOG" 2>&1 || \
        warn "bootctl --no-variables тоже упал, продолжаем с efibootmgr"

    # Определяем номер EFI-раздела из EFI_PART (sda1 → 1, nvme0n1p1 → 1)
    EFI_PART_NUM=$(echo "$EFI_PART" | grep -oE '[0-9]+$')

    if efibootmgr \
        --create \
        --disk "$DISK" \
        --part "$EFI_PART_NUM" \
        --label "Arch Linux (systemd-boot)" \
        --loader '\EFI\systemd\systemd-bootx64.efi' \
        >> "$LOG" 2>&1; then
        ok "efibootmgr: EFI-запись создана вручную"
    else
        warn "efibootmgr тоже упал — загрузчик установлен только как fallback (EFI/BOOT/BOOTX64.EFI)"
        warn "Если VMware не загружается: зайди в настройки VM → добавь загрузочную запись вручную"
    fi
fi

mkdir -p /boot/loader/entries

cat > /boot/loader/loader.conf << 'EOF'
default arch.conf
timeout 3
console-mode max
editor  no
EOF

# Определяем UUID — ОБЯЗАТЕЛЬНО проверяем что он не пустой
if $USE_LUKS; then
    # Для LUKS берём UUID самого LUKS-раздела (не маппера)
    LUKS_UUID=$(blkid -s UUID -o value "$ROOT_PART" 2>/dev/null)
    [[ -z "$LUKS_UUID" ]] && die "Не удалось получить UUID LUKS раздела $ROOT_PART"
    info "LUKS UUID: $LUKS_UUID"
    EXTRA_PARAMS="cryptdevice=UUID=${LUKS_UUID}:cryptroot root=/dev/mapper/cryptroot"
else
    # Для обычного раздела берём UUID файловой системы (ext4)
    ROOT_UUID=$(blkid -s UUID -o value "$MOUNT_ROOT" 2>/dev/null)
    [[ -z "$ROOT_UUID" ]] && die "Не удалось получить UUID раздела $MOUNT_ROOT"
    info "Root UUID: $ROOT_UUID"
    EXTRA_PARAMS="root=UUID=${ROOT_UUID}"
fi

KERNEL_PARAMS="$EXTRA_PARAMS rw quiet loglevel=3"
if $NVIDIA && [[ "$PROFILE" == "desktop" ]]; then
    KERNEL_PARAMS="$KERNEL_PARAMS nvidia-drm.modeset=1"
fi

cat > /boot/loader/entries/arch.conf << EOF
title   Arch Linux
linux   /vmlinuz-linux
initrd  /initramfs-linux.img
options ${KERNEL_PARAMS}
EOF

cat > /boot/loader/entries/arch-fallback.conf << EOF
title   Arch Linux (fallback)
linux   /vmlinuz-linux
initrd  /initramfs-linux-fallback.img
options ${KERNEL_PARAMS}
EOF

ok "Bootloader установлен"

# Проверка — показываем что реально записалось
info "Содержимое arch.conf:"
cat /boot/loader/entries/arch.conf | tee -a "$LOG"
info "Bootctl status:"
bootctl status >> "$LOG" 2>&1 || true

# ─── ZSH ──────────────────────────────────────────────────
info "Настройка ZSH"
chsh -s /bin/zsh "$USERNAME" >> "$LOG" 2>&1 || true

# ─── SSH ──────────────────────────────────────────────────
info "Настройка SSH"
sed -i 's/^#PermitRootLogin.*/PermitRootLogin no/'                /etc/ssh/sshd_config
sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^#PubkeyAuthentication.*/PubkeyAuthentication yes/'     /etc/ssh/sshd_config

# ─── DESKTOP SPECIFIC ─────────────────────────────────────
if [[ "$PROFILE" == "desktop" ]]; then
    mkdir -p /etc/sddm.conf.d
    cat > /etc/sddm.conf.d/theme.conf << 'EOF'
[Theme]
Current=breeze
EOF
    mkdir -p /home/"$USERNAME"/.config
    cat > /home/"$USERNAME"/.config/gamemode.ini << 'EOF'
[general]
reaper_freq=5
desiredgov=performance
EOF
    chown -R "$USERNAME:$USERNAME" /home/"$USERNAME"/.config
fi

# ─── FIRST BOOT SERVICE ───────────────────────────────────
info "Настройка first-boot сервиса"

cat > /etc/first-boot-vars << EOF
USERNAME="$USERNAME"
PROFILE="$PROFILE"
DOTFILES_REPO="$DOTFILES_REPO"
EOF

cp /root/first-boot.sh /usr/local/bin/first-boot.sh
chmod +x /usr/local/bin/first-boot.sh

cat > /etc/systemd/system/first-boot.service << 'SVC'
[Unit]
Description=First Boot Setup (yay + AUR + dotfiles)
After=network-online.target
Wants=network-online.target
ConditionPathExists=/usr/local/bin/first-boot.sh

[Service]
Type=oneshot
ExecStart=/usr/local/bin/first-boot.sh
RemainAfterExit=yes
StandardOutput=journal+console
StandardError=journal+console

[Install]
WantedBy=multi-user.target
SVC

systemctl enable first-boot.service
ok "First-boot сервис включён"

ok "=== Chroot настройка завершена ==="
