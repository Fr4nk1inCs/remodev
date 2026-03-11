#!/usr/bin/env bash

BASE="$(realpath "$(dirname "$0")")"
REMODEV_BASE="$(dirname "$BASE")"

TMUX_CONF="$REMODEV_BASE/.tmux.conf"
SOCK_NAME="fr4nk1in.sock"

# how should I make all tmux session source the additional zshrc?
tmux -L "$SOCK_NAME" has-session -t "keep-alive" 2>/dev/null || \
  tmux -L "$SOCK_NAME" -u -f "$TMUX_CONF" new-session -d -s "keep-alive"

tmux -L "$SOCK_NAME" set-environment -g "ZDOTDIR" "$REMODEV_BASE"
