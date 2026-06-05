local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
local debug_options = dofile(root .. "/dev/debug_options.lua")

local M = {}

local function setup_verbosefile()
  if vim.env.TERMLINE_DEBUG ~= "1" then
    return
  end
  vim.fn.mkdir(root .. "/tmp", "p")
  vim.fn.writefile({}, root .. "/tmp/dev.out")
  vim.o.verbosefile = root .. "/tmp/dev.out"
  vim.o.verbose = 1
end

function M.setup(opts)
  opts = opts or {}
  setup_verbosefile()
  if opts.before_setup then
    opts.before_setup()
  end
  require("termline").setup(debug_options.build())
end

return M
