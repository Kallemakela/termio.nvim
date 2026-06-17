local M = {}
local state = {}
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
local status = dofile(root .. "/dev/status.lua")

local function status_height()
  return #status.snapshot_lines()
end

local function render()
  if state.rendering then
    return
  end
  if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then
    return
  end
  state.rendering = true
  local ok, err = pcall(function()
    if state.win and vim.api.nvim_win_is_valid(state.win) then
      vim.api.nvim_win_set_height(state.win, status_height())
    end
    vim.bo[state.buf].modifiable = true
    vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, status.snapshot_lines())
    vim.bo[state.buf].modifiable = false
  end)
  state.rendering = false
  if not ok then
    error(err)
  end
end

local function open_window()
  local current_win = vim.api.nvim_get_current_win()
  vim.cmd("botright " .. status_height() .. "new")
  state.win = vim.api.nvim_get_current_win()
  state.buf = vim.api.nvim_get_current_buf()
  vim.bo[state.buf].buftype = "nofile"
  vim.bo[state.buf].bufhidden = "wipe"
  vim.bo[state.buf].swapfile = false
  vim.bo[state.buf].modifiable = false
  vim.wo[state.win].number = false
  vim.wo[state.win].relativenumber = false
  vim.wo[state.win].signcolumn = "no"
  vim.wo[state.win].wrap = false
  vim.wo[state.win].winfixheight = true
  vim.api.nvim_buf_set_name(state.buf, "termio://status")
  vim.api.nvim_set_current_win(current_win)
end

function M.setup()
  status.setup()
  open_window()
  vim.keymap.set("n", "<Leader>s", function()
    status.copy_and_dump()
  end, { desc = "Copy termio status" })
  local group = vim.api.nvim_create_augroup("termio-dev-status", { clear = true })
  vim.api.nvim_create_autocmd({
    "CursorMoved",
    "CursorMovedI",
    "TermRequest",
    "TextChanged",
    "TextChangedI",
    "User",
    "WinEnter",
    "BufEnter",
  }, {
    group = group,
    callback = render,
  })
  state.timer = assert(vim.uv.new_timer())
  state.timer:start(0, 100, vim.schedule_wrap(render))
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      if state.timer then
        state.timer:stop()
        state.timer:close()
      end
    end,
  })
  render()
end

return M
