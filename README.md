# Remodev

A set of minimal configurations for develop on a remote server. This contains
configurations of `zsh`, `neovim`, `pi` and other tools managed by `mise`.

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

Install dependencies and tools with:
```console
$ bash scripts/install.sh
```

This installs `mise` and all the tools declared in `.config/mise/config.toml`,
such as `neovim`, `fzf`, `eza`, `zoxide`, `starship`, `gh`, `pi` and so on.
Add other tools to that file as needed and install them with `mise upgrade`.

## Usage

This repo acts as a self-contained `$HOME`. To use it, explicitly point
`$HOME` at the repo's root and start a login shell:
```console
$ export HOME="/path/to/remodev" && cd && zsh -l
```
The login shell then sources this repo's `.zshrc`, which sets up the XDG
directories, tools and aliases.

For machine-specific tweaks, create `.zshrc.local.pre` and/or
`.zshrc.local.post` in the repo root — they are sourced before and after the
main `.zshrc`, respectively.
