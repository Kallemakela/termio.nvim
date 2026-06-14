## Ignore completions in read

- Goal: ignore shell completion UI when reading current command.
- Example: `ls<Tab>` shows matches below command in zsh.
- In zsh ZLE, the real editable command is [`BUFFER`](https://zsh.sourceforge.io/Doc/Release/Zsh-Line-Editor.html#index-BUFFER), and [`PREDISPLAY`](https://zsh.sourceforge.io/Doc/Release/Zsh-Line-Editor.html#index-PREDISPLAY) / [`POSTDISPLAY`](https://zsh.sourceforge.io/Doc/Release/Zsh-Line-Editor.html#index-POSTDISPLAY) are display text outside the editable buffer.
- I could not find terminal protocol markers for completion UI sections.

## Possible solutions

### Inject a shell integration script, VSCode does this

- VS Code shell integration docs: https://code.visualstudio.com/docs/terminal/shell-integration
- Supported escape sequences: https://code.visualstudio.com/docs/terminal/shell-integration#_supported-escape-sequences
- Example script for bash: https://github.com/microsoft/vscode/blob/main/src/vs/workbench/contrib/terminal/common/scripts/shellIntegration-bash.sh
- Hook shell lifecycle points such as prompt start/end, pre-exec, and command finish in the injected script (`__vsc_prompt_start`, `__vsc_prompt_end`, `__vsc_preexec`, `__vsc_command_complete`).
- Emit [`OSC 633;E;<commandline>[;<nonce>]`] with the exact command text.
- Read that escape sequence in the terminal and store the command separately from rendered terminal text.

### Keep a marker at the end inside neovim

- Simple solution could be to try to always keep our own marker at the end of the line without other sh scripts
- might interact with the shell cursor? maybe not? good to try at least.
