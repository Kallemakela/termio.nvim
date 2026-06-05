--- Terms:
--- - shell state: what the shell currently has
--- - buffer state: state of current visible buffer
--- - target state: wanted state, used as sync target for shell and also sometimes for live buffer
---   - target state is not up to date most of the time, it updated only when needed

local api = require("termline.api")
local config = require("termline.config")
local sync = require("termline.sync")
local helpers = require("termline.util.helpers")
local log = require("termline.util.log")

local M = {}

local function build_context(ctx)
  ctx = ctx or {}
  local target_buf = helpers.current_buf(ctx.target_buf)
  return {
    target_buf = target_buf,
    target_win = ctx.target_win or vim.fn.bufwinid(target_buf),
  }
end

local function read_live_buffer_state(buf, win)
  local ok_state, state = pcall(function()
    return {
      command = api.read_command(buf),
      cursor = api.command_cursor(win, buf)[2],
    }
  end)
  if ok_state then
    return state
  end
  -- Opening before OSC133 state is ready currently falls back to an empty command.
  -- TODO: this seems risky, investigate if necessary
  return { command = "", cursor = 0 }
end

-- TODO: separate to multiple functions, cleanup
function M._set_live_buffer_state(buf, win, target_state)
  local prompt_end_cursor = helpers.ensure_buffer_state(api.buffers, buf).prompt_end_cursor
  if not prompt_end_cursor then
    error("termline: missing OSC133 prompt end cursor")
  end
  local row, prompt_end_col = unpack(prompt_end_cursor)
  local prompt_line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ""
  local command_rows = vim.split(target_state.command, "\n", { plain = true })
  -- Keep the existing prompt text and replace only the editable command area.
  command_rows[1] = prompt_line:sub(1, prompt_end_col) .. command_rows[1]
  log.debug("integrated set live buffer", { buf = buf, win = win, target_state = target_state })
  vim.api.nvim_buf_set_lines(buf, row - 1, vim.api.nvim_buf_line_count(buf), false, command_rows)
  if target_state.cursor == nil then
    return
  end
  local cursor = math.min(target_state.cursor, #target_state.command)
  for index, command_row in ipairs(command_rows) do
    if cursor <= #command_row then
      -- The first command row starts after the prompt; later rows start at column 0.
      vim.api.nvim_win_set_cursor(
        win,
        { row + index - 1, index == 1 and prompt_end_col + cursor or cursor }
      )
      return
    end
    cursor = cursor - #command_row
  end
end

local function close(buf)
  if not vim.bo[buf].modifiable then
    vim.cmd.startinsert()
    return
  end
  vim.bo[buf].modifiable = false
  vim.schedule(function()
    vim.cmd.startinsert()
  end)
end

local function override_state(current, target)
  if not target then
    return current
  end
  if target.command ~= nil then
    current.command = type(target.command) == "function" and target.command(current)
      or target.command
  end
  if target.cursor ~= nil then
    current.cursor = type(target.cursor) == "function" and target.cursor(current) or target.cursor
  end
  return current
end

local function write_and_close(buf)
  log.debug("integrated write_and_close start", { buf = buf })
  M.write({ target_buf = buf })
  close(buf)
end

local function submit(buf)
  log.debug("integrated submit", { buf = buf })
  write_and_close(buf)
  helpers.send_keys("<CR>", buf)
end

local function pass_after_sync(buf, key)
  log.debug("integrated pass_after_sync", { buf = buf, key = key })
  write_and_close(buf)
  helpers.send_keys(key, buf)
end

local function write(buf)
  log.debug("integrated write_only", { buf = buf })
  M.write({ target_buf = buf })
end

local function action_handlers(buf)
  return {
    submit = function()
      submit(buf)
    end,
    write = function()
      write(buf)
    end,
  }
end

local function apply_keymaps()
  local open_keymap = config.options.editor.open
  vim.api.nvim_create_autocmd("TermOpen", {
    callback = function(args)
      if not helpers.is_enabled_terminal(args.buf) then
        return
      end
      local handlers = action_handlers(args.buf)
      vim.keymap.set(
        "n",
        open_keymap,
        M.open,
        { buffer = args.buf, desc = "Edit terminal command" }
      )
      vim.keymap.set("t", open_keymap, function()
        vim.cmd("stopinsert")
        M.open({ target_buf = args.buf, target_win = vim.fn.bufwinid(args.buf) })
      end, { buffer = args.buf, desc = "Edit terminal command" })
      for lhs, spec in pairs(config.options.editor.keys) do
        local handler = handlers[spec.action]
        if handler then
          vim.keymap.set(spec.mode, lhs, function()
            handler(lhs)
          end, { buffer = args.buf })
        end
      end
      for _, key in ipairs(config.options.editor.pass_through_insert_keys) do
        vim.keymap.set({ "n", "i" }, key, function()
          pass_after_sync(args.buf, key)
        end, { buffer = args.buf, desc = "Sync and pass key to terminal" })
      end
    end,
  })
end

---Open the integrated terminal editor for the target terminal.
---@param ctx? table
function M.open(ctx)
  ctx = build_context(ctx)
  local buf, win = ctx.target_buf, ctx.target_win
  if not helpers.is_enabled_terminal(buf) then
    error("termline: terminal buffer name does not match editor.terminal_name_pattern")
  end
  local buffer_state = helpers.ensure_buffer_state(api.buffers, buf)
  buffer_state.target_state = read_live_buffer_state(buf, win)
  buffer_state.shell_state.command = buffer_state.target_state.command
  log.debug("integrated open", { buf = buf, win = win, target_state = buffer_state.target_state })
  vim.bo[ctx.target_buf].modifiable = true
end

---Write the current integrated editor state into the shell.
---@param ctx? table
---@param target_state? table Final shell target state. Fields override the live editor state.
---@return boolean did_sync
function M.write(ctx, target_state)
  ctx = build_context(ctx)
  local buf, win = ctx.target_buf, ctx.target_win
  helpers.assert_terminal(buf)
  local state = helpers.ensure_buffer_state(api.buffers, buf)
  local target_state = override_state(read_live_buffer_state(buf, win), target_state)
  log.debug("integrated write resolved target", {
    buf = buf,
    win = win,
    live_state = read_live_buffer_state(buf, win),
    override = target_state,
    shell_state = state.shell_state,
  })
  local did_sync = sync.sync(target_state, buf, state.shell_state)
  M._set_live_buffer_state(buf, win, target_state)
  log.debug("integrated write result", { did_sync = did_sync, target_state = target_state })
  return did_sync
end

---Register the integrated editor keymaps and command.
function M.setup()
  apply_keymaps()
  vim.api.nvim_create_user_command("TermEditCommand", function()
    M.open()
  end, {})
end

return M
