local config = require("termline.config")
local api = require("termline.api")
local helpers = require("termline.util.helpers")
local log = require("termline.util.log")
local M = {}

local function build_context(ctx)
  ctx = ctx or {}
  local target_buf = ctx.target_buf or vim.api.nvim_get_current_buf()
  return {
    target_buf = target_buf,
    target_win = ctx.target_win or vim.fn.bufwinid(target_buf),
  }
end

---@param buf integer
---@param reason? string
local function set_sync_block_reason(buf, reason)
  M.buffers[buf].sync_block_reason = reason
end

---Read the editable draft command from the terminal buffer.
---@param buf integer
---@return string
function M.read_command(buf)
  local prompt_cursor = M.buffers[buf].promt_cursor
  local lines = vim.api.nvim_buf_get_lines(buf, prompt_cursor[1] - 1, -1, false)
  lines[1] = (lines[1] or ""):sub(prompt_cursor[2] + 1)
  return table.concat(lines, "")
end

local function read_editor_state(buf, win)
  return {
    command = M.read_command(buf),
    cursor = api.command_cursor(win, buf)[2],
  }
end

---@param buf integer
---@param from_cursor integer
---@param to_cursor integer
---Return the editable command zone in the terminal buffer.
---@param buf? integer
---@return { start_row: integer, start_col: integer, end_row: integer, end_col: integer }?
function M.get_editable_zone(buf)
  local target = buf or vim.api.nvim_get_current_buf()
  local bufinfo = M.buffers and M.buffers[target]
  local prompt_cursor = bufinfo and bufinfo.promt_cursor
  if not prompt_cursor then
    return nil
  end
  local start_row, start_col = unpack(prompt_cursor)
  local end_row = vim.api.nvim_buf_line_count(target)
  local line = vim.api.nvim_buf_get_lines(target, end_row - 1, end_row, false)[1] or ""
  return { start_row = start_row, start_col = start_col, end_row = end_row, end_col = #line }
end

---Check if the current cursor is inside the editable command zone.
---@param buf? integer
---@param cursor? integer[]
---@return boolean
function M.is_cursor_in_editable_zone(buf, cursor)
  local zone = M.get_editable_zone(buf)
  if not zone then
    return false
  end
  local row, col = unpack(cursor or vim.api.nvim_win_get_cursor(0))
  if row < zone.start_row or row > zone.end_row then
    return false
  end
  if row == zone.start_row and col < zone.start_col then
    return false
  end
  return row ~= zone.end_row or col <= zone.end_col
end

---Check if cursor is outside the editable zone and move it back if needed.
---@param buf integer
---@param cursor integer[]
local function refresh_editable_state(buf, cursor)
  local prompt_cursor = M.buffers[buf].promt_cursor
  if prompt_cursor and cursor[1] == prompt_cursor[1] and cursor[2] < prompt_cursor[2] then
    cursor[2] = prompt_cursor[2]
    vim.api.nvim_win_set_cursor(0, cursor)
  end
  vim.bo[buf].modifiable = M.is_cursor_in_editable_zone(buf, cursor)
end

---Return write guard delay for a command.
---@param command string
---@return integer
function M.get_write_guard_delay_ms(command)
  return 50
end

---@param buf integer
---@param target? { command?: string, cursor?: integer }
---@return boolean did_sync
function M.write(buf, target)
  local bufinfo = M.buffers[buf]
  bufinfo.has_unsynced_edits = false
  target = target or {}
  if target.command == nil then
    target = read_editor_state(buf, vim.api.nvim_get_current_win())
  end
  local command = target.command
  local cursor = target.cursor
  local delay = M.get_write_guard_delay_ms(command)
  log.debug("editable.write.start", {
    buf = buf,
    has_target = next(target) ~= nil,
    delay = delay,
    sync_block_reason = bufinfo.sync_block_reason,
    has_unsynced_edits = bufinfo.has_unsynced_edits,
  })
  -- Terminal redraw after sync can emit TextChanged events into the same buffer.
  -- Keep a short guard so those redraws are not treated as fresh user edits.
  set_sync_block_reason(buf, "write")
  vim.defer_fn(function()
    if M.buffers[buf] and M.buffers[buf].sync_block_reason == "write" then
      set_sync_block_reason(buf, nil)
    end
    log.debug("editable.writing.stop", { buf = buf })
  end, delay)
  local shell_state = helpers.ensure_buffer_state(api.buffers, buf).shell_state
  local did_sync = shell_state.command ~= command
    or (cursor ~= nil and shell_state.cursor ~= cursor)
  if did_sync then
    api.write_command(command, buf, cursor)
  end
  log.debug("editable.write.done", { buf = buf, did_sync = did_sync })
  return did_sync
end

---@param buf integer
---@param cursor integer
function M.set_term_cursor(buf, cursor)
  local to_cursor = cursor - M.buffers[buf].promt_cursor[2]
  log.debug("editable.set_term_cursor", {
    buf = buf,
    cursor = cursor,
    prompt_cursor = M.buffers[buf].promt_cursor,
    to_cursor = to_cursor,
  })
  M.write(buf, { command = api.read_command(buf), cursor = to_cursor })
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

local function enter_insert_with_target(buf, target_state)
  local target =
    override_state(read_editor_state(buf, vim.api.nvim_get_current_win()), target_state)
  M.write(buf, target)
  vim.cmd.startinsert()
end

---@param buf integer
local function mark_unsynced_edit(buf)
  M.buffers[buf].has_unsynced_edits = true
end

---@param buf integer
local function store_operator_start_cursor(buf)
  M.buffers[buf].operator_start_cursor =
    read_editor_state(buf, vim.api.nvim_get_current_win()).cursor
end

---@param buf integer
---@param cursor integer[]
---@return integer
local function command_offset_from_cursor(buf, cursor)
  local prompt_row, prompt_col = unpack(M.buffers[buf].promt_cursor)
  local offset = 0
  for row = prompt_row, cursor[1] do
    local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1] or ""
    local start_col = row == prompt_row and prompt_col or 0
    local end_col = row == cursor[1] and cursor[2] or #line
    offset = offset + math.max(end_col - start_col, 0)
  end
  return offset
