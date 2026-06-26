autoload -Uz add-zsh-hook add-zle-hook-widget

if [[ -n ${TERMIO_SHELL_INTEGRATION_LOADED:-} ]]; then
  return
fi

TERMIO_SHELL_INTEGRATION_LOADED=1

# Termio writes via bracketed paste; avoid ZLE's pasted-text highlight.
zle_highlight+=(paste:none)

termio_shell_clear_completions() {
  zle -R -c
}

termio_shell_redraw() {
  zle reset-prompt
}

zle -N termio-clear-completions termio_shell_clear_completions
zle -N termio-redraw termio_shell_redraw
bindkey $'\e[27;5;67~' termio-clear-completions
bindkey $'\e[27;5;84~' termio-redraw

termio_shell_announce() {
  [[ -n ${TERMIO_SHELL_ANNOUNCED:-} ]] && return
  TERMIO_SHELL_ANNOUNCED=1
  printf '\e]633;I;zsh\a'
}

add-zle-hook-widget line-init termio_shell_announce
