local helpers = require("termio.util.helpers")

local M = { kind = "zsh" }

---@param payload string
---@return boolean
function M.matches(payload)
  return payload == "zsh"
end

---@param buf integer
function M.clear_completion_suggestions(buf)
  helpers.send_bytes("\27[27;5;67~", buf)
end

-- ZLE erases old command text by painting spaces. Redisplay repaints with ESC[K.
---@param buf integer
function M.redraw_after_pty_write(buf)
  helpers.send_bytes("\27[27;5;84~", buf)
end

return M
