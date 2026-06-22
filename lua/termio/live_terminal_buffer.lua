local helpers = require("termio.util.helpers")

local M = {}

---Return OSC133 prompt range for a live terminal buffer.
---@param buffers table<integer, table>
---@param buf integer
---@return integer[], integer[]
function M.prompt_range(buffers, buf)
  local state = helpers.ensure_buffer_state(buffers, buf)
  if not state.prompt_start_cursor then
    error("termio: missing OSC133 prompt start cursor")
  end
  if not state.prompt_end_cursor then
    error("termio: missing OSC133 prompt end cursor")
  end
  return state.prompt_start_cursor, state.prompt_end_cursor
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

---Return the command-relative cursor for a live terminal window.
---@param win integer
---@param buf integer
---@param start_cursor integer[]
---@return integer[]
function M.command_cursor(win, buf, start_cursor)
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
      return { 1, command_col + math.min(line_col, #line) }
    end
    command_col = command_col + #line
  end
  return { 1, command_col }
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
