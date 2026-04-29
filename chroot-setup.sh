#!/bin/bash
# =============================================================
#  chroot-setup.sh — запускается внутри arch-chroot
#  Читает переменные из /root/install-vars.sh
# =============================================================

set -e
source /root/install-vars.sh

LOG="/tmp/chroot-setup.log"
info() { echo -e "\033[0;36m[→]\033[0m $1" | tee -a "$LOG"; }
ok()   { echo -e "\033[0;32m[✓]\033[0m $1" | tee -a "$LOG"; }

# ─── TIMEZONE ─────────────────────────────────────────────
info "Настройка часового пояса (Ekaterinburg / Chelyabinsk)"
ln -sf /usr/share/zoneinfo/Asia/Yekaterinburg /etc/localtime
hwclock --systohc

# ─── LOCALE ───────────────────────────────────────────────
info "Настройка локали (ru_RU + en_US)"
cat >> /etc/locale.gen << 'EOF'
en_US.UTF-8 UTF-8
ru_RU.UTF-8 UTF-8
EOF
locale-gen

# Системный язык — английский (совместимость с dev-инструментами)
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# ─── CONSOLE (RU + EN всегда оба) ─────────────────────────
info "Настройка консоли"
cat > /etc/vconsole.conf << 'EOF'
KEYMAP=ru
FONT=cyr-sun16
EOF
# Оба layout'а настроятся через X11/Wayland в DE

# ─── HOSTNAME ─────────────────────────────────────────────
info "Настройка hostname: $HOSTNAME"
echo "$HOSTNAME" > /etc/hostname
cat > /etc/hosts << EOF
127.0.0.1   localhost
::1         localhost
127.0.1.1   ${HOSTNAME}.localdomain ${HOSTNAME}
EOF

# ─── PACMAN ───────────────────────────────────────────────
info "Включение multilib (для Steam/lib32)"
sed -i '/^#\[multilib\]/,/^#Include/{s/^#//}' /etc/pacman.conf
pacman -Sy --noconfirm >> "$LOG" 2>&1 || true

# ─── ROOT PASSWORD ────────────────────────────────────────
info "Установка пароля root"
echo "root:${ROOT_PASS}" | chpasswd

# ─── USER ─────────────────────────────────────────────────
info "Создание пользователя: $USERNAME"
useradd -m -G wheel,audio,video,storage,optical,input,gamemode,bluetooth \
    -s /bin/zsh "$USERNAME"
echo "${USERNAME}:${USER_PASS}" | chpasswd

# Sudo без пароля для wheel (поменяй если хочешь с паролем)
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# ─── SERVICES ─────────────────────────────────────────────
info "Включение сервисов"
systemctl enable NetworkManager
systemctl enable sshd

if [[ "$PROFILE" == "server" ]]; then
    systemctl enable vmtoolsd 2>/dev/null || true
    systemctl enable vmware-vmblock-fuse 2>/dev/null || true
    info "VMware tools включены"
fi

if [[ "$PROFILE" == "desktop" ]]; then
    systemctl enable sddm
    systemctl enable bluetooth 2>/dev/null || true
    info "SDDM включён"
fi

# ─── NVIDIA ───────────────────────────────────────────────
if $NVIDIA && [[ "$PROFILE" == "desktop" ]]; then
    info "Настройка Nvidia (DRM modeset)"
    # Ранняя загрузка KMS
    cat > /etc/modprobe.d/nvidia.conf << 'EOF'
options nvidia-drm modeset=1
options nvidia NVreg_PreserveVideoMemoryAllocations=1
EOF
    # Отключаем nouveau
    cat > /etc/modprobe.d/blacklist-nouveau.conf << 'EOF'
blacklist nouveau
options nouveau modeset=0
EOF
    # Модули для mkinitcpio
    sed -i 's/^MODULES=.*/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' \
        /etc/mkinitcpio.conf
fi

# ─── MKINITCPIO HOOKS ─────────────────────────────────────
info "Настройка mkinitcpio"
if $USE_LUKS; then
    sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect modconf kms keyboard keymap consolefont block encrypt filesystems fsck)/' \
        /etc/mkinitcpio.conf
else
    # Добавляем kms для Nvidia early KMS
    sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect modconf kms keyboard keymap consolefont block filesystems fsck)/' \
        /etc/mkinitcpio.conf
fi
mkinitcpio -P >> "$LOG" 2>&1
ok "initramfs пересобран"

# ─── BOOTLOADER (systemd-boot) ────────────────────────────
info "Установка bootloader (systemd-boot)"
bootctl install >> "$LOG" 2>&1

mkdir -p /boot/loader/entries
cat > /boot/loader/loader.conf << 'EOF'
default arch.conf
timeout 3
console-mode max
editor  no
EOF

# Определяем UUID для bootentry
if $USE_LUKS; then
    LUKS_UUID=$(blkid -s UUID -o value "$ROOT_PART")
    EXTRA_PARAMS="cryptdevice=UUID=${LUKS_UUID}:cryptroot root=/dev/mapper/cryptroot"
else
    ROOT_UUID=$(blkid -s UUID -o value "$MOUNT_ROOT")
    EXTRA_PARAMS="root=UUID=${ROOT_UUID}"
fi

KERNEL_PARAMS="$EXTRA_PARAMS rw quiet loglevel=3 systemd.show_status=auto rd.udev.log_level=3"

# Nvidia дополнительные параметры
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

# ─── ZSH / OH-MY-ZSH (опционально) ───────────────────────
info "Настройка ZSH"
chsh -s /bin/zsh "$USERNAME" >> "$LOG" 2>&1 || true

# ─── SSH ──────────────────────────────────────────────────
info "Настройка SSH"
sed -i 's/^#PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^#PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config

# ─── PROFILE-SPECIFIC ─────────────────────────────────────
if [[ "$PROFILE" == "server" ]]; then
    info "Настройка VMware сервера"
    # VMware open-vm-tools
    systemctl enable vmtoolsd 2>/dev/null || true
fi

if [[ "$PROFILE" == "desktop" ]]; then
    info "Настройка рабочего стола"

    # SDDM тема
    mkdir -p /etc/sddm.conf.d
    cat > /etc/sddm.conf.d/theme.conf << 'EOF'
[Theme]
Current=breeze
EOF

    # XDG user dirs
    sudo -u "$USERNAME" xdg-user-dirs-update 2>/dev/null || true

    # Gamemode config
    mkdir -p /home/"$USERNAME"/.config
    cat > /home/"$USERNAME"/.config/gamemode.ini << 'EOF'
[general]
reaper_freq=5
desiredgov=performance

[gpu]
apply_gpu_optimisations=accept-responsibility
gpu_device=0
nv_powermizer_mode=1

[cpu]
park_cores=no
pin_cores=yes
EOF
    chown -R "$USERNAME:$USERNAME" /home/"$USERNAME"/.config
fi

ok "Chroot настройка завершена"
