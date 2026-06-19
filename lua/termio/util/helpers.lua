local M = {}
local config = require("termio.config")
local state = require("termio.state")

---@param keys string
---@return string
function M.term_codes(keys)
  return vim.api.nvim_replace_termcodes(keys, true, false, true)
end

---@param buf integer
---@return integer
local function assert_terminal_channel(buf)
  local chan = vim.bo[buf].channel
  if not chan or chan == 0 then
    error("termio: missing terminal channel")
  end
  return chan
end

---@param bytes string
---@param buf? integer
function M.send_bytes(bytes, buf)
  local target = M.current_buf(buf)
  M.assert_terminal(target)
  vim.api.nvim_chan_send(assert_terminal_channel(target), bytes)
end

---@param keys string
---@param buf? integer
function M.send_keys(keys, buf)
  M.send_bytes(M.term_codes(keys), buf)
end

---@param command string
---@param patterns string[]
---@param replacement? string
---@return string
function M.strip_patterns(command, patterns, replacement)
  replacement = replacement or ""
  for _, pattern in ipairs(patterns) do
    command = command:gsub(pattern, replacement)
  end
  return command
end

---@param command string
---@param patterns string[]
---@return string
function M.normalize_command(command, patterns)
  return M.strip_patterns(command, patterns, "\n"):gsub("\n$", "")
end

---@param buf? integer
---@return integer
function M.current_buf(buf)
  return buf or vim.api.nvim_get_current_buf()
end

---@param buf integer
---@return boolean
function M.is_enabled_terminal(buf)
  if vim.bo[buf].buftype ~= "terminal" then
    return false
  end
  local pattern = config.options.editor.terminal_name_pattern
  if not pattern then
    return true
  end
  local name = vim.api.nvim_buf_get_name(buf)
  local ok, regex = pcall(vim.regex, pattern)
  if not ok then
    error("termio: invalid editor.terminal_name_pattern: " .. tostring(pattern))
  end
  return regex:match_str(name) ~= nil
end

---@param buf integer
---@return boolean
function M.is_editor_disabled(buf)
  if not state.is_enabled() then
    return true
  end
  local is_disabled = config.options.editor.is_disabled
  if type(is_disabled) ~= "function" then
    error("termio: config.editor.is_disabled must be a function")
  end
  return is_disabled(buf) == true
end

---@param buffers table<integer, table>
---@param buf integer
---@return table
function M.ensure_buffer_state(buffers, buf)
  buffers[buf] = buffers[buf]
    or {
      prompt_start_cursor = nil,
      prompt_end_cursor = nil,
      shell_phase = nil,
      shell_fifo_path = nil,
      shell_state = { command = "", cursor = nil },
    }
  return buffers[buf]
end

---@param buf integer
function M.assert_terminal(buf)
  if vim.bo[buf].buftype ~= "terminal" then
    error("termio: current buffer is not a terminal")
  end
end

return M
