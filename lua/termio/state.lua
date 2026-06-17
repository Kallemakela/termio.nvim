local M = { enabled = false }

---Enable termio editor integrations.
function M.enable()
  M.enabled = true
end

---Disable termio editor integrations.
function M.disable()
  M.enabled = false
end

---Toggle termio editor integrations.
function M.toggle()
  if M.is_enabled() then
    M.disable()
  else
    M.enable()
  end
end

---Return whether termio editor integrations are enabled.
---@return boolean
function M.is_enabled()
  return M.enabled
end

return M
