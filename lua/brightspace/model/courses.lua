local time = require('brightspace.time')
local M = {}
local function quarter(name, start)
  local year, suffix = name:match('(20%d%d)/(%d%d)')
  local q = name:match('[Qq]([1-4])')
  if year and q then return year .. q, year .. '/' .. suffix .. ' Q' .. q end
  if start then
    local date = os.date('!*t', start)
    year = date.year - (date.month < 9 and 1 or 0)
    q = date.month >= 9 and (date.month >= 11 and 2 or 1)
      or (date.month < 2 and 2 or (date.month < 5 and 3 or 4))
    return tostring(year)..q, ('%d/%02d Q%d'):format(year, (year+1)%100, q)
  end
  return '0', 'Other'
end
function M.normalize(raw, now)
  local list, latest = {}, '0'
  local current_key = quarter('', now)
  for _, row in ipairs(raw or {}) do
    local unit, access = row.OrgUnit or {}, row.Access or {}
    if unit.Type and tonumber(unit.Type.Id) == 3 and access.CanAccess ~= false then
      local start, finish = time.parse(access.StartDate), time.parse(access.EndDate)
      local key, label = quarter((unit.Name or '') .. ' ' .. (unit.Code or ''), start)
      local current = access.IsActive ~= false and (not start or start <= now) and (not finish or now <= finish)
      if key > latest and key <= current_key then latest = key end
      list[#list+1] = {id=unit.Id, code=unit.Code or '', name=unit.Name or 'Untitled course',
        quarter_key=key, quarter_label=label, start=start, finish=finish,
        current=current and (start ~= nil or finish ~= nil), active=access.IsActive ~= false}
    end
  end
  for _, course in ipairs(list) do
    if not course.start and not course.finish then
      course.current = course.active and course.quarter_key == latest
    end
  end
  return list
end
function M.current(list)
  return vim.tbl_filter(function(c) return c.current end, list)
end
function M.group(list)
  local by_key, groups = {}, {}
  for _, course in ipairs(list) do
    local key = course.quarter_key
    if not by_key[key] then
      by_key[key] = {key=key,label=course.quarter_label,courses={}}
      groups[#groups+1] = by_key[key]
    end
    table.insert(by_key[key].courses, course)
  end
  table.sort(groups, function(a,b) return a.key > b.key end)
  return groups
end
return M
