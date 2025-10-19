local Config = require('snacks-smart-open.config')
local DB = require('snacks-smart-open.db')
local State = require('snacks-smart-open.state')
local Util = require('snacks-smart-open.util')

local picker_util = require('snacks.picker.util')

local CONTEXT_KEY = 'snacks_smart_open_ctx'

local function get_record(context, path)
  local cache = context.records
  if cache[path] ~= nil then
    return cache[path] or nil
  end
  local record = DB.get_file(path)
  cache[path] = record or false
  return record
end

local function build_recent_rank(open_list, db_rows, norm)
  local rank = 0
  local map = {}
  for _, entry in ipairs(open_list) do
    if entry.path and not map[entry.path] then
      rank = rank + 1
      map[entry.path] = rank
    end
  end
  for _, row in ipairs(db_rows) do
    local path = norm(row.path)
    if path and not map[path] then
      rank = rank + 1
      map[path] = rank
    end
  end
  return map, rank
end

local function ensure_context(ctx)
  local context = ctx.meta[CONTEXT_KEY]
  if context then
    return context
  end

  local config = Config.get()
  DB.ensure(config)
  local now = os.time()

  local cache = {}
  local function norm(path)
    if path == nil then
      return nil
    end
    if cache[path] ~= nil then
      return cache[path]
    end
    local normalized = Util.normalize_path(path)
    cache[path] = normalized
    return normalized
  end

  local state = State.get() or {}
  local current_path = state.current_path
  local alternate_path = state.alternate_path
  local open_map = state.open_map or {}
  local open_list = state.open_list or {}

  local cwd = norm((ctx.filter and ctx.filter.cwd) or vim.loop.cwd() or vim.fn.getcwd())
  if not current_path and not vim.in_fast_event() then
    current_path = norm(vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf()))
  end
  if not alternate_path and not vim.in_fast_event() then
    local alt_buf = vim.fn.bufnr('#')
    if alt_buf > 0 then
      alternate_path = norm(vim.api.nvim_buf_get_name(alt_buf))
    end
  end

  local weights = DB.get_weights(config.weights)
  local max_flat = DB.max_flat_score(now)
  if not max_flat or max_flat <= 0 then
    max_flat = 1
  end

  local recent_rows = DB.get_recent(config.scoring.recency_limit or 512)
  local recent_rank, rank = build_recent_rank(open_list, recent_rows, norm)

  local oldfiles = vim.v.oldfiles or {}
  for _, file in ipairs(oldfiles) do
    local path = norm(file)
    if path and not recent_rank[path] then
      rank = rank + 1
      recent_rank[path] = rank
    end
  end

  context = {
    now = now,
    cwd = cwd,
    current_path = current_path,
    alternate_path = alternate_path,
    open_map = open_map,
    weights = weights,
    max_flat = max_flat,
    recent_rank = recent_rank,
    records = {},
    normalize = norm,
    seen = {},
  }
  ctx.meta[CONTEXT_KEY] = context
  return context
end

local function compute_scores(context, path)
  local raw = {
    open = 0,
    alt = 0,
    proximity = 0,
    project = 0,
    frecency = 0,
    recency = 0,
  }

  local open_entry = context.open_map[path]
  if open_entry then
    raw.open = 1
  end
  if context.alternate_path and path == context.alternate_path then
    raw.alt = 1
  end

  local record = get_record(context, path)
  if record then
    local flat_score = (record.expiration or 0) - context.now
    if flat_score > 0 and context.max_flat > 0 then
      raw.frecency = math.min(1, flat_score / context.max_flat)
    end
  end

  local rank = context.recent_rank[path]
  if rank and rank > 0 then
    raw.recency = 8 / (rank + 7)
  end

  local anchor = context.current_path or context.cwd
  raw.proximity = Util.normalize_proximity(Util.calculate_proximity(anchor, path))

  if context.cwd and path:sub(1, #context.cwd) == context.cwd then
    raw.project = 1
  end

  local weighted = {}
  local base_score = 0
  for key, value in pairs(raw) do
    local contribution = (value or 0) * (context.weights[key] or 0)
    weighted[key] = contribution
    base_score = base_score + contribution
  end

  return weighted, raw, base_score, record, rank, open_entry
end

local function adjust_score_add(item, base_score)
  local previous = item.smart_open and item.smart_open.base_score or 0
  local current = item.score_add or 0
  if previous ~= 0 and item.score_add ~= nil then
    current = current - previous
  end
  local updated = current + base_score
  if updated ~= 0 then
    item.score_add = updated
  else
    item.score_add = nil
  end
end

local M = {}

function M.apply(item, ctx)
  local context = ensure_context(ctx)
  local path = picker_util.path(item) or item.file or item.text
  path = context.normalize(path)
  if not path then
    return item
  end
  if context.seen[path] then
    return false
  end
  context.seen[path] = true

  local smart_state = item.smart_open or {}
  local is_current = context.current_path and path == context.current_path or false
  smart_state.path = path
  smart_state.is_current = is_current

  local weighted, raw, base_score, record, rank, open_entry
  if is_current then
    weighted = {}
    raw = {
      open = 0,
      alt = 0,
      proximity = 0,
      project = 0,
      frecency = 0,
      recency = 0,
    }
    base_score = 0
    record = get_record(context, path)
    rank = context.recent_rank[path]
    open_entry = context.open_map[path]
  else
    weighted, raw, base_score, record, rank, open_entry = compute_scores(context, path)
  end

  smart_state.base_score = base_score
  smart_state.scores = weighted
  smart_state.features = raw
  smart_state.record = record
  smart_state.recent_rank = rank
  smart_state.timestamp = context.now
  smart_state.weights = context.weights
  smart_state.open = open_entry

  item.smart_open = smart_state

  adjust_score_add(item, base_score)

  if open_entry and open_entry.bufnr and not item.buf then
    item.buf = open_entry.bufnr
  end
  if open_entry and open_entry.modified then
    item.modified = true
  end
  if raw and raw.frecency and raw.frecency > 0 and not item.frecency then
    item.frecency = raw.frecency
  end

  return item
end

return M
