# Related projects

### `editable-term.nvim`
- makes the prompt modifiable when on the command line and syncs changes back to the shell on edit events
- also keeps shell cursor in sync with neovim
- does not work with multiline/wrapped commands (could be fixed maybe)
- chansend jitter is visible, otherwise very similar to this project

### [`TheLeoP Fork of editable-term.nvim`](https://github.com/TheLeoP/nvim-config/blob/bae7e8cd7eb6220e92174d7507145a465d562249/lua/personal/editable-term.lua#L1-L278)
- [discussion](https://github.com/neovim/neovim/issues/23645#issuecomment-3643708670)
"My main modifications in top of the original editable-term.nvim are
- correct handling of multibyte chars
- handling prompts spanning multiple visual lines
- handling changes made while using the blackhole register
- drop support for pattern based prompt matching (at least in a first implementation) to simplify the code, relying solely in the OSC133 escape sequence (which, btw, seems to use utf indexing instead of byte indexing)"
- This sounds good but did not work for me

### `term-edit.nvim`
- simulates vim motions by sending translated keystrokes to terminal
- requires a delay
- supports a subset of editing options
