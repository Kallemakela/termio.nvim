local log = require("termio.util.log")

local M = { kind = "fish" }

---@param payload string
---@return string?
function M.parse_fifo_path(payload)
  return payload:match("^(.*);fish$")
end

---@param buf integer
---@param state table
function M.before_send_action(buf, state)
  local channel = vim.b[buf].terminal_job_id or vim.bo[buf].channel
  if not channel then
    error("termio: missing terminal channel for fish wake")
  end
  vim.api.nvim_chan_send(channel, "\24\20")
  log.debug("shell wake", { buf = buf, shell = state.shell_kind })
end

function M.after_send_action() end

---@param buf integer
---@param send_shell_action fun(buf: integer, action: string, payload?: string)
function M.clear_completion_suggestions(buf, send_shell_action)
  send_shell_action(buf, "clear-completions", "")
end

return M
