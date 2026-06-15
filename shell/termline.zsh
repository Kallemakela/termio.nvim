autoload -Uz add-zsh-hook

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

# Emit the executed command before the shell runs it.
termline_shell_preexec() {
  printf '\e]633;E;%s\a' "$(termline_shell_escape "$1")"
}

termline_shell_report_buffer() {
  printf '\e]633;Q;%s;%s\a' "$CURSOR" "$(termline_shell_escape "$BUFFER")"
}

add-zsh-hook preexec termline_shell_preexec
zle -N termline-report-buffer termline_shell_report_buffer
bindkey '\e[99;9u' termline-report-buffer
