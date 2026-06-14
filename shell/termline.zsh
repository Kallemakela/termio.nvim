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

# Emit the executed command before the shell runs it.
termline_shell_preexec() {
  printf '\e]633;E;%s\a' "$(termline_shell_escape "$1")"
}

# Emit the live ZLE buffer state before each prompt-line redraw.
termline_shell_buffer_state() {
  printf '\e]633;T;%s;%s\a' "$CURSOR" "$(termline_shell_escape "$BUFFER")"
}

add-zsh-hook preexec termline_shell_preexec
# Register the shell function as a ZLE widget before attaching the hook.
zle -N termline-shell-buffer-state termline_shell_buffer_state
add-zle-hook-widget line-pre-redraw termline-shell-buffer-state
