local bash = require("termio.shell_integration.bash")
local config = require("termio.config")
local fish = require("termio.shell_integration.fish")
local helpers = require("termio.util.helpers")
local log = require("termio.util.log")
local zsh = require("termio.shell_integration.zsh")

local M = {}
local buffers = {}
local shells = { bash, fish, zsh }

---@param buffer_state table<integer, table>
function M.use_buffers(buffer_state)
  buffers = buffer_state
end

---Asks process which shell
---@param sequence string
---@return table? shell
function M.parse_shell(sequence)
  local payload = sequence:match("^\27]633;I;([^\7]*)")
  if not payload then
    return nil
  end
  for _, shell in ipairs(shells) do
    if shell.matches(payload) then
      return shell
    end
  end
  return nil
end

---@param buf integer
---@param timeout_ms? integer
---@return { command: string, cursor: integer? }?
function M.read_state(buf, timeout_ms)
  local state = helpers.ensure_buffer_state(buffers, buf)
  if not state.shell_integration or not state.shell_integration.read_state then
    return nil
  end
  state.shell_query_pending = true
  state.shell_integration.read_state(buf)
  local timeout = config.options.timeouts.shell_query
  local received = vim.wait(timeout_ms or timeout.limit_ms, function()
    return state.shell_query_pending == false
  end, timeout.interval_ms)
  if not received then
    state.shell_query_pending = false
    log.debug("shell_integration.read_state.timeout", { buf = buf, shell = state.shell_kind })
    return nil
  end
  return vim.deepcopy(state.shell_state)
end

---@param buf integer
function M.clear_completion_suggestions(buf)
  local state = helpers.ensure_buffer_state(buffers, buf)
  if state.shell_integration then
    state.shell_integration.clear_completion_suggestions(buf)
  end
end

---@param buf integer
function M.redraw_after_pty_write(buf)
  local state = helpers.ensure_buffer_state(buffers, buf)
  if state.shell_integration then
    state.shell_integration.redraw_after_pty_write(buf)
  end
end

return M
