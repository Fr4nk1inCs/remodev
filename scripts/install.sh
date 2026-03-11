#!/usr/bin/env bash

set -e

tmp_workspace="$(mktemp -d)"
echo "Created temporary workspace at $tmp_workspace"
cd "$tmp_workspace" || exit 1

cleanup() {
  echo "Cleaning up temporary workspace at $tmp_workspace"
  rm -rf "$tmp_workspace"

  exit 1
}

trap cleanup EXIT ERR INT TERM

_last_version=""
fetch_latest_release() {
  local repo="$1"
  local version="$(curl -sL "https://api.github.com/repos/$repo/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')"
  echo "  The latest release of $repo is: $version"
  _last_version="$version"
}

_last_installed=""
install_latest_from_github() {
  local repo="$1"
  local filefmt="$2"

  fetch_latest_release "$repo"
  local version="$_last_version"
  local prefix="https://github.com/$repo/releases/download/$version"
  version="${version#v}" # remove prefix "v" if exists
  local filename="$(sed -E "s/%v/$version/g" <<< "$filefmt")"
  local url="$prefix/$filename"

  echo "  Fetching latest release of $repo from $url"
  local out="$tmp_workspace/$filename"
  curl -sL "$url" -o "$out"

  _last_installed="$out"
}

install_fzf() {
  echo "Installing fzf..."

  install_latest_from_github "junegunn/fzf" "fzf-%v-linux_amd64.tar.gz"

  echo "  Unpacking fzf to /usr/local/bin"
  tar -xzf "$_last_installed" -C "/usr/local/bin" --no-same-owner --strip-components=1 "fzf"
}


install_lua_ls() {
  echo "Installing lua-language-server..."

  install_latest_from_github "LuaLS/lua-language-server" "lua-language-server-%v-linux-x64.tar.gz"

  echo "  Unpacking lua-language-server to /opt/lua/language-server"
  mkdir -p "/opt/lua-language-server"
  tar -xzf "$_last_installed" -C "/opt/lua-language-server" --no-same-owner --strip-components=1
}

install_neovim() {
  echo "Installing nightly neovim..."

  add-apt-repository ppa:neovim-ppa/unstable -y && \
  apt-get update -y && \
  apt-get install neovim -y
}

install_copilot_lsp() {
  echo "Installing nodejs, npm and copilot-language-server..."
  apt-get install npm -y
  npm install -g @github/copilot-language-server
}

install_starship() {
  echo "Installing starship..."
  # installs to /usr/local/bin by default
  curl -sS https://starship.rs/install.sh | sh
}

install_eza() {
  echo "Installing eza..."
  apt-get update
  apt-get install -y gpg
  mkdir -p /etc/apt/keyrings
  wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc | \
    gpg --dearmor -o /etc/apt/keyrings/gierens.gpg
  echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" | \
    tee /etc/apt/sources.list.d/gierens.list
  chmod 644 /etc/apt/keyrings/gierens.gpg /etc/apt/sources.list.d/gierens.list
  apt-get update
  apt-get install -y eza
}

install_zoxide() {
  echo "Installing zoxide..."
  local url="https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh"
  local script="$tmp_workspace/install_zoxide.sh"
  curl -sL "$url" -o "$script"
  sh "$script" --bin-dir /usr/local/bin --man-dir /usr/local/share/zoxide
}

install_direnv() {
  echo "Installing direnv..."
  apt-get install -y direnv
}

ask_and_maybe_run() {
  local cmd="$1"
  local answer="p"
  local yellow=""
  local reset="\\033[0m"

  while [[ ! "$answer" =~ ^[YyNn]?$ ]]; do
    read -p "Do you want to run \`$cmd\`? (y/n)" -n 1 answer
  done

  echo
  if [[ "$answer" =~ ^[Yy]?$ ]]; then
    eval "$cmd"
  else
    echo "Skipped running: $cmd"
  fi
}

main() {
  ask_and_maybe_run install_fzf
  ask_and_maybe_run install_starship
  ask_and_maybe_run install_eza
  ask_and_maybe_run install_zoxide
  ask_and_maybe_run install_direnv
  ask_and_maybe_run install_lua_ls
  ask_and_maybe_run install_copilot_lsp
  ask_and_maybe_run install_neovim

  echo "Installation complete!"

  echo
  echo "=============================================================================="
  echo 'You might also install `pyrefly`, `ruff` and `tree-sitter-cli` using a'
  echo 'convenient method for your system.'
  echo 'For example, use conda to install `tree-sitter-cli` and use `uv` to install '
  echo '`pyrefly` and `ruff`:'
  echo "  conda install -c conda-forge tree-sitter-cli"
  echo "  uv tool install pyrefly ruff"
}

main
