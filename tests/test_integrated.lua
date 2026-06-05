local Helpers = require("tests.helpers")
local T = MiniTest.new_set()
local child = Helpers.new_child_neovim()

local function get_editor_state(buf, win)
  return {
    command = child.lua_get([[require("termline").read_command(...)]], { buf }),
    cursor = child.lua_get([=[require("termline").command_cursor(...)[2]]=], { win, buf }),
  }
end

local function expect_state_eq(got, expected)
  if got.command ~= expected.command then
    error(
      string.format(
        "state command mismatch\nexpected: %s\ngot:      %s\nstate:    %s",
        vim.inspect(expected.command),
        vim.inspect(got.command),
        vim.inspect(got)
      )
    )
  end
  if expected.cursor ~= nil and got.cursor ~= expected.cursor then
    error(
      string.format(
        "state cursor mismatch\nexpected: %s\ngot:      %s\nstate:    %s",
        vim.inspect(expected.cursor),
        vim.inspect(got.cursor),
        vim.inspect(got)
      )
    )
  end
end

T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      Helpers.setup_child(child, [[{ editor = { type = "integrated", open = "<Esc>" } }]])
    end,
    post_once = child.stop,
  },
})

T["integrated.open()"] = MiniTest.new_set()

T["integrated keymaps"] = MiniTest.new_set()

T["integrated keymaps"]["skips terminal names outside allowlist"] = function()
  child.cmd("terminal /bin/sh")
  child.wait(100)
  MiniTest.expect.equality(Helpers.has_terminal_esc_mapping(child), false)
end

T["integrated keymaps"]["allows configured terminal name pattern"] = function()
  Helpers.setup_child(
    child,
    [=[{ editor = { type = "integrated", open = "<Esc>", terminal_name_pattern = [[/bin/sh]] } }]=]
  )
  child.cmd("terminal /bin/sh")
  Helpers.wait_until(child, function()
    return Helpers.has_terminal_esc_mapping(child)
  end)
  MiniTest.expect.equality(Helpers.has_terminal_esc_mapping(child), true)
end

T["integrated.open()"]["makes terminal buffer modifiable"] = function()
  local buf = Helpers.open_shell(child)
  local win = child.api.nvim_get_current_win()

  MiniTest.expect.equality(child.api.nvim_get_option_value("modifiable", { buf = buf }), false)
  child.lua([[require("termline.editors.integrated").open(...)]], {
    { target_buf = buf, target_win = win },
  })
  MiniTest.expect.equality(child.api.nvim_get_option_value("modifiable", { buf = buf }), true)
end

T["integrated.open()"]["caches shell command on open"] = function()
  local buf = Helpers.open_shell(child)
  local win = child.api.nvim_get_current_win()
  child.cmd("startinsert")
  child.api.nvim_input("echo old")
  Helpers.wait_for_read_command(child, buf, "echo old")
  child.lua([[require("termline.editors.integrated").open(...)]], {
    { target_buf = buf, target_win = win },
  })
  MiniTest.expect.equality(
    child.lua_get([=[require("termline.api").buffers[...].shell_state.command]=], { buf }),
    "echo old"
  )
end

-- T["integrated.open()"]["<Esc> opens edit mode and i enters insert mode"] = function()
--   local buf = Helpers.open_shell(child)
--   child.cmd("startinsert")
--   Helpers.wait_for_mode(child, "t")
--   child.api.nvim_input("<Esc>")
--   Helpers.wait_for_mode(child, "n")
--   MiniTest.expect.equality(child.api.nvim_get_option_value("modifiable", { buf = buf }), true)
--   child.api.nvim_input("i")
--   Helpers.wait_for_mode(child, "i")
-- end

T["integrated write"] = MiniTest.new_set()

