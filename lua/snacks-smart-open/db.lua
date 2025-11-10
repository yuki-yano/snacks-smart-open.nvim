local Config = require('snacks-smart-open.config')

local sqlite = require('snacks.picker.util.db')

local M = {}

local SCHEMA_VERSION = 2
local connection ---@type snacks.picker.db?
local connection_path ---@type string?
local statements = {} ---@type table<string, snacks.picker.db.Query>

local function normalize_scope(scope)
  if type(scope) ~= 'string' or scope == '' then
    return ''
  end
  return scope
end

local function ensure_parent(path)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ':h'), 'p')
end

local function close_statements()
  for name, stmt in pairs(statements) do
    if stmt and stmt.close then
      pcall(stmt.close, stmt)
    end
    statements[name] = nil
  end
end

function M.close()
  if connection then
    close_statements()
    pcall(connection.close, connection)
    connection = nil
    connection_path = nil
  end
end

local function get_user_version(db)
  local stmt = db:prepare('PRAGMA user_version;')
  local version = 0
  if stmt:exec() == 100 then
    version = stmt:col('number')
  end
  stmt:close()
  return version
end

local function migrate_to_v1(db)
  db:exec([[
    CREATE TABLE IF NOT EXISTS snacks_smart_open_files (
      path TEXT PRIMARY KEY,
      dir TEXT NOT NULL,
      last_open INTEGER NOT NULL DEFAULT 0,
      frequency INTEGER NOT NULL DEFAULT 0,
      frecency REAL NOT NULL DEFAULT 0,
      score REAL NOT NULL DEFAULT 0,
      expiration INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL DEFAULT 0,
      updated_at INTEGER NOT NULL DEFAULT 0
    );
  ]])
  db:exec([[CREATE INDEX IF NOT EXISTS idx_snacks_smart_open_files_dir ON snacks_smart_open_files(dir);]])
  db:exec([[CREATE INDEX IF NOT EXISTS idx_snacks_smart_open_files_last_open ON snacks_smart_open_files(last_open);]])
  db:exec([[CREATE INDEX IF NOT EXISTS idx_snacks_smart_open_files_expiration ON snacks_smart_open_files(expiration);]])
  db:exec([[
    CREATE TABLE IF NOT EXISTS snacks_smart_open_weights (
      key TEXT PRIMARY KEY,
      value REAL NOT NULL
    );
  ]])
  db:exec([[
    CREATE TABLE IF NOT EXISTS snacks_smart_open_meta (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    );
  ]])
end

local function migrate_to_v2(db)
  close_statements()
  db:exec('DROP TABLE IF EXISTS snacks_smart_open_weights;')
  db:exec([[
    CREATE TABLE IF NOT EXISTS snacks_smart_open_weights (
      scope TEXT NOT NULL,
      key TEXT NOT NULL,
      value REAL NOT NULL,
      PRIMARY KEY(scope, key)
    );
  ]])
  db:exec([[CREATE INDEX IF NOT EXISTS idx_snacks_smart_open_weights_scope ON snacks_smart_open_weights(scope);]])
end

local function apply_schema(db)
  local current_version = get_user_version(db)
  if current_version < 1 then
    migrate_to_v1(db)
    current_version = 1
  end
  if current_version < 2 then
    migrate_to_v2(db)
    current_version = 2
  end
  db:exec(('PRAGMA user_version = %d;'):format(SCHEMA_VERSION))
end

local function connect(cfg)
  cfg = cfg or Config.get()
  if connection and connection_path == cfg.db.path then
    return connection
  end
  M.close()
  ensure_parent(cfg.db.path)
  local ok, db = pcall(sqlite.new, cfg.db.path, 'number')
  if not ok then
    vim.notify(
      ('snacks-smart-open: failed to open SQLite database: %s'):format(db),
      vim.log.levels.ERROR,
      { title = 'snacks-smart-open' }
    )
    return
  end
  connection = db
  connection_path = cfg.db.path
  apply_schema(connection)
  return connection
end

function M.get(cfg)
  return connect(cfg)
end

function M.path()
  local cfg = Config.get()
  return cfg.db.path
end

function M.ensure(cfg)
  return connect(cfg)
end

function M.prepare(name, sql)
  if statements[name] then
    return statements[name]
  end
  local db = connect()
  if not db then
    return
  end
  local stmt = db:prepare(sql)
  statements[name] = stmt
  return stmt
end

function M.exec(sql)
  local db = connect()
  if not db then
    return
  end
  db:exec(sql)
end

function M.ensure_weights(weights, scope)
  local db = connect()
  if not db then
    return
  end
  local list = weights or {}
  local scoped = normalize_scope(scope)
  local stmt = M.prepare(
    'ensure_weight',
    'INSERT OR IGNORE INTO snacks_smart_open_weights (scope, key, value) VALUES (?, ?, ?);'
  )
  if not stmt then
    return
  end
  for key, value in pairs(list) do
    stmt:exec({ scoped, key, value })
  end
  stmt:reset()
end

