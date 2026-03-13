local Util = require("snacks-smart-open.util")

local uv = vim.uv or vim.loop

local M = {}
local UPDATE_DEBOUNCE_MS = 20

local snapshot ---@type {open_map:table<string,{path:string,bufnr:number,modified:boolean,lastused:number,current:boolean}>,open_list:table[],current_buf:number,current_path:string?,alternate_path:string?,cwd:string?}?
local pending = false

local function gather()
  local current_buf = vim.api.nvim_get_current_buf()
  local current_path = Util.normalize_path(vim.api.nvim_buf_get_name(current_buf))
  local alt_buf = vim.fn.bufnr("#")
  local alternate_path = alt_buf > 0 and Util.normalize_path(vim.api.nvim_buf_get_name(alt_buf)) or nil
  local cwd = Util.normalize_path(uv.cwd() or vim.fn.getcwd())

  local map, list = {}, {}
  for _, info in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
    local buf = info.bufnr
    local name = info.name or ""
    if name ~= "" then
      local path = Util.normalize_path(name)
      if path then
        local entry = {
          path = path,
          bufnr = buf,
          lastused = info.lastused or 0,
          modified = info.changed == 1,
          current = current_path and path == current_path or false,
        }
        map[path] = entry
        list[#list + 1] = entry
      end
    end
  end

  table.sort(list, function(a, b)
    return (a.lastused or 0) > (b.lastused or 0)
  end)

  snapshot = {
    current_buf = current_buf,
    current_path = current_path,
    alternate_path = alternate_path,
    open_map = map,
    open_list = list,
    cwd = cwd,
  }
  return snapshot
end

function M.update()
  if not snapshot and not vim.in_fast_event() then
    local ok = pcall(gather)
    if not ok then
      snapshot = snapshot or {}
    end
    return
  end
  if pending then
    return
  end
  pending = true
  local function refresh()
    pending = false
    local ok = pcall(gather)
    if not ok then
      snapshot = snapshot or {}
    end
  end
  if vim.in_fast_event() then
    vim.schedule(function()
      vim.defer_fn(refresh, UPDATE_DEBOUNCE_MS)
    end)
    return
  end
  vim.defer_fn(refresh, UPDATE_DEBOUNCE_MS)
end

function M.get()
  if snapshot then
    return snapshot
  end
  if vim.in_fast_event() then
    vim.schedule(M.update)
    return snapshot
  end
  return gather()
end

return M
