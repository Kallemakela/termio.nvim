local api = require("termio.api")

local M = {}

function M.setup()
  vim.api.nvim_create_user_command("TermioReadCommand", function()
    local command = api.read_command()
    vim.api.nvim_echo({ { command == "" and "(empty)" or command } }, false, {})
  end, {})
  vim.api.nvim_create_user_command("TermioWriteCommand", function(opts)
    api.write_command(opts.args)
  end, { nargs = "*" })
  vim.api.nvim_create_user_command("TermioEnable", function()
    require("termio").enable()
  end, {})
  vim.api.nvim_create_user_command("TermioDisable", function()
    require("termio").disable()
  end, {})
  vim.api.nvim_create_user_command("TermioToggle", function()
    require("termio").toggle()
  end, {})
end

return M
