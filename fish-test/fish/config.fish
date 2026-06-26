set -g fish_greeting
set -g fish_autosuggestion_enabled 0

function fish_prompt
  printf '%s' "$TERMIO_TEST_PROMPT"
end

source "$TERMIO_REPO_ROOT/shell/termio.fish"
