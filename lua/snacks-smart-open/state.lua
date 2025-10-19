local Util = require('snacks-smart-open.util')

local M = {}

local snapshot ---@type {open_map:table<string,{path:string,bufnr:number,modified:boolean,lastused:number,current:boolean}>,open_list:table[],current_buf:number,current_path:string?,alternate_path:string?,cwd:string?}?

local function gather()
  local current_buf = vim.api.nvim_get_current_buf()
  local current_path = Util.normalize_path(vim.api.nvim_buf_get_name(current_buf))
  local alt_buf = vim.fn.bufnr('#')
  local alternate_path = alt_buf > 0 and Util.normalize_path(vim.api.nvim_buf_get_name(alt_buf)) or nil

  local map, list = {}, {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[buf].buflisted then
      local name = vim.api.nvim_buf_get_name(buf)
      if name ~= '' then
        local path = Util.normalize_path(name)
        if path then
          local info = vim.fn.getbufinfo(buf)[1]
          local entry = {
            path = path,
            bufnr = buf,
            lastused = info and info.lastused or 0,
            modified = vim.bo[buf].modified,
            current = current_path and path == current_path or false,
          }
          map[path] = entry
          list[#list + 1] = entry
        end
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
  }
  return snapshot
end

function M.update()
  if vim.in_fast_event() then
    vim.schedule(M.update)
    return
  end
  local ok = pcall(gather)
  if not ok then
    snapshot = snapshot or {}
  end
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
