local helpers = require("termio.util.helpers")

local M = {}
local buffers = {}

---@param buffer_state table<integer, table>
function M.use_buffers(buffer_state)
  buffers = buffer_state
end

---@param buf integer
---@return integer[], integer[]
local function assert_prompt_range(buf)
  local state = helpers.ensure_buffer_state(buffers, buf)
  if not state.prompt_start_cursor then
    error("termio: missing OSC133 prompt start cursor")
  end
  if not state.prompt_end_cursor then
    error("termio: missing OSC133 prompt end cursor")
  end
  return state.prompt_start_cursor, state.prompt_end_cursor
end

---@param buf integer
---@return string[]
local function read_command_rows(buf)
  local _, prompt_end_cursor = assert_prompt_range(buf)
  local row, prompt_end_col = unpack(prompt_end_cursor)
  local command_rows = {}
  for index = row, vim.api.nvim_buf_line_count(buf) do
    local line = vim.api.nvim_buf_get_lines(buf, index - 1, index, false)[1] or ""
    if line == "" then
      break
    end
    if index == row then
      line = line:sub(prompt_end_col + 1)
    end
    command_rows[#command_rows + 1] = line
  end
  return command_rows
end

---@param buf integer
---@param cursor integer
---@param command string
local function move_cursor(buf, cursor, command)
  local delta = #command - cursor
  if delta > 0 then
    helpers.send_bytes(("\27[D"):rep(delta), buf)
  end
end

---@param win integer
---@param buf integer
---@return integer
local function read_visible_cursor(win, buf)
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
      return command_col + math.min(line_col, #line)
    end
    command_col = command_col + #line
  end
  return command_col
end

---Read the visible terminal command using OSC133 prompt markers.
---@param buf integer
---@return string
function M.read_command(buf)
  return M.read_state(buf).command
end

---@param buf integer
---@param win? integer
---@return { command: string, cursor: integer? }
function M.read_state(buf, win)
  local command = table.concat(read_command_rows(buf), "")
  local state = helpers.ensure_buffer_state(buffers, buf)
  state.shell_state.command = command
  state.shell_state.cursor = win and read_visible_cursor(win, buf) or nil
  return vim.deepcopy(state.shell_state)
end

---Write command text through the terminal channel with nvim_chan_send().
---@param buf integer
---@param command string
---@param cursor integer
function M.write_command(buf, command, cursor)
  helpers.send_keys("<C-e><C-u>", buf)
  helpers.send_bytes(command, buf)
  move_cursor(buf, cursor, command)
  local state = helpers.ensure_buffer_state(buffers, buf)
  state.shell_state.command = command
  state.shell_state.cursor = cursor
end

function M.clear_completion_suggestions() end

return M
