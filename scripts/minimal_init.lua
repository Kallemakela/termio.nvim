local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")

vim.opt.runtimepath:append(root)
vim.opt.runtimepath:append(vim.fn.fnamemodify(root, ":h") .. "/mini.test")
vim.fn.mkdir(root .. "/tmp", "p")
vim.fn.writefile({}, root .. "/tmp/test.out")
vim.o.verbosefile = root .. "/tmp/test.out"
vim.o.verbose = 1
require("mini.test").setup()
