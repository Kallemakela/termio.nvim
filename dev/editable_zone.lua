local M = {}
local ns = vim.api.nvim_create_namespace("termio-editable-zone-debug")

---@param buf? integer
---@return integer
local function current_buf(buf)
  return buf or vim.api.nvim_get_current_buf()
end

---@param buf integer
---@return { start_row: integer, start_col: integer, end_row: integer, end_col: integer }?
function M.get(buf)
  local editable = require("termio.editors.editable")
  local target_buf = current_buf(buf)
  local zone = editable.get_editable_zone(target_buf)
  if not zone then
    return nil
  end
  local end_row = vim.api.nvim_buf_line_count(target_buf)
  local line = vim.api.nvim_buf_get_lines(target_buf, end_row - 1, end_row, false)[1] or ""
  return {
    start_row = zone.start_row,
    start_col = zone.start_col,
    end_row = end_row,
    end_col = #line,
  }
end

---@param buf? integer
function M.clear(buf)
  vim.api.nvim_buf_clear_namespace(current_buf(buf), ns, 0, -1)
end

---@param buf? integer
function M.highlight(buf)
  local target_buf = current_buf(buf)
  M.clear(target_buf)
  local zone = M.get(target_buf)
  if not zone then
    vim.notify("termio: no editable zone detected", vim.log.levels.INFO)
    return
  end
  vim.api.nvim_buf_set_extmark(target_buf, ns, zone.start_row - 1, zone.start_col, {
    end_row = zone.end_row - 1,
    end_col = zone.end_col,
    hl_group = "Visual",
  })
end

---@param buf? integer
function M.show(buf)
  local zone = M.get(buf)
  if not zone then
    vim.notify("termio: no editable zone detected", vim.log.levels.INFO)
    return
  end
  M.highlight(buf)
  vim.notify(
    string.format(
      "editable zone rows=%d..%d cols=%d..%d",
      zone.start_row,
      zone.end_row,
      zone.start_col,
      zone.end_col
    ),
    vim.log.levels.INFO
  )
end

return M
