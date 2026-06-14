autoload -Uz add-zsh-hook

if [[ -n ${TERMLINE_SHELL_INTEGRATION_LOADED:-} ]]; then
  return
fi

TERMLINE_SHELL_INTEGRATION_LOADED=1

termline#shell#escape() {
  local escaped=${1//\\/\\\\}
  escaped=${escaped//;/\\x3b}
  print -r -- "$escaped"
}

termline#shell#preexec() {
  printf '\e]633;E;%s\a' "$(termline#shell#escape "$1")"
}

add-zsh-hook preexec termline#shell#preexec
