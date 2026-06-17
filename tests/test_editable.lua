local Helpers = require("tests.helpers")
local T = MiniTest.new_set()
local child = Helpers.new_child_neovim()

T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      Helpers.setup_child(child, [[{ editor = { type = "editable" } }]])
      child.set_size(24, 80)
    end,
    post_once = child.stop,
  },
})

T["editable edit"] = MiniTest.new_set()

T["editable keymaps"] = MiniTest.new_set()

T["editable keymaps"]["skips terminal names outside allowlist"] = function()
  child.cmd("terminal /bin/sh")
  child.wait(100)
  MiniTest.expect.equality(Helpers.has_terminal_esc_mapping(child), false)
end

T["editable keymaps"]["allows configured terminal name pattern"] = function()
  Helpers.setup_child(
    child,
    [=[{ editor = { type = "editable", terminal_name_pattern = [[/bin/sh]] } }]=]
  )
  child.cmd("terminal /bin/sh")
  Helpers.wait_until(child, function()
    return Helpers.has_terminal_esc_mapping(child)
  end)
  MiniTest.expect.equality(Helpers.has_terminal_esc_mapping(child), true)
end

local function enter_editable_normal_mode(buf)
  child.api.nvim_input("<Esc>")
  Helpers.wait_for_mode(child, "nt")
  Helpers.wait_until(child, function()
    return child.api.nvim_get_option_value("modifiable", { buf = buf })
  end)
end

local function get_command_cursor(buf)
  local win = child.api.nvim_get_current_win()
  return child.lua_get([=[require("termio.api").command_cursor(...)[2]]=], { win, buf })
end

local function read_editable_command(buf)
  return child.lua_get([[require("termio.editors.editable").read_command(...)]], { buf })
end

T["editable edit"]["open key leaves terminal mode"] = function()
  local buf = Helpers.open_shell(child)
  child.cmd("startinsert")
  Helpers.wait_for_mode(child, "t")
  enter_editable_normal_mode(buf)
  MiniTest.expect.equality(child.lua_get("vim.api.nvim_get_mode().mode"), "nt")
end

T["editable edit"]["open key stays in terminal mode when disabled"] = function()
  Helpers.setup_child(
    child,
    [[{ editor = { type = "editable", is_disabled = function(buf) return vim.b[buf].term_tui_active == true end } }]]
  )
  local buf = Helpers.open_shell(child)
  child.lua([[vim.b[...].term_tui_active = true]], { buf })
  child.cmd("startinsert")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("<Esc>")
  child.wait(100)
  MiniTest.expect.equality(child.lua_get("vim.api.nvim_get_mode().mode"), "t")
end

T["editable edit"]["open returns false when disabled"] = function()
  Helpers.setup_child(
    child,
    [[{ editor = { type = "editable", is_disabled = function() return true end } }]]
  )
  local buf = Helpers.open_shell(child)
  MiniTest.expect.equality(
    child.lua_get([[require("termio.editors.editable").open({ target_buf = ... })]], { buf }),
    false
  )
end

T["editable edit"]["disable stops editor open"] = function()
  local buf = Helpers.open_shell(child)
  child.lua([[require("termio").disable()]])
  MiniTest.expect.equality(
    child.lua_get([[require("termio.editors.editable").open({ target_buf = ... })]], { buf }),
    false
  )
end

T["editable edit"]["open stores current shell state"] = function()
  local buf = Helpers.open_shell(child)
  child.cmd("startinsert")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("echo hello world")
  Helpers.wait_for_read_command(child, buf, "echo hello world")
  child.lua([[require("termio.editors.editable").open({ target_buf = ... })]], { buf })
  MiniTest.expect.equality(
    child.lua_get([[require("termio.api").buffers[...] .shell_state.command]], { buf }),
    "echo hello world"
  )
  MiniTest.expect.equality(
    child.lua_get([[require("termio.api").buffers[...] .shell_state.cursor]], { buf }),
    16
  )
end

T["editable edit"]["open keeps bash cursor at command end"] = function()
  local buf = Helpers.open_shell(child, "$ ", "bash")
  child.cmd("startinsert")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("echo hello world<Esc>")
  Helpers.wait_for_mode(child, "nt")
  MiniTest.expect.equality(get_command_cursor(buf), 15)
end

