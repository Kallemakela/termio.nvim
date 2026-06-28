local config = require("termio.config")
local api = require("termio.api")
local helpers = require("termio.util.helpers")
local keymaps = require("termio.util.keymaps")
local log = require("termio.util.log")
local terminal_buffer = require("termio.terminal_buffer")
local M = {}
local DELETE_OPERATOR_FUNC = "v:lua.require'termio.editors.editable'.apply_delete_operator"
local YANK_OPERATOR_FUNC = "v:lua.require'termio.editors.editable'.apply_yank_operator"
-- `g@` calls operatorfunc after the keymap returns, so keep the selected
-- after-delete behavior in an upvalue until `apply_delete_operator()` runs.
local pending_after_delete_operator
local pending_after_yank_cursor

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

local function has_command_start_cursor(buf)
  return api.command_start_cursor(buf) ~= nil
end

local function ensure_command_start_cursor(buf)
  if has_command_start_cursor(buf) then
    return true
  end
  api.update_prompt_range(buf)
  return has_command_start_cursor(buf)
end

---Read the editable draft command from the terminal buffer.
---@param buf integer
---@return string
function M.read_command_from_buffer(buf)
  return terminal_buffer.command_text(buf, api.command_start_cursor(buf))
end

local function read_editor_state(buf, win)
  return {
    command = M.read_command_from_buffer(buf),
    cursor = api.cursor_index_in_command(win, buf),
  }
end

local function is_prompt_rendered(buf)
  local cursor = api.command_start_cursor(buf)
  if not cursor then
    return false
  end
  local line = vim.api.nvim_buf_get_lines(buf, cursor[1] - 1, cursor[1], false)[1] or ""
  return #line >= cursor[2]
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

local function is_position_after(row, col, target)
  return row > target[1] or (row == target[1] and col > target[2])
end

---Convert a command-text byte offset back to a terminal buffer cursor.
---@param buf integer
---@param offset integer offset from prompt end
---@return integer[] cursor 1-based row, 0-based column
local function get_buffer_location_from_shell_offset(buf, offset)
  return terminal_buffer.location_from_offset(buf, api.command_start_cursor(buf), offset)
end

