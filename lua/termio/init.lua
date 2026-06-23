local api = require("termio.api")
local config = require("termio.config")
local commands = require("termio.commands")
local shell_state = require("termio.shell_state")
local state = require("termio.state")

local M = {
  disable = state.disable,
  enable = state.enable,
  toggle = state.toggle,
  is_enabled = state.is_enabled,
  read_command = api.read_command,
  write_command = api.write_command,
}

local function load_editor()
  local editor = config.options.editor.type
  if editor == nil then
    return nil
  elseif editor == "editable" then
    return require("termio.editors.editable")
  end
  error("termio: config.editor.type must be nil or 'editable'")
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
  state.enable({ notify = false })
  commands.setup()
  local editor = load_editor()
  if editor then
    editor.setup()
  end
  if M.initialized then
    return M
  end
  create_autocmds()
  M.initialized = true
  return M
end

return M
