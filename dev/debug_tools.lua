local M = { terminal = {} }

local function assert_terminal_channel()
  local chan = M.terminal.chan
  if not chan or chan == 0 then
    error("test entrypoint: missing terminal channel")
  end
  return chan
end

---Store the active terminal handles for later debug actions.
---@param buf integer
---@param win integer
---@param chan integer
function M.attach_terminal(buf, win, chan)
  if not chan or chan == 0 then
    error("test entrypoint: missing terminal channel")
  end
  M.terminal = { buf = buf, win = win, chan = chan }
end

---Send raw terminal input during debug runs.
---@param keys string
function M.send_keys(keys)
  vim.fn.chansend(assert_terminal_channel(), keys)
end

return M
