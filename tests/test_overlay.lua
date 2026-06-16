local Helpers = require("tests.helpers")
local T = MiniTest.new_set()
local child = Helpers.new_child_neovim()

T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      Helpers.setup_child(child, [[{ editor = { type = "overlay" } }]])
    end,
    post_once = child.stop,
  },
})

T["overlay.open()"] = MiniTest.new_set()

T["overlay keymaps"] = MiniTest.new_set()

T["overlay keymaps"]["skips terminal names outside allowlist"] = function()
  child.cmd("terminal /bin/sh")
  child.wait(100)
  MiniTest.expect.equality(Helpers.has_terminal_esc_mapping(child), false)
end

T["overlay keymaps"]["allows configured terminal name pattern"] = function()
  Helpers.setup_child(
    child,
    [=[{ editor = { type = "overlay", terminal_name_pattern = [[/bin/sh]] } }]=]
  )
  child.cmd("terminal /bin/sh")
  Helpers.wait_until(child, function()
    return Helpers.has_terminal_esc_mapping(child)
  end)
  MiniTest.expect.equality(Helpers.has_terminal_esc_mapping(child), true)
end

local function open_overlay(command)
  local buf = Helpers.open_shell(child)
  local target_win = child.api.nvim_get_current_win()
  child.lua([[require("termline").clear_command(...)]], { buf })
  child.lua([[require("termline").write_command(...)]], { command, buf })
  Helpers.wait_for_read_command(child, buf, command)
  child.lua([[require("termline.editors.overlay").open(...)]], {
    { target_buf = buf, target_win = target_win },
  })
  return buf
end

local function enter_overlay_normal_mode()
  child.api.nvim_input("<Esc>")
  Helpers.wait_for_mode(child, "n")
end

local function current_window_topline()
  return child.lua_get([[(function()
    return vim.fn.line("w0")
  end)()]])
end

T["overlay.open()"]["opens a floating window"] = function()
  open_overlay("echo popup")
  local config = child.api.nvim_win_get_config(0)
  MiniTest.expect.equality(config.relative, "editor")
end

T["overlay.open()"]["renders prompt between OSC133;A and OSC133;B"] = function()
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
  child.lua([[require("termline.editors.overlay").open(...)]], {
    { target_buf = buf, target_win = child.api.nvim_get_current_win() },
  })

  MiniTest.expect.equality(child.api.nvim_get_current_line(), prompt .. "echo hello")
end

T["overlay.open()"]["renders prompt from terminal state"] = function()
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

T["overlay.open()"]["clears zsh tab suggestions"] = function()
  local buf = Helpers.open_shell(child)
  child.cmd("startinsert")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("ls <Tab>")
  Helpers.wait_until(child, function()
    return child
      .lua_get([[table.concat(vim.api.nvim_buf_get_lines(..., 0, -1, false), "\n")]], { buf })
      :match("README%.md") ~= nil
  end)
  child.api.nvim_input("<Esc>")
  Helpers.wait_until(child, function()
    return child.api.nvim_get_option_value("buftype", { buf = 0 }) == "prompt"
  end)
  Helpers.wait_until(child, function()
    return child
      .lua_get([[table.concat(vim.api.nvim_buf_get_lines(..., 0, -1, false), "\n")]], { buf })
      :match("README%.md") == nil
  end)
end

T["overlay.open()"]["tab pass-through returns to terminal insert mode"] = function()
  local buf = Helpers.open_shell(child)
  child.cmd("startinsert")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("<Esc>")
  Helpers.wait_until(child, function()
    return child.api.nvim_get_option_value("buftype", { buf = 0 }) == "prompt"
  end)
  child.api.nvim_input("acat R<Tab>")
  Helpers.wait_until(child, function()
    return child.api.nvim_get_current_buf() == buf
  end)
  Helpers.wait_for_mode(child, "t")
end

T["overlay.open()"]["submit returns to terminal mode"] = function()
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

T["overlay.open()"]["insert submit returns to terminal mode"] = function()
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

T["overlay.open()"]["echo hello world esc bbdw cr outputs world"] = function()
  local buf = Helpers.open_shell(child)
  child.cmd("startinsert")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("echo hello world")
  Helpers.wait_for_read_command(child, buf, "echo hello world")
  child.api.nvim_input("<Esc>")
  Helpers.wait_until(child, function()
    return child.api.nvim_get_option_value("buftype", { buf = 0 }) == "prompt"
  end)
  child.api.nvim_input("bbdw<CR>")
  Helpers.wait_until(child, function()
    return child.api.nvim_get_current_buf() == buf
  end)
  Helpers.wait_for_shell_output(child, buf, "world")
