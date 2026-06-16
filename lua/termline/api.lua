local M = { buffers = {} }
local config = require("termline.config")
local helpers = require("termline.util.helpers")

---@param buf integer
---@return integer
local function assert_shell_pid(buf)
  local job_id = vim.b[buf].terminal_job_id
  local pid = job_id and vim.fn.jobpid(job_id)
  if not pid or pid <= 0 then
    error("termline: missing terminal job pid")
  end
  return pid
end

local function signal_shell(buf, signal)
  vim.uv.kill(assert_shell_pid(buf), signal)
end

---@param buf integer
---@return string
local function shell_control_file(buf)
  return (vim.env.TMPDIR or "/tmp") .. "/termline.nvim." .. assert_shell_pid(buf) .. ".control"
end

---@param buf integer
---@param lines string[]
local function send_shell_control(buf, lines)
  local file = shell_control_file(buf)
  vim.fn.writefile(lines, file, "b")
  signal_shell(buf, vim.uv.constants.SIGUSR2)
  return file
end

---@param buf integer
---@return integer[], integer[]
local function assert_prompt_range(buf)
  local state = helpers.ensure_buffer_state(M.buffers, buf)
  if not state.prompt_start_cursor then
    error("termline: missing OSC133 prompt start cursor")
  end
  if not state.prompt_end_cursor then
    error("termline: missing OSC133 prompt end cursor")
  end
  return state.prompt_start_cursor, state.prompt_end_cursor
end

---Query the current zsh BUFFER.
---@param buf? integer
---@param timeout_ms? integer
---@return string
function M.read_command(buf, timeout_ms)
  local target = helpers.current_buf(buf)
  helpers.assert_terminal(target)
  local state = helpers.ensure_buffer_state(M.buffers, target)
  state.shell_query_pending = true
  signal_shell(target, vim.uv.constants.SIGUSR1)
  local received = vim.wait(timeout_ms or 200, function()
    return state.shell_query_pending == false
  end, 5)
  if not received then
    error("termline: shell command query timed out")
  end
  return state.shell_state.command
end

---Hide zsh completion suggestions shown below the prompt.
---@param buf? integer
function M.clear_completion_suggestions(buf)
  local target = helpers.current_buf(buf)
  helpers.assert_terminal(target)
  local file = send_shell_control(target, { "clear-completions" })
  vim.wait(100, function()
    return vim.fn.filereadable(file) == 0
  end, 5)
end

---Write zsh BUFFER directly.
---@param command string
---@param buf? integer
---@param cursor? integer
function M.write_command(command, buf, cursor)
  local target = helpers.current_buf(buf)
  helpers.assert_terminal(target)
  if type(command) ~= "string" then
    error("termline: command must be a string")
  end
  local shell_command = helpers.strip_patterns(command, config.options.write_strip_patterns)
  local shell_cursor = cursor and math.max(0, math.min(cursor, #shell_command)) or #shell_command
  local state = helpers.ensure_buffer_state(M.buffers, target)
  state.shell_write_pending = true
  send_shell_control(target, { "write", tostring(shell_cursor), shell_command })
  local applied = vim.wait(500, function()
    return state.shell_write_pending == false
  end, 5)
  if not applied then
    error("termline: shell command write timed out")
  end
  state.shell_state.command = shell_command
  state.shell_state.cursor = shell_cursor
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
