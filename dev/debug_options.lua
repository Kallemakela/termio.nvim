local M = {}

function M.build()
  local options = {
    debug = vim.env.TERMIO_DEBUG == "1",
    editor = {
      type = vim.env.TERMIO_EDITOR or "editable",
    },
  }
  if vim.env.TERMIO_BACKEND and vim.env.TERMIO_BACKEND ~= "" then
    options.backend = vim.env.TERMIO_BACKEND
  end
  return options
end

return M
