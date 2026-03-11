# new home directory
export HOME="$ZDOTDIR"

# vi-mode
bindkey -v
autoload edit-command-line
zle -N edit-command-line
bindkey -M vicmd v edit-command-line

# history
HISTSIZE="50000"
SAVEHIST="10000"

HISTFILE="$HOME/.zsh_history"
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

# zim
ZIM_HOME="$HOME/.zim"

if [[ ! -e ${ZIM_HOME}/zimfw.zsh ]]; then
  if (( ${+commands[curl]} )); then
    curl -fsSL --create-dirs -o ${ZIM_HOME}/zimfw.zsh \
        https://github.com/zimfw/zimfw/releases/latest/download/zimfw.zsh
  else
    mkdir -p ${ZIM_HOME} && wget -nv -O ${ZIM_HOME}/zimfw.zsh \
        https://github.com/zimfw/zimfw/releases/latest/download/zimfw.zsh
  fi
fi

if [[ ! ${ZIM_HOME}/init.zsh -nt ${ZDOTDIR:-${HOME}}/.zimrc ]]; then
  source ${ZIM_HOME}/zimfw.zsh init -q
fi

source ${ZIM_HOME}/init.zsh

zmodload -F zsh/terminfo +p:terminfo

for key ('^[[A' '^P' ${terminfo[kcuu1]}) bindkey ${key} history-substring-search-up
for key ('^[[B' '^N' ${terminfo[kcud1]}) bindkey ${key} history-substring-search-down
for key ('k') bindkey -M vicmd ${key} history-substring-search-up
for key ('j') bindkey -M vicmd ${key} history-substring-search-down
unset key

export COLORTERM="truecolor"

# eza alias
alias -- eza='eza --icons auto --git'
alias -- l='eza -alh'
alias -- la='eza -a'
alias -- ll='eza -l'
alias -- lla='eza -la'
alias -- ls=eza
alias -- lt='eza --tree'
alias -- tree='eza -T'

# nvim alias
export EDITOR="nvim"
alias -- vim="nvim"
alias -- vi="nvim"
alias -- v="nvim"
alias -- vimdiff="nvim -d"

# starship
eval "$(starship init zsh)"

# zoxide
eval "$(zoxide init zsh)"
alias -- cd="z"

# fzf
source <(fzf --zsh)

# direnv
eval "$(direnv hook zsh)"

# gh
eval "$(gh completion --shell zsh)"

# opencode
export PATH="$HOME/.opencode/bin:$PATH"

if [[ -f "$HOME/.zshrc.local" ]]; then
  source "$HOME/.zshrc.local"
fi

