local MiniTest = require("mini.test")
local Util = require("snacks-smart-open.util")

local function tmpdir()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  return dir
end

local function reload_state()
  package.loaded["snacks-smart-open.state"] = nil
  return require("snacks-smart-open.state")
end

local T
T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      T.tmp_root = tmpdir()
      T.file = T.tmp_root .. "/state.lua"
      vim.fn.writefile({ "return true" }, T.file)
      vim.cmd("silent edit " .. vim.fn.fnameescape(T.file))
      T.State = reload_state()
    end,
    post_case = function()
      package.loaded["snacks-smart-open.state"] = nil
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        local path = Util.normalize_path(vim.api.nvim_buf_get_name(buf))
        if path and T.tmp_root and vim.startswith(path, Util.normalize_path(T.tmp_root)) then
          pcall(vim.api.nvim_buf_delete, buf, { force = true })
        end
      end
      if T.tmp_root then
        vim.fn.delete(T.tmp_root, "rf")
      end
    end,
  },
})

local eq = MiniTest.expect.equality

T["coalesces repeated update requests"] = function()
  local original_list_bufs = vim.api.nvim_list_bufs
  local count = 0
  vim.api.nvim_list_bufs = function(...)
    count = count + 1
    return original_list_bufs(...)
  end

  T.State.update()
  count = 0

  T.State.update()
  T.State.update()
  T.State.update()

  vim.wait(200, function()
    return count > 0
  end)
  vim.api.nvim_list_bufs = original_list_bufs

  eq(count, 1)
end

return T
