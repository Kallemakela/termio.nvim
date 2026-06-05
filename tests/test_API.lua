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
    local api = require("termline")
    local state = require("termline.util.helpers").ensure_buffer_state(api.buffers, buf)
    state.prompt = prompt
    state.prompt_end_cursor = { 1, #prompt }]],
    { buf, prompt }
  )
  child.cmd("startinsert")
  child.api.nvim_input("echo hello")
  Helpers.wait_for_read_command(child, buf, "echo hello")

  MiniTest.expect.equality(
    child.lua_get([[require("termline").read_command(...)]], { buf }),
    "echo hello"
  )
end

T["read_command()"]["strips all-whitespace input"] = function()
  local prompt = string.rep("x", 27)

  child.cmd("terminal true")
  local buf = child.api.nvim_get_current_buf()
  child.api.nvim_set_option_value("modifiable", true, { buf = buf })
  child.api.nvim_buf_set_lines(buf, 0, -1, false, { prompt .. "           " })
  child.api.nvim_exec_autocmds("TermRequest", {
    buffer = buf,
    modeline = false,
    data = { sequence = "\27]133;B", cursor = { 1, 27 } },
  })

  MiniTest.expect.equality(child.lua_get([[require("termline").read_command(...)]], { buf }), "")
end

return T
