local M = {}

local Group = {}
Group.__index = Group

-- A group is a set of related keymaps with one shared lifecycle.
-- Normal maps can be disabled; always maps stay active.
---Create a declarative keymap group.
---@param opts? table Default keymap opts and optional initial `enabled` state.
---@return table
function M.group(opts)
  opts = opts or {}
  local enabled = opts.enabled
  if enabled == nil then
    enabled = true
  end
  local keymap_opts = vim.tbl_extend("force", {}, opts)
  keymap_opts.enabled = nil
  return setmetatable({
    always_maps = {},
    enabled = enabled,
    maps = {},
    opts = keymap_opts,
  }, Group)
end

local function merged_opts(defaults, opts)
  return vim.tbl_extend("force", defaults, opts or {})
end

local function make_entry(defaults, mode, lhs, rhs, opts)
  opts = merged_opts(defaults, opts)
  local fallback = opts.fallback
  opts.fallback = nil
  return { fallback = fallback, mode = mode, lhs = lhs, rhs = rhs, opts = opts }
end

local function set_entry(entry)
  vim.keymap.set(entry.mode, entry.lhs, entry.rhs, entry.opts)
  entry.installed = true
end

---@param mode string|string[]
---@param lhs string
---@param rhs string|function
---@param opts? table
---Add and install a keymap controlled by the group lifecycle.
---Disabled groups store the map but do not install it.
function Group:map(mode, lhs, rhs, opts)
  local entry = make_entry(self.opts, mode, lhs, rhs, opts)
  table.insert(self.maps, entry)
  if self.enabled then
    set_entry(entry)
  end
end

---@param mode string|string[]
---@param lhs string
---@param rhs string|function
---@param opts? table
---Add and install a keymap that stays active while normal maps are disabled.
---Use this for controls that must remain available, such as toggles.
function Group:always(mode, lhs, rhs, opts)
  local entry = make_entry(self.opts, mode, lhs, rhs, opts)
  table.insert(self.always_maps, entry)
  vim.keymap.set(mode, lhs, rhs, entry.opts)
end

local function set_entries(entries)
  for _, entry in ipairs(entries) do
    set_entry(entry)
    entry.fallback_installed = false
  end
end

local function each_mode(mode)
  if type(mode) == "table" then
    return ipairs(mode)
  end
  return ipairs({ mode })
end

local function delete_entry(entry)
  for _, mode in each_mode(entry.mode) do
    vim.keymap.del(mode, entry.lhs, entry.opts)
  end
end

local function delete_entries(entries)
  for _, entry in ipairs(entries) do
    delete_entry(entry)
  end
end

local function set_fallback_entries(entries)
  for _, entry in ipairs(entries) do
    if entry.fallback then
      vim.keymap.set(entry.mode, entry.lhs, entry.fallback, entry.opts)
      entry.fallback_installed = true
    else
      delete_entry(entry)
    end
    entry.installed = false
  end
end

---Install normal maps in the group.
function Group:enable()
  self.enabled = true
  set_entries(self.maps)
end

---Remove normal maps while leaving always maps installed.
---Fallback maps are installed for normal maps that define `fallback`.
function Group:disable()
  if not self.enabled then
    return
  end
  self.enabled = false
  set_fallback_entries(vim.tbl_filter(function(entry)
    return entry.installed
  end, self.maps))
end

return M
