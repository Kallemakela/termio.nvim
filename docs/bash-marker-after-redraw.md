# Bash Marker After Redraw

`termio.nvim` used to wake bash readline through `bind -x` for shell-side actions.

Observed failure:

- Shell query state is correct, e.g. `command_len = 1270`, `cursor = 1270`.
- Terminal buffer render is stale or truncated when integrated code reads it.
- A fixed wait after the bash wake makes the issue disappear.

## Bash Source

Bash 5.3 runs `bind -x` handlers in `bashline.c:bash_execute_unix_command()`.

Before the handler:

```c
rl_clear_visible_line ();
fflush (rl_outstream);
```

After the handler and after copying back `READLINE_LINE`, `READLINE_POINT`, and `READLINE_MARK`:

```c
/* and restore the readline buffer and display after command execution. */
if (ce && r != 124)
  rl_redraw_prompt_last_line ();
else
  rl_forced_update_display ();
```

There is no check for whether readline state changed. A marker-only `bind -x` handler still redraws.

## Tested Facts

- A marker printed by a `bind -x` handler appears before Bash's post-handler redraw.
- `OSC 133;B` from `PS1` appears before readline writes the command text.
- Control bytes inside `READLINE_LINE` are displayed as printable notation, e.g. `^[]633;R^G`, not emitted as raw OSC.
- A `bind -x` wake can still force a redraw even when no readline state changes.
