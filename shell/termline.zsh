autoload -Uz add-zsh-hook add-zle-hook-widget

if [[ -n ${TERMLINE_SHELL_INTEGRATION_LOADED:-} ]]; then
  return
fi

TERMLINE_SHELL_INTEGRATION_LOADED=1

# Escape marker payload so separators stay parseable.
termline_shell_escape() {
  local escaped=${1//\\/\\\\}
  escaped=${escaped//;/\\x3b}
  print -r -- "$escaped"
}

# FIFO payload escaping: one logical frame per line.
termline_fifo_unescape() {
  local s="$1"
  s=${s//\\\\/$'\001'}
  s=${s//\\n/$'\n'}
  s=${s//$'\001'/\\}
  print -r -- "$s"
}

termline_shell_report_buffer() {
  printf '\e]633;Q;%s;%s\a' "$CURSOR" "$(termline_shell_escape "$BUFFER")"
}

termline_shell_clear_completions() {
  zle -R -c
}

termline_shell_write_buffer() {
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

termline_shell_control_fifo() {
  local fd=${1:-$TERMLINE_FIFO_FD}
  local frame action body cursor command

  while IFS= read -r -t 0.01 -u $fd frame; do
    action=${frame%%$'\t'*}
    body=${frame#*$'\t'}

    case "$action" in
      write)
        cursor=${body%%$'\t'*}
        command=${body#*$'\t'}
        command=$(termline_fifo_unescape "$command")
        termline_shell_write_buffer "$cursor"$'\n'"$command"
        ;;
      clear-completions)
        termline_shell_clear_completions
        ;;
      query)
        zle -R
        termline_shell_report_buffer
        ;;
    esac
  done
}
zle -N termline-control-fifo termline_shell_control_fifo

termline_shell_cleanup() {
  if [[ -n ${TERMLINE_FIFO_FD:-} ]]; then
    zle -F $TERMLINE_FIFO_FD 2>/dev/null
    exec {TERMLINE_FIFO_FD}>&-
  fi
  [[ -n ${TERMLINE_FIFO:-} ]] && rm -f -- "$TERMLINE_FIFO"
}

termline_shell_start_fifo() {
  [[ -n ${TERMLINE_FIFO_ACTIVE:-} ]] && return
  zle -F -w $TERMLINE_FIFO_FD termline-control-fifo
  TERMLINE_FIFO_ACTIVE=1
  printf '\e]633;I;%s\a' "$TERMLINE_FIFO"
}

add-zsh-hook zshexit termline_shell_cleanup
add-zle-hook-widget line-init termline_shell_start_fifo

TERMLINE_FIFO="${TMPDIR:-/tmp}/termline.nvim.$$.fifo"
rm -f -- "$TERMLINE_FIFO"
mkfifo -m 600 "$TERMLINE_FIFO"
exec {TERMLINE_FIFO_FD}<>"$TERMLINE_FIFO"
