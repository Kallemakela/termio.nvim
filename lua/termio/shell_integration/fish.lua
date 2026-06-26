local M = { kind = "fish" }

---@param payload string
---@return boolean
function M.matches(payload)
  return payload == "fish"
end

---@param buf integer
function M.clear_completion_suggestions(buf)
  local channel = vim.b[buf].terminal_job_id or vim.bo[buf].channel
  if not channel then
    error("termio: missing terminal channel for fish wake")
  end
  vim.api.nvim_chan_send(channel, "\24\20")
end

function M.redraw_after_pty_write() end

return M
