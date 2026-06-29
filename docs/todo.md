# TODO

## Bugs

### Serious lag in dev harness
#dev
- maybe expensive reads in dev harness status? does it read from shell via osc maybe?
- or is there some event firing often? some cursormove or textchange?
- or is the cursor being updated from shell?
- whatever it is, it happened in the last few commits
- maybe it was zsh vi mode?

## Features

### p support
#popup

### add support for reading multi-line commands via shell integration
#api #shell-integration
- fish supports natively
- zsh support PREBUFFER
- bash does not seem to support
- this would make reading multi-line commands with completion

### edits with modifiable and non-modifiable should clamp to zone
#integrated #enhancement
- at least if trailing non-mod zone since it actually happens quite often on accident

### expose status to users

### add log levels
#enhancement
- number based, python scicomp style

### add simple markers to tab complete
#maybe
- not really needed(?) now since we read from zsh shell directly

## Refactor

## Chores
