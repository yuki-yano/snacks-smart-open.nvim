local MiniTest = require("mini.test")
local Config = require("snacks-smart-open.config")
local DB = require("snacks-smart-open.db")
local Learning = require("snacks-smart-open.learning")
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
      T.tmp_root = tmpdir()
      local db_path = T.tmp_root .. "/smart-open.sqlite3"
      DB.close()
      Config.apply({ db = { path = db_path } })
    end,
    post_case = function()
      DB.close()
      if T.tmp_root then
        vim.fn.delete(T.tmp_root, "rf")
      end
    end,
  },
})
local eq = MiniTest.expect.equality

T["keeps weight rows isolated per scope"] = function()
  local defaults = Config.get().weights
  DB.save_weights({ path_fzf = 30 }, "/scope-a")
  DB.save_weights({ path_fzf = 80 }, "/scope-b")

  local weights_a = DB.get_weights(defaults, "/scope-a")
  local weights_b = DB.get_weights(defaults, "/scope-b")

  eq(weights_a.path_fzf, 30)
  eq(weights_b.path_fzf, 80)
  eq(weights_a.recency, defaults.recency)
  eq(weights_b.recency, defaults.recency)
end

T["detects scope from cwd markers when preparing confirm context"] = function()
  local root = T.tmp_root .. "/project"
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

  eq(ctx.scope, Util.normalize_path(root))
  eq(ctx.weights.recency, unique_recency)
end

T["clamps learning adjustments per scope"] = function()
  local scope = Util.normalize_path(T.tmp_root .. "/clamp-project")
  vim.fn.mkdir(scope, "p")
  local selected = scope .. "/selected.lua"
  vim.fn.writefile({ "" }, selected)
  local other = scope .. "/other.lua"

  local config = Config.get()
  eq(config.learning.max_delta, 0.25)
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
  eq(saved.path_fzf, weights.path_fzf - config.learning.max_delta)
  eq(saved.recency, weights.recency)
end

return T
