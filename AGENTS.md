# AGENTS.md

always start with reading `README.md`

## Separation of editor and api
- it is extremely important to separate the api from the editor. The editor serves mostly as an example editor for users to create their own api integrations.

## Code style
- Add short comments above non-obvious code steps.
- Give functions and variables specific names. It should be immediately clear from the name what the function does and how it differs from other functions.

## Implementation Workflow
1. Implement change with debug logging.
2. Use the dev harness and verify the output is as expected.
3. Possibly write an unit test if you are confident that the implemented behaviour is desired in the future and the test won't get in the way in
4. Iterate on 1-3 until the solution passes.
5. Refactor to minimal amount of code changes in the package.
6. Run steps 1-4 with refactored solution.
7. Run relevant tests.

## Testing

### Run tests
`nvim --headless -u "scripts/minimal_init.lua" -c "lua MiniTest.run_file('tests/test_API.lua')" -c qall`
- Run filtered mini.test cases: `bash ./run_single_test.sh <test-file> <match-string>`
    - Example: `bash ./run_single_test.sh tests/test_API.lua "starts directly after"`
    - If you are iterating on a problem, always use this since it keeps debug logs clean.
    - You should always check debug logs when iterating on a single test.
- Test debug.log output goes to `./tmp/test.out`.

### Interactive
- Use the dev harness to run arbitrary workflows with the correct setup:
`sh ./dev/run.sh --headless --debug --post-setup 'lua require("termio.util.log").debug("debug", "hello world")' --words 3`
    - `--headless` switches startup mode.
    - `--debug` enables plugin debug output through `verbosefile` in `./tmp/dev.out`.
    - `--post-setup` runs an Ex command string after setup and before quit, like `nvim --headless -c`.
    - `--auto` sets `editor.open_on_prompt` true.

### Writing tests
- do not add tests for keybinds or config options
- `vim.api.nvim_input("ihello<Esc>")` is the best way to simulate key presses

## Formatting

- run `stylua .`
