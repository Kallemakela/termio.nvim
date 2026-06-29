set -g fish_greeting
set -g fish_autosuggestion_enabled 0
set -q TERMIO_TEST_PROMPT; or set -gx TERMIO_TEST_PROMPT '$ '

function fish_prompt
  printf '%s' "$TERMIO_TEST_PROMPT"
end

source "$TERMIO_REPO_ROOT/shell/termio.fish"
