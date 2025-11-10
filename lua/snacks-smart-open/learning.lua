local Config = require('snacks-smart-open.config')
local DB = require('snacks-smart-open.db')
local State = require('snacks-smart-open.state')
local Util = require('snacks-smart-open.util')

local uv = vim.uv or vim.loop

local picker_util = require('snacks.picker.util')

local M = {}

local function current_score(record, now, decay)
  local time_left = (record.expiration or 0) - now
  if time_left <= 0 then
    return 1
  end
  return math.exp(decay * time_left)
end

local function compute_expiration(record, now, cfg)
  local decay = cfg.frecency.decay_constant
  local score = current_score(record, now, decay) + cfg.frecency.score_per_access
  local lifetime = math.log(score) / decay
  local expiration = math.floor(now + lifetime)
  return expiration, score
end

local function update_usage(path, config, opts)
  opts = opts or {}
  local now = opts.now or os.time()
  if not path or path == '' then
    return
  end

  local stat = vim.loop.fs_stat(path)
  if not stat or stat.type ~= 'file' then
    return
  end

  local record = DB.get_file(path)
    or {
      expiration = now - 1,
      last_open = now,
      frequency = 0,
      frecency = 0,
      score = 0,
      created_at = now,
    }
  local expiration, score = compute_expiration(record, now, config)
  local flat_score = math.max(0, expiration - now)

  DB.update_file({
    path = path,
    last_open = now,
    frequency = opts.frequency or 1,
    frecency = score,
    score = flat_score,
    expiration = expiration,
    created_at = record.created_at ~= 0 and record.created_at or now,
    updated_at = now,
  })
  DB.delete_expired(now)
end

local function capture_results(picker, config)
  local limit = (config.learning.promote_cap or 15) + (config.learning.demote_cap or 1) + 1
  local ret = {}
  local items = picker and picker.list and picker.list.items or {}
  for _, item in ipairs(items) do
    if item.smart_open and item.smart_open.path then
      ret[#ret + 1] = {
        path = item.smart_open.path,
        current = item.smart_open.is_current,
        scores = vim.deepcopy(item.smart_open.scores or {}),
      }
      if #ret >= limit then
        break
      end
    end
  end
  return ret
end

local function select_entry(results, path)
  for _, entry in ipairs(results) do
    if entry.path == path then
      return entry
    end
  end
end

local function is_protected(key, cfg)
  local protect = cfg and cfg.protect or nil
  if not protect then
    return false
  end
  for _, name in ipairs(protect) do
    if name == key then
      return true
    end
  end
  return false
end

local function adjust_weights(original, weights, success_entry, miss_entry, factor, cfg)
  if not success_entry or not miss_entry then
    return
  end
  if success_entry.current or miss_entry.current then
    return
  end

  local function unweight(key, score)
    local w = original[key]
    if not w or w == 0 then
      return nil
    end
    return score / w
  end

  local to_deduct, to_add = 0, 0
  for key, weight in pairs(original) do
    if weight and weight ~= 0 then
      local hit = unweight(key, success_entry.scores[key] or 0)
      local miss = unweight(key, miss_entry.scores[key] or 0)
      if hit and miss then
        if miss > hit then
          to_deduct = to_deduct + (miss - hit)
        elseif hit > miss then
          to_add = to_add + (hit - miss)
        end
      end
    end
  end

  if to_deduct == 0 and to_add == 0 then
    return
  end

  local min_weight = cfg.min_weight or 1
  local max_weight = cfg.max_weight or math.huge
  local max_delta = cfg.max_delta or 0

  local function apply_delta(key, weight, direction, delta)
    if direction == 'down' and is_protected(key, cfg) then
      return
    end
    if max_delta > 0 then
      delta = math.min(delta, max_delta)
    end
    if delta <= 0 then
      return
    end
    local current = weights[key] or weight
    if direction == 'down' then
      weights[key] = math.max(min_weight, current - delta)
    else
      weights[key] = math.min(max_weight, current + delta)
    end
  end

  for key, weight in pairs(original) do
    if weight and weight ~= 0 then
      local hit = unweight(key, success_entry.scores[key] or 0)
      local miss = unweight(key, miss_entry.scores[key] or 0)
      if hit and miss then
        if miss > hit and to_deduct > 0 then
          local delta = cfg.adjustment_points * factor * ((miss - hit) / to_deduct)
          apply_delta(key, weight, 'down', delta)
        elseif hit > miss and to_add > 0 then
          local delta = cfg.adjustment_points * factor * ((hit - miss) / to_add)
          apply_delta(key, weight, 'up', delta)
        end
      end
    end
  end
