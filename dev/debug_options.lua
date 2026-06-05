local M = {}

function M.build()
  return {
    debug = vim.env.TERMLINE_DEBUG == "1",
    editor = {
      type = vim.env.TERMLINE_EDITOR or "overlay",
      open_on_prompt = vim.env.TERMLINE_AUTO == "1",
    },
  }
end

return M
