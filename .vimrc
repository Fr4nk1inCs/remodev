if !has('nvim')
  let s:config_home = empty($XDG_CONFIG_HOME) ? expand('~/.config') : $XDG_CONFIG_HOME
  execute 'source' fnameescape(s:config_home . '/vim/vimrc')
endif
