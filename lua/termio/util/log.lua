local M = {}

local function timestamp()
  return vim.fn.strftime("%H:%M:%S")
    .. string.format(".%03d", math.floor((vim.loop.hrtime() / 1e6) % 1000))
end

local function append_log(line, history, verbose)
  vim.api.nvim_echo({ { line } }, history, { verbose = verbose })
end

---Write a timestamped debug event.
---@param event string
---@param data any
function M.debug(event, data)
  append_log(string.format("%s %s %s", timestamp(), event, vim.inspect(data)), false, true)
end

---Write a plain message.
---@param message string
function M.info(message)
  append_log(message, true, false)
end

---Write a timestamped debug header followed by raw lines.
---@param event string
---@param lines string[]
function M.debug_lines(event, lines)
  append_log(string.format("%s %s", timestamp(), event), false, true)
  for _, line in ipairs(lines) do
    append_log(line, false, true)
  end
end

return M
