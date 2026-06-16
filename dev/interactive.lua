local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
local config = dofile(root .. "/dev/config.lua")
local editable_zone = dofile(root .. "/dev/editable_zone.lua")
local scenario = dofile(root .. "/dev/setup_debug_scenario.lua")
local status_window = dofile(root .. "/dev/status_window.lua")

local long_lorem = table.concat({
  "echo lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor incididunt ut labore et dolore magna aliqua",
  "ut enim ad minim veniam quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat",
  "duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur",
  "excepteur sint occaecat cupidatat non proident sunt in culpa qui officia deserunt mollit anim id est laborum",
}, " ")

local function write_long_lorem_with_zle()
  local api = require("termline.api")
  local buf = scenario.terminal_buf
  local ready = vim.wait(1000, function()
    return pcall(api.read_command_shell, buf, 100)
  end, 20)
  if not ready then
    error("termline dev: zsh integration is not ready")
  end
  api.write_command_shell(long_lorem, nil, buf)
end

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
    {
      "n",
      "<leader>w",
      write_long_lorem_with_zle,
    },
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
