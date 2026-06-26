local config = require("termio.config")
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
  live_terminal_buffer.update_prompt_cursors_from_patterns(buffers, buf, win)
  local _, prompt_end_cursor = live_terminal_buffer.prompt_range(buffers, buf, win)
  local command = live_terminal_buffer.command_text(buf, prompt_end_cursor, true)
  local state = helpers.ensure_buffer_state(buffers, buf)
  win = win or visible_window(buf)
  local cursor = win
      and live_terminal_buffer.cursor_index_from_start_cursor(win, buf, prompt_end_cursor)
    or nil
  command = helpers.strip_patterns(command, config.options.read_strip_patterns)
  state.shell_state.command = command
  state.shell_state.cursor = cursor
  return vim.deepcopy(state.shell_state)
end

---Write command text through the terminal channel with nvim_chan_send().
---@param buf integer
---@param command string
---@param cursor integer
function M.write_command(buf, command, cursor)
  local state = helpers.ensure_buffer_state(buffers, buf)
  local win = visible_window(buf)
  local can_signal_shell = live_terminal_buffer.can_send_shell_integration_signal(buffers, buf, win)
  helpers.send_keys("<C-e><C-u>", buf)
  helpers.send_bytes("\27[200~" .. command .. "\27[201~", buf)
  move_shell_cursor(buf, cursor, command)
  if can_signal_shell then
    shell_integration.redraw_after_pty_write(buf)
  end
  state.shell_state.command = command
  state.shell_state.cursor = cursor
end

function M.clear_completion_suggestions() end

return M
