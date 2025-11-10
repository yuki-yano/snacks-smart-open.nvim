local M = {}

local defaults = {
  db = {
    path = vim.fn.stdpath('data') .. '/snacks/smart-open.sqlite3',
  },
  frecency = {
    half_life_days = 10,
    score_per_access = 100,
    max_lifetime_days = 365,
  },
  weights = {
    path_fzf = 140,
    path_fzy = 140,
    virtual_name_fzf = 131,
    virtual_name_fzy = 131,
    open = 3,
    alt = 4,
    proximity = 13,
    project = 10,
    frecency = 17,
    recency = 9,
  },
  learning = {
    adjustment_points = 0.6,
    promote_cap = 15,
    demote_cap = 1,
    min_weight = 1,
    max_weight = 40,
    max_delta = 0.25,
    protect = { 'frecency', 'recency', 'project', 'proximity', 'open', 'alt' },
    auto_record = true,
  },
  scoring = {
    proximity_bias = 6,
    recency_window = 7 * 24 * 60 * 60,
    recency_limit = 512,
    project_roots = {
      '.git',
      '.hg',
      '.svn',
      'package.json',
      'pyproject.toml',
    },
  },
  picker = {
    matcher = {
      cwd_bonus = true,
      frecency = true,
      history_bonus = true,
      filename_bonus = true,
      sort_empty = true,
    },
    sort = {
      fields = { 'score:desc', '#text', 'idx' },
    },
  },
  debug = {
    log = false,
  },
  apply_to = { 'smart', 'smart_open_files' },
}

local function expand_path(path)
  if vim.startswith(path, '~') then
    path = vim.fn.expand(path)
  end
  return vim.fs.normalize(path)
end

local function with_defaults(opts)
  opts = opts or {}
  local merged = vim.tbl_deep_extend('force', {}, defaults, opts)
  merged.db.path = expand_path(merged.db.path)
  local half_life = merged.frecency.half_life_days
  if half_life <= 0 then
    half_life = defaults.frecency.half_life_days
  end
  local seconds = half_life * 24 * 60 * 60
  merged.frecency.decay_constant = math.log(2) / seconds
  merged.frecency.expiration_window =
    math.max(seconds, (merged.frecency.max_lifetime_days or defaults.frecency.max_lifetime_days) * 24 * 60 * 60)
  return merged
end

function M.apply(opts)
  M._config = with_defaults(opts)
  return M._config
end

function M.get()
  if not M._config then
    return M.apply({})
  end
  return M._config
end

function M.defaults()
  return vim.deepcopy(defaults)
end

return M
