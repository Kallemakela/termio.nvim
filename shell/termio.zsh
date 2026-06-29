autoload -Uz add-zsh-hook add-zle-hook-widget

if [[ -n ${TERMIO_SHELL_INTEGRATION_LOADED:-} ]]; then
  return
fi

TERMIO_SHELL_INTEGRATION_LOADED=1

# Termio clears commands with Emacs readline controls like C-e C-u.
bindkey -e

# Termio writes via bracketed paste; avoid ZLE's pasted-text highlight.
zle_highlight+=(paste:none)

termio_shell_clear_completions() {
  zle -R -c
}

termio_shell_redraw() {
  zle reset-prompt
}

termio_shell_read_state() {
  printf '\e]633;E;%d;%s\a' "$CURSOR" "$BUFFER"
}

zle -N termio-clear-completions termio_shell_clear_completions
zle -N termio-read-state termio_shell_read_state
zle -N termio-redraw termio_shell_redraw
for termio_keymap in emacs viins vicmd; do
  bindkey -M "$termio_keymap" $'\e[27;5;67~' termio-clear-completions
  bindkey -M "$termio_keymap" $'\C-x\C-r' termio-read-state
  bindkey -M "$termio_keymap" $'\e[27;5;84~' termio-redraw
done
unset termio_keymap

termio_shell_announce() {
  [[ -n ${TERMIO_SHELL_ANNOUNCED:-} ]] && return
  TERMIO_SHELL_ANNOUNCED=1
  printf '\e]633;I;zsh\a'
}

add-zle-hook-widget line-init termio_shell_announce
