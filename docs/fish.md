# Fish

Fish has no bash/zsh-style `exec fd<>fifo` pattern for keeping the termio FIFO open as a persistent bidirectional fd.

Instead, termio sends a hidden wake key before writing. The fish key binding starts a short FIFO read, then Neovim writes the action frame.

Flow:

1. Neovim sends the wake key.
2. Fish runs `termio_shell_control_fifo`.
3. Fish starts reading `$TERMIO_FIFO`.
4. Neovim writes the frame.

Without the wake, there is no FIFO reader yet.

Sources:

- Fish redirection docs list `<`, `>`, `N<`, and `N>`, but not `<>`: https://fishshell.com/docs/current/language.html#input-output-redirection
- Fish `exec` is `exec COMMAND` and replaces the shell: https://fishshell.com/docs/current/cmds/exec.html
