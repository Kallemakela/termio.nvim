local config = require("termio.config")
local autoresize = require("termio.editors.autoresize")
local fixbuf = require("termio.editors.fixbuf")
local helpers = require("termio.util.helpers")
local keymaps = require("termio.util.keymaps")
local terminal_buffer = require("termio.terminal_buffer")

local M = {}

function M.new(opts)
  opts = opts or {}
  opts.write = opts.write or function(edit_buf)
    M.write_current(opts.buffers, edit_buf)
  end
  opts.open = opts.open or function(ctx)
    return M.open(opts, ctx)
  end
  return setmetatable(opts, { __index = M })
end

function M:build_context(ctx)
  ctx = ctx or {}
  local target_buf = helpers.current_buf(ctx.target_buf)
  return { target_buf = target_buf, target_win = ctx.target_win or vim.fn.bufwinid(target_buf) }
end

local function api()
  return require("termio.api")
end

function M.is_first_visual_line()
  return vim.fn.winline() == 1
end

function M.feed_key(key, mode)
  vim.api.nvim_feedkeys(helpers.term_codes(key), mode, false)
end

function M.command_lines(command)
  return vim.split(command, "\n", { plain = true })
end

function M:prepare_data(ctx)
  local prompt = M.terminal_prompt_text(ctx.target_buf)
  local shell = api().read_state(ctx.target_buf, ctx.target_win)
  return {
    prompt = prompt,
    shell = shell,
    lines = M.command_lines(prompt .. shell.command),
  }
end

function M.command_text(buf, start_cursor)
  return table.concat(terminal_buffer.command_rows(buf, start_cursor), "\n")
end

