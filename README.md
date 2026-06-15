# termline.nvim

> [!NOTE]
> WIP. Expect bugs.

Edit the current terminal command in Neovim.

`termline.nvim` provides an API for reading, writing, and syncing the current
command, and some built-in editors using the API.

#### `overlay` editor demo

https://github.com/user-attachments/assets/71864d1e-9fc7-4875-9b6c-910e9a6bef4d

#### `editable` editor demo

https://github.com/user-attachments/assets/fe20e2f0-296c-4b43-89d5-2e16b5872e44

## Editor usage

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
  -- Keys sent by clear_command to clear the current line.
  clear_current_line = "<C-u>",
  -- Delay between clear_current_line verification checks.
  clear_current_line_check_ms = 10,
  -- Number of clear_current_line verification checks before falling back to Ctrl-C.
  clear_current_line_check_count = 5,
  -- Max wait for the shell to emit a fresh prompt after an interrupt.
  prompt_refresh_wait_ms = 50,
  -- Patterns stripped from command text when reading input.
  read_strip_patterns = { "\\n", "\n> ?", "^%s+$", "%s%s+$" },
  -- Patterns stripped from command text before sending it back to the terminal.
  write_strip_patterns = { "\n" },
  -- Ctrl-C is used to clear the line if any of these match the command.
  ctrl_c_on = { "\n> ?" },
  editor = {
    -- nil means API-only, "overlay" enables the default floating editor.
    -- "editable" applies edits to terminal buffer directly.
    type = "overlay",
    -- Vim regex matched against terminal buffer names before editor keymaps attach.
    terminal_name_pattern = [[\v(:| )(/[^ ]*/)?(zsh|bash|fish)( |$)]],
    -- Global normal-mode mapping for the editor command. Set false to disable.
    open = "<Esc>",
    -- Open the editor when a new OSC133 ]133;B is detected.
    open_on_prompt = false,
    -- Sync editor text, close, then pass these keys to the terminal in insert mode.
    pass_through_insert_keys = { "<Up>", "<Tab>" },
    -- Sync text, close, then replay these in normal mode.
    pass_through_normal_keys = { "}", "<C-d>", "<C-b>", "<C-f>", "G", "L" },
    -- Only on the first overlay line, sync text, close, then replay these in normal mode.
    pass_through_normal_keys_first_line = { "{", "<C-u>", "gg", "H" },
    keys = {
      ["<CR>"] = { action = "submit", mode = { "n", "i" } },
      ["<C-u>"] = { action = "clear", mode = { "n", "i" } },
      ["<C-s>"] = { action = "write", mode = { "n", "i" } },
      ["<C-f>"] = { action = "save_and_close", mode = { "n", "i" } },
      ["<Esc>"] = { action = "save_and_close", mode = { "n" } },
      ["q"] = { action = "close", mode = { "n" } },
      ["j"] = { action = "down", mode = { "n", "x", "o" } },
      ["k"] = { action = "up", mode = { "n", "x", "o" } },
    },
  },
  -- true: vim.notify debug events. function(event, data): custom logger.
  debug = false,
})
```

- `editor.type = nil` leaves the API loaded without any editor.
- `editor.type = "overlay"` uses the default floating editor with the shell prompt included.
- `editor.type = "editable"` edits the current command directly in the terminal buffer.
<!-- - `editor.type = "integrated"` is an in-place editor for the terminal buffer. -->

## API

- `api.read_command_visible` reads text starting from last `OSC133;B` marker from the visible terminal buffer.
- `api.read_command_cache` reads command text from the shell-side cache.
- `api.read_command` chooses between live buffer and cache automatically.
- `api.clear_command` sends `clear_current_line` with a `C-c` fallback if the command stays non-empty.
- `api.write_command` chansends the given command text. 
- `sync.sync` clears and writes changed command text, and moves the cursor when `target.cursor` is set. See the editors for usage.


```lua
local termline = require("termline.api")
local buf = vim.api.nvim_get_current_buf()
local command = termline.read_command(buf)
local visible_command = termline.read_command_visible(buf)
local cached_command = termline.read_command_cache(buf)
termline.clear_command(buf)
termline.write_command("echo hello", buf)
```

See `./termline.nvim/lua/termline/editors/overlay.lua` for usage example.

## User Commands

User commands target the current terminal buffer.

```vim
:TermReadCommand
:TermWriteCommand echo hello
:TermClearCommand
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

## Buffer Cache

Per-terminal state is cached in an internal Lua table, keyed by the existing terminal buffer handle.
- `prompt`: cached prompt text.
- `prompt_start_cursor`: `{ row, col }` at the prompt start from `OSC133;A`.
- `prompt_end_cursor`: `{ row, col }` at the prompt/command boundary from `OSC133;B`.
- `shell_state`: shell-side `{ command, cursor }` state. What the shell program thinks the state is.
- `target_state`: target `{ command, cursor }` state, used by the integrated editor to restore
state in some cases where terminal writes to the terminal buffer.

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
