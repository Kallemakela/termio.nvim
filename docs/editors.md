Default editor: `integrated`.

## `./overlay-editor.md`

This editor is a separate window/buffer from the terminal.
Uses `buftype='prompt'`, includes the shell prompt in the first line, and opens in normal mode.
It is the smoothest editing experience but it requires complexity to handle:
- changing buffer when in the editor window
- moving seamlessly in and out of the window when navigating the terminal

## `./integrated-editor.md`

This editor integrates to the terminal buffer directly. Pros: no extra window, cons: hacky, needs to fight with pty over the buffer state.
