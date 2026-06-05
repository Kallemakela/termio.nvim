# Plan: editable term buffer

Idea:
Terminal buffer is modifiable, actual shell state is hidden away and synced.

Status:
BLOCKED, can't insert in terminal buffer without sending chars to shell.
    - see `./insert-or-normal-mode-in-term-buffer.md`

- The core problem with this approach is that the shell process directly writes to the terminal buffer.
- This means that every key you send to shell, e.g. for sync, interacts with the editable buffer.
- So flicker seems impossible to avoid, which was the main reason to use this over something like editable-term.nvim
- What if we only sync on keys line cr, up, tab, similar to overlay?
    - Blocked: ./insert-or-normal-mode-in-term-buffer.md

### Model
- Keep one real terminal buffer visible
- Keep plugin draft state in `api.buffers[buf]`
- Terminal buffer is presentation during draft edit, not source of truth

### State
- `target_state.command`: editable draft command
- `target_state.cursor`: editable draft cursor as logical command col
- `shell_state.command`: last known shell command
- `shell_state.cursor`: last known shell cursor
- `prompt_end_cursor`: current OSC133 prompt position

### Open draft edit
- Only allow when cursor is on current prompt row
- Read shell state with existing `api.read_command(buf)` and `api.command_cursor(win, buf)`
- Copy shell state into draft state
- Make terminal buffer temporarily `modifiable`

### Edit flow
- User edits the visible terminal command area directly
- On `TextChanged` / `TextChangedI`:
- Read visible command area back into `draft.command`
- Read visible cursor back into `draft.cursor`
- Do not `chansend()` anything here
- Shell stays at `draft.shell_command` / `draft.shell_cursor`

### Repaint flow
- Add helper to rewrite only the command area from `draft.command`
- Add helper to place the visible cursor from `draft.cursor`
- Repaint on events that can corrupt the local presentation: cursor moves, mode switches, `TermRequest`, terminal redraw/output if detectable

### Sync flow
- Sync only on explicit actions: save, submit, pass-through keys
- Compare `draft.shell_command` with `draft.command`
- If different:
- `api.clear_command(buf)`
- `api.write_command(draft.command, buf)`
- Move shell cursor to `draft.cursor`
- Update `draft.shell_command = draft.command`
- Update `draft.shell_cursor = draft.cursor`

### Sending cursor to shell
- Add shell movement primitives like `editable-term.nvim`
- Needed keys:
- `goto_line_start`
- `forward_char`
- First cut: always send `goto_line_start`, then `forward_char` repeated `draft.cursor` times

### Actions
- `save`: sync, keep terminal open
- `submit`: sync, then send `\r`
- pass-through key like `<Up>` / `<Tab>`: sync, then send key
- `close` discard: leave shell untouched, drop draft state

### Drift handling
- If shell outputs a new prompt or command changes under an active draft, abort draft mode first version
- Restore `nomodifiable`
- Warn loudly, no silent failure

### Scope for first cut
- Prefer current prompt row editing first
- Wrapped display lines are fine
- Multiline continuation prompts may need a second pass
