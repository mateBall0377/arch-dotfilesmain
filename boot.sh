#!/bin/bash
# boot.sh — кладёшь на флешку, запускаешь один раз

set -e

echo "Качаю установщик с GitHub..."

BASE="https://raw.githubusercontent.com/mateBall0377/arch-dotfiles/main"

curl -fsSL "$BASE/install.sh"       -o install.sh
curl -fsSL "$BASE/chroot-setup.sh"  -o chroot-setup.sh

chmod +x install.sh chroot-setup.sh

bash install.sh


