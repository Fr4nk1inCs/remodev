#!/usr/bin/env bash

set -e
set -o pipefail

BASE_DIR="$(dirname "$(realpath "$0")")"
REMODEV_BASE="$(dirname "$BASE_DIR")"

export HOME="$REMODEV_BASE"

echo "Installing mise..."
curl https://mise.run | MISE_INSTALL_PATH="$HOME/.local/bin/mise" sh
eval "$("$HOME/.local/bin/mise" activate bash)"

echo "Installing packages..."
mise upgrade

echo "Installing tree-sitter-cli..."
cargo install --locked tree-sitter-cli

echo "Installing pyrefly and ruff..."
uv tool install pyrefly ruff
