local Config = require("snacks-smart-open.config")
local Runtime = require("snacks-smart-open.runtime")

local M = {}

local function notify(message, level)
  vim.schedule(function()
    vim.notify(message, level or vim.log.levels.WARN, { title = "snacks-smart-open" })
  end)
end

local function try_attach()
  local ok, snacks = pcall(require, "snacks")
  if not ok then
    snacks = rawget(_G, "Snacks")
  end
  if not snacks then
    return false
  end
  Runtime.setup(snacks, Config.get())
  return true
end

function M.setup(opts)
  local config = Config.apply(opts or {})
  if try_attach() then
    return config
  end
  vim.defer_fn(function()
    if Runtime.is_ready() then
      return
    end
    if not try_attach() then
      notify(
        "Unable to initialize snacks-smart-open because snacks.nvim is not loaded yet. Please load snacks.nvim and call setup() again."
      )
    end
  end, 100)
  return config
end

function M.reconfigure(opts)
  if opts then
    Config.apply(opts)
  end
  Runtime.reconfigure()
  return Config.get()
end

function M.config()
  return Config.get()
end

return M
