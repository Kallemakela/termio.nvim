local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
local config = dofile(root .. "/dev/config.lua")
local editable_zone = dofile(root .. "/dev/editable_zone.lua")
local scenario = dofile(root .. "/dev/setup_debug_scenario.lua")
local snapshot = dofile(root .. "/dev/snapshot.lua")
local status_window = dofile(root .. "/dev/status_window.lua")

local long_lorem = table.concat({
  "echo lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor incididunt ut labore et dolore magna aliqua",
  "ut enim ad minim veniam quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat",
  "duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur",
  "excepteur sint occaecat cupidatat non proident sunt in culpa qui officia deserunt mollit anim id est laborum",
}, " ")

local function write_long_lorem_with_zle()
  local termio = require("termio")
  local buf = scenario.terminal_buf
  local ready = vim.wait(1000, function()
    return pcall(termio.read_command, buf)
  end, 20)
  if not ready then
    error("termio dev: shell integration is not ready")
  end
  termio.write_command(long_lorem, buf)
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
})

vim.keymap.set("n", "<leader>g", "<Cmd>TermioReadCommand<CR>")
vim.keymap.set("n", "<leader>w", write_long_lorem_with_zle)
vim.keymap.set({ "n", "v", "x" }, "K", "{")
vim.keymap.set({ "n", "v", "x" }, "J", "}")
vim.keymap.set("n", "<leader>e", function()
  editable_zone.show()
end)
vim.keymap.set("n", "<leader>bk", "<Cmd>bdelete!<CR>")
vim.keymap.set("n", "<leader>i", snapshot.write)
vim.keymap.set("n", "<leader>l", function()
  vim.cmd.edit(vim.fn.fnameescape(vim.o.verbosefile))
end)
vim.keymap.set("n", "<leader>o", function()
  vim.cmd.edit(vim.fn.fnameescape(vim.fn.getcwd() .. "/tmp/termdump.out"))
end)

scenario.open_terminal()
local function extend_prompt_jump(mode, lhs, suffix)
  local original = vim.fn.maparg(lhs, mode, false, true)
  vim.keymap.set(mode, lhs, function()
    original.callback()
    vim.cmd.normal({ suffix, bang = true })
  end, { buffer = scenario.terminal_buf })
end

extend_prompt_jump("n", "[[", "E")
extend_prompt_jump("x", "[[", "E")
extend_prompt_jump("n", "]]", "E")
extend_prompt_jump("x", "]]", "E")
status_window.setup()
