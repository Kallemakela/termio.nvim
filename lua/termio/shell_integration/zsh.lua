local M = { kind = "zsh" }

---@param payload string
---@return string
function M.parse_fifo_path(payload)
  return payload
end

function M.after_send_action() end

return M
