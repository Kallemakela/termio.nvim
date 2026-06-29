local Helpers = require("tests.helpers")
local T = MiniTest.new_set()
local child = Helpers.new_child_neovim()

T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      Helpers.setup_child(child, [[{ editor = { type = "minimal" } }]])
      child.set_size(24, 80)
    end,
    post_once = child.stop,
  },
})

T["minimal editor"] = MiniTest.new_set()

local function open_minimal_editor(command)
  local terminal_buf = Helpers.open_shell(child)
  child.api.nvim_input("i")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input(command)
  Helpers.wait_for_read_command(child, terminal_buf, command)
  local terminal_win = child.api.nvim_get_current_win()
  child.lua([[require("termio.editors.minimal").open({ target_buf = ... })]], { terminal_buf })
  Helpers.wait_for_mode(child, "n")
  return terminal_buf, terminal_win
end

T["minimal editor"]["opens prompt command buffer in float"] = function()
  local _, terminal_win = open_minimal_editor("echo old")
  local float_config = child.api.nvim_win_get_config(0)
  MiniTest.expect.equality(float_config.relative, "win")
  MiniTest.expect.equality(float_config.win, terminal_win)
  MiniTest.expect.equality(child.api.nvim_get_current_line(), "$ echo old")
end

T["minimal editor"]["opens at shell cursor"] = function()
  local terminal_buf = Helpers.open_shell(child)
  child.api.nvim_input("i")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("echo old<Left><Left><Left>")
  Helpers.wait_until(child, function()
    local state = child.lua_get([[require("termio.api").read_state(...)]], { terminal_buf })
    return state.command == "echo old" and state.cursor == 5
  end)

  child.lua([[require("termio.editors.minimal").open({ target_buf = ... })]], { terminal_buf })
  Helpers.wait_for_mode(child, "n")
  MiniTest.expect.equality(child.api.nvim_win_get_cursor(0), { 1, 7 })
end

T["minimal editor"]["clamps cursor after prompt"] = function()
  open_minimal_editor("echo old")
  child.cmd("normal! 0")
  Helpers.wait_until(child, function()
    return child.api.nvim_win_get_cursor(0)[2] == 2
  end)
end

T["minimal editor"]["writes command from prompt buffer"] = function()
  local terminal_buf = open_minimal_editor("echo old")
  child.api.nvim_set_current_line("$ echo minimal")
  child.lua([[require("termio.editors.minimal").write()]])
  Helpers.wait_for_read_command(child, terminal_buf, "echo minimal")
end

T["minimal editor"]["insert enter submits command"] = function()
  local terminal_buf = open_minimal_editor("echo insert")
  child.api.nvim_input("i<CR>")
  Helpers.wait_for_shell_output(child, terminal_buf, "insert")
  Helpers.wait_for_mode(child, "t")
end

T["minimal editor"]["insert shift enter adds newline"] = function()
  open_minimal_editor("echo first")
  child.api.nvim_input("A<S-CR>second")
  Helpers.wait_until(child, function()
    return child.lua_get([[vim.api.nvim_buf_line_count(0)]]) == 2
  end)
  MiniTest.expect.equality(
    child.api.nvim_buf_get_lines(0, 0, -1, false),
    { "$ echo first", "second" }
  )
end

T["minimal editor"]["normal escape saves and closes"] = function()
  local terminal_buf = open_minimal_editor("echo hello")
  child.api.nvim_set_current_line("$ echo changed")
  child.api.nvim_input("<Esc>")
  Helpers.wait_until(child, function()
    return child.api.nvim_get_current_buf() == terminal_buf
  end)
  Helpers.wait_for_read_command(child, terminal_buf, "echo changed")
end

T["minimal editor"]["q closes without submitting"] = function()
  local terminal_buf = open_minimal_editor("echo hello")
  child.api.nvim_set_current_line("$ echo changed")
  child.api.nvim_input("q")
  Helpers.wait_until(child, function()
    return child.api.nvim_get_current_buf() == terminal_buf
  end)
  Helpers.wait_for_read_command(child, terminal_buf, "echo hello")
end

T["minimal editor"]["tab passes through to terminal insert mode"] = function()
  local terminal_buf = open_minimal_editor("echo hello")
  child.api.nvim_input("A")
  Helpers.wait_for_mode(child, "i")
  child.api.nvim_input("<Tab>")
  Helpers.wait_until(child, function()
    return child.api.nvim_get_current_buf() == terminal_buf
  end)
  Helpers.wait_for_mode(child, "t")
end

T["minimal editor"]["j and k move by visual lines"] = function()
  open_minimal_editor(("echo lorem ipsum dolor sit amet "):rep(5))
  local start = child.api.nvim_win_get_cursor(0)
  child.api.nvim_input("j")
  child.wait(20)
  MiniTest.expect.equality(child.api.nvim_win_get_cursor(0)[1] >= start[1], true)
  child.api.nvim_input("k")
  child.wait(20)
  MiniTest.expect.equality(child.api.nvim_get_option_value("buftype", { buf = 0 }), "prompt")
end

T["minimal editor"]["resizes when content grows"] = function()
  open_minimal_editor("echo first")
  local initial_config = child.api.nvim_win_get_config(0)
  child.api.nvim_input("A<S-CR>second")
  Helpers.wait_until(child, function()
    return child.api.nvim_win_get_config(0).height == 2
  end)
  MiniTest.expect.equality(initial_config.height, 1)
end

T["minimal editor"]["first-line normal pass-through returns to terminal"] = function()
  local terminal_buf = open_minimal_editor("echo hello")
  Helpers.wait_for_mode(child, "n")
  child.api.nvim_input("{")
  Helpers.wait_until(child, function()
    return child.api.nvim_get_current_buf() == terminal_buf
  end)
end

T["minimal editor"]["search keys pass through to terminal"] = function()
  local terminal_buf = open_minimal_editor("echo hello")
  child.api.nvim_input("/")
  Helpers.wait_until(child, function()
    return child.api.nvim_get_current_buf() == terminal_buf and child.fn.getcmdtype() == "/"
  end)
  child.api.nvim_input("<Esc>")
end

T["minimal editor"]["redirects opened files to target window"] = function()
  local _, terminal_win = open_minimal_editor("echo old")
  child.cmd("edit README.md")
  Helpers.wait_until(child, function()
    return child.api.nvim_get_current_win() == terminal_win
  end)
  Helpers.expect.match(child.api.nvim_buf_get_name(0), "README%.md$")
end

return T
