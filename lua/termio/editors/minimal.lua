local autoresize = require("termio.editors.autoresize")
local popup = require("termio.editors.popup")
local plugin_state = require("termio.state")
local M = popup.new({
  buffers = {},
  toggle = function()
    plugin_state.toggle()
  end,
})

local function max_editor_height(target_win)
  return math.max(1, vim.api.nvim_win_get_height(target_win) - 4)
end

local function centered_float_config(target_win, width, height)
  local target_width = vim.api.nvim_win_get_width(target_win)
  local target_height = vim.api.nvim_win_get_height(target_win)
  return {
    relative = "win",
    win = target_win,
    width = width,
    height = height,
    row = math.floor((target_height - height) / 2),
    col = math.floor((target_width - width) / 2),
    style = "minimal",
    border = "rounded",
  }
end

-- Open a small floating editor centered over the target terminal window.
local function open_editor_window(edit_buf, target_win, lines)
  local target_width = vim.api.nvim_win_get_width(target_win)
  local width = math.min(math.max(20, math.floor(target_width * 0.7)), target_width)
  local height = autoresize.height_for_lines(lines, width, max_editor_height(target_win))
  return vim.api.nvim_open_win(edit_buf, true, centered_float_config(target_win, width, height))
end

function M:create_editor_window(ctx, data)
  local edit_buf = self:create_buffer(data)
  return edit_buf, open_editor_window(edit_buf, ctx.target_win, data.lines)
end

function M:max_height(ctx)
  return max_editor_height(ctx.target_win)
end

function M.setup()
  M:setup_terminal_open("termio-minimal")
end

return M
