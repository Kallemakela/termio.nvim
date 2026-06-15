local M = {}

---@param text string
---@return string
local function unescape_payload(text)
  return text:gsub("\\x3b", ";"):gsub("\\\\", "\\")
end

---@param sequence string
---@return { command: string, cursor: integer }?
function M.parse_buffer_marker(sequence)
  local cursor, command = sequence:match("^\27]633;T;(%d+);(.*)$")
  if not cursor then
    return nil
  end
  return {
    command = unescape_payload(command),
    cursor = tonumber(cursor),
  }
end

---@param shell_state { command: string, cursor: integer? }
---@param sequence string
---@return boolean
function M.update_shell_state(shell_state, sequence)
  local marker = M.parse_buffer_marker(sequence)
  if not marker then
    return false
  end
  shell_state.command = marker.command
  shell_state.cursor = marker.cursor
  return true
end

return M
