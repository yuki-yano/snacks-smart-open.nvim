local Config = require('snacks-smart-open.config')
local DB = require('snacks-smart-open.db')
local Learning = require('snacks-smart-open.learning')
local Transform = require('snacks-smart-open.transform')

local Actions = require('snacks.picker.core.actions')

local M = {}

local default_source_config = {
  smart_open_files = {
    finder = 'files',
    format = 'file',
    matcher = {
      cwd_bonus = true,
      frecency = true,
      sort_empty = true,
    },
    sort = {
      fields = { 'score:desc', '#text', 'idx' },
    },
  },
}

local state = {
  applied = false,
  snacks = nil,
  original_transform = {},
  original_confirm = {},
}

local function resolve_transform(spec)
  if type(spec) == 'function' then
    return spec
  elseif type(spec) == 'string' then
    local transforms = require('snacks.picker.transform')
    return transforms[spec]
  end
end

local function wrap_transform(source)
  local original = state.original_transform[source]
  local original_fn = resolve_transform(original)
  return function(item, ctx)
    if original_fn then
      local res = original_fn(item, ctx)
      if res == false then
        return false
      end
      if type(res) == 'table' then
        item = res
      end
    end
    local ret = Transform.apply(item, ctx)
    return ret == nil and item or ret
  end
end

local function call_original_confirm(source, picker, item, action)
  local opts = picker.opts
  opts.actions = opts.actions or {}
  local saved = opts.actions.confirm
  opts.actions.confirm = state.original_confirm[source]
  local ok, result = pcall(function()
    local resolved = Actions.resolve('confirm', picker, 'confirm')
    return resolved.action(picker, item, resolved or action)
  end)
  opts.actions.confirm = saved
  if not ok then
    error(result)
  end
  return result
end

local function wrap_confirm(source)
  return function(picker, item, action)
    local ctx = Learning.before_confirm(picker)
    local ok, result = pcall(call_original_confirm, source, picker, item, action)
    if ok then
      local after_ok, after_err = pcall(Learning.after_confirm, picker, ctx, result)
      if not after_ok then
        Learning.on_error(ctx, after_err)
      end
      return result
    end
    Learning.on_error(ctx, result)
    error(result)
  end
end

local function apply_picker_overrides(config)
  if not state.snacks then
    return
  end
  local snacks_config = state.snacks.config
  if not snacks_config then
    return
  end
  local picker_cfg = snacks_config.picker
  if not picker_cfg then
    snacks_config.picker = {}
    picker_cfg = snacks_config.picker
  end
  picker_cfg.sources = picker_cfg.sources or {}
  local sources = picker_cfg.sources
  local config_sources = config.apply_to or { 'smart', 'smart_open_files' }
  for _, source in ipairs(config_sources) do
    sources[source] = sources[source] or {}
    if default_source_config[source] then
      sources[source] = vim.tbl_deep_extend('force', {}, default_source_config[source], sources[source] or {})
    end
    local conf = sources[source]
    if not state.original_transform[source] then
      state.original_transform[source] = conf.transform
    end
    if not state.original_confirm[source] then
      state.original_confirm[source] = (conf.actions and conf.actions.confirm) or conf.confirm
    end

    conf.transform = wrap_transform(source)
    conf.actions = conf.actions or {}
    conf.actions.confirm = wrap_confirm(source)

    conf.matcher =
      vim.tbl_deep_extend('force', conf.matcher or {}, vim.deepcopy(config.picker and config.picker.matcher or {}))
    conf.sort = vim.tbl_deep_extend('force', conf.sort or {}, vim.deepcopy(config.picker and config.picker.sort or {}))
  end
end

function M.setup(snacks, config)
  state.snacks = snacks
  DB.ensure(config)
  Learning.bootstrap(config)
  if state.applied then
    apply_picker_overrides(config)
    return
  end
  apply_picker_overrides(config)
  state.applied = true
end

function M.reconfigure()
  if not state.snacks then
    return
  end
  local config = Config.get()
  DB.ensure(config)
  Learning.refresh(config)
  apply_picker_overrides(config)
end

function M.is_ready()
  return state.applied
end

return M
