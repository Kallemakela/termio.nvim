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

T["shell integration"]["test shell command query reads current buffer"] = function()
  local buf = Helpers.open_shell(child)
  child.cmd("startinsert")
  child.api.nvim_input("echo a;b")
  Helpers.wait_until(child, function()
    return child.lua_get([[require("termline").read_command_shell(...)]], { buf }) == "echo a;b"
  end)
end

T["shell integration"]["test shell command query ignores stale completion rows"] = function()
  local buf = Helpers.open_shell(child)
  child.cmd("startinsert")
  child.api.nvim_input("ls <Tab>foo")
  Helpers.wait_until(child, function()
    return child.lua_get([[require("termline").read_command_shell(...)]], { buf }) == "ls foo"
  end)
end

T["shell integration"]["test read command ignores stale completion rows"] = function()
  local buf = Helpers.open_shell(child)
  child.cmd("startinsert")
  child.api.nvim_input("ls <Tab>foo")
  Helpers.wait_until(child, function()
    return child.lua_get([[require("termline").read_command(...)]], { buf }) == "ls foo"
  end)
end

T["shell integration"]["test API clears zsh tab suggestions"] = function()
  local buf = Helpers.open_shell(child)
  child.cmd("startinsert")
  child.api.nvim_input("ls <Tab>")
  Helpers.wait_until(child, function()
    return child
      .lua_get([[table.concat(vim.api.nvim_buf_get_lines(..., 0, -1, false), "\n")]], { buf })
      :match("README%.md") ~= nil
  end)
  child.lua([[require("termline").clear_completion_suggestions(...)]], { buf })
  Helpers.wait_until(child, function()
    return child
      .lua_get([[table.concat(vim.api.nvim_buf_get_lines(..., 0, -1, false), "\n")]], { buf })
      :match("README%.md") == nil
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
      local helpers = require("termline.util.helpers")
      local original_write = api.write_command_shell
      local original_send = helpers.send_keys
      _G.termline_write_error = nil
      api.write_command_shell = function()
        error("boom")
      end
      helpers.send_keys = function()
        error("fallback called")
      end
      local ok, err = pcall(api.write_command, "echo replacement", ...)
      api.write_command_shell = original_write
      helpers.send_keys = original_send
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
  child.lua([[require("termline").write_command_shell(...)]], { command, nil, buf })
  Helpers.wait_for_read_command(child, buf, command)
end

return T
