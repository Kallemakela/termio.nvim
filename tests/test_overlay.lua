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
  MiniTest.expect.equality(child.lua_get("vim.api.nvim_win_get_cursor(0)[2]"), #command - 1)
end

T["overlay.open()"]["keeps first line visible after first newline"] = function()
  open_overlay("echo hello world")
  child.api.nvim_input("A<S-CR>")
  Helpers.wait_until(child, function()
    return #child.api.nvim_buf_get_lines(0, 0, -1, false) == 2
  end)
  MiniTest.expect.equality(child.api.nvim_win_get_config(0).height, 2)
  MiniTest.expect.equality(child.api.nvim_buf_get_lines(0, 0, -1, false)[1], "echo hello world")
  MiniTest.expect.equality(current_window_topline(), 1)
end

T["overlay.open()"]["closes on first-line k"] = function()
  local buf = open_overlay("echo popup")
  child.api.nvim_input("k")
  child.wait(100)
  MiniTest.expect.equality(child.api.nvim_get_current_buf(), buf)
end

T["overlay.open()"]["k stays inside overlay off first visual line"] = function()
  local buf = open_overlay(string.rep("x", 120))
  local overlay_buf = child.api.nvim_get_current_buf()
  child.api.nvim_input("j")
  child.api.nvim_input("k")
  child.wait(100)
  MiniTest.expect.equality(child.api.nvim_get_current_buf(), overlay_buf)
  MiniTest.expect.equality(child.api.nvim_win_get_buf(0), overlay_buf)
end

T["overlay.open()"]["closes on first-line {"] = function()
  local buf = open_overlay("echo popup")
  child.api.nvim_input("{")
  child.wait(100)
  MiniTest.expect.equality(child.api.nvim_get_current_buf(), buf)
end

T["overlay.open()"]["closes on first-line normal pass-through keys"] = function()
  local keys = { "{", "<C-u>", "gg", "H" }
  for _, key in ipairs(keys) do
    local buf = open_overlay("echo popup")
    child.api.nvim_input(key)
    child.wait(100)
    MiniTest.expect.equality(child.api.nvim_get_current_buf(), buf)
  end
end

T["overlay.open()"]["first-line pass-through uses first visual line"] = function()
  local buf = open_overlay(string.rep("x", 120))
  local overlay_buf = child.api.nvim_get_current_buf()
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
    child.api.nvim_input("j")
    child.api.nvim_input(key)
    child.wait(100)
    MiniTest.expect.equality(child.api.nvim_get_current_buf(), buf)
  end
end

return T
