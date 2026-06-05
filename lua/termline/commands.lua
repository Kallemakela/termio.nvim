local api = require("termline.api")

local M = {}

function M.setup()
  vim.api.nvim_create_user_command("TermReadCommand", function()
    local command = api.read_command()
    vim.api.nvim_echo({ { command == "" and "(empty)" or command } }, false, {})
  end, {})
  vim.api.nvim_create_user_command("TermWriteCommand", function(opts)
    api.write_command(opts.args ~= "" and opts.args or nil)
  end, { nargs = "*" })
  vim.api.nvim_create_user_command("TermClearCommand", function()
    api.clear_command()
  end, {})
end

return M
