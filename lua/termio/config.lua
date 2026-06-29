local M = {}

M.defaults = {
  backend = "auto",
  prompt_patterns = { [[^>>> ]], [[^\.\.\. ]] },
  read_replace_patterns = {},
  write_replace_patterns = {},
  clear_interrupt_replace_patterns = { { "\\$", "" }, { "^> ", "" } },
  timeouts = {
    -- Poll for terminal buffer render to catch up to writes.
    render_command = { limit_ms = 50, interval_ms = 2 },
    -- Poll for shell integration to report the integrated command buffer.
    shell_query = { limit_ms = 50, interval_ms = 2 },
  },
  waits = {
    -- Ignore redraw-triggered TextChanged briefly after writing to the shell.
    -- This was needed when text write was done via nvim_chan_send, which could trigger
    -- the written text as user input. Might not be needed anymore.
    integrated_write_guard_ms = 0,
  },
  editor = {
    type = "integrated",
    terminal_name_pattern = [[\v(:| )(/[^ ]*/)?(zsh|bash|fish)( |$)]],
    open = "<Esc>",
    is_disabled = function()
      return false
    end,
    keys = {
      t = {
        ["<Esc>"] = "open",
        ["<CR>"] = "submit",
        ["<C-u>"] = "clear",
        ["<C-s>"] = "write",
        ["<M-t>"] = "toggle",
      },
      n = {
        ["<CR>"] = "submit",
        ["<C-u>"] = "clear",
        ["<C-s>"] = "write",
        ["<Esc>"] = "save_and_close",
        ["<M-t>"] = "toggle",
      },
    },
    popup = {
      open_on_prompt = false,
      keys = {
        i = {
          ["<CR>"] = "submit",
          ["<C-u>"] = "clear",
          ["<C-s>"] = "write",
        },
        n = {
          ["q"] = "close",
          ["j"] = "down",
          ["k"] = "up",
        },
        x = {
          ["j"] = "down",
          ["k"] = "up",
        },
        o = {
          ["j"] = "down",
          ["k"] = "up",
        },
      },
      pass_through_insert_keys = { "<Up>", "<Tab>" },
      pass_through_normal_keys = { "}", "<C-d>", "<C-b>", "G", "L", "/", "?", "n", "N" },
      pass_through_normal_keys_first_line = { "{", "<C-u>", "gg", "H" },
    },
  },
  debug = false,
}

---Store resolved plugin options and return them.
---@param options? table
---@return table
function M.setup(options)
  M.options = vim.deepcopy(vim.tbl_deep_extend("keep", options or {}, M.defaults))
  return M.options
end

return M
