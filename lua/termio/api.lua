local M = { buffers = {} }
local config = require("termio.config")
local chan_send_api = require("termio.chan_send_api")
local helpers = require("termio.util.helpers")
local shell_integration = require("termio.shell_integration")
local live_terminal_buffer = require("termio.live_terminal_buffer")

shell_integration.use_buffers(M.buffers)
chan_send_api.use_buffers(M.buffers)

local function current_api(api_type)
  api_type = api_type or config.options.api.type
  if api_type == "shell" then
    return shell_integration
  end
  if api_type == "chan_send" then
    return chan_send_api
  end
  error("termio: config.api.type must be 'shell' or 'chan_send'")
end

---Query the current shell command buffer.
---@param buf? integer
---@param timeout_ms? integer
---@param api_type? "shell"|"chan_send"
---@return string
function M.read_command(buf, timeout_ms, api_type)
  return M.read_state(buf, nil, timeout_ms, api_type).command
end

---Query the current shell command and cursor state.
---@param buf? integer
---@param win? integer
---@param timeout_ms? integer
---@param api_type? "shell"|"chan_send"
---@return { command: string, cursor: integer? }
function M.read_state(buf, win, timeout_ms, api_type)
  local target = helpers.current_buf(buf)
  helpers.assert_terminal(target)
  return current_api(api_type).read_state(target, win, timeout_ms)
end

---Hide shell completion suggestions shown below the prompt.
---@param buf? integer
---@param api_type? "shell"|"chan_send"
function M.clear_completion_suggestions(buf, api_type)
  local target = helpers.current_buf(buf)
  helpers.assert_terminal(target)
  current_api(api_type).clear_completion_suggestions(target)
end

---Write shell command buffer directly.
---@param command string
---@param buf? integer
---@param cursor? integer
---@param api_type? "shell"|"chan_send"
function M.write_command(command, buf, cursor, api_type)
  local target = helpers.current_buf(buf)
  helpers.assert_terminal(target)
  if type(command) ~= "string" then
    error("termio: command must be a string")
  end
  local shell_command = helpers.strip_patterns(command, config.options.write_strip_patterns)
  local shell_cursor = cursor and math.max(0, math.min(cursor, #shell_command)) or #shell_command
  current_api(api_type).write_command(target, shell_command, shell_cursor)
end

---@param win integer
---@param buf integer
---@return integer[]
function M.command_cursor(win, buf)
  local _, prompt_end_cursor = live_terminal_buffer.prompt_range(M.buffers, buf)
  return live_terminal_buffer.command_cursor(win, buf, prompt_end_cursor)
end

return M
