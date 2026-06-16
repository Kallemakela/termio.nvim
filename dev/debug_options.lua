local M = {}

function M.build()
  return {
    debug = vim.env.TERMLINE_DEBUG == "1",
    editor = {
      type = vim.env.TERMLINE_EDITOR or "editable",
    },
  }
end

return M
