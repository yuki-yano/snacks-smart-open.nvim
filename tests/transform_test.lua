local MiniTest = require("mini.test")
local Config = require("snacks-smart-open.config")
local DB = require("snacks-smart-open.db")
local State = require("snacks-smart-open.state")
local Transform = require("snacks-smart-open.transform")
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
      Config.apply({ db = { path = db_path } })

      T.original_db = {
        ensure = DB.ensure,
        get_file = DB.get_file,
        get_recent = DB.get_recent,
        get_weights = DB.get_weights,
        max_flat_score = DB.max_flat_score,
      }
      T.original_state_get = State.get

      DB.ensure = function() end
      DB.get_file = function()
        return nil
      end
      DB.get_recent = function()
        return {}
      end
      DB.get_weights = function(weights)
        return vim.deepcopy(weights)
      end
      DB.max_flat_score = function()
        return 1
      end
    end,
    post_case = function()
      DB.ensure = T.original_db.ensure
      DB.get_file = T.original_db.get_file
      DB.get_recent = T.original_db.get_recent
      DB.get_weights = T.original_db.get_weights
      DB.max_flat_score = T.original_db.max_flat_score
      State.get = T.original_state_get
      DB.close()
      if T.tmp_root then
        vim.fn.delete(T.tmp_root, "rf")
      end
    end,
  },
})
local eq = MiniTest.expect.equality

T["does not treat sibling directories as the same project"] = function()
  local project_root = T.tmp_root .. "/proj"
  local sibling_root = T.tmp_root .. "/project"
  local project_file = project_root .. "/src/current.lua"
  local sibling_file = sibling_root .. "/notes.txt"

  vim.fn.mkdir(vim.fn.fnamemodify(project_file, ":h"), "p")
  vim.fn.mkdir(vim.fn.fnamemodify(sibling_file, ":h"), "p")
  vim.fn.writefile({ "return true" }, project_file)
  vim.fn.writefile({ "sibling" }, sibling_file)

  State.get = function()
    return {
      cwd = Util.normalize_path(project_root),
      current_path = Util.normalize_path(project_file),
      open_map = {},
      open_list = {},
    }
  end

  local transformed = Transform.apply({
    file = sibling_file,
  }, {
    filter = { cwd = project_root },
    meta = {},
  })

  eq(transformed.smart_open.features.project, 0)
end

T["respects recency_window when ranking database rows"] = function()
  local file = T.tmp_root .. "/recent.lua"
  vim.fn.writefile({ "return true" }, file)
  local normalized = Util.normalize_path(file)

  Config.apply({
    db = { path = T.tmp_root .. "/smart-open.sqlite3" },
    scoring = { recency_window = 1 },
  })

  DB.get_recent = function()
    return {
      { path = normalized, last_open = os.time() - 60 },
    }
  end
  State.get = function()
    return {
      cwd = Util.normalize_path(T.tmp_root),
      open_map = {},
      open_list = {},
    }
  end

  local transformed = Transform.apply({
    file = file,
  }, {
    filter = { cwd = T.tmp_root },
    meta = {},
  })

  eq(transformed.smart_open.features.recency, 0)
end

T["respects proximity_bias when scoring nearby files"] = function()
  local project_root = T.tmp_root .. "/proj"
  local current_file = project_root .. "/src/current.lua"
  local nearby_file = project_root .. "/src/nested/other.lua"

  vim.fn.mkdir(vim.fn.fnamemodify(nearby_file, ":h"), "p")
  vim.fn.writefile({ "return true" }, current_file)
  vim.fn.writefile({ "return false" }, nearby_file)

  DB.get_recent = function()
    return {}
  end
  State.get = function()
    return {
      cwd = Util.normalize_path(project_root),
      current_path = Util.normalize_path(current_file),
      open_map = {},
      open_list = {},
    }
  end

  Config.apply({
    db = { path = T.tmp_root .. "/smart-open.sqlite3" },
    scoring = { proximity_bias = 2 },
  })
  local low_bias = Transform.apply({
    file = nearby_file,
  }, {
    filter = { cwd = project_root },
    meta = {},
  })

  Config.apply({
    db = { path = T.tmp_root .. "/smart-open.sqlite3" },
    scoring = { proximity_bias = 20 },
  })
  local high_bias = Transform.apply({
    file = nearby_file,
  }, {
    filter = { cwd = project_root },
    meta = {},
  })

  assert(low_bias.smart_open.features.proximity > high_bias.smart_open.features.proximity)
end

return T