---Return the editable command zone in the terminal buffer.
---@param buf? integer
---@return { start_row: integer, start_col: integer, end_row: integer, end_col: integer }?
function M.get_editable_zone(buf)
  local target = buf or vim.api.nvim_get_current_buf()
  local cursor = api.command_start_cursor(target)
  if not cursor then
    return nil
  end
  local start_row, start_col = unpack(cursor)
  local end_cursor =
    terminal_buffer.location_from_offset(target, cursor, #M.read_command_from_buffer(target))
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
  local zone = M.get_editable_zone(buf)
  if not zone then
    return cursor
  end
  local min_cursor = { zone.start_row, zone.start_col }
  local max_cursor = { zone.end_row, zone.end_col }
  if command_length then
    max_cursor = get_buffer_location_from_shell_offset(buf, math.max(command_length - 1, 0))
  end
  return clamp_cursor(cursor, min_cursor, max_cursor)
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
  local command_state = helpers.ensure_buffer_state(api.buffers, buf).shell_state
  local did_sync = command_state.command ~= command
    or (cursor ~= nil and command_state.cursor ~= cursor)
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
  local win = vim.api.nvim_get_current_win()
  if not ensure_command_start_cursor(buf) then
    vim.cmd.startinsert()
    return
  end
  local target = override_state(read_editor_state(buf, win), target_state)
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

local function set_termio_keymap(buf, mode, lhs, event, action, opts)
  opts = opts or {}
  local disabled_return = opts.expr and "" or nil
  M.buffers[buf].keymaps:map(mode, lhs, function()
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
  local prompt_row, prompt_col = unpack(api.command_start_cursor(buf))
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
  local clamped_cursor = clamp_cursor_to_editable_zone(buf, cursor)
  move_cursor_if_needed(0, vim.api.nvim_win_get_cursor(0), clamped_cursor)
end

local function command_end_offset(buf)
  return #M.read_command_from_buffer(buf)
end

local function add_mark_at_command_offset(buf, offset)
  local cursor = get_buffer_location_from_shell_offset(buf, offset)
  vim.api.nvim_buf_set_mark(buf, "z", cursor[1], cursor[2], {})
  return "`z"
end

-- Motion used by `0` and `^`: jump to the first byte of the command.
local function add_mark_to_command_start(buf)
  return add_mark_at_command_offset(buf, 0)
end

-- Motion used by `$`: jump to the last command byte, not the exclusive end.
local function add_mark_to_command_last_byte(buf)
  return add_mark_at_command_offset(buf, math.max(command_end_offset(buf) - 1, 0))
end

-- Operator-pending `$` needs an explicit charwise range for wrapped commands.
local function charwise_command_end_operator_motion(buf)
  -- `g@` needs a real motion range. Jumping to a temporary mark gives Vim that
  -- range; `v` forces charwise selection so multi-row wrapped commands are not
  -- treated as linewise deletions.
  return "v" .. add_mark_to_command_last_byte(buf)
end

local function move_to_command_start(buf)
  keep_cursor_at_command_offset(buf, 0)
end

local function move_to_command_end(buf)
  keep_cursor_at_command_offset(buf, math.max(command_end_offset(buf) - 1, 0))
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

function M.apply_yank_operator()
  local buf = vim.api.nvim_get_current_buf()
  local command = M.read_command_from_buffer(buf)
  local start_offset = command_offset_at_operator_start(buf)
  -- `]` points at the last included byte; convert it to an exclusive end.
  local end_offset = get_shell_cursor_offset(buf, vim.api.nvim_buf_get_mark(buf, "]")) + 1
  if end_offset < start_offset then
    start_offset, end_offset = end_offset, start_offset
  end
  vim.fn.setreg(vim.v.register, command:sub(start_offset + 1, math.min(end_offset, #command)), "V")
  if pending_after_yank_cursor then
    vim.api.nvim_win_set_cursor(0, pending_after_yank_cursor)
    pending_after_yank_cursor = nil
  end
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

local function start_yank_operator()
  pending_after_yank_cursor = vim.api.nvim_win_get_cursor(0)
  vim.go.operatorfunc = YANK_OPERATOR_FUNC
  return "g@"
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
  if not has_command_start_cursor(buf) then
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
  local buffer_state = helpers.ensure_buffer_state(api.buffers, buf)
  buffer_state.shell_state = api.read_state(buf, win)
  api.clear_completion_suggestions(buf)
  log.debug("editable.open", { buf = buf, win = win, shell_state = buffer_state.shell_state })
  wait_until_command_is_rendered(buf, buffer_state.shell_state.command)
  local cursor = vim.api.nvim_win_get_cursor(win)
  cursor = move_cursor_back_to_editable_zone(buf, cursor, win, #buffer_state.shell_state.command)
  refresh_editable_state(buf, cursor, win)
  return true
end

local function map_config_keymaps(buf)
  local buffer_state = M.buffers[buf]
  local handlers = {
    open = function(lhs)
      return function()
        log.debug("editable.key.open", { buf = buf, mode = vim.api.nvim_get_mode().mode })
        return run_termio_action(buf, "editable.key.open", function()
          vim.cmd("stopinsert")
        end, helpers.term_codes(lhs))
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
      require("termio").toggle()
    end,
  }
  for lhs, action in pairs(config.options.editor.keys.t) do
    local handler = action == "open" and handlers.open(lhs) or handlers[action]
    if handler then
      if action == "toggle" then
        buffer_state.keymaps:always("t", lhs, handler)
      else
        buffer_state.keymaps:map("t", lhs, handler)
      end
    end
  end
  for lhs, action in pairs(config.options.editor.keys.n) do
    local handler = handlers[action]
    if handler then
      if action == "toggle" then
        buffer_state.keymaps:always("n", lhs, handler)
      else
        buffer_state.keymaps:map("n", lhs, handler)
      end
    end
  end
end

local function log_editable_key(event, buf)
  log.debug(event, { buf = buf, cursor = vim.api.nvim_win_get_cursor(0) })
end

-- Enter terminal insert mode at Vim-like insertion targets.
local function map_insert_keymaps(buf)
  local insert_targets = {
    A = {
      cursor = function(current)
        return #current.command
      end,
    },
    I = { cursor = 0 },
    i = false,
    a = {
      cursor = function(current)
        return current.cursor + 1
      end,
    },
  }
  for lhs, target in pairs(insert_targets) do
    set_termio_keymap(buf, "n", lhs, "editable.key." .. lhs, function()
      log_editable_key("editable.key." .. lhs, buf)
      enter_insert_with_target(buf, target or nil)
    end)
  end
end

-- Apply immediate normal-mode edits that do not need a motion.
local function map_normal_edit_keymaps(buf)
  local normal_edits = {
    x = function()
      mark_unsynced_edit(buf)
      vim.cmd("normal! x")
    end,
    p = function()
      mark_unsynced_edit(buf)
      paste_register_into_editable_buffer(true)
    end,
    P = function()
      mark_unsynced_edit(buf)
      paste_register_into_editable_buffer(false)
    end,
  }
  for lhs, action in pairs(normal_edits) do
    set_termio_keymap(buf, "n", lhs, "editable.key." .. lhs, function()
      log_editable_key("editable.key." .. lhs, buf)
      action()
    end)
  end
end

local function map_normal_motion_keymaps(buf)
  local normal_motions =
    { ["0"] = move_to_command_start, ["^"] = move_to_command_start, ["$"] = move_to_command_end }
  for lhs, action in pairs(normal_motions) do
    set_termio_keymap(buf, "n", lhs, "editable.key." .. lhs, function()
      log_editable_key("editable.key." .. lhs, buf)
      action(buf)
    end)
  end
end

local function map_operator_pending_motion_keymaps(buf)
  local operator_motions = {
    ["0"] = add_mark_to_command_start,
    ["^"] = add_mark_to_command_start,
    ["$"] = charwise_command_end_operator_motion,
  }
  for lhs, action in pairs(operator_motions) do
    set_termio_keymap(buf, "o", lhs, "editable.key.operator_" .. lhs, function()
      log_editable_key("editable.key.operator_" .. lhs, buf)
      return action(buf)
    end, { expr = true })
  end
end

local function map_visual_motion_keymaps(buf)
  local visual_motions = {
    ["0"] = add_mark_to_command_start,
    ["^"] = add_mark_to_command_start,
    ["$"] = add_mark_to_command_last_byte,
  }
  for lhs, action in pairs(visual_motions) do
    set_termio_keymap(buf, "x", lhs, "editable.key.visual_" .. lhs, function()
      log_editable_key("editable.key.visual_" .. lhs, buf)
      return action(buf)
    end, { expr = true })
  end
end

-- Start Vim's operator flow for normal-mode delete/change commands.
local function map_normal_operator_keymaps(buf)
  local normal_operators = {
    dd = {
      start = function()
        return "0d$"
      end,
      motion = function()
        return ""
      end,
      remap = true,
    },
    d = {
      start = start_delete_operator,
      motion = function()
        return ""
      end,
    },
    D = {
      start = start_delete_operator,
      motion = function()
        return "$"
      end,
      remap = true,
    },
    c = {
      start = start_change_operator,
      motion = function()
        return ""
      end,
    },
    C = {
      start = start_change_operator,
      motion = function()
        return "$"
      end,
      remap = true,
    },
    s = {
      start = start_change_operator,
      motion = function()
        return vim.v.count1 .. "l"
      end,
    },
    yy = {
      start = function()
        return "0" .. start_yank_operator() .. "$"
      end,
      motion = function()
        return ""
      end,
      remap = true,
    },
  }
  for lhs, operator in pairs(normal_operators) do
    set_termio_keymap(buf, "n", lhs, "editable.key." .. lhs, function()
      log_editable_key("editable.key." .. lhs, buf)
      return operator.start() .. operator.motion()
    end, { expr = true, remap = operator.remap })
  end
end

local function map_visual_operator_keymaps(buf)
  -- Visual mode already has a selected range, so no extra motion suffix is needed.
  for _, lhs in ipairs({ "c", "s" }) do
    set_termio_keymap(buf, "x", lhs, "editable.key.visual_" .. lhs, function()
      log_editable_key("editable.key.visual_" .. lhs, buf)
      return start_change_operator()
    end, { expr = true })
  end
end

-- Replace a visual selection with the selected paste register.
local function map_visual_paste_keymaps(buf)
  local visual_pastes = { p = true, P = false }
  for lhs, after in pairs(visual_pastes) do
    set_termio_keymap(buf, "x", lhs, "editable.key.visual_" .. lhs, function()
      log_editable_key("editable.key.visual_" .. lhs, buf)
      paste_register_over_visual_selection(after)
    end)
  end
end

local function map_editable_keymaps(buf)
  map_insert_keymaps(buf)
  map_normal_edit_keymaps(buf)
  map_normal_motion_keymaps(buf)
  map_operator_pending_motion_keymaps(buf)
  map_visual_motion_keymaps(buf)
  map_normal_operator_keymaps(buf)
  map_visual_operator_keymaps(buf)
  map_visual_paste_keymaps(buf)
end

function M.enable()
  for _, buffer_state in pairs(M.buffers or {}) do
    buffer_state.keymaps:enable()
  end
end

function M.disable()
  for _, buffer_state in pairs(M.buffers or {}) do
    buffer_state.keymaps:disable()
  end
end

M.setup = function()
  M.buffers = M.buffers or {}
  vim.api.nvim_create_autocmd("TermOpen", {
    group = vim.api.nvim_create_augroup("editable-term", {}),
    callback = function(args)
      if not helpers.is_enabled_terminal(args.buf) then
        return
      end
      M.buffers[args.buf] = {
        has_unsynced_edits = false,
        keymaps = keymaps.group({
          buffer = args.buf,
          enabled = not helpers.is_editor_disabled(args.buf),
        }),
        sync_block_reason = "term_leave",
      }
      log.debug("editable.term_open", { buf = args.buf })
      map_config_keymaps(args.buf)
      map_editable_keymaps(args.buf)
      local editgroup =
        vim.api.nvim_create_augroup("editable-term-text-change" .. args.buf, { clear = true })
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
          -- Any TextChanged immediately after leaving terminal mode may come
          -- from the mode switch or shell redraw instead of a deliberate edit.
          set_sync_block_reason(args.buf, "term_leave")
          log.debug("editable.term_leave", { buf = args.buf })
          local ok, opened = pcall(M.open, { target_buf = args.buf })
          if not ok then
            log.debug("editable.open.failed", { buf = args.buf, error = opened })
          end
        end,
      })
      vim.api.nvim_create_autocmd("BufDelete", {
        group = editgroup,
        buffer = args.buf,
        callback = function(args)
          M.buffers[args.buf] = nil
          vim.api.nvim_del_augroup_by_id(editgroup)
        end,
      })
      vim.api.nvim_create_autocmd("CursorMoved", {
        group = editgroup,
        buffer = args.buf,
        callback = function(args)
          if M.buffers[args.buf].sync_block_reason == "term_leave" then
            return
          end
          refresh_editable_state(args.buf, vim.api.nvim_win_get_cursor(0))
        end,
      })
    end,
  })
end
return M
