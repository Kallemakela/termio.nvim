local M = {}

M.defaults = {
  write_strip_patterns = { "\n" },
  editor = {
    type = "editable",
    terminal_name_pattern = [[\v(:| )(/[^ ]*/)?zsh( |$)]],
    open = "<Esc>",
    keys = {
      ["<CR>"] = { action = "submit", mode = { "n", "i" } },
      ["<C-u>"] = { action = "clear", mode = { "n", "i" } },
      ["<C-s>"] = { action = "write", mode = { "n", "i" } },
      ["<Esc>"] = { action = "save_and_close", mode = { "n" } },
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
