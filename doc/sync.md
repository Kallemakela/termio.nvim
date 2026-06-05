# Sync

## Current setup

Command state:
```lua
{
  command = "echo hello",
  cursor = nil,
}
```
- read current terminal state on
    1. manual sync calls
    2. InsertLeave
- skip write when state is identical
- no check for running chansend process when triggering a new one (dangerous?)

## Upcoming

### Insert mode should instantly insert without sync
- Requires the cursor position to be synced
- First step could be to only do this if inserting to the end of command (most common case)

### More events
See what `editable-term.nvim` uses
- `TextChanged`
- `TextChangedI`
- ...

### Last write wins
- kill active chansend if new requested
- no idea if this is possible even
