local helpers = require("termio.util.helpers")
local config = require("termio.config")
local log = require("termio.util.log")
local bash = require("termio.shell_integration.bash")
local zsh = require("termio.shell_integration.zsh")

local M = {}
local buffers = {}
local shells = { bash, zsh }

---@param buffer_state table<integer, table>
function M.use_buffers(buffer_state)
  buffers = buffer_state
end

---@param value string
---@return string
local function escape_fifo_payload(value)
  return value:gsub("\\", "\\\\"):gsub("\n", "\\n")
end

---@param buf integer
---@param action string
---@param payload? string
local function send_fifo_frame(buf, action, payload)
  local state = helpers.ensure_buffer_state(buffers, buf)
  local fifo = state.shell_fifo_path
  if not fifo then
    error("termio: missing shell integration FIFO")
  end
  local stat = vim.uv.fs_stat(fifo)
  if not stat or stat.type ~= "fifo" then
    log.debug("shell fifo unavailable", { buf = buf, fifo = fifo })
    state.shell_fifo_path = nil
    error("termio: shell integration FIFO unavailable")
  end
  local fd = assert(vim.uv.fs_open(fifo, "w", 384))
  local ok, err = vim.uv.fs_write(fd, action .. "\t" .. (payload or "") .. "\n", -1)
  vim.uv.fs_close(fd)
  assert(ok, err)
  log.debug("shell fifo frame", { buf = buf, action = action, fifo = fifo })
end

---@param buf integer
---@param action string
---@param payload? string
local function send_shell_action(buf, action, payload)
  local state = helpers.ensure_buffer_state(buffers, buf)
  if not state.shell_fifo_path then
    local timeout = config.options.timeouts.fifo_ready
    vim.wait(timeout.limit_ms, function()
      return state.shell_fifo_path ~= nil
    end, timeout.interval_ms)
  end
  send_fifo_frame(buf, action, payload)
  state.shell_integration.after_send_action(buf, state)
end

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

---@param sequence string
---@param state table
local function update_shell_integration(sequence, state)
  local payload = sequence:match("^\27]633;I;([^\7]*)")
  if not payload then
    return
  end
  for _, shell in ipairs(shells) do
    local fifo_path = shell.parse_fifo_path(payload)
    if fifo_path then
      state.shell_fifo_path = fifo_path
      state.shell_kind = shell.kind
      state.shell_integration = shell
      break
    end
  end
  log.debug("shell integration ready", { fifo = state.shell_fifo_path, shell = state.shell_kind })
end

---Handle shell integration terminal markers.
---@param args vim.api.keyset.create_autocmd.callback_args
function M.handle_term_request(args)
  local state = helpers.ensure_buffer_state(buffers, args.buf)
  if args.data.sequence:match("^\27]133;A") then
    state.prompt_start_cursor = args.data.cursor
    return
  end
  if args.data.sequence:match("^\27]133;B") then
    update_prompt(args, state)
    return
  end
  if args.data.sequence:match("^\27]633;I") then
    update_shell_integration(args.data.sequence, state)
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

---Query the current shell command buffer.
---@param buf integer
---@param timeout_ms? integer
---@return string
function M.read_command(buf, timeout_ms)
  local state = helpers.ensure_buffer_state(buffers, buf)
  state.shell_query_pending = true
  send_shell_action(buf, "query", "")
  local timeout = config.options.timeouts.read_command
  local received = vim.wait(timeout_ms or timeout.limit_ms, function()
    return state.shell_query_pending == false
  end, timeout.interval_ms)
  if not received then
    error("termio: shell command query timed out")
  end
  -- TODO: remove this manual wait and wait for terminal render/query consistency.
  -- FIFO query replies can arrive before Neovim has processed shell redraw bytes
  -- from the terminal PTY. Let the channel drain before callers read screen text.
  vim.wait(config.options.waits.read_render_drain_ms, function()
    return false
  end, config.options.waits.read_render_drain_ms)
  return state.shell_state.command
end

---@param buf integer
function M.clear_completion_suggestions(buf)
  send_shell_action(buf, "clear-completions", "")
end

---Write shell command buffer directly.
---@param buf integer
---@param command string
---@param cursor integer
function M.write_command(buf, command, cursor)
  local state = helpers.ensure_buffer_state(buffers, buf)
  state.shell_write_pending = true
  send_shell_action(buf, "write", tostring(cursor) .. "\t" .. escape_fifo_payload(command))
  local timeout = config.options.timeouts.write_command
  local applied = vim.wait(timeout.limit_ms, function()
    return state.shell_write_pending == false
  end, timeout.interval_ms)
  if not applied then
    error("termio: shell command write timed out")
  end
  state.shell_state.command = command
  state.shell_state.cursor = cursor
end

return M
