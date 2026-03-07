#!/usr/bin/env bash

set -e

tmp_workspace="$(mktemp -d)"
echo "Created temporary workspace at $tmp_workspace"
cd "$tmp_workspace" || exit 1

cleanup() {
  echo "Cleaning up temporary workspace at $tmp_workspace"
  rm -rf "$tmp_workspace"
}

trap cleanup EXIT ERR INT TERM

# Patch global zshrc to load our additional zshrc in our tmux sessions
patch_zshrc() {
  printf "Appending:\n  "
  echo '[[ -n "$TMUX_EXTRA_ZSHRC" && -f "$TMUX_EXTRA_ZSHRC" ]] && source "$TMUX_EXTRA_ZSHRC"' | tee -a "$HOME/.zshrc" > /dev/null
}

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

main() {
  patch_zshrc
  install_fzf
  install_lua_ls
  install_neovim
  install_copilot_lsp

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
