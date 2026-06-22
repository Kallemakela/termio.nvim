set -g fish_greeting

function fish_prompt
  printf '%s' "$TERMIO_TEST_PROMPT"
end

source "$TERMIO_REPO_ROOT/shell/termio.fish"
