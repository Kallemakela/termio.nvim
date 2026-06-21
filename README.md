# termio.nvim

> [!NOTE]
> WIP. Expect bugs.

Edit the terminal buffer like any other text buffer with minimal latency.

<img width="1600" height="795" alt="screen-recording-new" src="https://github.com/user-attachments/assets/9e546153-4f5e-4d87-a1c6-18f3a85fa9a3" />

<br>

Provides a read/write API + a bundled 'editor' for the terminal buffer.
Set `editor = nil` to only load the API.
Currently supports zsh and bash.
It is easy to add support for other shells as well if needed.


## Setup

### Shell

In zsh startup, e.g. in `~/.zshrc`:
```zsh
if [ -n "$NVIM" ]; then
  source "$HOME/code/nvim/termio.nvim/shell/termio.zsh"
fi
```

> [!NOTE]
> `termio.nvim` does not auto-load shell integration because it is complex and insecure.

In bash startup, e.g. in `~/.bashrc`:
```bash
if [ -n "$NVIM" ]; then
  source "$HOME/code/nvim/termio.nvim/shell/termio.bash"
fi
```

Check if all markers are visible to Neovim:

```vim
:checkhealth termio
```

### Neovim

<details>
<summary>With <a href="https://neovim.io/doc/user/pack.html#vim.pack">vim.pack</a> (Neovim 0.12+)</summary>

```lua
vim.pack.add({ "https://github.com/Kallemakela/termio.nvim" })
```

</details>

<details>
<summary>With <a href="https://github.com/folke/lazy.nvim">lazy.nvim</a></summary>
</details>

```lua
{
  "Kallemakela/termio.nvim",
  opts = {},
}
```

Or just on startup:
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
    terminal_name_pattern = [[\v(:| )(/[^ ]*/)?(zsh|bash)( |$)]],
    open = "<Esc>",
    is_disabled = function(buf)
      -- Example, assuming you track if TUI active in terminal
      -- See `./docs/tui-detection.md` for tracking alt-screen/TUI state.
      -- return vim.b[buf].term_tui_active
      return false
    end,
    keys = {
      t = {
        ["<Esc>"] = "open",
        ["<CR>"] = "submit",
        ["<C-u>"] = "clear",
        ["<C-s>"] = "write",
        ["<M-t>"] = "toggle",
      },
      n = {
        ["<CR>"] = "submit",
        ["<C-u>"] = "clear",
        ["<C-s>"] = "write",
        ["<Esc>"] = "save_and_close",
        ["<M-t>"] = "toggle",
      },
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
:TermioEnable
:TermioDisable
:TermioToggle
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

## Tips

Map shell prompt jumps to skip the prompt marker line:

```lua
vim.keymap.set({ "n", "x" }, "[[", "[[W", { buffer = true, remap = true })
vim.keymap.set({ "n", "x" }, "]]", "]]W", { buffer = true, remap = true })
```

## [Known issues/Planned features/Roadmap/TODO](./docs/todo.md)

## [Contributing](./docs/contributing.md)

## [Development](./docs/development.md)

## [Related projects](./docs/related-projects.md)
