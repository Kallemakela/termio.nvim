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

T["write_command()"] = MiniTest.new_set()

T["write_command()"]["empty command after cursor stays empty"] = function()
  local buf = Helpers.open_shell(child)
  child.api.nvim_input("i")
  Helpers.wait_for_mode(child, "t")
  child.lua([[require("termio").write_command("", ..., 1)]], { buf })
  Helpers.wait_for_read_command(child, buf, "")
end

return T
