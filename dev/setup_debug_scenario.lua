local M = {}

local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
local demo = dofile(root .. "/demo.lua")
local debug_tools = dofile(root .. "/debug_tools.lua")
local status = dofile(root .. "/status.lua")

M.debug_tools = debug_tools

local function set_keymaps(extra_keymaps)
  vim.keymap.set("n", "<leader>q", "<Cmd>qa!<CR>")
  vim.keymap.set("n", "<leader>c", function()
    vim.fn.setreg("+", vim.fn.execute("messages"))
  end)
  for _, keymap in ipairs(extra_keymaps or {}) do
    vim.keymap.set(keymap[1], keymap[2], keymap[3])
  end
end

local function get_words()
  local lorem = table.concat({
    "echo lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor incididunt ut labore et dolore magna aliqua ut enim ad minim veniam quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur excepteur sint occaecat cupidatat non proident sunt in culpa qui officia deserunt mollit anim id est laborum",
    "lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor incididunt ut labore et dolore magna aliqua ut enim ad minim veniam quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur excepteur sint occaecat cupidatat non proident sunt in culpa qui officia deserunt mollit anim id est laborum",
    "lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor incididunt ut labore et dolore magna aliqua ut enim ad minim veniam quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur excepteur sint occaecat cupidatat non proident sunt in culpa qui officia deserunt mollit anim id est laborum",
  }, " ")
  local words = vim.split(lorem, " ", { trimempty = true })
  local raw_count = vim.env.LOREM_WORDS
  if not raw_count or raw_count == "" then
    return words
  end
  local count = tonumber(raw_count)
  if not count or count < 0 then
    error("test entrypoint: LOREM_WORDS must be a non-negative integer")
  end
  return vim.list_slice(words, 1, math.min(count, #words))
end

local function format_lines(words)
  if vim.env.MULTILINE ~= "1" then
    return table.concat(words, " ")
  end
  local lines, start = {}, 1
  for i = 1, 3 do
    local remaining_words = #words - start + 1
    local size = math.ceil(remaining_words / (4 - i))
    lines[i] = table.concat(vim.list_slice(words, start, start + size - 1), " ")
    start = start + size
  end
  return table.concat({ lines[1] .. " \\", lines[2] .. " \\", lines[3] }, "\n")
end

local function get_command()
  return format_lines(get_words())
end

function M.setup(opts)
  opts = opts or {}
  _G.termio_debug = debug_tools
  status.setup()
  vim.g.mapleader = " "
  vim.opt.clipboard = "unnamedplus"
  vim.opt.runtimepath:append(vim.fn.fnamemodify(root, ":h"))
  dofile(root .. "/debug_dump_terminal.lua").setup()
  if opts.setup then
    opts.setup()
  end
  set_keymaps(opts.keymaps)
end

---Send input through Neovim input to match user keystrokes.
---@param keys string
function M.open_terminal()
  local layout = vim.env.TERMIO_LAYOUT or "single"
  if layout == "v" then
    vim.cmd.vsplit()
  elseif layout == "h" then
    vim.cmd.split()
  elseif layout ~= "single" then
    error("test entrypoint: invalid layout: " .. layout)
  end
  vim.cmd.terminal()
  M.terminal_buf = vim.api.nvim_get_current_buf()
  M.terminal_win = vim.api.nvim_get_current_win()
  M.terminal_chan = vim.b.terminal_job_id or vim.bo.channel
  debug_tools.attach_terminal(M.terminal_buf, M.terminal_win, M.terminal_chan)
  vim.schedule(function()
    vim.defer_fn(function()
      local command = get_command()
      if command ~= "" then
        vim.api.nvim_input(command)
      end
      vim.cmd.startinsert()
      if vim.env.TERMIO_DEMO == "1" then
        demo.start()
      end
    end, 500)
  end)
end

function M.finish()
  local post_setup = vim.env.TERMIO_POST_SETUP
  if post_setup and post_setup ~= "" then
    vim.cmd(post_setup)
  end
  vim.cmd("qall!")
end

function M.defer_finish(ms)
  vim.defer_fn(M.finish, ms)
end

return M
