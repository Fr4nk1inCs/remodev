#!/usr/bin/env bash
set -e
set -o pipefail

HOME="$(dirname "$(dirname "$(realpath "$0")")")"
export HOME
source "$HOME/.config/shell/environment.sh"
cd "$HOME"

echo "Installing dependencies..."
apt-get install clangd build-essential curl zsh git -y

echo "Installing mise..."
curl -fsSL https://mise.run | MISE_INSTALL_PATH="$HOME/.local/bin/mise" sh
eval "$("$HOME/.local/bin/mise" activate bash)"

echo "Installing packages..."
mise upgrade

echo "Installing Rex..."
curl -fsSL https://pkgs.superlogical.com/rex/install.sh | sh -s -- --user
