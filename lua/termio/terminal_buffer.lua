local helpers = require("termio.util.helpers")
local config = require("termio.config")

local M = {}

local function configured_prompt_patterns()
  return (config.options or config.defaults).prompt_patterns or {}
end

local function prompt_pattern_scan_start_row(state)
  if state.prompt_start_cursor then
    return state.prompt_start_cursor[1] + 1
  end
  return 1
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
---@return integer[]?, integer[]?
function M.update_prompt_cursors_from_patterns(buffers, buf)
  if #configured_prompt_patterns() == 0 then
    return nil, nil
  end
  local state = helpers.ensure_buffer_state(buffers, buf)
  local top_row = prompt_pattern_scan_start_row(state)
  local bottom_row = vim.api.nvim_buf_line_count(buf)
  for row = bottom_row, top_row, -1 do
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

---Return prompt range for a terminal buffer.
---@param buffers table<integer, table>
---@param buf integer
---@return integer[]?, integer[]?
function M.prompt_range(buffers, buf)
  local state = helpers.ensure_buffer_state(buffers, buf)
  return state.prompt_start_cursor, state.prompt_end_cursor
end

---Read command rows from a terminal buffer after start_cursor.
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

---Read command text from a terminal buffer after start_cursor.
---@param buf integer
---@param start_cursor integer[]
---@param stop_at_blank? boolean
---@return string
function M.command_text(buf, start_cursor, stop_at_blank)
  return table.concat(M.command_rows(buf, start_cursor, stop_at_blank), "")
end

---Unreliable, used only to check if there might be completions currently
---@param rows string[]
---@param position? integer[] Position relative to rows. Rows before it are always command rows.
---@return string[], string[]
function M.split_completion_rows(rows, position)
  -- Heuristics for completion UI detection:
  -- 1. [USED] Current command row does not end in a newline, but the following line has text.
  -- 2. [NOT USED] Following lines contain evenly spaced words.
  local first_candidate = position and position[1] or 1
  for command_end_row = first_candidate, #rows - 1 do
    local next_row = rows[command_end_row + 1]
    local next_row_has_text = next_row and next_row:find("%S") ~= nil
    if not next_row_has_text then
      return rows, {}
    end
    local current_row_ends_with_newline = rows[command_end_row]:sub(-1) == "\n"
    if not current_row_ends_with_newline then
      return vim.list_slice(rows, 1, command_end_row), vim.list_slice(rows, command_end_row + 1)
    end
  end
  return rows, {}
end

---@param rows string[]
---@return boolean
function M.maybe_has_completions(rows)
  -- Unreliable for wrapped commands; kept only as a best-effort helper.
  local _, completion_rows = M.split_completion_rows(rows)
  return #completion_rows > 0
end

---@param buffers table<integer, table>
---@param buf integer
---@param win integer?
---@param prompt_end_cursor integer[]
---@return { command: string, cursor: integer? }
function M.read_state(buffers, buf, win, prompt_end_cursor)
  local rows = M.command_rows(buf, prompt_end_cursor, true)
  local state = helpers.ensure_buffer_state(buffers, buf)
  local command = table.concat(rows, "")
  local cursor = win and vim.api.nvim_win_get_cursor(win) or nil
  cursor = cursor and M.cursor_index_from_start_cursor(cursor, buf, prompt_end_cursor) or nil
  state.shell_state.command = helpers.strip_patterns(command, config.options.read_strip_patterns)
  state.shell_state.cursor = cursor
  return vim.deepcopy(state.shell_state)
end

---Return the cursor byte index inside command text.
---@param cursor integer[]
---@param buf integer
---@param start_cursor integer[]
---@return integer
function M.cursor_index_from_start_cursor(cursor, buf, start_cursor)
  local row, start_col = unpack(start_cursor)
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

---Convert a command-text byte offset back to a terminal buffer cursor.
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
