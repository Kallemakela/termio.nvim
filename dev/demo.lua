local M = {}

local function send(keys)
  vim.api.nvim_input(keys)
end

function M.start()
  local initial_wait_ms = 200
  local key_wait_ms = 50
  local command_wait_ms = 300
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

  step(0, "")
  type_keys("c", "h", "o", " ", "h", "e", "l", "l", "o", " ", "w", "o", "r", "l", "d")
  step(command_wait_ms, "<Esc>")
  command_keys("b", "b", "cw")
  type_keys("g", "o", "o", "d", "b", "y", "e", "<Esc>")
  step(50, "")
  command_keys("A")
  step(200, "")
  type_keys(
    ",",
    " ",
    "i",
    "t",
    " ",
    "w",
    "a",
    "s",
    " ",
    "n",
    "i",
    "c",
    "e",
    " ",
    "w",
    "h",
    "i",
    "l",
    "e",
    " ",
    "i",
    "t",
    " ",
    "l",
    "a",
    "s",
    "t",
    "e",
    "d",
    "<Esc>"
  )
  step(50, "")
  command_keys("I")
  step(200, "")
  type_keys("e", "<Esc>")
  command_keys("A")
  step(50, "")
  type_keys("!", "<CR>")
  step(submit_wait_ms, "<Esc>")
  command_keys("a")
  type_keys("c", "a", "t")
  step(command_wait_ms, "<Up>")
  step(100, "")
  step(command_wait_ms, "<Down>")
  step(100, "")
  step(command_wait_ms, "<Esc>")
  command_keys("a")
  command_keys(" ", "R", "<Tab>", "<CR>")
  step(100, "")
  command_keys("<CR>")
end

return M
