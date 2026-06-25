# TODO

## Bugs

### whitespace gets added when modifying command if target smaller than start command
- this is because the shell command editor replaces the grid cells that used to have characters with spaces to clear them
- neovim interprets these spaces as valid characters in the buffer.
- zsh only? 

## Features

### REPL support
- add prompt recognition for e.g. python >>> (or markers if possible)

### visual selection with modifiable and non-modifiable zone to `d` should d the part inside mod zone still(?)
- at least if trailing non-mod zone since it actually happens quite often on accident

### change the api config to chan_send vs FIFO

### expose status to users

### auto-switch to chan_send on REPL switch

### add simple markers to tab complete

## Refactor

### rewrite editable write

### rewrite editable open
- still uses read command i think, but might not be needed anymore


## Chores
