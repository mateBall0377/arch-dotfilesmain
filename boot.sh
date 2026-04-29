#!/bin/bash

BASE="https://raw.githubusercontent.com/mateBall0377/arch-dotfilesmain/master"

echo "Качаю установщик..."
curl -fsSL "$BASE/install.sh"      -o install.sh
curl -fsSL "$BASE/chroot-setup.sh" -o chroot-setup.sh
chmod +x install.sh chroot-setup.sh

bash install.sh
