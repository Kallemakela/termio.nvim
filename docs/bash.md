# Bash

## Options

- `bind -x`: best shell-script option. Gives access to `READLINE_LINE`, `READLINE_POINT`, and `READLINE_MARK`, and can copy changes back to readline.
- Prompt hooks: useful for command lifecycle markers, but not for reading or editing the active readline buffer.
- Traps/signals: can wake bash in some states, but do not give shell script reliable access to active readline state.
- `READLINE_LINE` in normal shell code: not available except through `bind -x`.
- Compiled loadable builtin: could use readline C globals/hooks such as `rl_line_buffer`, `rl_point`, and `rl_event_hook`, but adds build, ABI, loading, and trust costs.

## Notes

- Bash `bind -x` redraw behavior: [bash-marker-after-redraw.md](bash-marker-after-redraw.md)

## `bind -x` Flow

1. Readline receives the bound key.
2. Bash clears the visible readline line.
3. Bash exports `READLINE_LINE`, `READLINE_POINT`, and `READLINE_MARK`.
4. Bash runs the bound shell command.
5. Bash copies `READLINE_LINE`, `READLINE_POINT`, and `READLINE_MARK` back into readline.
6. Bash calls readline redraw.
7. Control returns to readline.
