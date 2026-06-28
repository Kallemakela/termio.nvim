local Helpers = require("tests.helpers")
local T = MiniTest.new_set()
local child = Helpers.new_child_neovim()

T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      Helpers.setup_child(child, [[{ backend = "buffer" }]])
    end,
    post_once = child.stop,
  },
})

T["buffer backend"] = MiniTest.new_set()

-- Buffer lines cannot reliably distinguish completions from wrapped commands.
-- T["buffer backend"]["read command ignores zsh completion rows"] = function()
--   local buf = Helpers.open_shell(child)
--   child.api.nvim_input("i")
--   Helpers.wait_for_mode(child, "t")
--   child.api.nvim_input("ls<Tab>")
--   Helpers.wait_until(child, function()
--     return child.lua_get(
--       [[table.concat(vim.api.nvim_buf_get_lines(..., 0, -1, false), "\n"):find("lsbom") ~= nil]],
--       { buf }
--     )
--   end)
--   MiniTest.expect.equality(child.lua_get([[require("termio").read_command(...)]], { buf }), "ls")
-- end

return T
