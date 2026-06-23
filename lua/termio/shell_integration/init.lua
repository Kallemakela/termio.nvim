local config = require("termio.config")
local log = require("termio.util.log")
local bash = require("termio.shell_integration.bash")
local fish = require("termio.shell_integration.fish")
local helpers = require("termio.util.helpers")
local zsh = require("termio.shell_integration.zsh")

local M = {}
local buffers = {}
local shells = { bash, fish, zsh }

local function wait_for_timeout_poll(name, timeout, predicate, data)
  local started = vim.uv.hrtime()
  local completed = vim.wait(timeout.limit_ms, predicate, timeout.interval_ms)
  log.debug(
    "shell timeout poll",
    vim.tbl_extend("force", data or {}, {
      name = name,
      completed = completed,
      elapsed_ms = math.floor((vim.uv.hrtime() - started) / 1e6),
      limit_ms = timeout.limit_ms,
      interval_ms = timeout.interval_ms,
    })
  )
  return completed
end

---@param buffer_state table<integer, table>
function M.use_buffers(buffer_state)
  buffers = buffer_state
end

---@param sequence string
---@return string? fifo_path
---@return table? shell
function M.parse_fifo_path(sequence)
  local payload = sequence:match("^\27]633;I;([^\7]*)")
  if not payload then
    return nil, nil
  end
  for _, shell in ipairs(shells) do
    local fifo_path = shell.parse_fifo_path(payload)
    if fifo_path then
      return fifo_path, shell
    end
  end
  return nil, nil
end

---@param value string
---@return string
local function escape_fifo_payload(value)
  return value:gsub("\\", "\\\\"):gsub("\n", "\\n")
end

---@param fifo string
---@return integer
local function open_fifo_writer(fifo)
  local flags = vim.uv.constants.O_WRONLY + vim.uv.constants.O_NONBLOCK
  local timeout = config.options.timeouts.fifo_ready
  local deadline = vim.uv.hrtime() + timeout.limit_ms * 1e6
  local last_error
  repeat
    local fd, err, err_name = vim.uv.fs_open(fifo, flags, 384)
    if type(fd) == "number" and fd >= 0 then
      return fd
    end
    last_error = err_name or err
    vim.wait(timeout.interval_ms)
  until vim.uv.hrtime() >= deadline
  error("termio: shell integration FIFO has no reader: " .. tostring(last_error))
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
  local fd = open_fifo_writer(fifo)
  local ok, err = vim.uv.fs_write(fd, action .. "\t" .. (payload or "") .. "\n", -1)
  vim.uv.fs_close(fd)
  if type(ok) ~= "number" or ok < 0 then
    error(err or "termio: shell integration FIFO write failed")
  end
  log.debug("shell fifo frame", { buf = buf, action = action, fifo = fifo })
end

---@param buf integer
---@param action string
---@param payload? string
local function send_shell_action(buf, action, payload)
  local state = helpers.ensure_buffer_state(buffers, buf)
  if not state.shell_fifo_path then
    local timeout = config.options.timeouts.fifo_ready
    wait_for_timeout_poll("fifo_ready", timeout, function()
      return state.shell_fifo_path ~= nil
    end, { buf = buf, action = action })
  end
  if state.shell_integration.before_send_action then
    state.shell_integration.before_send_action(buf, state)
  end
  send_fifo_frame(buf, action, payload)
  state.shell_integration.after_send_action(buf, state)
end

---Query the current shell command buffer.
---@param buf integer
---@param timeout_ms? integer
---@return string
function M.read_command(buf, timeout_ms)
  return M.read_state(buf, nil, timeout_ms).command
end

---@param buf integer
---@param _win? integer
---@param timeout_ms? integer
---@return { command: string, cursor: integer? }
function M.read_state(buf, _win, timeout_ms)
  local state = helpers.ensure_buffer_state(buffers, buf)
  state.shell_query_pending = true
  send_shell_action(buf, "query", "")
  local timeout = config.options.timeouts.read_command
  local active_timeout =
    vim.tbl_extend("force", timeout, { limit_ms = timeout_ms or timeout.limit_ms })
  local received = wait_for_timeout_poll("read_command", active_timeout, function()
    return state.shell_query_pending == false
  end, { buf = buf })
  if not received then
    error("termio: shell command query timed out")
  end
  return vim.deepcopy(state.shell_state)
end

---@param buf integer
function M.clear_completion_suggestions(buf)
  local state = helpers.ensure_buffer_state(buffers, buf)
  state.shell_integration.clear_completion_suggestions(buf, send_shell_action)
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
  local applied = wait_for_timeout_poll("write_command", timeout, function()
    return state.shell_write_pending == false
  end, { buf = buf })
  if not applied then
    error("termio: shell command write timed out")
  end
  state.shell_state.command = command
  state.shell_state.cursor = cursor
end

return M
