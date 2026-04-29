#!/bin/bash
# install-server.sh
# Запускается после git clone ~/.dotfiles на server профиле

set -e
DOTFILES="$HOME/.dotfiles"
info() { echo -e "\033[0;36m[→]\033[0m $1"; }
ok()   { echo -e "\033[0;32m[✓]\033[0m $1"; }

# ─── ZSHRC ────────────────────────────────────────────────────
[[ -f "$HOME/.zshrc" ]] && mv "$HOME/.zshrc" "$HOME/.zshrc.bak" 2>/dev/null || true
ln -sf "$DOTFILES/configs/common/.zshrc" "$HOME/.zshrc"
ok "~/.zshrc"

# ─── OH-MY-ZSH ────────────────────────────────────────────────
if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
    info "Устанавливаю oh-my-zsh..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
[[ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]] && \
    git clone https://github.com/zsh-users/zsh-autosuggestions \
        "$ZSH_CUSTOM/plugins/zsh-autosuggestions" --depth=1
[[ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]] && \
    git clone https://github.com/zsh-users/zsh-syntax-highlighting \
        "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" --depth=1

# ─── TMUX CONFIG ──────────────────────────────────────────────
cat > "$HOME/.tmux.conf" << 'EOF'
# Prefix = Ctrl+A (удобнее чем B)
set -g prefix C-a
unbind C-b
bind C-a send-prefix

# Мышь
set -g mouse on

# Нумерация с 1
set -g base-index 1
set -g pane-base-index 1

# Статус-бар
set -g status-bg colour235
set -g status-fg colour136
set -g status-left "#[fg=colour148,bold] [#S] "
set -g status-right "#[fg=colour136]%d.%m %H:%M "

# Разделение окон
bind | split-window -h -c "#{pane_current_path}"
bind - split-window -v -c "#{pane_current_path}"

# Vim-like навигация
bind h select-pane -L
bind j select-pane -D
bind k select-pane -U
bind l select-pane -R

set -g history-limit 50000
set -sg escape-time 0
EOF
ok "~/.tmux.conf"

ok "Server конфиги установлены!"
