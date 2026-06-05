local api = require("termline.api")
local config = require("termline.config")
local commands = require("termline.commands")
local helpers = require("termline.util.helpers")

local M = api

local function load_editor()
  local editor = config.options.editor.type
  if editor == nil then
    return nil
  elseif editor == "overlay" then
    return require("termline.editors.overlay")
  elseif editor == "prompt" then
    return require("termline.editors.prompt")
  elseif editor == "integrated" then
    return require("termline.editors.integrated")
  elseif editor == "editable" then
    return require("termline.editors.editable")
  end
  error(
    "termline: config.editor.type must be nil, 'overlay', 'prompt', 'integrated', or 'editable'"
  )
end

local function create_autocmds()
  vim.api.nvim_create_autocmd("TermRequest", {
    group = vim.api.nvim_create_augroup("termline-osc133", { clear = true }),
    callback = function(args)
      -- OSC133 sequences: A prompt start, B prompt end, C pre-exec, D command finish.
      local state = helpers.ensure_buffer_state(api.buffers, args.buf)
      if args.data.sequence:match("^\27]133;A") then
        state.prompt_start_cursor = args.data.cursor
        return
      end
      if not args.data.sequence:match("^\27]133;B") then
        return
      end
      state.prompt_end_cursor = args.data.cursor
      -- HACK: TermRequest arrives before the terminal buffer line shows the new prompt text.
      vim.defer_fn(function()
        if vim.api.nvim_buf_is_valid(args.buf) then
          local prompt = api.update_cached_prompt(args.buf)
          vim.api.nvim_exec_autocmds("User", {
            pattern = "termline-prompt-updated",
            data = { buf = args.buf, cursor = args.data.cursor, prompt = prompt },
            modeline = false,
          })
        end
      end, 10)
      vim.api.nvim_exec_autocmds("User", {
        pattern = "termline-open-on-prompt",
        data = { buf = args.buf, cursor = args.data.cursor },
        modeline = false,
      })
    end,
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
