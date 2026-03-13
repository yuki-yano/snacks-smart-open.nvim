local MiniTest = require("mini.test")
local Config = require("snacks-smart-open.config")

local T
T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      T.original_modules = {}
      for _, name in ipairs({
        "snacks-smart-open.runtime",
        "snacks-smart-open.init",
        "snacks-smart-open.learning",
        "snacks-smart-open.transform",
        "snacks.picker.core.actions",
        "snacks.picker.transform",
      }) do
        T.original_modules[name] = package.loaded[name]
        package.loaded[name] = nil
      end

      T.original_snacks = rawget(_G, "Snacks")
      T.original_notify = vim.notify

      package.loaded["snacks.picker.core.actions"] = {
        resolve = function(_, _, _)
          return {
            action = function()
              return true
            end,
          }
        end,
      }
      package.loaded["snacks.picker.transform"] = {}

      package.loaded["snacks-smart-open.learning"] = {
        bootstrap = function() end,
        refresh = function() end,
        before_confirm = function()
          return {}
        end,
        after_confirm = function() end,
        on_error = function() end,
      }
      package.loaded["snacks-smart-open.transform"] = {
        apply = function(item)
          return item
        end,
      }

      T.snacks = {
        config = {
          picker = {
            sources = {
              smart = {
                transform = function(item)
                  item.smart_original = true
                  return item
                end,
                actions = {
                  confirm = function()
                    return "smart"
                  end,
                },
              },
              smart_open_files = {
                transform = function(item)
                  item.files_original = true
                  return item
                end,
                actions = {
                  confirm = function()
                    return "smart_open_files"
                  end,
                },
              },
            },
          },
        },
      }
      _G.Snacks = T.snacks
      vim.notify = function() end
    end,
    post_case = function()
      for name, value in pairs(T.original_modules) do
        package.loaded[name] = value
      end
      _G.Snacks = T.original_snacks
      vim.notify = T.original_notify
    end,
  },
})

local eq = MiniTest.expect.equality

T["reconfigure keeps previous config values when applying a partial update"] = function()
  local plugin = require("snacks-smart-open")

  plugin.setup({
    db = { path = "/tmp/snacks-smart-open-runtime-test.sqlite3" },
    apply_to = { "smart_open_files" },
  })
  local updated = plugin.reconfigure({
    learning = { auto_record = false },
  })

  eq(updated.db.path, "/tmp/snacks-smart-open-runtime-test.sqlite3")
  eq(updated.apply_to, { "smart_open_files" })
  eq(updated.learning.auto_record, false)
end

T["reconfigure restores hooks for sources removed from apply_to"] = function()
  local Runtime = require("snacks-smart-open.runtime")

  local original_transform = T.snacks.config.picker.sources.smart.transform
  local original_confirm = T.snacks.config.picker.sources.smart.actions.confirm

  local initial = Config.apply({
    apply_to = { "smart", "smart_open_files" },
  })
  Runtime.setup(T.snacks, initial)

  local reduced = Config.apply({
    apply_to = { "smart_open_files" },
  })
  Runtime.reconfigure(reduced)

  eq(T.snacks.config.picker.sources.smart.transform, original_transform)
  eq(T.snacks.config.picker.sources.smart.actions.confirm, original_confirm)
end

return T
