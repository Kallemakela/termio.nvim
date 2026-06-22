local M = { kind = "zsh" }

---@param payload string
---@return string
function M.parse_fifo_path(payload)
  return payload
end

function M.after_send_action() end

---@param buf integer
---@param send_shell_action fun(buf: integer, action: string, payload?: string)
function M.clear_completion_suggestions(buf, send_shell_action)
  send_shell_action(buf, "clear-completions", "")
end

return M
