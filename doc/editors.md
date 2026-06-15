Default editor: `overlay`.

## `./overlay-editor.md`

This editor is a separate window/buffer from the terminal.
Uses `buftype='prompt'`, includes the shell prompt in the first line, and opens in insert mode.
It is the smoothest editing experience but it requires complexity to handle:
- changing buffer when in the editor window
- moving seamlessly in and out of the window when navigating the terminal

## `./editable-editor.md`

This editor is close to editable-term.nvim plugin implementation.
It syncs on all insert mode entries and operations that require cursor movement.
Downside is that it flickers due to terminal buffer rendering all edits made by the sync.

## `./integrated-editor.md`

This editor is in between the other two. No extra window and syncs less often to reduce flickering.
