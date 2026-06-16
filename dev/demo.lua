local M = {}

local function send(keys)
  vim.api.nvim_input(keys)
end

function M.start()
  local initial_wait_ms = 200
  local key_wait_ms = 40
  local command_wait_ms = 200
  local submit_wait_ms = 1000
  local delay = initial_wait_ms
  local function step(wait, keys)
    delay = delay + wait
    vim.defer_fn(function()
      send(keys)
    end, delay)
  end
  local function type_keys(...)
    for _, keys in ipairs({ ... }) do
      step(key_wait_ms, keys)
    end
  end
  local function command_keys(...)
    for _, keys in ipairs({ ... }) do
      step(command_wait_ms, keys)
    end
  end

  step(1000, "")
  type_keys(" ", "w", "o", "r", "r", "d")
  command_keys("<Esc>", "b", "b", "e", "v", "[[", "E", "E", "E", "b")
  step(200, "")
  command_keys("c")
  type_keys("h", "e", "l", "l", "o", "<Esc>")
  step(200, "")
  command_keys("A", "!", "<Esc>")
  command_keys("Fr")
  command_keys("rl")
  step(50, "")
  command_keys("?", "h", "e", "l", "l", "o", "<CR>")
  step(50, "")
  command_keys("ce")
  type_keys("g", "o", "o", "d", "b", "y", "e")
  step(200, "")
  command_keys("<CR>")
  type_keys("c", "a", "t")
  step(500, "<Up>")
  step(500, "<Down>")
  step(500, "<Esc>")
  command_keys("a")
  command_keys(" ", "R", "<Tab>", "<CR>")
  step(100, "")
  command_keys("<CR>")
  step(500, "<Esc>")
  command_keys("?")
  command_keys(".", "/", "d", "o", "c")
  step(200, "")
  command_keys("<CR>", "n")
  step(200, "")
  command_keys("vi(")
  step(200, "")
  command_keys("y", "a")
  step(200, "")
  type_keys("c", "a", "t", " ")
  step(200, "")
  command_keys("<Esc>", "p")
  step(500, "<CR>")
end

return M
