## Ignore completions in read

- Goal: ignore shell completion UI when reading current command.
- Example: `ls<Tab>` shows matches below command in zsh.
- In zsh ZLE, the real editable command is [`BUFFER`](https://zsh.sourceforge.io/Doc/Release/Zsh-Line-Editor.html#index-BUFFER), and [`PREDISPLAY`](https://zsh.sourceforge.io/Doc/Release/Zsh-Line-Editor.html#index-PREDISPLAY) / [`POSTDISPLAY`](https://zsh.sourceforge.io/Doc/Release/Zsh-Line-Editor.html#index-POSTDISPLAY) are display text outside the editable buffer.
- I could not find terminal protocol markers for completion UI sections.

## Useful zsh fields

- `BUFFER` / `CURSOR`: authoritative editable command state. `ls <Tab>` stayed `cursor=3 buffer="ls "`; `ls A<Tab>` became `cursor=13 buffer="ls AGENTS.md "`.
- `LBUFFER` / `RBUFFER`: same command state split at cursor. Best payload shape for sync/cursor math.
- `SUFFIX_ACTIVE`, `SUFFIX_START`, `SUFFIX_END`: useful for auto-removable inserted suffixes. `ls A<Tab>` had `suffix_active=1 suffix_start=12 suffix_end=13`.
- `BUFFERLINES`: editable command screen-line count, not completion list rows. Stayed `1` in tests.
- `PREDISPLAY` / `POSTDISPLAY`: empty for normal completion lists in tests. Not useful for list rows.
- `compstate[list_lines]`, `compstate[list]`, `compstate[nmatches]`, `compstate[insert]`, `compstate[old_list]`, `compstate[unambiguous]`: likely best for exact completion-list info, but only available inside completion widgets/functions, not a plain wrapper around `zle .expand-or-complete`.

Current conclusion: wrapping completion widgets can cheaply emit `CL;S/E` with `CURSOR`, `LBUFFER`, `RBUFFER`, and suffix fields. Exact list row counts probably require a `zle -C` / compsys-level experiment with `compstate[list_lines]`.

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
