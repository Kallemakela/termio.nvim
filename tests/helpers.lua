-- imported from https://github.com/echasnovski/mini.nvim
local Helpers = {}
local test_root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
local test_zdotdir = test_root .. "/zsh-test"
local test_bash_env = test_root .. "/bash-test/env"

-- Add extra expectations
Helpers.expect = vim.deepcopy(MiniTest.expect)

local function error_message(str, pattern)
  return string.format("Pattern: %s\nObserved string: %s", vim.inspect(pattern), str)
end

Helpers.expect.buf_width = MiniTest.new_expectation(
  "variable in child process matches",
  function(child, field, value)
    return Helpers.expect.equality(
      child.lua_get("vim.api.nvim_win_get_width(_G.YourPluginName.state." .. field .. ")"),
      value
    )
  end,
  error_message
)

Helpers.expect.global = MiniTest.new_expectation(
  "variable in child process matches",
  function(child, field, value)
    return Helpers.expect.equality(child.lua_get(field), value)
  end,
  error_message
)

Helpers.expect.global_type = MiniTest.new_expectation(
  "variable type in child process matches",
  function(child, field, value)
    return Helpers.expect.global(child, "type(" .. field .. ")", value)
  end,
  error_message
)

Helpers.expect.config = MiniTest.new_expectation(
  "config option matches",
  function(child, field, value)
    if field == "" then
      return Helpers.expect.global(child, "_G.YourPluginName.config" .. field, value)
    else
      return Helpers.expect.global(child, "_G.YourPluginName.config." .. field, value)
    end
  end,
  error_message
)

Helpers.expect.config_type = MiniTest.new_expectation(
  "config option type matches",
  function(child, field, value)
    return Helpers.expect.global(child, "type(_G.YourPluginName.config." .. field .. ")", value)
  end,
  error_message
)

Helpers.expect.state = MiniTest.new_expectation("state matches", function(child, field, value)
  return Helpers.expect.global(child, "_G.YourPluginName.state." .. field, value)
end, error_message)

Helpers.expect.state_type = MiniTest.new_expectation(
  "state type matches",
  function(child, field, value)
    return Helpers.expect.global(child, "type(_G.YourPluginName.state." .. field .. ")", value)
  end,
  error_message
)

Helpers.expect.match = MiniTest.new_expectation("string matching", function(str, pattern)
  return str:find(pattern) ~= nil
end, error_message)

Helpers.expect.no_match = MiniTest.new_expectation("no string matching", function(str, pattern)
  return str:find(pattern) == nil
end, error_message)

-- Monkey-patch `MiniTest.new_child_neovim` with helpful wrappers
Helpers.new_child_neovim = function()
  local child = MiniTest.new_child_neovim()

  local prevent_hanging = function(method)
    if not child.is_blocked() then
      return
    end

    local msg = string.format("Can not use `child.%s` because child process is blocked.", method)
    error(msg)
  end

  child.wait = function(ms)
    child.loop.sleep(ms or 10)
  end

  child.nnp = function()
    child.cmd("YourPluginName")
    child.wait()
  end

  child.get_wins_in_tab = function(tab)
    tab = tab or "_G.YourPluginName.state.active_tab"

    return child.lua_get("vim.api.nvim_tabpage_list_wins(" .. tab .. ")")
  end

  child.list_buffers = function()
    return child.lua_get("vim.api.nvim_list_bufs()")
  end

  child.setup = function()
    child.restart({ "-u", "scripts/minimal_init.lua" })

    -- Change initial buffer to be readonly. This not only increases execution
    -- speed, but more closely resembles manually opened Neovim.
    child.bo.readonly = false
  end

  child.get_current_win = function()
    return child.lua_get("vim.api.nvim_get_current_win()")
  end

  child.set_lines = function(arr, start, finish)
    prevent_hanging("set_lines")

    if type(arr) == "string" then
      arr = vim.split(arr, "\n")
    end

    child.api.nvim_buf_set_lines(0, start or 0, finish or -1, false, arr)
  end

  child.get_lines = function(start, finish)
    prevent_hanging("get_lines")

    return child.api.nvim_buf_get_lines(0, start or 0, finish or -1, false)
  end

  child.set_cursor = function(line, column, win_id)
    prevent_hanging("set_cursor")

    child.api.nvim_win_set_cursor(win_id or 0, { line, column })
  end

  child.get_cursor = function(win_id)
    prevent_hanging("get_cursor")

    return child.api.nvim_win_get_cursor(win_id or 0)
  end

  child.set_size = function(lines, columns)
    prevent_hanging("set_size")

    if type(lines) == "number" then
      child.o.lines = lines
    end

    if type(columns) == "number" then
      child.o.columns = columns
    end
  end

  child.get_size = function()
    prevent_hanging("get_size")

    return { child.o.lines, child.o.columns }
  end

  --- Assert visual marks
  ---
  --- Useful to validate visual selection
  ---
  ---@param first number|table Table with start position or number to check linewise.
  ---@param last number|table Table with finish position or number to check linewise.
  ---@private
  child.expect_visual_marks = function(first, last)
    child.ensure_normal_mode()

    first = type(first) == "number" and { first, 0 } or first
    last = type(last) == "number" and { last, 2147483647 } or last

    MiniTest.expect.equality(child.api.nvim_buf_get_mark(0, "<"), first)
    MiniTest.expect.equality(child.api.nvim_buf_get_mark(0, ">"), last)
  end

  child.expect_screenshot = function(opts, path, screenshot_opts)
    MiniTest.expect.reference_screenshot(child.get_screenshot(screenshot_opts), path, opts)
  end

  return child
