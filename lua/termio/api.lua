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

local function can_send_shell_integration_signal(buf)
  return helpers.ensure_buffer_state(M.buffers, buf).active_prompt_source ~= "regex"
end

---Update cached prompt range from configured prompt patterns.
---@param buf? integer
function M.update_prompt_range(buf)
  local target = helpers.current_buf(buf)
  helpers.assert_terminal(target)
  terminal_buffer.update_prompt_cursors_from_patterns(M.buffers, target)
end

---Return the cached prompt range, or nil when no prompt has been detected yet.
---@param buf? integer
---@return integer[]? prompt_start_cursor
---@return integer[]? prompt_end_cursor
function M.prompt_range(buf)
  local target = helpers.current_buf(buf)
  helpers.assert_terminal(target)
  return terminal_buffer.prompt_range(M.buffers, target)
end

---Return the cursor where command text starts after the prompt, or nil before prompt detection.
---@param buf? integer
---@return integer[]? cursor 1-based row, 0-based column
function M.command_start_cursor(buf)
  local _, prompt_end_cursor = M.prompt_range(buf)
  return prompt_end_cursor
end

---Return current cursor byte index inside command text, or nil before prompt detection.
---@param win integer
---@param buf? integer
---@return integer?
function M.cursor_index_in_command(win, buf)
  local target = helpers.current_buf(buf)
  local _, prompt_end_cursor = M.prompt_range(target)
  if not prompt_end_cursor then
    return nil
  end
  return terminal_buffer.cursor_index_from_start_cursor(
    vim.api.nvim_win_get_cursor(win),
    target,
    prompt_end_cursor
  )
end

---Query the current shell command buffer.
---@param buf? integer
---@param timeout_ms? integer
---@param backend? "auto"|"buffer" Communication backend. "auto" tries shell integration first; "buffer" reads rendered terminal text.
---@return string
function M.read_command(buf, timeout_ms, backend)
  return M.read_state(buf, nil, timeout_ms, backend).command
end

---Query the current shell command and cursor state.
---@param buf? integer
---@param win? integer
---@param timeout_ms? integer
---@param backend? "auto"|"buffer" Communication backend. "auto" tries shell integration first; "buffer" reads rendered terminal text.
---@return { command: string, cursor: integer? }
function M.read_state(buf, win, timeout_ms, backend)
  local target = helpers.current_buf(buf)
  helpers.assert_terminal(target)
  backend = backend or config.options.backend
  if backend ~= "auto" and backend ~= "buffer" then
    error("termio: backend must be 'auto' or 'buffer'")
  end
  M.update_prompt_range(target)
  local _, prompt_end_cursor = M.prompt_range(target)
  if not prompt_end_cursor then
    error("termio: missing prompt end cursor")
  end
  if backend == "auto" and can_send_shell_integration_signal(target) then
    local shell_state = shell_integration.read_state(target, timeout_ms)
    if shell_state then
      shell_state.command =
        helpers.strip_patterns(shell_state.command, config.options.read_strip_patterns)
      return shell_state
    end
  end
  win = win or helpers.visible_window(target)
  return terminal_buffer.read_state(M.buffers, target, win, prompt_end_cursor)
end

---Hide shell completion suggestions shown below the prompt.
---@param buf? integer
function M.clear_completion_suggestions(buf)
  local target = helpers.current_buf(buf)
  helpers.assert_terminal(target)
  if can_send_shell_integration_signal(target) then
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
  local can_signal_shell = can_send_shell_integration_signal(target)
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
