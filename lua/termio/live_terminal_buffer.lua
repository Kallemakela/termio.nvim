local helpers = require("termio.util.helpers")
local config = require("termio.config")

local M = {}

local function configured_prompt_patterns()
  return (config.options or config.defaults).prompt_patterns or {}
end

local function prompt_pattern_scan_start_row(buf, win)
  if win and vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
    return vim.api.nvim_win_get_cursor(win)[1]
  end
  return vim.api.nvim_buf_line_count(buf)
end

local function match_prompt(line)
  for _, pattern in ipairs(configured_prompt_patterns()) do
    if type(pattern) ~= "string" then
      error("termio: prompt_patterns entries must be strings")
    end
    local ok, regex = pcall(vim.regex, pattern)
    if not ok then
      error("termio: invalid prompt_patterns entry: " .. tostring(pattern))
    end
    local start_col, end_col = regex:match_str(line)
    if start_col then
      return start_col, end_col
    end
  end
end

---Update prompt start/end cursors from configured prompt regexes.
---@param buffers table<integer, table>
---@param buf? integer
---@param win? integer
---@return integer[]?, integer[]?
function M.update_prompt_cursors_from_patterns(buffers, buf, win)
  if #configured_prompt_patterns() == 0 then
    return nil, nil
  end
  local state = helpers.ensure_buffer_state(buffers, buf)
  for row = prompt_pattern_scan_start_row(buf, win), 1, -1 do
    local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ""
    local start_col, end_col = match_prompt(line)
    if start_col then
      state.prompt_start_cursor = { row, start_col }
      state.prompt_end_cursor = { row, end_col }
      state.active_prompt_cursor = state.prompt_end_cursor
      state.active_prompt_source = "regex"
      state.active_prompt_process = nil
      state.shell_phase = "input"
      return state.prompt_start_cursor, state.prompt_end_cursor
    end
  end
  return nil, nil
end

---Return cached or regex-detected prompt range, if available.
---@param buffers table<integer, table>
---@param buf integer
---@param win? integer
---@return integer[]?, integer[]?
function M.get_prompt_range(buffers, buf, win)
  M.update_prompt_cursors_from_patterns(buffers, buf, win)
  local state = helpers.ensure_buffer_state(buffers, buf)
  return state.prompt_start_cursor, state.prompt_end_cursor
end

---Return whether shell integration signals are safe for the active prompt.
---@param buffers table<integer, table>
---@param buf integer
---@param win? integer
---@return boolean
function M.can_send_shell_integration_signal(buffers, buf, win)
  M.update_prompt_cursors_from_patterns(buffers, buf, win)
  return helpers.ensure_buffer_state(buffers, buf).active_prompt_source ~= "regex"
end

---Return prompt range for a live terminal buffer.
---@param buffers table<integer, table>
---@param buf integer
---@param win? integer
---@return integer[], integer[]
function M.prompt_range(buffers, buf, win)
  local state = helpers.ensure_buffer_state(buffers, buf)
  if not state.prompt_start_cursor then
    error("termio: missing prompt start cursor")
  end
  if not state.prompt_end_cursor then
    error("termio: missing prompt end cursor")
  end
  return state.prompt_start_cursor, state.prompt_end_cursor
end

---Return the cursor where command text starts after the prompt.
---@param buffers table<integer, table>
---@param buf integer
---@param win? integer
---@return integer[] cursor 1-based row, 0-based column
function M.command_start_cursor(buffers, buf, win)
  local target = helpers.current_buf(buf)
  helpers.assert_terminal(target)
  M.update_prompt_cursors_from_patterns(buffers, target, win)
  local _, prompt_end_cursor = M.prompt_range(buffers, target, win)
  return prompt_end_cursor
end

---Read command rows from a live terminal buffer after start_cursor.
---@param buf integer
---@param start_cursor integer[]
---@param stop_at_blank? boolean
---@return string[]
function M.command_rows(buf, start_cursor, stop_at_blank)
  local row, start_col = unpack(start_cursor)
  local rows = {}
  for index = row, vim.api.nvim_buf_line_count(buf) do
    local line = vim.api.nvim_buf_get_lines(buf, index - 1, index, false)[1] or ""
    if stop_at_blank and line == "" then
      break
    end
    if index == row then
      line = line:sub(start_col + 1)
    end
    rows[#rows + 1] = line
  end
  return rows
end

---Read command text from a live terminal buffer after start_cursor.
---@param buf integer
---@param start_cursor integer[]
---@param stop_at_blank? boolean
---@return string
function M.command_text(buf, start_cursor, stop_at_blank)
  return table.concat(M.command_rows(buf, start_cursor, stop_at_blank), "")
end

---Return the cursor byte index inside command text for a live terminal window.
---@param win integer
---@param buf integer
---@param start_cursor integer[]
---@return integer
function M.cursor_index_from_start_cursor(win, buf, start_cursor)
  local row, start_col = unpack(start_cursor)
  local cursor = vim.api.nvim_win_get_cursor(win)
  local command_col = 0
  for index = row, cursor[1] do
    local line = vim.api.nvim_buf_get_lines(buf, index - 1, index, false)[1] or ""
    if index == row then
      line = line:sub(start_col + 1)
    end
    if index == cursor[1] then
      local line_col = index == row and math.max(cursor[2] - start_col, 0) or cursor[2]
      return command_col + math.min(line_col, #line)
    end
    command_col = command_col + #line
  end
  return command_col
end

---Return current cursor byte index inside command text.
---@param buffers table<integer, table>
---@param win integer
---@param buf? integer
---@return integer
function M.cursor_index_in_command(buffers, win, buf)
  local target = helpers.current_buf(buf)
  helpers.assert_terminal(target)
  return M.cursor_index_from_start_cursor(win, target, M.command_start_cursor(buffers, target, win))
end

---Convert a command-text byte offset back to a live terminal buffer cursor.
---Terminal buffers may contain blank/padded cells after the prompt line. This
---walks forward by command bytes, so command zones end at command text, not at
---the terminal buffer edge.
---@param buf integer
---@param start_cursor integer[]
---@param offset integer
---@return integer[]
function M.location_from_offset(buf, start_cursor, offset)
  local row, col = unpack(start_cursor)
  col = col + offset
  while row < vim.api.nvim_buf_line_count(buf) do
    local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ""
    if col <= #line then
      return { row, col }
    end
    col = col - #line
    row = row + 1
  end
  return { row, col }
end

return M