end

local function revise_weights(original_weights, results, selected_path, cfg)
  if not selected_path or selected_path == '' then
    return original_weights
  end
  local selected = select_entry(results, selected_path)
  if not selected then
    return original_weights
  end
  local new_weights = vim.deepcopy(original_weights)
  local greater, lesser = {}, {}
  local found = false
  for _, entry in ipairs(results) do
    if entry.path == selected_path then
      found = true
    elseif not found then
      greater[#greater + 1] = entry
      if #greater >= (cfg.promote_cap or 15) then
        break
      end
    else
      lesser[#lesser + 1] = entry
      if #lesser >= (cfg.demote_cap or 1) then
        break
      end
    end
  end

  if #greater + #lesser == 0 then
    return original_weights
  end

  for _, entry in ipairs(greater) do
    adjust_weights(original_weights, new_weights, selected, entry, 1 / #greater, cfg)
  end
  for _, entry in ipairs(lesser) do
    adjust_weights(original_weights, new_weights, selected, entry, 0.1 / #lesser, cfg)
  end

  return new_weights
end

local function record_selected(paths, config)
  if not paths then
    return
  end
  for _, path in ipairs(paths) do
    update_usage(path, config)
  end
end

local function resolve_scope(picker, config)
  config = config or Config.get()
  local filter = picker and picker.input and picker.input.filter
  local filter_cwd = filter and filter.cwd or nil
  local state = State.get() or {}
  local base_path = filter_cwd or state.current_path or state.cwd or uv.cwd() or vim.fn.getcwd()
  local scope = Util.resolve_scope({
    path = base_path,
    cwd = state.cwd,
    markers = config.scoring and config.scoring.project_roots or {},
  })
  return scope or ''
end

function M.bootstrap(config)
  config = config or Config.get()
  DB.ensure(config)
  DB.ensure_weights(config.weights)
  State.update()

  local state_group = vim.api.nvim_create_augroup('snacks_smart_open_state', { clear = true })
  vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWinEnter', 'BufWritePost', 'BufDelete' }, {
    group = state_group,
    callback = function()
      State.update()
    end,
  })
  if config.learning.auto_record == false then
    return
  end
  if M._autocmd then
    return
  end
  local group = vim.api.nvim_create_augroup('snacks_smart_open_usage', { clear = true })
  vim.api.nvim_create_autocmd({ 'BufWinEnter', 'BufWritePost' }, {
    group = group,
    callback = function(args)
      local buf = args.buf
      if not buf or not vim.api.nvim_buf_is_valid(buf) then
        return
      end
      local name = vim.api.nvim_buf_get_name(buf)
      if name == '' or vim.bo[buf].buftype ~= '' then
        return
      end
      if vim.b[buf].snacks_smart_open_registered then
        return
      end
      vim.b[buf].snacks_smart_open_registered = true
      update_usage(name, config)
      State.update()
    end,
  })
  M._autocmd = group
end

function M.refresh(config)
  config = config or Config.get()
  DB.ensure(config)
  DB.ensure_weights(config.weights)
  State.update()
end

function M.before_confirm(picker)
  local config = Config.get()
  local scope = resolve_scope(picker, config)
  local selected = picker:selected({ fallback = true })
  local selected_paths = {}
  for _, item in ipairs(selected) do
    local path = item.smart_open and item.smart_open.path or picker_util.path(item)
    if path then
      selected_paths[#selected_paths + 1] = path
    end
  end

  return {
    config = config,
    scope = scope,
    weights = DB.get_weights(config.weights, scope),
    results = capture_results(picker, config),
    selected_paths = selected_paths,
  }
end

function M.after_confirm(_, ctx, _result)
  if not ctx then
    return
  end
  local config = ctx.config or Config.get()
  record_selected(ctx.selected_paths, config)
  if ctx.results and ctx.weights and ctx.selected_paths and ctx.selected_paths[1] then
    local updated = revise_weights(ctx.weights, ctx.results, ctx.selected_paths[1], config.learning)
    DB.save_weights(updated, ctx.scope)
  end
end

function M.on_error(_, err)
  vim.schedule(function()
    vim.notify(
      ('snacks-smart-open: error while running confirm hook: %s'):format(err),
      vim.log.levels.ERROR,
      { title = 'snacks-smart-open' }
    )
  end)
end

return M
