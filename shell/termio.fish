if set -q TERMIO_SHELL_INTEGRATION_LOADED
  return
end

set -g TERMIO_SHELL_INTEGRATION_LOADED 1

# Termio writes via bracketed paste; avoid fish selection-style paste highlight.
set -g fish_color_selection normal

function termio_shell_clear_transient_ui
  if commandline --paging-mode
    commandline -f cancel
  end
  if commandline --showing-suggestion
    commandline -f suppress-autosuggestion
  end
  commandline -f repaint
end

if functions -q fish_user_key_bindings
  functions -c fish_user_key_bindings termio_original_fish_user_key_bindings
end

function fish_user_key_bindings
  if functions -q termio_original_fish_user_key_bindings
    termio_original_fish_user_key_bindings
  end
  bind \cx\ct termio_shell_clear_transient_ui
end

bind \cx\ct termio_shell_clear_transient_ui
printf '\e]633;I;fish\a'
