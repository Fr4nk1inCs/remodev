NEW_HOME=$(realpath $(dirname $0))

export XDG_CONFIG_HOME="$NEW_HOME/.config"
export XDG_CACHE_HOME="$NEW_HOME/.cache"
export XDG_DATA_HOME="$NEW_HOME/.local/share"
export XDG_STATE_HOME="$NEW_HOME/.local/state"

export EDITOR="nvim"

# zsh vi-mode
bindkey -v
autoload edit-command-line
zle -N edit-command-line
bindkey -M vicmd v edit-command-line

# history
HISTSIZE="50000"
SAVEHIST="10000"

HISTFILE="$NEW_HOME/.zsh_history"
mkdir -p "$(dirname "$HISTFILE")"

unsetopt APPEND_HISTORY
unsetopt HIST_IGNORE_ALL_DUPS

setopt HIST_FCNTL_LOCK
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_EXPIRE_DUPS_FIRST
setopt SHARE_HISTORY
setopt EXTENDED_HISTORY

setopt interactivecomments

export COLORTERM="truecolor"

# fzf
if command -v fzf >/dev/null; then
  source <(fzf --zsh)
fi

# gh
if command -v gh >/dev/null; then
  eval "$(gh completion --shell zsh)"
fi
