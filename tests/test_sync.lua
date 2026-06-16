local T = MiniTest.new_set()
local sync = require("termline.sync")

T["sync_state()"] = MiniTest.new_set()

local function mock_api(opts)
  opts = opts or {}
  local calls = { clear = 0, write = 0, read = 0, cursor = 0, bytes = 0 }
  local api = require("termline.api")
  api.read_command = function()
    calls.read = calls.read + 1
    return opts.command or "echo synced"
  end
  api.command_cursor = function()
    calls.cursor = calls.cursor + 1
    return { 1, 0 }
  end
  api.clear_command = function(_, opts)
    calls.clear = calls.clear + 1
    calls.clear_opts = opts
  end
  api.write_command = function(command)
    calls.write = calls.write + 1
    calls.command = command
  end
  api.should_read_command_shell = function()
    return opts.should_read_command_shell == true
  end
  api.write_command_shell = function(command, cursor)
    calls.shell_write = (calls.shell_write or 0) + 1
    calls.shell_command = command
    calls.shell_cursor = cursor
    if opts.shell_write_error then
      error(opts.shell_write_error)
    end
  end
  api.send_bytes = function()
    calls.bytes = calls.bytes + 1
  end
  return calls
end

T["sync_state()"]["syncs changed command"] = function()
  local calls = mock_api({ command = "echo stale" })
  local did_sync = sync.sync({ command = "echo synced", cursor = nil }, 1)
  MiniTest.expect.equality(did_sync, true)
  MiniTest.expect.equality(calls.clear, 1)
  MiniTest.expect.equality(calls.write, 1)
  MiniTest.expect.equality(calls.command, "echo synced")
  MiniTest.expect.equality(calls.read, 1)
  MiniTest.expect.equality(calls.cursor, 0)
  MiniTest.expect.equality(calls.bytes, 0)
  MiniTest.expect.equality(calls.clear_opts.skip_verify, false)
end

T["sync_state()"]["skips clear verification with explicit current state"] = function()
  local calls = mock_api()
  local did_sync = sync.sync(
    { command = "echo synced", cursor = nil },
    1,
    { command = "echo stale" }
  )
  MiniTest.expect.equality(did_sync, true)
  MiniTest.expect.equality(calls.clear, 1)
  MiniTest.expect.equality(calls.write, 1)
  MiniTest.expect.equality(calls.read, 0)
  MiniTest.expect.equality(calls.clear_opts.skip_verify, true)
end

T["sync_state()"]["skips identical terminal input"] = function()
  local calls = mock_api()
  local did_sync = sync.sync({ command = "echo synced", cursor = nil }, 1)
  MiniTest.expect.equality(did_sync, false)
  MiniTest.expect.equality(calls.clear, 0)
  MiniTest.expect.equality(calls.write, 0)
  MiniTest.expect.equality(calls.read, 1)
  MiniTest.expect.equality(calls.cursor, 0)
  MiniTest.expect.equality(calls.bytes, 0)
end

T["sync_state()"]["shell write errors instead of falling back"] = function()
  local calls = mock_api({
    command = "echo stale",
    should_read_command_shell = true,
    shell_write_error = "boom",
  })
  local ok, err = pcall(sync.sync, { command = "echo synced", cursor = nil }, 1)
  MiniTest.expect.equality(ok, false)
  MiniTest.expect.equality(err:match("boom") ~= nil, true)
  MiniTest.expect.equality(calls.shell_write, 1)
  MiniTest.expect.equality(calls.clear, 0)
  MiniTest.expect.equality(calls.write, 0)
end

return T
