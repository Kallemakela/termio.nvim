local api = require("termline.api")
local helpers = require("termline.util.helpers")
local log = require("termline.util.log")

local M = {}

---@param value string
---@return string
local function unescape_shell_payload(value)
  return value:gsub("\\x3b", ";"):gsub("\\\\", "\\")
end

---@param shell_state { command: string, cursor: integer? }
local function clear_shell_state(shell_state)
  shell_state.command = ""
  shell_state.cursor = nil
end

local function update_prompt(args, state)
  state.prompt_end_cursor = args.data.cursor
  clear_shell_state(state.shell_state)
end

---@param sequence string
---@param state table
local function update_shell_query(sequence, state)
  local cursor, command = sequence:match("^\27]633;Q;(%d+);(.*)")
  if not cursor then
    return
  end
  state.shell_state.command = unescape_shell_payload(command)
  state.shell_state.cursor = tonumber(cursor)
  state.shell_query_pending = false
end

---Handle shell integration terminal markers.
---@param args vim.api.keyset.create_autocmd.callback_args
function M.handle_term_request(args)
  local state = helpers.ensure_buffer_state(api.buffers, args.buf)
  if args.data.sequence:match("^\27]133;A") then
    state.prompt_start_cursor = args.data.cursor
    return
  end
  if args.data.sequence:match("^\27]133;B") then
    update_prompt(args, state)
    return
  end
  if args.data.sequence:match("^\27]633;I") then
    log.debug("shell integration ready", { buf = args.buf })
    state.shell_integration_ready = true
    return
  end
  if args.data.sequence:match("^\27]633;Q") then
    update_shell_query(args.data.sequence, state)
    return
  end
  if args.data.sequence:match("^\27]633;W") then
    state.shell_write_pending = false
  end
end

return M
