#!/bin/bash

set -e

INSTALL_URL="https://raw.githubusercontent.com/koswika/mcprobe/main/mcprobe.sh"
INSTALL_PATH="/usr/local/bin/mcprobe"

if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "$OSTYPE" == "win32" ]]; then
    echo "Windows detected. Use the PowerShell installer instead:"
    echo ""
    echo '  irm https://raw.githubusercontent.com/koswika/mcprobe/main/install.ps1 | iex'
    exit 1
fi

if ! command -v curl &>/dev/null; then
    if command -v apt-get &>/dev/null; then
        sudo apt-get install -y curl
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y curl
    elif command -v pacman &>/dev/null; then
        sudo pacman -S --noconfirm curl
    elif command -v zypper &>/dev/null; then
        sudo zypper install -y curl
    elif command -v apk &>/dev/null; then
        sudo apk add curl
    else
        echo "Error: curl not found and could not be installed automatically."
        exit 1
    fi
fi

echo "Downloading mcprobe..."
sudo curl -fsSL "$INSTALL_URL" -o "$INSTALL_PATH"
sudo chmod +x "$INSTALL_PATH"

echo "mcprobe installed to $INSTALL_PATH"
echo "Run: mcprobe <server>"