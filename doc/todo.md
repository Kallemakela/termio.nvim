# TODO

## Refactor

## Bugs

### Whitespace added to the terminal on some edits

### In insert mode > write > auto open > now in normal mode
#overlay, #auto
- focus to term buffer from insert mode changes to normal, not insert mode it seems
    - only critical for auto-open

### Prompt appearing slightly after osc marker
#api
- So on osc marker update, the promp is usually empty, e.g.
```text
2:k@mbp:termline.nvim>> (\27]133;B)cd ..
3:k@mbp:nvim>> (\27]133;B)echo hello world
4:hello world
5:             (\27]133;B)                                                                                                                                                     
```
- there is also extra whitespace on the new command line
- not sure if fixable
- current solution is to 
    - trim all whitespace commands on read
    - have another event on prompt update that gives user an event where prompt is up to date (10ms hardcoded wait)
- proper fix not planned 

## Chores

## Features

### transfer visual selection to terminal buffer when closing overlay window
#overlay
- so start selection in overlay, press e.g. gg, selection now in target buffer ending in the same spot as in overlay

### add overlay on edits in editable editor to hide flicker
#editable

### set color in config, nil defaults, mention that intentionally black in demo
#overlay

### Ignore completions on read line `./completions.md`
#api

### Better sync `./sync.md`
#sync

### Seamless navigation between term window and overlay
#overlay
- currently k on first line defocuses
- Esc or change to insert can always be used to focus back
- [ ] k should reset pos to prompt pos before moving up
- [ ] auto open on focus to current prompt line
    - or maybe do not close window when changing to
    - could actually be simple, do not close, and if cursor inside window, steal focus?
- not planned unless autofocus becomes important
