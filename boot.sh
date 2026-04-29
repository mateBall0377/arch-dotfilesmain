#!/bin/bash

BASE="https://raw.githubusercontent.com/mateBall0377/arch-dotfilesmain/master"
curl -fsSL "$BASE/install.sh"      -o install.sh
curl -fsSL "$BASE/chroot-setup.sh" -o chroot-setup.sh
curl -fsSL "$BASE/first-boot.sh"   -o first-boot.sh
chmod +x install.sh chroot-setup.sh first-boot.sh
bash install.sh