T["editable edit"]["open keeps bash cursor on wrapped command end"] = function()
  local buf = Helpers.open_shell(child, "$ ", "bash")
  local command = "echo " .. string.rep("lorem ipsum ", 16)
  child.cmd("startinsert")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input(command)
  Helpers.wait_for_read_command(child, buf, command)
  child.api.nvim_input("<Esc>")
  Helpers.wait_for_mode(child, "nt")
  Helpers.wait_until(child, function()
    return child.api.nvim_get_option_value("modifiable", { buf = buf })
  end)
  MiniTest.expect.equality(get_command_cursor(buf), #command - 1)
  MiniTest.expect.equality(child.api.nvim_win_get_cursor(0)[1] > 1, true)
end

T["editable edit"]["open keeps bash cursor inside command"] = function()
  local buf = Helpers.open_shell(child, "$ ", "bash")
  child.cmd("startinsert")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("echo hello world<Left><Left><Left><Esc>")
  Helpers.wait_for_mode(child, "nt")
  MiniTest.expect.equality(get_command_cursor(buf), 13)
end

T["editable edit"]["open clears zsh tab suggestions"] = function()
  local buf = Helpers.open_shell(child, "$ ", "zsh")
  child.cmd("startinsert")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("ls <Tab>")
  Helpers.wait_until(child, function()
    return child
      .lua_get([[table.concat(vim.api.nvim_buf_get_lines(..., 0, -1, false), "\n")]], { buf })
      :match("README%.md") ~= nil
  end)
  child.api.nvim_input("<Esc>")
  Helpers.wait_for_mode(child, "nt")
  Helpers.wait_until(child, function()
    return child
      .lua_get([[table.concat(vim.api.nvim_buf_get_lines(..., 0, -1, false), "\n")]], { buf })
      :match("README%.md") == nil
  end)
end

T["editable edit"]["submit runs command in normal mode and enters insert mode"] = function()
  local buf = Helpers.open_shell(child)
  child.cmd("startinsert")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("echo normal")
  Helpers.wait_for_read_command(child, buf, "echo normal")
  enter_editable_normal_mode(buf)
  child.api.nvim_input("<CR>")
  Helpers.wait_for_shell_output(child, buf, "normal")
  Helpers.wait_for_mode(child, "t")
end

T["editable edit"]["submit runs command in insert mode"] = function()
  local buf = Helpers.open_shell(child)
  child.cmd("startinsert")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("echo insert<CR>")
  Helpers.wait_for_shell_output(child, buf, "insert")
end

T["editable edit"]["bbcw updates read_command"] = function()
  local buf = Helpers.open_shell(child)
  child.cmd("startinsert")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("echo hello world")
  Helpers.wait_for_read_command(child, buf, "echo hello world")
  enter_editable_normal_mode(buf)
  child.api.nvim_input("bbcwgoodbye<Esc>")
  Helpers.wait_for_read_command(child, buf, "echo goodbye world")
end

T["editable edit"]["bbvec text change keeps editor draft"] = function()
  local buf = Helpers.open_shell(child)
  child.cmd("startinsert")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("echo hello world<Esc>")
  Helpers.wait_for_read_command(child, buf, "echo hello world")
  Helpers.wait_for_mode(child, "nt")
  Helpers.wait_until(child, function()
    return child.api.nvim_get_option_value("modifiable", { buf = buf })
  end)
  child.api.nvim_input("bbvec")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("googbye")
  Helpers.wait_for_editable_command(child, buf, "echo googbye world")
end

T["editable edit"]["bbce text change keeps editor draft"] = function()
  local buf = Helpers.open_shell(child)
  child.cmd("startinsert")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("echo hello world<Esc>")
  Helpers.wait_for_read_command(child, buf, "echo hello world")
  Helpers.wait_for_mode(child, "nt")
  Helpers.wait_until(child, function()
    return child.api.nvim_get_option_value("modifiable", { buf = buf })
  end)
  child.api.nvim_input("bbce")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("googbye")
  Helpers.wait_for_editable_command(child, buf, "echo googbye world")
end

T["editable edit"]["bbC changes to command end"] = function()
  local buf = Helpers.open_shell(child)
  child.cmd("startinsert")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("echo hello world")
  Helpers.wait_for_read_command(child, buf, "echo hello world")
  enter_editable_normal_mode(buf)
  child.api.nvim_input("bbC")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("goodbye")
  Helpers.wait_for_read_command(child, buf, "echo goodbye")
end

T["editable edit"]["bbved deletes visual selection from editor draft"] = function()
  local buf = Helpers.open_shell(child)
  child.cmd("startinsert")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("echo hello world<Esc>")
  Helpers.wait_for_read_command(child, buf, "echo hello world")
  Helpers.wait_for_mode(child, "nt")
  Helpers.wait_until(child, function()
    return child.api.nvim_get_option_value("modifiable", { buf = buf })
  end)
  child.api.nvim_input("bbved")
  MiniTest.expect.equality(read_editable_command(buf), "echo  world")
end

T["editable edit"]["bbcw<Esc> updates command"] = function()
  local buf = Helpers.open_shell(child)
  local command = "echo hello world there friend"
  child.cmd("startinsert")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input(command)
  Helpers.wait_for_read_command(child, buf, command)
  enter_editable_normal_mode(buf)
  child.api.nvim_input("bbcw<Esc>")
  Helpers.wait_for_read_command(child, buf, "echo hello world  friend")
end

T["editable edit"]["visual delete from wrapped command keeps last word"] = function()
  local buf = Helpers.open_shell(child)
  local last_word = "omega"
  local command = "echo lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor incididunt ut labore et dolore magna aliqua "
    .. last_word
  child.cmd("startinsert")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input(command)
  Helpers.wait_for_read_command(child, buf, command)
  child.api.nvim_input("<Esc>bbev[[EEbhd")
  Helpers.wait_for_mode(child, "nt")
  Helpers.wait_until(child, function()
    return child.api.nvim_get_option_value("modifiable", { buf = buf })
  end)
  Helpers.wait_for_editable_command(child, buf, "echo " .. last_word)
end

T["editable edit"]["visual change from wrapped command keeps last word"] = function()
  local buf = Helpers.open_shell(child)
  local last_word = "omega"
  local command = "echo lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor incididunt ut labore et dolore magna aliqua "
    .. last_word
  child.cmd("startinsert")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input(command)
  Helpers.wait_for_read_command(child, buf, command)
  child.api.nvim_input("<Esc>bbev[[EEbhc")
  Helpers.wait_for_mode(child, "t")
  Helpers.wait_for_read_command(child, buf, "echo " .. last_word)
end

T["editable edit"]["bbdw updates editor draft and stays in normal mode"] = function()
  local buf = Helpers.open_shell(child)
  child.cmd("startinsert")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("echo hello world")
  Helpers.wait_for_read_command(child, buf, "echo hello world")
  enter_editable_normal_mode(buf)
  child.api.nvim_input("bbdw")
  MiniTest.expect.equality(read_editable_command(buf), "echo world")
  MiniTest.expect.equality(
    child.lua_get([[require("termio").read_command(...)]], { buf }),
    "echo hello world"
  )
  MiniTest.expect.equality(child.lua_get("vim.api.nvim_get_mode().mode"), "nt")
end

T["editable edit"]["bbdw<C-s> syncs editor draft to shell state"] = function()
  local buf = Helpers.open_shell(child)
  child.cmd("startinsert")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("echo hello world")
  Helpers.wait_for_read_command(child, buf, "echo hello world")
  enter_editable_normal_mode(buf)
  child.api.nvim_input("bbdw<C-s>")
  Helpers.wait_for_read_command(child, buf, "echo world")
end

T["editable edit"]["bbdwwvep keeps edited draft"] = function()
  local buf = Helpers.open_shell(child)
  child.cmd("startinsert")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("echo hello world")
  Helpers.wait_for_read_command(child, buf, "echo hello world")
  enter_editable_normal_mode(buf)
  child.api.nvim_input("bbdwwvep")
  Helpers.wait_for_editable_command(child, buf, "echo hello")
end

T["editable edit"]["bbdwi keeps deleted command state"] = function()
  local buf = Helpers.open_shell(child)
  child.cmd("startinsert")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("echo hello world")
  Helpers.wait_for_read_command(child, buf, "echo hello world")
  enter_editable_normal_mode(buf)
  child.api.nvim_input("bbdw")
  MiniTest.expect.equality(read_editable_command(buf), "echo world")
  child.api.nvim_input("i")
  Helpers.wait_for_mode(child, "t")
  child.wait(100)
  Helpers.wait_for_read_command(child, buf, "echo world")
end

T["editable edit"]["bbdwi enters insert at correct spot"] = function()
  local buf = Helpers.open_shell(child)
  child.cmd("startinsert")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("echo hello world")
  Helpers.wait_for_read_command(child, buf, "echo hello world")
  enter_editable_normal_mode(buf)
  child.api.nvim_input("bbdw")
  MiniTest.expect.equality(read_editable_command(buf), "echo world")
  child.api.nvim_input("i")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("!")
  Helpers.wait_for_read_command(child, buf, "echo !world")
end

T["editable edit"]["bbdwa enters insert at correct spot"] = function()
  local buf = Helpers.open_shell(child)
  child.cmd("startinsert")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("echo hello world")
  Helpers.wait_for_read_command(child, buf, "echo hello world")
  enter_editable_normal_mode(buf)
  child.api.nvim_input("bbdw")
  MiniTest.expect.equality(read_editable_command(buf), "echo world")
  child.api.nvim_input("a")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("!")
  Helpers.wait_for_read_command(child, buf, "echo w!orld")
end

T["editable edit"]["a on empty command inserts typed text instead of cursor"] = function()
  local buf = Helpers.open_shell(child)
  child.cmd("startinsert")
  Helpers.wait_for_mode(child, "t")
  enter_editable_normal_mode(buf)
  child.api.nvim_input("a >")
  Helpers.wait_for_read_command(child, buf, " >")
end

T["editable edit"]["bbdwI enters insert at command start"] = function()
  local buf = Helpers.open_shell(child)
  child.cmd("startinsert")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("echo hello world")
  Helpers.wait_for_read_command(child, buf, "echo hello world")
  enter_editable_normal_mode(buf)
  child.api.nvim_input("bbdw")
  MiniTest.expect.equality(read_editable_command(buf), "echo world")
  child.api.nvim_input("I")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("!")
  Helpers.wait_for_read_command(child, buf, "!echo world")
end

T["editable edit"]["bbdwA enters insert at command end"] = function()
  local buf = Helpers.open_shell(child)
  child.cmd("startinsert")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("echo hello world")
  Helpers.wait_for_read_command(child, buf, "echo hello world")
  enter_editable_normal_mode(buf)
  child.api.nvim_input("bbdw")
  MiniTest.expect.equality(read_editable_command(buf), "echo world")
  child.api.nvim_input("A")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("!")
  Helpers.wait_for_read_command(child, buf, "echo world!")
end

T["editable edit"]["bxxx defers shell sync until insert"] = function()
  local buf = Helpers.open_shell(child)
  child.cmd("startinsert")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("echo hello world")
  Helpers.wait_for_read_command(child, buf, "echo hello world")
  enter_editable_normal_mode(buf)
  child.api.nvim_input("bxxx")
  MiniTest.expect.equality(read_editable_command(buf), "echo hello ld")
  MiniTest.expect.equality(
    child.lua_get([[require("termio.api").buffers[...] .shell_state.command]], { buf }),
    "echo hello world"
  )
  child.api.nvim_input("i")
  Helpers.wait_for_mode(child, "t")
  Helpers.wait_for_read_command(child, buf, "echo hello ld")
  MiniTest.expect.equality(
    child.lua_get([[require("termio.api").buffers[...] .shell_state.command]], { buf }),
    "echo hello ld"
  )
end

T["editable edit"]["xp keeps paste in editor draft"] = function()
  local buf = Helpers.open_shell(child)
  child.cmd("startinsert")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("hello")
  Helpers.wait_for_read_command(child, buf, "hello")
  enter_editable_normal_mode(buf)
  child.api.nvim_input("x")
  Helpers.wait_for_editable_command(child, buf, "hell")
  child.api.nvim_input("p")
  Helpers.wait_for_editable_command(child, buf, "hello")
  child.api.nvim_input("x")
  Helpers.wait_for_editable_command(child, buf, "hell")
  child.api.nvim_input("p")
  Helpers.wait_for_editable_command(child, buf, "hello")
end

T["editable edit"]["dj on wrapped command does not sync shell state"] = function()
  local buf = Helpers.open_shell(child)
  local command =
    "echo lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor incididunt ut labore et dolore magna aliqua ut enim ad minim veniam quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur excepteur sint occaecat cupidatat non proident sunt in culpa qui officia deserunt mollit anim id est laborum lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor incididunt ut labore et dolore magna aliqua ut enim ad minim veniam quis nostrud exercitation ullamco laboris nisi"
  child.set_size(24, 80)
  child.cmd("startinsert")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input(command)
  Helpers.wait_for_read_command(child, buf, command)
  enter_editable_normal_mode(buf)
  child.api.nvim_input("dj")
  MiniTest.expect.equality(child.lua_get([[require("termio").read_command(...)]], { buf }), command)
  MiniTest.expect.equality(child.lua_get("vim.api.nvim_get_mode().mode"), "nt")
  MiniTest.expect.equality(
    child.lua_get([[require("termio.api").buffers[...] .shell_state.command]], { buf }),
    command
  )
end

-- Disabled while debugging editable-buffer sync corruption.
-- Ruled out so far:
-- - extra delay after leaving terminal mode
-- - spacing out each `x` edit with waits
-- - forcing manual `<C-s>` sync after each `x`
-- - `leaving_term` as the main cause; removing it makes corruption worse
-- Likely causes still left:
-- - terminal redraw writes stale visible text back into the buffer after sync
-- - `writing` skips real edits during that redraw window with no reconciliation
-- T["editable edit"]["xxxxxamars keeps deleted command state"] = function()
--   local buf = Helpers.open_shell(child)
--   child.cmd("startinsert")
--   Helpers.wait_for_mode(child, "t")
--   child.api.nvim_input("echo hello world")
--   Helpers.wait_for_read_command(child, buf, "echo hello world")
--   enter_editable_normal_mode(buf)
--   local expected_steps = {
--     { keys = "x", command = "echo hello worl", cursor = 14 },
--     { keys = "x", command = "echo hello wor", cursor = 13 },
--     { keys = "x", command = "echo hello wo", cursor = 12 },
--     { keys = "x", command = "echo hello w", cursor = 11 },
--     { keys = "x", command = "echo hello ", cursor = 10 },
--   }
--   for _, step in ipairs(expected_steps) do
--     child.api.nvim_input(step.keys)
--     Helpers.wait_for_read_command(child, buf, step.command)
--     MiniTest.expect.equality(get_command_cursor(buf), step.cursor)
--     child.wait(120)
--   end
--   child.api.nvim_input("a")
--   Helpers.wait_for_mode(child, "t")
--   child.api.nvim_input("mars")
--   Helpers.wait_for_read_command(child, buf, "echo hello mars")
-- end
-- T["editable edit"]["bxxxxxamars keeps deleted command state"] = function()
--   local buf = Helpers.open_shell(child)
--   child.cmd("startinsert")
--   Helpers.wait_for_mode(child, "t")
--   child.api.nvim_input("echo hello world")
--   Helpers.wait_for_read_command(child, buf, "echo hello world")
--   enter_editable_normal_mode(buf)
--   child.wait(120)
--   child.api.nvim_input("b")
--   local expected_steps = {
--     "echo hello orld",
--     "echo hello rld",
--     "echo hello ld",
--     "echo hello d",
--     "echo hello ",
--   }
--   for _, command in ipairs(expected_steps) do
--     child.api.nvim_input("x")
--     child.api.nvim_input("<C-s>")
--     Helpers.wait_for_read_command(child, buf, command)
--     child.wait(120)
--   end
--   Helpers.wait_for_read_command(child, buf, "echo world")
--   child.api.nvim_input("a")
--   Helpers.wait_for_mode(child, "t")
--   child.api.nvim_input("mars ")
--   Helpers.wait_for_read_command(child, buf, "echo mars world")
-- end

T["editable edit"]["bbdw<CR> outputs world"] = function()
  local buf = Helpers.open_shell(child)
  child.cmd("startinsert")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("echo hello world")
  Helpers.wait_for_read_command(child, buf, "echo hello world")
  enter_editable_normal_mode(buf)
  child.api.nvim_input("bbdw")
  MiniTest.expect.equality(read_editable_command(buf), "echo world")
  child.api.nvim_input("<CR>")
  Helpers.wait_for_shell_output(child, buf, "world")
end

return T
