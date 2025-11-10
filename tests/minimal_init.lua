local uv = vim.uv or vim.loop

local function ensure_dir(path)
  if not path or path == "" then
    return
  end
  if vim.fn.isdirectory(path) == 0 then
    vim.fn.mkdir(path, "p")
  end
end

local function add_package_path(path)
  if not path or vim.fn.isdirectory(path) == 0 then
    return
  end
  local lua_dir = path .. "/lua"
  if vim.fn.isdirectory(lua_dir) == 1 then
    package.path = lua_dir .. "/?.lua;" .. lua_dir .. "/?/init.lua;" .. package.path
  end
end

local root = vim.fn.fnamemodify(vim.fn.expand("<sfile>"), ":p:h:h")
ensure_dir(root)
vim.opt.runtimepath:prepend(root)
add_package_path(root)

local candidates = {}
if vim.env.SNACKS_NVIM_PATH and vim.env.SNACKS_NVIM_PATH ~= "" then
  table.insert(candidates, vim.env.SNACKS_NVIM_PATH)
end
table.insert(candidates, vim.fn.stdpath("data") .. "/lazy/snacks.nvim")
table.insert(candidates, vim.fn.expand("~/repos/github.com/folke/snacks.nvim"))

for _, path in ipairs(candidates) do
  if vim.fn.isdirectory(path) == 1 then
    vim.opt.runtimepath:append(path)
    add_package_path(path)
    break
  end
end

local function noop() end
_G.Snacks = _G.Snacks or {}
if type(_G.Snacks.notify) ~= "table" then
  _G.Snacks.notify = {}
end
setmetatable(_G.Snacks.notify, { __call = noop })
_G.Snacks.notify.error = _G.Snacks.notify.error or noop

vim.o.swapfile = false
vim.o.writebackup = false
vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1
