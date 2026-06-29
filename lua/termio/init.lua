local api = require("termio.api")
local config = require("termio.config")
local commands = require("termio.commands")
local shell_state = require("termio.shell_state")
local state = require("termio.state")
local active_editor

local M = {
  is_enabled = state.is_enabled,
  read_command = api.read_command,
  update_prompt_range = api.update_prompt_range,
  prompt_range = api.prompt_range,
  clear_command = api.clear_command,
  write_command = api.write_command,
  command_start_cursor = api.command_start_cursor,
  cursor_index_in_command = api.cursor_index_in_command,
}

local function load_editor()
  local editor = config.options.editor.type
  if editor == nil then
    return nil
  elseif editor == "integrated" then
    return require("termio.editors.integrated")
  end
  error("termio: config.editor.type must be nil or 'integrated'")
end

---Enable termio integrations and reload enabled-only editor resources.
---@param opts? { notify?: boolean }
function M.enable(opts)
  state.enable(opts)
  if active_editor and active_editor.enable then
    active_editor.enable()
  end
end

---Disable termio integrations and unload enabled-only editor resources.
function M.disable()
  state.disable()
  if active_editor and active_editor.disable then
    active_editor.disable()
  end
end

function M.toggle()
  if state.is_enabled() then
    M.disable()
  else
    M.enable()
  end
end

local function create_autocmds()
  vim.api.nvim_create_autocmd("TermRequest", {
    group = vim.api.nvim_create_augroup("termio-osc133", { clear = true }),
    callback = function(args)
      shell_state.handle_term_request(api.buffers, args)
    end,
  })
end

---Initialize termio from the plugin entrypoint.
---@param opts? table
function M.setup(opts)
  config.setup(opts)
  commands.setup()
  active_editor = load_editor()
  if active_editor then
    active_editor.setup()
  end
  M.enable({ notify = false })
  if M.initialized then
    return M
  end
  create_autocmds()
  M.initialized = true
  return M
end

return M
