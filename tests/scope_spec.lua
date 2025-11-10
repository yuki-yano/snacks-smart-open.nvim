local uv = vim.uv or vim.loop

local Config = require("snacks-smart-open.config")
local DB = require("snacks-smart-open.db")
local Learning = require("snacks-smart-open.learning")
local Util = require("snacks-smart-open.util")

local function tmpdir()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  return dir
end

local function fresh_config()
  local dir = tmpdir()
  local db_path = dir .. "/smart-open.sqlite3"
  DB.close()
  Config.apply({ db = { path = db_path } })
  return dir, db_path
end

describe("snacks-smart-open scoped weights", function()
  local tmp_root

  before_each(function()
    tmp_root = tmpdir()
    local db_path = tmp_root .. "/smart-open.sqlite3"
    DB.close()
    Config.apply({ db = { path = db_path } })
  end)

  after_each(function()
    DB.close()
    if tmp_root then
      vim.fn.delete(tmp_root, "rf")
    end
  end)

  it("keeps weight rows isolated per scope", function()
    local defaults = Config.get().weights
    DB.save_weights({ path_fzf = 30 }, "/scope-a")
    DB.save_weights({ path_fzf = 80 }, "/scope-b")

    local weights_a = DB.get_weights(defaults, "/scope-a")
    local weights_b = DB.get_weights(defaults, "/scope-b")

    assert.are.equal(30, weights_a.path_fzf)
    assert.are.equal(80, weights_b.path_fzf)
    assert.are.equal(defaults.recency, weights_a.recency)
    assert.are.equal(defaults.recency, weights_b.recency)
  end)

  it("detects scope from cwd markers when preparing confirm context", function()
    local root = tmp_root .. "/project"
    local nested = root .. "/src/app"
    vim.fn.mkdir(nested, "p")
    vim.fn.writefile({}, root .. "/.git")

    local unique_recency = 123
    local defaults = Config.get().weights
    local weights = vim.deepcopy(defaults)
    weights.recency = unique_recency
    DB.save_weights(weights, Util.normalize_path(root))

    local selected_path = nested .. "/main.lua"
    vim.fn.writefile({ "" }, selected_path)
    local picker = {
      list = {
        items = {
          {
            smart_open = {
              path = selected_path,
              is_current = false,
              scores = {},
            },
          },
        },
      },
      input = { filter = { cwd = nested } },
    }
    function picker:selected()
      return { { smart_open = { path = selected_path } } }
    end

    local ctx = Learning.before_confirm(picker)

    assert.are.equal(Util.normalize_path(root), ctx.scope)
    assert.are.equal(unique_recency, ctx.weights.recency)
  end)

  it("clamps learning adjustments per scope", function()
    local scope = Util.normalize_path(tmp_root .. "/clamp-project")
    vim.fn.mkdir(scope, "p")
    local selected = scope .. "/selected.lua"
    vim.fn.writefile({ "" }, selected)
    local other = scope .. "/other.lua"

    local config = Config.get()
    assert.are.equal(0.25, config.learning.max_delta)
    local weights = vim.deepcopy(config.weights)
    weights.path_fzf = 20
    weights.recency = 9

    DB.save_weights(weights, scope)

    local ctx = {
      config = config,
      scope = scope,
      weights = vim.deepcopy(weights),
      results = {
        {
          path = other,
          current = false,
          scores = {
            path_fzf = weights.path_fzf * 5,
            recency = weights.recency * 5,
          },
        },
        {
          path = selected,
          current = false,
          scores = {
            path_fzf = weights.path_fzf * 0.1,
            recency = weights.recency * 0.1,
          },
        },
      },
      selected_paths = { selected },
    }

    Learning.after_confirm(nil, ctx)

    local saved = DB.get_weights(config.weights, scope)
    assert.are.equal(weights.path_fzf - config.learning.max_delta, saved.path_fzf)
    assert.are.equal(weights.recency, saved.recency)
  end)
end)
