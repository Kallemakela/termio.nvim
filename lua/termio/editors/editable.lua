local config = require("termio.config")
local api = require("termio.api")
local helpers = require("termio.util.helpers")
local log = require("termio.util.log")
local state = require("termio.state")
local M = {}
local DELETE_OPERATOR_FUNC = "v:lua.require'termio.editors.editable'.apply_delete_operator"
-- `g@` calls operatorfunc after the keymap returns, so keep the selected
-- after-delete behavior in an upvalue until `apply_delete_operator()` runs.
local pending_after_delete_operator

local function build_context(ctx)
  ctx = ctx or {}
  local target_buf = ctx.target_buf or vim.api.nvim_get_current_buf()
  return {
    target_buf = target_buf,
    target_win = ctx.target_win or vim.fn.bufwinid(target_buf),
  }
end

---@param buf integer
---@param reason? string
local function set_sync_block_reason(buf, reason)
  M.buffers[buf].sync_block_reason = reason
end

---Read the editable draft command from the terminal buffer.
---@param buf integer
---@return string
function M.read_command_from_buffer(buf)
  local prompt_cursor = M.buffers[buf].promt_cursor
  local lines = vim.api.nvim_buf_get_lines(buf, prompt_cursor[1] - 1, -1, false)
  lines[1] = (lines[1] or ""):sub(prompt_cursor[2] + 1)
  return table.concat(lines, "")
end

local function read_editor_state(buf, win)
  return {
    command = M.read_command_from_buffer(buf),
    cursor = api.command_cursor(win, buf)[2],
  }
end

local function is_prompt_rendered(buf)
  local prompt_cursor = M.buffers[buf].promt_cursor
  if not prompt_cursor then
    return false
  end
  local line = vim.api.nvim_buf_get_lines(buf, prompt_cursor[1] - 1, prompt_cursor[1], false)[1]
    or ""
  return #line >= prompt_cursor[2]
end

local function is_command_rendered(buf, command)
  return is_prompt_rendered(buf) and M.read_command_from_buffer(buf) == command
end

---Wait for editable text to match shell state after query/write markers.
---Bash readline redraw can arrive after the marker that updates shell state.
---@param buf integer
---@param command? string
local function wait_until_command_is_rendered(buf, command)
  if not command or is_command_rendered(buf, command) then
    return
  end
  local timeout = config.options.timeouts.render_command
  vim.wait(timeout.limit_ms, function()
    return is_command_rendered(buf, command)
  end, timeout.interval_ms)
end

local function wait_for_terminal_leave(buf)
  local timeout = config.options.timeouts.terminal_leave
  vim.wait(timeout.limit_ms, function()
    return vim.api.nvim_get_mode().mode ~= "t"
  end, timeout.interval_ms)
end

