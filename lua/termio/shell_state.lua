local helpers = require("termio.util.helpers")
local shell_integration = require("termio.shell_integration")

local M = {}

---@param value string
---@return string
local function unescape_shell_payload(value)
  value = value:gsub("\7$", ""):gsub("\27\\$", "")
  return value:gsub("\\x3b", ";"):gsub("\\\\", "\\")
end

---@param sequence string
---@return string?
local function parse_title(sequence)
  return sequence:match("^\27%][012];(.-)\7") or sequence:match("^\27%][012];(.-)\27\\")
end

---@param buffers table<integer, table>
---@param args vim.api.keyset.create_autocmd.callback_args
---@return boolean handled
function M.handle_term_request(buffers, args)
  local state = helpers.ensure_buffer_state(buffers, args.buf)
  local sequence = args.data.sequence
  local title = parse_title(sequence)
  if title then
    state.terminal_title = title
    return true
  end
  if sequence:match("^\27]133;A") then
    state.prompt_start_cursor = args.data.cursor
    state.shell_phase = "prompt"
    return true
  end
  if sequence:match("^\27]133;B") then
    state.prompt_end_cursor = args.data.cursor
    state.active_prompt_cursor = args.data.cursor
    state.active_prompt_source = "osc133"
    state.active_prompt_process = nil
    state.shell_phase = "input"
    return true
  end
  if sequence:match("^\27]133;C") then
    state.active_prompt_cursor = nil
    state.active_prompt_source = nil
    state.active_prompt_process = nil
    state.shell_phase = "output"
    return true
  end
  if sequence:match("^\27]133;D") then
    state.shell_phase = "finished"
    state.shell_exit_status = tonumber(sequence:match("^\27]133;D;?(%d*)"))
    state.shell_state.command = ""
    state.shell_state.cursor = nil
    return true
  end
  local fifo_path, shell = shell_integration.parse_fifo_path(sequence)
  if fifo_path then
    state.shell_fifo_path = fifo_path
    state.shell_kind = shell.kind
    state.shell_integration = shell
    return true
  end
  local cursor, command = sequence:match("^\27]633;Q;(%d+);(.*)")
  if cursor then
    state.shell_state.command = unescape_shell_payload(command)
    state.shell_state.cursor = tonumber(cursor)
    state.shell_phase = "input"
    state.shell_query_pending = false
    return true
  end
  if sequence:match("^\27]633;W") then
    state.shell_write_pending = false
    return true
  end
  return false
end

return M
