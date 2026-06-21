# TODO

## Bugs

### [[ not working as expected, always goes to first prompt end

## Features

### visual selection with modifiable and non-modifiable zone to `d` should d the part inside mod zone still(?)
- at least if trailing non-mod zone since it actually happens quite often on accident

### rewrite editable write

### rewrite editable open
- still uses read command i think, but might not be needed anymore

### add simple markers to tab complete

### fish support
- fish has `commandline -f repaint` so should work like zsh

### add config option to make commands like D,C,$ ignore wrap-newlines and go to end of command

## Chores

update docs to match current zsh only state

## Investigate

why is nvim_chan_send much faster with bash than zsh?
- because zsh has a bunch of processing like syntax highlighting
- but both are still slower than expected, why is it not near instant?
