local M = {}

local PATH_SEP = package.config:sub(1, 1)

function M.normalize_path(path)
  if not path or path == '' then
    return nil
  end
  if path:sub(1, 1) == '~' then
    path = vim.fn.expand(path)
  end
  path = vim.fn.fnamemodify(path, ':p')
  local fs = _G.svim and _G.svim.fs or nil
  if fs and fs.normalize then
    path = fs.normalize(path, { _fast = true, expand_env = false })
  elseif vim.fs and vim.fs.normalize then
    path = vim.fs.normalize(path)
  end
  if path == '' then
    return nil
  end
  return path:gsub('/+$', '')
end

function M.calculate_proximity(a, b)
  if not a or not b then
    return 0
  end
  local in_common = 0
  local index = 0
  local previous_index = 1
  while true do
    index = a:find(PATH_SEP, index + 1, true)
    if not index then
      break
    elseif index > 1 then
      if a:sub(previous_index, index) == b:sub(previous_index, index) then
        in_common = in_common + 1
      else
        break
      end
    end
    previous_index = index
  end
  return in_common
end

function M.normalize_proximity(value)
  value = value or 0
  return 1 - 1 / (1 + math.exp(value * 0.5 - 3))
end

return M
