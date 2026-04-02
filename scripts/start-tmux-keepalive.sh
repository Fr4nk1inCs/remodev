#!/usr/bin/env bash

BASE="$(realpath "$(dirname "$0")")"
REMODEV_BASE="$(dirname "$BASE")"

TMUX_CONF="$REMODEV_BASE/.tmux.conf"
SOCK_NAME="fr4nk1in.sock"

tmux() {
  command tmux -L "$SOCK_NAME" "$@"
}

if ! tmux has-session -t "keep-alive" 2>/dev/null; then
  echo "Starting tmux keep-alive session..."
  ZDOTDIR="$REMODEV_BASE" \
  HOME="$REMODEV_BASE" \
    tmux -u -f "$TMUX_CONF" new-session -d -s "keep-alive"
else
  echo "Tmux keep-alive session already running."
fi
