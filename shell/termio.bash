if [[ -n ${TERMIO_SHELL_INTEGRATION_LOADED:-} ]]; then
  return 0 2>/dev/null || exit 0
fi

# BASH_ENV also runs in child bash scripts; integration output would corrupt them.
if [[ $- != *i* ]]; then
  return 0 2>/dev/null || exit 0
fi

TERMIO_SHELL_INTEGRATION_LOADED=1

# Termio clears commands with Emacs readline controls like C-e C-u.
set -o emacs

# Termio writes via bracketed paste; avoid Readline's active-region highlight.
bind 'set active-region-start-color ""'
bind 'set active-region-end-color ""'

termio_shell_clear_completions() {
  READLINE_LINE=$READLINE_LINE
}

termio_shell_read_state() {
  printf '\e]633;E;%s;%s\a' "$READLINE_POINT" "$READLINE_LINE"
}

bind -x '"\C-x\C-t": termio_shell_clear_completions'
bind -x '"\C-x\C-r": termio_shell_read_state'
printf '\e]633;I;bash\a'
