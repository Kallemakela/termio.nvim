local M = {}
local api = require("termline.api")
local helpers = require("termline.util.helpers")
local log = require("termline.util.log")

---@param buf integer
---@return integer
local function read_visible_cursor(buf)
  local win = vim.fn.bufwinid(buf)
  if win == -1 then
    error("termline: buffer is not visible, cannot read command cursor")
  end
  return api.command_cursor(win, buf)[2]
end

---@param buf integer
---@param from_cursor integer
---@param to_cursor integer
---@return boolean
local function sync_cursor(buf, from_cursor, to_cursor)
  local delta = to_cursor - from_cursor
  if delta == 0 then
    return false
  end
  local bytes = (delta > 0 and "\27[C" or "\27[D"):rep(math.abs(delta))
  -- log.debug("sync cursor", { buf = buf, from = from_cursor, to = to_cursor, delta = delta })
  helpers.send_bytes(bytes, buf)
  return true
end

---@param target table
---@param current table
---@return boolean
local function needs_cursor_sync(target, current)
  log.debug("check cursor sync", { target_cursor = target.cursor, current_cursor = current.cursor })
  return target.cursor ~= nil and target.cursor ~= current.cursor
end

---@param command string
---@return string, boolean
local function split_submit_command(command)
  local should_submit = command:sub(-1) == "\r"
  return should_submit and command:sub(1, -2) or command, should_submit
end

---@param target table
---@param buf integer
---@return boolean
local function write_shell_command(target, buf)
  if not api.should_read_command_shell(buf) then
    return false
  end
  local command, should_submit = split_submit_command(target.command)
  api.write_command_shell(command, target.cursor, buf)
  if should_submit then
    helpers.send_keys("<CR>", buf)
  end
  return true
end

---@param buf integer
---@param target table
---@param current? table
---@return table
local function normalize_state(buf, target, current)
  if current then
    if target.cursor ~= nil and current.cursor == nil and current.command == target.command then
      current.cursor = read_visible_cursor(buf)
    end
    return current
  end
  return {
    command = api.read_command(buf),
    cursor = target.cursor ~= nil and read_visible_cursor(buf) or nil,
  }
end

---Return true when terminal state differs from the target state.
---@param current table
---@param target table
---@return boolean
function M.needs_sync(current, target)
  return current.command ~= target.command or needs_cursor_sync(target, current)
end

---Sync terminal input to the given target state.
---@param target table
---@param buf integer
---@param current? table
---@return boolean did_sync
function M.sync(target, buf, current)
  log.debug("sync start", { target = target, current = current })
  local has_current = current ~= nil
  local current = normalize_state(buf, target, current)
  if not M.needs_sync(current, target) then
    return false
  end
  if current.command ~= target.command then
    if write_shell_command(target, buf) then
      current.command = target.command
      current.cursor = #target.command
    else
      api.clear_command(buf, { skip_verify = has_current })
      api.write_command(target.command, buf)
    end
  end
  if needs_cursor_sync(target, current) then
    log.debug(
      "cursor out of sync",
      { current_cursor = current.cursor, target_cursor = target.cursor }
    )
    sync_cursor(buf, current.cursor, target.cursor)
    current.cursor = target.cursor
  end
  return true
end

return M
