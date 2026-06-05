## Prompt editor

Default editor.

- implemented on top of overlay editor behavior
- solves the issue in overlay where window x coord needs to either 
    1. start where prompt ends, which becomes wacky on multi line commands.
    2. start on col 1, which puts the window on top of prompt
- uses `buftype='prompt'`
- always uses start anchor; `editor.anchor` does not affect it

Tradeoff:
- some complexity needed to read the prompt from terminal, but seems to work