end

---@param buf integer
local function store_visual_start_cursor(buf)
  local visual_pos = vim.fn.getpos("v")
  local current_cursor = vim.api.nvim_win_get_cursor(0)
  local visual_cursor = { visual_pos[2], visual_pos[3] - 1 }
  M.buffers[buf].operator_start_cursor = math.min(
    command_offset_from_cursor(buf, visual_cursor),
    command_offset_from_cursor(buf, current_cursor)
  )
end

---@param buf integer
---@return { command: string, cursor: integer }
local function build_change_target(buf)
  local shell_state = helpers.ensure_buffer_state(api.buffers, buf).shell_state
  local start_offset = M.buffers[buf].operator_start_cursor or shell_state.cursor or 0
  local deleted_text = vim.fn.getreg('"')
  return {
    command = shell_state.command:sub(1, start_offset)
      .. shell_state.command:sub(start_offset + #deleted_text + 1),
    cursor = start_offset,
  }
end

---Handle terminal text changes with the concurrent-write guard.
---@param buf integer
function M.handle_text_changed(buf)
  local bufinfo = M.buffers[buf]
  log.debug("editable.text_changed", {
    buf = buf,
    sync_block_reason = bufinfo.sync_block_reason,
    has_unsynced_edits = bufinfo.has_unsynced_edits,
    line = vim.api.nvim_get_current_line(),
  })
  if not bufinfo.promt_cursor then
    log.debug("editable.text_changed.skip", {
      buf = buf,
      sync_block_reason = bufinfo.sync_block_reason,
      has_unsynced_edits = bufinfo.has_unsynced_edits,
    })
    return
  end
  if bufinfo.sync_block_reason == "term_leave" then
    set_sync_block_reason(buf, nil)
    log.debug("editable.text_changed.skip", {
      buf = buf,
      sync_block_reason = bufinfo.sync_block_reason,
      has_unsynced_edits = bufinfo.has_unsynced_edits,
    })
    return
  end
  if bufinfo.sync_block_reason == "write" or bufinfo.has_unsynced_edits then
    log.debug("editable.text_changed.skip", {
      buf = buf,
      sync_block_reason = bufinfo.sync_block_reason,
      has_unsynced_edits = bufinfo.has_unsynced_edits,
    })
    return
  end
  M.write(buf)
end

---Open the editable terminal editor for the target terminal.
---@param ctx? table
function M.open(ctx)
  ctx = build_context(ctx)
  local buf, win = ctx.target_buf, ctx.target_win
  if not helpers.is_enabled_terminal(buf) then
    error("termline: terminal buffer name does not match editor.terminal_name_pattern")
  end
  local ok, err = pcall(api.clear_completion_suggestions, buf)
  if not ok then
    log.debug("editable clear completions skipped", { buf = buf, error = err })
  end
  local buffer_state = helpers.ensure_buffer_state(api.buffers, buf)
  api.read_command(buf)
  log.debug("editable.open", { buf = buf, win = win, shell_state = buffer_state.shell_state })
  vim.cmd("stopinsert")
  vim.schedule(function()
    local cursor = vim.api.nvim_win_get_cursor(win)
    refresh_editable_state(buf, cursor)
  end)
end

local function apply_keymaps(buf)
  local handlers = {
    open = function()
      log.debug("editable.key.open", { buf = buf, mode = vim.api.nvim_get_mode().mode })
      M.open({ target_buf = buf })
    end,
    submit = function()
      local mode = vim.api.nvim_get_mode().mode
      log.debug("editable.key.submit", { buf = buf, mode = mode })
      if mode:sub(1, 1) == "t" then
        helpers.send_keys("<CR>", buf)
      else
        M.write(buf)
        helpers.send_keys("<CR>", buf)
      end
      vim.cmd("startinsert")
    end,
    write = function()
      log.debug("editable.key.write", { buf = buf, mode = vim.api.nvim_get_mode().mode })
      M.write(buf)
    end,
  }
  vim.keymap.set(
    "t",
    config.options.editor.open,
    handlers.open,
    { buffer = buf, desc = "Edit terminal command" }
  )
  for lhs, spec in pairs(config.options.editor.keys) do
    local mode = vim.tbl_map(function(keymap_mode)
      return keymap_mode == "i" and "t" or keymap_mode
    end, spec.mode)
    local handler = handlers[spec.action]
    if handler then
      vim.keymap.set(mode, lhs, handler, { buffer = buf })
    end
  end
end

---@class Promt
---@field keybinds? Keybinds

---@class Keybinds
---@field clear_current_line string
---@field forward_char string
---@field goto_line_start string

---@class EditableTermConfig
---@field default_keybinds? Keybinds
---@field promts? {[string]: Promt}

---@param config EditableTermConfig
M.setup = function(config)
  M.buffers = {}
  M.promts = (config or {}).promts
  M.default_keybinds = (config or {}).default_keybinds
    or {
      clear_current_line = "<C-e><C-u>",
      forward_char = "<C-f>",
      goto_line_start = "<C-a>",
      goto_line_end = "<C-e>",
    }
  vim.api.nvim_create_autocmd("TermOpen", {
    group = vim.api.nvim_create_augroup("editable-term", {}),
    callback = function(args)
      if not helpers.is_enabled_terminal(args.buf) then
        return
      end
      log.debug("editable.term_open", { buf = args.buf })
      apply_keymaps(args.buf)
      local editgroup =
        vim.api.nvim_create_augroup("editable-term-text-change" .. args.buf, { clear = true })
      M.buffers[args.buf] = {
        has_unsynced_edits = false,
        keybinds = M.default_keybinds,
        sync_block_reason = "term_leave",
      }
      vim.keymap.set("n", "A", function()
        log.debug("editable.key.A", { buf = args.buf })
        enter_insert_with_target(args.buf, {
          cursor = function(current)
            return #current.command
          end,
        })
      end, { buffer = args.buf })
      vim.keymap.set("n", "I", function()
        log.debug("editable.key.I", { buf = args.buf })
        enter_insert_with_target(args.buf, { cursor = 0 })
      end, { buffer = args.buf })
      vim.keymap.set("n", "i", function()
        log.debug("editable.key.i", { buf = args.buf, cursor = vim.api.nvim_win_get_cursor(0) })
        enter_insert_with_target(args.buf)
      end, { buffer = args.buf })
      vim.keymap.set("n", "a", function()
        log.debug("editable.key.a", { buf = args.buf, cursor = vim.api.nvim_win_get_cursor(0) })
        enter_insert_with_target(args.buf, {
          cursor = function(current)
            return current.cursor + 1
          end,
        })
      end, { buffer = args.buf })
      vim.keymap.set("n", "x", function()
        log.debug("editable.key.x", { buf = args.buf, cursor = vim.api.nvim_win_get_cursor(0) })
        mark_unsynced_edit(args.buf)
        vim.cmd("normal! x")
      end, { buffer = args.buf })
      vim.keymap.set("n", "p", function()
        log.debug("editable.key.p", { buf = args.buf, cursor = vim.api.nvim_win_get_cursor(0) })
        mark_unsynced_edit(args.buf)
        vim.cmd("normal! p")
      end, { buffer = args.buf })
      vim.keymap.set("n", "P", function()
        log.debug("editable.key.P", { buf = args.buf, cursor = vim.api.nvim_win_get_cursor(0) })
        mark_unsynced_edit(args.buf)
        vim.cmd("normal! P")
      end, { buffer = args.buf })
      vim.keymap.set("n", "d", function()
        log.debug("editable.key.d", { buf = args.buf, cursor = vim.api.nvim_win_get_cursor(0) })
        store_operator_start_cursor(args.buf)
        mark_unsynced_edit(args.buf)
        return "d"
      end, { buffer = args.buf, expr = true })
      vim.keymap.set("n", "c", function()
        log.debug("editable.key.c", { buf = args.buf, cursor = vim.api.nvim_win_get_cursor(0) })
        store_operator_start_cursor(args.buf)
        return "c"
      end, { buffer = args.buf, expr = true })
      vim.keymap.set("x", "c", function()
        log.debug(
          "editable.key.visual_c",
          { buf = args.buf, cursor = vim.api.nvim_win_get_cursor(0) }
        )
        store_visual_start_cursor(args.buf)
        return "c"
      end, { buffer = args.buf, expr = true })
      vim.api.nvim_create_autocmd("TextYankPost", {
        group = editgroup,
        buffer = args.buf,
        callback = function(args)
          if vim.v.event.operator ~= "c" then
            return
          end
          log.debug("editable.text_yank_post.c", { buf = args.buf, deleted = vim.fn.getreg('"') })
          M.write(args.buf, build_change_target(args.buf))
          vim.cmd.startinsert()
        end,
      })
      vim.api.nvim_create_autocmd("TextChanged", {
        buffer = args.buf,
        group = editgroup,
        callback = function(args)
          M.handle_text_changed(args.buf)
        end,
      })
      vim.api.nvim_create_autocmd("TermLeave", {
        group = editgroup,
        buffer = args.buf,
        callback = function(args)
          local bufinfo = M.buffers[args.buf]
          -- Any TextChanged immediately after leaving terminal mode may come
          -- from the mode switch or shell redraw instead of a deliberate edit.
          set_sync_block_reason(args.buf, "term_leave")
          local ln = vim.api.nvim_get_current_line()
          local cursor = vim.api.nvim_win_get_cursor(0)
          log.debug("editable.term_leave", { buf = args.buf, line = ln, cursor = cursor })
          vim.api.nvim_win_set_cursor(0, cursor)
          line_num = cursor[1]
          if M.promts ~= nil and ln ~= nil then
            for pattern, promt in pairs(M.promts) do
              start, ent = ln:find(pattern)
              if start ~= nil then
                bufinfo.promt_cursor = { line_num, ent }
                bufinfo.keybinds = promt.keybinds or M.default_keybinds
                log.debug("editable.term_leave.prompt_match", {
                  buf = args.buf,
                  pattern = pattern,
                  prompt_cursor = bufinfo.promt_cursor,
                })
                break
              end
            end
          end
          refresh_editable_state(args.buf, cursor)
        end,
      })
      vim.api.nvim_create_autocmd("TermRequest", {
        group = editgroup,
        buffer = args.buf,
        callback = function(args)
          if string.match(args.data.sequence, "^\027]133;B") then
            M.buffers[args.buf].promt_cursor = args.data.cursor
            log.debug("editable.term_request.prompt", { buf = args.buf, cursor = args.data.cursor })
          end
        end,
      })
      vim.api.nvim_create_autocmd("BufDelete", {
        group = editgroup,
        buffer = args.buf,
        callback = function(args)
          vim.api.nvim_del_augroup_by_id(editgroup)
        end,
      })
      vim.api.nvim_create_autocmd("CursorMoved", {
        group = editgroup,
        buffer = args.buf,
        callback = function(args)
          local cursor = vim.api.nvim_win_get_cursor(0)
          local bufinfo = M.buffers[args.buf]
          vim.bo.modifiable = M.is_cursor_in_editable_zone(args.buf, cursor)
          log.debug("editable.cursor_moved", {
            buf = args.buf,
            cursor = cursor,
            prompt_cursor = bufinfo.promt_cursor,
            modifiable = vim.bo.modifiable,
          })
        end,
      })
    end,
  })
end
return M
