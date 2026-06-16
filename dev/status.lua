local M = {}

local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")

local function get_api()
  return require("termline.api")
end

local function get_config()
  return require("termline.config")
end

local function get_helpers()
  return require("termline.util.helpers")
end

local function inspect_text(value)
  if value == nil or value == "" then
    return "-"
  end
  local text = tostring(value):gsub("\n", "\\n")
  local function edge_marker(space)
    return space == "\t" and "→" or "·"
  end
  text = text:gsub("^[ \t]+", function(space)
    return space:gsub(".", edge_marker)
  end)
  text = text:gsub("[ \t]+$", function(space)
    return space:gsub(".", edge_marker)
  end)
  return text
end

local function format_cursor(cursor)
  if type(cursor) ~= "table" then
    return cursor or "-"
  end
  return string.format("%s:%s", cursor[1] or "-", cursor[2] or "-")
end

local function format_debug_cursor(cursor)
  local value = format_cursor(cursor)
  if type(value) == "number" then
    return string.format("%2d", value)
  end
  return string.format("%2s", tostring(value))
end

local function read_buffer_state(buf, win)
  local api = get_api()
  local helpers = get_helpers()
  local shell_state = helpers.ensure_buffer_state(api.buffers, buf).shell_state
  return { command = shell_state.command, cursor = api.command_cursor(win, buf)[2] }
end

local function find_editor_window()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].filetype == "termline" then
      return win, buf
    end
  end
end

local function get_log_path()
  if vim.o.verbosefile ~= "" then
    return vim.o.verbosefile
  end
  return root .. "/tmp/dev.out"
end

function M.collect()
  local terminal = _G.termline_debug and _G.termline_debug.terminal or {}
  local shell = { command = "missing terminal", cursor = { "-", "-" } }
  local target = { active = false, cursor = "-", command = "-" }
  local buffer = { cursor = "-", command = "missing terminal" }
  local config = get_config()
  local editor_options = config.options and config.options.editor or config.defaults.editor
  if terminal.buf and vim.api.nvim_buf_is_valid(terminal.buf) then
    local api = get_api()
    local helpers = get_helpers()
    local buf_state = helpers.ensure_buffer_state(api.buffers, terminal.buf)
    local visible = nil
    if buf_state.prompt_end_cursor and terminal.win and vim.api.nvim_win_is_valid(terminal.win) then
      visible = read_buffer_state(terminal.buf, terminal.win)
    end
    local shell_state = buf_state.shell_state
    buffer.cursor = visible and visible.cursor or "-"
    buffer.command = visible and visible.command or "missing prompt"
    shell = {
      cursor = shell_state and shell_state.cursor or "-",
      command = shell_state and shell_state.command or "-",
    }
    target.active = vim.api.nvim_get_option_value("modifiable", { buf = terminal.buf })
  end
  local editor_win, editor_buf = find_editor_window()
  target.type = editor_options.type
  target.buf = editor_buf
  target.win = editor_win
  if editor_buf and editor_win then
    target.cursor = vim.api.nvim_win_get_cursor(editor_win)
    target.command = table.concat(vim.api.nvim_buf_get_lines(editor_buf, 0, -1, false), "\n")
    target.active = true
  end
  return { terminal = terminal, shell = shell, target = target, buffer = buffer }
end

function M.render_lines(snapshot)
  return {
    string.format(
      "target: type=%s active=%s mode=%s term=%s/%s/%s buf=%s win=%s",
      snapshot.target.type or "-",
      tostring(snapshot.target.active),
      vim.api.nvim_get_mode().mode,
      snapshot.terminal.buf or "-",
      snapshot.terminal.win or "-",
      snapshot.terminal.chan or "-",
      snapshot.target.buf or "-",
      snapshot.target.win or "-"
    ),
    string.format(
      "buffer: %s cmd: %s",
      format_debug_cursor(snapshot.buffer.cursor),
      inspect_text(snapshot.buffer.command)
    ),
    string.format(
      "shell : %s cmd: %s",
      format_debug_cursor(snapshot.shell.cursor),
      inspect_text(snapshot.shell.command)
    ),
    string.format(
      "target: %s cmd: %s",
      format_debug_cursor(snapshot.target.cursor),
      inspect_text(snapshot.target.command)
    ),
  }
end

function M.snapshot_lines(label)
  local lines = M.render_lines(M.collect())
  if not label or label == "" then
    return lines
  end
  return vim.list_extend({ "status: " .. label }, lines)
end

function M.dump(label)
  local lines = M.snapshot_lines(label)
  vim.fn.writefile(vim.list_extend(lines, { "" }), get_log_path(), "a")
  return lines
end

function M.copy_and_dump(label)
  local lines = M.dump(label)
  vim.fn.setreg("+", table.concat(lines, "\n"))
  vim.notify("Copied termline status", vim.log.levels.INFO)
  return lines
end

function M.setup()
  _G.termline_debug = _G.termline_debug or {}
  _G.termline_debug.dump_status = M.dump
  _G.termline_debug.copy_status = M.copy_and_dump
end

return M
