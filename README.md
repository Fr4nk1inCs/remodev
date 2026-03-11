# Remodev

A set of minimal configurations for develop on a remote server. This contains a
simple configuration of `neovim`, `tmux` and `opencode`.

> [!Note]
> This repo targets a shared server, where everyone logs in as the same root user.
> In such case, any modification to the global dotfiles would affect others,
> which is NOT COOL! However, such situation is common when working on a
> containerized environment.
>
> This repo does not suit you if:
> 1. Your server is not shared, so you can customize the dotfiles as you like.
> 2. You have your own account on the server, so you can customize the dotfiles
>    in your home directory.
>    - If you do not have root permission on such server, I recommend you to use
>      `pixi` or `mise` as a package manager to install tools in your home
>      directory.

## Installation

We only support ubuntu for now, since it's widely adopted on gpu servers.

Install dependencies and patch ~/.zshrc with:
```console
$ bash scripts/install.sh
```

This would only install `neovim`, `fzf`, `lua-language-server` and `gh` (github cli).
You should install other tools by yourself, such as `tmux`, `opencode`,
`tree-sitter-cli` and so on.

## Usage

In `scripts/start-tmux-keepalive.sh`, we launch a keep-alive tmux session
using a special socket `fr4nk1in.sock` and set `ZDOTDIR` to this repo's
root. Such that all sessions attached to this tmux server/socket would
source this `.zshrc` and get the same environment.

First run `scripts/start-tmux-keepalive.sh` to start the tmux server.

After that, to start a new session, simply run:
```console
$ tmux -L fr4nk1in.sock new -s <session-name>
```
