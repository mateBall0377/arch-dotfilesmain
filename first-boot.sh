#!/bin/bash
# first-boot.sh — запускается один раз при первом старте системы

source /etc/first-boot-vars

LOG="/var/log/first-boot.log"
exec > >(tee -a "$LOG") 2>&1

info() { echo "[→] $1"; }
ok()   { echo "[✓] $1"; }

info "=== FIRST BOOT SETUP ==="
info "Пользователь: $USERNAME"
info "Профиль: $PROFILE"

# Ждём сети
info "Ожидание сети..."
for i in $(seq 1 30); do
    ping -c1 -W1 8.8.8.8 &>/dev/null && break
    sleep 1
done

# Устанавливаем yay
if ! command -v yay &>/dev/null; then
    info "Устанавливаю yay..."
    cd /tmp
    sudo -u "$USERNAME" git clone https://aur.archlinux.org/yay-bin.git --depth=1
    cd /tmp/yay-bin
    sudo -u "$USERNAME" makepkg -si --noconfirm --needed
    rm -rf /tmp/yay-bin
    ok "yay установлен"
fi

# AUR пакеты
info "Устанавливаю AUR пакеты..."
AUR_PKGS="vcpkg"
if [[ "$PROFILE" == "desktop" ]]; then
    AUR_PKGS="$AUR_PKGS joplin-desktop"
fi
sudo -u "$USERNAME" yay -S --noconfirm --needed $AUR_PKGS && ok "AUR пакеты установлены"

# Dotfiles
if [[ -n "$DOTFILES_REPO" ]] && [[ "$DOTFILES_REPO" != *"ТВОЙ"* ]]; then
    info "Клонирую dotfiles: $DOTFILES_REPO"
    sudo -u "$USERNAME" git clone "$DOTFILES_REPO" /home/$USERNAME/.dotfiles

    if [[ "$PROFILE" == "desktop" ]] && [[ -f /home/$USERNAME/.dotfiles/install-desktop.sh ]]; then
        sudo -u "$USERNAME" bash /home/$USERNAME/.dotfiles/install-desktop.sh
    elif [[ "$PROFILE" == "server" ]] && [[ -f /home/$USERNAME/.dotfiles/install-server.sh ]]; then
        sudo -u "$USERNAME" bash /home/$USERNAME/.dotfiles/install-server.sh
    fi
    ok "Dotfiles установлены"
fi

# Отключаем сервис — больше не нужен
systemctl disable first-boot.service
rm -f /etc/systemd/system/first-boot.service
rm -f /usr/local/bin/first-boot.sh
rm -f /etc/first-boot-vars

ok "=== FIRST BOOT ЗАВЕРШЁН ==="