---Return the buffer cursor where the editable command text ends.
---Terminal buffers may contain blank/padded cells after the prompt line. This
---walks forward exactly `#read_command()` bytes from `prompt_cursor`, so the
---editable zone ends at command text, not at the terminal buffer edge.
---@param buf integer
---@param prompt_cursor integer[] 0-based column cursor where command starts
---@return integer[] cursor 1-based row, 0-based column
local function get_command_end_location_in_buffer(buf, prompt_cursor)
  local row, col = unpack(prompt_cursor)
  local remaining = #M.read_command_from_buffer(buf)
  while remaining > 0 and row <= vim.api.nvim_buf_line_count(buf) do
    local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ""
    local line_start = row == prompt_cursor[1] and col or 0
    local line_remaining = math.max(#line - line_start, 0)
    if remaining <= line_remaining then
      return { row, line_start + remaining }
    end
    remaining = remaining - line_remaining
    row = row + 1
  end
  return { row, col }
end

local function is_position_after(row, col, target)
  return row > target[1] or (row == target[1] and col > target[2])
end

---Convert a command-text byte offset back to a terminal buffer cursor.
---@param buf integer
---@param offset integer offset from prompt end
---@return integer[] cursor 1-based row, 0-based column
local function get_buffer_location_from_shell_offset(buf, offset)
  local prompt_row, prompt_col = unpack(M.buffers[buf].promt_cursor)
  local row = prompt_row
  local col = prompt_col + offset
  local line_count = vim.api.nvim_buf_line_count(buf)
  while row < line_count do
    local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ""
    if col <= #line then
      return { row, col }
    end
    col = col - #line
    row = row + 1
  end
  return { row, col }
end

---Return the editable command zone in the terminal buffer.
---@param buf? integer
---@return { start_row: integer, start_col: integer, end_row: integer, end_col: integer }?
function M.get_editable_zone(buf)
  local target = buf or vim.api.nvim_get_current_buf()
  local bufinfo = M.buffers and M.buffers[target]
  local prompt_cursor = bufinfo and bufinfo.promt_cursor
  if not prompt_cursor then
    return nil
  end
  local start_row, start_col = unpack(prompt_cursor)
  local end_cursor = get_command_end_location_in_buffer(target, prompt_cursor)
  return {
    start_row = start_row,
    start_col = start_col,
    end_row = end_cursor[1],
    end_col = end_cursor[2],
  }
end

---Normalize Vim's cursor form for a command ending at the terminal wrap edge.
---After linewise operators Vim may place the cursor at `{end_row + 1, 0}`.
---For an editable command ending exactly at `{end_row, #line}`, that is the same
---visual position as command end and must stay inside the editable zone.
---@param buf integer
---@param cursor integer[] 1-based row, 0-based column
---@param zone? { start_row: integer, start_col: integer, end_row: integer, end_col: integer }
---@return integer[] cursor
local function canonicalize_cursor_at_wrapped_command_end(buf, cursor, zone)
  zone = zone or M.get_editable_zone(buf)
  if not zone or cursor[2] ~= 0 or cursor[1] ~= zone.end_row + 1 then
    return cursor
  end
  local end_line = vim.api.nvim_buf_get_lines(buf, zone.end_row - 1, zone.end_row, false)[1] or ""
  if zone.end_col == #end_line then
    return { zone.end_row, zone.end_col }
  end
  return cursor
end

---Check if the current cursor is inside the editable command zone.
---@param buf? integer
---@param cursor? integer[]
---@return boolean
function M.is_cursor_in_editable_zone(buf, cursor)
  local zone = M.get_editable_zone(buf)
  if not zone then
    return false
  end
  local row, col = unpack(
    canonicalize_cursor_at_wrapped_command_end(buf, cursor or vim.api.nvim_win_get_cursor(0), zone)
  )
  if row < zone.start_row or row > zone.end_row then
    return false
  end
  if row == zone.start_row and col < zone.start_col then
    return false
  end
  return row ~= zone.end_row or col <= zone.end_col
end

---@param cursor integer[]
---@param min_cursor integer[]
---@param max_cursor integer[]
---@return integer[] cursor
local function clamp_cursor(cursor, min_cursor, max_cursor)
  if is_position_after(min_cursor[1], min_cursor[2], max_cursor) then
    max_cursor = min_cursor
  end
  if cursor[1] == min_cursor[1] and cursor[2] < min_cursor[2] then
    return min_cursor
  end
  if is_position_after(cursor[1], cursor[2], max_cursor) then
    return max_cursor
  end
  return cursor
end

---@param buf integer
---@param cursor integer[]
---@param command_length? integer
---@return integer[] cursor
local function clamp_cursor_to_editable_zone(buf, cursor, command_length)
  local prompt_cursor = M.buffers[buf].promt_cursor
  if not prompt_cursor then
    return cursor
  end
  local zone = M.get_editable_zone(buf)
  if not zone then
    return cursor
  end
  local max_cursor = { zone.end_row, zone.end_col }
  if command_length then
    max_cursor = get_buffer_location_from_shell_offset(buf, math.max(command_length - 1, 0))
  end
  return clamp_cursor(cursor, prompt_cursor, max_cursor)
end

---@param win integer
---@param current_cursor integer[]
---@param target_cursor integer[]
local function move_cursor_if_needed(win, current_cursor, target_cursor)
  if current_cursor[1] ~= target_cursor[1] or current_cursor[2] ~= target_cursor[2] then
    vim.api.nvim_win_set_cursor(win, target_cursor)
  end
end

---@param buf integer
---@param cursor integer[]
---@param win? integer
---@param command_length? integer
---@return integer[] cursor
local function move_cursor_back_to_editable_zone(buf, cursor, win, command_length)
  win = win or 0
  local clamped_cursor = clamp_cursor_to_editable_zone(buf, cursor, command_length)
  move_cursor_if_needed(win, cursor, clamped_cursor)
  return clamped_cursor
end

---Refresh editable state from the current cursor position.
---@param buf integer
---@param cursor integer[]
---@param win? integer
local function refresh_editable_state(buf, cursor, win)
  win = win or 0
  local current_cursor = vim.api.nvim_win_get_cursor(win)
  cursor = canonicalize_cursor_at_wrapped_command_end(buf, cursor)
  move_cursor_if_needed(win, current_cursor, cursor)
  vim.bo[buf].modifiable = M.is_cursor_in_editable_zone(buf, cursor)
  if vim.bo[buf].modifiable then
    M.buffers[buf].last_editable_cursor = vim.deepcopy(cursor)
  end
end

---@param buf integer
---@param target? { command?: string, cursor?: integer }
---@return boolean did_sync
function M.write(buf, target)
  local bufinfo = M.buffers[buf]
  bufinfo.has_unsynced_edits = false
  target = target or {}
  if target.command == nil or target.cursor == nil then
    local current = read_editor_state(buf, vim.api.nvim_get_current_win())
    target.command = target.command or current.command
    target.cursor = target.cursor or current.cursor
  end
  local command = target.command
  local cursor = target.cursor
  local delay = config.options.waits.editable_write_guard_ms
  log.debug("editable.write.start", {
    buf = buf,
    has_target = next(target) ~= nil,
    delay = delay,
    sync_block_reason = bufinfo.sync_block_reason,
    has_unsynced_edits = bufinfo.has_unsynced_edits,
  })
  -- Terminal redraw after sync can emit TextChanged events into the same buffer.
  -- Keep a short guard so those redraws are not treated as fresh user edits.
  set_sync_block_reason(buf, "write")
  vim.defer_fn(function()
    if M.buffers[buf] and M.buffers[buf].sync_block_reason == "write" then
      set_sync_block_reason(buf, nil)
    end
    log.debug("editable.writing.stop", { buf = buf })
  end, delay)
  local shell_state = helpers.ensure_buffer_state(api.buffers, buf).shell_state
  local did_sync = shell_state.command ~= command
    or (cursor ~= nil and shell_state.cursor ~= cursor)
  if did_sync then
    api.write_command(command, buf, cursor)
    wait_until_command_is_rendered(buf, command)
  end
  log.debug("editable.write.done", { buf = buf, did_sync = did_sync })
  return did_sync
end

local function override_state(current, target)
  if not target then
    return current
  end
  if target.command ~= nil then
    current.command = type(target.command) == "function" and target.command(current)
      or target.command
  end
  if target.cursor ~= nil then
    current.cursor = type(target.cursor) == "function" and target.cursor(current) or target.cursor
  end
  return current
end

local function enter_insert_with_target(buf, target_state)
  local target =
    override_state(read_editor_state(buf, vim.api.nvim_get_current_win()), target_state)
  M.write(buf, target)
  vim.cmd.startinsert()
end

local function run_termio_action(buf, event, action, disabled_return)
  if helpers.is_editor_disabled(buf) then
    log.debug(event .. ".disabled", { buf = buf })
    return disabled_return
  end
  return action()
end

local function set_termio_keymap(mode, lhs, event, buf, action, opts)
  opts = vim.tbl_extend("force", { buffer = buf }, opts or {})
  local disabled_return = opts.expr and "" or nil
  vim.keymap.set(mode, lhs, function()
    return run_termio_action(buf, event, action, disabled_return)
  end, opts)
end

---@param buf integer
local function mark_unsynced_edit(buf)
  M.buffers[buf].has_unsynced_edits = true
end

local function paste_register_into_editable_buffer(after, register)
  -- `normal! p` can take terminal-buffer paste paths. Keep paste as a plain
  -- buffer edit so the editable draft stays desynced from the shell state.
  local text = vim.fn.getreg(register or vim.v.register)
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  if after then
    col = col + 1
  end
  local lines = vim.split(text, "\n", { plain = true })
  vim.api.nvim_buf_set_text(0, row - 1, col, row - 1, col, lines)
  -- Cursor should land on the last inserted character, matching normal paste.
  vim.api.nvim_win_set_cursor(0, { row + #lines - 1, col + #lines[#lines] - 1 })
end

local function delete_visual_selection_then(action)
  mark_unsynced_edit(vim.api.nvim_get_current_buf())
  vim.cmd("normal! d")
  if action then
    action()
  end
end

---Replace the visual selection with a register using editable-buffer writes.
---The delete step changes `vim.v.register`, so preserve and pass the original
---register explicitly to paste the user's intended text.
---@param after boolean paste after cursor when true, before cursor when false
local function paste_register_over_visual_selection(after)
  local register = vim.v.register
  local text = vim.fn.getreg(register):gsub("%s+$", "")
  local register_type = vim.fn.getregtype(register)
  delete_visual_selection_then(function()
    vim.fn.setreg(register, text, register_type)
    paste_register_into_editable_buffer(after, register)
  end)
end

---Convert a buffer cursor to a command-text byte offset from the prompt end.
---@param buf integer
---@param cursor integer[] 1-based row, 0-based column
---@return integer offset
local function get_shell_cursor_offset(buf, cursor)
  local prompt_row, prompt_col = unpack(M.buffers[buf].promt_cursor)
  local offset = 0
  for row = prompt_row, cursor[1] do
    local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ""
    local start_col = row == prompt_row and prompt_col or 0
    local end_col = row == cursor[1] and cursor[2] or #line
    offset = offset + math.max(end_col - start_col, 0)
  end
  return offset
end

---Return the command offset where the current operator motion started.
---@param buf integer
---@return integer offset
local function command_offset_at_operator_start(buf)
  local mark = vim.api.nvim_buf_get_mark(buf, "[")
  return get_shell_cursor_offset(buf, mark)
end

---Delete the range Vim resolved for the pending `g@` operator motion.
---@param motion_type string
local function delete_operator_motion_range(motion_type)
  -- `g@` stores the resolved motion range in `[ and `]. Delete that range
  -- after Vim has handled the motion instead of reimplementing motions here.
  vim.cmd("normal! " .. (motion_type == "line" and "`[V`]d" or "`[v`]d"))
end

local function keep_cursor_at_command_offset(buf, offset)
  local cursor = get_buffer_location_from_shell_offset(buf, offset)
  move_cursor_back_to_editable_zone(buf, cursor)
end

---Sync the deleted draft to the shell and continue in terminal insert mode.
---@param buf integer
---@param offset integer command offset where insert mode should continue
local function enter_insert_at_command_offset(buf, offset)
  M.write(buf, { cursor = offset })
  vim.cmd.startinsert()
end

---Delete the range captured by `g@` and run the pending after-delete callback.
---@param motion_type string
function M.apply_delete_operator(motion_type)
  local buf = vim.api.nvim_get_current_buf()
  local offset = command_offset_at_operator_start(buf)
  -- pending_after_delete_operator should handle keeping cursor at correct position
  -- for c{motion}, this happens by going to 't' mode which clamps cursor
  -- for d{motion}, we manually apply keep_cursor_at_command_offset
  local after_delete = pending_after_delete_operator or keep_cursor_at_command_offset
  pending_after_delete_operator = nil
  mark_unsynced_edit(buf)
  delete_operator_motion_range(motion_type)
  after_delete(buf, offset)
end

local function start_delete_operator(after_delete)
  -- `g@` lets Vim collect the motion range before `apply_delete_operator()`
  -- handles shared delete-side effects and the key-specific follow-up.
  pending_after_delete_operator = after_delete
  vim.go.operatorfunc = DELETE_OPERATOR_FUNC
  return "g@"
end

local function start_change_operator()
  return start_delete_operator(enter_insert_at_command_offset)
end

---Handle terminal text changes with the concurrent-write guard.
---@param buf integer
function M.handle_text_changed(buf)
  local bufinfo = M.buffers[buf]
  log.debug("editable.text_changed", {
    buf = buf,
    sync_block_reason = bufinfo.sync_block_reason,
    has_unsynced_edits = bufinfo.has_unsynced_edits,
    line = vim.api.nvim_get_current_line(),
  })
  if not bufinfo.promt_cursor then
    log.debug("editable.text_changed.skip", {
      buf = buf,
      sync_block_reason = bufinfo.sync_block_reason,
      has_unsynced_edits = bufinfo.has_unsynced_edits,
    })
    return
  end
  if bufinfo.sync_block_reason == "term_leave" then
    set_sync_block_reason(buf, nil)
    log.debug("editable.text_changed.skip", {
      buf = buf,
      sync_block_reason = bufinfo.sync_block_reason,
      has_unsynced_edits = bufinfo.has_unsynced_edits,
    })
    return
  end
  if bufinfo.sync_block_reason == "write" or bufinfo.has_unsynced_edits then
    log.debug("editable.text_changed.skip", {
      buf = buf,
      sync_block_reason = bufinfo.sync_block_reason,
      has_unsynced_edits = bufinfo.has_unsynced_edits,
    })
    return
  end
  M.write(buf)
end

---Open the editable terminal editor for the target terminal.
---@param ctx? table
---@return boolean opened
function M.open(ctx)
  ctx = build_context(ctx)
  local buf, win = ctx.target_buf, ctx.target_win
  if not helpers.is_enabled_terminal(buf) then
    error("termio: terminal buffer name does not match editor.terminal_name_pattern")
  end
  if helpers.is_editor_disabled(buf) then
    log.debug("editable.open.disabled", { buf = buf, win = win })
    return false
  end
  local ok, err = pcall(api.clear_completion_suggestions, buf)
  if not ok then
    log.debug("editable clear completions skipped", { buf = buf, error = err })
  end
  local buffer_state = helpers.ensure_buffer_state(api.buffers, buf)
  api.read_command(buf)
  log.debug("editable.open", { buf = buf, win = win, shell_state = buffer_state.shell_state })
  vim.cmd("stopinsert")
  wait_for_terminal_leave(buf)
  wait_until_command_is_rendered(buf, buffer_state.shell_state.command)
  vim.schedule(function()
    local cursor = vim.api.nvim_win_get_cursor(win)
    cursor = move_cursor_back_to_editable_zone(buf, cursor, win, buffer_state.shell_state.cursor)
    refresh_editable_state(buf, cursor, win)
  end)
  return true
end

local function apply_keymaps(buf)
  local handlers = {
    open = function(lhs)
      return function()
        log.debug("editable.key.open", { buf = buf, mode = vim.api.nvim_get_mode().mode })
        local ok, opened = pcall(M.open, { target_buf = buf })
        if not ok then
          vim.notify(opened, vim.log.levels.WARN)
        end
        if not ok or opened == false then
          helpers.send_keys(lhs, buf)
        end
      end
    end,
    submit = function()
      return run_termio_action(buf, "editable.key.submit", function()
        local mode = vim.api.nvim_get_mode().mode
        log.debug("editable.key.submit", { buf = buf, mode = mode })
        if mode:sub(1, 1) == "t" then
          helpers.send_keys("<CR>", buf)
        else
          M.write(buf)
          helpers.send_keys("<CR>", buf)
        end
        vim.cmd("startinsert")
      end)
    end,
    write = function()
      return run_termio_action(buf, "editable.key.write", function()
        log.debug("editable.key.write", { buf = buf, mode = vim.api.nvim_get_mode().mode })
        M.write(buf)
      end)
    end,
    toggle = function()
      log.debug("editable.key.toggle", { buf = buf, mode = vim.api.nvim_get_mode().mode })
      state.toggle()
    end,
  }
  for lhs, action in pairs(config.options.editor.keys.t) do
    local handler = action == "open" and handlers.open(lhs) or handlers[action]
    if handler then
      vim.keymap.set("t", lhs, handler, { buffer = buf })
    end
  end
  for lhs, action in pairs(config.options.editor.keys.n) do
    local handler = handlers[action]
    if handler then
      vim.keymap.set("n", lhs, handler, { buffer = buf })
    end
  end
end

---@class EditableTermConfig
---@field promts? table<string, true>

---@param config EditableTermConfig
M.setup = function(config)
  M.buffers = M.buffers or {}
  M.promts = (config or {}).promts
  vim.api.nvim_create_autocmd("TermOpen", {
    group = vim.api.nvim_create_augroup("editable-term", {}),
    callback = function(args)
      if not helpers.is_enabled_terminal(args.buf) then
        return
      end
      M.buffers[args.buf] = {
        has_unsynced_edits = false,
        sync_block_reason = "term_leave",
      }
      log.debug("editable.term_open", { buf = args.buf })
      apply_keymaps(args.buf)
      local editgroup =
        vim.api.nvim_create_augroup("editable-term-text-change" .. args.buf, { clear = true })
      set_termio_keymap("n", "A", "editable.key.A", args.buf, function()
        log.debug("editable.key.A", { buf = args.buf })
        enter_insert_with_target(args.buf, {
          cursor = function(current)
            return #current.command
          end,
        })
      end)
      set_termio_keymap("n", "I", "editable.key.I", args.buf, function()
        log.debug("editable.key.I", { buf = args.buf })
        enter_insert_with_target(args.buf, { cursor = 0 })
      end)
      set_termio_keymap("n", "i", "editable.key.i", args.buf, function()
        log.debug("editable.key.i", { buf = args.buf, cursor = vim.api.nvim_win_get_cursor(0) })
        enter_insert_with_target(args.buf)
      end)
      set_termio_keymap("n", "a", "editable.key.a", args.buf, function()
        log.debug("editable.key.a", { buf = args.buf, cursor = vim.api.nvim_win_get_cursor(0) })
        enter_insert_with_target(args.buf, {
          cursor = function(current)
            return current.cursor + 1
          end,
        })
      end)
      set_termio_keymap("n", "x", "editable.key.x", args.buf, function()
        log.debug("editable.key.x", { buf = args.buf, cursor = vim.api.nvim_win_get_cursor(0) })
        mark_unsynced_edit(args.buf)
        vim.cmd("normal! x")
      end)
      set_termio_keymap("n", "p", "editable.key.p", args.buf, function()
        log.debug("editable.key.p", { buf = args.buf, cursor = vim.api.nvim_win_get_cursor(0) })
        mark_unsynced_edit(args.buf)
        paste_register_into_editable_buffer(true)
      end)
      set_termio_keymap("n", "P", "editable.key.P", args.buf, function()
        log.debug("editable.key.P", { buf = args.buf, cursor = vim.api.nvim_win_get_cursor(0) })
        mark_unsynced_edit(args.buf)
        paste_register_into_editable_buffer(false)
      end)
      set_termio_keymap("n", "d", "editable.key.d", args.buf, function()
        log.debug("editable.key.d", { buf = args.buf, cursor = vim.api.nvim_win_get_cursor(0) })
        return start_delete_operator()
      end, { expr = true })
      set_termio_keymap("n", "c", "editable.key.c", args.buf, function()
        log.debug("editable.key.c", { buf = args.buf, cursor = vim.api.nvim_win_get_cursor(0) })
        return start_change_operator()
      end, { expr = true })
      set_termio_keymap("n", "cw", "editable.key.cw", args.buf, function()
        log.debug("editable.key.cw", { buf = args.buf, cursor = vim.api.nvim_win_get_cursor(0) })
        -- Vim treats `cw` like `ce`, preserving the following whitespace.
        return start_change_operator() .. "e"
      end, { expr = true })
      set_termio_keymap("n", "C", "editable.key.C", args.buf, function()
        log.debug("editable.key.C", { buf = args.buf, cursor = vim.api.nvim_win_get_cursor(0) })
        return start_change_operator() .. "$"
      end, { expr = true })
      set_termio_keymap("x", "c", "editable.key.visual_c", args.buf, function()
        log.debug(
          "editable.key.visual_c",
          { buf = args.buf, cursor = vim.api.nvim_win_get_cursor(0) }
        )
        return start_change_operator()
      end, { expr = true })
      set_termio_keymap("x", "p", "editable.key.visual_p", args.buf, function()
        log.debug(
          "editable.key.visual_p",
          { buf = args.buf, cursor = vim.api.nvim_win_get_cursor(0) }
        )
        paste_register_over_visual_selection(true)
      end)
      set_termio_keymap("x", "P", "editable.key.visual_P", args.buf, function()
        log.debug(
          "editable.key.visual_P",
          { buf = args.buf, cursor = vim.api.nvim_win_get_cursor(0) }
        )
        paste_register_over_visual_selection(false)
      end)
      vim.api.nvim_create_autocmd("TextChanged", {
        buffer = args.buf,
        group = editgroup,
        callback = function(args)
          M.handle_text_changed(args.buf)
        end,
      })
      vim.api.nvim_create_autocmd("TermLeave", {
        group = editgroup,
        buffer = args.buf,
        callback = function(args)
          local bufinfo = M.buffers[args.buf]
          -- Any TextChanged immediately after leaving terminal mode may come
          -- from the mode switch or shell redraw instead of a deliberate edit.
          set_sync_block_reason(args.buf, "term_leave")
          local ln = vim.api.nvim_get_current_line()
          local cursor = vim.api.nvim_win_get_cursor(0)
          log.debug("editable.term_leave", { buf = args.buf, line = ln, cursor = cursor })
          vim.api.nvim_win_set_cursor(0, cursor)
          local line_num = cursor[1]
          if M.promts ~= nil and ln ~= nil then
            for pattern in pairs(M.promts) do
              local start, ent = ln:find(pattern)
              if start ~= nil then
                bufinfo.promt_cursor = { line_num, ent }
                log.debug("editable.term_leave.prompt_match", {
                  buf = args.buf,
                  pattern = pattern,
                  prompt_cursor = bufinfo.promt_cursor,
                })
                break
              end
            end
          end
        end,
      })
      vim.api.nvim_create_autocmd("TermRequest", {
        group = editgroup,
        buffer = args.buf,
        callback = function(args)
          if string.match(args.data.sequence, "^\027]133;B") then
            M.buffers[args.buf].promt_cursor = args.data.cursor
            log.debug("editable.term_request.prompt", { buf = args.buf, cursor = args.data.cursor })
          end
        end,
      })
      vim.api.nvim_create_autocmd("BufDelete", {
        group = editgroup,
        buffer = args.buf,
        callback = function(args)
          vim.api.nvim_del_augroup_by_id(editgroup)
        end,
      })
      vim.api.nvim_create_autocmd("CursorMoved", {
        group = editgroup,
        buffer = args.buf,
        callback = function(args)
          local cursor = vim.api.nvim_win_get_cursor(0)
          local bufinfo = M.buffers[args.buf]
          refresh_editable_state(args.buf, cursor)
          log.debug("editable.cursor_moved", {
            buf = args.buf,
            cursor = vim.api.nvim_win_get_cursor(0),
            prompt_cursor = bufinfo.promt_cursor,
            modifiable = vim.bo.modifiable,
          })
        end,
      })
    end,
  })
end
return M
