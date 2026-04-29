#!/bin/bash
# install-desktop.sh
# Запускается после git clone ~/.dotfiles
# Создаёт симлинки конфигов, ставит дополнительные вещи

set -e
DOTFILES="$HOME/.dotfiles"
CONFIG="$HOME/.config"

info() { echo -e "\033[0;36m[→]\033[0m $1"; }
ok()   { echo -e "\033[0;32m[✓]\033[0m $1"; }

mkdir -p "$CONFIG"

# ─── СИМЛИНКИ ─────────────────────────────────────────────────
info "Создаю симлинки конфигов..."

link() {
    local src="$DOTFILES/configs/desktop/$1"
    local dst="$CONFIG/$2"
    mkdir -p "$(dirname "$dst")"
    [[ -e "$dst" ]] && mv "$dst" "${dst}.bak" 2>/dev/null || true
    ln -sf "$src" "$dst"
    ok "  $dst → $src"
}

link "hypr/hyprland.conf"     "hypr/hyprland.conf"
link "hypr/hyprpaper.conf"    "hypr/hyprpaper.conf"
link "waybar/config.jsonc"    "waybar/config.jsonc"
link "waybar/style.css"       "waybar/style.css"
link "alacritty/alacritty.toml" "alacritty/alacritty.toml"

# zshrc
[[ -f "$HOME/.zshrc" ]] && mv "$HOME/.zshrc" "$HOME/.zshrc.bak" 2>/dev/null || true
ln -sf "$DOTFILES/configs/common/.zshrc" "$HOME/.zshrc"
ok "  ~/.zshrc"

# ─── OH-MY-ZSH ────────────────────────────────────────────────
if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
    info "Устанавливаю oh-my-zsh..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

# ZSH плагины
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
if [[ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]]; then
    git clone https://github.com/zsh-users/zsh-autosuggestions \
        "$ZSH_CUSTOM/plugins/zsh-autosuggestions" --depth=1
fi
if [[ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]]; then
    git clone https://github.com/zsh-users/zsh-syntax-highlighting \
        "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" --depth=1
fi

# ─── СКРИНШОТЫ ПАПКА ──────────────────────────────────────────
mkdir -p "$HOME/Pictures/Screenshots"

# ─── GTK ТЕМА ─────────────────────────────────────────────────
mkdir -p "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0"
cat > "$HOME/.config/gtk-3.0/settings.ini" << 'EOF'
[Settings]
gtk-theme-name=Adwaita-dark
gtk-icon-theme-name=Papirus-Dark
gtk-font-name=Noto Sans 11
gtk-cursor-theme-size=24
gtk-application-prefer-dark-theme=1
EOF
cp "$HOME/.config/gtk-3.0/settings.ini" "$HOME/.config/gtk-4.0/settings.ini"

ok "Конфиги установлены!"
info "Перезапусти Hyprland или перелогинься."
