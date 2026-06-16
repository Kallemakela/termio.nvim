local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
local config = dofile(root .. "/dev/config.lua")
local scenario = dofile(root .. "/dev/setup_debug_scenario.lua")

scenario.setup({
  setup = function()
    config.setup()
  end,
})

scenario.open_terminal()
if vim.env.TERMLINE_DEMO == "1" then
  scenario.defer_finish(10000)
elseif vim.env.TERMLINE_AUTO == "1" then
  scenario.defer_finish(600)
else
  scenario.finish()
end
