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
pacman -Sy --noconfirm >> "$LOG" 2>&1 || true

# ─── ROOT PASSWORD ────────────────────────────────────────
info "Установка пароля root"
echo "root:${ROOT_PASS}" | chpasswd

# ─── USER ─────────────────────────────────────────────────
info "Создание пользователя: $USERNAME"
useradd -m -G wheel,audio,video,storage,optical,input,gamemode,bluetooth \
    -s /bin/zsh "$USERNAME"
echo "${USERNAME}:${USER_PASS}" | chpasswd
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
bootctl install >> "$LOG" 2>&1

mkdir -p /boot/loader/entries
cat > /boot/loader/loader.conf << 'EOF'
default arch.conf
timeout 3
console-mode max
editor  no
EOF

if $USE_LUKS; then
    LUKS_UUID=$(blkid -s UUID -o value "$ROOT_PART")
    EXTRA_PARAMS="cryptdevice=UUID=${LUKS_UUID}:cryptroot root=/dev/mapper/cryptroot"
else
    ROOT_UUID=$(blkid -s UUID -o value "$MOUNT_ROOT")
    EXTRA_PARAMS="root=UUID=${ROOT_UUID}"
fi

KERNEL_PARAMS="$EXTRA_PARAMS rw quiet loglevel=3 systemd.show_status=auto rd.udev.log_level=3"

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

# ─── ZSH ──────────────────────────────────────────────────
info "Настройка ZSH"
chsh -s /bin/zsh "$USERNAME" >> "$LOG" 2>&1 || true

# ─── SSH ──────────────────────────────────────────────────
info "Настройка SSH"
sed -i 's/^#PermitRootLogin.*/PermitRootLogin no/'                /etc/ssh/sshd_config
sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
sed -i 's/^#PubkeyAuthentication.*/PubkeyAuthentication yes/'     /etc/ssh/sshd_config

# ─── PROFILE SPECIFIC ─────────────────────────────────────
if [[ "$PROFILE" == "desktop" ]]; then
    info "Настройка рабочего стола"

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

# ─── FIRST BOOT SERVICE (AUR + dotfiles) ──────────────────
info "Настройка сервиса первого запуска"

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

ok "Chroot настройка завершена"
