local M = {}

function M.build()
  return {
    debug = vim.env.TERMIO_DEBUG == "1",
    editor = {
      type = vim.env.TERMIO_EDITOR or "editable",
    },
  }
end

return M
