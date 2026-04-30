#!/bin/bash

echo "Качаю репозиторий..."
git clone https://github.com/mateBall0377/arch-dotfilesmain.git --depth=1
cd arch-dotfilesmain
chmod +x install.sh chroot-setup.sh first-boot.sh
bash install.sh
