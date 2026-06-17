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
    return child.lua_get([[require("termio").read_command(...)]], { buf }) == "ls foo"
  end)
end

T["shell integration"]["test write command replaces zsh buffer directly"] = function()
  local buf = Helpers.open_shell(child)
  child.cmd("startinsert")
  child.api.nvim_input("echo old")
  Helpers.wait_for_read_command(child, buf, "echo old")
  child.lua([[require("termio").write_command("echo replacement", ...)]], { buf })
  Helpers.wait_for_read_command(child, buf, "echo replacement")
end

T["shell integration"]["test shell integration announces fifo path"] = function()
  local buf = Helpers.open_shell(child)
  Helpers.wait_until(child, function()
    local path = child.lua_get([[require("termio.api").buffers[...].shell_fifo_path]], { buf })
    return type(path) == "string" and path:match("termio%.nvim%.%d+%.fifo$") ~= nil
  end)
end

T["shell integration"]["test fifo frame writes zsh buffer"] = function()
  local buf = Helpers.open_shell(child)
  child.cmd("startinsert")
  Helpers.wait_until(child, function()
    return child.lua_get([[require("termio.api").buffers[...].shell_fifo_path ~= nil]], { buf })
  end)
  child.lua([[require("termio").write_command("echo fifo", ...)]], { buf })
  Helpers.wait_for_read_command(child, buf, "echo fifo")
end

T["shell integration"]["test fifo write surfaces write error"] = function()
  local buf = Helpers.open_shell(child)
  child.cmd("startinsert")
  Helpers.wait_until(child, function()
    return child.lua_get([[require("termio.api").buffers[...].shell_fifo_path ~= nil]], { buf })
  end)
  child.lua(
    [[
      local api = require("termio")
      local original_write = vim.uv.fs_write
      _G.termio_write_error = nil
      vim.uv.fs_write = function()
        error("boom")
      end
      local ok, err = pcall(api.write_command, "echo replacement", ...)
      vim.uv.fs_write = original_write
      _G.termio_write_error = ok and nil or err
    ]],
    { buf }
  )
  MiniTest.expect.equality(child.lua_get("_G.termio_write_error:match('boom') ~= nil"), true)
end

T["shell integration"]["test shell write verifies long zsh buffer"] = function()
  local buf = Helpers.open_shell(child)
  child.cmd("startinsert")
  local command = "echo " .. string.rep("lorem ipsum dolor sit amet ", 20)
  child.lua([[require("termio").write_command(...)]], { command, buf })
  Helpers.wait_for_read_command(child, buf, command)
end

return T
