local M = {}
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
---@return string
local function send_shell_control(buf, lines)
  local file = shell_control_file(buf)
  vim.fn.writefile(lines, file, "b")
  signal_shell(buf, vim.uv.constants.SIGUSR2)
  return file
end

M.buffers = {}

---Return OSC133 prompt range for the current editable command.
---@param buf integer
---@return integer[], integer[]
local function assert_osc133_prompt_range(buf)
  local state = helpers.ensure_buffer_state(M.buffers, buf)
  local prompt_start_cursor = state.prompt_start_cursor
  local prompt_end_cursor = state.prompt_end_cursor
  if not prompt_start_cursor then
    error("termline: missing OSC133 prompt start cursor")
  end
  if not prompt_end_cursor then
    error("termline: missing OSC133 prompt end cursor")
  end
  return prompt_start_cursor, prompt_end_cursor
end

---Return OSC133 prompt end position for the current editable command.
---@param buf integer
---@return integer, integer
local function assert_osc133_prompt_end_position(buf)
  local _, prompt_end_cursor = assert_osc133_prompt_range(buf)
  return unpack(prompt_end_cursor)
end

---@param command_rows string[]
---@param prompt_end_col integer
---@return string[]
local function remove_prompt(command_rows, prompt_end_col)
  command_rows[1] = command_rows[1]:sub(prompt_end_col + 1)
  return command_rows
end

