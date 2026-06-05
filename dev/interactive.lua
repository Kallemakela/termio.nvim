local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
local config = dofile(root .. "/dev/config.lua")
local editable_zone = dofile(root .. "/dev/editable_zone.lua")
local scenario = dofile(root .. "/dev/setup_debug_scenario.lua")
local status_window = dofile(root .. "/dev/status_window.lua")

scenario.setup({
  setup = function()
    config.setup({
      before_setup = function()
        require("vim._core.ui2").enable({
          enable = true,
          msg = {
            targets = {
              default = "cmd",
              progress = "cmd",
            },
          },
        })
      end,
    })
  end,
  keymaps = {
    { "n", "<leader>g", "<Cmd>TermReadCommand<CR>" },
    { "n", "<leader>s", "<Cmd>TermWriteCommand<CR>" },
    { { "n", "v", "x" }, "K", "{" },
    { { "n", "v", "x" }, "J", "}" },
    {
      "n",
      "<leader>e",
      function()
        editable_zone.show()
      end,
    },
    { "n", "<leader>bk", "<Cmd>bdelete!<CR>" },
    {
      "n",
      "<leader>l",
      function()
        vim.cmd.edit(vim.fn.fnameescape(vim.o.verbosefile))
      end,
    },
    {
      "n",
      "<leader>o",
      function()
        vim.cmd.edit(vim.fn.fnameescape(vim.fn.getcwd() .. "/tmp/termdump.out"))
      end,
    },
  },
})

scenario.open_terminal()
status_window.setup()