end

T["overlay.open()"]["k esc ends in normal mode"] = function()
  local buf = Helpers.open_shell(child)
  child.cmd("startinsert")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("echo hello world")
  Helpers.wait_for_read_command(child, buf, "echo hello world")
  enter_overlay_normal_mode()
  child.api.nvim_input("k")
  Helpers.wait_until(child, function()
    return child.api.nvim_get_current_buf() == buf
  end)
  Helpers.wait_until(child, function()
    return child.lua_get("vim.api.nvim_get_mode().mode"):match("^n") ~= nil
  end)
end

T["overlay.open()"]["esc then { on wrapped command stays right after prompt"] = function()
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

T["overlay.open()"]["opens at command end when terminal cursor is before prompt"] = function()
  local command = "echo hello world"
  local buf = Helpers.open_shell(child)
  local target_win = child.api.nvim_get_current_win()
  child.lua([[require("termline").clear_command(...)]], { buf })
  child.lua([[require("termline").write_command(...)]], { command, buf })
  Helpers.wait_for_read_command(child, buf, command)
  child.set_cursor(1, 0, target_win)
  child.lua([[require("termline.editors.overlay").open(...)]], {
    { target_buf = buf, target_win = target_win },
  })
  MiniTest.expect.equality(child.lua_get("vim.api.nvim_win_get_cursor(0)[2]"), #"$ " + #command - 1)
end

T["overlay.open()"]["keeps first line visible after first newline"] = function()
  open_overlay("echo hello world")
  enter_overlay_normal_mode()
  child.api.nvim_input("A<S-CR>")
  Helpers.wait_until(child, function()
    return #child.api.nvim_buf_get_lines(0, 0, -1, false) == 2
  end)
  MiniTest.expect.equality(child.api.nvim_win_get_config(0).height, 2)
  MiniTest.expect.equality(child.api.nvim_buf_get_lines(0, 0, -1, false)[1], "$ echo hello world")
  MiniTest.expect.equality(current_window_topline(), 1)
end

T["overlay.open()"]["closes on first-line k"] = function()
  local buf = open_overlay("echo popup")
  enter_overlay_normal_mode()
  child.api.nvim_input("k")
  child.wait(100)
  MiniTest.expect.equality(child.api.nvim_get_current_buf(), buf)
end

T["overlay.open()"]["k stays inside overlay off first visual line"] = function()
  local buf = open_overlay(string.rep("x", 120))
  local overlay_buf = child.api.nvim_get_current_buf()
  enter_overlay_normal_mode()
  child.api.nvim_input("j")
  child.api.nvim_input("k")
  child.wait(100)
  MiniTest.expect.equality(child.api.nvim_get_current_buf(), overlay_buf)
  MiniTest.expect.equality(child.api.nvim_win_get_buf(0), overlay_buf)
end

T["overlay.open()"]["closes on first-line {"] = function()
  local buf = open_overlay("echo popup")
  enter_overlay_normal_mode()
  child.api.nvim_input("{")
  child.wait(100)
  MiniTest.expect.equality(child.api.nvim_get_current_buf(), buf)
end

T["overlay.open()"]["closes on first-line normal pass-through keys"] = function()
  local keys = { "{", "<C-u>", "gg", "H" }
  for _, key in ipairs(keys) do
    local buf = open_overlay("echo popup")
    enter_overlay_normal_mode()
    child.api.nvim_input(key)
    child.wait(100)
    MiniTest.expect.equality(child.api.nvim_get_current_buf(), buf)
  end
end

T["overlay.open()"]["first-line pass-through uses first visual line"] = function()
  local buf = open_overlay(string.rep("x", 120))
  local overlay_buf = child.api.nvim_get_current_buf()
  enter_overlay_normal_mode()
  child.api.nvim_input("j")
  child.api.nvim_input("{")
  child.wait(100)
  MiniTest.expect.equality(child.api.nvim_get_current_buf(), overlay_buf)
  MiniTest.expect.equality(child.api.nvim_win_get_buf(0), overlay_buf)
end

T["overlay.open()"]["closes on normal pass-through keys"] = function()
  local keys = { "}", "<C-d>", "<C-b>", "<C-f>", "G", "L" }
  for _, key in ipairs(keys) do
    local buf = open_overlay("echo popup")
    enter_overlay_normal_mode()
    child.api.nvim_input("j")
    child.api.nvim_input(key)
    child.wait(100)
    MiniTest.expect.equality(child.api.nvim_get_current_buf(), buf)
  end
end

return T
