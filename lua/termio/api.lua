local M = { buffers = {} }
local config = require("termio.config")
local chan_send_api = require("termio.chan_send_api")
local helpers = require("termio.util.helpers")
local shell_integration = require("termio.shell_integration")
local live_terminal_buffer = require("termio.live_terminal_buffer")

shell_integration.use_buffers(M.buffers)
chan_send_api.use_buffers(M.buffers)

local function current_io_api(io_backend)
  io_backend = io_backend or config.options.io_backend
  if io_backend == "fifo" then
    return shell_integration
  end
  if io_backend == "auto" or io_backend == "pty" then
    return chan_send_api
  end
  error("termio: config.io_backend must be 'auto', 'pty', or 'fifo'")
end

---Query the current shell command buffer.
---@param buf? integer
---@param timeout_ms? integer
---@param io_backend? "auto"|"pty"|"fifo"
---@return string
function M.read_command(buf, timeout_ms, io_backend)
  return M.read_state(buf, nil, timeout_ms, io_backend).command
end

---Query the current shell command and cursor state.
---@param buf? integer
---@param win? integer
---@param timeout_ms? integer
---@param io_backend? "auto"|"pty"|"fifo"
---@return { command: string, cursor: integer? }
function M.read_state(buf, win, timeout_ms, io_backend)
  local target = helpers.current_buf(buf)
  helpers.assert_terminal(target)
  return current_io_api(io_backend).read_state(target, win, timeout_ms)
end

---Hide shell completion suggestions shown below the prompt.
---@param buf? integer
---@param io_backend? "auto"|"pty"|"fifo"
function M.clear_completion_suggestions(buf, io_backend)
  local target = helpers.current_buf(buf)
  helpers.assert_terminal(target)
  current_io_api(io_backend).clear_completion_suggestions(target)
end

---Write shell command buffer directly.
---@param command string
---@param buf? integer
---@param cursor? integer
---@param io_backend? "auto"|"pty"|"fifo"
function M.write_command(command, buf, cursor, io_backend)
  local target = helpers.current_buf(buf)
  helpers.assert_terminal(target)
  if type(command) ~= "string" then
    error("termio: command must be a string")
  end
  local shell_command = helpers.strip_patterns(command, config.options.write_strip_patterns)
  local shell_cursor = cursor and math.max(0, math.min(cursor, #shell_command)) or #shell_command
  current_io_api(io_backend).write_command(target, shell_command, shell_cursor)
end

---@param win integer
---@param buf integer
---@return integer[]
function M.command_cursor(win, buf)
  local _, prompt_end_cursor = live_terminal_buffer.prompt_range(M.buffers, buf)
  return live_terminal_buffer.command_cursor(win, buf, prompt_end_cursor)
end

return M
