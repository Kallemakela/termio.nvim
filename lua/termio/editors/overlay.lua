local api = require("termio.api")
local autoresize = require("termio.editors.autoresize")
local popup = require("termio.editors.popup")
local helpers = require("termio.util.helpers")
local keymaps = require("termio.util.keymaps")
local config = require("termio.config")
local state = require("termio.state")

local M = popup.new({
  buffers = {},
  terminal_keymaps = {},
  toggle = function()
    state.toggle()
  end,
})

local function popup_options()
  return config.options.editor.popup
end

local function max_float_height(row)
  return math.max(1, vim.o.lines - row - vim.o.cmdheight)
end

local function command_screen_row(target_win, target_buf)
  local _, prompt_end = api.prompt_range(target_buf)
  if not prompt_end then
    error("termio: missing prompt end cursor")
  end
  local pos = vim.fn.screenpos(target_win, prompt_end[1], prompt_end[2] + 1)
  return math.max(pos.row - 1, 0)
end

local function popup_config(target_win, target_buf, lines)
  local win_row, col = unpack(vim.api.nvim_win_get_position(target_win))
  local row = win_row + command_screen_row(target_win, target_buf)
  local width = vim.api.nvim_win_get_width(target_win)
  return {
    relative = "editor",
    style = "minimal",
    border = "none",
    width = width,
    height = autoresize.height_for_lines(lines, width, max_float_height(row)),
    row = row,
    col = col,
  }
end

local function set_editor_options(edit_buf, edit_win)
  vim.bo[edit_buf].modifiable = true
  vim.bo[edit_buf].swapfile = false
  vim.bo[edit_buf].textwidth = 0
  vim.bo[edit_buf].autoindent = false
  vim.bo[edit_buf].smartindent = false
  vim.bo[edit_buf].cindent = false
  vim.bo[edit_buf].formatoptions = vim.bo[edit_buf].formatoptions:gsub("[tca]", "")
  vim.wo[edit_win].wrap = true
end

function M:prepare_data(ctx)
  local data = popup.prepare_data(self, ctx)
  -- We clear command behind the overlay so it does not show up when
  -- overlay window gets smaller.
  helpers.clear_command_line(ctx.target_buf)
  return data
end

function M:create_editor_window(ctx, data)
  local edit_buf = self:create_buffer(data)
  local edit_win =
    vim.api.nvim_open_win(edit_buf, true, popup_config(ctx.target_win, ctx.target_buf, data.lines))
  set_editor_options(edit_buf, edit_win)
  return edit_buf, edit_win
end

local function register_insert_leave_writer(ctx, edit_buf, edit_win)
  vim.api.nvim_create_autocmd("InsertLeave", {
    buffer = edit_buf,
    callback = function()
      if vim.api.nvim_buf_is_valid(edit_buf) then
        popup.write_command(ctx, edit_buf, edit_win)
      end
    end,
  })
end

function M:max_height(_, edit_win)
  return max_float_height(vim.api.nvim_win_get_config(edit_win).row)
end

function M:after_open(ctx, edit_buf, edit_win)
  register_insert_leave_writer(ctx, edit_buf, edit_win)
end

local function apply_terminal_keymaps(buf)
  local group = keymaps.group({ buffer = buf })
  popup.map_terminal_open(
    buf,
    M.open,
    { group = group, modes = { "n", "t" }, stopinsert_modes = { t = true } }
  )
  M.terminal_keymaps[buf] = group
  vim.api.nvim_create_autocmd("BufDelete", {
    buffer = buf,
    callback = function()
      M.terminal_keymaps[buf] = nil
    end,
  })
end

local function open_on_prompt()
  error("termio: editor.popup.open_on_prompt is not implemented")
end

function M.enable()
  for _, group in pairs(M.terminal_keymaps) do
    group:enable()
  end
end

function M.disable()
  for _, group in pairs(M.terminal_keymaps) do
    group:disable()
  end
end

function M.setup()
  vim.api.nvim_create_autocmd("TermOpen", {
    group = vim.api.nvim_create_augroup("termio-overlay", { clear = true }),
    callback = function(args)
      if helpers.is_enabled_terminal(args.buf) then
        vim.schedule(function()
          if vim.api.nvim_buf_is_valid(args.buf) then
            apply_terminal_keymaps(args.buf)
          end
        end)
      end
    end,
  })
  if popup_options().open_on_prompt then
    open_on_prompt()
  end
end

return M