-- T["integrated A"]["bbdw"] = function()
--   local buf = Helpers.open_shell(child)
--   child.cmd("startinsert")
--   Helpers.wait_until(child, function()
--     return child.lua_get("vim.api.nvim_get_mode().mode") == "t"
--   end)
--   child.api.nvim_input("echo hello world")
--   Helpers.wait_for_read_command(child, buf, "echo hello world")
--   child.api.nvim_input("<Esc>")
--   child.api.nvim_input("bbdwA")
--   Helpers.wait_until(child, function()
--     return child.lua_get("vim.api.nvim_get_mode().mode") == "t"
--   end)
--   child.api.nvim_input("a")
--   Helpers.wait_for_read_command(child, buf, "echo worlda")
-- end

-- T["integrated A"]["bdw"] = function()
--   local buf = Helpers.open_shell(child)
--   child.cmd("startinsert")
--   Helpers.wait_until(child, function()
--     return child.lua_get("vim.api.nvim_get_mode().mode") == "t"
--   end)
--   child.api.nvim_input("echo hello world")
--   Helpers.wait_for_read_command(child, buf, "echo hello world")
--   child.api.nvim_input("<Esc>")
--   child.api.nvim_input("bdwA")
--   Helpers.wait_until(child, function()
--     return child.lua_get("vim.api.nvim_get_mode().mode") == "t"
--   end)
--   child.api.nvim_input("a")
--   Helpers.wait_for_read_command(child, buf, "echo helloa")
-- end

T["integrated write"]["syncs cursor-only changes into shell"] = function()
  local buf = Helpers.open_shell(child)
  local win = child.api.nvim_get_current_win()
  local ctx = { target_buf = buf, target_win = win }
  child.lua([[require("termline").write_command(...)]], { "echo old", buf })
  Helpers.wait_for_read_command(child, buf, "echo old")
  child.lua([[require("termline.editors.integrated").open(...)]], {
    ctx,
  })
  child.api.nvim_win_set_cursor(win, { child.get_cursor(win)[1], 8 })
  local target_cursor =
    child.lua_get([=[require("termline").command_cursor(...)[2]]=], { win, buf })
  child.lua([[require("termline.editors.integrated").write(...)]], { ctx })
  Helpers.wait_until(child, function()
    return child.lua_get([=[require("termline").command_cursor(...)[2]]=], { win, buf })
      == target_cursor
  end)
end

T["integrated write"]["syncs edited command into shell"] = function()
  local buf = Helpers.open_shell(child)
  local win = child.api.nvim_get_current_win()
  local ctx = { target_buf = buf, target_win = win }
  child.lua([[require("termline").write_command(...)]], { "echo old", buf })
  Helpers.wait_for_read_command(child, buf, "echo old")
  child.lua([[require("termline.editors.integrated").open(...)]], {
    ctx,
  })
  local row = child.get_cursor(win)[1]
  child.api.nvim_buf_set_text(buf, row - 1, 7, row - 1, 10, { "new" })
  child.lua([[require("termline.editors.integrated").write(...)]], { ctx })
  Helpers.wait_until(child, function()
    return child.lua_get([[require("termline").read_command(...)]], { buf }) == "echo new"
  end)
end

T["integrated write"]["clears deleted text after bdb and C-s"] = function()
  local buf = Helpers.open_shell(child)
  local win = child.api.nvim_get_current_win()
  local ctx = { target_buf = buf, target_win = win }
  child.cmd("startinsert")
  Helpers.wait_until(child, function()
    return child.lua_get("vim.api.nvim_get_mode().mode") == "t"
  end)
  child.api.nvim_input("echo hello world")
  Helpers.wait_for_read_command(child, buf, "echo hello world")
  child.api.nvim_input("<Esc>")
  Helpers.wait_until(child, function()
    return child.api.nvim_get_option_value("modifiable", { buf = buf })
  end)
  child.api.nvim_input("bdb")
  MiniTest.expect.equality(child.api.nvim_get_current_line(), "$ echo world")
  child.lua([[require("termline.editors.integrated").write(...)]], { ctx })
  Helpers.wait_for_read_command(child, buf, "echo world")
  expect_state_eq(get_editor_state(buf, win), { command = "echo world", cursor = nil })
