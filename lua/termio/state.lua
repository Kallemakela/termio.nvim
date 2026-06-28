local M = { enabled = false }

---Enable termio editor integrations.
---@param opts? { notify?: boolean }
function M.enable(opts)
  if M.enabled then
    return
  end
  M.enabled = true
  if not opts or opts.notify ~= false then
    vim.notify("termio enabled", vim.log.levels.INFO)
  end
end

---Disable termio editor integrations.
function M.disable()
  if not M.enabled then
    return
  end
  M.enabled = false
  vim.notify("termio disabled", vim.log.levels.INFO)
end

---Return whether termio editor integrations are enabled.
---@return boolean
function M.is_enabled()
  return M.enabled
end

return M
