local Util = require("snacks-smart-open.util")

local function tmpdir()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  return dir
end

describe("snacks-smart-open util", function()
  local temp_root

  before_each(function()
    temp_root = tmpdir()
  end)

  after_each(function()
    if temp_root then
      vim.fn.delete(temp_root, "rf")
    end
  end)

  it("normalizes absolute paths without trailing separators", function()
    local test_dir = temp_root .. "/foo/bar"
    vim.fn.mkdir(test_dir, "p")
    local normalized = Util.normalize_path(test_dir .. "/")
    assert.are.equal(vim.fs.normalize(test_dir), normalized)
    assert.are_not.equal("/", normalized:sub(-1))
  end)

  it("finds project root using markers", function()
    local project = temp_root .. "/proj"
    local nested = project .. "/src/module"
    vim.fn.mkdir(nested, "p")
    vim.fn.writefile({}, project .. "/.git")
    local file = nested .. "/main.lua"
    vim.fn.writefile({ "" }, file)

    local root = Util.find_project_root(file, { ".git" })
    assert.are.equal(Util.normalize_path(project), root)
  end)

  it("resolves scope fallback when no markers are found", function()
    local project = temp_root .. "/plain"
    local nested = project .. "/child"
    vim.fn.mkdir(nested, "p")

    local scope = Util.resolve_scope({ path = nested, markers = { ".nope" } })
    assert.are.equal(Util.normalize_path(nested), scope)
  end)
end)
