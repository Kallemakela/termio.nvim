local M = {}

local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
local log_path = root .. "/tmp/snapshot.out"

local function append_window(out, win)
  local buf = vim.api.nvim_win_get_buf(win)
  local cursor = vim.api.nvim_win_get_cursor(win)
  local name = vim.api.nvim_buf_get_name(buf)
  out[#out + 1] = string.format(
    "Window %d buffer=%d type=%s cursor=%d:%d name=%s",
    win,
    buf,
    vim.bo[buf].buftype,
    cursor[1],
    cursor[2],
    name ~= "" and name or "[No Name]"
  )
  for i, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    out[#out + 1] = string.format("%d:%s", i, line)
  end
end

function M.write()
  local out = { "Snapshot " .. os.date("%Y-%m-%d %H:%M:%S") }
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    out[#out + 1] = ""
    append_window(out, win)
  end
  vim.fn.mkdir(vim.fn.fnamemodify(log_path, ":h"), "p")
  vim.fn.writefile(out, log_path)
  vim.notify("Wrote " .. log_path)
end

return M
