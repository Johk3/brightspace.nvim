local M = {}
local paths = require('brightspace.paths')
local seen, baselines = {}, {}
-- Decoded cache records by file path, so opening and refreshing decode each file once.
local records = {}
local function read(path)
  local f = io.open(path, 'rb')
  if not f then return nil end
  local data = f:read('*a'); f:close()
  local ok, value = pcall(vim.json.decode, data)
  if ok and type(value) == 'table' then return value end
end
local function write(path, value)
  local temp = path .. '.tmp'
  local fd = assert(vim.uv.fs_open(temp, 'w', 384))
  assert(vim.uv.fs_write(fd, vim.json.encode(value), 0))
  vim.uv.fs_close(fd)
  assert(vim.uv.fs_rename(temp, path))
end
local function name_path(name)
  return paths.cache()..'/'..name:gsub('[^%w_-]', '_')..'.json'
end
function M.cache_get(name)
  local path = name_path(name)
  local record = records[path] or read(path)
  if record and type(record.saved)=='number' then
    records[path] = record
    return record.data, math.max(0, os.time()-record.saved)
  end
  return nil, math.huge
end
function M.cache_put(name, data)
  local path, record = name_path(name), {saved=os.time(),data=data}
  write(path, record)
  records[path] = record
end
function M.seen_load()
  local value = read(paths.data()..'/seen.json') or {}
  seen = type(value.seen)=='table' and value.seen or {}
  baselines = type(value.baselines)=='table' and value.baselines or {}
end
local function save() write(paths.data()..'/seen.json', {seen=seen,baselines=baselines}) end
function M.is_new(item) return item.kind ~= 'module' and seen[item.key] ~= (item.modified or 0) end
function M.mark_seen(item) seen[item.key] = item.modified or 0; save() end
function M.mark_all_seen(items)
  for _, item in ipairs(items) do seen[item.key] = item.modified or 0 end
  save()
end
function M.baseline(course_id, items, now)
  local key = tostring(course_id)
  if baselines[key] then return end
  for _, item in ipairs(items) do
    if type(item.modified) ~= 'number' or item.modified < now-7*86400 then seen[item.key] = item.modified or 0 end
  end
  baselines[key] = true
  save()
end
function M.clear_cache()
  records = {}
  for _, file in ipairs(vim.fn.glob(paths.cache()..'/*.json', false, true)) do vim.fn.delete(file) end
  vim.fn.delete(paths.cache()..'/files', 'rf')
end
return M
