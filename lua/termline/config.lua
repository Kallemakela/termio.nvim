local M = {}

M.defaults = {
  clear_current_line = "<C-e><C-u>",
  clear_current_line_check_ms = 10,
  clear_current_line_check_count = 5,
  prompt_refresh_wait_ms = 50,
  read_strip_patterns = { "\\n", "\n> ?", "^%s+$", "%s%s+$" },
  write_strip_patterns = { "\n" },
  ctrl_c_on = { "\n> ?" },
  editor = {
    type = "prompt",
    terminal_name_pattern = [[\v(:| )(/[^ ]*/)?(zsh|bash|fish)( |$)]],
    open_on_prompt = false,
    anchor = "prompt",
    open = "<Esc>",
    pass_through_insert_keys = { "<Up>", "<Tab>" },
    pass_through_normal_keys = { "}", "<C-d>", "<C-b>", "<C-f>", "G", "L" },
    pass_through_normal_keys_first_line = { "{", "<C-u>", "gg", "H" },
    keys = {
      ["<CR>"] = { action = "submit", mode = { "n", "i" } },
      ["<C-u>"] = { action = "clear", mode = { "n", "i" } },
      ["<C-s>"] = { action = "write", mode = { "n", "i" } },
      ["<C-f>"] = { action = "save_and_close", mode = { "n", "i" } },
      ["<Esc>"] = { action = "save_and_close", mode = { "n" } },
      ["q"] = { action = "close", mode = { "n" } },
      ["j"] = { action = "down", mode = { "n", "x", "o" } },
      ["k"] = { action = "up", mode = { "n", "x", "o" } },
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
