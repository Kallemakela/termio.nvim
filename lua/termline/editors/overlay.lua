local api = require("termline.api")
local config = require("termline.config")
local fixbuf = require("termline.editors.fixbuf")
local sync = require("termline.sync")
local helpers = require("termline.util.helpers")
local log = require("termline.util.log")

local M = {}

local function clamp_cursor_to_prompt(edit_buf)
  local prompt = vim.fn.prompt_getprompt(edit_buf)
  local cursor = vim.api.nvim_win_get_cursor(0)
  if cursor[1] ~= 1 or cursor[2] >= #prompt then
    return
  end
  vim.api.nvim_win_set_cursor(0, { 1, #prompt })
end

local function register_cursor_clamp(edit_buf)
  local group = vim.api.nvim_create_augroup("termline-prompt-" .. edit_buf, { clear = true })
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = group,
    buffer = edit_buf,
    callback = function()
      clamp_cursor_to_prompt(edit_buf)
    end,
  })
end

M.get_buftype = function()
  return "prompt"
end
M.get_write_fn = function(target_buf)
  return function(text)
    sync.sync({ command = text, cursor = nil }, target_buf)
  end
end
M.get_editor_text = function(edit_buf)
  local lines = vim.api.nvim_buf_get_lines(edit_buf, 0, -1, false)
  local prompt = vim.fn.prompt_getprompt(edit_buf)
  if #lines > 0 and prompt ~= "" and lines[1]:sub(1, #prompt) == prompt then
    lines[1] = lines[1]:sub(#prompt + 1)
  end
  return table.concat(lines, "\n")
end
M.pre_open = function(edit_buf, ctx)
  local prompt_text = helpers.ensure_buffer_state(api.buffers, ctx.target_buf).prompt
  if not prompt_text or prompt_text == "" then
    vim.wait(50, function()
      prompt_text = helpers.ensure_buffer_state(api.buffers, ctx.target_buf).prompt
      return prompt_text and prompt_text ~= ""
    end)
  end
  vim.fn.prompt_setprompt(edit_buf, prompt_text or "")
  register_cursor_clamp(edit_buf)
end
M.get_initial_lines = function(lines, edit_buf, ctx)
  local prompt = vim.fn.prompt_getprompt(edit_buf)
  lines[1] = prompt .. (lines[1] or "")
  return lines
end
M.get_initial_cursor = function(cursor_pos, edit_buf, ctx)
  local prompt = vim.fn.prompt_getprompt(edit_buf)
  if cursor_pos[1] == 1 then
    return { cursor_pos[1], #prompt + cursor_pos[2] }
  end
  return cursor_pos
end
M.startinsert_on_open = true

local function feed_terminal_key(key)
  vim.api.nvim_feedkeys(helpers.term_codes(key), "t", false)
end

local function feed_normal_key(key)
  vim.api.nvim_feedkeys(helpers.term_codes(key), "n", false)
end

local function close_window(win)
  if vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_close(win, true)
  end
end

local function focus_target(target_win)
  if vim.api.nvim_win_is_valid(target_win) then
    vim.api.nvim_set_current_win(target_win)
  end
end

local function is_first_visual_line()
  return vim.fn.winline() == 1
end

local function sync_target_window_cursor(edit_win, target_win, target_buf)
  local prompt_end_cursor = api.buffers[target_buf].prompt_end_cursor
  local edit_cursor = vim.api.nvim_win_get_cursor(edit_win)
  local row = prompt_end_cursor[1] + edit_cursor[1] - 1
  local col = edit_cursor[1] == 1 and prompt_end_cursor[2] + edit_cursor[2] or edit_cursor[2]
  vim.api.nvim_win_set_cursor(target_win, { row, col })
end

local function keep_cursor_line_at_top(edit_win)
  local cursor = vim.api.nvim_win_get_cursor(edit_win)
  local height = vim.api.nvim_win_get_height(edit_win)
  pcall(vim.api.nvim_win_call, edit_win, function()
    vim.fn.winrestview({ topline = math.max(cursor[1] - height + 1, 1) })
  end)
end

-- Clamp cursor to valid position in the command.
---@param lines string[]
---@param cursor? integer[]
---@return integer[]
local function clamp_cursor(lines, cursor)
  local row = math.min(math.max((cursor or {})[1] or 1, 1), #lines)
  local col = math.min(math.max((cursor or {})[2] or 0, 0), #lines[row])
  return { row, col }
end

local function command_end_cursor(lines)
  local row = math.max(#lines, 1)
  return { row, math.max(#lines[row] - 1, 0) }
end

local function get_fallback_cursor(target_win, target_buf, lines)
  local cursor_pos = api.command_cursor(target_win, target_buf)
  local prompt_end_cursor = api.buffers[target_buf].prompt_end_cursor
  local target_cursor = vim.api.nvim_win_get_cursor(target_win)
  local command_end_row = prompt_end_cursor[1] + #lines - 1
  if
    target_cursor[1] < prompt_end_cursor[1]
    or target_cursor[1] > command_end_row
    or (target_cursor[1] == prompt_end_cursor[1] and target_cursor[2] < prompt_end_cursor[2])
  then
    return command_end_cursor(lines)
  end
  return cursor_pos
end

---@param content string
---@param width integer
---@param command_row integer
---@return integer
local function window_height(content, width, command_row)
  local ui = vim.api.nvim_list_uis()[1]
  local ui_height = ui and ui.height or vim.o.lines
  -- Sum wrapped rows per real line (user may insert newlines in the editor)
  local needed = 0
  for _, line in ipairs(vim.split(content, "\n", { plain = true })) do
    needed = needed + math.max(1, math.ceil(vim.fn.strdisplaywidth(line) / math.max(width, 1)))
  end
  return math.min(needed, math.max(ui_height - command_row, 1))
end

---@param target_win integer
---@param command string
---@param command_screenpos integer[]
---@return table
local function popup_config(target_win, command, command_screenpos)
  local width = vim.api.nvim_win_get_width(target_win)
  local _, win_col = unpack(vim.api.nvim_win_get_position(target_win))
  return {
    relative = "editor",
    style = "minimal",
    border = "none",
    width = width,
    height = window_height(command, width, command_screenpos[1]),
    col = math.max(win_col, 0),
    row = math.max(command_screenpos[1], 0),
  }
end

local function apply_keymaps()
  local open_keymap = config.options.editor.open
  if not open_keymap then
    return
  end
  vim.api.nvim_create_autocmd("TermOpen", {
    callback = function(args)
      local buf = args.buf
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) then
          return
        end
        if not helpers.is_enabled_terminal(buf) then
          return
        end
        vim.keymap.set("n", open_keymap, M.open, { buffer = buf, desc = "Edit terminal command" })
        vim.keymap.set("t", open_keymap, function()
          vim.cmd("stopinsert")
          M.open({ target_buf = buf, target_win = vim.fn.bufwinid(buf) })
        end, { buffer = buf, desc = "Edit terminal command" })
      end)
    end,
  })
end

local function open_on_prompt()
  vim.api.nvim_create_autocmd("User", {
    pattern = "termline-open-on-prompt",
    callback = function(args)
      local target_buf = args.data.buf
      if not helpers.is_enabled_terminal(target_buf) then
        return
      end
      local target_win = vim.fn.bufwinid(target_buf)
      if target_win == -1 or target_win ~= vim.api.nvim_get_current_win() then
        return
      end
      M.open({
        target_buf = target_buf,
        target_win = target_win,
      })
    end,
  })
end

local function build_context(ctx)
  ctx = ctx or {}
  return {
    target_buf = helpers.current_buf(ctx.target_buf),
    target_win = ctx.target_win or vim.api.nvim_get_current_win(),
  }
end

local function set_editor_options(edit_buf, edit_win)
  vim.bo[edit_buf].bufhidden = "wipe"
  vim.bo[edit_buf].buftype = M.get_buftype()
  vim.bo[edit_buf].filetype = "termline"
  vim.bo[edit_buf].swapfile = false
  vim.bo[edit_buf].modifiable = true
  vim.bo[edit_buf].textwidth = 0
  vim.bo[edit_buf].autoindent = false
  vim.bo[edit_buf].smartindent = false
  vim.bo[edit_buf].cindent = false
  vim.bo[edit_buf].formatoptions = vim.bo[edit_buf].formatoptions:gsub("[tca]", "")
  vim.wo[edit_win].wrap = true
end

local function register_resize_hook(edit_buf, edit_win, width, command_row, initial_height)
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    buffer = edit_buf,
    callback = function()
      local content = table.concat(vim.api.nvim_buf_get_lines(edit_buf, 0, -1, false), "\n")
      local target = math.max(window_height(content, width, command_row), initial_height)
      local current = vim.api.nvim_win_get_config(edit_win).height
      if target ~= current then
        vim.api.nvim_win_set_config(edit_win, { height = target })
        keep_cursor_line_at_top(edit_win)
      end
    end,
  })
end

local function action_handlers(ctx, edit_buf, edit_win, last_synced)
  local write_fn = M.get_write_fn(ctx.target_buf)
  local function sync_editor_text()
    local text = M.get_editor_text(edit_buf)
    log.debug(
      "overlay sync request",
      { buf = ctx.target_buf, text = text, last = last_synced.text }
    )
    if text == last_synced.text then
      log.debug("overlay sync skip", { buf = ctx.target_buf })
      return false
    end
    local did_sync = write_fn(text)
    log.debug("overlay sync result", { buf = ctx.target_buf, did_sync = did_sync })
    if did_sync then
      last_synced.text = text
    end
    return did_sync
  end
  local function save_and_close_target()
    sync_editor_text()
    close_window(edit_win)
    focus_target(ctx.target_win)
  end
  local function submit_and_enter_terminal()
    log.debug("overlay submit", { buf = ctx.target_buf })
    sync.sync({ command = M.get_editor_text(edit_buf) .. "\r", cursor = nil }, ctx.target_buf)
    close_window(edit_win)
    focus_target(ctx.target_win)
    -- Switch modes only after submit sync, otherwise InsertLeave can reenter sync.
    vim.schedule(function()
      focus_target(ctx.target_win)
      vim.cmd.stopinsert()
      vim.cmd.startinsert()
    end)
  end
  local function submit()
    submit_and_enter_terminal()
  end
  local function save_and_close()
    save_and_close_target()
  end
  local function write_only()
    sync_editor_text()
  end
  local function clear()
    vim.api.nvim_buf_set_lines(edit_buf, 0, -1, false, { "" })
    vim.api.nvim_win_set_cursor(edit_win, { 1, 0 })
  end
  local function close()
    close_window(edit_win)
    vim.cmd.startinsert()
    focus_target(ctx.target_win)
  end
  local function pass_through_insert(key)
    sync_editor_text()
    close_window(edit_win)
    focus_target(ctx.target_win)
    vim.schedule(function()
      if not vim.api.nvim_win_is_valid(ctx.target_win) then
        return
      end
      focus_target(ctx.target_win)
      vim.cmd.startinsert()
      feed_terminal_key(key)
    end)
  end
  local function pass_through_normal(key)
    sync_editor_text()
    sync_target_window_cursor(edit_win, ctx.target_win, ctx.target_buf)
    close_window(edit_win)
    focus_target(ctx.target_win)
    feed_normal_key(key)
  end
  return {
    submit = submit,
    clear = clear,
    write = write_only,
    save_and_close = save_and_close,
    close = close,
    pass_through_insert = pass_through_insert,
    pass_through_normal = pass_through_normal,
    down = function()
      vim.cmd("normal! gj")
    end,
    up = function()
      if vim.api.nvim_get_mode().mode == "n" and is_first_visual_line() then
        pass_through_normal("k")
        return
      end
      vim.cmd("normal! gk")
    end,
  }
end

local function apply_editor_keymaps(edit_buf, handlers)
  for lhs, spec in pairs(config.options.editor.keys) do
    local handler = handlers[spec.action]
    assert(handler, "termline: unknown editor key action: " .. tostring(spec.action))
    vim.keymap.set(spec.mode, lhs, function()
      handler(lhs)
    end, { buffer = edit_buf })
  end
  for _, key in ipairs(config.options.editor.pass_through_insert_keys) do
    vim.keymap.set("i", key, function()
      handlers.pass_through_insert(key)
    end, { buffer = edit_buf })
  end
  for _, key in ipairs(config.options.editor.pass_through_normal_keys) do
    vim.keymap.set("n", key, function()
      handlers.pass_through_normal(key)
    end, { buffer = edit_buf })
  end
  for _, key in ipairs(config.options.editor.pass_through_normal_keys_first_line) do
    vim.keymap.set("n", key, function()
      if is_first_visual_line() then
        handlers.pass_through_normal(key)
        return
      end
      vim.cmd("normal! " .. key)
    end, { buffer = edit_buf })
  end
end

local function open_editor(ctx)
  if api.should_read_command_shell(ctx.target_buf) then
    local ok, err = pcall(api.clear_completion_suggestions, ctx.target_buf)
    if not ok then
      log.debug("overlay clear completions skipped", { buf = ctx.target_buf, error = err })
    end
  end
  local command = api.read_command(ctx.target_buf)
  local command_screenpos = api.command_screenpos(ctx.target_win, ctx.target_buf)
  local last_synced = { text = command }
  local lines = vim.split(command, "\n", { plain = true })
  local cursor_pos = get_fallback_cursor(ctx.target_win, ctx.target_buf, lines)
  local edit_buf = vim.api.nvim_create_buf(false, false)
  local win_config = popup_config(ctx.target_win, command, command_screenpos)
  local edit_win = vim.api.nvim_open_win(edit_buf, true, win_config)
  set_editor_options(edit_buf, edit_win)
  M.pre_open(edit_buf, ctx)
  lines = M.get_initial_lines(lines, edit_buf, ctx)
  cursor_pos = M.get_initial_cursor(cursor_pos, edit_buf, ctx)
  vim.api.nvim_buf_set_lines(edit_buf, 0, -1, false, lines)
  vim.api.nvim_win_set_cursor(edit_win, clamp_cursor(lines, cursor_pos))
  if M.startinsert_on_open then
    vim.cmd.startinsert()
  end
  register_resize_hook(
    edit_buf,
    edit_win,
    win_config.width,
    command_screenpos[1],
    win_config.height
  )
  fixbuf.register(edit_buf, edit_win, ctx.target_win)
  vim.api.nvim_create_autocmd("InsertLeave", {
    buffer = edit_buf,
    callback = function()
      log.debug("overlay InsertLeave", { buf = ctx.target_buf })
      local text = M.get_editor_text(edit_buf)
      if text == last_synced.text then
        log.debug("overlay InsertLeave skip", { buf = ctx.target_buf })
        return false
      end
      local did_sync = M.get_write_fn(ctx.target_buf)(text)
      log.debug("overlay InsertLeave result", { buf = ctx.target_buf, did_sync = did_sync })
      if did_sync then
        last_synced.text = text
      end
      return did_sync
    end,
  })
  apply_editor_keymaps(edit_buf, action_handlers(ctx, edit_buf, edit_win, last_synced))
end

function M.open(ctx)
  open_editor(build_context(ctx))
end

function M.setup()
  apply_keymaps()
  if config.options.editor.open_on_prompt then
    open_on_prompt()
  end
  vim.api.nvim_create_user_command("TermEditCommand", function()
    M.open()
  end, {})
end

return M
