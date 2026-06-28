local T = MiniTest.new_set()

local function state_for(sequence, cursor)
  local shell_state = require("termio.shell_state")
  local buffers = {}
  local buf = vim.api.nvim_get_current_buf()
  shell_state.handle_term_request(buffers, {
    buf = buf,
    data = { sequence = sequence, cursor = cursor or { 1, 0 } },
  })
  return buffers[buf]
end

T["OSC133 prompt end activates prompt"] = function()
  local state = state_for("\027]133;B\007", { 2, 4 })

  MiniTest.expect.equality(state.prompt_end_cursor, { 2, 4 })
  MiniTest.expect.equality(state.active_prompt_cursor, { 2, 4 })
  MiniTest.expect.equality(state.active_prompt_source, "osc133")
  MiniTest.expect.equality(state.shell_phase, "input")
end

T["OSC133 preexec clears active prompt"] = function()
  local shell_state = require("termio.shell_state")
  local state = state_for("\027]133;B\007", { 2, 4 })

  shell_state.handle_term_request({ [vim.api.nvim_get_current_buf()] = state }, {
    buf = vim.api.nvim_get_current_buf(),
    data = { sequence = "\027]133;C\007", cursor = { 2, 8 } },
  })

  MiniTest.expect.equality(state.prompt_end_cursor, { 2, 4 })
  MiniTest.expect.equality(state.active_prompt_cursor, nil)
  MiniTest.expect.equality(state.active_prompt_source, nil)
  MiniTest.expect.equality(state.shell_phase, "output")
end

T["OSC633 integration marker stores shell"] = function()
  local state = state_for("\027]633;I;zsh\007")

  MiniTest.expect.equality(state.shell_kind, "zsh")
  MiniTest.expect.equality(state.shell_integration.kind, "zsh")
end

T["OSC633 command marker stores shell command state"] = function()
  local state = state_for("\027]633;E;4;echo test\007")

  MiniTest.expect.equality(state.shell_state.command, "echo test")
  MiniTest.expect.equality(state.shell_state.cursor, 4)
  MiniTest.expect.equality(state.shell_query_pending, false)
end

T["OSC title stores terminal title"] = function()
  local state = state_for("\027]2;python\007")

  MiniTest.expect.equality(state.terminal_title, "python")
end

T["term request stores title in api buffer state"] = function()
  local api = require("termio.api")
  local buf = vim.api.nvim_get_current_buf()

  require("termio.shell_state").handle_term_request(api.buffers, {
    buf = buf,
    data = { sequence = "\027]0;node\007", cursor = { 1, 0 } },
  })

  MiniTest.expect.equality(api.buffers[buf].terminal_title, "node")
end

return T
