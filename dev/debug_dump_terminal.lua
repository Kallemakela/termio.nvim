local M = {}

local log_path = vim.fn.getcwd() .. "/tmp/termdump.out"
local buffer_events = {}

vim.fn.mkdir(vim.fn.fnamemodify(log_path, ":h"), "p")
io.open(log_path, "w"):close()

local function timestamp()
  return vim.fn.strftime("%H:%M:%S")
    .. string.format(".%03d", math.floor((vim.loop.hrtime() / 1e6) % 1000))
end

local function visible_sequence(sequence)
  return vim.inspect(sequence or ""):sub(2, -2)
end

local function insert_markers(line, events)
  if not events or #events == 0 then
    return line
  end
  table.sort(events, function(a, b)
    return a.col < b.col
  end)

  local parts = {}
  local start_col = 1
  for _, event in ipairs(events) do
    local col = math.max(event.col, 0)
    local split_col = math.min(col + 1, #line + 1)
    parts[#parts + 1] = line:sub(start_col, split_col - 1)
    parts[#parts + 1] = "(" .. event.sequence .. ")"
    start_col = split_col
  end
  parts[#parts + 1] = line:sub(start_col)
  return table.concat(parts)
end

local function format_buffer_lines(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local state = buffer_events[buf]
  local now = state and state.timestamp or timestamp()
  local out = {}

  for line_number, line in ipairs(lines) do
    local events = state and state.by_row[line_number] or nil
    out[#out + 1] = string.format("%d:%s", line_number, insert_markers(line, events))
  end
  out[#out + 1] = now
  return out
end

local function rewrite_log(buf)
  vim.fn.writefile(format_buffer_lines(buf), log_path)
end

local function remember_event(args)
  local cursor = args.data.cursor or {}
  local row = cursor[1]
  local col = cursor[2]
  if not row or row <= 0 or col == nil then
    return
  end

  local state = buffer_events[args.buf] or { by_row = {} }
  state.timestamp = timestamp()
  state.by_row[row] = state.by_row[row] or {}
  state.by_row[row][#state.by_row[row] + 1] = {
    col = col,
    sequence = visible_sequence(args.data.sequence),
  }
  buffer_events[args.buf] = state

  rewrite_log(args.buf)
end

local function clear_events(args)
  buffer_events[args.buf] = nil
end

function M.setup()
  vim.api.nvim_create_autocmd({ "BufDelete", "TermClose" }, {
    group = vim.api.nvim_create_augroup("termio-debug-dump-cleanup", { clear = true }),
    callback = clear_events,
  })
  vim.api.nvim_create_autocmd("TermRequest", {
    group = vim.api.nvim_create_augroup("termio-debug-dump", { clear = true }),
    callback = remember_event,
  })
end

return M
