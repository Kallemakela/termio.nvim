autoload -Uz add-zsh-hook

if [[ -n ${TERMLINE_SHELL_INTEGRATION_LOADED:-} ]]; then
  return
fi

TERMLINE_SHELL_INTEGRATION_LOADED=1
printf '\e]633;I\a'

# Escape marker payload so separators stay parseable.
termline_shell_escape() {
  local escaped=${1//\\/\\\\}
  escaped=${escaped//;/\\x3b}
  print -r -- "$escaped"
}

# Emit the executed command before the shell runs it.
termline_shell_preexec() {
  printf '\e]633;E;%s\a' "$(termline_shell_escape "$1")"
}

termline_shell_report_buffer() {
  printf '\e]633;Q;%s;%s\a' "$CURSOR" "$(termline_shell_escape "$BUFFER")"
}

termline_shell_clear_completions() {
  zle -R -c
}
zle -N termline-clear-completions termline_shell_clear_completions

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
}
zle -N termline-write-buffer termline_shell_write_buffer

termline_shell_control() {
  local file="${TMPDIR:-/tmp}/termline.nvim.$$.control"
  [[ -f "$file" ]] || return 1
  local payload="$(< "$file")"
  rm -f "$file"
  local action="${payload%%$'\n'*}"
  local body="${payload#*$'\n'}"
  if [[ "$action" == "write" ]]; then
    zle termline-write-buffer -- "$body"
  elif [[ "$action" == "clear-completions" ]]; then
    termline_shell_clear_completions
  elif [[ "$action" == "query" ]]; then
    termline_shell_report_buffer
  else
    return 1
  fi
}
zle -N termline-control termline_shell_control

add-zsh-hook preexec termline_shell_preexec
TRAPUSR1() {
  termline_shell_report_buffer
}
TRAPUSR2() {
  zle termline-control
}
