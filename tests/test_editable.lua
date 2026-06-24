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

local function get_command_cursor(buf)
  local win = child.api.nvim_get_current_win()
  return child.lua_get([=[require("termio.api").command_cursor(...)[2]]=], { win, buf })
end

local function read_editable_command(buf)
  return child.lua_get(
    [[require("termio.editors.editable").read_command_from_buffer(...)]],
    { buf }
  )
end

T["editable edit"]["open key leaves terminal mode"] = function()
  local buf = Helpers.open_shell(child)
  child.api.nvim_input("i")
  Helpers.wait_for_mode(child, "t")
  Helpers.open_terminal_normal_mode(child)
  MiniTest.expect.equality(child.lua_get("vim.api.nvim_get_mode().mode"), "nt")
end

T["editable edit"]["open key stays in terminal mode when disabled"] = function()
  Helpers.setup_child(
    child,
    [[{ editor = { type = "editable", is_disabled = function(buf) return vim.b[buf].term_tui_active == true end } }]]
  )
  local buf = Helpers.open_shell(child)
  child.api.nvim_input("i")
  Helpers.wait_for_mode(child, "t")
  child.lua([[vim.b[...].term_tui_active = true]], { buf })
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

T["editable edit"]["actions are disabled after terminal exits"] = function()
  local buf = Helpers.open_shell(child)
  local job = child.lua_get("vim.b[...].terminal_job_id", { buf })
  child.fn.jobstop(job)
  Helpers.wait_until(child, function()
    return child.lua_get([[require("termio.util.helpers").is_editor_disabled(...)]], { buf })
  end)
  child.api.nvim_input("<CR>")
  child.api.nvim_input("<Esc>")
  child.wait(100)
  Helpers.expect.no_match(child.cmd_capture("messages"), "closed stream")
end

T["editable edit"]["normal insert keys do nothing when disabled"] = function()
  Helpers.setup_child(
    child,
    [=[{ editor = { type = "editable", terminal_name_pattern = [[/bin/sh]] } }]=]
  )
  child.cmd("terminal /bin/sh")
  local buf = child.api.nvim_get_current_buf()
  child.lua([[require("termio").disable()]])
  child.api.nvim_input([[<C-\><C-n>]])
  Helpers.wait_for_mode(child, "nt")
  child.api.nvim_input("a")
  child.wait(100)
  Helpers.expect.no_match(
    child.lua_get([[vim.api.nvim_exec2("messages", { output = true }).output]]),
    "prompt_cursor"
  )
  MiniTest.expect.equality(child.lua_get("vim.api.nvim_get_mode().mode"), "nt")
  MiniTest.expect.equality(child.api.nvim_get_current_buf(), buf)
end

T["editable edit"]["open stores current shell state"] = function()
  local buf = Helpers.open_shell(child)
  child.api.nvim_input("i")
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

T["editable edit"]["open keeps cursor at command end"] = function()
  local buf = Helpers.open_shell(child)
  child.api.nvim_input("i")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("echo hello world")
  Helpers.wait_for_read_command(child, buf, "echo hello world")
  Helpers.open_editable_normal_mode(child, buf)
  Helpers.wait_until(child, function()
    return get_command_cursor(buf) == 15
  end)
end

