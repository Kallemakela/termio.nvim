local Helpers = require("tests.helpers")
local T = MiniTest.new_set()
local child = Helpers.new_child_neovim()

T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      Helpers.setup_child(child)
    end,
    post_once = child.stop,
  },
})

T["shell integration"] = MiniTest.new_set()

T["shell integration"]["test shell emits OSC633 preexec marker"] = function()
  local buf = Helpers.open_shell(child)
  child.lua([[
    _G.termline_test_sequences = {}
    vim.api.nvim_create_autocmd("TermRequest", {
      group = vim.api.nvim_create_augroup("termline-test-osc633", { clear = true }),
      callback = function(args)
        table.insert(_G.termline_test_sequences, args.data.sequence)
      end,
    })
  ]])
  child.cmd("startinsert")
  child.api.nvim_input("echo hello<CR>")
  Helpers.wait_for_shell_output(child, buf, "hello")
  Helpers.wait_until(child, function()
    return child.lua_get([[
      vim.iter(_G.termline_test_sequences):any(function(sequence)
        return sequence:match("^\27]633;E;echo hello") ~= nil
      end)
    ]])
  end)
end

return T
