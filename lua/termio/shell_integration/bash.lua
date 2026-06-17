local log = require("termio.util.log")

local M = { kind = "bash" }

---@param payload string
---@return string?
function M.parse_fifo_path(payload)
  return payload:match("^(.*);bash$")
end

---@param buf integer
---@param state table
function M.after_send_action(buf, state)
  local channel = vim.b[buf].terminal_job_id or vim.bo[buf].channel
  if not channel then
    error("termio: missing terminal channel for bash wake")
  end
  vim.api.nvim_chan_send(channel, "\24\20")
  -- TODO: remove this manual wait and wait for command to render
  vim.wait(30)
  log.debug("shell wake", { buf = buf, shell = state.shell_kind })
end

return M
