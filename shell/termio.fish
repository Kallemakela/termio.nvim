if set -q TERMIO_SHELL_INTEGRATION_LOADED
  return
end

set -g TERMIO_SHELL_INTEGRATION_LOADED 1

# Termio writes via bracketed paste; avoid fish selection-style paste highlight.
set -g fish_color_selection normal

function termio_shell_escape --argument-names value
  string replace -a '\\' '\\\\' -- "$value" | string replace -a ';' '\\x3b'
end

function termio_fifo_unescape --argument-names value
  string replace -a '\\\\' '\\' -- "$value"
end

function termio_shell_write_buffer --argument-names cursor command
  commandline -r -- "$command"
  if string match -qr '^\d+$' -- "$cursor"
    commandline -C "$cursor"
  else
    commandline -C (string length -- "$command")
  end
  termio_shell_clear_transient_ui
  printf '\e]633;W\a'
end

function termio_shell_report_buffer
  termio_shell_clear_transient_ui
  printf '\e]633;Q;%s;%s\a' (commandline -C) (termio_shell_escape (commandline))
end

function termio_shell_clear_transient_ui
  if commandline --paging-mode
    commandline -f cancel
  end
  if commandline --showing-suggestion
    commandline -f suppress-autosuggestion
  end
  commandline -f repaint
end

function termio_shell_control_fifo
  read frame < "$TERMIO_FIFO"
  set -l tab (printf '\t')
  set -l message (string split -m1 $tab -- "$frame")
  set -l action $message[1]
  set -l body $message[2]
  switch "$action"
    case write
      set -l payload (string split -m1 $tab -- "$body")
      termio_shell_write_buffer $payload[1] (termio_fifo_unescape $payload[2])
    case clear-completions
      termio_shell_clear_transient_ui
    case query
      termio_shell_report_buffer
  end
end

function termio_shell_cleanup --on-event fish_exit
  test -n "$TERMIO_FIFO"; and rm -f -- "$TERMIO_FIFO"
end

if functions -q fish_user_key_bindings
  functions -c fish_user_key_bindings termio_original_fish_user_key_bindings
end

function fish_user_key_bindings
  if functions -q termio_original_fish_user_key_bindings
    termio_original_fish_user_key_bindings
  end
  bind \cx\ct termio_shell_control_fifo
end

set -l termio_tmpdir /tmp
set -q TMPDIR; and set termio_tmpdir "$TMPDIR"
set -g TERMIO_FIFO "$termio_tmpdir/termio.nvim.$fish_pid.fifo"
rm -f -- "$TERMIO_FIFO"
mkfifo -m 600 "$TERMIO_FIFO"
bind \cx\ct termio_shell_control_fifo
printf '\e]633;I;%s;fish\a' "$TERMIO_FIFO"
