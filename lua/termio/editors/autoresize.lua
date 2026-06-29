local M = {}

---Calculate float height needed for wrapped editor content.
---@param lines string[]
---@param width integer
---@param max_height integer
---@return integer
function M.height_for_lines(lines, width, max_height)
  local height = 0
  for _, line in ipairs(lines) do
    height = height + math.max(1, math.ceil(vim.fn.strdisplaywidth(line) / math.max(width, 1)))
  end
  return math.max(1, math.min(height, max_height))
end

local function keep_cursor_visible(edit_win)
  local cursor = vim.api.nvim_win_get_cursor(edit_win)
  local height = vim.api.nvim_win_get_height(edit_win)
  vim.api.nvim_win_call(edit_win, function()
    vim.fn.winrestview({ topline = math.max(cursor[1] - height + 1, 1) })
  end)
end

---Resize an editor float when its buffer content changes.
---@param edit_buf integer
---@param edit_win integer
---@param max_height integer
function M.register(edit_buf, edit_win, max_height)
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    buffer = edit_buf,
    callback = function()
      if not vim.api.nvim_win_is_valid(edit_win) then
        return
      end
      local config = vim.api.nvim_win_get_config(edit_win)
      local lines = vim.api.nvim_buf_get_lines(edit_buf, 0, -1, false)
      local height = M.height_for_lines(lines, config.width, max_height)
      if height == config.height then
        return
      end
      vim.api.nvim_win_set_config(edit_win, { height = height })
      keep_cursor_visible(edit_win)
    end,
  })
end

return M
