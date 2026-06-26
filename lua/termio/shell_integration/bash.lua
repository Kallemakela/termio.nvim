local M = { kind = "bash" }

---@param payload string
---@return boolean
function M.matches(payload)
  return payload == "bash"
end

function M.clear_completion_suggestions() end

-- Bash readline automatically clears stale cells with ESC[K after PTY writes.
function M.redraw_after_pty_write() end

return M