end

T["integrated keys"] = MiniTest.new_set()

T["integrated keys"]["<Up> syncs and returns to terminal mode"] = function()
  local buf = Helpers.open_shell(child)
  local win = child.api.nvim_get_current_win()
  local ctx = { target_buf = buf, target_win = win }
  child.lua([[require("termline").write_command(...)]], { "echo old", buf })
  Helpers.wait_for_read_command(child, buf, "echo old")
  child.lua([[require("termline.editors.integrated").open(...)]], { ctx })
  local row = child.get_cursor(win)[1]
  child.api.nvim_buf_set_text(buf, row - 1, 7, row - 1, 10, { "new" })
  child.api.nvim_input("<Up>")
  Helpers.wait_until(child, function()
    return not child.api.nvim_get_option_value("modifiable", { buf = buf })
  end)
  Helpers.wait_for_mode(child, "t")
  Helpers.wait_for_read_command(child, buf, "echo new")
end

T["integrated keys"]["<Tab> syncs and returns to terminal mode"] = function()
  local buf = Helpers.open_shell(child)
  local win = child.api.nvim_get_current_win()
  local ctx = { target_buf = buf, target_win = win }
  child.lua([[require("termline").write_command(...)]], { "echo old", buf })
  Helpers.wait_for_read_command(child, buf, "echo old")
  child.lua([[require("termline.editors.integrated").open(...)]], { ctx })
  local row = child.get_cursor(win)[1]
  child.api.nvim_buf_set_text(buf, row - 1, 7, row - 1, 10, { "new" })
  child.api.nvim_input("<Tab>")
  Helpers.wait_until(child, function()
    return not child.api.nvim_get_option_value("modifiable", { buf = buf })
  end)
  Helpers.wait_for_mode(child, "t")
  Helpers.wait_for_read_command(child, buf, "echo new")
end

T["integrated keys"]["<CR> syncs and submits command"] = function()
  local buf = Helpers.open_shell(child)
  local win = child.api.nvim_get_current_win()
  local ctx = { target_buf = buf, target_win = win }
  child.lua([[require("termline").write_command(...)]], { "echo old", buf })
  Helpers.wait_for_read_command(child, buf, "echo old")
  child.lua([[require("termline.editors.integrated").open(...)]], { ctx })
  local row = child.get_cursor(win)[1]
  child.api.nvim_buf_set_text(buf, row - 1, 7, row - 1, 10, { "new" })
  child.api.nvim_input("<CR>")
  Helpers.wait_until(child, function()
    return not child.api.nvim_get_option_value("modifiable", { buf = buf })
  end)
  Helpers.wait_for_mode(child, "t")
  Helpers.wait_for_shell_output(child, buf, "new")
end

T["integrated keys"]["<C-s> syncs and keeps integrated mode open"] = function()
  local buf = Helpers.open_shell(child)
  local win = child.api.nvim_get_current_win()
  local ctx = { target_buf = buf, target_win = win }
  child.lua([[require("termline").write_command(...)]], { "echo old", buf })
  Helpers.wait_for_read_command(child, buf, "echo old")
  child.lua([[require("termline.editors.integrated").open(...)]], { ctx })
  local row = child.get_cursor(win)[1]
  child.api.nvim_buf_set_text(buf, row - 1, 7, row - 1, 10, { "new" })
  MiniTest.expect.equality(
    child.lua_get([=[require("termline.api").buffers[...].shell_state.command]=], { buf }),
    "echo old"
  )
  child.api.nvim_input("<C-s>")
  Helpers.wait_until(child, function()
    return child.lua_get([=[require("termline.api").buffers[...].shell_state.command]=], { buf })
      == "echo new"
  end)
  MiniTest.expect.equality(child.api.nvim_get_option_value("modifiable", { buf = buf }), true)
end

return T
