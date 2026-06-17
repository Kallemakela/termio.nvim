if [[ -n ${TERMIO_SHELL_INTEGRATION_LOADED:-} ]]; then
  return 0 2>/dev/null || exit 0
fi

TERMIO_SHELL_INTEGRATION_LOADED=1

# Escape marker payload so separators stay parseable.
termio_shell_escape() {
  local escaped=${1//\\/\\\\}
  escaped=${escaped//;/\\x3b}
  printf '%s' "$escaped"
}

# FIFO payload escaping: one logical frame per line.
termio_fifo_unescape() {
  local s="$1"
  s=${s//\\\\/$'\001'}
  s=${s//\\n/$'\n'}
  s=${s//$'\001'/\\}
  printf '%s' "$s"
}

termio_shell_report_buffer() {
  printf '\e]633;Q;%s;%s\a' "$READLINE_POINT" "$(termio_shell_escape "$READLINE_LINE")"
}

termio_shell_clear_completions() {
  READLINE_LINE=$READLINE_LINE
}

termio_shell_write_buffer() {
  local cursor="$1"
  local command="$2"
  READLINE_LINE="$command"
  if [[ "$cursor" =~ ^[0-9]+$ ]]; then
    READLINE_POINT="$cursor"
  else
    READLINE_POINT="${#READLINE_LINE}"
  fi
  printf '\e]633;W\a'
}

termio_shell_control_fifo() {
  local fd=${1:-$TERMIO_FIFO_FD}
  local frame action body cursor command

  while IFS= read -r -t 0.01 -u "$fd" frame; do
    action=${frame%%$'\t'*}
    body=${frame#*$'\t'}

    case "$action" in
      write)
        cursor=${body%%$'\t'*}
        command=${body#*$'\t'}
        command=$(termio_fifo_unescape "$command")
        termio_shell_write_buffer "$cursor" "$command"
        ;;
      clear-completions)
        termio_shell_clear_completions
        ;;
      query)
        termio_shell_report_buffer
        ;;
    esac
  done
}

termio_shell_cleanup() {
  if [[ -n ${TERMIO_FIFO_FD:-} ]]; then
    eval "exec ${TERMIO_FIFO_FD}>&-"
  fi
  [[ -n ${TERMIO_FIFO:-} ]] && rm -f -- "$TERMIO_FIFO"
}

TERMIO_FIFO="${TMPDIR:-/tmp}/termio.nvim.$$.fifo"
TERMIO_FIFO_FD=9
rm -f -- "$TERMIO_FIFO"
mkfifo -m 600 "$TERMIO_FIFO"
eval "exec ${TERMIO_FIFO_FD}<>\"$TERMIO_FIFO\""
bind -x '"\C-x\C-t": termio_shell_control_fifo'
trap termio_shell_cleanup EXIT
printf '\e]633;I;%s;bash\a' "$TERMIO_FIFO"
