local api = require("termline.api")
local config = require("termline.config")
local commands = require("termline.commands")
local shell_integration = require("termline.shell_integration.general")

local M = {
  read_command = api.read_command,
  write_command = api.write_command,
}

local function load_editor()
  local editor = config.options.editor.type
  if editor == nil then
    return nil
  elseif editor == "editable" then
    return require("termline.editors.editable")
  end
  error("termline: config.editor.type must be nil or 'editable'")
end

local function create_autocmds()
  vim.api.nvim_create_autocmd("TermRequest", {
    group = vim.api.nvim_create_augroup("termline-osc133", { clear = true }),
    callback = shell_integration.handle_term_request,
  })
end

---Initialize termline from the plugin entrypoint.
---@param opts? table
function M.setup(opts)
  config.setup(opts)
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