function M.prompt_start_cursor(buf)
  return { 1, #vim.fn.prompt_getprompt(buf) }
end

function M.terminal_prompt_text(buf)
  api().update_prompt_range(buf)
  local prompt_start, prompt_end = api().prompt_range(buf)
  if not prompt_start or not prompt_end then
    error("termio: missing prompt range")
  end
  local line = terminal_buffer.command_rows(buf, prompt_start, true)[1] or ""
  return line:sub(1, prompt_end[2] - prompt_start[2])
end

function M.cursor_index(buf, win, start_cursor)
  return terminal_buffer.cursor_index_from_start_cursor(
    vim.api.nvim_win_get_cursor(win),
    buf,
    start_cursor
  )
end

function M.normal_cursor_offset(command, cursor)
  if cursor then
    return math.min(cursor, math.max(#command - 1, 0))
  end
  return math.max(#command - 1, 0)
end

function M.set_initial_cursor(edit_buf, edit_win, command, cursor)
  vim.api.nvim_win_set_cursor(
    edit_win,
    terminal_buffer.location_from_offset(
      edit_buf,
      M.prompt_start_cursor(edit_buf),
      M.normal_cursor_offset(command, cursor)
    )
  )
end

function M.write_command(ctx, edit_buf, edit_win, cursor)
  local start_cursor = M.prompt_start_cursor(edit_buf)
  local target_cursor = cursor
  if target_cursor == nil and vim.api.nvim_win_is_valid(edit_win) then
    target_cursor = M.cursor_index(edit_buf, edit_win, start_cursor)
  end
  api().write_command(M.command_text(edit_buf, start_cursor), ctx.target_buf, target_cursor)
end

function M.write_current(buffers, edit_buf)
  edit_buf = edit_buf or vim.api.nvim_get_current_buf()
  M.write_command(buffers[edit_buf], edit_buf, vim.api.nvim_get_current_win())
end

function M:write(edit_buf)
  M.write_current(self.buffers, edit_buf)
end

function M.clear(edit_buf, edit_win)
  local start_cursor = M.prompt_start_cursor(edit_buf)
  vim.api.nvim_buf_set_lines(edit_buf, 0, -1, false, { vim.fn.prompt_getprompt(edit_buf) })
  vim.api.nvim_win_set_cursor(edit_win, start_cursor)
end

local function clamp_prompt_buffer_cursor(edit_buf)
  local prompt = vim.fn.prompt_getprompt(edit_buf)
  local cursor = vim.api.nvim_win_get_cursor(0)
  if cursor[1] == 1 and cursor[2] < #prompt then
    vim.api.nvim_win_set_cursor(0, { 1, #prompt })
  end
end

local function register_cursor_clamp(edit_buf)
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = vim.api.nvim_create_augroup("termio-popup-prompt-" .. edit_buf, { clear = true }),
    buffer = edit_buf,
    callback = function()
      clamp_prompt_buffer_cursor(edit_buf)
    end,
  })
end

function M.focus_target(ctx)
  if vim.api.nvim_win_is_valid(ctx.target_win) then
    vim.api.nvim_set_current_win(ctx.target_win)
  end
end

function M.close(buffers, edit_buf, ctx, edit_win)
  ctx = ctx or buffers[edit_buf]
  if not ctx then
    return
  end
  edit_win = edit_win or ctx.edit_win
  if vim.api.nvim_win_is_valid(edit_win) then
    vim.api.nvim_win_close(edit_win, true)
  end
  M.focus_target(ctx)
  buffers[edit_buf] = nil
end

function M.submit(buffers, edit_buf, ctx, edit_win)
  api().write_command(
    M.command_text(edit_buf, M.prompt_start_cursor(edit_buf)),
    ctx.target_buf,
    nil
  )
  helpers.send_keys("<CR>", ctx.target_buf)
  M.close(buffers, edit_buf, ctx, edit_win)
  vim.schedule(function()
    M.focus_target(ctx)
    vim.cmd.stopinsert()
    vim.cmd.startinsert()
  end)
end

function M.action_handlers(opts)
  local function write()
    M.write_command(opts.ctx, opts.edit_buf, opts.edit_win)
  end
  local function pass_through_insert(key)
    write()
    M.close(opts.buffers, opts.edit_buf, opts.ctx, opts.edit_win)
    vim.schedule(function()
      M.focus_target(opts.ctx)
      vim.cmd.startinsert()
      M.feed_key(key, "t")
    end)
  end
  local function pass_through_normal(key)
    write()
    M.close(opts.buffers, opts.edit_buf, opts.ctx, opts.edit_win)
    M.feed_key(key, "n")
  end
  return {
    submit = function()
      M.submit(opts.buffers, opts.edit_buf, opts.ctx, opts.edit_win)
    end,
    clear = function()
      M.clear(opts.edit_buf, opts.edit_win)
    end,
    write = write,
    save_and_close = function()
      write()
      M.close(opts.buffers, opts.edit_buf, opts.ctx, opts.edit_win)
    end,
    close = function()
      M.close(opts.buffers, opts.edit_buf, opts.ctx, opts.edit_win)
      vim.cmd.startinsert()
    end,
    toggle = opts.toggle,
    pass_through_insert = pass_through_insert,
    pass_through_normal = pass_through_normal,
    down = function()
      vim.cmd("normal! gj")
    end,
    up = function()
      if vim.api.nvim_get_mode().mode == "n" and M.is_first_visual_line() then
        pass_through_normal("k")
        return
      end
      vim.cmd("normal! gk")
    end,
  }
end

function M:handlers(ctx, edit_buf, edit_win)
  return M.action_handlers({
    buffers = self.buffers,
    ctx = ctx,
    edit_buf = edit_buf,
    edit_win = edit_win,
    toggle = function()
      self.toggle()
    end,
  })
end

---Create a popup editor buffer.
---@param opts table
---@return integer
function M.make_buffer(opts)
  local edit_buf = vim.api.nvim_create_buf(false, opts.scratch ~= false)
  vim.bo[edit_buf].buftype = opts.buftype or "nofile"
  vim.bo[edit_buf].bufhidden = "wipe"
  vim.bo[edit_buf].filetype = "termio"
  vim.b[edit_buf].termio_fixed_editor = true
  if opts.prompt then
    vim.fn.prompt_setprompt(edit_buf, opts.prompt)
  end
  vim.api.nvim_buf_set_lines(edit_buf, 0, -1, false, opts.lines)
  vim.bo[edit_buf].modified = false
  return edit_buf
end

function M:create_buffer(data)
  return M.make_buffer({
    buftype = "prompt",
    scratch = false,
    prompt = data.prompt,
    lines = data.lines,
  })
end

function M:open(ctx)
  ctx = self:build_context(ctx)
  if helpers.is_editor_disabled(ctx.target_buf) then
    return false
  end
  vim.cmd.stopinsert()
  local data = self:prepare_data(ctx)
  local edit_buf, edit_win = self:create_editor_window(ctx, data)
  M.set_initial_cursor(edit_buf, edit_win, data.shell.command, data.shell.cursor)
  self:register({
    edit_buf = edit_buf,
    edit_win = edit_win,
    ctx = ctx,
    max_height = self:max_height(ctx, edit_win),
  })
  if self.after_open then
    self:after_open(ctx, edit_buf, edit_win)
  end
  return edit_buf
end

---Register shared popup editor features.
---@param opts table
function M.register_buffer(opts)
  opts.buffers[opts.edit_buf] = vim.tbl_extend("force", opts.ctx, { edit_win = opts.edit_win })
  opts.buffers[opts.edit_buf].keymaps = M.apply_keymaps(opts.edit_buf, opts.handlers)
  autoresize.register(opts.edit_buf, opts.edit_win, opts.max_height)
  fixbuf.register(opts.edit_buf, opts.edit_win, opts.ctx.target_win)
  if vim.bo[opts.edit_buf].buftype == "prompt" then
    register_cursor_clamp(opts.edit_buf)
  end
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = opts.edit_buf,
    callback = function()
      opts.buffers[opts.edit_buf] = nil
    end,
  })
end

function M:register(opts)
  opts.buffers = self.buffers
  opts.handlers = opts.handlers or self:handlers(opts.ctx, opts.edit_buf, opts.edit_win)
  M.register_buffer(opts)
end

local function map_editor_keys(group, handlers)
  for _, source in ipairs({ config.options.editor.keys, config.options.editor.popup.keys }) do
    for mode, mappings in pairs(source or {}) do
      if type(mappings) == "table" then
        for lhs, action in pairs(mappings) do
          if type(action) == "string" and action ~= "open" then
            local handler = handlers[action]
            assert(handler, "termio: unknown popup key action: " .. tostring(action))
            group:map(mode, lhs, function()
              handler(lhs)
            end)
          end
        end
      end
    end
  end
end

local function map_pass_through_keys(group, handlers)
  local options = config.options.editor.popup
  for _, key in ipairs(options.pass_through_insert_keys or {}) do
    group:map("i", key, function()
      handlers.pass_through_insert(key)
    end)
  end
  for _, key in ipairs(options.pass_through_normal_keys or {}) do
    group:map("n", key, function()
      handlers.pass_through_normal(key)
    end)
  end
  for _, key in ipairs(options.pass_through_normal_keys_first_line or {}) do
    group:map("n", key, function()
      if M.is_first_visual_line() then
        handlers.pass_through_normal(key)
        return
      end
      vim.cmd("normal! " .. key)
    end)
  end
end

---Apply shared popup editor keymaps.
---@param edit_buf integer
---@param handlers table<string, function>
---@return table
function M.apply_keymaps(edit_buf, handlers)
  local group = keymaps.group({ buffer = edit_buf })
  map_editor_keys(group, handlers)
  map_pass_through_keys(group, handlers)
  return group
end

function M.map_terminal_open(buf, open, opts)
  opts = opts or {}
  local group = opts.group
  local modes = opts.modes or { "t" }
  for _, mode in ipairs(modes) do
    local map = function()
      if opts.stopinsert or (opts.stopinsert_modes and opts.stopinsert_modes[mode]) then
        vim.cmd.stopinsert()
      end
      open({ target_buf = buf, target_win = vim.fn.bufwinid(buf) })
    end
    if group then
      group:map(mode, config.options.editor.open, map)
    else
      vim.keymap.set(
        mode,
        config.options.editor.open,
        map,
        { buffer = buf, desc = "Edit terminal command" }
      )
    end
  end
  return group
end

function M.register_terminal_open(name, open, opts)
  opts = opts or {}
  vim.api.nvim_create_autocmd("TermOpen", {
    group = vim.api.nvim_create_augroup(name, { clear = true }),
    callback = function(args)
      if helpers.is_enabled_terminal(args.buf) then
        M.map_terminal_open(args.buf, open, opts)
      end
    end,
  })
end

function M:setup_terminal_open(name, opts)
  M.register_terminal_open(name, function(ctx)
    return self.open(ctx)
  end, opts)
end

return M
