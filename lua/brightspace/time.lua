local M = {}

-- Convert Gregorian UTC dates without depending on the editor's time zone.
function M.parse(value)
  if type(value) == 'number' then return value end
  if type(value) ~= 'string' then return nil end
  local y, m, d, h, min, sec = value:match('^(%d%d%d%d)%-(%d%d)%-(%d%d)T(%d%d):(%d%d):(%d%d)')
  if not y then
    y, m, d = value:match('^(%d%d%d%d)%-(%d%d)%-(%d%d)$')
    h, min, sec = 0, 0, 0
  end
  if not y then return nil end
  y, m, d = tonumber(y), tonumber(m), tonumber(d)
  if m < 1 or m > 12 or d < 1 or d > 31 then return nil end
  y = y - (m <= 2 and 1 or 0)
  local era = math.floor(y / 400)
  local year = y - era * 400
  local month = m + (m > 2 and -3 or 9)
  local days = era * 146097 + year * 365 + math.floor(year / 4) - math.floor(year / 100)
    + math.floor((153 * month + 2) / 5) + d - 1 - 719468
  local result = days * 86400 + tonumber(h) * 3600 + tonumber(min) * 60 + tonumber(sec)
  local sign, oh, om = value:match('([+-])(%d%d):?(%d%d)$')
  if sign then result = result - (sign == '+' and 1 or -1) * (tonumber(oh) * 3600 + tonumber(om) * 60) end
  return result
end

function M.iso(epoch) return os.date('!%Y-%m-%dT%H:%M:%S.000Z', epoch) end
return M
