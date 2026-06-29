local M = {}

local function editor_intact(buf)
  return vim.api.nvim_buf_is_valid(buf) and vim.b[buf].termio_fixed_editor == true
end

---Redirect files opened in a fixed editor window back to the target window.
---@param edit_buf integer
---@param edit_win integer
---@param target_win integer
function M.register(edit_buf, edit_win, target_win)
  local pending = false
  vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
    callback = function(args)
      if pending then
        return
      end
      pending = true
      vim.schedule(function()
        pending = false
        if not vim.api.nvim_win_is_valid(edit_win) then
          pcall(vim.api.nvim_del_autocmd, args.id)
          return
        end
        local buf = vim.api.nvim_win_get_buf(edit_win)
        if buf == edit_buf and editor_intact(edit_buf) then
          return
        end
        pcall(vim.api.nvim_del_autocmd, args.id)
        if not vim.api.nvim_win_is_valid(target_win) then
          return
        end
        vim.api.nvim_win_set_buf(target_win, buf)
        vim.api.nvim_win_close(edit_win, true)
        vim.api.nvim_set_current_win(target_win)
      end)
    end,
  })
end

return M
