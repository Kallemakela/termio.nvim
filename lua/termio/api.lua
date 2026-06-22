local M = { buffers = {} }
local config = require("termio.config")
local chan_send_api = require("termio.chan_send_api")
local helpers = require("termio.util.helpers")
local shell_integration = require("termio.shell_integration.general")

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

---@param buf integer
---@return integer[], integer[]
local function assert_prompt_range(buf)
  local state = helpers.ensure_buffer_state(M.buffers, buf)
  if not state.prompt_start_cursor then
    error("termio: missing OSC133 prompt start cursor")
  end
  if not state.prompt_end_cursor then
    error("termio: missing OSC133 prompt end cursor")
  end
  return state.prompt_start_cursor, state.prompt_end_cursor
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
  local _, prompt_end_cursor = assert_prompt_range(buf)
  local row, prompt_end_col = unpack(prompt_end_cursor)
  local cursor = vim.api.nvim_win_get_cursor(win)
  local command_col = 0
  for index = row, cursor[1] do
    local line = vim.api.nvim_buf_get_lines(buf, index - 1, index, false)[1] or ""
    if index == row then
      line = line:sub(prompt_end_col + 1)
    end
    if index == cursor[1] then
      local line_col = index == row and math.max(cursor[2] - prompt_end_col, 0) or cursor[2]
      command_col = command_col + math.min(line_col, #line)
      break
    end
    command_col = command_col + #line
  end
  return { 1, command_col }
end

return M