function M.get_weights(defaults, scope)
  local db = connect()
  local ret = vim.deepcopy(defaults or {})
  if not db then
    return ret
  end
  local scoped = normalize_scope(scope)
  M.ensure_weights(defaults or {}, scoped)
  local stmt = M.prepare('select_weights', 'SELECT key, value FROM snacks_smart_open_weights WHERE scope = ?;')
  if not stmt then
    return ret
  end
  local code = stmt:exec({ scoped })
  while code == 100 do
    local key = stmt:col('string', 0)
    local value = stmt:col('number', 1)
    if key then
      ret[key] = value
    end
    code = stmt:step()
  end
  stmt:reset()
  return ret
end

function M.get_file(path)
  local db = connect()
  if not db then
    return
  end
  local stmt = M.prepare(
    'select_file',
    [[
      SELECT
        path,
        last_open,
        frequency,
        frecency,
        score,
        expiration,
        created_at,
        updated_at
      FROM snacks_smart_open_files
      WHERE path = ?;
    ]]
  )
  if not stmt then
    return
  end
  local record
  if stmt:exec({ path }) == 100 then
    record = {
      path = stmt:col('string', 0),
      last_open = stmt:col('number', 1) or 0,
      frequency = stmt:col('number', 2) or 0,
      frecency = stmt:col('number', 3) or 0,
      score = stmt:col('number', 4) or 0,
      expiration = stmt:col('number', 5) or 0,
      created_at = stmt:col('number', 6) or 0,
      updated_at = stmt:col('number', 7) or 0,
    }
  end
  stmt:reset()
  return record
end

function M.max_flat_score(now)
  local db = connect()
  if not db then
    return 0
  end
  local stmt = M.prepare('max_expiration', 'SELECT MAX(expiration) FROM snacks_smart_open_files;')
  if not stmt then
    return 0
  end
  local max_flat = 0
  if stmt:exec() == 100 then
    local max_expiration = stmt:col('number', 0)
    if max_expiration and now then
      max_flat = math.max(0, max_expiration - now)
    end
  end
  stmt:reset()
  return max_flat
end

function M.get_recent(limit)
  local db = connect()
  if not db then
    return {}
  end
  limit = limit or 512
  local stmt =
    M.prepare('recent_files', 'SELECT path, last_open FROM snacks_smart_open_files ORDER BY last_open DESC LIMIT ?;')
  if not stmt then
    return {}
  end
  local results = {}
  local code = stmt:exec({ limit })
  while code == 100 do
    results[#results + 1] = {
      path = stmt:col('string', 0),
      last_open = stmt:col('number', 1) or 0,
    }
    code = stmt:step()
  end
  stmt:reset()
  return results
end

function M.save_weights(weights, scope)
  local db = connect()
  if not db then
    return
  end
  local scoped = normalize_scope(scope)
  local stmt = M.prepare(
    'save_weight',
    [[
      INSERT INTO snacks_smart_open_weights (scope, key, value)
      VALUES (?, ?, ?)
      ON CONFLICT(scope, key) DO UPDATE SET value = excluded.value;
    ]]
  )
  if not stmt then
    return
  end
  for key, value in pairs(weights or {}) do
    stmt:exec({ scoped, key, value })
  end
  stmt:reset()
end

function M.update_file(opts)
  local db = connect()
  if not db then
    return
  end
  opts = opts or {}
  local stmt = M.prepare(
    'upsert_file',
    [[
      INSERT INTO snacks_smart_open_files
        (path, dir, last_open, frequency, frecency, score, expiration, created_at, updated_at)
      VALUES
        (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(path) DO UPDATE SET
        dir = excluded.dir,
        last_open = excluded.last_open,
        frequency = snacks_smart_open_files.frequency + excluded.frequency,
        frecency = excluded.frecency,
        score = excluded.score,
        expiration = excluded.expiration,
        updated_at = excluded.updated_at;
    ]]
  )
  if not stmt then
    return
  end
  local path = opts.path
  if not path then
    return
  end
  local dir = opts.dir or vim.fn.fnamemodify(path, ':h')
  local last_open = opts.last_open or os.time()
  local frequency = opts.frequency or 1
  local frecency = opts.frecency or 0
  local score = opts.score or 0
  local expiration = opts.expiration or last_open
  local created_at = opts.created_at or last_open
  local updated_at = opts.updated_at or last_open
  stmt:exec({ path, dir, last_open, frequency, frecency, score, expiration, created_at, updated_at })
  stmt:reset()
end

function M.delete_expired(now)
  local db = connect()
  if not db then
    return
  end
  local stmt = M.prepare('delete_expired', 'DELETE FROM snacks_smart_open_files WHERE expiration <= ?;')
  if not stmt then
    return
  end
  stmt:exec({ now })
  stmt:reset()
end

vim.api.nvim_create_autocmd('VimLeavePre', {
  group = vim.api.nvim_create_augroup('snacks_smart_open_db', { clear = true }),
  callback = function()
    M.close()
  end,
})

return M
