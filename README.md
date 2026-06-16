# termline.nvim

> [!NOTE]
> WIP. Expect bugs.

Read and write the current zsh state in Neovim.

This branch is now a minimal zsh api + editor.
No overlay editor.
No sync module.
Only `read_command()` and `write_command()`.
Old general chansend based implementation is on branch `old`.
The reasoning for making it zsh only is that this gets rid of chansend, which causes jitter when editing commands. Zsh only implementation simply overwrites the zle state to sync.

Maybe easy to add support for other shells as well?

## Setup

In zsh startup, e.g. in `~/.zshrc`:
```bash
source /path/to/termline.nvim/shell/termline.zsh
```

In neovim:
```lua
require("termline").setup()
```

## Config

Defaults live in `lua/termline/config.lua`.

```lua
require("termline").setup({
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
local termline = require("termline")
local buf = vim.api.nvim_get_current_buf()
local command = termline.read_command(buf)
termline.write_command("echo hello", buf)
```

## User Commands

User commands target the current terminal buffer.

```vim
:TermReadCommand
:TermWriteCommand echo hello
```

## Terms

- Command: full editable command text, can contain multiple lines.
- Command row: one line in a command.
- Prompt: shell text shown before the command.
- OSC133: terminal escape sequence used to find where the prompt ends and command starts.

## Completions

Bundled editors set `vim.bo.filetype = "termline"`.
Use that filetype to set custom completions for the editor buffer.

Blink example:

```lua
require("blink.cmp").setup({
  sources = {
    per_filetype = {
      ["termline"] = { "path", "snippets" },
    },
  },
})
```

## [Known issues/Planned features/Roadmap/TODO](/doc/todo.md)

## [Related projects](/doc/related-projects.md)
