local api = require("termline.api")
local overlay = require("termline.editors.overlay")
local helpers = require("termline.util.helpers")

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

overlay.get_buftype = function()
  return "prompt"
end

overlay.get_editor_text = function(edit_buf)
  local lines = vim.api.nvim_buf_get_lines(edit_buf, 0, -1, false)
  local prompt = vim.fn.prompt_getprompt(edit_buf)
  if #lines > 0 and prompt ~= "" and lines[1]:sub(1, #prompt) == prompt then
    lines[1] = lines[1]:sub(#prompt + 1)
  end
  return table.concat(lines, "\n")
end

overlay.get_anchor = function()
  return "start"
end

overlay.pre_open = function(edit_buf, ctx)
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

overlay.get_initial_lines = function(lines, edit_buf, ctx)
  local prompt = vim.fn.prompt_getprompt(edit_buf)
  lines[1] = prompt .. (lines[1] or "")
  return lines
end

overlay.get_initial_cursor = function(cursor_pos, edit_buf, ctx)
  local prompt = vim.fn.prompt_getprompt(edit_buf)
  if cursor_pos[1] == 1 then
    return { cursor_pos[1], #prompt + cursor_pos[2] }
  end
  return cursor_pos
end

local M = {}
M.open = overlay.open
M.setup = overlay.setup
return M