T["editable edit"]["open keeps cursor on wrapped command end"] = function()
  local buf = Helpers.open_shell(child)
  local command = Helpers.lorem_command(197)
  child.api.nvim_input("i")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input(command)
  Helpers.wait_for_read_command(child, buf, command)
  Helpers.open_editable_normal_mode(child, buf)
  MiniTest.expect.equality(get_command_cursor(buf), #command - 1)
  MiniTest.expect.equality(child.api.nvim_win_get_cursor(0)[1] > 1, true)
end

T["editable edit"]["open keeps cursor inside command"] = function()
  local buf = Helpers.open_shell(child)
  child.api.nvim_input("i")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("echo hello world")
  Helpers.wait_for_read_command(child, buf, "echo hello world")
  child.api.nvim_input("<Left><Left><Left>")
  Helpers.wait_for_read_command(child, buf, "echo hello world")
  Helpers.open_editable_normal_mode(child, buf)
  Helpers.wait_until(child, function()
    return get_command_cursor(buf) == 12
  end)
end

T["editable edit"]["open clears tab suggestions"] = function()
  if vim.env.TERMIO_TEST_SHELL == "bash" then
    MiniTest.skip("bash has no completions to clear")
  end
  local buf = Helpers.open_shell(child)
  child.api.nvim_input("i")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("ls <Tab>")
  Helpers.wait_until(child, function()
    return child
      .lua_get([[table.concat(vim.api.nvim_buf_get_lines(..., 0, -1, false), "\n")]], { buf })
      :match("README%.md") ~= nil
  end)
  Helpers.open_editable_normal_mode(child, buf)
  Helpers.wait_until(child, function()
    return child
      .lua_get([[table.concat(vim.api.nvim_buf_get_lines(..., 0, -1, false), "\n")]], { buf })
      :match("README%.md") == nil
  end)
end

T["editable edit"]["submit runs command in normal mode and enters insert mode"] = function()
  local buf = Helpers.open_shell(child)
  child.api.nvim_input("i")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("echo normal")
  Helpers.wait_for_read_command(child, buf, "echo normal")
  Helpers.open_editable_normal_mode(child, buf)
  child.api.nvim_input("<CR>")
  Helpers.wait_for_shell_output(child, buf, "normal")
  Helpers.wait_for_mode(child, "t")
end

T["editable edit"]["submit runs command in insert mode"] = function()
  local buf = Helpers.open_shell(child)
  child.api.nvim_input("i")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("echo insert<CR>")
  Helpers.wait_for_shell_output(child, buf, "insert")
end

T["editable edit"]["bbcw updates read_command"] = function()
  local buf = Helpers.open_shell(child)
  child.api.nvim_input("i")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("echo hello world")
  Helpers.wait_for_read_command(child, buf, "echo hello world")
  Helpers.open_editable_normal_mode(child, buf)
  child.api.nvim_input("bbcegoodbye<Esc>")
  Helpers.wait_for_read_command(child, buf, "echo goodbye world")
end

T["editable edit"]["bbvec text change keeps editor draft"] = function()
  local buf = Helpers.open_shell(child)
  child.api.nvim_input("i")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("echo hello world")
  Helpers.wait_for_read_command(child, buf, "echo hello world")
  Helpers.open_editable_normal_mode(child, buf)
  child.api.nvim_input("bbvec")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("googbye")
  Helpers.wait_for_editable_command(child, buf, "echo googbye world")
end

T["editable edit"]["bbce text change keeps editor draft"] = function()
  local buf = Helpers.open_shell(child)
  child.api.nvim_input("i")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("echo hello world")
  Helpers.wait_for_read_command(child, buf, "echo hello world")
  Helpers.open_editable_normal_mode(child, buf)
  child.api.nvim_input("bbce")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("googbye")
  Helpers.wait_for_editable_command(child, buf, "echo googbye world")
end

T["editable edit"]["s substitutes character and enters terminal insert"] = function()
  local buf = Helpers.open_shell(child)
  child.api.nvim_input("i")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("echo test")
  Helpers.wait_for_read_command(child, buf, "echo test")
  Helpers.open_editable_normal_mode(child, buf)
  child.api.nvim_input("FesX")
  Helpers.wait_for_mode(child, "t")
  Helpers.wait_for_read_command(child, buf, "echo tXst")
end

T["editable edit"]["visual s changes selection"] = function()
  local buf = Helpers.open_shell(child)
  child.api.nvim_input("i")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("echo hello world")
  Helpers.wait_for_read_command(child, buf, "echo hello world")
  Helpers.open_editable_normal_mode(child, buf)
  child.api.nvim_input("bbvesgoodbye")
  Helpers.wait_for_mode(child, "t")
  Helpers.wait_for_read_command(child, buf, "echo goodbye world")
end

T["editable edit"]["bbC changes to command end"] = function()
  local buf = Helpers.open_shell(child)
  child.api.nvim_input("i")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("echo hello world")
  Helpers.wait_for_read_command(child, buf, "echo hello world")
  Helpers.open_editable_normal_mode(child, buf)
  child.api.nvim_input("bbC")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("goodbye")
  Helpers.wait_for_read_command(child, buf, "echo goodbye")
end

T["editable edit"]["C changes to wrapped command end"] = function()
  local buf = Helpers.open_shell(child)
  local command = Helpers.lorem_command(126)
  child.api.nvim_input("i")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input(command)
  Helpers.wait_for_read_command(child, buf, command)
  Helpers.open_editable_normal_mode(child, buf)
  child.api.nvim_input("[[WW")
  child.api.nvim_input("Cdone")
  Helpers.wait_for_mode(child, "t")
  Helpers.wait_for_read_command(child, buf, "echo done")
end

T["editable edit"]["D deletes to wrapped command end"] = function()
  local buf = Helpers.open_shell(child)
  local command = Helpers.lorem_command(126)
  child.api.nvim_input("i")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input(command)
  Helpers.wait_for_read_command(child, buf, command)
  Helpers.open_editable_normal_mode(child, buf)
  child.api.nvim_input("[[WW")
  child.api.nvim_input("D")
  Helpers.wait_for_editable_command(child, buf, "echo ")
end

T["editable edit"]["0 moves to wrapped command start"] = function()
  local buf = Helpers.open_shell(child)
  local command = Helpers.lorem_command(126)
  child.api.nvim_input("i")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input(command)
  Helpers.wait_for_read_command(child, buf, command)
  Helpers.open_editable_normal_mode(child, buf)
  child.api.nvim_input("[[WW")
  child.api.nvim_input("0")
  Helpers.wait_until(child, function()
    return get_command_cursor(buf) == 0
  end)
end

T["editable edit"]["$ moves to wrapped command end"] = function()
  local buf = Helpers.open_shell(child)
  local command = Helpers.lorem_command(126)
  child.api.nvim_input("i")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input(command)
  Helpers.wait_for_read_command(child, buf, command)
  Helpers.open_editable_normal_mode(child, buf)
  child.api.nvim_input("[[WW")
  child.api.nvim_input("$")
  Helpers.wait_until(child, function()
    return get_command_cursor(buf) == #command - 1
  end)
end

T["editable edit"]["^ moves to wrapped command start"] = function()
  local buf = Helpers.open_shell(child)
  local command = Helpers.lorem_command(126)
  child.api.nvim_input("i")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input(command)
  Helpers.wait_for_read_command(child, buf, command)
  Helpers.open_editable_normal_mode(child, buf)
  child.api.nvim_input("[[WW")
  child.api.nvim_input("^")
  Helpers.wait_until(child, function()
    return get_command_cursor(buf) == 0
  end)
end

T["editable edit"]["visual 0 deletes to wrapped command start"] = function()
  local buf = Helpers.open_shell(child)
  local command = Helpers.lorem_command(126)
  child.api.nvim_input("i")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input(command)
  Helpers.wait_for_read_command(child, buf, command)
  Helpers.open_editable_normal_mode(child, buf)
  child.api.nvim_input("[[WW")
  child.api.nvim_input("v0d")
  Helpers.wait_for_editable_command(child, buf, command:sub(7))
end

T["editable edit"]["visual ^ deletes to wrapped command start"] = function()
  local buf = Helpers.open_shell(child)
  local command = Helpers.lorem_command(126)
  child.api.nvim_input("i")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input(command)
  Helpers.wait_for_read_command(child, buf, command)
  Helpers.open_editable_normal_mode(child, buf)
  child.api.nvim_input("[[WW")
  child.api.nvim_input("v^d")
  Helpers.wait_for_editable_command(child, buf, command:sub(7))
end

T["editable edit"]["visual $ deletes to wrapped command end"] = function()
  local buf = Helpers.open_shell(child)
  local command = Helpers.lorem_command(126)
  child.api.nvim_input("i")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input(command)
  Helpers.wait_for_read_command(child, buf, command)
  Helpers.open_editable_normal_mode(child, buf)
  child.api.nvim_input("0v$d")
  Helpers.wait_for_editable_command(child, buf, "")
end

T["editable edit"]["d0 deletes to wrapped command start"] = function()
  local buf = Helpers.open_shell(child)
  local command = Helpers.lorem_command(126)
  child.api.nvim_input("i")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input(command)
  Helpers.wait_for_read_command(child, buf, command)
  Helpers.open_editable_normal_mode(child, buf)
  child.api.nvim_input("[[WW")
  child.api.nvim_input("d0")
  Helpers.wait_for_editable_command(child, buf, command:sub(6))
end

T["editable edit"]["c^ changes to wrapped command start"] = function()
  local buf = Helpers.open_shell(child)
  local command = Helpers.lorem_command(126)
  child.api.nvim_input("i")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input(command)
  Helpers.wait_for_read_command(child, buf, command)
  Helpers.open_editable_normal_mode(child, buf)
  child.api.nvim_input("[[WW")
  child.api.nvim_input("c^done")
  Helpers.wait_for_mode(child, "t")
  Helpers.wait_for_read_command(child, buf, "done" .. command:sub(6))
end

T["editable edit"]["dd deletes wrapped command"] = function()
  local buf = Helpers.open_shell(child)
  local command = Helpers.lorem_command(126)
  child.api.nvim_input("i")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input(command)
  Helpers.wait_for_read_command(child, buf, command)
  Helpers.open_editable_normal_mode(child, buf)
  child.api.nvim_input("[[WW")
  child.api.nvim_input("dd")
  Helpers.wait_for_editable_command(child, buf, "")
end

T["editable edit"]["yy yanks wrapped command"] = function()
  local buf = Helpers.open_shell(child)
  local command = Helpers.lorem_command(126)
  child.api.nvim_input("i")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input(command)
  Helpers.wait_for_read_command(child, buf, command)
  Helpers.open_editable_normal_mode(child, buf)
  child.api.nvim_input("[[WW")
  local cursor = get_command_cursor(buf)
  child.api.nvim_input("yy")
  MiniTest.expect.equality(child.fn.getreg('"'), command .. "\n")
  MiniTest.expect.equality(child.fn.getregtype('"'), "V")
  MiniTest.expect.equality(get_command_cursor(buf), cursor)
end

T["editable edit"]["bbved deletes visual selection from editor draft"] = function()
  local buf = Helpers.open_shell(child)
  child.api.nvim_input("i")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("echo hello world")
  Helpers.wait_for_read_command(child, buf, "echo hello world")
  Helpers.open_editable_normal_mode(child, buf)
  child.api.nvim_input("bbved")
  MiniTest.expect.equality(read_editable_command(buf), "echo  world")
end

T["editable edit"]["bbcw<Esc> updates command"] = function()
  local buf = Helpers.open_shell(child)
  local command = "echo hello world there friend"
  child.api.nvim_input("i")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input(command)
  Helpers.wait_for_read_command(child, buf, command)
  Helpers.open_editable_normal_mode(child, buf)
  child.api.nvim_input("bbcw<Esc>")
  Helpers.wait_for_read_command(child, buf, "echo hello world friend")
end

T["editable edit"]["visual delete from wrapped command keeps last word"] = function()
  local buf = Helpers.open_shell(child)
  local last_word = "omega"
  local command = Helpers.lorem_command(126) .. last_word
  child.api.nvim_input("i")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input(command)
  Helpers.wait_for_read_command(child, buf, command)
  Helpers.open_editable_normal_mode(child, buf)
  child.api.nvim_input("bbev[[EEbhd")
  Helpers.wait_for_editable_command(child, buf, "echo " .. last_word)
end

T["editable edit"]["visual change from wrapped command keeps last word"] = function()
  local buf = Helpers.open_shell(child)
  local last_word = "omega"
  local command = Helpers.lorem_command(126) .. last_word
  child.api.nvim_input("i")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input(command)
  Helpers.wait_for_read_command(child, buf, command)
  Helpers.open_editable_normal_mode(child, buf)
  child.api.nvim_input("bbev[[EEbhc")
  Helpers.wait_for_mode(child, "t")
  Helpers.wait_for_read_command(child, buf, "echo " .. last_word)
end

T["editable edit"]["bbdw updates editor draft and stays in normal mode"] = function()
  local buf = Helpers.open_shell(child)
  child.api.nvim_input("i")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("echo hello world")
  Helpers.wait_for_read_command(child, buf, "echo hello world")
  Helpers.open_editable_normal_mode(child, buf)
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
  child.api.nvim_input("i")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("echo hello world")
  Helpers.wait_for_read_command(child, buf, "echo hello world")
  Helpers.open_editable_normal_mode(child, buf)
  child.api.nvim_input("bbdw<C-s>")
  Helpers.wait_for_read_command(child, buf, "echo world")
end

T["editable edit"]["bbdwvep keeps edited draft"] = function()
  local buf = Helpers.open_shell(child)
  child.api.nvim_input("i")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("echo hello world")
  Helpers.wait_for_read_command(child, buf, "echo hello world")
  Helpers.open_editable_normal_mode(child, buf)
  child.api.nvim_input("bbdwvep")
  Helpers.wait_for_editable_command(child, buf, "echo hello")
end

T["editable edit"]["bbdwi keeps deleted command state"] = function()
  local buf = Helpers.open_shell(child)
  child.api.nvim_input("i")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("echo hello world")
  Helpers.wait_for_read_command(child, buf, "echo hello world")
  Helpers.open_editable_normal_mode(child, buf)
  child.api.nvim_input("bbdw")
  MiniTest.expect.equality(read_editable_command(buf), "echo world")
  child.api.nvim_input("i")
  Helpers.wait_for_mode(child, "t")
  child.wait(100)
  Helpers.wait_for_read_command(child, buf, "echo world")
end

T["editable edit"]["bbdwi enters insert at correct spot"] = function()
  local buf = Helpers.open_shell(child)
  child.api.nvim_input("i")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("echo hello world")
  Helpers.wait_for_read_command(child, buf, "echo hello world")
  Helpers.open_editable_normal_mode(child, buf)
  child.api.nvim_input("bbdw")
  MiniTest.expect.equality(read_editable_command(buf), "echo world")
  child.api.nvim_input("i")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("!")
  Helpers.wait_for_read_command(child, buf, "echo !world")
end

T["editable edit"]["bbdwa enters insert at correct spot"] = function()
  local buf = Helpers.open_shell(child)
  child.api.nvim_input("i")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("echo hello world")
  Helpers.wait_for_read_command(child, buf, "echo hello world")
  Helpers.open_editable_normal_mode(child, buf)
  child.api.nvim_input("bbdw")
  MiniTest.expect.equality(read_editable_command(buf), "echo world")
  child.api.nvim_input("a")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("!")
  Helpers.wait_for_read_command(child, buf, "echo w!orld")
end

T["editable edit"]["a on empty command inserts typed text instead of cursor"] = function()
  local buf = Helpers.open_shell(child)
  child.api.nvim_input("i")
  Helpers.wait_for_mode(child, "t")
  Helpers.open_editable_normal_mode(child, buf)
  child.api.nvim_input("a >")
  Helpers.wait_for_read_command(child, buf, " >")
end

T["editable edit"]["bbdwI enters insert at command start"] = function()
  local buf = Helpers.open_shell(child)
  child.api.nvim_input("i")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("echo hello world")
  Helpers.wait_for_read_command(child, buf, "echo hello world")
  Helpers.open_editable_normal_mode(child, buf)
  child.api.nvim_input("bbdw")
  MiniTest.expect.equality(read_editable_command(buf), "echo world")
  child.api.nvim_input("I")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("!")
  Helpers.wait_for_read_command(child, buf, "!echo world")
end

T["editable edit"]["bbdwA enters insert at command end"] = function()
  local buf = Helpers.open_shell(child)
  child.api.nvim_input("i")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("echo hello world")
  Helpers.wait_for_read_command(child, buf, "echo hello world")
  Helpers.open_editable_normal_mode(child, buf)
  child.api.nvim_input("bbdw")
  MiniTest.expect.equality(read_editable_command(buf), "echo world")
  child.api.nvim_input("A")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("!")
  Helpers.wait_for_read_command(child, buf, "echo world!")
end

T["editable edit"]["bxxx defers shell sync until insert"] = function()
  local buf = Helpers.open_shell(child)
  child.api.nvim_input("i")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("echo hello world")
  Helpers.wait_for_read_command(child, buf, "echo hello world")
  Helpers.open_editable_normal_mode(child, buf)
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
  child.api.nvim_input("i")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("hello")
  Helpers.wait_for_read_command(child, buf, "hello")
  Helpers.open_editable_normal_mode(child, buf)
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
  local command = Helpers.lorem_command(520)
  child.set_size(24, 80)
  child.api.nvim_input("i")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input(command)
  Helpers.wait_for_read_command(child, buf, command)
  Helpers.open_editable_normal_mode(child, buf)
  child.api.nvim_input("dj")
  MiniTest.expect.equality(child.lua_get([[require("termio").read_command(...)]], { buf }), command)
  MiniTest.expect.equality(child.lua_get("vim.api.nvim_get_mode().mode"), "nt")
  MiniTest.expect.equality(
    child.lua_get([[require("termio.api").buffers[...] .shell_state.command]], { buf }),
    command
  )
end

T["editable edit"]["dj on wrapped command keeps cursor inside editable command"] = function()
  local buf = Helpers.open_shell(child)
  local command = Helpers.lorem_command(520)
  child.set_size(24, 80)
  child.api.nvim_input("i")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input(command)
  Helpers.wait_for_read_command(child, buf, command)
  Helpers.open_editable_normal_mode(child, buf)
  child.api.nvim_input("dj")
  Helpers.wait_for_mode(child, "nt")
  Helpers.wait_until(child, function()
    return child.api.nvim_get_option_value("modifiable", { buf = buf })
  end)
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
  child.api.nvim_input("i")
  Helpers.wait_for_mode(child, "t")
  child.api.nvim_input("echo hello world")
  Helpers.wait_for_read_command(child, buf, "echo hello world")
  Helpers.open_editable_normal_mode(child, buf)
  child.api.nvim_input("bbdw")
  MiniTest.expect.equality(read_editable_command(buf), "echo world")
  child.api.nvim_input("<CR>")
  Helpers.wait_for_shell_output(child, buf, "world")
end

return T
