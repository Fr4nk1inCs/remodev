export XDG_CONFIG_HOME="$HOME/.config"
export XDG_CACHE_HOME="$HOME/.cache"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_STATE_HOME="$HOME/.local/state"
export ZDOTDIR="$XDG_CONFIG_HOME/zsh"
export SHELL=/usr/bin/zsh

export CARGO_HOME="$XDG_DATA_HOME/cargo"
export CLAUDE_CONFIG_DIR="$XDG_CONFIG_HOME/claude"
export COPILOT_HOME="$XDG_CONFIG_HOME/copilot"
export CODEX_HOME="$XDG_CONFIG_HOME/codex"
export CUDA_CACHE_PATH="$XDG_CACHE_HOME/nv"
export IPYTHONDIR="$XDG_CONFIG_HOME/ipython"
export JUPYTER_CONFIG_DIR="$XDG_CONFIG_HOME/jupyter"
export LESSHISTFILE="$XDG_STATE_HOME/less/history"
export NODE_REPL_HISTORY="$XDG_STATE_HOME/node/repl_history"
export NPM_CONFIG_PREFIX="$XDG_DATA_HOME/npm"
export NPM_CONFIG_USERCONFIG="$XDG_CONFIG_HOME/npm/npmrc"
export PI_CODING_AGENT_DIR="$XDG_CONFIG_HOME/pi/agent"
export PYTHON_HISTORY="$XDG_STATE_HOME/python/history"
export RUSTUP_HOME="$XDG_DATA_HOME/rustup"
export TRITON_CACHE_DIR="$XDG_CACHE_HOME/triton"
export WGETRC="$XDG_CONFIG_HOME/wget/wgetrc"
export npm_config_cache="$XDG_CACHE_HOME/npm"

case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) export PATH="$HOME/.local/bin:$PATH" ;;
esac
