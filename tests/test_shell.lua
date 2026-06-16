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
  child.cmd("startinsert")
  child.api.nvim_input("ls <Tab>foo")
  Helpers.wait_until(child, function()
    return child.lua_get([[require("termline").read_command(...)]], { buf }) == "ls foo"
  end)
end

T["shell integration"]["test write command replaces zsh buffer directly"] = function()
  local buf = Helpers.open_shell(child)
  child.cmd("startinsert")
  child.api.nvim_input("echo old")
  Helpers.wait_for_read_command(child, buf, "echo old")
  child.lua([[require("termline").write_command("echo replacement", ...)]], { buf })
  Helpers.wait_for_read_command(child, buf, "echo replacement")
end

T["shell integration"]["test write command does not fall back after shell write error"] = function()
  local buf = Helpers.open_shell(child)
  child.cmd("startinsert")
  child.lua(
    [[
      local api = require("termline")
      local original_kill = vim.uv.kill
      _G.termline_write_error = nil
      vim.uv.kill = function()
        error("boom")
      end
      local ok, err = pcall(api.write_command, "echo replacement", ...)
      vim.uv.kill = original_kill
      _G.termline_write_error = ok and nil or err
    ]],
    { buf }
  )
  MiniTest.expect.equality(child.lua_get("_G.termline_write_error:match('boom') ~= nil"), true)
end

T["shell integration"]["test shell write verifies long zsh buffer"] = function()
  local buf = Helpers.open_shell(child)
  child.cmd("startinsert")
  local command = "echo " .. string.rep("lorem ipsum dolor sit amet ", 20)
  child.lua([[require("termline").write_command(...)]], { command, buf })
  Helpers.wait_for_read_command(child, buf, command)
end

return T
