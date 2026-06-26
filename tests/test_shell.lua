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

T["shell integration"]["test read command ignores stale completion rows"] = function()
  local buf = Helpers.open_shell(child)
  child.api.nvim_input("i")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("ls <Tab>foo")
  Helpers.wait_until(child, function()
    return child.lua_get([[require("termio").read_command(...)]], { buf }) == "ls foo"
  end)
end

T["shell integration"]["test write command replaces zsh buffer directly"] = function()
  local buf = Helpers.open_shell(child)
  child.api.nvim_input("i")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("echo old")
  Helpers.wait_for_read_command(child, buf, "echo old")
  child.lua([[require("termio").write_command("echo replacement", ...)]], { buf })
  Helpers.wait_for_read_command(child, buf, "echo replacement")
end

T["shell integration"]["test shell write verifies long zsh buffer"] = function()
  local buf = Helpers.open_shell(child)
  local command = Helpers.lorem_command(545)
  child.lua([[require("termio").write_command(...)]], { command, buf })
  Helpers.wait_for_read_command(child, buf, command)
end

T["shell integration"]["test read and write command through shell"] = function()
  local buf = Helpers.open_shell(child)
  child.api.nvim_input("i")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("echo old")
  Helpers.wait_for_read_command(child, buf, "echo old")
  local command = [[printf '\\'; echo bash;]]
  child.lua([[require("termio").write_command(...)]], { command, buf })
  Helpers.wait_for_read_command(child, buf, command)
end

return T
