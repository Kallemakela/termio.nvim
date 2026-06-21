local api = require("termio.api")
local config = require("termio.config")
local shell_integration = require("termio.shell_integration.general")

local M = {}

local required_markers = {
  { name = "OSC 133;A", pattern = "^\27]133;A" },
  { name = "OSC 133;B", pattern = "^\27]133;B" },
  { name = "OSC 133;C", pattern = "^\27]133;C" },
  { name = "OSC 133;D", pattern = "^\27]133;D" },
  { name = "OSC 633;I", pattern = "^\27]633;I" },
  { name = "OSC 633;Q", pattern = "^\27]633;Q" },
  { name = "OSC 633;W", pattern = "^\27]633;W" },
}

local function report()
  local health = vim.health
  if health.start then
    return health
  end
  return { start = health.report_start, ok = health.report_ok, error = health.report_error }
end

local function wait_until(timeout_ms, predicate)
  return vim.wait(timeout_ms, predicate, 20)
end

local function terminal_command(opts)
  if opts and opts.command then
    return opts.command
  end
  return { vim.o.shell, "-i" }
end

local function marker_status(sequences)
  local seen = {}
  local missing = {}
  for _, marker in ipairs(required_markers) do
    seen[marker.name] = false
    for _, sequence in ipairs(sequences) do
      if sequence:match(marker.pattern) then
        seen[marker.name] = true
        break
      end
    end
    if not seen[marker.name] then
      table.insert(missing, marker.name)
    end
  end
  return seen, missing
end

---Open a temporary terminal and verify the user's shell emits every marker.
---@param opts? { command: string[]|string, timeout_ms: integer? }
---@return { ok: boolean, missing: string[], seen: table<string, boolean>, sequences: string[], errors: string[] }
function M.check_markers(opts)
  opts = opts or {}
  if not config.options then
    config.setup()
  end
  local timeout_ms = opts.timeout_ms or 3000
  local buf = vim.api.nvim_create_buf(false, true)
  local sequences = {}
  local errors = {}
  shell_integration.use_buffers(api.buffers)

  local group = vim.api.nvim_create_augroup("termio-health-marker-check", { clear = true })
  vim.api.nvim_create_autocmd("TermRequest", {
    group = group,
    buffer = buf,
    callback = function(args)
      table.insert(sequences, args.data.sequence)
      shell_integration.handle_term_request(args)
    end,
  })

  vim.api.nvim_buf_call(buf, function()
    vim.fn.termopen(terminal_command(opts))
  end)
  wait_until(timeout_ms, function()
    return api.buffers[buf]
      and api.buffers[buf].shell_fifo_path ~= nil
      and api.buffers[buf].prompt_end_cursor ~= nil
  end)

  local channel = vim.b[buf].terminal_job_id
  if channel then
    local ok, err = pcall(api.read_command, buf, timeout_ms)
    if not ok then
      table.insert(errors, err)
    end
    ok, err = pcall(api.write_command, "", buf)
    if not ok then
      table.insert(errors, err)
    end
    vim.api.nvim_chan_send(channel, "echo termio-health\n")
    wait_until(timeout_ms, function()
      return api.buffers[buf] and api.buffers[buf].shell_exit_status ~= nil
    end)
  end

  local seen, missing = marker_status(sequences)
  vim.api.nvim_del_augroup_by_id(group)
  pcall(vim.api.nvim_buf_delete, buf, { force = true })
  api.buffers[buf] = nil
  return {
    ok = #missing == 0,
    missing = missing,
    seen = seen,
    sequences = sequences,
    errors = errors,
  }
end

function M.check()
  local health = report()
  health.start("termio.nvim")
  local result = M.check_markers()
  for _, marker in ipairs(required_markers) do
    if result.seen[marker.name] then
      health.ok(marker.name)
    else
      health.error(marker.name .. " missing")
    end
  end
  for _, err in ipairs(result.errors) do
    health.error(err)
  end
end

return M
