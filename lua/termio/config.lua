local M = {}

M.defaults = {
  write_strip_patterns = { "\n" },
  timeouts = {
    -- Poll for shell integration to publish its FIFO after terminal startup.
    fifo_ready = { limit_ms = 50, interval_ms = 2 },
    -- Poll for a shell query reply before read_command() fails.
    read_command = { limit_ms = 50, interval_ms = 2 },
    -- Poll for a shell write acknowledgement before write_command() fails.
    write_command = { limit_ms = 50, interval_ms = 2 },
  },
  waits = {
    -- Let terminal PTY redraw bytes drain after a query reply.
    read_render_drain_ms = 20,
    -- Ignore redraw-triggered TextChanged briefly after writing to the shell.
    editable_write_guard_ms = 50,
    -- Let bash render the command after waking readline.
    bash_wake_render_ms = 30,
  },
  editor = {
    type = "editable",
    terminal_name_pattern = [[\v(:| )(/[^ ]*/)?(zsh|bash)( |$)]],
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
