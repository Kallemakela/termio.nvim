# termio.nvim

> [!NOTE]
> WIP. Expect bugs.

<img width="1600" height="808" alt="screen-recording" src="https://github.com/user-attachments/assets/8c9786fd-bf7c-48e0-818a-7b97a02f643a" />

Edit the terminal buffer like any other text buffer with minimal latency.

Provides a read/write API + a bundled 'editor' for the terminal buffer.
Set `editor = nil` to only load the API.

## Branches 

Current branch only supports zsh.
Old general (and much more hacky and complex) `nvim_chan_send` based implementation is on branch `old`.
The main reason for making this zsh only is that this allows to not send a lot of characters/bytes to the neovim terminal, which causes lag, visible jitter and race conditions in some cases. With the zsh only approach we can simply overwrite the zle state to sync our editable buffer to the shell.
I suspect it is easy to add support for other shells as well with the current branch's minimal approach, but zsh is enough for me.

## Setup

In zsh startup, e.g. in `~/.zshrc`:
```bash
source /path/to/termio.nvim/shell/termio.zsh
```

In neovim:
```lua
require("termio").setup()
```

## Config

Defaults live in `lua/termio/config.lua`.

```lua
require("termio").setup({
  write_strip_patterns = { "\n" },
  editor = {
    type = "editable",
    terminal_name_pattern = [[\v(:| )(/[^ ]*/)?zsh( |$)]],
    open = "<Esc>",
    keys = {
      ["<CR>"] = { action = "submit", mode = { "n", "i" } },
      ["<C-u>"] = { action = "clear", mode = { "n", "i" } },
      ["<C-s>"] = { action = "write", mode = { "n", "i" } },
      ["<Esc>"] = { action = "save_and_close", mode = { "n" } },
    },
  },
  -- true: vim.notify debug events. function(event, data): custom logger.
  debug = false,
})
```

Set `editor.type = nil` for API-only mode.

## API

```lua
local termio = require("termio")
local buf = vim.api.nvim_get_current_buf()
local command = termio.read_command(buf)
termio.write_command("echo hello", buf)
```

## User Commands

User commands target the current terminal buffer.

```vim
:TermioReadCommand
:TermioWriteCommand echo hello
```

## Terms

- Command: full editable command text, can contain multiple lines.
- Command row: one line in a command.
- Prompt: shell text shown before the command.
- OSC133: terminal escape sequence used to find where the prompt ends and command starts.

## Completions

Bundled editors set `vim.bo.filetype = "termio"`.
Use that filetype to set custom completions for the editor buffer.

Blink example:

```lua
require("blink.cmp").setup({
  sources = {
    per_filetype = {
      ["termio"] = { "path", "snippets" },
    },
  },
})
```

## [Known issues/Planned features/Roadmap/TODO](./doc/todo.md)

## [Related projects](./doc/related-projects.md)
