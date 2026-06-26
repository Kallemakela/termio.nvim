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

T["read_command()"] = MiniTest.new_set()

local function open_python_repl()
  if child.fn.executable("python3") == 0 then
    MiniTest.skip("python3 is not executable")
  end
  child.cmd("terminal python3 -q")
  local buf = child.api.nvim_get_current_buf()
  Helpers.wait_until(child, function()
    return child.api.nvim_get_current_line():match("^>>>%s*$") ~= nil
  end)
  return buf
end

T["read_command()"]["starts directly after OSC133;B cursor col"] = function()
  local prompt = "$ "
  local buf = Helpers.open_shell(child, prompt)
  child.lua(
    [[local buf, prompt = ...
    local api = require("termio.api")
    local state = require("termio.util.helpers").ensure_buffer_state(api.buffers, buf)
    state.prompt_start_cursor = { 1, 0 }
    state.prompt_end_cursor = { 1, #prompt }]],
    { buf, prompt }
  )
  child.api.nvim_input("i")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("echo hello")
  Helpers.wait_for_read_command(child, buf, "echo hello")

  MiniTest.expect.equality(
    child.lua_get([[require("termio").read_command(...)]], { buf }),
    "echo hello"
  )
end

T["read_command()"]["applies configured read strip patterns"] = function()
  child.lua([[require("termio.config").options.read_strip_patterns = { "%s+$" }]])
  local buf = Helpers.open_shell(child)
  child.api.nvim_input("i")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("echo keep   ")
  Helpers.wait_for_read_command(child, buf, "echo keep")
end

T["read_command()"]["detects default Python REPL prompt regex"] = function()
  local buf = open_python_repl()
  child.api.nvim_input("i")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("1 + 1")
  Helpers.wait_for_read_command(child, buf, "1 + 1")
  MiniTest.expect.equality(
    child.lua_get([[require("termio").command_start_cursor(...)]], { buf }),
    { 1, 4 }
  )
end

T["write_command()"] = MiniTest.new_set()

T["write_command()"]["empty command after cursor stays empty"] = function()
  local buf = Helpers.open_shell(child)
  child.api.nvim_input("i")
  Helpers.wait_for_mode(child, "t")
  child.lua([[require("termio").write_command("", ..., 1)]], { buf })
  Helpers.wait_for_read_command(child, buf, "")
end

T["pty io backend"] = MiniTest.new_set()

T["pty io backend"]["writes through terminal channel"] = function()
  child.lua([[require("termio.config").options.io_backend = "pty"]])
  local buf = Helpers.open_shell(child)
  child.api.nvim_input("i")
  Helpers.wait_for_mode(child, "t")
  child.lua([[require("termio").write_command("echo chan", ...)]], { buf })
  Helpers.wait_for_read_command(child, buf, "echo chan")
end

return T
