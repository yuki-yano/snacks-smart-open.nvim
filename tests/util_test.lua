local MiniTest = require("mini.test")
local Util = require("snacks-smart-open.util")

local function tmpdir()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  return dir
end

local T
T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      T.temp_root = tmpdir()
    end,
    post_case = function()
      if T.temp_root then
        vim.fn.delete(T.temp_root, "rf")
      end
    end,
  },
})
local eq = MiniTest.expect.equality
local no_eq = MiniTest.expect.no_equality

T["normalizes absolute paths without trailing separators"] = function()
  local test_dir = T.temp_root .. "/foo/bar"
  vim.fn.mkdir(test_dir, "p")

  local normalized = Util.normalize_path(test_dir .. "/")

  eq(normalized, vim.fs.normalize(test_dir))
  no_eq(normalized:sub(-1), "/")
end

T["finds project root using markers"] = function()
  local project = T.temp_root .. "/proj"
  local nested = project .. "/src/module"
  vim.fn.mkdir(nested, "p")
  vim.fn.writefile({}, project .. "/.git")
  local file = nested .. "/main.lua"
  vim.fn.writefile({ "" }, file)

  local root = Util.find_project_root(file, { ".git" })

  eq(root, Util.normalize_path(project))
end

T["resolves scope fallback when no markers are found"] = function()
  local project = T.temp_root .. "/plain"
  local nested = project .. "/child"
  vim.fn.mkdir(nested, "p")

  local scope = Util.resolve_scope({ path = nested, markers = { ".nope" } })

  eq(scope, Util.normalize_path(nested))
end

return T
