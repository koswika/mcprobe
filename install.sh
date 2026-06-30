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

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
    if command -v sudo &>/dev/null; then
        SUDO="sudo"
    else
        echo "Error: this script needs root privileges to write to $INSTALL_PATH, and 'sudo' was not found."
        echo "Re-run as root, or install sudo first."
        exit 1
    fi
fi

if ! command -v curl &>/dev/null; then
    if command -v apt-get &>/dev/null; then
        $SUDO apt-get install -y curl
    elif command -v dnf &>/dev/null; then
        $SUDO dnf install -y curl
    elif command -v yum &>/dev/null; then
        $SUDO yum install -y curl
    elif command -v pacman &>/dev/null; then
        $SUDO pacman -S --noconfirm curl
    elif command -v zypper &>/dev/null; then
        $SUDO zypper install -y curl
    elif command -v apk &>/dev/null; then
        $SUDO apk add curl
    elif command -v brew &>/dev/null; then
        brew install curl
    else
        echo "Error: curl not found and could not be installed automatically."
        exit 1
    fi
fi

echo "Downloading mcprobe..."
TMP_FILE="$(mktemp)"
trap 'rm -f "$TMP_FILE"' EXIT

if ! curl -fsSL "$INSTALL_URL" -o "$TMP_FILE"; then
    echo "Error: failed to download mcprobe from $INSTALL_URL"
    exit 1
fi

if [ ! -s "$TMP_FILE" ] || ! head -1 "$TMP_FILE" | grep -q '^#!'; then
    echo "Error: downloaded file does not look like a valid script. Aborting install."
    exit 1
fi

chmod +x "$TMP_FILE"
$SUDO mv "$TMP_FILE" "$INSTALL_PATH"
trap - EXIT

echo "mcprobe installed to $INSTALL_PATH"
echo "Run: mcprobe <server>"