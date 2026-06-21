# Development

## Dev Harness

Recommended for testing. Uses a minimal config without other plugins etc.

```sh
sh ./dev/run.sh --debug --words 300
SHELL=/opt/homebrew/bin/bash
```

Debug output: `./tmp/dev.out`.

#### Args
- `--debug`: write Neovim verbose output and termio debug logs to `./tmp/dev.out`.
- `--words N`: prefill the terminal with a lorem command of `N` words.
- `--multi`: split the prefilled command over multiple shell lines.
- `--headless`: run without UI, then quit.
- `--post-setup CMD`: run a Vim command before a headless run quits.
- `--config debug|own`: use the repo debug config or your own config.
- `--editor TYPE`: set the termio editor type.
- `--layout single|v|h`: open the terminal in one window, vertical split, or horizontal split.

#### Env vars
- `SHELL=/path/to/shell`: choose the shell used by `:terminal`, e.g. `/bin/bash`.

#### Keymaps in debug config
- `<leader>q`: quit.
- `<leader>c`: copy `:messages`.
- `<leader>bk`: delete the current buffer.
- `<leader>l`: open `./tmp/dev.out`.
- `<leader>o`: open `./tmp/termdump.out`.
- `<leader>i`: write a snapshot to `./tmp/snapshot.out`.
- `<leader>s`: copy current termio status and append it to `./tmp/dev.out`.
- `<leader>g`: run `:TermioReadCommand`.
- `<leader>w`: write a long lorem command through termio.
- `<leader>e`: show the editable zone.
- `K`: previous prompt marker.
- `J`: next prompt marker.


## Testing

Targeted test:
```sh
sh ./run_filtered_tests.sh tests/test_API.lua 'read_command'
```

Run all tests:

```sh
make test
make test-bash
```

Tests write debug output to `./tmp/test.out`.

Env vars:

- `TERMIO_TEST_SHELL=(bash|zsh)`

Read some existing tests before writing new ones. Testing requires a lot of quirks since almost everything is async when working with the terminal.


