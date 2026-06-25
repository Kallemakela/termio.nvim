local helpers = require("termio.util.helpers")
local live_terminal_buffer = require("termio.live_terminal_buffer")
local shell_integration = require("termio.shell_integration")

local M = {}
local buffers = {}

---@param buffer_state table<integer, table>
function M.use_buffers(buffer_state)
  buffers = buffer_state
end

---@param buf integer
---@param cursor integer
---@param command string
local function move_shell_cursor(buf, cursor, command)
  local delta = #command - cursor
  if delta > 0 then
    helpers.send_bytes(("\27[D"):rep(delta), buf)
  end
end

---@param buf integer
---@return integer?
local function visible_window(buf)
  local win = vim.fn.bufwinid(buf)
  return win ~= -1 and win or nil
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
  local _, prompt_end_cursor = live_terminal_buffer.prompt_range(buffers, buf)
  local command = live_terminal_buffer.command_text(buf, prompt_end_cursor, true)
  local state = helpers.ensure_buffer_state(buffers, buf)
  win = win or visible_window(buf)
  state.shell_state.command = command
  state.shell_state.cursor = win
      and live_terminal_buffer.command_cursor(win, buf, prompt_end_cursor)[2]
    or nil
  return vim.deepcopy(state.shell_state)
end

---Write command text through the terminal channel with nvim_chan_send().
---@param buf integer
---@param command string
---@param cursor integer
function M.write_command(buf, command, cursor)
  helpers.send_keys("<C-e><C-u>", buf)
  helpers.send_bytes("\27[200~" .. command .. "\27[201~", buf)
  move_shell_cursor(buf, cursor, command)
  local state = helpers.ensure_buffer_state(buffers, buf)
  shell_integration.redraw_after_pty_write(buf)
  state.shell_state.command = command
  state.shell_state.cursor = cursor
end

function M.clear_completion_suggestions() end

return M