end

Helpers.setup_child = function(child, setup)
  child.setup()
  child.lua(string.format("require('termio').setup(%s)", setup or "{ editor = { type = nil } }"))
end

Helpers.wait_until = function(child, check, timeout)
  local deadline = vim.uv.now() + (timeout or 5000)
  while vim.uv.now() < deadline do
    if check() then
      return
    end
    child.wait(50)
  end
  error("timed out")
end

Helpers.wait_for_mode = function(child, mode, timeout)
  Helpers.wait_until(child, function()
    return child.lua_get("vim.api.nvim_get_mode().mode") == mode
  end, timeout)
end

Helpers.wait_for_read_command = function(child, buf, expected, timeout)
  local got
  local ok, err = pcall(function()
    Helpers.wait_until(child, function()
      got = child.lua_get([[require("termio").read_command(...)]], { buf })
      return got == expected
    end, timeout)
  end)
  if ok then
    return
  end
  error(string.format("expected read_command %q, got %q", expected, got or "<nil>"))
end

Helpers.wait_for_editable_command = function(child, buf, expected, timeout)
  local got
  local read_error
  local ok = pcall(function()
    Helpers.wait_until(child, function()
      local did_read, result = pcall(function()
        return child.lua_get(
          [[require("termio.editors.editable").read_command_from_buffer(...)]],
          { buf }
        )
      end)
      if not did_read then
        read_error = result
        return false
      end
      got = result
      return got == expected
    end, timeout)
  end)
  if ok then
    return
  end
  error(
    string.format(
      "expected editable command %q, got %q (%s)",
      expected,
      got or "<nil>",
      read_error or "no read error"
    )
  )
end

Helpers.wait_for_shell_output = function(child, buf, expected, timeout)
  local output
  local text
  local ok = pcall(function()
    Helpers.wait_until(child, function()
      text = child.lua_get(
        [[table.concat(vim.api.nvim_buf_get_lines(..., 0, -1, false), "\n")]],
        { buf }
      )
      output = text:match("%$ [^\n]*\n([^\n]+)")
      return output == expected
    end, timeout)
  end)
  if ok then
    return
  end
  error(string.format("expected shell output %q, got %q", expected, output or text or "<nil>"))
end

Helpers.has_terminal_esc_mapping = function(child)
  return child.lua_get([[vim.fn.maparg("<Esc>", "t", false, true).buffer == 1]])
end

Helpers.open_shell = function(child, prompt, shell)
  prompt = prompt or "$ "
  shell = shell or vim.env.TERMIO_TEST_SHELL or "zsh"
  if shell == "zsh" then
    child.cmd(
      string.format(
        [[terminal env ZDOTDIR=%q TERMIO_REPO_ROOT=%q PS1=%q PROMPT=%q zsh -d -i]],
        test_zdotdir,
        test_root,
        prompt,
        prompt
      )
    )
  elseif shell == "bash" then
    child.cmd(
      string.format(
        [[terminal env BASH_ENV=%q TERMIO_REPO_ROOT=%q PS1=%q bash --rcfile %q -i]],
        test_bash_env,
        test_root,
        prompt,
        test_bash_env
      )
    )
  else
    error("unsupported test shell: " .. shell)
  end
  local buf = child.api.nvim_get_current_buf()
  -- Terminal startup is async; wait for the prompt itself so the synthetic
  -- OSC133 marker lands at the prompt boundary instead of transient shell output.
  Helpers.wait_until(child, function()
    return child.api.nvim_get_current_line():match("^" .. vim.pesc(prompt) .. "%s*$") ~= nil
  end)
  local cursor = child.get_cursor()
  -- Terminal window cursor col is not reliable here; inject prompt-end from the prompt text.
  cursor[2] = #prompt
  -- Test shells do not emit OSC133 prompt markers, so inject prompt bounds here.
  child.api.nvim_exec_autocmds("TermRequest", {
    buffer = buf,
    modeline = false,
    data = { sequence = "\27]133;A", cursor = { cursor[1], 0 } },
  })
  child.api.nvim_exec_autocmds("TermRequest", {
    buffer = buf,
    modeline = false,
    data = { sequence = "\27]133;B", cursor = cursor },
  })
  return buf
end

return Helpers
