local M = { buffers = {} }
local config = require("termio.config")
local helpers = require("termio.util.helpers")
local terminal_buffer = require("termio.terminal_buffer")
local shell_integration = require("termio.shell_integration")

shell_integration.use_buffers(M.buffers)

---@param buf integer
---@param cursor integer
---@param command string
local function move_shell_cursor(buf, cursor, command)
  local delta = #command - cursor
  if delta > 0 then
    helpers.send_bytes(("\27[D"):rep(delta), buf)
  end
end

---@param buf integer
---@param prompt_end_cursor integer[]
---@return string
local function command_text_without_completion_rows(buf, prompt_end_cursor)
  local rows = terminal_buffer.command_rows(buf, prompt_end_cursor, true)
  if #rows == 1 then
    return rows[1]
  end
  -- Extra rows after the prompt are usually transient completion UI. Ask the
  -- shell to clear them, then reread the terminal buffer as command text.
  M.clear_completion_suggestions(buf)
  return terminal_buffer.command_text(buf, prompt_end_cursor, true)
end

---Query the current shell command buffer.
---@param buf? integer
---@param timeout_ms? integer
---@return string
function M.read_command(buf, timeout_ms)
  return M.read_state(buf, nil, timeout_ms).command
end

---Query the current shell command and cursor state.
---@param buf? integer
---@param win? integer
---@param timeout_ms? integer
---@return { command: string, cursor: integer? }
function M.read_state(buf, win, timeout_ms)
  local target = helpers.current_buf(buf)
  helpers.assert_terminal(target)
  terminal_buffer.update_prompt_cursors_from_patterns(M.buffers, target, win)
  local _, prompt_end_cursor = terminal_buffer.prompt_range(M.buffers, target, win)
  local command = command_text_without_completion_rows(target, prompt_end_cursor)
  local state = helpers.ensure_buffer_state(M.buffers, target)
  win = win or helpers.visible_window(target)
  local cursor = win
      and terminal_buffer.cursor_index_from_start_cursor(win, target, prompt_end_cursor)
    or nil
  command = helpers.strip_patterns(command, config.options.read_strip_patterns)
  state.shell_state.command = command
  state.shell_state.cursor = cursor
  return vim.deepcopy(state.shell_state)
end

---Hide shell completion suggestions shown below the prompt.
---@param buf? integer
function M.clear_completion_suggestions(buf)
  local target = helpers.current_buf(buf)
  helpers.assert_terminal(target)
  local state = helpers.ensure_buffer_state(M.buffers, target)
  if state.shell_integration then
    shell_integration.clear_completion_suggestions(target)
  end
end

---Write shell command buffer directly.
---@param command string
---@param buf? integer
---@param cursor? integer
function M.write_command(command, buf, cursor)
  local target = helpers.current_buf(buf)
  helpers.assert_terminal(target)
  if type(command) ~= "string" then
    error("termio: command must be a string")
  end
  local shell_command = helpers.strip_patterns(command, config.options.write_strip_patterns)
  local shell_cursor = cursor and math.max(0, math.min(cursor, #shell_command)) or #shell_command
  local state = helpers.ensure_buffer_state(M.buffers, target)
  local win = helpers.visible_window(target)
  local can_signal_shell = terminal_buffer.can_send_shell_integration_signal(M.buffers, target, win)
  helpers.send_keys("<C-e><C-u>", target)
  helpers.send_bytes("\27[200~" .. shell_command .. "\27[201~", target)
  move_shell_cursor(target, shell_cursor, shell_command)
  if can_signal_shell then
    shell_integration.redraw_after_pty_write(target)
  end
  state.shell_state.command = shell_command
  state.shell_state.cursor = shell_cursor
end

return M
