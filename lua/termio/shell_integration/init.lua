local bash = require("termio.shell_integration.bash")
local fish = require("termio.shell_integration.fish")
local helpers = require("termio.util.helpers")
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
