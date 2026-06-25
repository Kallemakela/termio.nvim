autoload -Uz add-zsh-hook add-zle-hook-widget

if [[ -n ${TERMIO_SHELL_INTEGRATION_LOADED:-} ]]; then
  return
fi

TERMIO_SHELL_INTEGRATION_LOADED=1

# Termio writes via bracketed paste; avoid ZLE's pasted-text highlight.
zle_highlight+=(paste:none)

# Escape marker payload so separators stay parseable.
termio_shell_escape() {
  local escaped=${1//\\/\\\\}
  escaped=${escaped//;/\\x3b}
  print -r -- "$escaped"
}

# FIFO payload escaping: one logical frame per line.
termio_fifo_unescape() {
  local s="$1"
  s=${s//\\\\/$'\001'}
  s=${s//\\n/$'\n'}
  s=${s//$'\001'/\\}
  print -r -- "$s"
}

termio_shell_report_buffer() {
  printf '\e]633;Q;%s;%s\a' "$CURSOR" "$(termio_shell_escape "$BUFFER")"
}

termio_shell_clear_completions() {
  zle -R -c
}

termio_shell_redraw() {
  zle reset-prompt
}

termio_shell_write_buffer() {
  local payload="$1"
  local cursor="${payload%%$'\n'*}"
  BUFFER="${payload#*$'\n'}"
  if [[ "$cursor" == <-> ]]; then
    CURSOR="$cursor"
  else
    CURSOR="${#BUFFER}"
  fi
  zle -R
  printf '\e]633;W\a'
}

termio_shell_control_fifo() {
  local fd=${1:-$TERMIO_FIFO_FD}
  local frame action body cursor command

  while IFS= read -r -t 0.01 -u $fd frame; do
    action=${frame%%$'\t'*}
    body=${frame#*$'\t'}

    case "$action" in
      write)
        cursor=${body%%$'\t'*}
        command=${body#*$'\t'}
        command=$(termio_fifo_unescape "$command")
        termio_shell_write_buffer "$cursor"$'\n'"$command"
        ;;
      clear-completions)
        termio_shell_clear_completions
        ;;
      query)
        zle -R
        termio_shell_report_buffer
        ;;
    esac
  done
}
zle -N termio-control-fifo termio_shell_control_fifo
zle -N termio-redraw termio_shell_redraw
bindkey $'\e[27;5;84~' termio-redraw

termio_shell_cleanup() {
  if [[ -n ${TERMIO_FIFO_FD:-} ]]; then
    zle -F $TERMIO_FIFO_FD 2>/dev/null
    exec {TERMIO_FIFO_FD}>&-
  fi
  [[ -n ${TERMIO_FIFO:-} ]] && rm -f -- "$TERMIO_FIFO"
}

termio_shell_start_fifo() {
  [[ -n ${TERMIO_FIFO_ACTIVE:-} ]] && return
  zle -F -w $TERMIO_FIFO_FD termio-control-fifo
  TERMIO_FIFO_ACTIVE=1
  printf '\e]633;I;%s\a' "$TERMIO_FIFO"
}

add-zsh-hook zshexit termio_shell_cleanup
add-zle-hook-widget line-init termio_shell_start_fifo

TERMIO_FIFO="${TMPDIR:-/tmp}/termio.nvim.$$.fifo"
rm -f -- "$TERMIO_FIFO"
mkfifo -m 600 "$TERMIO_FIFO"
exec {TERMIO_FIFO_FD}<>"$TERMIO_FIFO"
