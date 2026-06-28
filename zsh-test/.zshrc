if [[ -z "${__TERMIO_TEST_MARKERS_LOADED:-}" ]]; then
  __TERMIO_TEST_MARKERS_LOADED=1
  __termio_test_prompt_seen=0
  : "${TERMIO_TEST_PROMPT:=$ }"

  termio_test_prompt_marker() {
    local exit_status=$?
    if [[ "$__termio_test_prompt_seen" == 1 ]]; then
      printf '\033]133;D;%s\a' "$exit_status"
    fi
    __termio_test_prompt_seen=1
    printf '\033]133;A\a'
  }

  termio_test_command_start_marker() {
    printf '\033]133;C;\a'
  }

  precmd_functions+=(termio_test_prompt_marker)
  preexec_functions+=(termio_test_command_start_marker)
  PS1="${TERMIO_TEST_PROMPT}"$'%{\033]133;B\a%}'
fi

source "$TERMIO_REPO_ROOT/shell/termio.zsh"
