local Helpers = require("tests.helpers")
local T = MiniTest.new_set()
local child = Helpers.new_child_neovim()

T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      Helpers.setup_child(child, [[{ editor = { type = "prompt" } }]])
    end,
    post_once = child.stop,
  },
})

T["prompt.open()"] = MiniTest.new_set()

T["prompt.open()"]["renders prompt between OSC133;A and OSC133;B"] = function()
  local prompt = "$ "

  child.cmd("terminal true")
  local buf = child.api.nvim_get_current_buf()
  child.api.nvim_set_option_value("modifiable", true, { buf = buf })
  child.api.nvim_buf_set_lines(buf, 0, -1, false, { "noise" .. prompt .. "echo hello" })
  child.api.nvim_exec_autocmds("TermRequest", {
    buffer = buf,
    modeline = false,
    data = { sequence = "\27]133;A;cl=line", cursor = { 1, 5 } },
  })
  child.api.nvim_exec_autocmds("TermRequest", {
    buffer = buf,
    modeline = false,
    data = { sequence = "\27]133;B", cursor = { 1, 7 } },
  })
  Helpers.wait_until(child, function()
    return child.lua_get([[require("termline").buffers[...].prompt]], { buf }) == prompt
  end)
  child.lua([[require("termline.editors.prompt").open(...)]], {
    { target_buf = buf, target_win = child.api.nvim_get_current_win() },
  })

  MiniTest.expect.equality(child.api.nvim_get_current_line(), prompt .. "echo hello")
end

T["prompt.open()"]["renders prompt from terminal state"] = function()
  local prompt = "$ "
  local buf = Helpers.open_shell(child, prompt)
  child.cmd("startinsert")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("echo hello world")
  Helpers.wait_for_read_command(child, buf, "echo hello world")
  child.api.nvim_input("<Esc>")
  Helpers.wait_until(child, function()
    return child.api.nvim_get_option_value("buftype", { buf = 0 }) == "prompt"
  end)
  local got_prompt = child.lua_get([[(function()
    local win = vim.api.nvim_get_current_win()
    local row, col = unpack(vim.api.nvim_win_get_position(win))
    local screen_row = row + vim.fn.winline()
    local chars = {}
    for screen_col = col + 1, col + vim.api.nvim_win_get_width(win) do
      chars[#chars + 1] = vim.fn.screenstring(screen_row, screen_col)
    end
    return table.concat(chars):gsub("%s+$", "")
  end)() ]])
  MiniTest.expect.equality(got_prompt, prompt .. "echo hello world")
end

T["prompt.open()"]["tab pass-through returns to terminal insert mode"] = function()
  local buf = Helpers.open_shell(child)
  child.cmd("startinsert")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("<Esc>")
  Helpers.wait_until(child, function()
    return child.api.nvim_get_option_value("buftype", { buf = 0 }) == "prompt"
  end)
  child.api.nvim_input("acat R<Tab>")
  child.wait(100)
  MiniTest.expect.equality(child.api.nvim_get_current_buf(), buf)
  MiniTest.expect.equality(child.lua_get("vim.api.nvim_get_mode().mode"), "t")
end

T["prompt.open()"]["submit returns to terminal mode"] = function()
  local buf = Helpers.open_shell(child)
  child.cmd("startinsert")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("echo hello world")
  Helpers.wait_for_read_command(child, buf, "echo hello world")
  child.api.nvim_input("<Esc>")
  Helpers.wait_until(child, function()
    return child.api.nvim_get_option_value("buftype", { buf = 0 }) == "prompt"
  end)
  Helpers.wait_for_mode(child, "n")
  child.api.nvim_input("<CR>")
  Helpers.wait_until(child, function()
    return child.api.nvim_get_current_buf() == buf
  end)
  Helpers.wait_for_mode(child, "t")
end

T["prompt.open()"]["insert submit returns to terminal mode"] = function()
  local buf = Helpers.open_shell(child)
  child.cmd("startinsert")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("echo hello world")
  Helpers.wait_for_read_command(child, buf, "echo hello world")
  child.api.nvim_input("<Esc>")
  Helpers.wait_until(child, function()
    return child.api.nvim_get_option_value("buftype", { buf = 0 }) == "prompt"
  end)
  Helpers.wait_for_mode(child, "n")
  child.api.nvim_input("A")
  Helpers.wait_for_mode(child, "i")
  child.api.nvim_input("<CR>")
  Helpers.wait_until(child, function()
    return child.api.nvim_get_current_buf() == buf
  end)
  Helpers.wait_for_mode(child, "t")
end

T["prompt.open()"]["k esc ends in normal mode"] = function()
  local buf = Helpers.open_shell(child)
  child.cmd("startinsert")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("echo hello world")
  Helpers.wait_for_read_command(child, buf, "echo hello world")
  child.api.nvim_input("<Esc>")
  Helpers.wait_until(child, function()
    return child.api.nvim_get_option_value("buftype", { buf = 0 }) == "prompt"
  end)
  Helpers.wait_for_mode(child, "n")
  child.api.nvim_input("k")
  Helpers.wait_until(child, function()
    return child.api.nvim_get_current_buf() == buf
  end)
  child.api.nvim_input("<Esc>")
  Helpers.wait_for_mode(child, "n")
end

T["prompt.open()"]["esc then { on wrapped command stays right after prompt"] = function()
  local prompt = "$ "
  local command =
    "echo lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor incididunt ut labore et dolore magna aliqua ut enim ad minim veniam quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur excepteur sint occaecat cupidatat non proident sunt in culpa qui officia deserunt mollit anim id est laborum lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor incididunt ut labore et dolore magna aliqua ut enim ad minim veniam quis nostrud exercitation ullamco laboris nisi"
  local buf = Helpers.open_shell(child, prompt)
  child.set_size(24, 80)
  child.cmd("startinsert")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input(command)
  Helpers.wait_for_read_command(child, buf, command)
  child.api.nvim_input("<Esc>")
  Helpers.wait_until(child, function()
    return child.api.nvim_get_option_value("buftype", { buf = 0 }) == "prompt"
  end)
  child.api.nvim_input("j{")
  child.wait(100)
  MiniTest.expect.equality(child.lua_get("vim.api.nvim_win_get_cursor(0)[2]"), #prompt)
end

return T
