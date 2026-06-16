# termline.nvim

> [!NOTE]
> WIP. Expect bugs.
Edit the current zsh command in Neovim.

This branch is zsh-only.
No overlay editor.
No sync module.
Public API is `read_command()` and `write_command()`.

## Setup

```lua
require("termline").setup()
```

Press `<Esc>` on a terminal buffer to open the editor.

## Shell integration

Shell integration scripts add more markers to the shell output so we can parse
what part of the displayed text is the command and what is, e.g., shell
completions. Enable by sourcing the corresponding script on startup. Example
for zsh [script](./shell/termline.zsh):

```zsh
source /path/to/termline.nvim/shell/termline.zsh
```
Only zsh supported now. Should be easy to add support for other shells as well.

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

## User Autocommands

#### `User termline-open-on-prompt` after a terminal `OSC133;B`
prompt marker is seen.
`args.data` contains:
- `buf`: terminal buffer handle
- `cursor`: `{ row, col }` from the `TermRequest` event. `row` is the 1-based
  terminal line. `col` is the 0-based byte column right after the prompt, so it
  points at the first command character position.

See `./termline.nvim/lua/termline/editors/overlay.lua` for usage example.

#### `User termline-prompt-updated` after the cached prompt text has been refreshed. 
`args.data` contains:
- `buf`: terminal buffer handle
- `cursor`: `{ row, col }` from the `TermRequest` event
- `prompt`: cached prompt text

Example TBD

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
