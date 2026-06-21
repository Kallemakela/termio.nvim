# TUI detection

Neovim does not have a clean way to check if the terminal is in altscreen. Issue:
https://github.com/neovim/neovim/issues/40293

You can still track terminal alt-screen state if you want `editor.is_disabled` to ignore TUIs, but complex. Example:

```lua
local tui = {}

local ALT_SCREEN_ENTER = { "\27[?1049h", "\27[?1047h", "\27[?47h" }
local ALT_SCREEN_LEAVE = { "\27[?1049l", "\27[?1047l", "\27[?47l" }
local ALT_SCREEN_SUFFIX_LEN = 7

local function last_match(text, patterns)
  local last_index
  for _, pattern in ipairs(patterns) do
    local start = 1
    while true do
      local index = text:find(pattern, start, true)
      if not index then
        break
      end
      if not last_index or index > last_index then
        last_index = index
      end
      start = index + 1
    end
  end
  return last_index
end

function tui.init(buf)
  vim.b[buf].term_tui_active = false
  vim.b[buf].term_tui_pending = ""
end

function tui.track(buf, data)
  local text = (vim.b[buf].term_tui_pending or "") .. table.concat(data, "")
  local enter_index = last_match(text, ALT_SCREEN_ENTER)
  local leave_index = last_match(text, ALT_SCREEN_LEAVE)
  if enter_index or leave_index then
    vim.b[buf].term_tui_active = leave_index == nil or (enter_index or 0) > leave_index
  end
  vim.b[buf].term_tui_pending = text:sub(-ALT_SCREEN_SUFFIX_LEN)
end

local buf = vim.api.nvim_create_buf(false, true)
tui.init(buf)
vim.fn.termopen(vim.o.shell, {
  on_stdout = function(_, data)
    tui.track(buf, data)
  end,
})
```

Then disable termio while alt-screen is active:

```lua
require("termio").setup({
  editor = {
    is_disabled = function(buf)
      return vim.b[buf].term_tui_active == true
    end,
  },
})
```