---@param buf integer
---@return string[]
local function read_command_rows(buf)
  local row, prompt_end_col = assert_osc133_prompt_end_position(buf)
  local line_count = vim.api.nvim_buf_line_count(buf)
  local command_rows = {}
  for index = row, line_count do
    local line = vim.api.nvim_buf_get_lines(buf, index - 1, index, false)[1] or ""
    if line == "" then
      break
    end
    command_rows[#command_rows + 1] = line
  end
  if #command_rows == 0 then
    return command_rows
  end
  return remove_prompt(command_rows, prompt_end_col)
end

---@param buf integer
---@return string
local function read_prompt_from_raw(buf)
  local prompt_start_cursor, prompt_end_cursor = assert_osc133_prompt_range(buf)
  local row, prompt_start_col = unpack(prompt_start_cursor)
  local _, prompt_end_col = unpack(prompt_end_cursor)
  local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ""
  return line:sub(prompt_start_col + 1, prompt_end_col)
end

---Refresh the cached prompt for a terminal buffer.
---@param buf integer
---@return string
function M.update_cached_prompt(buf)
  helpers.assert_terminal(buf)
  local state = helpers.ensure_buffer_state(M.buffers, buf)
  state.prompt = read_prompt_from_raw(buf)
  return state.prompt
end

---Check if raw terminal command content matches force-Ctrl-c patterns.
---@param buf integer
---@return boolean true when line clear should fall back to Ctrl-C, false when clear_current_line should be enough
local function needs_ctrl_c_clear(buf)
  if #config.options.ctrl_c_on == 0 then
    return false
  end
  -- Match against the raw terminal layout so patterns can detect shell states
  -- such as PS2 continuation prompts between physical rows.
  local command_text = table.concat(read_command_rows(buf), "\n")
  for _, pattern in ipairs(config.options.ctrl_c_on) do
    if command_text:match(pattern) then
      return true
    end
  end
  return false
end

---@param buf integer
---@return boolean true when OSC133 moved to a new prompt after Ctrl-C
local function send_ctrl_c_and_wait(buf)
  local bufinfo = helpers.ensure_buffer_state(M.buffers, buf)
  local old_cursor = bufinfo.prompt_end_cursor
  helpers.send_keys("<C-c>", buf)
  -- true stops waiting once OSC133 points at a new prompt after Ctrl-C.
  -- false keeps waiting for that prompt refresh.
  return vim.wait(config.options.prompt_refresh_wait_ms, function()
    return bufinfo.prompt_end_cursor ~= old_cursor
  end)
end

---@param buf integer
---@param opts? { skip_verify?: boolean }
---@return boolean true when the command is empty after clear_current_line, false when the Ctrl-C fallback should run
local function clear_line_and_wait(buf, opts)
  helpers.send_keys(config.options.clear_current_line, buf)
  if opts and opts.skip_verify then
    return true
  end
  for _ = 1, config.options.clear_current_line_check_count do
    if M.read_command(buf) == "" then
      return true
    end
    vim.wait(config.options.clear_current_line_check_ms, function()
      return false
    end)
  end
  return M.read_command(buf) == ""
end

---Read the current visible command from terminal buffer text only.
---@param buf integer
---@return string
function M.read_command_visible(buf)
  local command_rows = read_command_rows(buf)
  if #command_rows == 0 then
    return ""
  end
  return helpers.normalize_command(
    table.concat(command_rows, ""),
    config.options.read_strip_patterns
  )
end

---Return true when shell-side command query is worth trying.
---@param buf? integer
---@return boolean
function M.should_read_command_shell(buf)
  local target = helpers.current_buf(buf)
  helpers.assert_terminal(target)
  return true
end

---Read the current command.
---@param buf? integer
---@return string
function M.read_command(buf)
  local target = helpers.current_buf(buf)
  helpers.assert_terminal(target)
  if M.should_read_command_shell(target) then
    local ok, command = pcall(M.read_command_shell, target)
    if ok then
      return command
    end
  end
  return M.read_command_visible(target)
end

---Query the shell-side editable command through shell integration.
---@param buf? integer
---@param timeout_ms? integer
---@return string
function M.read_command_shell(buf, timeout_ms)
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

---Clear shell completion suggestions displayed below the prompt.
---@param buf? integer
function M.clear_completion_suggestions(buf)
  local target = helpers.current_buf(buf)
  helpers.assert_terminal(target)
  local file = send_shell_control(target, { "clear-completions" })
  vim.wait(100, function()
    return vim.fn.filereadable(file) == 0
  end, 5)
end

---Write command text. If omitted, reuse the last cached read value.
---@param command? string
---@param buf? integer
function M.write_command(command, buf)
  local target = helpers.current_buf(buf)
  helpers.assert_terminal(target)
  local bufinfo = helpers.ensure_buffer_state(M.buffers, target)
  local shell_state = bufinfo.shell_state
  if command ~= nil then
    if type(command) ~= "string" then
      error("termline: command must be a string")
    end
    shell_state.command = helpers.strip_patterns(command, config.options.write_strip_patterns)
  end
  if M.should_read_command_shell(target) then
    local should_submit = shell_state.command:sub(-1) == "\r"
    local shell_command = should_submit and shell_state.command:sub(1, -2) or shell_state.command
    M.write_command_shell(shell_command, nil, target)
    if should_submit then
      helpers.send_keys("<CR>", target)
    end
    return
  end
  helpers.send_keys(shell_state.command, target)
end

---Write command text directly to zsh ZLE BUFFER.
---@param command string
---@param cursor? integer
---@param buf? integer
function M.write_command_shell(command, cursor, buf)
  local target = helpers.current_buf(buf)
  helpers.assert_terminal(target)
  if type(command) ~= "string" then
    error("termline: command must be a string")
  end
  local cursor_text = cursor and tostring(cursor) or ""
  send_shell_control(target, { "write", cursor_text, command })
  local applied = vim.wait(500, function()
    local ok, current = pcall(M.read_command_shell, target, 100)
    return ok and current == command
  end, 10)
  if not applied then
    error("termline: shell command write timed out")
  end
end

---Clear the current command.
---@param buf? integer
---@param opts? { skip_verify?: boolean }
function M.clear_command(buf, opts)
  local target = helpers.current_buf(buf)
  helpers.assert_terminal(target)

  -- Ctrl-C exits multiline / continuation states
  if needs_ctrl_c_clear(target) then
    send_ctrl_c_and_wait(target)
    return
  end

  if not clear_line_and_wait(target, opts) then
    send_ctrl_c_and_wait(target)
    return
  end
end

function M.command_cursor(win, buf)
  local row, prompt_end_col = assert_osc133_prompt_end_position(buf)
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

function M.command_screenpos(win, buf)
  local row, prompt_end_col = assert_osc133_prompt_end_position(buf)
  local pos = vim.fn.screenpos(win, row, prompt_end_col + 1)
  return { pos.row - 1, pos.col - 1 }
end

return M
