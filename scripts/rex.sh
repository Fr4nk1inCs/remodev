#!/usr/bin/env bash

export HOME="$(dirname "$(dirname "$(realpath "$0")")")"
source "$HOME/.config/shell/environment.sh"

exec rex --server "unix://$REX_RUNTIME_DIR/server.sock" --autostart=false server "$@"
