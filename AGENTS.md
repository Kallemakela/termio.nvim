# AGENTS.md

## Code Style
- Keep changes minimal.
- Add short comments above non-obvious code.
- Use specific function and variable names.
- Triple-check if you could use existing functionality.

## Workflow
1. Start with a focused failing test when practical.
2. Run the single test.
3. Implement minimal changes.
4. Run the single test, if fail go to 2, else go to 5.
5. Refactor to the smallest clear implementation.
6. Run all tests, if fail go to 2, else go to 7.
7. Cleanup. Remove extra logs, code that is not needed anymore, tests that were made for inspection rather than testing long term desired behaviour.

### Practices during workflow
- Add a lot of debug logs around the bug or new feature.
    - Read them every time after the test.
- Use the dev harness for setup-sensitive checks.

## Testing
- Run filtered tests: `sh ./run_filtered_tests.sh <test-file> <match-string>`
    - Can be used for running a single test.
    - Test output of the last test goes to `./tmp/test.out`.
- Run all tests: `make test`
- Run one file: `nvim --headless --noplugin -u ./scripts/minimal_init.lua -c "lua MiniTest.run_file('tests/test_dev.lua')" -c qall`
- Do NOT run multiple test commands at the same time. This causes issues.

## Dev Harness
- Headless smoke: `sh ./dev/run.sh --headless --debug --post-setup 'lua assert(_G.YourPluginName.config.debug == true)'`
- Interactive session: `sh ./dev/run.sh --debug`
- Debug output goes to `./tmp/dev.out`.
- Final terminal state goes to `./tmp/termdump.out`
- The users debug output goes to the same place. If the user reports something not working, it is a good idea to check if the scenario logs are here.

## Formatting
- Run `stylua .`
