# termio.nvim

> [!NOTE]
> WIP. Expect bugs.

Edit the terminal like any other text with minimal latency.

<img width="1600" height="795" alt="screen-recording-new" src="https://github.com/user-attachments/assets/9e546153-4f5e-4d87-a1c6-18f3a85fa9a3" />

<br>

Provides a read/write API + a bundled 'editor' for the terminal buffer.
Set `editor = nil` to only load the API.
Currently supports zsh and bash.
It is easy to add support for other shells as well if needed.


## Setup

### Shell

<details>
<summary>Zsh</summary>

Load [zsh integration script](./shell/termio.zsh) on startup, e.g. in `~/.zshrc`:

```zsh
if [ -n "$NVIM" ]; then
  source "$HOME/code/nvim/termio.nvim/shell/termio.zsh"
fi
```

</details>

> [!NOTE]
> `termio.nvim` does not auto-load shell integration because it is complex and insecure.

<details>
<summary>Bash</summary>

Load [bash integration script](./shell/termio.bash) on startup, e.g. in `~/.bashrc`:

```bash
if [ -n "$NVIM" ]; then
  source "$HOME/code/nvim/termio.nvim/shell/termio.bash"
fi
```

</details>

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

```lua
{
  "Kallemakela/termio.nvim",
  opts = {},
}
```

</details>

Or just on startup:
```lua
require("termio").setup()
```

## Config

Defaults live in `lua/termio/config.lua`.

```lua
require("termio").setup({
  -- Vim regexes. Command text starts after the matched prompt.
  prompt_patterns = { [[^>>> ]], [[^\.\.\. ]] },
  read_strip_patterns = {},
  write_strip_patterns = { "\n" },
  editor = {
    type = "integrated",
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

- Command: full integrated command text, can contain multiple lines.
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

## Project Structure

```text
termio.nvim/
├── lua/termio/
│   ├── init.lua                 setup entrypoint
│   ├── config.lua               defaults
│   ├── api.lua                  public read/write API
│   ├── commands.lua             user commands
│   ├── health.lua               :checkhealth termio checks
│   ├── terminal_buffer.lua      terminal-buffer reads and cursor math
│   ├── state.lua                plugin state storage
│   ├── shell_state.lua          OSC marker state updates
│   ├── editors/                 bundled terminal-buffer editors
│   │   └── integrated.lua         default integrated-buffer editor
│   ├── shell_integration/       shell marker and key-hook integration
│   │   ├── init.lua             shell integration dispatch
│   │   ├── zsh.lua              zsh integration
│   │   ├── bash.lua             bash integration
│   │   └── fish.lua             fish integration
│   └── util/                    shared utilities
│       ├── helpers.lua          small helper functions
│       └── log.lua              debug logging
├── shell/                       shell startup scripts
│   ├── termio.zsh               zsh markers and key hooks
│   ├── termio.bash              bash markers and key hooks
│   └── termio.fish              fish markers and key hooks
├── tests/                       MiniTest tests
├── dev/                         dev harness
├── docs/                        notes, setup details, roadmap
├── scripts/minimal_init.lua     test config
├── run_filtered_tests.sh        focused test runner
└── Makefile                     all-test entrypoint
```

## How the api works.

#### `read`
- reads command text from the terminal buffer after the current prompt marker.
- prompt markers come from OSC 133 shell integration or configured prompt regexes.
- if extra rows appear after the prompt, asks the shell hook to clear transient completion UI and rereads the buffer.

#### `write`
- clear the command by sending C-e C-u to the shell process, then sending the command inside bracketed paste.
- move the cursor by sending arrow keys to the shell.
- shell hooks redraw or clear completion UI when available; command transport is always PTY input.

## REPLs

`termio.nvim` uses OSC133 markers or configured prompt regexes to detect where
the prompt ends and the editable command starts. 

### Example: Python REPL

Add these to prompt patterns:
```lua
prompt_patterns = { [[^>>> ]], [[^\.\.\. ]] },
```

Or, add OSC133 markers to the REPL prompt. Example for python:

```sh
# ~/.zshrc
export PYTHONSTARTUP="$HOME/.pythonrc.py"
```

```python
import sys

OSC133_PROMPT_START = "\001\033]133;A\007\002"
OSC133_PROMPT_END = "\001\033]133;B\007\002"

sys.ps1 = OSC133_PROMPT_START + ">>> " + OSC133_PROMPT_END
sys.ps2 = OSC133_PROMPT_START + "... " + OSC133_PROMPT_END
```

Check that prompt is as expected:
```python
>>> print(repr(sys.ps1))
'\x01\x1b]133;A\x07\x02>>> \x01\x1b]133;B\x07\x02'
```

> [!NOTE]
> REPLs use prompt regexes when OSC 133 shell markers are not available.

## [Known issues/Planned features/Roadmap/TODO](./docs/todo.md)

## [Contributing](./docs/contributing.md)

## [Development](./docs/development.md)

## [Related projects](./docs/related-projects.md)
