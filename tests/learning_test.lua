local MiniTest = require("mini.test")
local Config = require("snacks-smart-open.config")
local DB = require("snacks-smart-open.db")
local Util = require("snacks-smart-open.util")

local function tmpdir()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  return dir
end

local function reload_learning()
  package.loaded["snacks-smart-open.learning"] = nil
  return require("snacks-smart-open.learning")
end

local function clear_groups()
  pcall(vim.api.nvim_del_augroup_by_name, "snacks_smart_open_state")
  pcall(vim.api.nvim_del_augroup_by_name, "snacks_smart_open_usage")
end

local function wipe_temp_buffers(root)
  local normalized_root = Util.normalize_path(root)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(buf)
    local path = Util.normalize_path(name)
    if path and normalized_root and vim.startswith(path, normalized_root) then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end
end

local function apply_config(db_path, auto_record)
  Config.apply({
    db = { path = db_path },
    learning = { auto_record = auto_record },
  })
end

local T
T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      T.tmp_root = tmpdir()
      T.db_path = T.tmp_root .. "/smart-open.sqlite3"
      DB.close()
      clear_groups()
      apply_config(T.db_path, true)
      T.Learning = reload_learning()
    end,
    post_case = function()
      clear_groups()
      DB.close()
      wipe_temp_buffers(T.tmp_root)
      if T.tmp_root then
        vim.fn.delete(T.tmp_root, "rf")
      end
    end,
  },
})
local eq = MiniTest.expect.equality

T["records usage for repeated events on the same buffer"] = function()
  local file = T.tmp_root .. "/tracked.lua"
  vim.fn.writefile({ "print('ok')" }, file)

  T.Learning.bootstrap(Config.get())
  vim.cmd("silent edit " .. vim.fn.fnameescape(file))
  local buf = vim.api.nvim_get_current_buf()
  local path = Util.normalize_path(vim.api.nvim_buf_get_name(buf))
  vim.api.nvim_exec_autocmds("BufWritePost", { buffer = buf, modeline = false })

  local record = DB.get_file(path)
  eq(record.frequency, 2)
end

T["disables auto recording when refreshed with auto_record=false"] = function()
  local file = T.tmp_root .. "/disabled.lua"
  vim.fn.writefile({ "print('off')" }, file)

  T.Learning.bootstrap(Config.get())
  apply_config(T.db_path, false)
  T.Learning.refresh(Config.get())

  vim.cmd("silent edit " .. vim.fn.fnameescape(file))
  local path = Util.normalize_path(vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf()))

  local record = DB.get_file(path)
  eq(record, nil)
end

T["enables auto recording when refreshed with auto_record=true"] = function()
  local file = T.tmp_root .. "/enabled.lua"
  vim.fn.writefile({ "print('on')" }, file)

  apply_config(T.db_path, false)
  T.Learning = reload_learning()
  T.Learning.bootstrap(Config.get())

  apply_config(T.db_path, true)
  T.Learning.refresh(Config.get())

  vim.cmd("silent edit " .. vim.fn.fnameescape(file))
  local path = Util.normalize_path(vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf()))

  local record = DB.get_file(path)
  eq(record.frequency, 1)
end

T["caps frecency expiration using max_lifetime_days"] = function()
  local file = T.tmp_root .. "/lifetime.lua"
  vim.fn.writefile({ "print('lifetime')" }, file)

  Config.apply({
    db = { path = T.db_path },
    frecency = {
      half_life_days = 0.1,
      max_lifetime_days = 1,
      score_per_access = 100000,
    },
    learning = { auto_record = true },
  })
  T.Learning = reload_learning()
  T.Learning.bootstrap(Config.get())

  vim.cmd("silent edit " .. vim.fn.fnameescape(file))
  local path = Util.normalize_path(vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf()))
  local record = DB.get_file(path)

  assert(record.expiration - record.last_open <= 24 * 60 * 60)
end

return T
